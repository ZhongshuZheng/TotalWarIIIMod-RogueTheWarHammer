# AdamRogue 阶段 B 实现规范

本文档是“阶段 B：正式战斗循环”的硬性实现规范。目标是让开发者 agent 在阶段 A 已完成的前提下，直接开始下一轮开发。

背景总览见：

- `Docs/adamrogue_项目进展与开发路线.md`

## 本阶段目标

把当前“能打通一次固定战斗”的原型，升级为真正可支撑 run 推进的正式战斗循环。

阶段 B 完成后，系统应能：

1. 根据给定总价值分生成敌军，而不是只依赖单一固定模板。
2. 在战斗结算后正式维护 run 的战斗统计字段。
3. 正确处理胜利、失败、连续失败与后续状态推进。
4. 明确并固化“战斗损失是否保留”的设计。

## 本阶段不做什么

本阶段不要提前实现以下内容：

- 装备奖励事件正文逻辑
- 目的地事件正文逻辑
- 虚拟地图系统
- 多派系敌军池
- 大规模平衡参数表
- 完整 GAME_OVER 总结展示

允许做的最小预埋：

- 为阶段 C 的装备奖励事件保留战后跳转接口

## 阶段输入前提

开发者 agent 可以假设以下前提已成立：

- 阶段 A 已完成并稳定
- 正式入口已存在
- `PAUSED` / 恢复语义已跑通
- 奖励事件与战斗事件都可以被重新打开

如果这些前提在当前分支里并不成立，应先回退到阶段 A 的修复，不要直接跳过。

## 本阶段核心开发点

### 1. 敌军模板池

当前 MVP 的敌军配置过于固定，本阶段主方案不再是模板池，而是“基于价值分的敌军生成器 v1”。

第一版目标：

- 输入一个目标总价值分
- 在震旦兵种池内随机拼装一支接近该预算的敌军
- 输出一名领主、若干作战单位、以及可选的嵌入事务官

### 1.1 价值分来源

兵种价值分的主参考口径：

- 优先参考遭遇战模式或多人对战模式的单位价格

实现要求：

- 开发者 agent 需先确认这些价格在本地数据中是否能稳定读取
- 如果能读取：
  - 直接采用该价格作为 `unit_value`
- 如果不能直接读取：
  - 需要在文档中写明回退方案
  - 再采用人工维护的临时价值表

本阶段不允许：

- 完全不定义价值分口径
- 随意拍脑袋给所有单位估值且不记录来源

### 1.2 生成器输入输出

建议输入字段：

- `target_value_budget`
- `faction_key`
- `battle_tier`
- `allow_embedded_agent`

建议输出字段：

- `template_type = generated_by_budget`
- `lord_subtype`
- `unit_list`
- `embedded_agent_subtype`
- `generated_total_value`
- `budget_delta`

### 1.3 第一版生成要求

第一版要求：

- 只支持震旦敌军
- 只需要覆盖一份震旦可用兵种池
- 生成结果应尽量接近目标预算
- 可接受存在一定误差区间

推荐预算误差目标：

- `0.8x ~ 1.2x`

如果该区间在早期实现中过于严格，可先放宽，但必须写进日志和文档。

### 1.4 单位池配置

建议配置字段：

- `unit_key`
- `unit_value`
- `min_battle_tier`
- `max_battle_tier`
- `weight`
- `role_tag`

要求：

- 事件上下文中必须保存生成结果或足以重建同一结果的 payload
- 恢复战斗事件时不得重新随机出另一支完全不同的敌军
- 本阶段不要求生成器完美平衡，但要求结果可解释、可复现、可恢复

### 2. 战斗状态字段

本阶段至少要正式维护以下字段：

- `completed_battle_count`
- `victory_count`
- `defeat_count`
- `consecutive_defeat_count`

推荐同时保留：

- `last_battle_result`
- `last_battle_force_source`
- `last_battle_budget`

字段更新规则：

- 每完成一场有效战斗：
  - `completed_battle_count + 1`
- 玩家胜利：
  - `victory_count + 1`
  - `consecutive_defeat_count = 0`
- 玩家失败：
  - `defeat_count + 1`
  - `consecutive_defeat_count + 1`

### 3. 战斗后状态推进

本阶段必须把“战斗完之后去哪里”写死，不能继续模糊。

当前规定：

- 战斗胜利后：
  - 跳转到阶段 C 预留入口
  - 在阶段 C 未实现前，可先进入一个占位状态或直接回到下一事件生成点
- 战斗失败后：
  - 若未达到失败阈值，则 run 继续
  - 若达到失败阈值，则进入 `GAME_OVER`

本阶段要求：

- 失败阈值必须做成可配置常量
- 推荐常量名例如：
  - `MAX_CONSECUTIVE_DEFEATS = 3`

### 4. 战斗损失保留策略

这部分本阶段必须定案，不再继续“以后再说”。

当前设计决定：

- 阶段 B 先实现“战斗损失不保留”

允许的实现方式：

1. 克隆战斗军队
2. 战斗后重建原军队
3. 记录战前状态并回滚

要求：

- 只能选其中一种主方案
- 选定后要把方案写入文档，不要只写在代码里
- 如果当前版本先继续沿用 MVP 的现有方式，也必须明确说明其限制

### 5. 战斗事件恢复

阶段 B 下，战斗事件恢复要求比阶段 A 更严格。

恢复战斗事件时，必须保证以下内容不变：

- 敌军生成结果
- 敌方 faction key
- 选项语义
- 当前战斗事件 key

恢复时不得：

- 重新生成完全不同的一支敌军
- 重新换一个敌方 faction
- 因恢复而直接生成第二支新敌军

## 事件上下文扩展要求

阶段 B 需要在原有事件上下文基础上新增战斗相关 payload。

战斗事件 payload 最低要求：

- `battle_force_source`
- `target_value_budget`
- `enemy_faction_key`
- `enemy_general_subtype`
- `enemy_unit_list`
- `enemy_agent_subtype`
- `generated_total_value`
- `budget_delta`
- `start_battle_choice_index`
- `pause_choice_index`

如果实现中还需要以下字段，也可加入：

- `generated_enemy_force_cqi`
- `battle_seed`
- `battle_budget_tier`

原则：

- payload 必须足以在恢复时重建同一场待开始战斗

## 日志要求

本阶段需要新增或保留以下关键日志点：

- 当前目标总价值分
- 当前采用的单位价值分来源
- 敌军生成结果与最终总价值分
- 战斗结算后的统计字段更新结果
- 当前连续失败次数
- 是否进入 `GAME_OVER`
- 当前采用的“战损不保留”实现路径

建议日志示例：

```text
[adamrogue_phase_b] Building enemy force with budget [4200], value_source=[multiplayer_cost].
[adamrogue_phase_b] Generated enemy force total_value=[4075], delta=[-125].
[adamrogue_phase_b] Battle resolved as [victory]. completed=3, victory=2, defeat=1, consecutive_defeat=0.
[adamrogue_phase_b] Losses are not persisted. Strategy=[rebuild_force].
```

## 代码组织建议

本阶段建议至少把战斗逻辑分成下面几块：

- 单位价值表或价值读取层
- 敌军预算生成器
- 战斗事件生成函数
- 战斗结算更新函数
- 连败阈值判断函数
- 战损不保留处理函数

不强制大拆模块，但这些职责不能混在一个超长过程函数里无法维护。

## 验收标准

阶段 B 完成后，至少应满足以下验收项：

1. 系统能按总价值分生成震旦敌军，而不是只用固定模板。
2. 战斗事件恢复后，敌军生成结果不会变化。
3. 每场战斗后 `completed_battle_count` 正确增加。
4. 胜利时 `victory_count` 增加且 `consecutive_defeat_count` 清零。
5. 失败时 `defeat_count` 和 `consecutive_defeat_count` 正确增加。
6. 达到失败阈值后，状态进入 `GAME_OVER`。
7. 当前版本的“战斗损失不保留”策略已明确落地并写入文档。
8. 当前兵种价值分来源已明确记录为“多人/遭遇战价格”或已记录回退方案。

## 测试者在游戏内应看到什么

开发者 agent 在交付阶段 B 时，必须补充一份测试说明，并至少覆盖以下游戏内结果：

1. 多次触发战斗时，不再总是同一组固定敌军
2. 战斗失败后，如果未达到失败阈值，run 仍可继续
3. 连续失败达到阈值后，不再继续正常推进
4. 当前设计下，战斗造成的损失不会被永久带回 run

## 开发者常见误区

以下做法视为不符合阶段 B 设计：

- 表面上写了价值分生成器，但恢复战斗时又重新随机另一支不同敌军
- 胜利和失败都只写一个 `last_battle_result`，却不更新统计字段
- 连续失败不清零，导致胜利后仍然错误 GAME_OVER
- 战斗结束后直接跳回 `INIT`，丢失 run 统计
- “战损不保留”只停留在口头，没有稳定实现
