# AdamRogue 阶段 B 测试说明

本阶段统一继续使用日志文件 `adamrogue_phase_a_log.txt`，但测试重点已经从“入口与暂停恢复”扩展到“正式战斗循环”。

本轮测试重点：

- 奖励 -> 战斗的正式循环是否稳定
- 战斗敌军是否按预算生成，而不是固定模板
- 战斗统计字段是否正确更新
- 连续失败阈值与 `GAME_OVER` 是否正确
- 当前版本的“战损不保留”是否成立

## 当前实现口径

### 敌军价值分来源

当前阶段 B 使用：

- `OriginalGameData/db/main_units_tables/data__.tsv`
- 字段：`multiplayer_cost`

作为震旦敌军预算生成的单位价值分来源。

### 当前战损不保留策略

当前采用策略：

- `rebuild_force`

具体做法：

- 战斗开始前记录玩家军队的单位 roster
- 战斗结束后将现存单位补满生命值
- 如果有单位在战斗中损失，则按战前快照补回缺失单位

当前阶段不要求保留“战斗中的损失结果”，因此只需确认战后军队不会因为本场战斗永久减员。

## 游戏内可见结果

### 1. 基础入口与恢复

应继续满足阶段 A 已通过内容：

- 开局生成测试军队
- 正式入口按钮存在
- 奖励事件和战斗事件都可暂停/恢复
- 读档后可恢复待处理事件

### 2. 预算生成敌军

在连续多次进入战斗事件时，应看到：

- 敌军不再总是同一组固定单位
- 不同战斗之间的敌军组合会变化
- 同一次已生成但尚未开始的战斗，在暂停恢复后其敌军不会变化

### 3. 战斗统计更新

每完成一场战斗后，应看到：

- `completed_battle_count` 增加
- 胜利时 `victory_count` 增加
- 失败时 `defeat_count` 增加
- 胜利后 `consecutive_defeat_count` 清零
- 失败后 `consecutive_defeat_count` 增加

### 4. 连败阈值与 GAME_OVER

连续失败达到阈值后，应看到：

- 当前 run 进入 `GAME_OVER`
- 再次点击正式入口时，不再按正常奖励/战斗流程推进

### 5. 战损不保留

战斗结束后回到大地图，应看到：

- 本场战斗造成的减员不会永久保留
- 玩家军队在战后会恢复到战前 roster 规模
- 再进入下一轮事件时，不会因为上一战减员而缺单位

## 建议测试步骤

1. 开新震旦战役，确认测试军队和正式入口按钮出现。
2. 点击正式入口，进入奖励事件并选择一个单位。
3. 自动进入战斗事件，先选择“稍后再战”。
4. 再次点击入口，确认恢复的是同一场战斗事件。
5. 记录此时日志中的 `enemy_unit_list` 或 `generated_total_value`。
6. 选择“立即开战”，完成一场战斗。
7. 回到大地图后再次点击正式入口，继续下一轮奖励 -> 战斗。
8. 连续完成多场战斗，确认敌军组合会变化。
9. 故意连续失败，确认达到阈值后进入 `GAME_OVER`。
10. 额外观察战后玩家军队单位数量，确认不会因战斗永久减员。

## 关键日志

生成战斗事件时应接近看到：

```text
[adamrogue_phase_a] Building enemy force with budget [2600], value_source=[main_units_tables.multiplayer_cost], tier=[1].
[adamrogue_phase_a] Generated enemy force total_value=[2450], delta=[-150], units=[...].
[adamrogue_phase_a] Event context saved. type=[battle], key=[adamrogue_mvp_battle_dilemma], seed=[...], payload=[...]
```

恢复战斗事件后应看到：

```text
[adamrogue_phase_a] Entry triggered by player. reason=[ui_button], current_state=[PAUSED]
[adamrogue_phase_a] Current state is [PAUSED], paused_from_state=[BATTLE_PENDING].
[adamrogue_phase_a] Opening event from state [BATTLE_PENDING] with type=[battle], key=[adamrogue_mvp_battle_dilemma], seed=[...], payload=[...]
```

战斗触发时应接近看到：

```text
[adamrogue_phase_a] Captured pre-battle force snapshot. units=[...]
[adamrogue_phase_a] Launching caravan-core bridge battle for faction [...] in region [...] against enemy faction [wh3_main_cth_cathay_qb1], source=[budget_generator_v1], budget=[...]
```

战斗结算时应接近看到：

```text
[adamrogue_phase_a] Tracked battle resolved. Attackers=..., Defenders=..., Attacker victory=...
[adamrogue_phase_a] Battle resolved as [victory/defeat]. completed=..., victory=..., defeat=..., consecutive_defeat=...
[adamrogue_phase_a] Losses are not persisted. Strategy=[rebuild_force]. restored_units=[...]
```

进入 `GAME_OVER` 时应接近看到：

```text
[adamrogue_phase_a] Entering GAME_OVER because consecutive defeats reached [3].
```

## 边界检查

本阶段建议额外观察：

1. 同一场待开始战斗在暂停恢复前后，`enemy_unit_list` 是否保持一致。
2. 不同场战斗之间，预算和敌军组合是否出现变化。
3. 胜利后 `consecutive_defeat_count` 是否确实清零。
4. 连续失败达到阈值后，是否确实不再继续正常推进。
5. 战斗结束后玩家军队是否恢复到战前规模，而不是永久减员。
