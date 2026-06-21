from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT_PATH = REPO_ROOT / "tools" / "adamrogue" / "faction_blueprint.json"
START_MARKER = "# AUTO-GENERATED NODE LOC START"
END_MARKER = "# AUTO-GENERATED NODE LOC END"

COMMON_EQUIPMENT_POOL = [
    ("wh_main_anc_weapon_sword_of_might", "weapon", "common", 6, 1, 3, "WEAPON"),
    ("wh_main_anc_armour_charmed_shield", "armour", "common", 6, 1, 3, "ARMOUR"),
    ("wh_main_anc_armour_dragonhelm", "armour", "common", 5, 1, 3, "ARMOUR"),
    ("wh_main_anc_armour_enchanted_shield", "armour", "common", 5, 1, 3, "ARMOUR"),
    ("wh_main_anc_armour_gamblers_armour", "armour", "uncommon", 5, 2, 3, "ARMOUR"),
    ("wh_main_anc_armour_helm_of_discord", "armour", "uncommon", 4, 2, 3, "ARMOUR"),
    ("wh_main_anc_talisman_obsidian_trinket", "talisman", "common", 5, 1, 3, "ACCESSORY"),
    ("wh_main_anc_enchanted_item_potion_of_foolhardiness", "enchanted_item", "common", 5, 1, 3, "ACCESSORY"),
]

ALLOWED_ANCILLARY_CATEGORIES = {"weapon", "armour", "talisman", "enchanted_item", "arcane_item"}


def find_workspace_root() -> Path:
    for candidate in [REPO_ROOT, *REPO_ROOT.parents]:
        if (candidate / "OriginalGameData" / "db").exists():
            return candidate
    raise FileNotFoundError("Could not locate workspace root containing OriginalGameData/db.")


WORKSPACE_ROOT = find_workspace_root()
ORIGINAL_DB_ROOT = WORKSPACE_ROOT / "OriginalGameData" / "db"


def read_tsv(table_name: str) -> list[dict[str, str]]:
    path = ORIGINAL_DB_ROOT / table_name / "data__.tsv"
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        header = next(reader)
        rows: list[dict[str, str]] = []
        for row in reader:
            if not row:
                continue
            if row[0].startswith("#"):
                continue
            if len(row) < len(header):
                row.extend([""] * (len(header) - len(row)))
            rows.append({key: value for key, value in zip(header, row)})
    return rows


def load_blueprint() -> list[dict[str, object]]:
    with BLUEPRINT_PATH.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list) or not data:
        raise ValueError("Faction blueprint must be a non-empty list.")
    return data


def to_int(raw: str, default: int = 0) -> int:
    try:
        return int(float(raw))
    except (TypeError, ValueError):
        return default


def natural_sort_key(value: str) -> list[object]:
    return [int(token) if token.isdigit() else token for token in re.split(r"(\d+)", value)]


def lua_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def build_destination_payload_component_key(node_key: str) -> str:
    return f"adamrogue_destination_payload_choice_{node_key}"


def build_destination_current_payload_component_key(node_key: str) -> str:
    return f"adamrogue_destination_payload_current_{node_key}"


def build_index(rows: list[dict[str, str]], key_name: str) -> dict[str, dict[str, str]]:
    return {row[key_name]: row for row in rows if row.get(key_name)}


def replace_block(path: Path, generated_lines: list[str]) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    try:
        start_index = lines.index(START_MARKER)
        end_index = lines.index(END_MARKER)
    except ValueError as exc:
        raise RuntimeError(f"Missing marker in {path}") from exc
    if end_index <= start_index:
        raise RuntimeError(f"Invalid marker order in {path}")

    new_lines = lines[: start_index + 1] + generated_lines + lines[end_index:]
    path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")


def format_lua_key(key: str) -> str:
    return key if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) else f'["{key}"]'


def derive_unit_weight(unit_value: int) -> int:
    if unit_value <= 350:
        return 8
    if unit_value <= 550:
        return 7
    if unit_value <= 800:
        return 6
    if unit_value <= 1100:
        return 4
    if unit_value <= 1400:
        return 3
    if unit_value <= 1700:
        return 2
    return 1


def derive_battle_tier(unit_tier: int, unit_value: int) -> tuple[int, int]:
    if unit_tier <= 1 or unit_value <= 450:
        return 1, 3
    if unit_tier <= 3:
        return 2, 3
    return 3, 3


def derive_role_tag(main_unit: dict[str, str], unit_key: str) -> str:
    caste = (main_unit.get("caste") or "").lower()
    ui_group = (main_unit.get("ui_unit_group_land") or "").lower()
    missile_cp = to_int(main_unit.get("missile_cp", "0"))
    is_monstrous = (main_unit.get("is_monstrous") or "").lower() == "true"

    if unit_key.startswith("wh") and "_art_" in unit_key:
        return "artillery"
    if caste == "warmachine":
        return "artillery"
    if is_monstrous or caste in {"monster", "beast", "monstrous_cavalry", "monstrous_infantry"}:
        return "monster"
    if "_cav_" in unit_key or "cavalry" in caste or "chariot" in caste:
        return "shock"
    if missile_cp > 0:
        return "missile"
    if "spear" in ui_group or "halberd" in ui_group:
        return "anti_large"
    return "frontline"


def derive_ancillary_reward_slot(category: str) -> str:
    if category == "weapon":
        return "WEAPON"
    if category == "armour":
        return "ARMOUR"
    return "ACCESSORY"


def derive_ancillary_rarity(uniqueness_score: int) -> tuple[str, int, int, int]:
    if uniqueness_score <= 90:
        return "common", 6, 1, 3
    if uniqueness_score <= 140:
        return "uncommon", 4, 2, 3
    if uniqueness_score <= 180:
        return "rare", 3, 3, 3
    if uniqueness_score <= 199:
        return "unique", 2, 3, 3
    return "legendary", 1, 3, 3


def is_high_tier_character_specific_set(set_key: str, set_items: list[dict[str, str]]) -> bool:
    lowered_key = (set_key or "").lower()
    if not lowered_key:
        return False

    # Stage E only asks us to remove legendary lord/hero exclusive equipment.
    # Keep broader condition-gated and faction-locked high-tier sets available.
    if "character" in lowered_key or "lord" in lowered_key or "hero" in lowered_key:
        return True
    return False


def build_enemy_faction_candidates(
    blueprint_entry: dict[str, object],
    available_factions: set[str],
) -> list[str]:
    qb_prefix = str(blueprint_entry.get("enemy_qb_prefix") or blueprint_entry["culture_key"])
    qb_candidates = sorted(
        [key for key in available_factions if key.startswith(qb_prefix)],
        key=natural_sort_key,
    )
    fallback_candidates = [
        str(value)
        for value in blueprint_entry.get("fallback_enemy_factions", [])
        if str(value) in available_factions
    ]

    combined: list[str] = []
    for faction_key in qb_candidates[:3] + fallback_candidates:
        if faction_key not in combined:
            combined.append(faction_key)
    return combined


def render_nodes_module(blueprint: list[dict[str, object]]) -> str:
    lines = [
        "local data = {}",
        "",
        "-- AUTO-GENERATED by tools/adamrogue/generate_stage_d_data.py.",
        'data.STARTING_NODE_KEY = "cathay"',
        "",
        "data.NODE_POOL = {",
    ]
    for entry in blueprint:
        node_key = str(entry["node_key"])
        faction_key = str(entry["faction_key"])
        culture_key = str(entry["culture_key"])
        lines.extend(
            [
                "    {",
                f"        node_key = {lua_string(node_key)},",
                f"        faction_key = {lua_string(faction_key)},",
                f"        culture_key = {lua_string(culture_key)},",
                f"        display_name_key = {lua_string('adamrogue_destination_node_name_' + node_key)},",
                f"        choice_text_key = {lua_string('adamrogue_destination_node_choice_' + node_key)},",
                "        enabled = true",
                "    },",
            ]
        )
    lines.extend(["}", "", "return data", ""])
    return "\n".join(lines)


def render_campaign_payload_ui_details_table(blueprint: list[dict[str, object]]) -> str:
    lines = [
        "component\ticon\tstate\tsort_order",
        "#campaign_payload_ui_details_tables;2;db/campaign_payload_ui_details_tables/!!adamrogue_mvp_campaign_payload_ui_details.tsv\t\t\t",
    ]

    for entry in blueprint:
        node_key = str(entry["node_key"])
        lines.append(f"{build_destination_payload_component_key(node_key)}\tUI/skins/default/icon_alert_message.png\tdefault\t0")
        lines.append(
            f"{build_destination_current_payload_component_key(node_key)}\tUI/skins/default/icon_alert_message.png\tdefault\t0"
        )

    lines.append("adamrogue_destination_payload_delay\tUI/skins/default/icon_alert_message.png\tdefault\t0")
    return "\n".join(lines) + "\n"


def render_battle_module(
    blueprint: list[dict[str, object]],
    battle_unit_pools: dict[str, list[dict[str, object]]],
    enemy_candidates: dict[str, list[str]],
    enemy_generals: dict[str, str],
    embedded_agents: dict[str, str],
) -> str:
    lines = [
        "local data = {}",
        "",
        "-- AUTO-GENERATED by tools/adamrogue/generate_stage_d_data.py.",
        f"data.DEFAULT_CONTENT_FACTION_KEY = {lua_string(str(blueprint[0]['faction_key']))}",
        f"data.DEFAULT_ENEMY_FACTION_KEY = {lua_string(enemy_candidates[str(blueprint[0]['faction_key'])][0])}",
        "",
        "data.ENEMY_FACTION_CANDIDATES_BY_CONTENT_FACTION = {",
    ]

    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        lines.append(f"    {format_lua_key(faction_key)} = {{")
        for candidate in enemy_candidates[faction_key]:
            lines.append(f"        {lua_string(candidate)},")
        lines.append("    },")
    lines.extend(["}", "", "data.ENEMY_GENERAL_SUBTYPE_BY_CONTENT_FACTION = {"])

    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        lines.append(f"    {format_lua_key(faction_key)} = {lua_string(enemy_generals[faction_key])},")
    lines.extend(["}", "", "data.ENEMY_EMBEDDED_AGENT_SUBTYPE_BY_CONTENT_FACTION = {"])

    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        lines.append(f"    {format_lua_key(faction_key)} = {lua_string(embedded_agents[faction_key])},")
    lines.extend(["}", "", "data.BATTLE_UNIT_POOLS_BY_CONTENT_FACTION = {"])

    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        lines.append(f"    {format_lua_key(faction_key)} = {{")
        for unit_entry in battle_unit_pools[faction_key]:
            lines.append(
                "        { unit_key = "
                + lua_string(str(unit_entry["unit_key"]))
                + ", unit_value = "
                + str(unit_entry["unit_value"])
                + ", min_battle_tier = "
                + str(unit_entry["min_battle_tier"])
                + ", max_battle_tier = "
                + str(unit_entry["max_battle_tier"])
                + ", weight = "
                + str(unit_entry["weight"])
                + ", role_tag = "
                + lua_string(str(unit_entry["role_tag"]))
                + " },"
            )
        lines.append("    },")
    lines.extend(["}", "", "return data", ""])
    return "\n".join(lines)


def render_ancillary_module(
    blueprint: list[dict[str, object]],
    faction_equipment_pools: dict[str, list[dict[str, object]]],
) -> str:
    lines = [
        "local data = {}",
        "",
        "-- AUTO-GENERATED by tools/adamrogue/generate_stage_d_data.py.",
        "",
        "data.EQUIPMENT_RARITY = {",
        '    COMMON = "common",',
        '    UNCOMMON = "uncommon",',
        '    RARE = "rare",',
        '    UNIQUE = "unique",',
        '    LEGENDARY = "legendary"',
        "}",
        "",
        "data.EQUIPMENT_REWARD_SLOT = {",
        '    WEAPON = "weapon_slot",',
        '    ARMOUR = "armour_slot",',
        '    ACCESSORY = "accessory_slot"',
        "}",
        "",
        "data.EQUIPMENT_REWARD_SLOT_ORDER = {",
        "    data.EQUIPMENT_REWARD_SLOT.WEAPON,",
        "    data.EQUIPMENT_REWARD_SLOT.ARMOUR,",
        "    data.EQUIPMENT_REWARD_SLOT.ACCESSORY",
        "}",
        "",
        "data.COMMON_EQUIPMENT_POOL = {",
    ]

    for item_key, item_category, item_rarity, weight, min_tier, max_tier, reward_slot in COMMON_EQUIPMENT_POOL:
        lines.append(
            "    { item_key = "
            + lua_string(item_key)
            + ", item_category = "
            + lua_string(item_category)
            + ", item_rarity = "
            + lua_string(item_rarity)
            + ", weight = "
            + str(weight)
            + ", min_battle_tier = "
            + str(min_tier)
            + ", max_battle_tier = "
            + str(max_tier)
            + ", enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT."
            + reward_slot
            + " },"
        )

    lines.extend(["}", "", "data.FACTION_EQUIPMENT_POOLS = {"])
    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        lines.append(f"    {format_lua_key(faction_key)} = {{")
        for item in faction_equipment_pools[faction_key]:
            lines.append(
                "        { item_key = "
                + lua_string(str(item["item_key"]))
                + ", item_category = "
                + lua_string(str(item["item_category"]))
                + ", item_rarity = "
                + lua_string(str(item["item_rarity"]))
                + ", weight = "
                + str(item["weight"])
                + ", min_battle_tier = "
                + str(item["min_battle_tier"])
                + ", max_battle_tier = "
                + str(item["max_battle_tier"])
                + ", enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT."
                + str(item["reward_slot"])
                + " },"
            )
        lines.append("    },")
    lines.extend(
        [
            "}",
            "",
            "data.EQUIPMENT_REWARD_POOL = {}",
            "",
            "for _, entry in ipairs(data.COMMON_EQUIPMENT_POOL) do",
            "    data.EQUIPMENT_REWARD_POOL[#data.EQUIPMENT_REWARD_POOL + 1] = entry",
            "end",
            "",
            "for _, pool in pairs(data.FACTION_EQUIPMENT_POOLS) do",
            "    for _, entry in ipairs(pool) do",
            "        data.EQUIPMENT_REWARD_POOL[#data.EQUIPMENT_REWARD_POOL + 1] = entry",
            "    end",
            "end",
            "",
            "return data",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> None:
    blueprint = load_blueprint()

    factions_rows = read_tsv("factions_tables")
    start_pos_rows = read_tsv("start_pos_factions_tables")
    units_rows = read_tsv("units_custom_battle_permissions_tables")
    main_units_rows = read_tsv("main_units_tables")
    ancillary_rows = read_tsv("ancillaries_tables")
    faction_set_rows = read_tsv("faction_set_items_tables")

    factions_by_key = build_index(factions_rows, "key")
    main_units_by_key = build_index(main_units_rows, "unit")
    available_factions = {row["faction"] for row in start_pos_rows if row.get("faction")}

    units_by_battle_faction: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in units_rows:
        units_by_battle_faction[row["faction"]].append(row)

    faction_sets: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in faction_set_rows:
        if row.get("remove", "").lower() == "true":
            continue
        faction_sets[row["set"]].append(row)

    validation_errors: list[str] = []
    warnings: list[str] = []
    battle_unit_pools: dict[str, list[dict[str, object]]] = {}
    enemy_candidates: dict[str, list[str]] = {}
    enemy_generals: dict[str, str] = {}
    embedded_agents: dict[str, str] = {}
    faction_equipment_pools: dict[str, list[dict[str, object]]] = {}

    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        battle_faction_key = str(entry["culture_key"])

        faction_row = factions_by_key.get(faction_key)
        if faction_row is None:
            validation_errors.append(f"Missing faction row for {faction_key}")
            continue

        battle_permissions_keys = [str(value) for value in entry.get("battle_permissions_keys", [battle_faction_key])]
        battle_permissions: list[dict[str, str]] = []
        for permissions_key in battle_permissions_keys:
            battle_permissions.extend(units_by_battle_faction.get(permissions_key, []))
        if not battle_permissions:
            validation_errors.append(
                f"Missing custom battle permissions for {faction_key} via keys {','.join(battle_permissions_keys)}"
            )
            continue

        general_candidates: list[tuple[int, str]] = []
        unit_pool: list[dict[str, object]] = []
        for permission in battle_permissions:
            unit_key = permission["unit"]
            main_unit = main_units_by_key.get(unit_key)
            if main_unit is None:
                continue

            if permission.get("campaign_exclusive", "").lower() == "true":
                continue

            unit_value = to_int(main_unit.get("multiplayer_cost", "0"))
            if unit_value <= 0:
                continue

            caste = (main_unit.get("caste") or "").lower()
            if permission.get("general_unit", "").lower() == "true":
                if caste == "lord":
                    general_candidates.append((unit_value, unit_key))
                continue

            if caste in {"lord", "hero"}:
                continue

            unit_tier = to_int(main_unit.get("tier", "0"))
            min_tier, max_tier = derive_battle_tier(unit_tier, unit_value)
            unit_pool.append(
                {
                    "unit_key": unit_key,
                    "unit_value": unit_value,
                    "min_battle_tier": min_tier,
                    "max_battle_tier": max_tier,
                    "weight": derive_unit_weight(unit_value),
                    "role_tag": derive_role_tag(main_unit, unit_key),
                }
            )

        if not unit_pool:
            validation_errors.append(f"No battle units generated for {faction_key}")
            continue
        battle_unit_pools[faction_key] = sorted(unit_pool, key=lambda item: (int(item["unit_value"]), str(item["unit_key"])))

        if not general_candidates:
            validation_errors.append(f"No enemy general candidate found for {faction_key}")
            continue
        general_candidates.sort(key=lambda item: (item[0], item[1]))
        configured_general_subtype = str(entry.get("enemy_general_subtype") or "")
        available_general_keys = {candidate[1] for candidate in general_candidates}
        # Keep generic-lord overrides data-driven in the blueprint. The cheapest custom battle
        # lord is often a caster or a named/special entry, which is not what stage D wants.
        if configured_general_subtype:
            if configured_general_subtype not in available_general_keys:
                validation_errors.append(
                    f"Configured enemy_general_subtype {configured_general_subtype} is not available for {faction_key}"
                )
                continue
            enemy_generals[faction_key] = configured_general_subtype
        else:
            enemy_generals[faction_key] = general_candidates[0][1]
        embedded_agents[faction_key] = str(entry.get("embedded_agent_subtype") or "")

        faction_candidates = build_enemy_faction_candidates(entry, available_factions)
        if not faction_candidates:
            validation_errors.append(f"No enemy faction candidates found for {faction_key}")
            continue
        enemy_candidates[faction_key] = faction_candidates

        subculture_key = faction_row.get("subculture", "")
        equipment_pool: list[dict[str, object]] = []
        seen_items: set[str] = set()
        for ancillary in ancillary_rows:
            item_key = ancillary.get("key", "")
            item_category = ancillary.get("category", "")
            faction_set_key = ancillary.get("faction_set", "")

            if not item_key or item_key in seen_items:
                continue
            if item_category not in ALLOWED_ANCILLARY_CATEGORIES:
                continue
            if ancillary.get("legendary_item", "").lower() == "true":
                continue
            if faction_set_key in {"", "all"}:
                continue

            set_items = faction_sets.get(faction_set_key, [])
            if not set_items:
                continue

            matched = False
            for set_item in set_items:
                if set_item.get("faction") == faction_key:
                    matched = True
                    break
                if set_item.get("culture") == battle_faction_key:
                    matched = True
                    break
                if subculture_key and set_item.get("subculture") == subculture_key:
                    matched = True
                    break
            if not matched:
                continue

            uniqueness_score = to_int(ancillary.get("uniqueness_score", "0"))
            item_rarity, weight, min_tier, max_tier = derive_ancillary_rarity(uniqueness_score)
            if item_rarity in {"unique", "legendary"} and is_high_tier_character_specific_set(faction_set_key, set_items):
                continue
            equipment_pool.append(
                {
                    "item_key": item_key,
                    "item_category": item_category,
                    "item_rarity": item_rarity,
                    "weight": weight,
                    "min_battle_tier": min_tier,
                    "max_battle_tier": max_tier,
                    "reward_slot": derive_ancillary_reward_slot(item_category),
                }
            )
            seen_items.add(item_key)

        if not equipment_pool:
            warnings.append(f"No faction equipment entries generated for {faction_key}")
        faction_equipment_pools[faction_key] = sorted(
            equipment_pool,
            key=lambda item: (str(item["item_rarity"]), str(item["item_category"]), str(item["item_key"])),
        )

    if validation_errors:
        for error in validation_errors:
            print(f"[ERROR] {error}")
        raise SystemExit(1)

    nodes_module = render_nodes_module(blueprint)
    battle_module = render_battle_module(
        blueprint,
        battle_unit_pools,
        enemy_candidates,
        enemy_generals,
        embedded_agents,
    )
    ancillary_module = render_ancillary_module(blueprint, faction_equipment_pools)
    campaign_payload_ui_details_table = render_campaign_payload_ui_details_table(blueprint)

    (REPO_ROOT / "script" / "campaign" / "mod" / "adamrogue" / "adamrogue_data_nodes.lua").write_text(
        nodes_module,
        encoding="utf-8",
    )
    (REPO_ROOT / "script" / "campaign" / "mod" / "adamrogue" / "adamrogue_data_battle_pools.lua").write_text(
        battle_module,
        encoding="utf-8",
    )
    (REPO_ROOT / "script" / "campaign" / "mod" / "adamrogue" / "adamrogue_data_ancillaries.lua").write_text(
        ancillary_module,
        encoding="utf-8",
    )
    (REPO_ROOT / "db" / "campaign_payload_ui_details_tables").mkdir(parents=True, exist_ok=True)
    (REPO_ROOT / "db" / "campaign_payload_ui_details_tables" / "!!adamrogue_mvp_campaign_payload_ui_details.tsv").write_text(
        campaign_payload_ui_details_table,
        encoding="utf-8",
    )

    cn_loc_lines = []
    en_loc_lines = []
    for entry in blueprint:
        node_key = str(entry["node_key"])
        cn_name = str(entry["display_name_cn"])
        en_name = str(entry["display_name_en"])
        cn_loc_lines.append(f"adamrogue_destination_node_name_{node_key}\t{cn_name}\tfalse")
        cn_loc_lines.append(f"adamrogue_destination_node_choice_{node_key}\t候选派系：{cn_name}\tfalse")
        cn_loc_lines.append(
            f"campaign_payload_ui_details_description_{build_destination_payload_component_key(node_key)}\t[[col:yellow]]候选派系：{cn_name}[[/col]]\tfalse"
        )
        cn_loc_lines.append(
            f"campaign_payload_ui_details_description_{build_destination_current_payload_component_key(node_key)}\t[[col:yellow]]当前派系：{cn_name}[[/col]]\tfalse"
        )
        en_loc_lines.append(f"adamrogue_destination_node_name_{node_key}\t{en_name}\tfalse")
        en_loc_lines.append(f"adamrogue_destination_node_choice_{node_key}\tCandidate Faction: {en_name}\tfalse")
        en_loc_lines.append(
            f"campaign_payload_ui_details_description_{build_destination_payload_component_key(node_key)}\t[[col:yellow]]Candidate Faction: {en_name}[[/col]]\tfalse"
        )
        en_loc_lines.append(
            f"campaign_payload_ui_details_description_{build_destination_current_payload_component_key(node_key)}\t[[col:yellow]]Current Faction: {en_name}[[/col]]\tfalse"
        )

    cn_loc_lines.append(
        "campaign_payload_ui_details_description_adamrogue_destination_payload_delay\t[[col:yellow]]保留当前候选，下次点击入口时继续选择。[[/col]]\tfalse"
    )
    en_loc_lines.append(
        "campaign_payload_ui_details_description_adamrogue_destination_payload_delay\t[[col:yellow]]Keep the current destination candidates and choose again later through the entry button.[[/col]]\tfalse"
    )

    replace_block(REPO_ROOT / "text" / "db" / "adamrogue_mvp_CN.loc.tsv", cn_loc_lines)
    replace_block(REPO_ROOT / "text" / "db" / "en" / "adamrogue_mvp_EN.loc.tsv", en_loc_lines)

    print(f"[OK] Generated nodes for {len(blueprint)} factions.")
    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        print(
            "[OK] "
            + faction_key
            + f" units={len(battle_unit_pools[faction_key])}"
            + f" equipment={len(faction_equipment_pools[faction_key])}"
            + f" enemy_candidates={len(enemy_candidates[faction_key])}"
        )
    for warning in warnings:
        print(f"[WARN] {warning}")


if __name__ == "__main__":
    main()
