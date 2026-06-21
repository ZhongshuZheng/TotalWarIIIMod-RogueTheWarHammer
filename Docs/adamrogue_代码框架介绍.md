---
name: 代码框架介绍
description: 商队Rogue玩法Mod的模块功能索引，供功能改动时快速定位代码文件
---

# 商队Rogue玩法Mod — 代码框架介绍

> 目标：快速定位模块，具体实现读源码。

---

## 一、文件结构速览

```
TotalWarIIIMod-RogueTheWarHammer/
├── Docs/                          ← 设计规范文档（阶段A–E）
├── db/                            ← 游戏数据库静态表（dilemma定义、装备解锁）
├── script/campaign/mod/
│   ├── adamrogue_mvp.lua          ← ★ 主入口：状态机、流程控制、事件调度
│   └── adamrogue/
│       ├── adamrogue_balance_config.lua        ← 平衡参数（难度/成长曲线/装备稀有度）
│       ├── adamrogue_battle_generator.lua      ← 敌军编队生成
│       ├── adamrogue_ancillary_generator.lua   ← 装备奖励生成
│       ├── adamrogue_force_snapshot.lua        ← 战损不保留（快照+恢复）
│       ├── adamrogue_data_nodes.lua            ← 24个目的地节点定义 [自动生成]
│       ├── adamrogue_data_battle_pools.lua     ← 各派系单位战斗池 [自动生成]
│       ├── adamrogue_data_ancillaries.lua      ← 各派系装备池 [自动生成]
│       └── adamrogue_data_players.lua          ← 全派系支持数据 [自动生成]
├── text/db/                       ← 中英文本地化
├── tools/adamrogue/               ← 数据生成工具（Python脚本 + 派系蓝图JSON）
└── ui/campaign ui/                ← HUD 入口按钮（twui.xml）
```

---

## 二、游戏主流程（状态机）

玩家点击 HUD 按钮触发，依次流转：

```
INIT
 → 单位奖励（UNIT_REWARD_PENDING）
 → 战斗（BATTLE_PENDING）
 → [胜] 装备奖励（EQUIPMENT_REWARD_PENDING）→ 目的地（DESTINATION_PENDING）→ cycle+1 → INIT
 → [败] 目的地（DESTINATION_PENDING）→ cycle+1 → INIT
 → [连败≥3] GAME_OVER

PAUSED：玩家关闭事件窗，再次点击按钮从断点恢复
```

---

## 三、模块功能索引

### `adamrogue_mvp.lua` — 主控制器

所有流程逻辑的入口，包含以下职责区块：

| 职责 | 关键词（搜索定位） |
|------|------------------|
| 全局常量与 SAVE_KEYS 定义 | `SAVE_KEYS`, `STATE`, `DILEMMA_*_KEY` |
| 平衡数值计算（敌军预算、奖励价值区间、装备稀有度） | `get_enemy_value_budget_for_cycle`, `get_player_reward_value_band_for_cycle` |
| 派系解析（玩家派系→内容派系映射，将领选项） | `resolve_player_content_faction_key`, `pick_random_player_general_option` |
| 初始编队生成 | `build_starting_player_unit_list` |
| 各阶段事件准备（生成 payload，写入存档） | `prepare_unit_reward_event`, `prepare_battle_event`, `prepare_equipment_reward_event`, `prepare_destination_event` |
| Dilemma 启动（运行时注入 payload） | `launch_reward_dilemma`, `launch_battle_dilemma`, `launch_equipment_reward_dilemma`, `launch_destination_dilemma` |
| 主调度器（根据 STATE 决定打开哪个事件） | `open_current_event` |
| 战斗发起（敌军 spawn + 战斗桥接） | `spawn_enemy_force_and_start_battle` |
| 战后状态转移 | `handle_post_battle_state_transition` |
| 各 dilemma 选项响应 | `handle_*_dilemma_choice` |
| 监听器注册与初始化 | `register_listeners`, `add_first_tick_callback` |

---

### `adamrogue_balance_config.lua` — 平衡参数

**改平衡数值时唯一需要改的文件。**  
包含：难度等级倍率、敌军成长曲线、玩家奖励价值区间、装备稀有度解锁梯度、精英战轮次配置、敌军数量控制。

---

### `adamrogue_battle_generator.lua` — 敌军生成器

工厂模式（`battle_generator.new(context)`），核心逻辑：  
- 按价值预算 + 轮次 tier 从单位池中随机抽取敌军编队  
- 三阶段算法：主循环随机选 → 低价填充 → 升级替换  
- 敌将 subtype 和嵌入事务官均由内容派系决定

**改敌军选兵逻辑** → 找 `build_budget_enemy_force_definition`

---

### `adamrogue_ancillary_generator.lua` — 装备奖励生成器

工厂模式（`ancillary_generator.new(context)`），核心逻辑：  
- 三槽位（weapon / armour / accessory）各生成一个候选装备  
- 奖励池来源：通用池 + 玩家派系池 + 当前节点派系池  
- 稀有度按轮次门控，精英战强制最高 tier，含三级 fallback

**改装备生成逻辑** → 找 `generate_equipment_reward_payload`  
**改稀有度规则** → 找 `get_allowed_rarity_bands_for_reward`

---

### `adamrogue_force_snapshot.lua` — 部队快照

工厂模式（`force_snapshot.new(context)`），核心逻辑：  
- 战前：快照当前编队单位列表和将领等级  
- 战后：全员满血，并补全战斗中损失的单位（战损不保留）  
- 部队意外丢失时：从快照完整重建军队

**改战损恢复逻辑** → 找 `restore_player_force_after_battle`

---

### `adamrogue_data_*.lua` — 数据层（自动生成，勿手动编辑）

| 文件 | 内容 |
|------|------|
| `adamrogue_data_nodes.lua` | 24个目的地节点（key、所属派系、显示文本key） |
| `adamrogue_data_battle_pools.lua` | 各派系战斗单位池（unit_key、价值、权重、tier范围）+ 敌将/事务官 subtype |
| `adamrogue_data_ancillaries.lua` | 通用装备池 + 各派系装备池（槽位、稀有度、权重） |
| `adamrogue_data_players.lua` | 全派系支持表、玩家派系→内容派系映射、各派系将领选项 |

**新增或修改派系** → 改 `tools/adamrogue/faction_blueprint.json`，运行 `regenerate_stage_d_data.ps1` 重新生成。

---

### `db/` — 数据库静态表

- `dilemmas_tables/`：4个 dilemma 的 key 注册（reward / battle / equipment_reward / destination）
- `cdir_events_dilemma_choice_details_tables/`：各 dilemma 选项 key（FIRST–FIFTH）
- `cdir_events_dilemma_payloads_tables/`：静态占位，实际 payload 由 Lua 运行时注入
- `ancillaries_tables/`：将所有 Mod 装备的 faction_set 设为 `all`，确保任意派系可领取
- `campaign_payload_ui_details_tables/`：目的地节点的 UI 图标 key

---

### `text/db/` — 本地化

中英文各一个 `.loc.tsv` 文件，覆盖 dilemma 文案、节点名称、按钮 tooltip。  
新增节点或选项时两个文件同步更新。

---

### `tools/adamrogue/` — 数据生成工具

- `faction_blueprint.json`：派系蓝图（faction_key、将领 subtype、QB 候选等）
- `generate_stage_d_data.py`：从 `OriginalGameData/db` 读取原始数据，输出四个 `adamrogue_data_*.lua`
- `regenerate_stage_d_data.ps1`：运行入口脚本

---

### `ui/campaign ui/` — HUD 按钮

圆形按钮，点击触发 `TriggerScriptEvent("adamrogue_phase_a_entry:{FactionKey}")`，被主入口监听器接收。

---

## 四、常见改动 → 文件对照

| 改动 | 涉及文件 |
|------|---------|
| 调整平衡数值（成长/奖励/稀有度/精英战） | `adamrogue_balance_config.lua` |
| 调整敌军选兵逻辑 | `adamrogue_battle_generator.lua` |
| 调整装备奖励逻辑 | `adamrogue_ancillary_generator.lua` |
| 调整战损/恢复逻辑 | `adamrogue_force_snapshot.lua` |
| 新增/修改派系支持 | `faction_blueprint.json` → 重跑生成脚本 |
| 修改单位奖励候选逻辑 | `adamrogue_mvp.lua` → `prepare_unit_reward_event` |
| 修改战斗胜败后转流 | `adamrogue_mvp.lua` → `handle_post_battle_state_transition` |
| 修改目的地选择逻辑 | `adamrogue_mvp.lua` → `prepare_destination_event` |
| 新增 dilemma 选项 | `db/cdir_events_dilemma_choice_details_tables/` + `launch_*_dilemma` |
| 修改文案 | `text/db/adamrogue_mvp_CN.loc.tsv` + `..._EN.loc.tsv` |
