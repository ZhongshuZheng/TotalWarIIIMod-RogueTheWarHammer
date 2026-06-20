# AdamRogue 阶段 A 实现规范

本文档是“阶段 A：正式入口与状态机收束”的硬性实现规范。目标是让开发者 agent 在不反复追问设计语义的前提下，直接开始开发。

背景总览见：

- `Docs/adamrogue_项目进展与开发路线.md`

## 本阶段目标

把当前 MVP 的“自动触发原型”改造成“玩家主动推进的正式流程雏形”。

阶段 A 完成后，玩家应能：

1. 进入战役后获得测试军队。
2. 通过一个正式入口主动推进 run。
3. 在奖励事件和战斗事件之间暂停、恢复，而不是依赖回合开始自动弹窗。
4. 读档后仍能恢复到正确事件。

## 本阶段不做什么

本阶段不要提前实现以下内容：

- 装备奖励事件正文逻辑
- 目的地事件正文逻辑
- 虚拟地图系统
- 完整失败结算
- 多派系适配
- 大规模模块拆分

允许做的最小预埋：

- 为后续 `EQUIPMENT_REWARD_PENDING`、`DESTINATION_PENDING` 预留状态枚举与接口占位

## 正式入口设计

### 入口优先级

本阶段入口方案优先级如下：

1. UI 按钮
2. 若 UI 按钮成本过高，则使用一个稳定的脚本入口作为过渡实现，并明确保留未来按钮接线层

### 正式入口要求

正式入口必须满足：

- 玩家可在同一回合内反复触发
- 触发时不会无条件重置 run
- 触发时只做一件事：
  - 恢复未完成事件
  - 或生成下一事件

正式入口不得：

- 直接跳过当前未完成事件
- 每次都重新随机事件内容
- 依赖“结束回合”才能继续

### Debug 入口要求

允许保留 debug 入口，但要求如下：

- 必须和正式入口分离
- 不能让 debug 入口成为主流程依赖
- 测试文档必须明确区分“正式入口测试”和“debug 入口测试”

## 状态机规范

### 必须支持的状态

- `INIT`
- `UNIT_REWARD_PENDING`
- `BATTLE_PENDING`
- `EQUIPMENT_REWARD_PENDING`
- `DESTINATION_PENDING`
- `PAUSED`
- `GAME_OVER`

### 状态语义

- `INIT`
  - run 已初始化，但还未生成当前待处理事件
- `UNIT_REWARD_PENDING`
  - 当前待处理事件是单位奖励事件
- `BATTLE_PENDING`
  - 当前待处理事件是战斗事件
- `EQUIPMENT_REWARD_PENDING`
  - 当前待处理事件是装备奖励事件
- `DESTINATION_PENDING`
  - 当前待处理事件是目的地事件
- `PAUSED`
  - 玩家主动关闭了当前事件窗，但该事件尚未结算
- `GAME_OVER`
  - 当前 run 已结束，不允许继续按正常流程推进

### 阶段 A 允许的真实业务状态

虽然状态枚举包含 7 个，但本阶段真正需要跑通的只有：

- `INIT`
- `UNIT_REWARD_PENDING`
- `BATTLE_PENDING`
- `PAUSED`

`EQUIPMENT_REWARD_PENDING` 和 `DESTINATION_PENDING` 在本阶段只要求能作为保留状态存在，不要求进入完整业务逻辑。

### PAUSED 语义

`PAUSED` 不是“事件类型”。

`PAUSED` 表示：

- 当前存在一个未完成事件
- 玩家主动选择暂时关闭
- 系统必须记住“暂停前真正是什么事件”

因此必须额外保存：

- `paused_from_state`

例如：

- 奖励事件关闭后：
  - `current_state = PAUSED`
  - `paused_from_state = UNIT_REWARD_PENDING`
- 战斗事件关闭后：
  - `current_state = PAUSED`
  - `paused_from_state = BATTLE_PENDING`

### 最小状态迁移表

本阶段至少满足以下迁移：

1. `INIT -> UNIT_REWARD_PENDING`
2. `UNIT_REWARD_PENDING -> BATTLE_PENDING`
3. `UNIT_REWARD_PENDING -> PAUSED`
4. `BATTLE_PENDING -> PAUSED`
5. `PAUSED -> paused_from_state`

本阶段禁止出现的迁移：

- `PAUSED -> INIT`
- `PAUSED -> 随机新事件`
- `UNIT_REWARD_PENDING -> INIT`
- `BATTLE_PENDING -> INIT`

## 入口触发规则

玩家点击正式入口时，统一按下面顺序处理：

1. 如果 run 尚未初始化，先确保测试军队与基础 run 数据存在
2. 读取当前状态
3. 若当前状态为 `PAUSED`
   - 恢复 `paused_from_state` 对应事件
   - 使用已保存的事件上下文重建事件
4. 若当前状态为 `INIT`
   - 生成下一事件
5. 若当前状态为 `UNIT_REWARD_PENDING`
   - 直接打开当前奖励事件，不重新随机
6. 若当前状态为 `BATTLE_PENDING`
   - 直接打开当前战斗事件，不重新随机
7. 若当前状态为 `GAME_OVER`
   - 当前阶段可先输出占位提示或日志，不要求实现正式总结窗

## 事件上下文规范

阶段 A 必须建立统一事件上下文，而不是把数据散落在多个 `saved_value` 里各自处理。

### 必须保存的字段

- `current_event_type`
- `current_event_key`
- `current_event_seed`
- `current_event_payload`
- `current_state`
- `paused_from_state`

### 字段语义

- `current_event_type`
  - 事件类型字符串，例如 `unit_reward` / `battle`
- `current_event_key`
  - 当前事件实例绑定的 dilemma key
- `current_event_seed`
  - 当前事件生成时使用的随机种子或等价标识
- `current_event_payload`
  - 当前事件恢复所需的最小数据集合
- `current_state`
  - 当前状态
- `paused_from_state`
  - 若当前状态是 `PAUSED`，记录暂停前状态

### Payload 最小要求

单位奖励事件至少要能恢复：

- 3 个奖励选项对应的单位 key
- 哪个选项是“稍后再选”

战斗事件至少要能恢复：

- 当前战斗模板 key
- 当前敌方 faction key
- 哪个选项是“立即开战”
- 哪个选项是“下回合再战/暂时关闭”

### 恢复原则

恢复事件时：

- 必须优先读取 `current_event_payload`
- 不得重新滚一次随机结果
- 不得因为重新打开事件而改变选项顺序或内容

## 自动弹窗逻辑处理

当前 MVP 中存在“回合开始自动弹窗”的原型行为。

阶段 A 要求：

- 正式主逻辑不再依赖 `FactionTurnStart` 自动弹窗
- 如有必要，可保留 debug 开关，例如：
  - `auto_resume_on_turn_start = false`
- 默认值必须是关闭

## 日志要求

阶段 A 需要新增或保留以下关键日志点：

- 正式入口被触发
- 当前状态读取结果
- 当前是“恢复事件”还是“生成新事件”
- `PAUSED` 写入时的来源状态
- 事件上下文保存完成
- 事件上下文恢复完成

建议日志示例：

```text
[adamrogue_phase_a] Entry triggered by player.
[adamrogue_phase_a] Current state is [PAUSED], paused_from_state=[UNIT_REWARD_PENDING].
[adamrogue_phase_a] Restoring saved unit reward event from payload.
```

## 代码组织建议

本阶段不强制大拆模块，但至少建议把责任分开：

- 入口处理函数
- 状态读取/写入函数
- 事件上下文保存/恢复函数
- 单位奖励事件触发函数
- 战斗事件触发函数

如果开发者 agent 愿意做小幅整理，可以接受“同文件多区域”方式，但职责必须清晰。

## 验收标准

阶段 A 完成后，至少应满足以下验收项：

1. 玩家不结束回合，只靠正式入口即可打开奖励事件。
2. 选择“稍后再选”后，当前状态变为 `PAUSED`。
3. 再次点击正式入口，会恢复到同一个奖励事件，且选项内容不变。
4. 进入战斗事件后，选择“下回合再战/关闭”会进入 `PAUSED`。
5. 再次点击正式入口，会恢复到同一个战斗事件，且目标模板不变。
6. 读档后点击正式入口，仍能恢复到正确事件。
7. 默认流程不依赖回合开始自动弹窗。

## 测试者在游戏内应看到什么

开发者 agent 在交付阶段 A 时，必须补充一份测试说明，并至少覆盖以下游戏内结果：

1. 地图上存在一个可用的正式入口触发方式
2. 不结束回合，连续两次点击入口时，流程表现符合状态机预期
3. 暂停后再次触发，看到的是原事件而不是新事件
4. 读档后再次触发，仍恢复原事件

## 开发者常见误区

以下做法视为不符合阶段 A 设计：

- 关闭事件窗后重新打开时重新随机选项
- 仍然主要依赖 `FactionTurnStart` 自动弹窗推进
- 只保存一个 `current_state = PAUSED`，但不保存暂停来源
- 战斗事件恢复时重新生成一支不同敌军
- 正式入口每次触发都把 run 重置到初始状态
