---
name: 游戏更新数据再生成指南
description: 游戏版本更新后，如何用 tools 脚本快速再生成 Mod 数据
---

# 商队Rogue玩法Mod — 游戏更新数据再生成指南

> 目标：游戏更新（新领主、兵种、装备、技能）后，快速判断哪些内容能自动进 Mod，以及需要执行的操作步骤。

---

## 一、脚本分工

| 脚本 | 路径 | 作用 |
|------|------|------|
| `generate_stage_d_data.py` | `tools/adamrogue/` | **主生成器**：从 `OriginalGameData/db` 读取原游戏表，生成 Mod 数据 |
| `update_hero_reward_metadata.py` | `tools/adamrogue/` | **辅助脚本**：从已生成的 `adamrogue_data_battle_pools.lua` 提取英雄列表，补 db / 本地化 |
| `regenerate_stage_d_data.ps1` | `tools/adamrogue/` | 运行主生成器 + luac 语法检查 |
| `faction_blueprint.json` | `tools/adamrogue/` | 派系蓝图：定义 Mod 关心的 24 个内容派系节点（**需手动维护**） |

主生成器自动定位工作区根目录下的 `OriginalGameData/db` 作为数据源。

---

## 二、主生成器产出物

运行 `regenerate_stage_d_data.ps1` 后会生成或覆盖：

| 产出 | 说明 |
|------|------|
| `script/.../adamrogue_data_nodes.lua` | 目的地节点 |
| `script/.../adamrogue_data_battle_pools.lua` | 战斗单位池、敌将、英雄池 |
| `script/.../adamrogue_data_ancillaries.lua` | 装备奖励池 |
| `script/.../adamrogue_data_players.lua` | 全派系玩家支持数据 |
| `script/.../adamrogue_data_enemy_skills_*.lua` | 各节点敌军技能计划 |
| `script/.../adamrogue_data_enemy_skills.lua` | 技能子模块加载器 |
| `db/ancillaries_tables/!!adamrogue_all_faction_set_all.tsv` | 装备 faction_set 全派系解锁 |
| `db/campaign_payload_ui_details_tables/...` | 目的地 UI 图标 |
| `text/db/` 中节点相关本地化块 | 中英文节点名称与选项文案 |

---

## 三、各类内容的自动适配能力

### 兵种（战斗单位池）— 基本能自动

**数据来源**：`units_custom_battle_permissions_tables` + `main_units_tables`

**纳入规则**：
- 按蓝图里每个派系的 `battle_permissions_keys` / `culture_key` 收集
- 自动排除 `campaign_exclusive`、将领/英雄单位、价值分 ≤ 0 的单位
- 自动推导 `weight`、`min/max_battle_tier`、`role_tag`

| 情况 | 是否自动 |
|------|----------|
| 旧派系新增兵种，且已进入 custom battle 权限表 | 是 |
| 单位只在 `main_units_tables` 中，未进 custom battle 权限 | 否 |
| 全新种族 / 新目的地节点 | 否，需补蓝图 |

---

### 领主（敌将 / 玩家将领）— 大部分能自动

**敌将**：从 custom battle 中 `general_unit=true` 且 `caste=lord` 的单位推导；蓝图可指定 `enemy_general_subtype`，未指定则取最便宜候选。

**玩家将领**：扫描 `start_pos_factions_tables` 中所有 `playable=true` 的派系，从 `faction_agent_permitted_subtypes_tables` 取 `agent=general` 的可招募将领。

| 情况 | 是否自动 |
|------|----------|
| 现有派系新增可玩领主 / 可战斗敌将（数据表齐全） | 是 |
| 全新 DLC 派系 | 否，需补 `faction_blueprint.json` |
| 新 `cdir_military_generator_config` 值 | 可能需补 `generate_stage_d_data.py` 中的 `PLAYER_CONTENT_NODE_BY_GENERATOR_CONFIG` 映射 |
| 蓝图写死的 `enemy_general_subtype` 在新版被删/改名 | 否，生成脚本报错退出 |

---

### 英雄（敌军英雄池 / 英雄奖励）— 半自动

**敌军英雄池**（主生成器）：
- 来源：`faction_agent_permitted_subtypes_tables` 的非 general 条目
- 要求 `recruitable`、`can_gain_xp`，关联单位 `caste=hero`

**英雄奖励 UI / db**（`update_hero_reward_metadata.py`）：
- 不读原游戏表，而是从**已生成**的 `adamrogue_data_battle_pools.lua` 正则提取英雄
- 为每个英雄补 payload 图标 key、中英文候选文案

英雄奖励需**两步**：先跑主生成器，再跑 `update_hero_reward_metadata.py`。

---

### 装备 — 大部分能自动，有筛选

**数据来源**：`ancillaries_tables` + `faction_set_items_tables` + 稀有度分组表

**自动纳入**：武器 / 护甲 / 饰品 / 附魔 / 秘法物品；`faction_set=all` 的通用装备；匹配派系 / culture / subculture 的派系装备。

**自动排除**：`legendary_item=true`、绑定特定 agent subtype 的装备、角色专属高阶套装（set key 含 character/lord/hero）、scrap 类。

脚本还会生成 `!!adamrogue_all_faction_set_all.tsv`，将 Mod 池内装备 `faction_set` 改为 `all`，确保任意派系可领取。

**局限**：新装备若 faction_set 规则特殊可能进不了池；装备轮次开放仍由 `adamrogue_balance_config.lua` 控制，脚本只负责建池。

---

### 技能 — 能自动，覆盖相关 subtype

**数据来源**：整套 `character_skill_*` 表

为敌将、嵌入事务官、敌军英雄、玩家将领等 subtype 生成技能计划；只保留 `character` / `battle` 类，排除 immortality、mentor 等。

**局限**：新将领若未进入上述池，技能也不会生成；部分 subtype 缺技能时脚本输出 `[WARN]` 但不退出。

---

## 四、不能一键适配的场景

| 场景 | 需要做什么 |
|------|-----------|
| 旧派系增量内容（兵种/将领/装备/技能，数据表齐全） | 更新 `OriginalGameData` 后重跑脚本即可 |
| 全新种族 / 新目的地节点 | 补 `faction_blueprint.json` |
| 新可玩派系（非蓝图主派系） | 多数靠 subculture / generator_config 自动映射；映射不到则改脚本映射表 |
| 新单位未进 custom battle 权限 | 不会自动进战斗池 |
| 英雄奖励 db / 本地化 | 主生成器后额外跑 `update_hero_reward_metadata.py` |
| 平衡参数、流程逻辑 | 脚本不处理，改 `adamrogue_balance_config.lua` / `adamrogue_mvp.lua` |

---

## 五、推荐更新流程

```
1. 用新版游戏数据更新工作区 OriginalGameData/db
2. 运行 tools/adamrogue/regenerate_stage_d_data.ps1
3. 若使用英雄奖励功能，再运行 update_hero_reward_metadata.py
4. 检查终端输出的 [WARN] / [ERROR]
5. 若有新派系 / 新节点，修改 faction_blueprint.json 后重跑
6. 进游戏做 spot check（抽几个派系验证单位池、装备、敌将技能）
```

### 命令参考

```powershell
# 主数据再生成（含 luac 语法检查）
.\tools\adamrogue\regenerate_stage_d_data.ps1

# 英雄奖励元数据（需在主生成器之后）
D:\SoftWares\miniforge3\python.exe .\tools\adamrogue\update_hero_reward_metadata.py
```

---

## 六、终端输出怎么看

| 标记 | 含义 | 处理 |
|------|------|------|
| `[OK]` | 正常生成统计 | 可对比前后数量变化 |
| `[WARN]` | 非致命问题（如某派系装备池为空、某 subtype 无技能） | 评估是否影响玩法，决定是否手改蓝图或规则 |
| `[ERROR]` | 致命校验失败（如蓝图配置的敌将 subtype 不存在） | 必须修复后重跑，脚本会退出 |

常见需关注的 warning：
- `No faction equipment entries generated for ...` — 该派系装备池为空
- `No character skill node set found for subtype ...` — 该将领无技能计划
- `Skipping playable faction ... because no content-faction mapping could be resolved` — 新可玩派系未映射到内容派系

---

## 七、设计原则（一句话）

> 以 `faction_blueprint.json` 定义 Mod 关心的内容派系节点；其余从原游戏 db 全量抽取 + 规则过滤 + 自动派生。

因此对**现有派系内的增量更新**，成本很低；对**全新派系或特殊数据来源**，仍需维护蓝图和少量脚本映射。
