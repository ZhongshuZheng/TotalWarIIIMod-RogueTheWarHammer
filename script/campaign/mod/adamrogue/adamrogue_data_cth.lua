local data = {}

data.PLAYER_GENERAL_SUBTYPE = "wh3_main_cth_lord_magistrate_yang"
data.PLAYER_STARTING_UNITS = table.concat({
    "wh3_main_cth_inf_jade_warriors_0",
    "wh3_main_cth_inf_jade_warriors_0",
    "wh3_main_cth_inf_jade_warrior_crossbowmen_0"
}, ",")

data.ENEMY_GENERAL_SUBTYPE = "wh3_main_cth_lord_magistrate_yin"
data.ENEMY_EMBEDDED_AGENT_SUBTYPE = "wh3_main_cth_alchemist"
data.DEFAULT_ENEMY_FACTION_KEY = "wh3_main_cth_cathay_rebels"

-- Prefer dedicated Cathay rebel / battle-only factions so cleanup and forced war stay isolated from core campaign factions.
data.ENEMY_FACTION_CANDIDATES = {
    "wh3_main_cth_cathay_rebels",
    "wh3_main_cth_cathay_qb2",
    "wh3_main_cth_cathay_qb3",
    "wh3_main_cth_rebel_lords_of_nan_yang",
    "wh3_main_cth_dissenter_lords_of_jinshen"
}

data.REWARD_UNITS_BY_CHOICE = {
    [0] = "wh3_main_cth_inf_dragon_guard_0",
    [1] = "wh3_main_cth_inf_dragon_guard_crossbowmen_0",
    [2] = "wh3_main_cth_cav_jade_lancers_0"
}

data.BATTLE_TIER = {
    EARLY = 1,
    MID = 2,
    LATE = 3
}

data.CATHAY_BATTLE_UNIT_POOL = {
    { unit_key = "wh3_main_cth_inf_peasant_spearmen_1", unit_value = 350, min_battle_tier = 1, max_battle_tier = 3, weight = 8, role_tag = "frontline" },
    { unit_key = "wh3_main_cth_inf_peasant_archers_0", unit_value = 400, min_battle_tier = 1, max_battle_tier = 3, weight = 8, role_tag = "missile" },
    { unit_key = "wh3_main_cth_inf_jade_warriors_0", unit_value = 525, min_battle_tier = 1, max_battle_tier = 3, weight = 10, role_tag = "frontline" },
    { unit_key = "wh3_main_cth_inf_jade_warriors_1", unit_value = 650, min_battle_tier = 1, max_battle_tier = 3, weight = 8, role_tag = "anti_large" },
    { unit_key = "wh3_main_cth_inf_jade_warrior_crossbowmen_0", unit_value = 600, min_battle_tier = 1, max_battle_tier = 3, weight = 8, role_tag = "missile" },
    { unit_key = "wh3_main_cth_inf_jade_warrior_crossbowmen_1", unit_value = 650, min_battle_tier = 1, max_battle_tier = 3, weight = 6, role_tag = "missile" },
    { unit_key = "wh3_main_cth_cav_peasant_horsemen_0", unit_value = 400, min_battle_tier = 1, max_battle_tier = 2, weight = 4, role_tag = "flanker" },
    { unit_key = "wh3_main_cth_cav_jade_lancers_0", unit_value = 800, min_battle_tier = 1, max_battle_tier = 3, weight = 5, role_tag = "shock" },
    { unit_key = "wh3_main_cth_inf_iron_hail_gunners_0", unit_value = 500, min_battle_tier = 2, max_battle_tier = 3, weight = 4, role_tag = "close_range" },
    { unit_key = "wh3_main_cth_inf_crane_gunners_0", unit_value = 1000, min_battle_tier = 2, max_battle_tier = 3, weight = 3, role_tag = "sniper" },
    { unit_key = "wh3_main_cth_inf_dragon_guard_0", unit_value = 1000, min_battle_tier = 2, max_battle_tier = 3, weight = 4, role_tag = "elite_frontline" },
    { unit_key = "wh3_main_cth_inf_dragon_guard_crossbowmen_0", unit_value = 1000, min_battle_tier = 2, max_battle_tier = 3, weight = 4, role_tag = "elite_missile" },
    { unit_key = "wh3_main_cth_inf_grenadiers", unit_value = 500, min_battle_tier = 2, max_battle_tier = 3, weight = 2, role_tag = "burst_missile" },
    { unit_key = "wh3_main_cth_veh_war_compass_0", unit_value = 950, min_battle_tier = 2, max_battle_tier = 3, weight = 2, role_tag = "support" },
    { unit_key = "wh3_main_cth_art_grand_cannon_0", unit_value = 900, min_battle_tier = 2, max_battle_tier = 3, weight = 2, role_tag = "artillery" },
    { unit_key = "wh3_main_cth_veh_sky_lantern_0", unit_value = 800, min_battle_tier = 2, max_battle_tier = 3, weight = 2, role_tag = "flying_support" },
    { unit_key = "wh3_main_cth_cav_jade_longma_riders_0", unit_value = 1350, min_battle_tier = 3, max_battle_tier = 3, weight = 2, role_tag = "elite_flanker" },
    { unit_key = "wh3_main_cth_mon_terracotta_sentinel_0", unit_value = 1600, min_battle_tier = 3, max_battle_tier = 3, weight = 2, role_tag = "monster" },
    { unit_key = "wh3_main_cth_art_fire_rain_rocket_battery_0", unit_value = 1100, min_battle_tier = 3, max_battle_tier = 3, weight = 2, role_tag = "artillery" },
    { unit_key = "wh3_main_cth_veh_sky_junk_0", unit_value = 1500, min_battle_tier = 3, max_battle_tier = 3, weight = 1, role_tag = "flying_artillery" }
}

return data
