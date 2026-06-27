if not get_mct then
    return
end

local mct = get_mct()
local mod = mct:register_mod("adamrogue_roguemod")

mod:set_title("mct_adamrogue_title")
mod:set_author("mct_adamrogue_author")
mod:set_description("mct_adamrogue_description")

mod:add_new_section("adamrogue_main_section", "mct_adamrogue_main_section")

local player_reward_value_multiplier = mod:add_new_option("player_reward_value_multiplier", "slider")
player_reward_value_multiplier:set_text("mct_adamrogue_player_reward_multiplier_text")
player_reward_value_multiplier:set_tooltip_text("mct_adamrogue_player_reward_multiplier_tooltip")
player_reward_value_multiplier:slider_set_precision(2)
player_reward_value_multiplier:slider_set_step_size(0.05, 2)
player_reward_value_multiplier:slider_set_min_max(0, 3)
player_reward_value_multiplier:set_default_value(1)

local enemy_value_multiplier = mod:add_new_option("enemy_value_multiplier", "slider")
enemy_value_multiplier:set_text("mct_adamrogue_enemy_value_multiplier_text")
enemy_value_multiplier:set_tooltip_text("mct_adamrogue_enemy_value_multiplier_tooltip")
enemy_value_multiplier:slider_set_precision(2)
enemy_value_multiplier:slider_set_step_size(0.05, 2)
enemy_value_multiplier:slider_set_min_max(0, 3)
enemy_value_multiplier:set_default_value(1)

local auto_battle_switch = mod:add_new_option("auto_battle_switch", "checkbox")
auto_battle_switch:set_text("mct_adamrogue_auto_battle_switch_text")
auto_battle_switch:set_tooltip_text("mct_adamrogue_auto_battle_switch_tooltip")
auto_battle_switch:set_default_value(false)

local logging_enabled = mod:add_new_option("logging_enabled", "checkbox")
logging_enabled:set_text("mct_adamrogue_logging_enabled_text")
logging_enabled:set_tooltip_text("mct_adamrogue_logging_enabled_tooltip")
logging_enabled:set_default_value(false)
