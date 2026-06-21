local data = {}

data.PLAYER_GENERAL_SUBTYPE = "wh3_main_cth_lord_magistrate_yang"
data.PLAYER_GENERAL_SUBTYPES = {
    "wh3_main_cth_lord_magistrate_yang",
    "wh3_main_cth_lord_magistrate_yin",
    "wh3_main_cth_dragon_blooded_shugengan_yang",
    "wh3_main_cth_dragon_blooded_shugengan_yin"
}
data.PLAYER_GENERAL_OPTIONS = {
    {
        subtype = "wh3_main_cth_lord_magistrate_yang",
        unit_key = "wh3_main_cth_cha_lord_magistrate_0",
        unit_value = 2100
    },
    {
        subtype = "wh3_main_cth_lord_magistrate_yin",
        unit_key = "wh3_main_cth_cha_lord_magistrate_0",
        unit_value = 2100
    },
    {
        subtype = "wh3_main_cth_dragon_blooded_shugengan_yang",
        unit_key = "wh3_main_cth_cha_dragon_blooded_shugengan_lord_yang_0",
        unit_value = 2100
    },
    {
        subtype = "wh3_main_cth_dragon_blooded_shugengan_yin",
        unit_key = "wh3_main_cth_cha_dragon_blooded_shugengan_lord_yin_0",
        unit_value = 2100
    }
}
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
