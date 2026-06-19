# AdamRogue MVP 测试说明

本次 MVP 的统一日志前缀是 `[adamrogue_mvp]`。

建议先验证这 4 段流程：

1. 进入一局由玩家操控的震旦战役。
2. 首回合或读档首 tick 后，确认出现测试军队与第一个 dilemma。
3. 选择一个奖励单位后，确认第二个 dilemma 出现。
4. 选择立即开战后，确认敌军生成、宣战、强制战斗与战斗结算日志。

关键日志顺序应接近如下：

```text
[adamrogue_mvp] First tick initialization started.
[adamrogue_mvp] Spawning player test force for [...]
[adamrogue_mvp] Player test force created. General CQI=..., Force CQI=..., Units=3
[adamrogue_mvp] State -> UNIT_REWARD_PENDING
[adamrogue_mvp] Triggering reward dilemma for faction [...]
```

奖励阶段成功后应看到：

```text
[adamrogue_mvp] Reward dilemma choice received: 0/1/2
[adamrogue_mvp] Granted reward unit [...] to player force. Unit count 3 -> 4
[adamrogue_mvp] State -> BATTLE_PENDING
[adamrogue_mvp] Triggering battle dilemma for faction [...]
```

战斗阶段成功后应看到：

```text
[adamrogue_mvp] Battle dilemma choice received: 0
[adamrogue_mvp] Spawning enemy test force for [...]
[adamrogue_mvp] Enemy test force created. General CQI=..., Force CQI=..., Units=3
[adamrogue_mvp] Embedded Cathay Alchemist into the enemy test army. Agent CQI=...
[adamrogue_mvp] Declaring war on enemy test faction [...]
```

随后通常会出现以下其中一条，用于说明强制进攻是从哪条路径启动：

```text
[adamrogue_mvp] War declaration listener confirmed both factions are now at war.
```

或：

```text
[adamrogue_mvp] Fallback war-state check succeeded after force_declare_war.
```

最后应看到：

```text
[adamrogue_mvp] Launching forced test battle from [...]
[adamrogue_mvp] Tracked battle resolved. Attackers=..., Defenders=..., Attacker victory=...
[adamrogue_mvp] Player test force completed a tracked battle as [...] with result [...]
[adamrogue_mvp] State -> BATTLE_RESOLVED
```

如果卡住，优先看这几类异常日志：

- `Local player faction is not supported for MVP`
- `Failed to find a valid spawn position`
- `Could not find a living non-player Cathay faction`
- `Fallback war-state check failed. Battle remains pending for later investigation.`
- `Reward unit grant attempted ..., but the unit count did not increase.`
