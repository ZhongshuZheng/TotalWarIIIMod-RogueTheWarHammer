local data = {}

data.DEFAULT_CURRENT_CYCLE = 1

data.CONFIG = {
    initial_player_value = 4500,
    initial_enemy_value = 3500,
    player_reward_value_multiplier = 1.00,
    enemy_value_multiplier = 1.00,
    enemy_growth = {
        { min_cycle = 1, max_cycle = 5, growth = 400, hero_num = 0 },
        { min_cycle = 6, max_cycle = 10, growth = 750, hero_num = 1 },
        { min_cycle = 11, max_cycle = 15, growth = 950, hero_num = 2 },
        { min_cycle = 16, max_cycle = 20, growth = 950, hero_num = 2 },
        { min_cycle = 21, max_cycle = 25, growth = 1050, hero_num = 3 },
        { min_cycle = 26, max_cycle = 30, growth = 1300, hero_num = 3 },
        { min_cycle = 31, max_cycle = nil, growth = 1450, hero_num = 3 }
    },
    player_reward_value = {
        { min_cycle = 1, max_cycle = 5, min_value = 300, max_value = 700, double_line = 0 },
        { min_cycle = 6, max_cycle = 10, min_value = 300, max_value = 1000, double_line = 501 },
        { min_cycle = 11, max_cycle = 15, min_value = 700, max_value = 1200, double_line = 901 },
        { min_cycle = 16, max_cycle = 20, min_value = 1000, max_value = 1500, double_line = 1201 },
        { min_cycle = 21, max_cycle = 25, min_value = 1200, max_value = 2000, double_line = 1500 },
        { min_cycle = 26, max_cycle = 30, min_value = 1500, max_value = 2500, double_line = 1551 },
        { min_cycle = 31, max_cycle = nil, min_value = 1500, max_value = 5000, double_line = 1601 }
    },
    equipment_rarity_by_cycle = {
        { min_cycle = 1, max_cycle = 5, tiers = { "common", "uncommon" } },
        { min_cycle = 6, max_cycle = 10, tiers = { "common", "uncommon", "rare" } },
        { min_cycle = 11, max_cycle = 15, tiers = { "common", "uncommon", "rare", "unique", "crafted" } },
        { min_cycle = 16, max_cycle = 20, tiers = { "uncommon", "rare", "unique", "crafted" } },
        { min_cycle = 21, max_cycle = 25, tiers = { "rare", "unique", "crafted" } },
        { min_cycle = 26, max_cycle = nil, tiers = { "rare", "unique", "crafted" } }
    },
    elite_battles = {
        battle_cycles = { 5, 10, 15, 20, 25, 30 },
        enemy_value_multiplier = 1.25,
        reward_highest_tier = true,
        -- false = 精英战禁用战前「自动战斗」；true = 允许自动战斗
        auto_battle_switch = false
    },
    enemy_unit_count = {
        minimum_units_base = 7,
        minimum_units_per_cycle = 1,
        hard_cap = 20,
        minimum_units_from_cycle_11 = 18,
        full_stack_from_cycle_19 = true
    }
}

return data
