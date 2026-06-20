local data = {}

data.EQUIPMENT_RARITY = {
    COMMON = "common",
    UNCOMMON = "uncommon",
    RARE = "rare"
}

data.EQUIPMENT_REWARD_SLOT = {
    WEAPON = "weapon_slot",
    ARMOUR = "armour_slot",
    ACCESSORY = "accessory_slot"
}

data.EQUIPMENT_REWARD_SLOT_ORDER = {
    data.EQUIPMENT_REWARD_SLOT.WEAPON,
    data.EQUIPMENT_REWARD_SLOT.ARMOUR,
    data.EQUIPMENT_REWARD_SLOT.ACCESSORY
}

data.EQUIPMENT_REWARD_POOL = {
    { item_key = "wh3_main_anc_weapon_serpent_fang", item_category = "weapon", item_rarity = "common", weight = 6, min_battle_tier = 1, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.WEAPON },
    { item_key = "wh3_main_anc_weapon_vermillion_blade", item_category = "weapon", item_rarity = "common", weight = 6, min_battle_tier = 1, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.WEAPON },
    { item_key = "wh_main_anc_weapon_sword_of_might", item_category = "weapon", item_rarity = "common", weight = 5, min_battle_tier = 1, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.WEAPON },
    { item_key = "wh3_main_anc_weapon_blade_of_xen_wu", item_category = "weapon", item_rarity = "uncommon", weight = 5, min_battle_tier = 2, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.WEAPON },
    { item_key = "wh3_main_anc_weapon_nuku_chos_crossbow", item_category = "weapon", item_rarity = "uncommon", weight = 4, min_battle_tier = 2, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.WEAPON },
    { item_key = "wh3_cp1_anc_weapon_cth_dragon_forged_blade", item_category = "weapon", item_rarity = "uncommon", weight = 4, min_battle_tier = 2, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.WEAPON },
    { item_key = "wh3_main_anc_weapon_dawn_glaive", item_category = "weapon", item_rarity = "rare", weight = 4, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.WEAPON },
    { item_key = "wh3_main_anc_weapon_spirit_qilin_spear", item_category = "weapon", item_rarity = "rare", weight = 3, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.WEAPON },
    { item_key = "wh3_cp1_anc_weapon_cth_desert_sun_claw", item_category = "weapon", item_rarity = "rare", weight = 3, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.WEAPON },

    { item_key = "wh_main_anc_armour_charmed_shield", item_category = "armour", item_rarity = "common", weight = 6, min_battle_tier = 1, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ARMOUR },
    { item_key = "wh_main_anc_armour_dragonhelm", item_category = "armour", item_rarity = "common", weight = 6, min_battle_tier = 1, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ARMOUR },
    { item_key = "wh_main_anc_armour_enchanted_shield", item_category = "armour", item_rarity = "common", weight = 5, min_battle_tier = 1, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ARMOUR },
    { item_key = "wh_main_anc_armour_gamblers_armour", item_category = "armour", item_rarity = "uncommon", weight = 5, min_battle_tier = 2, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ARMOUR },
    { item_key = "wh_main_anc_armour_helm_of_discord", item_category = "armour", item_rarity = "uncommon", weight = 4, min_battle_tier = 2, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ARMOUR },
    { item_key = "wh3_cp1_anc_armour_cth_ascendant_tiger", item_category = "armour", item_rarity = "uncommon", weight = 4, min_battle_tier = 2, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ARMOUR },
    { item_key = "wh3_cp1_anc_armour_cth_claw_plate", item_category = "armour", item_rarity = "rare", weight = 4, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ARMOUR },
    { item_key = "wh3_cp1_anc_armour_cth_serpent_scales", item_category = "armour", item_rarity = "rare", weight = 4, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ARMOUR },
    { item_key = "wh2_dlc10_dwf_anc_armour_starmetal_plate_caravan", item_category = "armour", item_rarity = "rare", weight = 2, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ARMOUR },

    { item_key = "wh3_main_anc_talisman_jet_amulet", item_category = "talisman", item_rarity = "common", weight = 6, min_battle_tier = 1, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY },
    { item_key = "wh_main_anc_talisman_obsidian_trinket", item_category = "talisman", item_rarity = "common", weight = 5, min_battle_tier = 1, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY },
    { item_key = "wh_main_anc_enchanted_item_potion_of_foolhardiness", item_category = "enchanted_item", item_rarity = "common", weight = 5, min_battle_tier = 1, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY },
    { item_key = "wh3_main_anc_talisman_crystal_of_kunlan", item_category = "talisman", item_rarity = "uncommon", weight = 5, min_battle_tier = 2, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY },
    { item_key = "wh3_cp1_anc_talisman_cth_arcane_trinket", item_category = "talisman", item_rarity = "uncommon", weight = 5, min_battle_tier = 2, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY },
    { item_key = "wh3_main_anc_enchanted_item_astromancers_spyglass", item_category = "enchanted_item", item_rarity = "uncommon", weight = 4, min_battle_tier = 2, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY },
    { item_key = "wh3_main_anc_talisman_jade_amulet", item_category = "talisman", item_rarity = "rare", weight = 4, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY },
    { item_key = "wh3_cp1_anc_enchanted_item_heavens_gate", item_category = "enchanted_item", item_rarity = "rare", weight = 4, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY },
    { item_key = "wh3_main_anc_caravan_sky_titan_relic", item_category = "arcane_item", item_rarity = "rare", weight = 3, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY },
    { item_key = "wh3_main_anc_caravan_statue_of_zharr", item_category = "enchanted_item", item_rarity = "rare", weight = 3, min_battle_tier = 3, max_battle_tier = 3, enabled = true, reward_slot = data.EQUIPMENT_REWARD_SLOT.ACCESSORY }
}

return data
