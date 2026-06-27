local data = {}

data.DEFAULT_CURRENT_CYCLE = 1
data.DEFAULT_DIFFICULTY_LEVEL = "normal"

data.DIFFICULTY_LEVELS = {
    easy = {
        enemy_value_multiplier = 0.85,
        player_reward_value_multiplier = 1.15,
        elite_enemy_value_multiplier = 1.15
    },
    normal = {
        enemy_value_multiplier = 1.00,
        player_reward_value_multiplier = 1.00,
        elite_enemy_value_multiplier = 1.25
    },
    hard = {
        enemy_value_multiplier = 1.15,
        player_reward_value_multiplier = 0.95,
        elite_enemy_value_multiplier = 1.30
    },
    very_hard = {
        enemy_value_multiplier = 1.30,
        player_reward_value_multiplier = 0.90,
        elite_enemy_value_multiplier = 1.35
    }
}

data.CONFIG = {
    initial_player_value = 4500,
    initial_enemy_value = 3500,
    enemy_growth = {
        { min_cycle = 1, max_cycle = 5, growth = 400, hero_num = 0 },
        { min_cycle = 6, max_cycle = 10, growth = 750, hero_num = 1 },
        { min_cycle = 11, max_cycle = 15, growth = 950, hero_num = 2 },
        { min_cycle = 16, max_cycle = 20, growth = 950, hero_num = 2 },
        { min_cycle = 21, max_cycle = 25, growth = 1050, hero_num = 3 },
        { min_cycle = 26, max_cycle = 30, growth = 1100, hero_num = 3 },
        { min_cycle = 31, max_cycle = nil, growth = 1500, hero_num = 3 }
    },
    player_reward_value = {
        { min_cycle = 1, max_cycle = 5, min_value = 300, max_value = 700, double_line = 0 },
        { min_cycle = 6, max_cycle = 10, min_value = 300, max_value = 1000, double_line = 501 },
        { min_cycle = 11, max_cycle = 15, min_value = 700, max_value = 1200, double_line = 901 },
        { min_cycle = 16, max_cycle = 20, min_value = 1000, max_value = 1500, double_line = 1201 },
        { min_cycle = 21, max_cycle = 25, min_value = 1200, max_value = 2000, double_line = 1500 },
        { min_cycle = 26, max_cycle = 30, min_value = 1500, max_value = 2500, double_line = 1500 },
        { min_cycle = 31, max_cycle = nil, min_value = 1500, max_value = 5000, double_line = 1500 }
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
        reward_highest_tier = true
    },
    enemy_unit_count = {
        minimum_units_base = 7,
        minimum_units_per_cycle = 1,
        hard_cap = 20,
        minimum_units_from_cycle_11 = 18,
        full_stack_from_cycle_19 = true
    }
}

function data.is_supported_difficulty_level(level)
    return type(level) == "string" and data.DIFFICULTY_LEVELS[string.lower(level)] ~= nil
end

function data.normalize_difficulty_level(level)
    if not data.is_supported_difficulty_level(level) then
        return data.DEFAULT_DIFFICULTY_LEVEL
    end

    return string.lower(level)
end

return data
