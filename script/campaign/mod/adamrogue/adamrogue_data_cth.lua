local data = {}

data.PLAYER_GENERAL_SUBTYPE = "wh3_main_cth_lord_magistrate_yang"
data.PLAYER_STARTING_UNITS = table.concat({
    "wh3_main_cth_inf_jade_warriors_0",
    "wh3_main_cth_inf_jade_warriors_0",
    "wh3_main_cth_inf_jade_warrior_crossbowmen_0"
}, ",")

data.BATTLE_TIER = {
    EARLY = 1,
    MID = 2,
    LATE = 3
}

return data
