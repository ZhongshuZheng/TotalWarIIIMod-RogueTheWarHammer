# AdamRogue 阶段 A 测试说明

本阶段统一日志前缀为 `[adamrogue_phase_a]`，日志文件名为 `adamrogue_phase_a_log.txt`。

本轮测试重点不是“自动弹窗是否工作”，而是“正式入口 + 状态机 + 暂停恢复”是否工作。

## 游戏内可见结果

### 1. 开局状态

进入一局由玩家操控的震旦战役后，应看到：

- 首次进入战役后，地图上生成一支测试军队。
- HUD 的派系按钮区域出现一个新的正式入口按钮。
- 首回合不会依赖 `FactionTurnStart` 自动弹出奖励或战斗事件。

### 2. 正式入口触发奖励事件

点击正式入口按钮后，应看到：

- 第一次点击会打开奖励 dilemma。
- 奖励选项固定为 3 个单位选项加 1 个“稍后再选”。
- 不结束回合，连续关闭和再次点击入口时，应仍然打开同一个奖励事件，而不是重新随机。

### 3. 奖励事件暂停与恢复

在奖励 dilemma 中选择“稍后再选”后，应看到：

- 当前事件关闭。
- 本回合可以继续正常操作，不会被自动再次弹窗打断。
- 再次点击正式入口按钮，会恢复到同一个奖励事件。
- 恢复后的 3 个奖励选项内容和顺序不变。

### 4. 奖励结算后进入战斗事件

在奖励 dilemma 中选择任意一个单位奖励后，应看到：

- 对应单位加入测试军队。
- 当前不会自动立刻弹出战斗事件。
- 再次点击正式入口按钮时，才会打开战斗 dilemma。

### 5. 战斗事件暂停与恢复

在战斗 dilemma 中选择“稍后再战”后，应看到：

- 当前事件关闭。
- 地图上不会提前生成敌军。
- 再次点击正式入口按钮，会恢复到同一个战斗事件。
- 恢复后的战斗事件仍然对应同一套敌军模板，不会随机变化。

### 6. 战斗触发与结算

在战斗 dilemma 中选择“立即开战”后，应看到：

- 地图附近生成一支固定的震旦测试敌军。
- 玩家与敌军进入强制战斗流程。
- 战斗结束返回大地图后，测试敌军被清理。
- 本轮战斗结算后，run 状态回到 `INIT`，下次再点击正式入口会重新进入下一轮奖励事件。

### 7. 读档恢复

建议分别在以下节点存档再读档：

- 奖励事件暂停后
- 战斗事件暂停后

读档后再次点击正式入口，应看到：

- 奖励暂停档会恢复到原奖励事件。
- 战斗暂停档会恢复到原战斗事件。
- 恢复内容不应变化。

## 建议测试步骤

1. 开新震旦战役，确认测试军队和正式入口按钮出现。
2. 点击正式入口，打开奖励事件。
3. 先选一次“稍后再选”，再点击入口，确认恢复同一奖励事件。
4. 重新打开奖励事件后，选择一个奖励单位。
5. 再次点击正式入口，打开战斗事件。
6. 先选一次“稍后再战”，再点击入口，确认恢复同一战斗事件。
7. 重新打开战斗事件后，选择“立即开战”，完成一场战斗。
8. 战斗结束后再点击正式入口，确认重新进入奖励事件。

## 关键日志

首次初始化时应接近看到：

```text
[adamrogue_phase_a] First tick initialization started.
[adamrogue_phase_a] Player test force created. General CQI=..., Force CQI=..., Units=3
[adamrogue_phase_a] State -> INIT
[adamrogue_phase_a] First tick initialization finished.
```

点击正式入口并生成奖励事件时应接近看到：

```text
[adamrogue_phase_a] Entry triggered by player. reason=[ui_button], current_state=[INIT]
[adamrogue_phase_a] Event context saved. type=[unit_reward], key=[adamrogue_mvp_reward_dilemma], seed=[...], payload=[...]
[adamrogue_phase_a] State -> UNIT_REWARD_PENDING
[adamrogue_phase_a] Triggered reward dilemma for faction [...]
```

奖励事件暂停时应接近看到：

```text
[adamrogue_phase_a] Reward dilemma choice received: 3 payload=[...]
[adamrogue_phase_a] State -> PAUSED
[adamrogue_phase_a] Paused from state -> UNIT_REWARD_PENDING
```

恢复奖励事件时应接近看到：

```text
[adamrogue_phase_a] Entry triggered by player. reason=[ui_button], current_state=[PAUSED]
[adamrogue_phase_a] Current state is [PAUSED], paused_from_state=[UNIT_REWARD_PENDING].
[adamrogue_phase_a] State -> UNIT_REWARD_PENDING
[adamrogue_phase_a] Triggered reward dilemma for faction [...]
```

奖励结算并转入战斗待处理时应接近看到：

```text
[adamrogue_phase_a] Reward dilemma choice received: 0/1/2 payload=[...]
[adamrogue_phase_a] Granted reward unit [...] to player force. Unit count ... -> ...
[adamrogue_phase_a] Event context saved. type=[battle], key=[adamrogue_mvp_battle_dilemma], seed=[...], payload=[...]
[adamrogue_phase_a] State -> BATTLE_PENDING
```

战斗事件暂停时应接近看到：

```text
[adamrogue_phase_a] Battle dilemma choice received: 1 payload=[...]
[adamrogue_phase_a] State -> PAUSED
[adamrogue_phase_a] Paused from state -> BATTLE_PENDING
```

战斗触发时应接近看到：

```text
[adamrogue_phase_a] Battle dilemma choice received: 0 payload=[...]
[adamrogue_phase_a] Spawning enemy test force for [...]
[adamrogue_phase_a] Enemy test force created. General CQI=..., Force CQI=..., Units=3
[adamrogue_phase_a] Embedded Cathay Alchemist into the enemy test army. Agent CQI=...
[adamrogue_phase_a] Launching forced test battle from [caravan_style_enemy_attack]
```

战斗结算时应接近看到：

```text
[adamrogue_phase_a] Tracked battle resolved. Attackers=..., Defenders=..., Attacker victory=...
[adamrogue_phase_a] Player test force completed a tracked battle as [...] with result [...]
[adamrogue_phase_a] State -> INIT
```

## 边界检查

本阶段建议额外观察：

1. 不结束回合、连续多次点击正式入口时，是否会错误生成多个不同事件。
2. 处于 `PAUSED` 时再次点击正式入口，是否一定恢复原事件而不是跳到新事件。
3. 读档后恢复的事件内容是否和存档前一致。
4. 默认配置下是否完全不依赖 `FactionTurnStart` 自动弹窗。
