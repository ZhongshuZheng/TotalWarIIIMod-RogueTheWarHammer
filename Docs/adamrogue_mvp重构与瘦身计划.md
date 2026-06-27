---
name: adamrogue_mvp重构与瘦身计划
description: 针对 adamrogue_mvp.lua 的模块拆分、迁移顺序、清理策略与验收标准
---

# AdamRogue MVP 主脚本重构与瘦身计划

## 一、目标

当前主脚本 [adamrogue_mvp.lua](D:/Warhummer%20III%20AdamWorkshop/MyMods/商队Rogue玩法Mod/TotalWarIIIMod-RogueTheWarHammer/script/campaign/mod/adamrogue_mvp.lua:1) 已经承担了过多职责：

- 状态机编排
- 事件 payload 准备
- dilemma 发射
- dilemma 选项处理
- 初始部队生成
- 目的地节点逻辑
- 敌军生成与刷出回退
- 商队桥接战斗
- 战后恢复与状态推进
- listener 注册与 UI 入口

这直接带来几个问题：

- 单文件体量过大，当前约 5847 行
- 局部逻辑聚集，函数嵌套和回调链很深
- 迭代时容易触发 Lua 同时活跃局部变量超过 200 的问题
- 清理无用代码和验证影响范围都比较困难

本计划目标不是“重写玩法”，而是把 `adamrogue_mvp.lua` 收缩为一个薄编排层，把具体逻辑拆到多个子模块中，并在拆分过程中同步清理遗留代码。

## 二、重构原则

### 1. 先拆职责，再调实现

优先做模块边界收口，不先大改玩法规则。这样可以降低回归风险。

### 2. 主脚本只保留编排

最终 `adamrogue_mvp.lua` 只应保留：

- 模块 require
- 核心常量装配
- 首 tick 初始化
- `open_current_event` 总调度
- listener 注册

### 3. 事件分三层

每类事件都尽量拆成三层：

- `prepare_*`：生成并持久化 payload
- `launch_*`：构建 dilemma 并发射
- `handle_*`：响应玩家选择并推进状态

### 4. 引擎桥接逻辑单独隔离

凡是与 `cm:create_force_with_general`、`caravans:create_caravan_battle`、轮询 CQI、fallback spawn 有关的逻辑，统一放到战斗桥接模块，不和奖励、状态推进混写。

### 5. 先做可验证拆分

优先拆最独立、最容易验证的部分；最后再拆战斗发起链。

## 三、现状结构判断

结合当前代码与文档，主流程已经比较明确：

```text
首次按钮点击
  -> 预览部队生成
  -> 预览 dilemma
  -> 确认 run

正式循环
  -> 英雄奖励周期判断
  -> 单位奖励
  -> 战斗
  -> 胜利: 装备奖励
  -> 失败/战后: 目的地选择
  -> 下一轮

连续失败达到阈值
  -> GAME_OVER
```

当前最重的复杂度热点主要有：

- `launch_spawned_enemy_force_battle`
- `issue_enemy_force_spawn_with_general`
- `build_starting_player_unit_list`
- `apply_player_character_minimum_rank_for_cycle`
- `find_alternative_enemy_spawn_position`
- `prepare_unit_reward_event`
- `prepare_battle_event`

这说明主脚本中同时混合了：

- 配置读取
- 算法生成
- 状态保存
- UI 发射
- 引擎桥接
- 战后回调

这是此次瘦身的核心切入点。

## 四、目标模块结构

建议在 `script/campaign/mod/adamrogue/` 下继续拆出以下模块。

### 1. `adamrogue_runtime_state.lua`

职责：

- `STATE`
- `SAVE_KEYS`
- `get_saved_value` / `set_saved_value`
- 当前事件上下文读写
- payload 编解码
- `get_current_state` / `set_current_state`
- paused 状态与恢复

说明：

这是所有模块的共同依赖，建议最先拆。拆完以后，主脚本不再直接散落大量 `cm:get_saved_value` / `cm:set_saved_value`。

### 2. `adamrogue_progression.lua`

职责：

- 当前 cycle / difficulty 读写与初始化
- 敌军预算成长
- 玩家奖励价值区间
- 装备稀有度上下文
- 精英战判断
- 玩家最小 rank 补齐
- 敌将目标 rank 与技能分配

说明：

把成长、难度、rank 相关逻辑统一收口，避免它们散在奖励和战斗逻辑里。

### 3. `adamrogue_player_bootstrap.lua`

职责：

- 玩家内容派系解析
- 玩家将领候选与默认将领 subtype
- 初始部队生成
- 预览部队生成
- 预览 dilemma 发射
- 预览 dilemma 选项处理

说明：

预览开局是一个明显独立的子流程，不应继续与正式循环混在一起。

### 4. `adamrogue_world_nodes.lua`

职责：

- 节点查询
- 当前节点初始化
- 当前节点切换
- 目的地候选生成
- 目的地事件 payload 生成
- 目的地状态清理

说明：

目的地逻辑本质上是“虚拟地图层”，应独立于奖励和战斗。

### 5. `adamrogue_reward_units.lua`

职责：

- 奖励单位池获取
- 按价值区间筛选单位
- 单位奖励 payload 生成
- 单位奖励 dilemma 发射
- 单位奖励选项处理

说明：

单位奖励有自己的一套价值筛选和池选择逻辑，适合单独维护。

### 6. `adamrogue_reward_heroes.lua`

职责：

- 英雄奖励周期判断
- 英雄候选生成
- 英雄奖励 dilemma 发射
- 满编警告 dilemma
- 发英雄、嵌入军队、补 rank
- 英雄奖励选项处理

说明：

英雄奖励和单位奖励不要混在一起。它们的引擎交互方式和失败处理明显不同。

### 7. `adamrogue_reward_equipment.lua`

职责：

- 装备奖励 payload 生成
- 装备奖励 dilemma 发射
- 装备奖励选项处理

说明：

底层生成器 `adamrogue_ancillary_generator.lua` 已经存在，这里只保留流程层和 UI 层。

### 8. `adamrogue_battle_flow.lua`

职责：

- 战斗事件 prepare
- 战斗 dilemma 发射
- 战斗选项处理
- 战后状态推进
- 胜负统计
- GAME_OVER 判断

说明：

该模块只负责“这场战斗在流程上代表什么”，不负责底层刷兵和桥接。

### 9. `adamrogue_battle_spawn.lua`

职责：

- 敌方派系候选序列
- 刷兵派系兼容性判断
- 玩家附近刷点搜索
- 替代刷点搜索
- 敌军与将领刷出
- create_force fallback
- CQI 轮询
- 商队桥接开战
- 战斗刷出失败回退与重试

说明：

这是当前最复杂、最容易导致局部变量过多的区域。应作为单独模块隔离。

### 10. `adamrogue_ui_entry.lua`

职责：

- HUD 按钮响应
- `DilemmaChoiceMadeEvent`
- `BattleCompleted`
- 调用 `open_current_event`

说明：

listener 不应与业务逻辑写在一起。

## 五、建议保留在主脚本中的内容

重构完成后，`adamrogue_mvp.lua` 建议只保留：

- `require` 各模块
- 构造共享 context
- 初始化各子模块
- `open_current_event`
- `register_listeners`
- `cm:add_first_tick_callback`

如果后续还要继续拆，`open_current_event` 也可以改为表驱动分发：

```lua
STATE_TO_OPEN_HANDLER = {
    [STATE.ARMY_PREVIEW_PENDING] = player_bootstrap.launch_army_preview_dilemma,
    [STATE.HERO_REWARD_PENDING] = hero_rewards.launch_hero_reward_dilemma,
    [STATE.UNIT_REWARD_PENDING] = unit_rewards.launch_reward_dilemma,
    [STATE.BATTLE_PENDING] = battle_flow.launch_battle_dilemma,
    [STATE.EQUIPMENT_REWARD_PENDING] = equipment_rewards.launch_equipment_reward_dilemma,
    [STATE.DESTINATION_PENDING] = world_nodes.launch_destination_dilemma,
}
```

## 六、分阶段迁移计划

### 阶段 0：基线整理

目标：

- 确认当前主流程不变
- 标记明显无用函数与遗留代码
- 建立迁移清单

建议处理项：

- 审核 `ensure_run_started`
- 审核 `force_attack_once`
- 审核 `set_difficulty_level`
- 审核 `get_saved_enemy_force`
- 审核 `find_enemy_spawn_near_player`

预期结果：

- 输出“保留 / 删除 / 待确认”列表

### 阶段 1：拆状态层

拆分模块：

- `adamrogue_runtime_state.lua`
- 可选同步拆出部分 `adamrogue_progression.lua`

迁移内容：

- 状态常量
- save key
- payload 编解码
- 当前事件上下文

验收标准：

- 主脚本中不再直接分散定义大量状态读写函数
- 原有事件流程不变

### 阶段 2：拆节点与奖励层

拆分模块：

- `adamrogue_world_nodes.lua`
- `adamrogue_reward_units.lua`
- `adamrogue_reward_heroes.lua`
- `adamrogue_reward_equipment.lua`

迁移内容：

- 节点查找与目的地事件
- 单位奖励全链路
- 英雄奖励全链路
- 装备奖励全链路

验收标准：

- 主脚本中不再包含大段 `prepare_*reward*`
- 目的地和奖励 dilemma 的 `prepare/launch/handle` 各自成组

### 阶段 3：拆玩家开局与预览层

拆分模块：

- `adamrogue_player_bootstrap.lua`

迁移内容：

- 玩家将领选择
- 初始部队生成
- 预览部队生成
- 预览 dilemma 与 choice handler

验收标准：

- 主脚本不再包含开局部队生成算法
- `build_starting_player_unit_list` 从主脚本移出

### 阶段 4：拆战斗流程层

拆分模块：

- `adamrogue_battle_flow.lua`
- `adamrogue_progression.lua`

迁移内容：

- 战斗事件 prepare
- 战后状态推进
- 胜负统计
- cycle / difficulty / rank 相关逻辑

验收标准：

- 主脚本不再包含 `prepare_battle_event` 和 `handle_post_battle_state_transition` 的主体实现

### 阶段 5：拆战斗刷出与桥接层

拆分模块：

- `adamrogue_battle_spawn.lua`

迁移内容：

- 敌军派系选择
- 出生点搜索
- create_force_with_general
- fallback 与 retry
- 轮询
- 商队桥接开战

验收标准：

- 主脚本中不再存在数百行战斗刷出链路
- 战斗生成失败时的 fallback 行为不变

### 阶段 6：拆 UI 与监听层

拆分模块：

- `adamrogue_ui_entry.lua`

迁移内容：

- 按钮 listener
- dilemma listener
- battle completed listener

验收标准：

- 主脚本只保留初始化装配

## 七、推荐执行顺序

实际操作建议按下面顺序推进，而不是按依赖最复杂的战斗层开刀：

1. `runtime_state`
2. `world_nodes`
3. `reward_heroes`
4. `reward_units`
5. `reward_equipment`
6. `player_bootstrap`
7. `progression`
8. `battle_flow`
9. `battle_spawn`
10. `ui_entry`

原因：

- 先拆轻模块，能快速降低主脚本体积
- 先把状态与奖励逻辑收口，后续战斗模块就不必再处理散乱的 save key 细节
- 最复杂的战斗刷出链留到后面，避免一开始就引入大规模回归风险

## 八、清理策略

本次重构不是单纯搬运函数，还应同步做清理。

### 1. 删除未引用函数

对于只定义不调用的函数，逐个核实后删除，不保留“也许以后会用”的遗留实现。

### 2. 清理重复 fallback

当前部分逻辑存在多层 fallback 叠加，后续应区分：

- 内容派系 fallback
- 敌军派系 fallback
- 刷点 fallback
- create_force fallback

每层只保留一个明确职责，不要互相交叉。

### 3. 把表驱动替代分支堆叠

以下位置优先考虑改为表驱动：

- state 到 launch handler 的映射
- dilemma key 到 choice handler 的映射
- reward slot 到 payload 生成的映射

### 4. 降低函数内局部变量密度

对于超大函数，优先拆成：

- 参数收集
- 核心计算
- 引擎调用
- 失败回退
- 日志输出

避免在一个函数里同时保存 20 到 40 个上下文字段。

## 九、每阶段验收方式

每拆完一个阶段，至少做以下检查：

- 脚本可加载，无 require 错误
- 首 tick 正常
- 按钮可点击
- 当前阶段涉及的事件链仍能打开
- payload 仍可正常保存与恢复
- pause / resume 不被破坏

对战斗相关阶段，还要额外检查：

- 敌军可正常刷出
- fallback 时不会卡死
- `BattleCompleted` 后仍可推进流程

## 十、最终目标状态

重构完成后，希望达到以下状态：

- `adamrogue_mvp.lua` 控制在 800 到 1500 行左右
- 单个模块职责单一
- 主要函数长度尽量控制在 40 到 120 行
- 超过 150 行的函数需要继续拆解
- 事件都遵循 `prepare -> launch -> handle` 结构
- 战斗桥接逻辑完全隔离
- 删除确认无用的历史遗留代码


