from __future__ import annotations

import csv
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CN_LOC_FILE_NAME = "adamrogue_mvp_CN.loc.tsv"
EN_LOC_FILE_NAME = "!!adamrogue_mvp_EN.loc.tsv"


def find_workspace_root() -> Path:
    for candidate in [REPO_ROOT, *REPO_ROOT.parents]:
        if (candidate / "Localisation").exists():
            return candidate
    raise FileNotFoundError("Could not locate workspace root containing Localisation.")


WORKSPACE_ROOT = find_workspace_root()
LOCALISATION_ROOT = WORKSPACE_ROOT / "Localisation"


def read_loc(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data

    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        try:
            next(reader)
        except StopIteration:
            return data

        for row in reader:
            if not row or row[0].startswith("#"):
                continue
            data[row[0]] = row[1] if len(row) > 1 else ""

    return data


def append_tsv_unique(path: Path, rows: list[list[object]], key_indices: list[int]) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    existing: set[tuple[str, ...]] = set()

    for line in lines[1:]:
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        existing.add(tuple(parts[index] if index < len(parts) else "" for index in key_indices))

    for row in rows:
        row_values = [str(value) for value in row]
        key = tuple(row_values[index] if index < len(row_values) else "" for index in key_indices)
        if key not in existing:
            lines.append("\t".join(row_values))
            existing.add(key)

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


TRANSLATION_REF_PATTERN = re.compile(r"^\{\{tr:([^}]+)\}\}$")


def resolve_translation_ref(value: str, table: dict[str, str]) -> str:
    for _ in range(4):
        match = TRANSLATION_REF_PATTERN.match(value or "")
        if not match:
            return value or ""
        value = table.get(match.group(1), value)
    return value or ""


def resolve_hero_name(subtype_key: str, unit_key: str, table: dict[str, str]) -> str:
    candidate_keys = [
        f"agent_subtypes_onscreen_name_override_{subtype_key}",
        f"land_units_onscreen_name_{unit_key}",
    ]
    for key in candidate_keys:
        value = resolve_translation_ref(table.get(key, ""), table)
        if value:
            return value
    return subtype_key


def collect_unique_heroes() -> list[tuple[str, str, str]]:
    battle_pools_path = REPO_ROOT / "script" / "campaign" / "mod" / "adamrogue" / "adamrogue_data_battle_pools.lua"
    text = battle_pools_path.read_text(encoding="utf-8")
    matches = re.findall(
        r'\{ agent_type = "([^"]+)", agent_subtype = "([^"]+)", unit_key = "([^"]+)"',
        text,
    )

    heroes: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for agent_type, subtype_key, unit_key in matches:
        if subtype_key not in seen:
            seen.add(subtype_key)
            heroes.append((agent_type, subtype_key, unit_key))

    return heroes


def update_db_tables(hero_subtypes: list[str]) -> None:
    append_tsv_unique(
        REPO_ROOT / "db" / "dilemmas_tables" / "!!adamrogue_mvp_dilemmas.tsv",
        [
            ["adamrogue_mvp_hero_reward_dilemma", "false", "dummy", "dummy", "agent", "false", "Event", "", "", "", "false"],
            ["adamrogue_mvp_hero_reward_full_dilemma", "false", "dummy", "dummy", "warning", "false", "Event", "", "", "", "false"],
        ],
        [0],
    )
    append_tsv_unique(
        REPO_ROOT
        / "db"
        / "cdir_events_dilemma_choice_details_tables"
        / "!!adamrogue_mvp_dilemma_choice_details.tsv",
        [[choice, "adamrogue_mvp_hero_reward_dilemma", "", ""] for choice in ["FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH"]]
        + [["FIRST", "adamrogue_mvp_hero_reward_full_dilemma", "", ""]],
        [0, 1],
    )
    append_tsv_unique(
        REPO_ROOT
        / "db"
        / "cdir_events_dilemma_option_junctions_tables"
        / "!!adamrogue_mvp_dilemma_option_junctions.tsv",
        [
            ["610190006", "adamrogue_mvp_hero_reward_dilemma", "VAR_CHANCE", "100", "default"],
            ["610190007", "adamrogue_mvp_hero_reward_full_dilemma", "VAR_CHANCE", "100", "default"],
        ],
        [1],
    )
    append_tsv_unique(
        REPO_ROOT
        / "db"
        / "campaign_payload_ui_details_tables"
        / "!!adamrogue_mvp_campaign_payload_ui_details.tsv",
        [[f"adamrogue_hero_reward_payload_{subtype_key}", "UI/skins/default/icon_agent.png", "default", "0"] for subtype_key in hero_subtypes],
        [0],
    )


def update_loc_tables(heroes: list[tuple[str, str, str]]) -> None:
    loc_en: dict[str, str] = {}
    for filename in ["agent_subtypes__.loc.tsv", "land_units__.loc.tsv"]:
        loc_en.update(read_loc(LOCALISATION_ROOT / "local_en" / "text" / "db" / filename))
    loc_cn = read_loc(LOCALISATION_ROOT / "local_cn" / "localisation__.loc.tsv")

    base_cn = [
        ["dilemmas_localised_title_adamrogue_mvp_hero_reward_dilemma", "战锤尖塔：英雄奖励", "false"],
        ["dilemmas_localised_description_adamrogue_mvp_hero_reward_dilemma", "本轮你可以从自己派系的 3 名随机英雄中选择 1 名加入部队。英雄会获得到当前轮数的等级。选择英雄后将跳过本轮单位奖励。", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaFIRST", "选择这位英雄", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaFIRST", "你很不错！", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaSECOND", "选择这位英雄", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaSECOND", "跟上队伍。", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaTHIRD", "选择这位英雄", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaTHIRD", "还是你来吧。", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaFOURTH", "稍后再选", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaFOURTH", "关闭事件，之后可通过 Mod 按钮重新打开该事件。", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaFIFTH", "切换到普通单位奖励", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaFIFTH", "放弃本轮英雄奖励，改为进入正常单位奖励事件。", "false"],
        ["dilemmas_localised_title_adamrogue_mvp_hero_reward_full_dilemma", "战锤尖塔：部队已满员", "false"],
        ["dilemmas_localised_description_adamrogue_mvp_hero_reward_full_dilemma", "当前部队已经达到 20 个单位，无法加入英雄。请先关闭事件窗调整部队，或返回奖励页面选择其他处理方式。", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_full_dilemmaFIRST", "返回奖励页面", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_full_dilemmaFIRST", "回到英雄奖励候选。", "false"],
    ]
    base_en = [
        ["dilemmas_localised_title_adamrogue_mvp_hero_reward_dilemma", "Warhammer Spire: Hero Reward", "false"],
        ["dilemmas_localised_description_adamrogue_mvp_hero_reward_dilemma", "This round, you may choose 1 of 3 random heroes from your own faction to join your force. Choosing a hero will skip this round's unit reward.", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaFIRST", "Claim Hero Candidate I", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaFIRST", "Claim the first hero shown below. If the army has room, this hero will join your current Rogue force and be raised to the current turn level.", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaSECOND", "Claim Hero Candidate II", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaSECOND", "Claim the second hero shown below. If the army has room, this hero will join your current Rogue force and be raised to the current turn level.", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaTHIRD", "Claim Hero Candidate III", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaTHIRD", "Claim the third hero shown below. If the army has room, this hero will join your current Rogue force and be raised to the current turn level.", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaFOURTH", "Choose Later", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaFOURTH", "Close this event for now. You can reopen the same set of hero candidates later from the Warhammer Spire button.", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_dilemmaFIFTH", "Switch to Normal Unit Reward", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_dilemmaFIFTH", "Give up this round's hero reward and proceed to the normal unit reward event instead. The regular battle flow will still follow.", "false"],
        ["dilemmas_localised_title_adamrogue_mvp_hero_reward_full_dilemma", "Warhammer Spire: Army Is Full", "false"],
        ["dilemmas_localised_description_adamrogue_mvp_hero_reward_full_dilemma", "Your current Rogue force has already reached 20 units, so no additional hero can join. Adjust your army capacity first, or return to the reward page and choose another option.", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_label_adamrogue_mvp_hero_reward_full_dilemmaFIRST", "Return to Reward Page", "false"],
        ["cdir_events_dilemma_choice_details_localised_choice_title_adamrogue_mvp_hero_reward_full_dilemmaFIRST", "Return to the previous page of hero reward candidates.", "false"],
    ]

    hero_rows_cn = []
    hero_rows_en = []
    for _, subtype_key, unit_key in heroes:
        hero_rows_cn.append(
            [
                f"campaign_payload_ui_details_description_adamrogue_hero_reward_payload_{subtype_key}",
                f"[[col:yellow]]候选英雄：{resolve_hero_name(subtype_key, unit_key, loc_cn)}[[/col]]",
                "false",
            ]
        )
        hero_rows_en.append(
            [
                f"campaign_payload_ui_details_description_adamrogue_hero_reward_payload_{subtype_key}",
                f"[[col:yellow]]Hero candidate: {resolve_hero_name(subtype_key, unit_key, loc_en)}[[/col]]",
                "false",
            ]
        )

    append_tsv_unique(REPO_ROOT / "text" / "db" / CN_LOC_FILE_NAME, base_cn + hero_rows_cn, [0])
    append_tsv_unique(REPO_ROOT / "text" / "db" / EN_LOC_FILE_NAME, base_en + hero_rows_en, [0])


def main() -> None:
    heroes = collect_unique_heroes()
    hero_subtypes = [subtype_key for _, subtype_key, _ in heroes]
    update_db_tables(hero_subtypes)
    update_loc_tables(heroes)
    print(f"[OK] Updated hero reward metadata. unique_heroes={len(heroes)}")


if __name__ == "__main__":
    main()
