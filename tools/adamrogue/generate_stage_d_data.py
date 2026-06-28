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
ANCILLARIES_OVERRIDE_OUTPUT_NAME = "!!adamrogue_all_faction_set_all.tsv"
CN_LOC_FILE_NAME = "adamrogue_mvp_CN.loc.tsv"
EN_LOC_FILE_NAME = "!!adamrogue_mvp_EN.loc.tsv"

ALLOWED_ANCILLARY_CATEGORIES = {"weapon", "armour", "talisman", "enchanted_item", "arcane_item"}
ALLOWED_SKILL_CATEGORIES = {"character", "battle"}
EXCLUDED_SKILL_NODE_KEYS = {
    "wh3_main_agent_action_scaling",
}
EXCLUDED_SKILL_KEY_PATTERNS = (
    "immortality",
    "mentor",
)
# Legendary lords available in custom battle but omitted from faction_agent_permitted_subtypes.
EXTRA_GENERAL_SUBTYPES_BY_CONTENT_FACTION: dict[str, list[str]] = {
    "wh3_dlc23_chd_astragoth": [
        "wh3_dlc23_chd_zhatan",
        "wh3_dlc23_chd_astragoth",
        "wh3_dlc23_chd_drazhoath",
    ],
}
PLAYER_CONTENT_NODE_BY_GENERATOR_CONFIG = {
    "WH_Cathay": "cathay",
    "WH_Kislev": "kislev",
    "WH_Ogre_Kingdoms": "ogres",
    "WH_Khorne": "khorne",
    "WH_Nurgle": "nurgle",
    "WH_Tzeentch": "tzeentch",
    "WH_Slaanesh": "slaanesh",
    "WH_Chaos_Dwarfs": "chaos_dwarfs",
    "WH_Empire": "empire",
    "WH_Dwarfs": "dwarfs",
    "WH_Greenskins": "greenskins",
    "WH_Vampire_Counts": "vampire_counts",
    "WH_Bretonnia": "bretonnia",
    "WH_Chaos": "warriors_of_chaos",
    "WH_Beastmen": "beastmen",
    "WH_Wood_Elves": "wood_elves",
    "WH_Wood_Elves_Drycha": "wood_elves",
    "WH_Norsca": "norsca",
    "WH_Norsca_Throgg": "norsca",
    "WH_High_Elves": "high_elves",
    "WH_High_Elves_Aislinn": "high_elves",
    "WH_Dark_Elves": "dark_elves",
    "WH_Lizardmen": "lizardmen",
    "WH_Skaven": "skaven",
    "WH_Tomb_Kings": "tomb_kings",
    "WH_Vampire_Coast_land": "vampire_coast",
    "WH_Chaos_Daemons": "daemons_of_chaos",
    "WH_CoC_Festus": "nurgle",
    "WH_CoC_Valkia": "khorne",
    "WH_CoC_Azazel": "slaanesh",
    "WH_CoC_Vilitch": "tzeentch",
}


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


def classify_player_general_lord_type(ui_unit_group_land: str) -> str:
    group = (ui_unit_group_land or "").strip().lower()
    if group == "lord":
        return "lord"
    if "wizard" in group:
        return "spellcaster_lord"
    return "lord"


def build_player_general_option_from_subtype(
    subtype_key: str,
    agent_subtypes_by_key: dict[str, dict[str, str]],
    main_units_by_key: dict[str, dict[str, str]],
) -> dict[str, object] | None:
    subtype_row = agent_subtypes_by_key.get(subtype_key)
    if subtype_row is None:
        return None
    if subtype_row.get("recruitable", "").lower() != "true":
        return None

    associated_unit_key = subtype_row.get("associated_unit_override", "")
    if not associated_unit_key:
        return None

    main_unit_row = main_units_by_key.get(associated_unit_key)
    if main_unit_row is None:
        return None
    if (main_unit_row.get("caste") or "").lower() != "lord":
        return None

    unit_value = to_int(main_unit_row.get("multiplayer_cost", "0"))
    if unit_value <= 0:
        unit_value = to_int(subtype_row.get("cost", "0"))
    if unit_value <= 0:
        return None

    return {
        "subtype": subtype_key,
        "unit_key": associated_unit_key,
        "unit_value": unit_value,
        "lord_type": classify_player_general_lord_type(main_unit_row.get("ui_unit_group_land", "")),
    }


def merge_player_general_options(option_lists: list[list[dict[str, object]]]) -> list[dict[str, object]]:
    by_subtype: dict[str, dict[str, object]] = {}
    for options in option_lists:
        for option in options:
            subtype_key = str(option.get("subtype") or "")
            if not subtype_key:
                continue
            existing = by_subtype.get(subtype_key)
            if existing is None or int(option.get("unit_value") or 0) > int(existing.get("unit_value") or 0):
                by_subtype[subtype_key] = option
    merged = list(by_subtype.values())
    merged.sort(key=lambda item: (int(item["unit_value"]), str(item["subtype"])))
    return merged


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


def derive_hero_weight(unit_value: int) -> int:
    if unit_value <= 1000:
        return 4
    if unit_value <= 1500:
        return 3
    if unit_value <= 2000:
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


def canonicalize_ancillary_rarity(group_key: str, ui_state: str) -> str | None:
    lowered_group_key = (group_key or "").lower()
    lowered_ui_state = (ui_state or "").lower()

    if "scrap" in lowered_group_key:
        return None
    if "unique" in lowered_group_key:
        return "unique"
    if "crafted" in lowered_group_key or "rune" in lowered_group_key:
        return "crafted"
    if lowered_ui_state in {"common", "uncommon", "rare"}:
        return lowered_ui_state
    if lowered_ui_state == "legendary":
        return "unique"
    if lowered_ui_state == "crafted":
        return "crafted"
    return None


def build_ancillary_rarity_lookup(group_rows: list[dict[str, str]]) -> dict[int, tuple[str, int, int, int]]:
    rarity_lookup: dict[int, tuple[str, int, int, int]] = {}

    for row in group_rows:
        uniqueness_min = to_int(row.get("uniqueness_min", "0"))
        uniqueness_max = to_int(row.get("uniqueness_max", "0"))
        if uniqueness_min < 0 or uniqueness_max < 0:
            continue

        rarity_key = canonicalize_ancillary_rarity(row.get("group_key", ""), row.get("ui_state", ""))
        if not rarity_key:
            continue

        if rarity_key == "common":
            rarity_payload = ("common", 6, 1, 3)
        elif rarity_key == "uncommon":
            rarity_payload = ("uncommon", 4, 2, 3)
        elif rarity_key == "rare":
            rarity_payload = ("rare", 3, 3, 3)
        elif rarity_key == "crafted":
            rarity_payload = ("crafted", 2, 3, 3)
        else:
            rarity_payload = ("unique", 1, 3, 3)

        for score in range(min(uniqueness_min, uniqueness_max), max(uniqueness_min, uniqueness_max) + 1):
            rarity_lookup[score] = rarity_payload

    return rarity_lookup


def derive_ancillary_rarity(uniqueness_score: int, rarity_lookup: dict[int, tuple[str, int, int, int]]) -> tuple[str, int, int, int]:
    if uniqueness_score in rarity_lookup:
        return rarity_lookup[uniqueness_score]

    if uniqueness_score <= 50:
        return "common", 6, 1, 3
    if uniqueness_score <= 100:
        return "uncommon", 4, 2, 3
    if uniqueness_score <= 150:
        return "rare", 3, 3, 3
    if uniqueness_score <= 199:
        return "crafted", 2, 3, 3
    return "unique", 1, 3, 3


def is_high_tier_character_specific_set(set_key: str, set_items: list[dict[str, str]]) -> bool:
    lowered_key = (set_key or "").lower()
    if not lowered_key:
        return False

    # Stage E only asks us to remove top-tier lord/hero exclusive equipment.
    # Keep broader condition-gated and faction-locked high-tier sets available.
    if "character" in lowered_key or "lord" in lowered_key or "hero" in lowered_key:
        return True
    return False


def should_skip_ancillary_for_reward_pool(
    ancillary: dict[str, str],
    ancillary_keys_with_included_agent_subtypes: set[str],
    ancillary_keys_with_skill_requirements: set[str],
    ancillary_keys_with_included_agents: set[str],
) -> bool:
    item_key = ancillary.get("key", "")
    if not item_key:
        return True
    if ancillary.get("category", "") not in ALLOWED_ANCILLARY_CATEGORIES:
        return True
    if ancillary.get("legendary_item", "").lower() == "true":
        return True
    if item_key in ancillary_keys_with_included_agent_subtypes:
        return True
    if item_key in ancillary_keys_with_skill_requirements:
        return True
    if item_key in ancillary_keys_with_included_agents:
        return True
    return False


def build_equipment_pool_entry(
    ancillary: dict[str, str],
    ancillary_rarity_lookup: dict[int, tuple[str, int, int, int]],
) -> dict[str, object]:
    item_key = ancillary.get("key", "")
    item_category = ancillary.get("category", "")
    uniqueness_score = to_int(ancillary.get("uniqueness_score", "0"))
    item_rarity, weight, min_tier, max_tier = derive_ancillary_rarity(uniqueness_score, ancillary_rarity_lookup)
    return {
        "item_key": item_key,
        "item_category": item_category,
        "item_rarity": item_rarity,
        "weight": weight,
        "min_battle_tier": min_tier,
        "max_battle_tier": max_tier,
        "reward_slot": derive_ancillary_reward_slot(item_category),
    }


def build_common_equipment_pool(
    ancillary_rows: list[dict[str, str]],
    ancillary_keys_with_included_agent_subtypes: set[str],
    ancillary_keys_with_skill_requirements: set[str],
    ancillary_keys_with_included_agents: set[str],
    ancillary_rarity_lookup: dict[int, tuple[str, int, int, int]],
) -> list[dict[str, object]]:
    equipment_pool: list[dict[str, object]] = []
    seen_items: set[str] = set()

    for ancillary in ancillary_rows:
        if should_skip_ancillary_for_reward_pool(
            ancillary,
            ancillary_keys_with_included_agent_subtypes,
            ancillary_keys_with_skill_requirements,
            ancillary_keys_with_included_agents,
        ):
            continue
        if ancillary.get("faction_set", "") != "all":
            continue

        item_key = ancillary.get("key", "")
        if item_key in seen_items:
            continue

        equipment_pool.append(build_equipment_pool_entry(ancillary, ancillary_rarity_lookup))
        seen_items.add(item_key)

    return sorted(
        equipment_pool,
        key=lambda item: (str(item["item_rarity"]), str(item["item_category"]), str(item["item_key"])),
    )


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
    enemy_general_options: dict[str, list[dict[str, object]]],
    enemy_general_values: dict[str, int],
    embedded_agents: dict[str, str],
    enemy_hero_pools: dict[str, list[dict[str, object]]],
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
    lines.extend(["}", "", "data.ENEMY_GENERAL_OPTIONS_BY_CONTENT_FACTION = {"])

    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        lines.append(f"    {format_lua_key(faction_key)} = {{")
        for option in enemy_general_options[faction_key]:
            lines.append(
                "        { agent_subtype = "
                + lua_string(str(option["agent_subtype"]))
                + ", unit_key = "
                + lua_string(str(option["unit_key"]))
                + ", unit_value = "
                + str(int(option["unit_value"]))
                + ", allowed_factions = { "
                + ", ".join(lua_string(str(candidate_key)) for candidate_key in option.get("allowed_factions", []))
                + " }"
                + " },"
            )
        lines.append("    },")
    lines.extend(["}", "", "data.ENEMY_GENERAL_UNIT_VALUE_BY_CONTENT_FACTION = {"])

    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        lines.append(f"    {format_lua_key(faction_key)} = {int(enemy_general_values[faction_key])},")
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
    lines.extend(["}", "", "data.ENEMY_HERO_POOLS_BY_CONTENT_FACTION = {"])

    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        lines.append(f"    {format_lua_key(faction_key)} = {{")
        for hero_entry in enemy_hero_pools.get(faction_key, []):
            lines.append(
                "        { agent_type = "
                + lua_string(str(hero_entry["agent_type"]))
                + ", agent_subtype = "
                + lua_string(str(hero_entry["agent_subtype"]))
                + ", unit_key = "
                + lua_string(str(hero_entry["unit_key"]))
                + ", unit_value = "
                + str(hero_entry["unit_value"])
                + ", weight = "
                + str(hero_entry["weight"])
                + " },"
            )
        lines.append("    },")
    lines.extend(["}", "", "return data", ""])
    return "\n".join(lines)


def render_ancillary_module(
    blueprint: list[dict[str, object]],
    faction_equipment_pools: dict[str, list[dict[str, object]]],
    common_equipment_pool: list[dict[str, object]],
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
        '    CRAFTED = "crafted"',
        "}",
        "",
        "data.EQUIPMENT_REWARD_SLOT = {",
        '    WEAPON = "weapon_slot",',
        '    ARMOUR = "armour_slot",',
        '    ACCESSORY = "accessory_slot",',
        '    ANY = "any_slot"',
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

    for item in common_equipment_pool:
        lines.append(
            "    { item_key = "
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


def render_players_module(
    supported_player_factions: list[str],
    player_content_faction_by_faction: dict[str, str],
    player_general_options_by_faction: dict[str, list[dict[str, object]]],
    preferred_default_content_faction_key: str,
) -> str:
    default_content_faction_key = ""
    default_faction_key = ""
    if supported_player_factions:
        if preferred_default_content_faction_key:
            if preferred_default_content_faction_key in supported_player_factions:
                default_content_faction_key = preferred_default_content_faction_key
                default_faction_key = preferred_default_content_faction_key
            for faction_key in supported_player_factions:
                if default_faction_key != "":
                    break
                if player_content_faction_by_faction.get(faction_key, "") == preferred_default_content_faction_key:
                    default_content_faction_key = preferred_default_content_faction_key
                    default_faction_key = faction_key
                    break

        if default_faction_key == "":
            for faction_key in supported_player_factions:
                resolved_content_faction_key = player_content_faction_by_faction.get(faction_key, "")
                if resolved_content_faction_key:
                    default_content_faction_key = resolved_content_faction_key
                    default_faction_key = faction_key
                    break
    lines = [
        "local data = {}",
        "",
        "-- AUTO-GENERATED by tools/adamrogue/generate_stage_d_data.py.",
        f"data.DEFAULT_SUPPORTED_PLAYER_FACTION_KEY = {lua_string(default_faction_key)}",
        f"data.DEFAULT_CONTENT_FACTION_KEY = {lua_string(default_content_faction_key)}",
        "",
        "data.SUPPORTED_PLAYER_FACTIONS = {",
    ]

    for faction_key in supported_player_factions:
        lines.append(f"    {format_lua_key(faction_key)} = true,")
    lines.extend(["}", "", "data.PLAYER_CONTENT_FACTION_BY_FACTION = {"])

    for faction_key in supported_player_factions:
        lines.append(
            f"    {format_lua_key(faction_key)} = {lua_string(player_content_faction_by_faction[faction_key])},"
        )
    lines.extend(["}", "", "data.PLAYER_GENERAL_OPTIONS_BY_FACTION = {"])

    for faction_key in supported_player_factions:
        lines.append(f"    {format_lua_key(faction_key)} = {{")
        for option in player_general_options_by_faction[faction_key]:
            lines.append(
                "        { subtype = "
                + lua_string(str(option["subtype"]))
                + ", unit_key = "
                + lua_string(str(option["unit_key"]))
                + ", unit_value = "
                + str(int(option["unit_value"]))
                + ", lord_type = "
                + lua_string(str(option.get("lord_type") or "lord"))
                + " },"
            )
        lines.append("    },")
    lines.extend(["}", "", "data.DEFAULT_PLAYER_GENERAL_SUBTYPE_BY_FACTION = {"])

    for faction_key in supported_player_factions:
        default_subtype = ""
        options = player_general_options_by_faction.get(faction_key, [])
        if options:
            default_subtype = str(options[0]["subtype"])
        lines.append(f"    {format_lua_key(faction_key)} = {lua_string(default_subtype)},")

    lines.extend(["}", "", "return data", ""])
    return "\n".join(lines)


def normalize_skill_category_key(category_key: str) -> str | None:
    lowered_key = (category_key or "").lower()
    if lowered_key.startswith("character"):
        return "character"
    if lowered_key.startswith("battle"):
        return "battle"
    if lowered_key.startswith("campaign"):
        return "campaign"
    return None


def resolve_skill_category_for_indent(
    indent: int,
    agent_subtype_key: str,
    category_rows: list[dict[str, str]],
) -> str | None:
    exact_matches: list[dict[str, str]] = []
    fallback_matches: list[dict[str, str]] = []

    for row in category_rows:
        min_indent = to_int(row.get("min_indent", "0"))
        max_indent = to_int(row.get("max_indent", "0"))
        if indent < min_indent or indent > max_indent:
            continue

        override_subtype = row.get("agent_subtype_override", "")
        if override_subtype and override_subtype == agent_subtype_key:
            exact_matches.append(row)
        elif not override_subtype:
            fallback_matches.append(row)

    for row in exact_matches + fallback_matches:
        resolved_category = normalize_skill_category_key(row.get("key", ""))
        if resolved_category:
            return resolved_category

    return None


def is_excluded_skill_entry(node_key: str, skill_key: str) -> bool:
    lowered_node_key = (node_key or "").lower()
    lowered_skill_key = (skill_key or "").lower()

    if node_key in EXCLUDED_SKILL_NODE_KEYS:
        return True

    for pattern in EXCLUDED_SKILL_KEY_PATTERNS:
        if pattern in lowered_node_key or pattern in lowered_skill_key:
            return True

    return False


def derive_skill_unlock_ranks_by_level(
    skill_key: str,
    skill_rows_by_key: dict[str, dict[str, str]],
    skill_level_detail_rows_by_skill: dict[str, list[dict[str, str]]],
) -> list[int]:
    detail_rows = sorted(
        skill_level_detail_rows_by_skill.get(skill_key, []),
        key=lambda row: to_int(row.get("level", "0"), 0),
    )
    default_unlock_rank = to_int(skill_rows_by_key.get(skill_key, {}).get("unlocked_at_rank", "0"), 0)

    if not detail_rows:
        return [default_unlock_rank]

    unlock_ranks_by_level: dict[int, int] = {}
    max_level = 1
    for row in detail_rows:
        level = max(1, to_int(row.get("level", "1"), 1))
        unlock_rank = to_int(row.get("unlocked_at_rank", "0"), default_unlock_rank)
        unlock_ranks_by_level[level] = unlock_rank
        if level > max_level:
            max_level = level

    resolved_unlock_ranks: list[int] = []
    for level in range(1, max_level + 1):
        resolved_unlock_ranks.append(unlock_ranks_by_level.get(level, default_unlock_rank))

    return resolved_unlock_ranks


def build_character_skill_plans_by_subtype(
    subtype_keys_by_content_faction: dict[str, set[str]],
    category_rows: list[dict[str, str]],
    skill_node_set_rows: list[dict[str, str]],
    skill_node_set_item_rows: list[dict[str, str]],
    skill_node_rows: list[dict[str, str]],
    skill_rows: list[dict[str, str]],
    skill_level_detail_rows: list[dict[str, str]],
    skill_lock_rows: list[dict[str, str]],
) -> tuple[dict[str, dict[str, list[dict[str, object]]]], list[str]]:
    skill_node_set_rows_by_subtype: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in skill_node_set_rows:
        subtype_key = row.get("agent_subtype_key", "")
        if subtype_key:
            skill_node_set_rows_by_subtype[subtype_key].append(row)

    skill_node_set_items_by_set: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in skill_node_set_item_rows:
        if row.get("mod_disabled", "").lower() == "true":
            continue
        set_key = row.get("set", "")
        if set_key:
            skill_node_set_items_by_set[set_key].append(row)

    skill_nodes_by_key = build_index(skill_node_rows, "key")
    skill_rows_by_key = build_index(skill_rows, "key")

    skill_level_detail_rows_by_skill: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in skill_level_detail_rows:
        skill_key = row.get("skill_key", "")
        if skill_key:
            skill_level_detail_rows_by_skill[skill_key].append(row)

    locked_node_keys_by_skill: dict[str, set[str]] = defaultdict(set)
    for row in skill_lock_rows:
        skill_key = row.get("character_skill", "")
        locked_node_key = row.get("character_skill_node", "")
        if skill_key and locked_node_key:
            locked_node_keys_by_skill[skill_key].add(locked_node_key)

    character_skill_plans_by_content_faction: dict[str, dict[str, list[dict[str, object]]]] = {}
    warnings: list[str] = []

    for content_faction_key, subtype_keys in subtype_keys_by_content_faction.items():
        subtype_plans: dict[str, list[dict[str, object]]] = {}

        for subtype_key in sorted(subtype_keys):
            set_rows = skill_node_set_rows_by_subtype.get(subtype_key, [])
            if not set_rows:
                warnings.append(
                    "No character skill node set found for subtype "
                    + subtype_key
                    + " under content faction "
                    + content_faction_key
                )
                continue

            skill_plan_entries: list[dict[str, object]] = []
            seen_node_keys: set[str] = set()
            seen_skill_keys: set[str] = set()

            for set_row in set_rows:
                set_key = set_row.get("key", "")
                if not set_key:
                    continue

                for item_row in skill_node_set_items_by_set.get(set_key, []):
                    node_key = item_row.get("item", "")
                    if not node_key or node_key in seen_node_keys:
                        continue

                    node_row = skill_nodes_by_key.get(node_key)
                    if node_row is None:
                        continue

                    skill_key = node_row.get("character_skill_key", "")
                    if not skill_key or skill_key in seen_skill_keys:
                        continue

                    resolved_category = resolve_skill_category_for_indent(
                        to_int(node_row.get("indent", "0"), 0),
                        subtype_key,
                        category_rows,
                    )
                    if resolved_category not in ALLOWED_SKILL_CATEGORIES:
                        continue

                    if is_excluded_skill_entry(node_key, skill_key):
                        continue

                    unlock_ranks_by_level = derive_skill_unlock_ranks_by_level(
                        skill_key,
                        skill_rows_by_key,
                        skill_level_detail_rows_by_skill,
                    )
                    locked_node_keys = sorted(locked_node_keys_by_skill.get(skill_key, set()), key=natural_sort_key)
                    skill_row = skill_rows_by_key.get(skill_key, {})
                    image_path = skill_row.get("image_path", "")
                    is_mount_skill = "_mount_" in skill_key or image_path.startswith("mount_")

                    skill_plan_entries.append(
                        {
                            "node_key": node_key,
                            "skill_key": skill_key,
                            "category_key": resolved_category,
                            "indent": to_int(node_row.get("indent", "0"), 0),
                            "tier": to_int(node_row.get("tier", "0"), 0),
                            "unlock_ranks_by_level": unlock_ranks_by_level,
                            "max_level": len(unlock_ranks_by_level),
                            "is_mount_skill": is_mount_skill,
                            "locked_node_keys": locked_node_keys,
                        }
                    )
                    seen_node_keys.add(node_key)
                    seen_skill_keys.add(skill_key)

            if not skill_plan_entries:
                warnings.append(
                    "No filtered character/battle skill entries generated for subtype "
                    + subtype_key
                    + " under content faction "
                    + content_faction_key
                )
                continue

            skill_plan_entries.sort(
                key=lambda entry: (
                    0 if entry["category_key"] == "character" else 1,
                    int(entry["indent"]),
                    int(entry["tier"]),
                    int(entry["unlock_ranks_by_level"][0] if entry["unlock_ranks_by_level"] else 0),
                    str(entry["node_key"]),
                )
            )
            subtype_plans[subtype_key] = skill_plan_entries

        character_skill_plans_by_content_faction[content_faction_key] = subtype_plans

    return character_skill_plans_by_content_faction, warnings


def render_enemy_skill_submodule(
    content_faction_key: str,
    skill_plans_by_subtype: dict[str, list[dict[str, object]]],
) -> str:
    lines = [
        "local data = {}",
        "",
        "-- AUTO-GENERATED by tools/adamrogue/generate_stage_d_data.py.",
        f"data.CONTENT_FACTION_KEY = {lua_string(content_faction_key)}",
        "",
        "data.CHARACTER_SKILL_PLANS_BY_SUBTYPE = {",
    ]

    for subtype_key in sorted(skill_plans_by_subtype, key=natural_sort_key):
        lines.append(f"    {format_lua_key(subtype_key)} = {{")
        for entry in skill_plans_by_subtype[subtype_key]:
            unlock_ranks_rendered = ", ".join(str(int(rank)) for rank in entry["unlock_ranks_by_level"])
            lines.extend(
                [
                    "        {",
                    f"            node_key = {lua_string(str(entry['node_key']))},",
                    f"            skill_key = {lua_string(str(entry['skill_key']))},",
                    f"            category_key = {lua_string(str(entry['category_key']))},",
                    f"            indent = {int(entry['indent'])},",
                    f"            tier = {int(entry['tier'])},",
                    f"            max_level = {int(entry['max_level'])},",
                    f"            is_mount_skill = {'true' if entry['is_mount_skill'] else 'false'},",
                    f"            unlock_ranks_by_level = {{ {unlock_ranks_rendered} }},",
                    "            locked_node_keys = {",
                ]
            )
            for locked_node_key in entry["locked_node_keys"]:
                lines.append(f"                {lua_string(str(locked_node_key))},")
            lines.extend(
                [
                    "            }",
                    "        },",
                ]
            )
        lines.append("    },")

    lines.extend(["}", "", "return data", ""])
    return "\n".join(lines)


def render_enemy_skill_loader(module_names: list[str]) -> str:
    lines = [
        "local data = {}",
        "",
        "-- AUTO-GENERATED by tools/adamrogue/generate_stage_d_data.py.",
        "data.CHARACTER_SKILL_PLANS_BY_SUBTYPE = {}",
        "data.CONTENT_FACTION_KEY_BY_SUBTYPE = {}",
        "",
    ]

    for index, module_name in enumerate(module_names, start=1):
        lines.append(f"local source_{index} = require({lua_string(module_name)})")
        lines.append(f"for subtype_key, skill_plan in pairs(source_{index}.CHARACTER_SKILL_PLANS_BY_SUBTYPE or {{}}) do")
        lines.append("    data.CHARACTER_SKILL_PLANS_BY_SUBTYPE[subtype_key] = skill_plan")
        lines.append(f"    data.CONTENT_FACTION_KEY_BY_SUBTYPE[subtype_key] = source_{index}.CONTENT_FACTION_KEY")
        lines.append("end")
        lines.append("")

    lines.extend(["return data", ""])
    return "\n".join(lines)


def build_blueprint_subculture_lookup(
    blueprint: list[dict[str, object]],
    factions_by_key: dict[str, dict[str, str]],
) -> dict[str, str]:
    subculture_to_content_faction: dict[str, str] = {}
    for entry in blueprint:
        faction_key = str(entry["faction_key"])
        faction_row = factions_by_key.get(faction_key)
        if not faction_row:
            continue
        subculture_key = faction_row.get("subculture", "")
        if subculture_key and subculture_key not in subculture_to_content_faction:
            subculture_to_content_faction[subculture_key] = faction_key
    return subculture_to_content_faction


def resolve_player_content_faction_key(
    faction_key: str,
    faction_row: dict[str, str],
    start_pos_row: dict[str, str],
    blueprint_by_node_key: dict[str, dict[str, object]],
    blueprint_faction_keys: set[str],
    blueprint_subculture_lookup: dict[str, str],
) -> tuple[str | None, str]:
    if faction_key in blueprint_faction_keys:
        return faction_key, "exact_blueprint_faction"

    generator_config = (start_pos_row.get("cdir_military_generator_config") or "").strip()
    if generator_config:
        mapped_node_key = PLAYER_CONTENT_NODE_BY_GENERATOR_CONFIG.get(generator_config)
        if mapped_node_key:
            blueprint_entry = blueprint_by_node_key.get(mapped_node_key)
            if blueprint_entry:
                return str(blueprint_entry["faction_key"]), "generator_config"

    subculture_key = (faction_row.get("subculture") or "").strip()
    if subculture_key and subculture_key in blueprint_subculture_lookup:
        return blueprint_subculture_lookup[subculture_key], "subculture"

    return None, "unresolved"


def build_ancillaries_faction_set_all_override(
    header: list[str],
    rows: list[dict[str, str]],
    ancillary_keys_with_included_agent_subtypes: set[str],
    ancillary_keys_with_skill_requirements: set[str],
    ancillary_keys_with_included_agents: set[str],
) -> str:
    output_header = "\t".join(header)
    output_meta = f"#ancillaries_tables;0;db/ancillaries_tables/{ANCILLARIES_OVERRIDE_OUTPUT_NAME}"
    category_key = "category"
    faction_set_key = "faction_set"
    output_rows = [output_header, output_meta]

    for row in rows:
        category = row.get(category_key, "")
        if category not in ALLOWED_ANCILLARY_CATEGORIES:
            continue
        if should_skip_ancillary_for_reward_pool(
            row,
            ancillary_keys_with_included_agent_subtypes,
            ancillary_keys_with_skill_requirements,
            ancillary_keys_with_included_agents,
        ):
            continue

        updated_row = []
        for column_key in header:
            if column_key == faction_set_key:
                updated_row.append("all")
            else:
                updated_row.append(row.get(column_key, ""))
        output_rows.append("\t".join(updated_row))

    return "\n".join(output_rows) + "\n"


def main() -> None:
    blueprint = load_blueprint()

    factions_rows = read_tsv("factions_tables")
    start_pos_rows = read_tsv("start_pos_factions_tables")
    faction_agent_permitted_subtype_rows = read_tsv("faction_agent_permitted_subtypes_tables")
    agent_subtype_rows = read_tsv("agent_subtypes_tables")
    units_rows = read_tsv("units_custom_battle_permissions_tables")
    main_units_rows = read_tsv("main_units_tables")
    ancillary_rows = read_tsv("ancillaries_tables")
    faction_set_rows = read_tsv("faction_set_items_tables")
    ancillary_group_rows = read_tsv("ancillary_uniqueness_groupings_tables")
    ancillary_included_agent_subtype_rows = read_tsv("ancillaries_included_agent_subtypes_tables")
    ancillaries_required_skills_rows = read_tsv("ancillaries_required_skills_tables")
    character_skill_level_to_ancillaries_rows = read_tsv("character_skill_level_to_ancillaries_junctions_tables")
    ancillary_to_included_agents_rows = read_tsv("ancillary_to_included_agents_tables")
    character_skill_category_rows = read_tsv("character_skill_categories_tables")
    character_skill_node_set_rows = read_tsv("character_skill_node_sets_tables")
    character_skill_node_set_item_rows = read_tsv("character_skill_node_set_items_tables")
    character_skill_node_rows = read_tsv("character_skill_nodes_tables")
    character_skill_rows = read_tsv("character_skills_tables")
    character_skill_level_detail_rows = read_tsv("character_skill_level_details_tables")
    character_skill_lock_rows = read_tsv("character_skill_nodes_skill_locks_tables")

    factions_by_key = build_index(factions_rows, "key")
    main_units_by_key = build_index(main_units_rows, "unit")
    agent_subtypes_by_key = build_index(agent_subtype_rows, "key")
    available_factions = {row["faction"] for row in start_pos_rows if row.get("faction")}
    blueprint_by_node_key = {str(entry["node_key"]): entry for entry in blueprint}
    blueprint_faction_keys = {str(entry["faction_key"]) for entry in blueprint}
    blueprint_subculture_lookup = build_blueprint_subculture_lookup(blueprint, factions_by_key)

    playable_start_pos_rows_by_faction: dict[str, dict[str, str]] = {}
    for row in start_pos_rows:
        faction_key = row.get("faction", "")
        if not faction_key:
            continue
        if (row.get("playable", "").lower() != "true"):
            continue
        if faction_key not in playable_start_pos_rows_by_faction or row.get("campaign") == "wh3_main_combi":
            playable_start_pos_rows_by_faction[faction_key] = row

    units_by_battle_faction: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in units_rows:
        units_by_battle_faction[row["faction"]].append(row)

    permitted_generals_by_faction: dict[str, list[str]] = defaultdict(list)
    permitted_heroes_by_faction: dict[str, list[str]] = defaultdict(list)
    for row in faction_agent_permitted_subtype_rows:
        if row.get("mod_disabled", "").lower() == "true":
            continue
        faction_key = row.get("faction", "")
        subtype_key = row.get("subtype", "")
        agent_type = row.get("agent", "")
        if not faction_key or not subtype_key:
            continue
        if agent_type == "general":
            permitted_generals_by_faction[faction_key].append(subtype_key)
        elif agent_type not in {"general", ""}:
            permitted_heroes_by_faction[faction_key].append(subtype_key)

    agent_subtypes_by_associated_unit: dict[str, list[str]] = defaultdict(list)
    for row in agent_subtype_rows:
        subtype_key = row.get("key", "")
        associated_unit_key = row.get("associated_unit_override", "")
        if not subtype_key or not associated_unit_key:
            continue
        if row.get("recruitable", "").lower() != "true":
            continue
        if row.get("can_gain_xp", "").lower() != "true":
            continue
        agent_subtypes_by_associated_unit[associated_unit_key].append(subtype_key)

    faction_sets: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in faction_set_rows:
        if row.get("remove", "").lower() == "true":
            continue
        faction_sets[row["set"]].append(row)

    ancillary_rarity_lookup = build_ancillary_rarity_lookup(ancillary_group_rows)
    ancillary_keys_with_included_agent_subtypes = {
        row.get("ancillary", "")
        for row in ancillary_included_agent_subtype_rows
        if row.get("ancillary", "")
    }
    ancillary_keys_with_skill_requirements = {
        row.get("ancillary", "")
        for row in ancillaries_required_skills_rows
        if row.get("ancillary", "")
    }
    ancillary_keys_with_skill_requirements.update(
        row.get("granted_ancillary", "")
        for row in character_skill_level_to_ancillaries_rows
        if row.get("granted_ancillary", "")
    )
    ancillary_keys_with_included_agents = {
        row.get("ancillary", "")
        for row in ancillary_to_included_agents_rows
        if row.get("ancillary", "")
    }

    validation_errors: list[str] = []
    warnings: list[str] = []
    battle_unit_pools: dict[str, list[dict[str, object]]] = {}
    enemy_candidates: dict[str, list[str]] = {}
    enemy_generals: dict[str, str] = {}
    enemy_general_options: dict[str, list[dict[str, object]]] = {}
    enemy_general_values: dict[str, int] = {}
    embedded_agents: dict[str, str] = {}
    enemy_hero_pools: dict[str, list[dict[str, object]]] = {}
    faction_equipment_pools: dict[str, list[dict[str, object]]] = {}
    supported_player_factions: list[str] = []
    player_content_faction_by_faction: dict[str, str] = {}
    player_general_options_by_faction: dict[str, list[dict[str, object]]] = {}
    player_mapping_summaries: list[str] = []

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

        # Build hero (non-lord agent) pool for this content faction.
        # Use the non-general permitted subtype list as the source of truth for which
        # agent subtypes are available, then verify the associated unit caste is "hero".
        permitted_hero_subtypes = set(permitted_heroes_by_faction.get(faction_key, []))
        agent_subtypes_by_key_local = {row["key"]: row for row in agent_subtype_rows if row.get("key")}
        hero_pool: list[dict[str, object]] = []
        seen_hero_subtype_keys: set[str] = set()
        for subtype_key in sorted(permitted_hero_subtypes, key=natural_sort_key):
            if subtype_key in seen_hero_subtype_keys:
                continue
            agent_row = agent_subtypes_by_key_local.get(subtype_key)
            if agent_row is None:
                continue
            if agent_row.get("recruitable", "").lower() != "true":
                continue
            if agent_row.get("can_gain_xp", "").lower() != "true":
                continue
            associated_unit_key = agent_row.get("associated_unit_override", "")
            if not associated_unit_key:
                continue
            main_unit = main_units_by_key.get(associated_unit_key)
            if main_unit is None:
                continue
            if (main_unit.get("caste") or "").lower() != "hero":
                continue
            unit_value = to_int(main_unit.get("multiplayer_cost", "0"))
            if unit_value <= 0:
                continue
            seen_hero_subtype_keys.add(subtype_key)
            # Determine the agent type from the permitted entry for this subtype.
            agent_type_for_subtype = next(
                (r["agent"] for r in faction_agent_permitted_subtype_rows
                 if r.get("faction") == faction_key and r.get("subtype") == subtype_key),
                "champion",
            )
            hero_pool.append(
                {
                    "agent_type": agent_type_for_subtype,
                    "agent_subtype": subtype_key,
                    "unit_key": associated_unit_key,
                    "unit_value": unit_value,
                    "weight": derive_hero_weight(unit_value),
                }
            )
        hero_pool.sort(key=lambda item: (int(item["unit_value"]), str(item["agent_subtype"])))
        enemy_hero_pools[faction_key] = hero_pool

        faction_candidates = build_enemy_faction_candidates(entry, available_factions)
        if not faction_candidates:
            validation_errors.append(f"No enemy faction candidates found for {faction_key}")
            continue
        enemy_candidates[faction_key] = faction_candidates

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
        general_value_by_unit_key = {unit_key: unit_value for unit_value, unit_key in general_candidates}
        enemy_general_values[faction_key] = int(general_value_by_unit_key[enemy_generals[faction_key]])

        permitted_general_subtypes = set(permitted_generals_by_faction.get(faction_key, []))
        patched_general_subtypes = set(EXTRA_GENERAL_SUBTYPES_BY_CONTENT_FACTION.get(faction_key, []))
        seen_general_option_keys: set[tuple[str, str]] = set()
        resolved_general_options: list[dict[str, object]] = []
        for unit_value, unit_key in general_candidates:
            subtype_candidates = sorted(agent_subtypes_by_associated_unit.get(unit_key, []), key=natural_sort_key)
            for subtype_key in subtype_candidates:
                if permitted_general_subtypes and subtype_key not in permitted_general_subtypes:
                    if subtype_key not in patched_general_subtypes:
                        continue

                # Testing: do not require subtype to appear in each QB faction's permitted list.
                allowed_factions = list(faction_candidates)

                dedupe_key = (subtype_key, unit_key)
                if dedupe_key in seen_general_option_keys:
                    continue
                seen_general_option_keys.add(dedupe_key)
                resolved_general_options.append(
                    {
                        "agent_subtype": subtype_key,
                        "unit_key": unit_key,
                        "unit_value": int(unit_value),
                        "allowed_factions": allowed_factions,
                    }
                )

        if not resolved_general_options:
            validation_errors.append(f"No enemy general agent subtype option found for {faction_key}")
            continue

        resolved_general_options.sort(
            key=lambda item: (int(item["unit_value"]), str(item["unit_key"]), natural_sort_key(str(item["agent_subtype"])))
        )
        enemy_general_options[faction_key] = resolved_general_options
        embedded_agents[faction_key] = str(entry.get("embedded_agent_subtype") or "")

        subculture_key = faction_row.get("subculture", "")
        equipment_pool: list[dict[str, object]] = []
        seen_items: set[str] = set()
        for ancillary in ancillary_rows:
            item_key = ancillary.get("key", "")
            item_category = ancillary.get("category", "")
            faction_set_key = ancillary.get("faction_set", "")

            if item_key in seen_items:
                continue
            if should_skip_ancillary_for_reward_pool(
                ancillary,
                ancillary_keys_with_included_agent_subtypes,
                ancillary_keys_with_skill_requirements,
                ancillary_keys_with_included_agents,
            ):
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
            item_rarity, weight, min_tier, max_tier = derive_ancillary_rarity(uniqueness_score, ancillary_rarity_lookup)
            if item_rarity in {"unique", "crafted"} and is_high_tier_character_specific_set(faction_set_key, set_items):
                continue
            equipment_pool.append(build_equipment_pool_entry(ancillary, ancillary_rarity_lookup))
            seen_items.add(item_key)

        if not equipment_pool:
            warnings.append(f"No faction equipment entries generated for {faction_key}")
        faction_equipment_pools[faction_key] = sorted(
            equipment_pool,
            key=lambda item: (str(item["item_rarity"]), str(item["item_category"]), str(item["item_key"])),
        )

    for faction_key, start_pos_row in sorted(playable_start_pos_rows_by_faction.items(), key=lambda item: item[0]):
        faction_row = factions_by_key.get(faction_key)
        if faction_row is None:
            warnings.append(f"Skipping playable faction {faction_key} because factions_tables row is missing.")
            continue

        resolved_content_faction_key, resolution = resolve_player_content_faction_key(
            faction_key,
            faction_row,
            start_pos_row,
            blueprint_by_node_key,
            blueprint_faction_keys,
            blueprint_subculture_lookup,
        )
        if not resolved_content_faction_key:
            warnings.append(
                "Skipping playable faction "
                + faction_key
                + " because no content-faction mapping could be resolved."
            )
            continue

        general_options: list[dict[str, object]] = []
        seen_general_subtypes: set[str] = set()
        for subtype_key in permitted_generals_by_faction.get(faction_key, []):
            if subtype_key in seen_general_subtypes:
                continue

            subtype_row = agent_subtypes_by_key.get(subtype_key)
            if subtype_row is None:
                continue
            if subtype_row.get("recruitable", "").lower() != "true":
                continue

            associated_unit_key = subtype_row.get("associated_unit_override", "")
            if not associated_unit_key:
                continue

            main_unit_row = main_units_by_key.get(associated_unit_key)
            if main_unit_row is None:
                continue
            if (main_unit_row.get("caste") or "").lower() != "lord":
                continue

            unit_value = to_int(main_unit_row.get("multiplayer_cost", "0"))
            if unit_value <= 0:
                unit_value = to_int(subtype_row.get("cost", "0"))
            if unit_value <= 0:
                continue

            general_options.append(
                {
                    "subtype": subtype_key,
                    "unit_key": associated_unit_key,
                    "unit_value": unit_value,
                    "lord_type": classify_player_general_lord_type(
                        main_unit_row.get("ui_unit_group_land", "")
                    ),
                }
            )
            seen_general_subtypes.add(subtype_key)

        for subtype_key in EXTRA_GENERAL_SUBTYPES_BY_CONTENT_FACTION.get(resolved_content_faction_key, []):
            if subtype_key in seen_general_subtypes:
                continue
            patched_option = build_player_general_option_from_subtype(
                subtype_key,
                agent_subtypes_by_key,
                main_units_by_key,
            )
            if patched_option is None:
                warnings.append(
                    "Could not add patched general option "
                    + subtype_key
                    + " for playable faction "
                    + faction_key
                )
                continue
            general_options.append(patched_option)
            seen_general_subtypes.add(subtype_key)

        if not general_options:
            warnings.append(
                "Skipping playable faction "
                + faction_key
                + " because no recruitable general options were found."
            )
            continue

        general_options.sort(key=lambda item: (int(item["unit_value"]), str(item["subtype"])))
        supported_player_factions.append(faction_key)
        player_content_faction_by_faction[faction_key] = resolved_content_faction_key
        player_general_options_by_faction[faction_key] = general_options
        player_mapping_summaries.append(
            "Playable faction mapping resolved: "
            + faction_key
            + " -> "
            + resolved_content_faction_key
            + f" ({resolution}), generals={len(general_options)} (pre-merge)"
        )

    options_by_content_faction: dict[str, list[list[dict[str, object]]]] = defaultdict(list)
    for faction_key in supported_player_factions:
        content_faction_key = player_content_faction_by_faction.get(faction_key, "")
        if not content_faction_key:
            continue
        options_by_content_faction[content_faction_key].append(player_general_options_by_faction[faction_key])

    merged_general_options_by_content_faction: dict[str, list[dict[str, object]]] = {}
    for content_faction_key, option_lists in options_by_content_faction.items():
        merged_general_options_by_content_faction[content_faction_key] = merge_player_general_options(option_lists)

    for faction_key in supported_player_factions:
        content_faction_key = player_content_faction_by_faction.get(faction_key, "")
        merged_options = merged_general_options_by_content_faction.get(content_faction_key)
        if merged_options is not None:
            player_general_options_by_faction[faction_key] = merged_options

    for content_faction_key, merged_options in sorted(merged_general_options_by_content_faction.items()):
        member_count = sum(
            1
            for faction_key in supported_player_factions
            if player_content_faction_by_faction.get(faction_key, "") == content_faction_key
        )
        player_mapping_summaries.append(
            "Shared player general pool for content faction "
            + content_faction_key
            + f": {len(merged_options)} options across {member_count} playable factions."
        )

    subtype_keys_by_content_faction: dict[str, set[str]] = defaultdict(set)
    for content_faction_key, subtype_key in enemy_generals.items():
        if subtype_key:
            if subtype_key in agent_subtypes_by_key:
                subtype_keys_by_content_faction[content_faction_key].add(subtype_key)
            else:
                for expanded_subtype_key in agent_subtypes_by_associated_unit.get(subtype_key, []):
                    subtype_keys_by_content_faction[content_faction_key].add(expanded_subtype_key)
    for content_faction_key, subtype_key in embedded_agents.items():
        if subtype_key:
            if subtype_key in agent_subtypes_by_key:
                subtype_keys_by_content_faction[content_faction_key].add(subtype_key)
            else:
                for expanded_subtype_key in agent_subtypes_by_associated_unit.get(subtype_key, []):
                    subtype_keys_by_content_faction[content_faction_key].add(expanded_subtype_key)
    for content_faction_key, hero_pool in enemy_hero_pools.items():
        for hero_entry in hero_pool:
            subtype_keys_by_content_faction[content_faction_key].add(str(hero_entry["agent_subtype"]))
    for player_faction_key, general_options in player_general_options_by_faction.items():
        content_faction_key = player_content_faction_by_faction.get(player_faction_key, "")
        if not content_faction_key:
            continue
        for general_option in general_options:
            subtype_key = str(general_option.get("subtype") or "")
            if subtype_key:
                subtype_keys_by_content_faction[content_faction_key].add(subtype_key)
    for content_faction_key, subtype_keys in EXTRA_GENERAL_SUBTYPES_BY_CONTENT_FACTION.items():
        for subtype_key in subtype_keys:
            subtype_keys_by_content_faction[content_faction_key].add(subtype_key)
    for content_faction_key, general_options in enemy_general_options.items():
        for general_option in general_options:
            subtype_key = str(general_option.get("agent_subtype") or "")
            if subtype_key:
                subtype_keys_by_content_faction[content_faction_key].add(subtype_key)

    if validation_errors:
        for error in validation_errors:
            print(f"[ERROR] {error}")
        raise SystemExit(1)

    common_equipment_pool = build_common_equipment_pool(
        ancillary_rows,
        ancillary_keys_with_included_agent_subtypes,
        ancillary_keys_with_skill_requirements,
        ancillary_keys_with_included_agents,
        ancillary_rarity_lookup,
    )

    nodes_module = render_nodes_module(blueprint)
    battle_module = render_battle_module(
        blueprint,
        battle_unit_pools,
        enemy_candidates,
        enemy_generals,
        enemy_general_options,
        enemy_general_values,
        embedded_agents,
        enemy_hero_pools,
    )
    ancillary_module = render_ancillary_module(blueprint, faction_equipment_pools, common_equipment_pool)
    players_module = render_players_module(
        supported_player_factions,
        player_content_faction_by_faction,
        player_general_options_by_faction,
        str(blueprint[0]["faction_key"]),
    )
    character_skill_plans_by_content_faction, character_skill_warnings = build_character_skill_plans_by_subtype(
        subtype_keys_by_content_faction,
        character_skill_category_rows,
        character_skill_node_set_rows,
        character_skill_node_set_item_rows,
        character_skill_node_rows,
        character_skill_rows,
        character_skill_level_detail_rows,
        character_skill_lock_rows,
    )
    ancillaries_faction_set_all_override = build_ancillaries_faction_set_all_override(
        list(ancillary_rows[0].keys()) if ancillary_rows else [],
        ancillary_rows,
        ancillary_keys_with_included_agent_subtypes,
        ancillary_keys_with_skill_requirements,
        ancillary_keys_with_included_agents,
    )
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
    (REPO_ROOT / "script" / "campaign" / "mod" / "adamrogue" / "adamrogue_data_players.lua").write_text(
        players_module,
        encoding="utf-8",
    )
    skill_module_names: list[str] = []
    for entry in blueprint:
        node_key = str(entry["node_key"])
        content_faction_key = str(entry["faction_key"])
        module_name = f"adamrogue_data_enemy_skills_{node_key}"
        skill_module_names.append(module_name)
        skill_submodule = render_enemy_skill_submodule(
            content_faction_key,
            character_skill_plans_by_content_faction.get(content_faction_key, {}),
        )
        (REPO_ROOT / "script" / "campaign" / "mod" / "adamrogue" / f"{module_name}.lua").write_text(
            skill_submodule,
            encoding="utf-8",
        )
    (REPO_ROOT / "script" / "campaign" / "mod" / "adamrogue" / "adamrogue_data_enemy_skills.lua").write_text(
        render_enemy_skill_loader(skill_module_names),
        encoding="utf-8",
    )
    (REPO_ROOT / "db" / "ancillaries_tables").mkdir(parents=True, exist_ok=True)
    (REPO_ROOT / "db" / "ancillaries_tables" / ANCILLARIES_OVERRIDE_OUTPUT_NAME).write_text(
        ancillaries_faction_set_all_override,
        encoding="utf-8-sig",
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
        "campaign_payload_ui_details_description_adamrogue_destination_payload_delay\t[[col:yellow]]Keep the current candidates and choose again the next time you press the button.[[/col]]\tfalse"
    )

    replace_block(REPO_ROOT / "text" / "db" / CN_LOC_FILE_NAME, cn_loc_lines)
    replace_block(REPO_ROOT / "text" / "db" / EN_LOC_FILE_NAME, en_loc_lines)

    print(f"[OK] Generated nodes for {len(blueprint)} factions.")
    print(f"[OK] Generated common equipment pool: {len(common_equipment_pool)}")
    print(f"[OK] Generated supported player factions: {len(supported_player_factions)}")
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
    for warning in character_skill_warnings:
        print(f"[WARN] {warning}")
    for summary in player_mapping_summaries:
        print(f"[OK] {summary}")
    for content_faction_key, subtype_keys in sorted(subtype_keys_by_content_faction.items(), key=lambda item: item[0]):
        print(
            "[OK] "
            + content_faction_key
            + f" skill_subtypes={len(subtype_keys)}"
            + f" generated_skill_plans={len(character_skill_plans_by_content_faction.get(content_faction_key, {}))}"
        )


if __name__ == "__main__":
    main()
