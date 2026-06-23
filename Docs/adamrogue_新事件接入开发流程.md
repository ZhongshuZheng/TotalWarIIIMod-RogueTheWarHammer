---
name: 新事件接入开发流程
description: 在 AdamRogue 状态机中接入一个新的 Dilemma 事件的完整步骤手册，涵盖 DB、本地化、Lua 各层的接入点与注意事项
---

# 新事件接入开发流程

> **目标：** 给出一套可直接套用的步骤流程，接入一个新的 Dilemma 事件分支，不需要每次从头调研链路。  
> **前提：** 熟悉`adamrogue_代码框架介绍.md`中的整体结构。

---

## 一、核心概念速查

接入一个新事件需要联动三层结构，每层各司其职：

| 层级 | 作用 | 关键文件 |
|------|------|---------|
| **DB 层（TSV）** | 向游戏引擎注册 dilemma key 和选项 key | `db/dilemmas_tables/`、`db/cdir_events_dilemma_choice_details_tables/`、`db/cdir_events_dilemma_option_junctions_tables/` |
| **本地化层（Loc）** | 定义玩家看到的所有文字 | `text/db/adamrogue_mvp_CN.loc.tsv`、`text/db/en/adamrogue_mvp_EN.loc.tsv` |
| **Lua 层** | 控制何时触发、payload 内容是什么、选择后做什么 | `script/campaign/mod/adamrogue_mvp.lua` |

### Payload 传递机制（最关键）

```
prepare_*_event()          → 写入 SAVE_KEYS（可跨回合/存档持久化）
    ↓
open_current_event()       → 读取 STATE，调度到对应 launch 函数
    ↓
launch_*_dilemma(faction)  → 读取 SAVE_KEYS，构建运行时 payload，弹出 dilemma
    ↓
DilemmaChoiceMadeEvent     → handle_*_dilemma_choice(context) 处理玩家选择
    ↓
下一个 STATE / open_current_event 递推
```

> **核心原则：** `prepare_*` 只负责确定数据（保存到 SAVE_KEYS），`launch_*` 只负责把保存的数据注入进 dilemma builder 并弹窗，`handle_*` 只负责根据玩家选择推进状态。

---

## 二、接入步骤（共 8 步）

### Step 1 — DB：注册 Dilemma Key

**文件：** `db/dilemmas_tables/!!adamrogue_mvp_dilemmas.tsv`

在末尾添加一行：

```tsv
adamrogue_mvp_你的事件名_dilemma	false	dummy	dummy	army_morale_up	false	Event				false
```

- `key`：全局唯一，建议命名规范 `adamrogue_mvp_{事件名}_dilemma`
- `ui_image`：事件图标（参考原版图标 key，如 `army_morale_up`、`enemy_spotted`、`plus_event_public_order`）
- 其余字段保持与已有行一致

> `#dilemmas_tables;3;...` 那行的数字是原版 schema 版本，不需要修改。

---

### Step 2 — DB：注册选项 Key

**文件：** `db/cdir_events_dilemma_choice_details_tables/!!adamrogue_mvp_dilemma_choice_details.tsv`

每个按钮添加一行，用原版的 `FIRST / SECOND / THIRD / FOURTH / FIFTH`：

```tsv
FIRST	adamrogue_mvp_你的事件名_dilemma		
SECOND	adamrogue_mvp_你的事件名_dilemma		
THIRD	adamrogue_mvp_你的事件名_dilemma		
```

- 选项 key 只能用 `FIRST`–`FIFTH`，不能自定义字符串
- 有几个按钮注册几行，多注册无害，但 `launch_*` 函数中不 `add_choice_payload` 的选项不会在 UI 出现

---

### Step 3 — DB：注册触发权重

**文件：** `db/cdir_events_dilemma_option_junctions_tables/!!adamrogue_mvp_dilemma_option_junctions.tsv`

添加一行：

```tsv
610190006	adamrogue_mvp_你的事件名_dilemma	VAR_CHANCE	100	default
```

- `id` 字段使用一个未被占用的整数（已有：610190001–610190005，新增时递增）
- `VAR_CHANCE	100` 表示 100% 触发，保持不变

---

### Step 4 — Loc：添加文本

**同时修改两个文件：**
- `text/db/adamrogue_mvp_CN.loc.tsv`（中文）
- `text/db/en/adamrogue_mvp_EN.loc.tsv`（英文）

每个 dilemma 需要以下 key（以 `adamrogue_mvp_你的事件名_dilemma` 为例）：

```tsv
dilemmas_localised_title_adamrogue_mvp_你的事件名_dilemma	事件窗口标题	false
dilemmas_localised_description_adamrogue_mvp_你的事件名_dilemma	事件窗口正文描述	false
cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_你的事件名_dilemmaFIRST	按钮一标签	false
cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_你的事件名_dilemmaFIRST	按钮一 hover 说明文字	false
cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_你的事件名_dilemmaSECOND	按钮二标签	false
cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_你的事件名_dilemmaSECOND	按钮二 hover 说明文字	false
```

> **注意：** choice key 与 dilemma key 之间**没有下划线**，是直接拼接：`...dilemmaSECOND`，不是 `...dilemma_SECOND`。  
> 可以在文字中用 `[[col:yellow]]文字[[/col]]` 添加彩色文本，Lua 运行时注入的动态内容无法写在 loc 里，只能用 `campaign_payload_ui_details` 机制（参见目的地事件的实现）。

---

### Step 5 — Lua：添加常量与 STATE

**文件：** `adamrogue_mvp.lua`

**（5a）** 在文件顶部 `DILEMMA_*_KEY` 常量附近添加：

```lua
local DILEMMA_你的事件名_KEY = "adamrogue_mvp_你的事件名_dilemma"
```

**（5b）** 在 `STATE` 表中添加新状态（如果此事件需要独立的等待状态）：

```lua
local STATE = {
    -- ... 已有状态 ...
    你的事件名_PENDING = "你的事件名_PENDING",
}
```

**（5c）如果 `launch_*` 函数被其他函数提前引用**，在文件第 4–6 行的前置声明区添加：

```lua
local launch_你的事件名_dilemma
```

---

### Step 6 — Lua：实现 `prepare_*` 和 `launch_*`

#### `prepare_你的事件名_event()` — 生成并持久化事件数据

放置位置：文件中其他 `prepare_*` 函数附近（搜索 `prepare_unit_reward_event`）。

```lua
local function prepare_你的事件名_event()
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        return false
    end

    -- 1. 生成事件所需数据（随机、查表等）
    local my_data_a = ...
    local my_data_b = ...

    -- 2. 打包为 payload table，序列化后存入 SAVE_KEYS
    --    （payload 用 JSON-like table，通过 encode/decode 持久化）
    local payload = {
        my_field_a = my_data_a,
        my_field_b = my_data_b,
    }
    save_current_event_payload(payload, "你的事件名")

    -- 3. 更新 STATE（触发方在 open_current_event 里，这里只设 PENDING）
    set_current_state(STATE.你的事件名_PENDING)
    log("prepare_你的事件名_event: prepared. my_data_a=[" .. tostring(my_data_a) .. "].")
    return true
end
```

> **Payload 持久化机制：** 通过 `save_current_event_payload(table, label)` 将 table 序列化为字符串存入 SAVE_KEYS；通过 `get_current_event_payload()` 在 `launch_*` 和 `handle_*` 中反序列化取回。

#### `launch_你的事件名_dilemma(faction)` — 构建运行时 Dilemma 并弹窗

放置位置：其他 `launch_*` 函数附近（搜索 `launch_destination_dilemma`）。  
如果使用了前置声明（Step 5c），此处要用 `launch_你的事件名_dilemma = function(faction)` 赋值，而不是 `local function`。

```lua
local function launch_你的事件名_dilemma(faction)
    local payload = get_current_event_payload()
    if not payload or type(payload) ~= "table" then
        log("launch_你的事件名_dilemma aborted: payload unavailable.")
        return false
    end

    local dilemma_builder = cm:create_dilemma_builder(DILEMMA_你的事件名_KEY)
    local payload_builder = cm:create_payload()

    -- FIRST 按钮：此例用 text_display 占位（纯文字选项）
    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("FIRST", payload_builder)
    payload_builder:clear()

    -- SECOND 按钮
    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("SECOND", payload_builder)
    payload_builder:clear()

    -- 如果需要向特定部队挂载目标（大多数事件需要）：
    local player_force = get_saved_player_force()
    if not player_force then
        log("launch_你的事件名_dilemma aborted: player force unavailable.")
        return false
    end
    dilemma_builder:add_target("default", player_force)

    cm:launch_custom_dilemma_from_builder(dilemma_builder, faction)
    log("launch_你的事件名_dilemma: launched for faction [" .. faction:name() .. "].")
    return true
end
```

**常用 payload_builder 方法：**

| 方法 | 用途 |
|------|------|
| `payload_builder:text_display("key")` | 展示一条 campaign_payload_ui_details 中定义的文本（纯占位用 `"dummy_do_nothing"`）|
| `payload_builder:add_unit(force, unit_key, count, xp, auto_assign)` | 向部队添加单位（奖励事件） |
| `payload_builder:add_ancillary(character, ancillary_key)` | 给角色授予装备 |
| `payload_builder:clear()` | 每次 add_choice_payload 后必须 clear，否则 payload 会累加 |

---

### Step 7 — Lua：实现 `handle_*`

放置位置：其他 `handle_*` 函数附近（搜索 `handle_destination_dilemma_choice`）。

```lua
local function handle_你的事件名_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_你的事件名_KEY then
        return
    end

    local choice = context:choice()  -- 0=FIRST, 1=SECOND, 2=THIRD...
    log("handle_你的事件名_dilemma_choice: choice=[" .. tostring(choice) .. "].")

    -- 延迟 0.1s 处理，避免与引擎 dilemma 关闭动画冲突
    cm:callback(function()
        if choice == 0 then
            -- FIRST：执行操作，推进状态
            -- ... 业务逻辑 ...
            set_current_state(STATE.下一个状态)
            cm:callback(function()
                open_current_event("你的事件名_choice_0")
            end, 0.1)

        elseif choice == 1 then
            -- SECOND：暂停（玩家选"稍后"）
            pause_current_event()

        else
            log("handle_你的事件名_dilemma_choice: unrecognised choice [" .. tostring(choice) .. "].")
        end
    end, 0.1)
end
```

**状态推进规范：**

| 场景 | 做法 |
|------|------|
| 选择完成，推进到下一步 | `set_current_state(STATE.下一步)` → `open_current_event(reason)` |
| 玩家关闭窗口（稍后再选） | `pause_current_event()`（会设 PAUSED + paused_from_state） |
| 需要准备下一步数据后再推进 | 先调 `prepare_下一步_event()` 确保 payload 写好，再 `set_current_state` |
| 需要删除/生成地图对象（kill_character 等） | 先做操作，再用 `cm:callback(..., 0.5)` 延迟推进（等引擎结算） |

---

### Step 8 — Lua：接入调度器与监听器

#### 8a：在 `open_current_event` 中添加分支

搜索 `open_current_event`，找到状态 dispatch 区块，加入新状态的处理：

```lua
-- 现有结构（在 STATE.DESTINATION_PENDING 之后添加）：
elseif state == STATE.你的事件名_PENDING then
    if not launch_你的事件名_dilemma(faction) then
        return
    end
```

如果新事件在 INIT 时触发（需要从 INIT 分支进入），修改 INIT 分支中的逻辑（参见 army_preview 的实现）。

#### 8b：在 `register_listeners` 中注册监听器

搜索 `register_listeners`，找到 `DilemmaChoiceMadeEvent` 的过滤条件和分发逻辑：

```lua
-- 过滤条件中添加：
or dilemma_key == DILEMMA_你的事件名_KEY

-- 分发逻辑中添加（放在 else 之前）：
elseif context:dilemma() == DILEMMA_你的事件名_KEY then
    handle_你的事件名_dilemma_choice(context)
```

---

## 三、各现有事件的参考路标

| 事件 | 特点 | Lua 关键字（搜索定位） |
|------|------|----------------------|
| **单位奖励（reward）** | payload 注入真实单位到 dilemma（玩家看到卡牌） | `prepare_unit_reward_event`, `launch_reward_dilemma` |
| **战斗（battle）** | 触发后生成敌军并强制发动攻击，无实际 payload 数据 | `prepare_battle_event`, `launch_battle_dilemma`, `spawn_enemy_force_and_start_battle` |
| **装备奖励（equipment_reward）** | 单位奖励的变体，payload 是 ancillary key | `prepare_equipment_reward_event`, `launch_equipment_reward_dilemma` |
| **目的地（destination）** | payload 包含 3 个节点 key；UI 文本通过 `campaign_payload_ui_details` 注入 | `prepare_destination_event`, `launch_destination_dilemma` |
| **预览部队（army_preview）** | 无 prepare 步骤（async spawn 后直接 launch）；reroll 需要 kill_character | `spawn_new_preview_army`, `launch_army_preview_dilemma` |

---

## 四、注意事项与常见坑

### DB 层

- **`#` 行不要修改**，那是游戏工具导出时写的 schema 版本标识，引擎不依赖它的内容做解析，但修改可能导致工具读取出错。
- Dilemma 选项 key 只能用 `FIRST`–`FIFTH`，这是原版 CA 的枚举，不支持自定义。
- TSV 列之间用 **Tab** 分隔，不是空格；末列后面**不加多余 Tab**。

### 本地化层

- Choice key 拼接规则：`cdir_events_dilemma_choice_details_localised_choice_label_{dilemma_key}{choice_key}`，其中 `{dilemma_key}` 和 `{choice_key}` 之间没有分隔符，直接拼接。
- 如果 `cdir_events_dilemma_choice_details_localised_choice_title_*` 缺失，按钮依然显示，只是 hover tooltip 为空，不会报错。
- `dilemmas_localised_description_*` 对应事件窗口主文本，可以写多行（引擎自动换行），支持 `[[col:yellow]][[/col]]` 等 BBCode。

### Lua 层

- **`cm:callback` 的必要性：** DilemmaChoiceMadeEvent 触发时，引擎正在关闭 dilemma 窗口；直接在回调里做 `kill_character` 或弹新 dilemma 会概率性崩溃。务必用 `cm:callback(..., 0.1)` 延迟执行。
- **kill_character 后的再次 launch：** 地图对象删除是异步的，`kill_character` 后立即读取 character 接口会得到 null。再次 spawn 建议再延迟 0.5s（`cm:callback(..., 0.5)`）。
- **payload 序列化限制：** `save_current_event_payload` 只支持 `string/number/boolean/array/table` 的嵌套结构；不支持函数、userdata、循环引用。key 尽量用英文字母，避免中文 key（存档 UTF-8 编码）。
- **前置声明（forward declaration）：** 如果 `spawn_*` 或其他函数在定义之前就调用了 `launch_*`，需要在文件顶部 `local launch_army_preview_dilemma` 式的前置声明区（第 4–6 行附近）添加声明，再在实际定义处用赋值式 `launch_xxx = function(...)` 而非 `local function launch_xxx(...)`。
- **`is_supported_runtime_state`：** 如果新 STATE 可能在 `run_started=true` 时持久化到存档，需要将其加入 `is_supported_runtime_state()` 函数，否则存档加载时会被 normalize 回 INIT（通常是无害的，但会中断流程）。
- **Dilemma 不会自动重弹：** 玩家在 dilemma 窗口期间关掉游戏，再进来时 STATE 仍是 PENDING。`open_current_event` 再次被按钮触发时会重新 launch 同一事件——因此 `launch_*` 函数必须是幂等的（用 `get_current_event_payload` 读已有数据，而不是重新随机）。

---

## 五、最小接入检查表

接入完成后，逐项确认：

- [ ] `dilemmas_tables` TSV 中有新 dilemma key
- [ ] `cdir_events_dilemma_choice_details_tables` TSV 中有所有按钮的注册行
- [ ] `cdir_events_dilemma_option_junctions_tables` TSV 中有新 id 行（id 不重复）
- [ ] 中英文 loc TSV 均有 title、description 以及每个按钮的 label 和 title
- [ ] `DILEMMA_你的事件名_KEY` 常量已添加
- [ ] `STATE.你的事件名_PENDING` 已添加（如需独立等待状态）
- [ ] `prepare_*_event()` 或等效的数据生成入口已实现并能正确写入 SAVE_KEYS
- [ ] `launch_*_dilemma(faction)` 已实现，调用了 `cm:create_dilemma_builder` + `add_choice_payload` + `launch_custom_dilemma_from_builder`
- [ ] `handle_*_dilemma_choice(context)` 已实现，使用 `cm:callback` 延迟处理
- [ ] `open_current_event` 中新状态分支已添加
- [ ] `register_listeners` 过滤条件和分发逻辑均已更新
- [ ] 如有前置引用，顶部前置声明已添加（赋值式定义而非 local function）
