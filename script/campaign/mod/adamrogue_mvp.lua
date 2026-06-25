local MODULE_KEY = "adamrogue_phase_a"
local config_log = true
local LOG_FILE_NAME = "adamrogue_phase_a_log.txt"
local get_current_event_payload
local launch_army_preview_dilemma

package.path = "script/campaign/mod/adamrogue/?.lua;" .. package.path

local adamrogue_data_cth = require("adamrogue_data_cth")
local adamrogue_data_players = require("adamrogue_data_players")
local adamrogue_data_nodes = require("adamrogue_data_nodes")
local adamrogue_data_battle_pools = require("adamrogue_data_battle_pools")
local adamrogue_data_ancillaries = require("adamrogue_data_ancillaries")
local adamrogue_balance_config = require("adamrogue_balance_config")
local adamrogue_battle_generator_module = require("adamrogue_battle_generator")
local adamrogue_ancillary_generator_module = require("adamrogue_ancillary_generator")
local adamrogue_force_snapshot_module = require("adamrogue_force_snapshot")
local adamrogue_enemy_skill_allocator_module = require("adamrogue_enemy_skill_allocator")

local BUTTON_CONTEXT_PREFIX = "adamrogue_phase_a_entry"
local AUTO_RESUME_ON_TURN_START = false
local MAX_CONSECUTIVE_DEFEATS = 3
local MAX_BATTLE_SPAWN_POLL_ATTEMPTS = 10
-- This is only a retry ceiling. The actual candidate list comes from the current content faction.
local MAX_BATTLE_SPAWN_RETRIES = 5
local WAR_ATTACK_DELAY = 0.25
local UNIT_VALUE_SOURCE = "main_units_tables.multiplayer_cost"

local DILEMMA_REWARD_KEY = "adamrogue_mvp_reward_dilemma"
local DILEMMA_BATTLE_KEY = "adamrogue_mvp_battle_dilemma"
local DILEMMA_EQUIPMENT_REWARD_KEY = "adamrogue_mvp_equipment_reward_dilemma"
local DILEMMA_DESTINATION_KEY = "adamrogue_mvp_destination_dilemma"
local DILEMMA_ARMY_PREVIEW_KEY = "adamrogue_mvp_army_preview_dilemma"
local DILEMMA_HERO_REWARD_KEY = "adamrogue_mvp_hero_reward_dilemma"
local DILEMMA_HERO_REWARD_FULL_KEY = "adamrogue_mvp_hero_reward_full_dilemma"

local DEFAULT_SUPPORTED_PLAYER_FACTION_KEY = adamrogue_data_players.DEFAULT_SUPPORTED_PLAYER_FACTION_KEY
local DEFAULT_PLAYER_CONTENT_FACTION_KEY = adamrogue_data_players.DEFAULT_CONTENT_FACTION_KEY
local SUPPORTED_PLAYER_FACTIONS = adamrogue_data_players.SUPPORTED_PLAYER_FACTIONS or {}
local PLAYER_CONTENT_FACTION_BY_FACTION = adamrogue_data_players.PLAYER_CONTENT_FACTION_BY_FACTION or {}
local PLAYER_GENERAL_OPTIONS_BY_FACTION = adamrogue_data_players.PLAYER_GENERAL_OPTIONS_BY_FACTION or {}
local DEFAULT_PLAYER_GENERAL_SUBTYPE_BY_FACTION = adamrogue_data_players.DEFAULT_PLAYER_GENERAL_SUBTYPE_BY_FACTION or {}

local STARTING_NODE_KEY = adamrogue_data_nodes.STARTING_NODE_KEY
local NODE_POOL = adamrogue_data_nodes.NODE_POOL

local ENEMY_GENERAL_SUBTYPE = adamrogue_data_battle_pools.ENEMY_GENERAL_SUBTYPE_BY_CONTENT_FACTION.wh3_main_cth_the_northern_provinces
local ENEMY_GENERAL_OPTIONS_BY_CONTENT_FACTION = adamrogue_data_battle_pools.ENEMY_GENERAL_OPTIONS_BY_CONTENT_FACTION or {}
local ENEMY_EMBEDDED_AGENT_SUBTYPE = adamrogue_data_battle_pools.ENEMY_EMBEDDED_AGENT_SUBTYPE_BY_CONTENT_FACTION.wh3_main_cth_the_northern_provinces
local DEFAULT_ENEMY_FACTION_KEY = adamrogue_data_battle_pools.DEFAULT_ENEMY_FACTION_KEY
local DEFAULT_CONTENT_FACTION_KEY = adamrogue_data_battle_pools.DEFAULT_CONTENT_FACTION_KEY
local ENEMY_FACTION_CANDIDATES_BY_CONTENT_FACTION = adamrogue_data_battle_pools.ENEMY_FACTION_CANDIDATES_BY_CONTENT_FACTION
local ENEMY_GENERAL_SUBTYPE_BY_CONTENT_FACTION = adamrogue_data_battle_pools.ENEMY_GENERAL_SUBTYPE_BY_CONTENT_FACTION
local ENEMY_GENERAL_UNIT_VALUE_BY_CONTENT_FACTION = adamrogue_data_battle_pools.ENEMY_GENERAL_UNIT_VALUE_BY_CONTENT_FACTION or {}
local ENEMY_EMBEDDED_AGENT_SUBTYPE_BY_CONTENT_FACTION = adamrogue_data_battle_pools.ENEMY_EMBEDDED_AGENT_SUBTYPE_BY_CONTENT_FACTION
local ENEMY_HERO_POOLS_BY_CONTENT_FACTION = adamrogue_data_battle_pools.ENEMY_HERO_POOLS_BY_CONTENT_FACTION or {}
local EQUIPMENT_RARITY = adamrogue_data_ancillaries.EQUIPMENT_RARITY
local EQUIPMENT_REWARD_SLOT_ORDER = adamrogue_data_ancillaries.EQUIPMENT_REWARD_SLOT_ORDER
local COMMON_EQUIPMENT_POOL = adamrogue_data_ancillaries.COMMON_EQUIPMENT_POOL
local FACTION_EQUIPMENT_POOLS = adamrogue_data_ancillaries.FACTION_EQUIPMENT_POOLS
local BALANCE_CONFIG = adamrogue_balance_config.CONFIG
local DEFAULT_CURRENT_CYCLE = adamrogue_balance_config.DEFAULT_CURRENT_CYCLE
local DEFAULT_DIFFICULTY_LEVEL = adamrogue_balance_config.DEFAULT_DIFFICULTY_LEVEL

local EVENT_TYPE = {
    UNIT_REWARD = "unit_reward",
    HERO_REWARD = "hero_reward",
    BATTLE = "battle",
    EQUIPMENT_REWARD = "equipment_reward",
    DESTINATION = "destination"
}

local BATTLE_TIER = adamrogue_data_cth.BATTLE_TIER

local STATE = {
    INIT = "INIT",
    ARMY_PREVIEW_PENDING = "ARMY_PREVIEW_PENDING",
    HERO_REWARD_PENDING = "HERO_REWARD_PENDING",
    HERO_REWARD_FULL_PENDING = "HERO_REWARD_FULL_PENDING",
    UNIT_REWARD_PENDING = "UNIT_REWARD_PENDING",
    BATTLE_PENDING = "BATTLE_PENDING",
    EQUIPMENT_REWARD_PENDING = "EQUIPMENT_REWARD_PENDING",
    DESTINATION_PENDING = "DESTINATION_PENDING",
    PAUSED = "PAUSED",
    GAME_OVER = "GAME_OVER"
}

local SAVE_KEYS = {
    run_started = "adamrogue_run_started",
    player_faction_key = "adamrogue_player_faction_key",
    player_force_cqi = "adamrogue_force_cqi",
    player_leader_cqi = "adamrogue_leader_cqi",
    current_state = "adamrogue_current_state",
    paused_from_state = "adamrogue_paused_from_state",
    current_event_type = "adamrogue_current_event_type",
    current_event_key = "adamrogue_current_event_key",
    current_event_seed = "adamrogue_current_event_seed",
    current_event_payload = "adamrogue_current_event_payload",
    last_reward_unit = "adamrogue_last_reward_unit",
    last_reward_ancillary = "adamrogue_last_reward_ancillary",
    last_battle_result = "adamrogue_last_battle_result",
    completed_battle_count = "adamrogue_completed_battle_count",
    victory_count = "adamrogue_victory_count",
    defeat_count = "adamrogue_defeat_count",
    consecutive_defeat_count = "adamrogue_consecutive_defeat_count",
    last_battle_force_source = "adamrogue_last_battle_force_source",
    last_battle_budget = "adamrogue_last_battle_budget",
    pre_battle_unit_snapshot = "adamrogue_pre_battle_unit_snapshot",
    pre_battle_embedded_hero_snapshot = "adamrogue_pre_battle_embedded_hero_snapshot",
    pre_battle_general_rank = "adamrogue_pre_battle_general_rank",
    player_general_subtype = "adamrogue_player_general_subtype",
    current_cycle = "adamrogue_current_cycle",
    difficulty_level = "adamrogue_difficulty_level",
    enemy_faction_key = "adamrogue_enemy_faction_key",
    enemy_force_cqi = "adamrogue_enemy_force_cqi",
    enemy_leader_cqi = "adamrogue_enemy_leader_cqi",
    enemy_agent_cqi = "adamrogue_enemy_agent_cqi",
    current_node_key = "adamrogue_current_node_key",
    current_node_faction_key = "adamrogue_current_node_faction_key",
    destination_candidate_node_keys = "adamrogue_destination_candidate_node_keys",
    destination_candidate_faction_keys = "adamrogue_destination_candidate_faction_keys",
    destination_leave_current_enabled = "adamrogue_destination_leave_current_enabled",
    destination_selection_generated = "adamrogue_destination_selection_generated",
    destination_generation_seed = "adamrogue_destination_generation_seed",
    destination_generation_attempts = "adamrogue_destination_generation_attempts",
    initial_peace_applied = "adamrogue_initial_peace_applied"
}

local BATTLE_UNIT_POOLS_BY_CONTENT_FACTION = adamrogue_data_battle_pools.BATTLE_UNIT_POOLS_BY_CONTENT_FACTION

local function build_destination_payload_component_key(node_key)
    return "adamrogue_destination_payload_choice_" .. tostring(node_key)
end

local function build_destination_current_payload_component_key(node_key)
    return "adamrogue_destination_payload_current_" .. tostring(node_key)
end

local function build_hero_reward_payload_component_key(agent_subtype)
    return "adamrogue_hero_reward_payload_" .. tostring(agent_subtype)
end

local function log(message)
    if not config_log then
        return
    end

    local logtext = tostring(message)
    local timestamp = os.date("%Y%m%d %X")
    local logfile = io.open(LOG_FILE_NAME, "a")

    if not logfile then
        out("[" .. MODULE_KEY .. "][log-fallback] " .. logtext)
        return
    end

    logfile:write("[" .. timestamp .. "] " .. logtext .. "\n")
    logfile:flush()
    logfile:close()
end

local function get_saved_value(key, default_value)
    local value = cm:get_saved_value(key)
    if value == nil then
        return default_value
    end
    return value
end

local function set_saved_value(key, value)
    cm:set_saved_value(key, value)
end

local function split_string(input, delimiter)
    local result = {}
    if not input or input == "" then
        return result
    end

    local pattern = string.format("([^%s]+)", delimiter)
    for token in string.gmatch(input, pattern) do
        result[#result + 1] = token
    end

    return result
end

local function get_current_state()
    return get_saved_value(SAVE_KEYS.current_state, STATE.INIT)
end

local function get_current_cycle()
    local cycle = tonumber(get_saved_value(SAVE_KEYS.current_cycle, DEFAULT_CURRENT_CYCLE)) or DEFAULT_CURRENT_CYCLE
    cycle = math.floor(cycle)
    if cycle < DEFAULT_CURRENT_CYCLE then
        cycle = DEFAULT_CURRENT_CYCLE
    end

    return cycle
end

local function set_current_cycle(cycle)
    local normalized_cycle = tonumber(cycle) or DEFAULT_CURRENT_CYCLE
    normalized_cycle = math.max(DEFAULT_CURRENT_CYCLE, math.floor(normalized_cycle))
    set_saved_value(SAVE_KEYS.current_cycle, normalized_cycle)
    log("Cycle -> " .. tostring(normalized_cycle))
end

local function get_difficulty_level()
    local saved_level = tostring(get_saved_value(SAVE_KEYS.difficulty_level, DEFAULT_DIFFICULTY_LEVEL) or DEFAULT_DIFFICULTY_LEVEL)
    return adamrogue_balance_config.normalize_difficulty_level(saved_level)
end

local function set_difficulty_level(level)
    local normalized_level = adamrogue_balance_config.normalize_difficulty_level(level)
    set_saved_value(SAVE_KEYS.difficulty_level, normalized_level)
    log("Difficulty -> " .. tostring(normalized_level))
end

local function ensure_balance_state_initialized(reason)
    local current_cycle = tonumber(get_saved_value(SAVE_KEYS.current_cycle, 0)) or 0
    if current_cycle < DEFAULT_CURRENT_CYCLE then
        set_saved_value(SAVE_KEYS.current_cycle, DEFAULT_CURRENT_CYCLE)
        log(
            "ensure_balance_state_initialized seeded current_cycle. reason=["
                .. tostring(reason)
                .. "], cycle=["
                .. tostring(DEFAULT_CURRENT_CYCLE)
                .. "]."
        )
    end

    local saved_difficulty_level = tostring(get_saved_value(SAVE_KEYS.difficulty_level, "") or "")
    if not adamrogue_balance_config.is_supported_difficulty_level(saved_difficulty_level) then
        set_saved_value(SAVE_KEYS.difficulty_level, DEFAULT_DIFFICULTY_LEVEL)
        log(
            "ensure_balance_state_initialized seeded difficulty_level. reason=["
                .. tostring(reason)
                .. "], difficulty_level=["
                .. tostring(DEFAULT_DIFFICULTY_LEVEL)
                .. "]."
        )
    end
end

local function get_difficulty_config()
    return adamrogue_balance_config.DIFFICULTY_LEVELS[get_difficulty_level()]
        or adamrogue_balance_config.DIFFICULTY_LEVELS[DEFAULT_DIFFICULTY_LEVEL]
end

local function get_enemy_growth_for_cycle(cycle)
    local normalized_cycle = math.max(DEFAULT_CURRENT_CYCLE, math.floor(tonumber(cycle) or DEFAULT_CURRENT_CYCLE))
    for _, entry in ipairs(BALANCE_CONFIG.enemy_growth or {}) do
        local min_cycle = tonumber(entry.min_cycle) or DEFAULT_CURRENT_CYCLE
        local max_cycle = entry.max_cycle and tonumber(entry.max_cycle) or nil
        if normalized_cycle >= min_cycle and (not max_cycle or normalized_cycle <= max_cycle) then
            return tonumber(entry.growth) or 0
        end
    end

    return 0
end

local function is_elite_battle_cycle(cycle)
    local normalized_cycle = math.max(DEFAULT_CURRENT_CYCLE, math.floor(tonumber(cycle) or DEFAULT_CURRENT_CYCLE))
    local elite_config = BALANCE_CONFIG.elite_battles or {}
    for _, elite_cycle in ipairs(elite_config.battle_cycles or {}) do
        if normalized_cycle == tonumber(elite_cycle) then
            return true
        end
    end

    return false
end

local function get_enemy_value_budget_for_cycle(cycle)
    local normalized_cycle = math.max(DEFAULT_CURRENT_CYCLE, math.floor(tonumber(cycle) or DEFAULT_CURRENT_CYCLE))
    local base_value = tonumber(BALANCE_CONFIG.initial_enemy_value) or 0
    local value_before_difficulty = base_value

    for growth_cycle = DEFAULT_CURRENT_CYCLE, normalized_cycle do
        value_before_difficulty = value_before_difficulty + get_enemy_growth_for_cycle(growth_cycle)
    end

    local difficulty_config = get_difficulty_config()
    local difficulty_multiplier = tonumber(difficulty_config.enemy_value_multiplier) or 1
    local elite_multiplier = 1
    local elite_battle = is_elite_battle_cycle(normalized_cycle)
    if elite_battle then
        elite_multiplier = tonumber(difficulty_config.elite_enemy_value_multiplier) or 1
    end

    local value_after_difficulty = math.floor((value_before_difficulty * difficulty_multiplier) + 0.5)
    local final_value = math.floor((value_after_difficulty * elite_multiplier) + 0.5)

    return {
        cycle = normalized_cycle,
        base_value = base_value,
        value_before_difficulty = value_before_difficulty,
        difficulty_multiplier = difficulty_multiplier,
        value_after_difficulty = value_after_difficulty,
        elite_battle = elite_battle,
        elite_multiplier = elite_multiplier,
        final_value = final_value
    }
end

local function get_player_reward_value_band_for_cycle(cycle)
    local normalized_cycle = math.max(DEFAULT_CURRENT_CYCLE, math.floor(tonumber(cycle) or DEFAULT_CURRENT_CYCLE))
    local resolved_entry = nil

    for _, entry in ipairs(BALANCE_CONFIG.player_reward_value or {}) do
        local min_cycle = tonumber(entry.min_cycle) or DEFAULT_CURRENT_CYCLE
        local max_cycle = entry.max_cycle and tonumber(entry.max_cycle) or nil
        if normalized_cycle >= min_cycle and (not max_cycle or normalized_cycle <= max_cycle) then
            resolved_entry = entry
            break
        end
    end

    resolved_entry = resolved_entry or {
        min_value = 300,
        max_value = 700
    }

    local difficulty_config = get_difficulty_config()
    local player_reward_value_multiplier = tonumber(difficulty_config.player_reward_value_multiplier) or 1
    local base_min_value = tonumber(resolved_entry.min_value) or 300
    local base_max_value = tonumber(resolved_entry.max_value) or base_min_value
    local base_double_line = tonumber(resolved_entry.double_line) or 0
    local min_value = math.floor((base_min_value * player_reward_value_multiplier) + 0.5)
    local max_value = math.floor((base_max_value * player_reward_value_multiplier) + 0.5)
    -- double_line 不随难度系数同步缩放，使难度不影响双倍奖励的触发范围
    local double_line = base_double_line
    if max_value < min_value then
        max_value = min_value
    end

    return {
        cycle = normalized_cycle,
        base_min_value = base_min_value,
        base_max_value = base_max_value,
        base_double_line = base_double_line,
        player_reward_value_multiplier = player_reward_value_multiplier,
        min_value = min_value,
        max_value = max_value,
        double_line = double_line
    }
end

local function get_equipment_rarity_context_for_cycle(cycle)
    local normalized_cycle = math.max(DEFAULT_CURRENT_CYCLE, math.floor(tonumber(cycle) or DEFAULT_CURRENT_CYCLE))
    for _, entry in ipairs(BALANCE_CONFIG.equipment_rarity_by_cycle or {}) do
        local min_cycle = tonumber(entry.min_cycle) or DEFAULT_CURRENT_CYCLE
        local max_cycle = entry.max_cycle and tonumber(entry.max_cycle) or nil
        if normalized_cycle >= min_cycle and (not max_cycle or normalized_cycle <= max_cycle) then
            return {
                cycle = normalized_cycle,
                tiers = entry.tiers or { EQUIPMENT_RARITY.COMMON }
            }
        end
    end

    return {
        cycle = normalized_cycle,
        tiers = { EQUIPMENT_RARITY.COMMON }
    }
end

local function resolve_player_content_faction_key(player_faction_key)
    if type(player_faction_key) ~= "string" or player_faction_key == "" then
        return DEFAULT_PLAYER_CONTENT_FACTION_KEY or DEFAULT_CONTENT_FACTION_KEY, "default_empty_player_faction"
    end

    local mapped_content_faction_key = PLAYER_CONTENT_FACTION_BY_FACTION[player_faction_key]
    if mapped_content_faction_key and mapped_content_faction_key ~= "" then
        return mapped_content_faction_key, "player_mapping"
    end

    if BATTLE_UNIT_POOLS_BY_CONTENT_FACTION[player_faction_key] then
        return player_faction_key, "direct_content_pool"
    end

    return DEFAULT_PLAYER_CONTENT_FACTION_KEY or DEFAULT_CONTENT_FACTION_KEY, "default_fallback"
end

local function get_player_general_options_for_faction(player_faction_key)
    local options = PLAYER_GENERAL_OPTIONS_BY_FACTION[player_faction_key]
    if options and #options > 0 then
        return options, player_faction_key, "exact_player_faction"
    end

    local resolved_content_faction_key = resolve_player_content_faction_key(player_faction_key)
    for supported_faction_key, content_faction_key in pairs(PLAYER_CONTENT_FACTION_BY_FACTION) do
        if content_faction_key == resolved_content_faction_key then
            local shared_options = PLAYER_GENERAL_OPTIONS_BY_FACTION[supported_faction_key]
            if shared_options and #shared_options > 0 then
                return shared_options, supported_faction_key, "shared_content_faction"
            end
        end
    end

    local default_options = PLAYER_GENERAL_OPTIONS_BY_FACTION[DEFAULT_SUPPORTED_PLAYER_FACTION_KEY] or {}
    return default_options, DEFAULT_SUPPORTED_PLAYER_FACTION_KEY, "default_supported_player_faction"
end

local function get_default_player_general_subtype_for_faction(player_faction_key)
    local default_subtype = DEFAULT_PLAYER_GENERAL_SUBTYPE_BY_FACTION[player_faction_key]
    if default_subtype and default_subtype ~= "" then
        return default_subtype
    end

    local options = PLAYER_GENERAL_OPTIONS_BY_FACTION[player_faction_key]
    if options and options[1] and options[1].subtype and options[1].subtype ~= "" then
        return options[1].subtype
    end

    if DEFAULT_SUPPORTED_PLAYER_FACTION_KEY and DEFAULT_SUPPORTED_PLAYER_FACTION_KEY ~= "" then
        local fallback_subtype = DEFAULT_PLAYER_GENERAL_SUBTYPE_BY_FACTION[DEFAULT_SUPPORTED_PLAYER_FACTION_KEY]
        if fallback_subtype and fallback_subtype ~= "" then
            return fallback_subtype
        end
    end

    return ""
end

local function pick_random_player_general_option(player_faction_key)
    local player_general_options, resolved_general_pool_faction_key, resolution = get_player_general_options_for_faction(player_faction_key)
    if player_general_options and #player_general_options > 0 then
        local selected_option = player_general_options[cm:random_number(#player_general_options, 1)]
        if selected_option and selected_option.subtype and selected_option.subtype ~= "" then
            log(
                "pick_random_player_general_option selected a faction-specific general option. player_faction_key=["
                    .. tostring(player_faction_key)
                    .. "], resolved_general_pool_faction_key=["
                    .. tostring(resolved_general_pool_faction_key)
                    .. "], resolution=["
                    .. tostring(resolution)
                    .. "], selected_subtype=["
                    .. tostring(selected_option.subtype)
                    .. "], unit_value=["
                    .. tostring(selected_option.unit_value or 0)
                    .. "]."
            )
            return selected_option
        end
    end

    local fallback_subtype = get_default_player_general_subtype_for_faction(player_faction_key)
    if fallback_subtype ~= "" then
        log(
            "[ERROR] pick_random_player_general_option is falling back to the default subtype because no explicit option list was available. player_faction_key=["
                .. tostring(player_faction_key)
                .. "], fallback_subtype=["
                .. tostring(fallback_subtype)
                .. "]."
        )
        return {
            subtype = fallback_subtype,
            unit_key = "",
            unit_value = 0
        }
    end

    return {
        subtype = "",
        unit_key = "",
        unit_value = 0
    }
end

local function build_starting_player_unit_list(player_faction_key, selected_general_option)
    local total_value_budget = tonumber(BALANCE_CONFIG.initial_player_value) or 4500
    local selected_general_value = tonumber(selected_general_option and selected_general_option.unit_value) or 0
    local target_value_budget = math.max(0, total_value_budget - selected_general_value)
    local resolved_faction_key, content_resolution = resolve_player_content_faction_key(player_faction_key)
    local source_pool = BATTLE_UNIT_POOLS_BY_CONTENT_FACTION[resolved_faction_key]

    local function build_dynamic_starting_fallback_unit_list()
        local fallback_source_pool = source_pool or {}
        local fallback_units = {}
        for _, unit_entry in ipairs(fallback_source_pool) do
            if unit_entry and unit_entry.unit_key then
                fallback_units[#fallback_units + 1] = unit_entry.unit_key
                if #fallback_units >= 3 then
                    break
                end
            end
        end

        if #fallback_units == 0 then
            return "", "", 0
        end

        local fallback_unit_list = table.concat(fallback_units, ",")
        return fallback_unit_list, fallback_unit_list, 0
    end

    if not source_pool or #source_pool == 0 then
        source_pool = BATTLE_UNIT_POOLS_BY_CONTENT_FACTION[DEFAULT_CONTENT_FACTION_KEY] or {}
        resolved_faction_key = DEFAULT_CONTENT_FACTION_KEY
        log(
            "[ERROR] build_starting_player_unit_list is falling back to the default content faction pool. requested_content_faction_key=["
                .. tostring(player_faction_key)
                .. "], resolved_content_faction_key=["
                .. tostring(resolved_faction_key)
                .. "], content_resolution=["
                .. tostring(content_resolution)
                .. "], pool_size=["
                .. tostring(#source_pool)
                .. "]."
        )
    end

    local weighted_pool = {}
    for _, unit_entry in ipairs(source_pool) do
        local unit_weight = tonumber(unit_entry.weight) or 0
        if unit_weight >= 7 then
            for _ = 1, math.max(1, unit_weight) do
                weighted_pool[#weighted_pool + 1] = unit_entry
            end
        end
    end

    if not weighted_pool or #weighted_pool == 0 then
        log(
            "[ERROR] build_starting_player_unit_list could not find any weight>=7 units in the resolved pool and will use the first available units from that pool. player_faction_key=["
                .. tostring(player_faction_key)
                .. "], resolved_faction_key=["
                .. tostring(resolved_faction_key)
                .. "]."
        )
        local fallback_unit_list, logged_fallback_unit_list, fallback_total_value = build_dynamic_starting_fallback_unit_list()
        return fallback_unit_list, logged_fallback_unit_list, fallback_total_value, resolved_faction_key or player_faction_key
    end

    local chosen_units = {}
    local total_value = 0
    local attempts = 0
    local unique_pool = {}
    local seen_unit_keys = {}

    for _, unit_entry in ipairs(weighted_pool) do
        if unit_entry and unit_entry.unit_key and not seen_unit_keys[unit_entry.unit_key] then
            unique_pool[#unique_pool + 1] = unit_entry
            seen_unit_keys[unit_entry.unit_key] = true
        end
    end

    table.sort(unique_pool, function(a, b)
        local a_value = tonumber(a.unit_value) or 0
        local b_value = tonumber(b.unit_value) or 0
        if a_value == b_value then
            return tostring(a.unit_key) < tostring(b.unit_key)
        end
        return a_value < b_value
    end)

    local function pick_budget_fit_unit(preferred_entry, remaining_budget)
        if remaining_budget <= 0 then
            return nil, "remaining_budget_empty"
        end

        local preferred_weight = tonumber(preferred_entry and preferred_entry.weight) or 0
        local preferred_value = tonumber(preferred_entry and preferred_entry.unit_value) or 0
        local high_weight_fallback_pool = {}
        local fitting_weighted_pool = {}

        for _, unit_entry in ipairs(weighted_pool) do
            local unit_value = tonumber(unit_entry.unit_value) or 0
            local unit_weight = tonumber(unit_entry.weight) or 0
            if unit_value <= remaining_budget then
                fitting_weighted_pool[#fitting_weighted_pool + 1] = unit_entry
                if unit_value < preferred_value and unit_weight >= preferred_weight then
                    high_weight_fallback_pool[#high_weight_fallback_pool + 1] = unit_entry
                end
            end
        end

        if #high_weight_fallback_pool > 0 then
            return high_weight_fallback_pool[cm:random_number(#high_weight_fallback_pool, 1)], "higher_weight_fallback"
        end

        if #fitting_weighted_pool > 0 then
            return fitting_weighted_pool[cm:random_number(#fitting_weighted_pool, 1)], "any_fitting_fallback"
        end

        return nil, "no_fitting_unit"
    end

    while attempts < 300 and #chosen_units < 19 do
        attempts = attempts + 1
        local attempted_unit_entry = weighted_pool[cm:random_number(#weighted_pool, 1)]
        local remaining_budget = target_value_budget - total_value
        local unit_entry = attempted_unit_entry
        local selection_mode = "direct_random"
        local projected_total = total_value + unit_entry.unit_value

        if projected_total > target_value_budget then
            unit_entry, selection_mode = pick_budget_fit_unit(attempted_unit_entry, remaining_budget)
            if unit_entry then
                projected_total = total_value + unit_entry.unit_value
                log(
                    "build_starting_player_unit_list replaced an over-budget random pick with a cheaper fallback. attempted_unit_key=["
                        .. tostring(attempted_unit_entry.unit_key)
                        .. "], attempted_unit_value=["
                        .. tostring(attempted_unit_entry.unit_value)
                        .. "], replacement_unit_key=["
                        .. tostring(unit_entry.unit_key)
                        .. "], replacement_unit_value=["
                        .. tostring(unit_entry.unit_value)
                        .. "], selection_mode=["
                        .. tostring(selection_mode)
                        .. "], remaining_budget=["
                        .. tostring(remaining_budget)
                        .. "]."
                )
            else
                log(
                    "build_starting_player_unit_list could not find any lower-cost unit to fit the remaining budget and will stop random filling. attempted_unit_key=["
                        .. tostring(attempted_unit_entry.unit_key)
                        .. "], attempted_unit_value=["
                        .. tostring(attempted_unit_entry.unit_value)
                        .. "], remaining_budget=["
                        .. tostring(remaining_budget)
                        .. "]."
                )
                break
            end
        end

        if projected_total <= target_value_budget then
            chosen_units[#chosen_units + 1] = unit_entry.unit_key
            total_value = projected_total
        end

        if total_value >= target_value_budget then
            break
        end
    end

    for _, unit_entry in ipairs(unique_pool) do
        if total_value >= target_value_budget then
            break
        end

        local projected_total = total_value + unit_entry.unit_value
        if projected_total <= target_value_budget then
            chosen_units[#chosen_units + 1] = unit_entry.unit_key
            total_value = projected_total
        end
    end

    if #chosen_units == 0 then
        log("[ERROR] build_starting_player_unit_list could not generate any weighted units and will fall back to the first available resolved-pool units.")
        local fallback_unit_list, logged_fallback_unit_list, fallback_total_value = build_dynamic_starting_fallback_unit_list()
        return fallback_unit_list, logged_fallback_unit_list, fallback_total_value, resolved_faction_key or player_faction_key
    end

    local unit_list = table.concat(chosen_units, ",")
    log(
        "build_starting_player_unit_list completed. player_faction_key=["
            .. tostring(player_faction_key)
            .. "], resolved_faction_key=["
            .. tostring(resolved_faction_key)
            .. "], content_resolution=["
            .. tostring(content_resolution)
            .. "], selected_general_subtype=["
            .. tostring(selected_general_option and selected_general_option.subtype or "")
            .. "], selected_general_value=["
            .. tostring(selected_general_value)
            .. "], total_value_budget=["
            .. tostring(total_value_budget)
            .. "], total_value=["
            .. tostring(total_value)
            .. "], target_value_budget=["
            .. tostring(target_value_budget)
            .. "], unit_count=["
            .. tostring(#chosen_units)
            .. "], unit_list=["
            .. tostring(unit_list)
            .. "]."
    )
    return unit_list, unit_list, total_value, resolved_faction_key or player_faction_key
end

local function set_current_state(state)
    set_saved_value(SAVE_KEYS.current_state, state)
    log("State -> " .. state)
end

local function set_paused_state(from_state)
    set_saved_value(SAVE_KEYS.paused_from_state, from_state)
    set_current_state(STATE.PAUSED)
    log("Paused from state -> " .. tostring(from_state))
end

local function get_paused_from_state()
    local paused_from_state = get_saved_value(SAVE_KEYS.paused_from_state, STATE.INIT)
    if paused_from_state == nil or paused_from_state == "" then
        return STATE.INIT
    end

    return paused_from_state
end

local function is_supported_runtime_state(state)
    return state == STATE.INIT
        or state == STATE.HERO_REWARD_PENDING
        or state == STATE.HERO_REWARD_FULL_PENDING
        or state == STATE.UNIT_REWARD_PENDING
        or state == STATE.BATTLE_PENDING
        or state == STATE.EQUIPMENT_REWARD_PENDING
        or state == STATE.DESTINATION_PENDING
        or state == STATE.PAUSED
        or state == STATE.GAME_OVER
end

local function get_local_player_faction()
    local faction_name = cm:get_local_faction_name(true)
    if not faction_name or faction_name == "" then
        return nil
    end

    local faction = cm:get_faction(faction_name)
    if not faction or faction:is_null_interface() or faction:is_dead() then
        return nil
    end

    return faction
end

local function is_supported_player_faction(faction)
    if not faction or faction:is_null_interface() or faction:is_dead() then
        return false
    end

    local faction_name = faction:name()
    if SUPPORTED_PLAYER_FACTIONS[faction_name] then
        return true
    end

    return PLAYER_CONTENT_FACTION_BY_FACTION[faction_name] ~= nil
end

local function get_saved_character(saved_key)
    local cqi = get_saved_value(saved_key, 0)
    if not cqi or cqi == 0 then
        return nil
    end

    local character = cm:get_character_by_cqi(cqi)
    if not character or character:is_null_interface() then
        log("get_saved_character returning nil because cm:get_character_by_cqi failed for value [" .. tostring(cqi) .. "].")
        return nil
    end

    return character
end

local function get_saved_player_general()
    return get_saved_character(SAVE_KEYS.player_leader_cqi)
end

local function get_saved_enemy_general()
    return get_saved_character(SAVE_KEYS.enemy_leader_cqi)
end

local function get_saved_player_force()
    local general = get_saved_player_general()
    if not general or not general:has_military_force() then
        return nil
    end

    local force = general:military_force()
    if force:is_null_interface() then
        return nil
    end

    return force
end

local function get_saved_enemy_force()
    local general = get_saved_enemy_general()
    if not general or not general:has_military_force() then
        return nil
    end

    local force = general:military_force()
    if force:is_null_interface() then
        return nil
    end

    return force
end

local function count_units_in_force(force)
    if not force or force:is_null_interface() then
        return 0
    end

    return force:unit_list():num_items()
end

local PLAYER_SPAWN_SETTLEMENT_SEARCH_RADII = { 10, 8, 6, 5 }
local PLAYER_SPAWN_CHARACTER_SEARCH_RADII = { 10, 8, 6 }

local function find_player_spawn_position_for_faction(faction, region_key, leader)
    local faction_key = faction:name()

    for _, radius in ipairs(PLAYER_SPAWN_SETTLEMENT_SEARCH_RADII) do
        local x, y = cm:find_valid_spawn_location_for_character_from_settlement(
            faction_key,
            region_key,
            false,
            true,
            radius
        )
        if x >= 0 and y >= 0 then
            log(
                "Resolved player spawn from settlement. faction=["
                    .. tostring(faction_key)
                    .. "], region=["
                    .. tostring(region_key)
                    .. "], radius=["
                    .. tostring(radius)
                    .. "], x=["
                    .. tostring(x)
                    .. "], y=["
                    .. tostring(y)
                    .. "]."
            )
            return x, y, "from_settlement_r" .. tostring(radius)
        end
    end

    if leader and not leader:is_null_interface() then
        local leader_lookup = cm:char_lookup_str(leader)
        for _, radius in ipairs(PLAYER_SPAWN_CHARACTER_SEARCH_RADII) do
            local x, y = cm:find_valid_spawn_location_for_character_from_character(
                faction_key,
                leader_lookup,
                true,
                radius
            )
            if x >= 0 and y >= 0 then
                log(
                    "Resolved player spawn from faction leader. faction=["
                        .. tostring(faction_key)
                        .. "], radius=["
                        .. tostring(radius)
                        .. "], x=["
                        .. tostring(x)
                        .. "], y=["
                        .. tostring(y)
                        .. "]."
                )
                return x, y, "from_leader_r" .. tostring(radius)
            end
        end
    end

    log(
        "Failed to resolve player spawn position. faction=["
            .. tostring(faction_key)
            .. "], region=["
            .. tostring(region_key)
            .. "]."
    )
    return nil
end

local function find_random_player_spawn_position_for_faction(faction, region_key, leader)
    local faction_key = faction:name()
    local candidates = {}
    local seen_positions = {}

    local function add_candidate(x, y, source)
        if x < 0 or y < 0 then
            return
        end

        local position_key = tostring(x) .. ":" .. tostring(y)
        if seen_positions[position_key] then
            return
        end

        seen_positions[position_key] = true
        candidates[#candidates + 1] = {
            x = x,
            y = y,
            source = source,
        }
    end

    for _, radius in ipairs(PLAYER_SPAWN_SETTLEMENT_SEARCH_RADII) do
        local x, y = cm:find_valid_spawn_location_for_character_from_settlement(
            faction_key,
            region_key,
            false,
            true,
            radius
        )
        add_candidate(x, y, "from_settlement_r" .. tostring(radius))
    end

    if leader and not leader:is_null_interface() then
        local leader_lookup = cm:char_lookup_str(leader)
        for _, radius in ipairs(PLAYER_SPAWN_CHARACTER_SEARCH_RADII) do
            local x, y = cm:find_valid_spawn_location_for_character_from_character(
                faction_key,
                leader_lookup,
                true,
                radius
            )
            add_candidate(x, y, "from_leader_r" .. tostring(radius))
        end
    end

    if #candidates == 0 then
        return nil
    end

    local picked = candidates[cm:random_number(#candidates, 1)]
    return picked.x, picked.y, picked.source
end

local function try_relocate_player_force_for_variety(reason)
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("try_relocate_player_force_for_variety skipped because the local faction is unsupported. reason=[" .. tostring(reason) .. "].")
        return false
    end

    local player_general = get_saved_player_general()
    if not player_general or player_general:is_null_interface() or not player_general:has_military_force() then
        log("try_relocate_player_force_for_variety skipped because the player general is unavailable. reason=[" .. tostring(reason) .. "].")
        return false
    end

    local region = player_general:region()
    if not region or region:is_null_interface() then
        region = faction:home_region()
    end
    if not region or region:is_null_interface() then
        log("try_relocate_player_force_for_variety skipped because no region could be resolved. reason=[" .. tostring(reason) .. "].")
        return false
    end

    local region_key = region:name()
    local old_x = player_general:logical_position_x()
    local old_y = player_general:logical_position_y()
    local x, y, source = find_random_player_spawn_position_for_faction(faction, region_key, player_general)
    if not x or not y then
        log(
            "try_relocate_player_force_for_variety skipped because no valid relocation position was found. reason=["
                .. tostring(reason)
                .. "], region=["
                .. tostring(region_key)
                .. "]."
        )
        return false
    end

    if x == old_x and y == old_y then
        log(
            "try_relocate_player_force_for_variety skipped because the resolved position matches the current position. reason=["
                .. tostring(reason)
                .. "], source=["
                .. tostring(source)
                .. "], x=["
                .. tostring(x)
                .. "], y=["
                .. tostring(y)
                .. "]."
        )
        return false
    end

    cm:teleport_to(cm:char_lookup_str(player_general), x, y)
    log(
        "Relocated player force for terrain variety. reason=["
            .. tostring(reason)
            .. "], region=["
            .. tostring(region_key)
            .. "], source=["
            .. tostring(source)
            .. "], from_x=["
            .. tostring(old_x)
            .. "], from_y=["
            .. tostring(old_y)
            .. "], to_x=["
            .. tostring(x)
            .. "], to_y=["
            .. tostring(y)
            .. "]."
    )
    return true
end

local function get_spawn_region_and_position_for_faction(faction)
    local leader = faction:faction_leader()
    if not leader or leader:is_null_interface() then
        return nil
    end

    local region = faction:home_region()
    if not region or region:is_null_interface() then
        if leader:has_region() then
            region = leader:region()
        end
    end

    if not region or region:is_null_interface() then
        return nil
    end

    local region_key = region:name()
    local x, y, source = find_player_spawn_position_for_faction(faction, region_key, leader)
    if not x or not y then
        return nil
    end

    log(
        "Player spawn region resolved. faction=["
            .. tostring(faction:name())
            .. "], region=["
            .. tostring(region_key)
            .. "], source=["
            .. tostring(source)
            .. "], x=["
            .. tostring(x)
            .. "], y=["
            .. tostring(y)
            .. "]."
    )

    return region_key, x, y
end

local function find_enemy_spawn_near_player(enemy_faction_key, player_general)
    local x, y = cm:find_valid_spawn_location_for_character_from_character(
        enemy_faction_key,
        cm:char_lookup_str(player_general),
        true,
        6
    )

    if x >= 0 and y >= 0 then
        return x, y, "from_character"
    end

    x, y = cm:find_valid_spawn_location_for_character_from_position(
        enemy_faction_key,
        player_general:logical_position_x(),
        player_general:logical_position_y(),
        true
    )

    if x >= 0 and y >= 0 then
        return x, y, "from_position"
    end

    local player_faction = player_general:faction()
    if player_faction and not player_faction:is_null_interface() then
        local _, fallback_x, fallback_y = get_spawn_region_and_position_for_faction(player_faction)
        if fallback_x and fallback_y then
            return fallback_x, fallback_y, "player_faction_region"
        end
    end

    return -1, -1, "not_found"
end

local function find_alternative_enemy_spawn_position(enemy_faction_key, player_general, disallowed_x, disallowed_y)
    log(
        "find_alternative_enemy_spawn_position started. enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "], disallowed_x=["
            .. tostring(disallowed_x)
            .. "], disallowed_y=["
            .. tostring(disallowed_y)
            .. "]."
    )

    local first_valid_x = -1
    local first_valid_y = -1
    local first_valid_source = "not_found"

    local function evaluate_candidate(x, y, source)
        log(
            "find_alternative_enemy_spawn_position evaluated candidate. source=["
                .. tostring(source)
                .. "], x=["
                .. tostring(x)
                .. "], y=["
                .. tostring(y)
                .. "], disallowed_x=["
                .. tostring(disallowed_x)
                .. "], disallowed_y=["
                .. tostring(disallowed_y)
                .. "]."
        )

        if x and y and x >= 0 and y >= 0 then
            if first_valid_x < 0 or first_valid_y < 0 then
                first_valid_x = x
                first_valid_y = y
                first_valid_source = source
            end

            if x ~= disallowed_x or y ~= disallowed_y then
                return x, y, source
            end
        end

        return nil
    end

    local char_lookup = cm:char_lookup_str(player_general)

    -- 策略1：从玩家将领出发，小半径（对齐测试Mod的 search_radius=6）
    log(
        "find_alternative_enemy_spawn_position trying strategy=[from_character_r6], enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "]."
    )
    local x, y = cm:find_valid_spawn_location_for_character_from_character(
        enemy_faction_key,
        char_lookup,
        true,
        6
    )
    local resolved_x, resolved_y, resolved_source = evaluate_candidate(x, y, "from_character_r6")
    if resolved_x then
        log(
            "find_alternative_enemy_spawn_position resolved. enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], source=["
                .. tostring(resolved_source)
                .. "], x=["
                .. tostring(resolved_x)
                .. "], y=["
                .. tostring(resolved_y)
                .. "]."
        )
        return resolved_x, resolved_y, resolved_source
    end

    -- 策略2：从玩家将领坐标出发，宽松模式（对齐测试Mod的 from_position true）
    log(
        "find_alternative_enemy_spawn_position trying strategy=[from_position_true], enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "]."
    )
    x, y = cm:find_valid_spawn_location_for_character_from_position(
        enemy_faction_key,
        player_general:logical_position_x(),
        player_general:logical_position_y(),
        true
    )
    resolved_x, resolved_y, resolved_source = evaluate_candidate(x, y, "from_position_true")
    if resolved_x then
        log(
            "find_alternative_enemy_spawn_position resolved. enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], source=["
                .. tostring(resolved_source)
                .. "], x=["
                .. tostring(resolved_x)
                .. "], y=["
                .. tostring(resolved_y)
                .. "]."
        )
        return resolved_x, resolved_y, resolved_source
    end

    -- 策略3：中等半径扩展搜索
    log(
        "find_alternative_enemy_spawn_position trying strategy=[from_character_r12], enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "]."
    )
    x, y = cm:find_valid_spawn_location_for_character_from_character(
        enemy_faction_key,
        char_lookup,
        true,
        12
    )
    resolved_x, resolved_y, resolved_source = evaluate_candidate(x, y, "from_character_r12")
    if resolved_x then
        log(
            "find_alternative_enemy_spawn_position resolved. enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], source=["
                .. tostring(resolved_source)
                .. "], x=["
                .. tostring(resolved_x)
                .. "], y=["
                .. tostring(resolved_y)
                .. "]."
        )
        return resolved_x, resolved_y, resolved_source
    end

    -- 策略4：从玩家所在定居点兜底（严格模式）
    local player_region = player_general:region()
    if player_region and not player_region:is_null_interface() then
        log(
            "find_alternative_enemy_spawn_position trying strategy=[from_settlement_r20], enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], region=["
                .. tostring(player_region:name())
                .. "]."
        )
        x, y = cm:find_valid_spawn_location_for_character_from_settlement(
            enemy_faction_key,
            player_region:name(),
            false,
            true,
            20
        )
        resolved_x, resolved_y, resolved_source = evaluate_candidate(x, y, "from_settlement_r20")
        if resolved_x then
            log(
                "find_alternative_enemy_spawn_position resolved. enemy_faction_key=["
                    .. tostring(enemy_faction_key)
                    .. "], source=["
                    .. tostring(resolved_source)
                    .. "], x=["
                    .. tostring(resolved_x)
                    .. "], y=["
                    .. tostring(resolved_y)
                    .. "]."
            )
            return resolved_x, resolved_y, resolved_source
        end
    else
        log(
            "find_alternative_enemy_spawn_position skipped strategy=[from_settlement_r20] because player region is unavailable. enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "]."
        )
    end

    if first_valid_x >= 0 and first_valid_y >= 0 then
        log(
            "find_alternative_enemy_spawn_position is falling back to the first valid candidate even though it matches the disallowed position. source=["
                .. tostring(first_valid_source)
                .. "], x=["
                .. tostring(first_valid_x)
                .. "], y=["
                .. tostring(first_valid_y)
                .. "]."
        )
        return first_valid_x, first_valid_y, first_valid_source
    end

    log(
        "find_alternative_enemy_spawn_position finished without a valid position. enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "]."
    )
    return -1, -1, "not_found"
end

local function get_enemy_faction_candidates_for_content_faction(content_faction_key)
    local combined_candidates = {}
    local seen = {}
    local function append_candidates(candidate_list)
        for _, faction_key in ipairs(candidate_list or {}) do
            if not seen[faction_key] then
                seen[faction_key] = true
                combined_candidates[#combined_candidates + 1] = faction_key
            end
        end
    end

    append_candidates(ENEMY_FACTION_CANDIDATES_BY_CONTENT_FACTION[content_faction_key] or {})
    -- 仅在该内容派系没有配置候选时才回退到默认派系，避免帝国战斗混入震旦 QB 派系。
    if #combined_candidates == 0 then
        append_candidates(ENEMY_FACTION_CANDIDATES_BY_CONTENT_FACTION[DEFAULT_CONTENT_FACTION_KEY] or {})
    end
    return combined_candidates
end

local function is_enemy_spawn_faction_compatible_with_content(content_faction_key, enemy_faction_key)
    if not enemy_faction_key or enemy_faction_key == "" then
        return false
    end

    local options = ENEMY_GENERAL_OPTIONS_BY_CONTENT_FACTION[content_faction_key] or {}
    for _, option in ipairs(options) do
        for _, allowed_faction_key in ipairs(option.allowed_factions or {}) do
            if allowed_faction_key == enemy_faction_key then
                return true
            end
        end
    end

    return false
end

-- QB / 占位敌军派系在战役里通常 is_dead()==true（无城镇、无领主），
-- 但 create_force_with_general 仍可正常生成；spawn 候选筛选不要用 is_dead()。
local function can_use_faction_for_enemy_spawn(faction)
    if not faction or faction:is_null_interface() then
        return false
    end

    if faction:is_human() then
        return false
    end

    return true
end

local function get_enemy_faction_candidate_sequence(player_faction_key, preferred_enemy_faction_key, candidate_list_string, content_faction_key)
    local content_candidates = get_enemy_faction_candidates_for_content_faction(content_faction_key)
    local content_candidate_set = {}
    for _, faction_key in ipairs(content_candidates) do
        content_candidate_set[faction_key] = true
    end

    local configured_candidates = split_string(candidate_list_string or "", ",")
    local filtered_configured = {}
    for _, faction_key in ipairs(configured_candidates) do
        if content_candidate_set[faction_key] then
            filtered_configured[#filtered_configured + 1] = faction_key
        end
    end
    if #filtered_configured == 0 then
        configured_candidates = content_candidates
    else
        configured_candidates = filtered_configured
    end

    local candidate_keys = {}
    if preferred_enemy_faction_key
        and preferred_enemy_faction_key ~= ""
        and preferred_enemy_faction_key ~= player_faction_key
        and content_candidate_set[preferred_enemy_faction_key] then
        candidate_keys[#candidate_keys + 1] = preferred_enemy_faction_key
    end

    for _, faction_key in ipairs(configured_candidates) do
        if faction_key ~= player_faction_key and faction_key ~= preferred_enemy_faction_key then
            candidate_keys[#candidate_keys + 1] = faction_key
        end
    end

    if #candidate_keys == 0 then
        for _, faction_key in ipairs(content_candidates) do
            if faction_key ~= player_faction_key then
                candidate_keys[#candidate_keys + 1] = faction_key
            end
        end
    end

    return candidate_keys
end

local function find_enemy_faction_fallback_candidate(
    player_faction_key,
    current_enemy_faction_key,
    player_general,
    fallback_index,
    candidate_list_string,
    content_faction_key
)
    local candidate_keys = get_enemy_faction_candidate_sequence(
        player_faction_key,
        current_enemy_faction_key,
        candidate_list_string,
        content_faction_key
    )
    local target_index = fallback_index or 2

    for index = target_index, #candidate_keys do
        local faction_key = candidate_keys[index]
        local faction = cm:get_faction(faction_key)
        if can_use_faction_for_enemy_spawn(faction) then
            local x, y, source = find_alternative_enemy_spawn_position(faction_key, player_general, -1, -1)
            log(
                "find_enemy_faction_fallback_candidate evaluated faction candidate. faction_key=["
                    .. tostring(faction_key)
                    .. "], candidate_index=["
                    .. tostring(index)
                    .. "], x=["
                    .. tostring(x)
                    .. "], y=["
                    .. tostring(y)
                    .. "], source=["
                    .. tostring(source)
                    .. "]."
            )

            if x >= 0 and y >= 0 then
                return faction_key, x, y, source, index
            end
        end
    end

    return nil, -1, -1, "not_found", nil
end

local function pick_initial_enemy_faction_key(player_faction_key, player_general, preferred_enemy_faction_key, candidate_list_string, content_faction_key)
    local candidate_keys = get_enemy_faction_candidate_sequence(
        player_faction_key,
        preferred_enemy_faction_key or DEFAULT_ENEMY_FACTION_KEY,
        candidate_list_string,
        content_faction_key
    )

    log(
        "pick_initial_enemy_faction_key started. preferred_enemy_faction_key=["
            .. tostring(preferred_enemy_faction_key)
            .. "], content_faction_key=["
            .. tostring(content_faction_key)
            .. "], candidate_count=["
            .. tostring(#candidate_keys)
            .. "], candidates=["
            .. table.concat(candidate_keys, ",")
            .. "]."
    )

    for index, faction_key in ipairs(candidate_keys) do
        local faction = cm:get_faction(faction_key)
        if not can_use_faction_for_enemy_spawn(faction) then
            if not faction or faction:is_null_interface() then
                log(
                    "pick_initial_enemy_faction_key skipped faction candidate because faction interface is unavailable. index=["
                        .. tostring(index)
                        .. "], faction_key=["
                        .. tostring(faction_key)
                        .. "]."
                )
            else
                log(
                    "pick_initial_enemy_faction_key skipped faction candidate because faction is human-controlled. index=["
                        .. tostring(index)
                        .. "], faction_key=["
                        .. tostring(faction_key)
                        .. "]."
                )
            end
        elseif not is_enemy_spawn_faction_compatible_with_content(content_faction_key, faction_key) then
            log(
                "pick_initial_enemy_faction_key skipped faction candidate because it is incompatible with battle content faction. index=["
                    .. tostring(index)
                    .. "], faction_key=["
                    .. tostring(faction_key)
                    .. "], content_faction_key=["
                    .. tostring(content_faction_key)
                    .. "]."
            )
        else
            log(
                "pick_initial_enemy_faction_key evaluating faction candidate. index=["
                    .. tostring(index)
                    .. "], faction_key=["
                    .. tostring(faction_key)
                    .. "]."
            )
            local x, y, source = find_alternative_enemy_spawn_position(faction_key, player_general, -1, -1)

            if x >= 0 and y >= 0 then
                log(
                    "pick_initial_enemy_faction_key selected faction candidate. faction_key=["
                        .. tostring(faction_key)
                        .. "], source=["
                        .. tostring(source)
                        .. "], x=["
                        .. tostring(x)
                        .. "], y=["
                        .. tostring(y)
                        .. "]."
                )
                return faction_key, x, y
            end

            log(
                "pick_initial_enemy_faction_key rejected faction candidate because no valid spawn point was found. index=["
                    .. tostring(index)
                    .. "], faction_key=["
                    .. tostring(faction_key)
                    .. "]."
            )
        end
    end

    log("pick_initial_enemy_faction_key finished without selecting a valid faction candidate.")
    return nil, -1, -1
end

local function cleanup_enemy_force()
    local enemy_faction_name = get_saved_value(SAVE_KEYS.enemy_faction_key, DEFAULT_ENEMY_FACTION_KEY)
    local enemy_faction = nil

    if enemy_faction_name ~= "" then
        enemy_faction = cm:get_faction(enemy_faction_name)
    end

    if caravans and caravans.cleanup_post_battle then
        log("cleanup_enemy_force invoking caravans:cleanup_post_battle().")
        caravans:cleanup_post_battle()
    elseif enemy_faction and not enemy_faction:is_null_interface() and not enemy_faction:is_dead() then
        log("cleanup_enemy_force invoking kill_all_armies_for_faction for enemy faction [" .. tostring(enemy_faction_name) .. "].")
        cm:kill_all_armies_for_faction(enemy_faction)
    end

    local enemy_general = get_saved_enemy_general()
    if enemy_general then
        log("Cleaning up enemy test army [" .. enemy_general:faction():name() .. "]")
        cm:kill_character(cm:char_lookup_str(enemy_general), true)
    end

    local enemy_agent = get_saved_character(SAVE_KEYS.enemy_agent_cqi)
    if enemy_agent and enemy_agent:is_alive() then
        cm:kill_character(cm:char_lookup_str(enemy_agent))
    end

    if caravans then
        caravans.enemy_force_cqi = 0
    end

    set_saved_value(SAVE_KEYS.enemy_faction_key, "")
    set_saved_value(SAVE_KEYS.enemy_force_cqi, 0)
    set_saved_value(SAVE_KEYS.enemy_leader_cqi, 0)
    set_saved_value(SAVE_KEYS.enemy_agent_cqi, 0)
end

local function cleanup_enemy_force_before_spawn(reason)
    local enemy_faction_name = get_saved_value(SAVE_KEYS.enemy_faction_key, DEFAULT_ENEMY_FACTION_KEY)
    local enemy_faction = nil
    if enemy_faction_name ~= "" then
        enemy_faction = cm:get_faction(enemy_faction_name)
    end

    log(
        "cleanup_enemy_force_before_spawn started. reason=["
            .. tostring(reason)
            .. "], enemy_faction_name=["
            .. tostring(enemy_faction_name)
            .. "]."
    )

    if caravans and caravans.cleanup_post_battle then
        log("cleanup_enemy_force_before_spawn invoking caravans:cleanup_post_battle().")
        caravans:cleanup_post_battle()
    elseif enemy_faction and not enemy_faction:is_null_interface() and not enemy_faction:is_dead() then
        log(
            "cleanup_enemy_force_before_spawn invoking kill_all_armies_for_faction for enemy faction ["
                .. tostring(enemy_faction_name)
                .. "]."
        )
        cm:kill_all_armies_for_faction(enemy_faction)
    else
        log("cleanup_enemy_force_before_spawn found no valid enemy faction to clean.")
    end

    if caravans then
        caravans.enemy_force_cqi = 0
    end
    set_saved_value(SAVE_KEYS.enemy_force_cqi, 0)
    set_saved_value(SAVE_KEYS.enemy_leader_cqi, 0)
    set_saved_value(SAVE_KEYS.enemy_agent_cqi, 0)
end

local function find_node_data_by_key(node_key)
    for _, node_data in ipairs(NODE_POOL) do
        if node_data.node_key == node_key then
            return node_data
        end
    end

    return nil
end

local function find_node_data_by_faction_key(faction_key)
    for _, node_data in ipairs(NODE_POOL) do
        if node_data.faction_key == faction_key then
            return node_data
        end
    end

    return nil
end

local function clear_destination_selection_state(reason)
    set_saved_value(SAVE_KEYS.destination_candidate_node_keys, "")
    set_saved_value(SAVE_KEYS.destination_candidate_faction_keys, "")
    set_saved_value(SAVE_KEYS.destination_leave_current_enabled, "false")
    set_saved_value(SAVE_KEYS.destination_selection_generated, "false")
    set_saved_value(SAVE_KEYS.destination_generation_seed, 0)
    set_saved_value(SAVE_KEYS.destination_generation_attempts, 0)
    log("Destination selection state cleared. reason=[" .. tostring(reason) .. "].")
end

local function set_current_node(node_data, reason)
    if not node_data then
        log("set_current_node aborted because node_data is nil. reason=[" .. tostring(reason) .. "].")
        return false
    end

    set_saved_value(SAVE_KEYS.current_node_key, node_data.node_key)
    set_saved_value(SAVE_KEYS.current_node_faction_key, node_data.faction_key)
    log(
        "Current node updated. reason=["
            .. tostring(reason)
            .. "], node_key=["
            .. tostring(node_data.node_key)
            .. "], faction_key=["
            .. tostring(node_data.faction_key)
            .. "], culture_key=["
            .. tostring(node_data.culture_key)
            .. "]."
    )
    return true
end

local function ensure_current_node_initialized(reason)
    local current_node_key = get_saved_value(SAVE_KEYS.current_node_key, "")
    local current_node_faction_key = get_saved_value(SAVE_KEYS.current_node_faction_key, "")

    if current_node_key ~= "" then
        local existing_node = find_node_data_by_key(current_node_key)
        if existing_node then
            if current_node_faction_key ~= existing_node.faction_key then
                set_saved_value(SAVE_KEYS.current_node_faction_key, existing_node.faction_key)
                log(
                    "ensure_current_node_initialized repaired node faction key. reason=["
                        .. tostring(reason)
                        .. "], node_key=["
                        .. tostring(current_node_key)
                        .. "], stored_faction_key=["
                        .. tostring(current_node_faction_key)
                        .. "], repaired_faction_key=["
                        .. tostring(existing_node.faction_key)
                        .. "]."
                )
            end
            return existing_node
        end

        log(
            "ensure_current_node_initialized found an unknown node key and will reset it. reason=["
                .. tostring(reason)
                .. "], current_node_key=["
                .. tostring(current_node_key)
                .. "]."
        )
    end

    local preferred_player_faction_key = tostring(get_saved_value(SAVE_KEYS.player_faction_key, "") or "")
    if preferred_player_faction_key == "" then
        local local_player_faction = get_local_player_faction()
        if local_player_faction and not local_player_faction:is_null_interface() and not local_player_faction:is_dead() then
            preferred_player_faction_key = local_player_faction:name()
        end
    end

    local resolved_content_faction_key = nil
    if preferred_player_faction_key ~= "" then
        resolved_content_faction_key = resolve_player_content_faction_key(preferred_player_faction_key)
    end

    local starting_node = nil
    if resolved_content_faction_key and resolved_content_faction_key ~= "" then
        starting_node = find_node_data_by_faction_key(resolved_content_faction_key)
    end
    if not starting_node then
        starting_node = find_node_data_by_key(STARTING_NODE_KEY) or find_node_data_by_faction_key(DEFAULT_CONTENT_FACTION_KEY)
    end
    if not starting_node then
        log("ensure_current_node_initialized failed because no starting node could be resolved.")
        return nil
    end

    set_current_node(starting_node, reason or "initialize_default_node")
    return starting_node
end

local function get_current_node_data()
    local node_data = ensure_current_node_initialized("get_current_node_data")
    if not node_data then
        return nil
    end

    return node_data
end

local adamrogue_battle_generator = adamrogue_battle_generator_module.new({
    log = log,
    cm = cm,
    split_string = split_string,
    default_unit_pool = BATTLE_UNIT_POOLS_BY_CONTENT_FACTION[DEFAULT_CONTENT_FACTION_KEY] or {},
    unit_pools_by_faction = BATTLE_UNIT_POOLS_BY_CONTENT_FACTION,
    battle_tier = BATTLE_TIER,
    enemy_general_subtype = ENEMY_GENERAL_SUBTYPE,
    enemy_general_subtypes_by_faction = ENEMY_GENERAL_SUBTYPE_BY_CONTENT_FACTION,
    enemy_general_options_by_faction = ENEMY_GENERAL_OPTIONS_BY_CONTENT_FACTION,
    enemy_general_unit_values_by_faction = ENEMY_GENERAL_UNIT_VALUE_BY_CONTENT_FACTION,
    enemy_embedded_agent_subtype = ENEMY_EMBEDDED_AGENT_SUBTYPE,
    enemy_embedded_agent_subtypes_by_faction = ENEMY_EMBEDDED_AGENT_SUBTYPE_BY_CONTENT_FACTION,
    default_content_faction_key = DEFAULT_CONTENT_FACTION_KEY,
    default_enemy_faction_key = DEFAULT_ENEMY_FACTION_KEY,
    enemy_unit_count_config = BALANCE_CONFIG.enemy_unit_count,
    enemy_hero_pools_by_faction = ENEMY_HERO_POOLS_BY_CONTENT_FACTION,
    enemy_growth_config = BALANCE_CONFIG.enemy_growth
})

local get_battle_tier_for_progress = adamrogue_battle_generator.get_battle_tier_for_progress
local get_target_battle_budget = adamrogue_battle_generator.get_target_battle_budget
local build_budget_enemy_force_definition = adamrogue_battle_generator.build_budget_enemy_force_definition
local create_battle_payload_from_definition = adamrogue_battle_generator.create_battle_payload_from_definition
local log_unit_list_details = adamrogue_battle_generator.log_unit_list_details

local unit_value_lookup_cache = nil

local function build_unit_value_lookup()
    if unit_value_lookup_cache then
        return unit_value_lookup_cache
    end

    local lookup = {}
    for _, pool in pairs(BATTLE_UNIT_POOLS_BY_CONTENT_FACTION) do
        for _, entry in ipairs(pool) do
            local unit_key = entry.unit_key
            if unit_key and unit_key ~= "" then
                local unit_value = tonumber(entry.unit_value) or 0
                if not lookup[unit_key] or unit_value > lookup[unit_key] then
                    lookup[unit_key] = unit_value
                end
            end
        end
    end

    for _, options in pairs(PLAYER_GENERAL_OPTIONS_BY_FACTION) do
        for _, option in ipairs(options) do
            local unit_key = option.unit_key
            if unit_key and unit_key ~= "" then
                local unit_value = tonumber(option.unit_value) or 0
                if not lookup[unit_key] or unit_value > lookup[unit_key] then
                    lookup[unit_key] = unit_value
                end
            end
        end
    end

    unit_value_lookup_cache = lookup
    return lookup
end

local function get_unit_value_for_key(unit_key)
    if not unit_key or unit_key == "" then
        return 0
    end

    return tonumber(build_unit_value_lookup()[unit_key]) or 0
end

local function get_force_total_unit_value(force)
    if not force or force:is_null_interface() then
        return 0
    end

    local total_value = 0
    local unit_list = force:unit_list()
    for i = 0, unit_list:num_items() - 1 do
        local unit = unit_list:item_at(i)
        if unit and not unit:is_null_interface() then
            total_value = total_value + get_unit_value_for_key(unit:unit_key())
        end
    end

    return total_value
end

local function log_battle_balance_check(payload)
    local current_cycle = tonumber(payload and payload.current_cycle) or get_current_cycle()
    local player_force = get_saved_player_force()
    local player_value = player_force and get_force_total_unit_value(player_force) or 0
    local enemy_value = tonumber(payload and payload.generated_total_value) or 0

    log(
        "[Balance Check] TURN:["
            .. tostring(current_cycle)
            .. "] Player Value: ["
            .. tostring(player_value)
            .. "] VS Enemy Value ["
            .. tostring(enemy_value)
            .. "]"
    )
end

local function get_reward_unit_pool_for_faction(content_faction_key, battle_tier, use_battle_tier_filter)
    local source_pool = BATTLE_UNIT_POOLS_BY_CONTENT_FACTION[content_faction_key]
    local resolved_faction_key = content_faction_key

    if not source_pool or #source_pool == 0 then
        source_pool = BATTLE_UNIT_POOLS_BY_CONTENT_FACTION[DEFAULT_CONTENT_FACTION_KEY] or {}
        resolved_faction_key = DEFAULT_CONTENT_FACTION_KEY
        log(
            "[ERROR] get_reward_unit_pool_for_faction is falling back to the default content faction pool. requested_content_faction_key=["
                .. tostring(content_faction_key)
                .. "], resolved_content_faction_key=["
                .. tostring(resolved_faction_key)
                .. "], pool_size=["
                .. tostring(#source_pool)
                .. "]."
        )
    end

    local candidate_pool = {}
    local apply_tier_filter = use_battle_tier_filter == true
    for _, unit_entry in ipairs(source_pool) do
        if (not apply_tier_filter) or (battle_tier >= unit_entry.min_battle_tier and battle_tier <= unit_entry.max_battle_tier) then
            for _ = 1, math.max(1, unit_entry.weight or 1) do
                candidate_pool[#candidate_pool + 1] = unit_entry
            end
        end
    end

    log(
        "get_reward_unit_pool_for_faction completed. requested_content_faction_key=["
            .. tostring(content_faction_key)
            .. "], resolved_content_faction_key=["
            .. tostring(resolved_faction_key)
            .. "], battle_tier=["
            .. tostring(battle_tier)
            .. "], use_battle_tier_filter=["
            .. tostring(apply_tier_filter)
            .. "], weighted_pool_size=["
            .. tostring(#candidate_pool)
            .. "]."
    )
    return candidate_pool, resolved_faction_key
end

local function pick_reward_unit_from_pool(weighted_pool, excluded_units)
    if not weighted_pool or #weighted_pool == 0 then
        return nil
    end

    local blocked = excluded_units or {}
    for _ = 1, 30 do
        local unit_entry = weighted_pool[cm:random_number(#weighted_pool, 1)]
        if unit_entry and unit_entry.unit_key and not blocked[unit_entry.unit_key] then
            return unit_entry.unit_key, unit_entry
        end
    end

    for _, unit_entry in ipairs(weighted_pool) do
        if unit_entry and unit_entry.unit_key and not blocked[unit_entry.unit_key] then
            return unit_entry.unit_key, unit_entry
        end
    end

    return nil
end

local function build_reward_value_filtered_pool(weighted_pool, min_value, max_value, excluded_units)
    local blocked = excluded_units or {}
    local in_range_pool = {}
    local closest_lower_value = nil
    local closest_higher_value = nil

    for _, unit_entry in ipairs(weighted_pool or {}) do
        if unit_entry and unit_entry.unit_key and not blocked[unit_entry.unit_key] then
            local unit_value = tonumber(unit_entry.unit_value) or 0
            if unit_value >= min_value and unit_value <= max_value then
                in_range_pool[#in_range_pool + 1] = unit_entry
            elseif unit_value < min_value then
                if closest_lower_value == nil or unit_value > closest_lower_value then
                    closest_lower_value = unit_value
                end
            elseif unit_value > max_value then
                if closest_higher_value == nil or unit_value < closest_higher_value then
                    closest_higher_value = unit_value
                end
            end
        end
    end

    if #in_range_pool > 0 then
        return in_range_pool, "in_range", nil
    end

    -- Reward bands should degrade toward the nearest lower-value unit first so late-cycle dry spots
    -- do not abruptly jump to a stronger reward than the configured curve intended.
    if closest_lower_value ~= nil then
        local lower_pool = {}
        for _, unit_entry in ipairs(weighted_pool or {}) do
            if unit_entry and unit_entry.unit_key and not blocked[unit_entry.unit_key] then
                if (tonumber(unit_entry.unit_value) or 0) == closest_lower_value then
                    lower_pool[#lower_pool + 1] = unit_entry
                end
            end
        end

        if #lower_pool > 0 then
            return lower_pool, "closest_lower", closest_lower_value
        end
    end

    if closest_higher_value ~= nil then
        local higher_pool = {}
        for _, unit_entry in ipairs(weighted_pool or {}) do
            if unit_entry and unit_entry.unit_key and not blocked[unit_entry.unit_key] then
                if (tonumber(unit_entry.unit_value) or 0) == closest_higher_value then
                    higher_pool[#higher_pool + 1] = unit_entry
                end
            end
        end

        if #higher_pool > 0 then
            return higher_pool, "closest_higher", closest_higher_value
        end
    end

    return {}, "empty", nil
end

local function pick_reward_unit_for_value_band(weighted_pool, min_value, max_value, excluded_units, selection_label)
    local filtered_pool, resolution, resolved_value = build_reward_value_filtered_pool(weighted_pool, min_value, max_value, excluded_units)
    log(
        "pick_reward_unit_for_value_band prepared candidate pool. selection_label=["
            .. tostring(selection_label)
            .. "], min_value=["
            .. tostring(min_value)
            .. "], max_value=["
            .. tostring(max_value)
            .. "], resolution=["
            .. tostring(resolution)
            .. "], resolved_value=["
            .. tostring(resolved_value)
            .. "], filtered_pool_size=["
            .. tostring(#filtered_pool)
            .. "]."
    )

    local unit_key, unit_entry = pick_reward_unit_from_pool(filtered_pool, excluded_units)
    if unit_entry then
        log(
            "pick_reward_unit_for_value_band selected unit. selection_label=["
                .. tostring(selection_label)
                .. "], unit_key=["
                .. tostring(unit_key)
                .. "], unit_value=["
                .. tostring(unit_entry.unit_value)
                .. "], resolution=["
                .. tostring(resolution)
                .. "]."
        )
    end

    return unit_key, unit_entry, resolution, resolved_value
end

local adamrogue_ancillary_generator = adamrogue_ancillary_generator_module.new({
    log = log,
    cm = cm,
    common_pool = COMMON_EQUIPMENT_POOL,
    faction_pools = FACTION_EQUIPMENT_POOLS,
    battle_tier = BATTLE_TIER,
    equipment_rarity = EQUIPMENT_RARITY,
    slot_order = EQUIPMENT_REWARD_SLOT_ORDER,
    equipment_rarity_by_cycle = BALANCE_CONFIG.equipment_rarity_by_cycle,
    elite_battle_cycles = BALANCE_CONFIG.elite_battles and BALANCE_CONFIG.elite_battles.battle_cycles or {},
    elite_reward_highest_tier = BALANCE_CONFIG.elite_battles and BALANCE_CONFIG.elite_battles.reward_highest_tier == true
})

local generate_equipment_reward_payload = adamrogue_ancillary_generator.generate_equipment_reward_payload

local adamrogue_force_snapshot = adamrogue_force_snapshot_module.new({
    cm = cm,
    log = log,
    save_keys = SAVE_KEYS,
    get_default_player_general_subtype_for_faction = get_default_player_general_subtype_for_faction,
    get_saved_value = get_saved_value,
    set_saved_value = set_saved_value,
    split_string = split_string,
    count_units_in_force = count_units_in_force,
    get_spawn_region_and_position_for_faction = get_spawn_region_and_position_for_faction,
    get_saved_player_force = get_saved_player_force,
    get_saved_player_general = get_saved_player_general
})

local capture_pre_battle_force_snapshot = adamrogue_force_snapshot.capture_pre_battle_force_snapshot
local restore_player_force_after_battle = adamrogue_force_snapshot.restore_player_force_after_battle

local function encode_payload(payload)
    local entries = {}

    for key, value in pairs(payload) do
        entries[#entries + 1] = tostring(key) .. "=" .. tostring(value)
    end

    table.sort(entries)
    return table.concat(entries, "|")
end

local function decode_payload(serialized)
    local payload = {}
    log("decode_payload called. serialized=[" .. tostring(serialized) .. "]")

    if type(serialized) ~= "string" or serialized == "" then
        return payload
    end

    for _, entry in ipairs(split_string(serialized, "|")) do
        local key, value = string.match(entry, "^([^=]+)=(.*)$")
        if key ~= nil then
            payload[key] = value
        else
            log("decode_payload skipped malformed entry=[" .. tostring(entry) .. "]")
        end
    end

    log("decode_payload completed.")
    return payload
end

local function get_saved_payload_field(field_name, default_value)
    log("get_saved_payload_field requested. field=[" .. tostring(field_name) .. "]")
    local serialized_before_decode = get_saved_value(SAVE_KEYS.current_event_payload, "")
    log(
        "get_saved_payload_field raw serialized payload before decode. field=["
            .. tostring(field_name)
            .. "], serialized=["
            .. tostring(serialized_before_decode)
            .. "]"
    )

    local decode_ok, payload_or_error = pcall(get_current_event_payload)
    if not decode_ok then
        log(
            "get_saved_payload_field failed while decoding payload. field=["
                .. tostring(field_name)
                .. "], error=["
                .. tostring(payload_or_error)
                .. "]"
        )
        payload_or_error = {}
    else
        log("get_saved_payload_field decode step completed successfully. field=[" .. tostring(field_name) .. "]")
    end

    local payload = payload_or_error
    local value = payload[field_name]
    if value ~= nil and value ~= "" then
        log("get_saved_payload_field resolved from decoded payload. field=[" .. tostring(field_name) .. "], value=[" .. tostring(value) .. "]")
        return value
    end

    local serialized = serialized_before_decode
    if type(serialized) ~= "string" or serialized == "" then
        log("get_saved_payload_field fell back to default because serialized payload is empty. field=[" .. tostring(field_name) .. "]")
        return default_value
    end

    local pattern = field_name .. "=([^|]+)"
    local matched_value = string.match(serialized, pattern)
    if matched_value ~= nil and matched_value ~= "" then
        log("get_saved_payload_field resolved from serialized payload. field=[" .. tostring(field_name) .. "], value=[" .. tostring(matched_value) .. "]")
        return matched_value
    end

    log("get_saved_payload_field returned default. field=[" .. tostring(field_name) .. "], default=[" .. tostring(default_value) .. "]")
    return default_value
end

local function get_completed_battle_count()
    local value = get_saved_value(SAVE_KEYS.completed_battle_count, 0)
    log("get_completed_battle_count resolved value=[" .. tostring(value) .. "]")
    return value
end

local function get_consecutive_defeat_count()
    local value = get_saved_value(SAVE_KEYS.consecutive_defeat_count, 0)
    log("get_consecutive_defeat_count resolved value=[" .. tostring(value) .. "]")
    return value
end

local function overwrite_current_battle_payload(payload, reason)
    local encoded_payload = encode_payload(payload)
    set_saved_value(SAVE_KEYS.current_event_payload, encoded_payload)
    log(
        "overwrite_current_battle_payload applied. reason=["
            .. tostring(reason)
            .. "], encoded_payload=["
            .. tostring(encoded_payload)
            .. "]."
    )
end

local function regenerate_battle_payload_for_spawn_retry(spawn_attempt, failure_reason)
    local existing_payload = get_current_event_payload()
    local target_value_budget = tonumber(get_saved_payload_field("target_value_budget", 0)) or 0
    local battle_tier = tonumber(get_saved_payload_field("battle_budget_tier", BATTLE_TIER.EARLY)) or BATTLE_TIER.EARLY
    local previous_unit_list = get_saved_payload_field("enemy_unit_list", "")
    local player_faction_key = get_saved_value(SAVE_KEYS.player_faction_key, "")

    log(
        "regenerate_battle_payload_for_spawn_retry started. spawn_attempt=["
            .. tostring(spawn_attempt)
            .. "], failure_reason=["
            .. tostring(failure_reason)
            .. "], target_value_budget=["
            .. tostring(target_value_budget)
            .. "], battle_tier=["
            .. tostring(battle_tier)
            .. "], previous_unit_list=["
            .. tostring(previous_unit_list)
            .. "]."
    )
    log_unit_list_details("retry_previous_unit_list_attempt_" .. tostring(spawn_attempt), previous_unit_list)

    if target_value_budget <= 0 then
        log("regenerate_battle_payload_for_spawn_retry aborted because target_value_budget is invalid.")
        return nil
    end

    if not existing_payload or not existing_payload.enemy_unit_list or existing_payload.enemy_unit_list == "" then
        log("regenerate_battle_payload_for_spawn_retry aborted because the existing payload is missing enemy_unit_list.")
        return nil
    end

    -- Retry the caravan spawn with the next configured faction before falling back to create_force.
    if spawn_attempt > 1 then
        local content_faction_key = existing_payload.battle_content_faction_key or DEFAULT_CONTENT_FACTION_KEY
        local configured_candidates = get_enemy_faction_candidate_sequence(
            player_faction_key,
            existing_payload.enemy_faction_key or DEFAULT_ENEMY_FACTION_KEY,
            existing_payload.enemy_faction_candidates or "",
            content_faction_key
        )

        local target_candidate_index = spawn_attempt
        local resolved_retry_faction_key = nil

        for index = target_candidate_index, #configured_candidates do
            local faction_key = configured_candidates[index]
            local faction = cm:get_faction(faction_key)
            if faction_key ~= player_faction_key and can_use_faction_for_enemy_spawn(faction) then
                resolved_retry_faction_key = faction_key
                target_candidate_index = index
                break
            end
        end

        if not resolved_retry_faction_key then
            log(
                "regenerate_battle_payload_for_spawn_retry could not resolve a valid retry faction candidate. requested_spawn_attempt=["
                    .. tostring(spawn_attempt)
                    .. "], enemy_faction_candidates=["
                    .. table.concat(configured_candidates, ",")
                    .. "]."
            )
            return nil
        end

        existing_payload.enemy_faction_key = resolved_retry_faction_key
        existing_payload.spawn_retry_index = target_candidate_index - 1
        log(
            "regenerate_battle_payload_for_spawn_retry selected next faction candidate for caravan spawn retry. candidate_index=["
                .. tostring(target_candidate_index)
                .. "], enemy_faction_key=["
                .. tostring(resolved_retry_faction_key)
                .. "]."
        )
    else
        existing_payload.spawn_retry_index = spawn_attempt - 1
    end

    existing_payload.retry_reason = failure_reason or "retry_requested"
    local payload = existing_payload
    overwrite_current_battle_payload(payload, "spawn_retry_" .. tostring(spawn_attempt))
    log_unit_list_details("retry_preserved_unit_list_attempt_" .. tostring(spawn_attempt), payload.enemy_unit_list)
    return payload
end

local function get_current_event_type()
    return get_saved_value(SAVE_KEYS.current_event_type, "")
end

local function get_current_event_key()
    return get_saved_value(SAVE_KEYS.current_event_key, "")
end

local function get_current_event_seed()
    return get_saved_value(SAVE_KEYS.current_event_seed, 0)
end

get_current_event_payload = function()
    local serialized = get_saved_value(SAVE_KEYS.current_event_payload, "")
    log("get_current_event_payload called. serialized=[" .. tostring(serialized) .. "]")
    return decode_payload(serialized)
end

local function set_current_event_context(event_type, event_key, event_seed, payload)
    set_saved_value(SAVE_KEYS.current_event_type, event_type)
    set_saved_value(SAVE_KEYS.current_event_key, event_key)
    set_saved_value(SAVE_KEYS.current_event_seed, event_seed)
    set_saved_value(SAVE_KEYS.current_event_payload, encode_payload(payload))

    log(
        "Event context saved. type=["
            .. tostring(event_type)
            .. "], key=["
            .. tostring(event_key)
            .. "], seed=["
            .. tostring(event_seed)
            .. "], payload=["
            .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
            .. "]"
    )
end

local function clear_current_event_context()
    set_saved_value(SAVE_KEYS.current_event_type, "")
    set_saved_value(SAVE_KEYS.current_event_key, "")
    set_saved_value(SAVE_KEYS.current_event_seed, 0)
    set_saved_value(SAVE_KEYS.current_event_payload, "")
end

local function new_event_seed()
    return cm:random_number(2147483647)
end

local function force_attack_once(attacker_force_cqi, defender_force_cqi, source_label)
    log(
        "Launching forced test battle from ["
            .. tostring(source_label)
            .. "]. Attacker force CQI="
            .. tostring(attacker_force_cqi)
            .. ", Defender force CQI="
            .. tostring(defender_force_cqi)
    )

    cm:callback(function()
        cm:force_attack_of_opportunity(attacker_force_cqi, defender_force_cqi, false, true)
    end, 0.05)
end

local function create_formal_entry_button()
    local button_group_management = find_uicomponent(core:get_ui_root(), "hud_campaign", "faction_buttons_docker", "button_group_management")
    if not button_group_management then
        return
    end

    local button = core:get_or_create_component(
        "button_adamrogue_phase_a_entry",
        "ui/campaign ui/adamrogue_phase_a_entry_button.twui.xml",
        button_group_management
    )

    if button then
        button:SetTooltipText(common.get_localised_string("campaign_localised_strings_button_adamrogue_phase_a_tooltip"), true)
    end
end

local function ensure_run_started()
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Local player faction is not supported yet. Waiting for a supported human faction.")
        return false
    end

    if get_saved_value(SAVE_KEYS.run_started, false) then
        return true
    end

    local region_key, x, y = get_spawn_region_and_position_for_faction(faction)
    if not region_key then
        log("Failed to find a valid spawn position for the player test force.")
        return false
    end

    log(string.format("Spawning player test force for [%s] at (%s, %s) in region [%s]", faction:name(), tostring(x), tostring(y), region_key))
    local resolved_player_content_faction_key = resolve_player_content_faction_key(faction:name())
    local selected_player_general_option = pick_random_player_general_option(faction:name())
    local player_general_subtype = selected_player_general_option.subtype or get_default_player_general_subtype_for_faction(faction:name())
    local starting_unit_list, logged_starting_unit_list, starting_unit_value, resolved_starting_pool_faction_key =
        build_starting_player_unit_list(faction:name(), selected_player_general_option)
    log(
        "Spawning randomized player test force. faction=["
            .. faction:name()
            .. "], resolved_player_content_faction_key=["
            .. tostring(resolved_player_content_faction_key)
            .. "], selected_general_unit_key=["
            .. tostring(selected_player_general_option.unit_key or "")
            .. "], general_subtype=["
            .. tostring(player_general_subtype)
            .. "], general_value=["
            .. tostring(selected_player_general_option.unit_value or 0)
            .. "], resolved_starting_pool_faction_key=["
            .. tostring(resolved_starting_pool_faction_key)
            .. "], starting_unit_value=["
            .. tostring(starting_unit_value)
            .. "], target_value_budget=["
            .. tostring(math.max(0, (tonumber(BALANCE_CONFIG.initial_player_value) or 4500) - (tonumber(selected_player_general_option.unit_value) or 0)))
            .. "], starting_unit_list=["
            .. tostring(logged_starting_unit_list)
            .. "]."
    )

    cm:create_force_with_general(
        faction:name(),
        starting_unit_list,
        region_key,
        x,
        y,
        "general",
        player_general_subtype,
        "",
        "",
        "",
        "",
        false,
        function(character_cqi)
            local character = cm:get_character_by_cqi(character_cqi)
            if not character or character:is_null_interface() or not character:has_military_force() then
                log("Player test force creation callback fired, but the created general was invalid.")
                return
            end

            local force = character:military_force()
            set_saved_value(SAVE_KEYS.run_started, true)
            set_saved_value(SAVE_KEYS.player_faction_key, faction:name())
            set_saved_value(SAVE_KEYS.player_general_subtype, character:character_subtype_key())
            set_saved_value(SAVE_KEYS.player_leader_cqi, character:command_queue_index())
            set_saved_value(SAVE_KEYS.player_force_cqi, force:command_queue_index())
            set_saved_value(SAVE_KEYS.completed_battle_count, get_saved_value(SAVE_KEYS.completed_battle_count, 0))
            set_saved_value(SAVE_KEYS.victory_count, get_saved_value(SAVE_KEYS.victory_count, 0))
            set_saved_value(SAVE_KEYS.defeat_count, get_saved_value(SAVE_KEYS.defeat_count, 0))
            set_saved_value(SAVE_KEYS.consecutive_defeat_count, get_saved_value(SAVE_KEYS.consecutive_defeat_count, 0))

            clear_current_event_context()
            clear_destination_selection_state("player_force_created")
            local starting_node = find_node_data_by_faction_key(resolved_player_content_faction_key)
            if not starting_node then
                starting_node = ensure_current_node_initialized("player_force_created")
            else
                set_current_node(starting_node, "player_force_created_from_player_faction")
            end
            ensure_balance_state_initialized("player_force_created")
            set_saved_value(SAVE_KEYS.paused_from_state, "")
            set_current_state(STATE.INIT)

            log(
                "Player test force created. General CQI="
                    .. tostring(character:command_queue_index())
                    .. ", Force CQI="
                    .. tostring(force:command_queue_index())
                    .. ", Units="
                    .. tostring(count_units_in_force(force))
                    .. ", general_subtype=["
                    .. tostring(character:character_subtype_key())
                    .. "], starting_unit_value=["
                    .. tostring(starting_unit_value)
                    .. ", current_cycle=["
                    .. tostring(get_current_cycle())
                    .. "], difficulty_level=["
                    .. tostring(get_difficulty_level())
                    .. "]."
            )
        end
    )

    return true
end

-- 生成预览部队（不设 run_started，生成完成后自动弹出预览困境）。
-- 用于首次或重新随机时；若玩家点"稍后"则部队留在地图，下次点击按钮直接弹出困境而不重复生成。
local function spawn_new_preview_army(faction)
    local region_key, x, y = get_spawn_region_and_position_for_faction(faction)
    if not region_key then
        log("spawn_new_preview_army: failed to find a valid spawn position for faction [" .. faction:name() .. "].")
        return false
    end

    local resolved_player_content_faction_key = resolve_player_content_faction_key(faction:name())
    local selected_player_general_option = pick_random_player_general_option(faction:name())
    local player_general_subtype = selected_player_general_option.subtype
        or get_default_player_general_subtype_for_faction(faction:name())
    local starting_unit_list, logged_starting_unit_list, starting_unit_value, resolved_starting_pool_faction_key =
        build_starting_player_unit_list(faction:name(), selected_player_general_option)
    log(
        "spawn_new_preview_army: spawning. faction=["
            .. faction:name()
            .. "], subtype=["
            .. tostring(player_general_subtype)
            .. "], unit_value=["
            .. tostring(selected_player_general_option.unit_value or 0)
            .. "], starting_unit_value=["
            .. tostring(starting_unit_value)
            .. "], unit_list=["
            .. tostring(logged_starting_unit_list)
            .. "]."
    )

    local faction_name_capture = faction:name()
    cm:create_force_with_general(
        faction_name_capture,
        starting_unit_list,
        region_key,
        x,
        y,
        "general",
        player_general_subtype,
        "",
        "",
        "",
        "",
        false,
        function(character_cqi)
            local character = cm:get_character_by_cqi(character_cqi)
            if not character or character:is_null_interface() or not character:has_military_force() then
                log("spawn_new_preview_army callback: created general was invalid.")
                return
            end

            local force = character:military_force()
            set_saved_value(SAVE_KEYS.player_faction_key, faction_name_capture)
            set_saved_value(SAVE_KEYS.player_general_subtype, character:character_subtype_key())
            set_saved_value(SAVE_KEYS.player_leader_cqi, character:command_queue_index())
            set_saved_value(SAVE_KEYS.player_force_cqi, force:command_queue_index())

            clear_current_event_context()
            clear_destination_selection_state("preview_army_created")
            local starting_node = find_node_data_by_faction_key(resolved_player_content_faction_key)
            if not starting_node then
                starting_node = ensure_current_node_initialized("preview_army_created")
            else
                set_current_node(starting_node, "preview_army_created_from_player_faction")
            end
            ensure_balance_state_initialized("preview_army_created")
            set_saved_value(SAVE_KEYS.paused_from_state, "")
            set_current_state(STATE.ARMY_PREVIEW_PENDING)

            log(
                "spawn_new_preview_army callback: preview army created. cqi=["
                    .. tostring(character_cqi)
                    .. "], subtype=["
                    .. tostring(character:character_subtype_key())
                    .. "]. Launching army preview dilemma."
            )

            local preview_faction = cm:get_faction(faction_name_capture)
            if preview_faction and not preview_faction:is_null_interface() then
                launch_army_preview_dilemma(preview_faction)
            end
        end
    )
    return true
end

-- 战役层无法像战斗脚本那样禁止援军入场；附近同战争派系军队仍可能加入 pending battle。
-- 首次点击 Mod 入口按钮时，先与所有交战派系强制议和，避免原版外交战争中的援军卷入 Mod 战斗。
local function force_peace_with_all_player_enemies(player_faction, reason_label)
    if not player_faction or player_faction:is_null_interface() then
        log("force_peace_with_all_player_enemies aborted: invalid player faction. reason=[" .. tostring(reason_label) .. "].")
        return 0
    end

    local war_factions = player_faction:factions_at_war_with()
    if not war_factions or war_factions:is_empty() then
        log("force_peace_with_all_player_enemies: player has no active wars. reason=[" .. tostring(reason_label) .. "].")
        return 0
    end

    local enemy_faction_keys = {}
    for i = 0, war_factions:num_items() - 1 do
        local enemy_faction = war_factions:item_at(i)
        if enemy_faction and not enemy_faction:is_null_interface() and not enemy_faction:is_dead() then
            table.insert(enemy_faction_keys, enemy_faction:name())
        end
    end

    if #enemy_faction_keys == 0 then
        log("force_peace_with_all_player_enemies: no valid enemy factions to pacify. reason=[" .. tostring(reason_label) .. "].")
        return 0
    end

    log(
        "force_peace_with_all_player_enemies started. player_faction=["
            .. player_faction:name()
            .. "], enemy_count=["
            .. tostring(#enemy_faction_keys)
            .. "], reason=["
            .. tostring(reason_label)
            .. "]."
    )

    cm:disable_event_feed_events(true, "wh_event_category_diplomacy", "", "")
    for _, enemy_faction_key in ipairs(enemy_faction_keys) do
        log("force_peace_with_all_player_enemies: " .. player_faction:name() .. " <-> " .. tostring(enemy_faction_key))
        cm:force_make_peace(player_faction:name(), enemy_faction_key)
    end
    cm:disable_event_feed_events(false, "wh_event_category_diplomacy", "", "")

    return #enemy_faction_keys
end

local function ensure_initial_peace_on_first_entry(player_faction, reason)
    if get_saved_value(SAVE_KEYS.initial_peace_applied, false) then
        return false
    end

    if reason ~= "ui_button" then
        return false
    end

    local peace_count = force_peace_with_all_player_enemies(player_faction, reason)
    set_saved_value(SAVE_KEYS.initial_peace_applied, true)
    log(
        "ensure_initial_peace_on_first_entry finished. peace_count=["
            .. tostring(peace_count)
            .. "], reason=["
            .. tostring(reason)
            .. "]."
    )
    return true
end

-- 若单位价值处于 (min_value, double_line) 开区间内，奖励两个；否则奖励一个。
-- double_line = 0 视为本轮不启用双倍奖励。
local function compute_reward_unit_count(unit_value, value_band)
    local dl = tonumber(value_band.double_line) or 0
    local mv = tonumber(value_band.min_value) or 0
    if dl > 0 and unit_value >= mv and unit_value < dl then
        return 2
    end
    return 1
end

function adamrogue_is_hero_reward_cycle(cycle)
    local normalized_cycle = math.max(1, math.floor(tonumber(cycle) or 1))
    return normalized_cycle == 5
        or normalized_cycle == 10
        or normalized_cycle == 15
        or normalized_cycle == 20
        or normalized_cycle == 25
end

function adamrogue_pick_unique_player_hero_options(hero_pool, target_count)
    local selected = {}
    local selected_lookup = {}
    local attempts = 0
    local max_attempts = math.max(30, (target_count or 3) * 20)

    if not hero_pool or #hero_pool == 0 then
        return selected
    end

    local weighted_pool = {}
    for _, hero_entry in ipairs(hero_pool) do
        if hero_entry and hero_entry.agent_subtype and hero_entry.agent_subtype ~= "" then
            for _ = 1, math.max(1, tonumber(hero_entry.weight) or 1) do
                weighted_pool[#weighted_pool + 1] = hero_entry
            end
        end
    end

    while #selected < target_count and attempts < max_attempts and #weighted_pool > 0 do
        attempts = attempts + 1
        local candidate = weighted_pool[cm:random_number(#weighted_pool, 1)]
        if candidate and not selected_lookup[candidate.agent_subtype] then
            selected_lookup[candidate.agent_subtype] = true
            selected[#selected + 1] = candidate
        end
    end

    if #selected < target_count then
        for _, candidate in ipairs(hero_pool) do
            if #selected >= target_count then
                break
            end
            if candidate and candidate.agent_subtype and not selected_lookup[candidate.agent_subtype] then
                selected_lookup[candidate.agent_subtype] = true
                selected[#selected + 1] = candidate
            end
        end
    end

    return selected
end

function adamrogue_prepare_player_hero_reward_event()
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("prepare_player_hero_reward_event aborted because the local faction is unsupported.")
        return false
    end
    if not faction or faction:is_null_interface() then
        log("prepare_player_hero_reward_event aborted because the local faction interface is invalid.")
        return false
    end
    local faction_name = faction:name()

    local current_cycle = get_current_cycle()
    if not adamrogue_is_hero_reward_cycle(current_cycle) then
        log("prepare_player_hero_reward_event skipped because current_cycle=[" .. tostring(current_cycle) .. "] is not a hero reward cycle.")
        return false
    end

    local player_content_faction_key, player_content_resolution = resolve_player_content_faction_key(faction_name)
    local hero_pool = ENEMY_HERO_POOLS_BY_CONTENT_FACTION[player_content_faction_key] or {}
    local selected_heroes = adamrogue_pick_unique_player_hero_options(hero_pool, 3)
    if #selected_heroes < 3 then
        log(
            "prepare_player_hero_reward_event aborted because fewer than 3 hero options were available. faction=["
                .. tostring(faction_name)
                .. "], player_content_faction_key=["
                .. tostring(player_content_faction_key)
                .. "], available=["
                .. tostring(#hero_pool)
                .. "], selected=["
                .. tostring(#selected_heroes)
                .. "]."
        )
        return false
    end

    local seed = new_event_seed()
    local payload = {
        hero_current_cycle = current_cycle,
        hero_player_faction_key = faction_name,
        hero_content_faction_key = player_content_faction_key,
        hero_content_resolution = player_content_resolution,
        pause_choice = 3,
        unit_reward_choice = 4
    }

    for index = 0, 2 do
        local hero_entry = selected_heroes[index + 1]
        if not hero_entry then
            log("prepare_player_hero_reward_event aborted because selected_heroes unexpectedly lost an entry at index=[" .. tostring(index) .. "].")
            return false
        end
        payload["hero_" .. tostring(index) .. "_agent_type"] = hero_entry.agent_type
        payload["hero_" .. tostring(index) .. "_agent_subtype"] = hero_entry.agent_subtype
        payload["hero_" .. tostring(index) .. "_unit_key"] = hero_entry.unit_key
        payload["hero_" .. tostring(index) .. "_unit_value"] = hero_entry.unit_value
    end

    set_current_event_context(EVENT_TYPE.HERO_REWARD, DILEMMA_HERO_REWARD_KEY, seed, payload)
    set_current_state(STATE.HERO_REWARD_PENDING)
    log(
        "Prepared player hero reward event. faction=["
            .. tostring(faction_name)
            .. "], content_faction=["
            .. tostring(player_content_faction_key)
            .. "], current_cycle=["
            .. tostring(current_cycle)
            .. "], heroes=["
            .. tostring(payload.hero_0_agent_subtype)
            .. ","
            .. tostring(payload.hero_1_agent_subtype)
            .. ","
            .. tostring(payload.hero_2_agent_subtype)
            .. "]."
    )
    return true
end

local function prepare_unit_reward_event()
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot prepare unit reward event because the local faction is unsupported.")
        return false
    end

    local current_node = get_current_node_data()
    if not current_node then
        log("prepare_unit_reward_event aborted because the current node could not be resolved.")
        return false
    end

    local completed_battle_count = get_completed_battle_count()
    local battle_tier = get_battle_tier_for_progress(completed_battle_count)
    local current_cycle = get_current_cycle()
    local reward_value_band = get_player_reward_value_band_for_cycle(current_cycle)
    local resolved_player_content_faction_key, player_content_resolution = resolve_player_content_faction_key(faction:name())
    local player_pool, resolved_player_pool_faction_key =
        get_reward_unit_pool_for_faction(resolved_player_content_faction_key, battle_tier, false)
    local node_pool, resolved_node_pool_faction_key = get_reward_unit_pool_for_faction(current_node.faction_key, battle_tier, false)
    if #player_pool == 0 or #node_pool == 0 then
        log(
            "prepare_unit_reward_event aborted because one or more weighted reward pools are empty. player_pool_size=["
                .. tostring(#player_pool)
                .. "], node_pool_size=["
                .. tostring(#node_pool)
                .. "]."
        )
        return false
    end

    local chosen_units = {}
    local chosen_lookup = {}
    local selected_entries = {}
    local unit_0, unit_0_entry = pick_reward_unit_for_value_band(
        player_pool,
        reward_value_band.min_value,
        reward_value_band.max_value,
        chosen_lookup,
        "player_choice_0"
    )
    if not unit_0 then
        log("prepare_unit_reward_event is falling back to unconstrained player reward choice 0 selection.")
        unit_0, unit_0_entry = pick_reward_unit_from_pool(player_pool, chosen_lookup)
    end
    if not unit_0 then
        log("prepare_unit_reward_event aborted because player reward choice 0 could not be generated.")
        return false
    end
    chosen_lookup[unit_0] = true
    chosen_units[0] = unit_0
    selected_entries[0] = unit_0_entry

    local unit_1, unit_1_entry = pick_reward_unit_for_value_band(
        player_pool,
        reward_value_band.min_value,
        reward_value_band.max_value,
        chosen_lookup,
        "player_choice_1"
    )
    if not unit_1 then
        log("prepare_unit_reward_event is falling back to unconstrained player reward choice 1 selection.")
        unit_1, unit_1_entry = pick_reward_unit_from_pool(player_pool, chosen_lookup)
    end
    if not unit_1 then
        log("prepare_unit_reward_event aborted because player reward choice 1 could not be generated.")
        return false
    end
    chosen_lookup[unit_1] = true
    chosen_units[1] = unit_1
    selected_entries[1] = unit_1_entry

    local unit_2, unit_2_entry = pick_reward_unit_for_value_band(
        node_pool,
        reward_value_band.min_value,
        reward_value_band.max_value,
        chosen_lookup,
        "node_choice_2"
    )
    if not unit_2 then
        log("prepare_unit_reward_event is falling back to unconstrained node reward choice 2 selection.")
        unit_2, unit_2_entry = pick_reward_unit_from_pool(node_pool, chosen_lookup)
    end
    if not unit_2 then
        log("prepare_unit_reward_event aborted because node reward choice 2 could not be generated.")
        return false
    end
    chosen_units[2] = unit_2
    chosen_lookup[unit_2] = true
    selected_entries[2] = unit_2_entry

    local unit_0_value = selected_entries[0] and selected_entries[0].unit_value or 0
    local unit_1_value = selected_entries[1] and selected_entries[1].unit_value or 0
    local unit_2_value = selected_entries[2] and selected_entries[2].unit_value or 0
    local unit_0_count = compute_reward_unit_count(unit_0_value, reward_value_band)
    local unit_1_count = compute_reward_unit_count(unit_1_value, reward_value_band)
    local unit_2_count = compute_reward_unit_count(unit_2_value, reward_value_band)

    local seed = new_event_seed()
    local payload = {
        unit_0 = chosen_units[0],
        unit_1 = chosen_units[1],
        unit_2 = chosen_units[2],
        unit_0_value = unit_0_value,
        unit_1_value = unit_1_value,
        unit_2_value = unit_2_value,
        unit_0_count = unit_0_count,
        unit_1_count = unit_1_count,
        unit_2_count = unit_2_count,
        reward_player_faction_key = resolved_player_content_faction_key,
        reward_current_node_faction_key = current_node.faction_key,
        reward_player_pool_faction_key = resolved_player_pool_faction_key,
        reward_node_pool_faction_key = resolved_node_pool_faction_key,
        reward_battle_tier = battle_tier,
        reward_completed_battle_count = completed_battle_count,
        reward_current_cycle = current_cycle,
        reward_target_min_value = reward_value_band.min_value,
        reward_target_max_value = reward_value_band.max_value,
        reward_base_min_value = reward_value_band.base_min_value,
        reward_base_max_value = reward_value_band.base_max_value,
        reward_double_line = reward_value_band.double_line,
        reward_player_value_multiplier = reward_value_band.player_reward_value_multiplier,
        pause_choice = 3
    }

    set_current_event_context(EVENT_TYPE.UNIT_REWARD, DILEMMA_REWARD_KEY, seed, payload)
    set_current_state(STATE.UNIT_REWARD_PENDING)
    log(
        "Prepared unit reward event for faction ["
            .. faction:name()
            .. "]. current_node_faction_key=["
            .. tostring(current_node.faction_key)
            .. "], battle_tier=["
            .. tostring(battle_tier)
            .. "], current_cycle=["
            .. tostring(current_cycle)
            .. "], reward_value_range=["
            .. tostring(reward_value_band.min_value)
            .. ","
            .. tostring(reward_value_band.max_value)
            .. "], reward_double_line=["
            .. tostring(reward_value_band.double_line)
            .. "], reward_values=["
            .. tostring(payload.unit_0_value)
            .. ","
            .. tostring(payload.unit_1_value)
            .. ","
            .. tostring(payload.unit_2_value)
            .. "], reward_counts=["
            .. tostring(payload.unit_0_count)
            .. ","
            .. tostring(payload.unit_1_count)
            .. ","
            .. tostring(payload.unit_2_count)
            .. "], reward_units=["
            .. tostring(chosen_units[0])
            .. ","
            .. tostring(chosen_units[1])
            .. ","
            .. tostring(chosen_units[2])
            .. "], reward_player_pool_faction_key=["
            .. tostring(resolved_player_pool_faction_key)
            .. "], reward_player_content_resolution=["
            .. tostring(player_content_resolution)
            .. "], reward_node_pool_faction_key=["
            .. tostring(resolved_node_pool_faction_key)
            .. "]."
    )
    return true
end

local function prepare_battle_event()
    log("prepare_battle_event started.")
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot prepare battle event because the local faction is unsupported.")
        return false
    end

    local current_node = get_current_node_data()
    if not current_node then
        log("prepare_battle_event aborted because the current node could not be resolved.")
        return false
    end

    local current_cycle = get_current_cycle()
    local completed_battle_count = get_completed_battle_count()
    local battle_tier = get_battle_tier_for_progress(completed_battle_count)
    local budget_context = get_enemy_value_budget_for_cycle(current_cycle)
    local target_value_budget = budget_context.final_value
    log(
        "prepare_battle_event progress resolved. current_cycle=["
            .. tostring(current_cycle)
            .. "], completed_battle_count=["
            .. tostring(completed_battle_count)
            .. "], battle_tier=["
            .. tostring(battle_tier)
            .. "], target_value_budget=["
            .. tostring(target_value_budget)
            .. "], budget_before_difficulty=["
            .. tostring(budget_context.value_before_difficulty)
            .. "], difficulty_multiplier=["
            .. tostring(budget_context.difficulty_multiplier)
            .. "], elite_battle=["
            .. tostring(budget_context.elite_battle)
            .. "], elite_multiplier=["
            .. tostring(budget_context.elite_multiplier)
            .. "], current_node_key=["
            .. tostring(current_node.node_key)
            .. "], current_node_faction_key=["
            .. tostring(current_node.faction_key)
            .. "]."
    )
    local battle_definition = build_budget_enemy_force_definition(
        target_value_budget,
        battle_tier,
        true,
        current_node.faction_key,
        {
            current_cycle = current_cycle
        }
    )
    if not battle_definition then
        log("Failed to generate a budget-based enemy force for the battle event using the current node context.")
        return false
    end

    local player_general = get_saved_player_general()
    if not player_general then
        log("prepare_battle_event aborted because the saved player general could not be resolved.")
        return false
    end

    local spawn_content_faction_key = battle_definition.content_faction_key or current_node.faction_key
    local enemy_faction_candidates = get_enemy_faction_candidates_for_content_faction(spawn_content_faction_key)
    local enemy_faction_key = enemy_faction_candidates[1] or DEFAULT_ENEMY_FACTION_KEY
    if not enemy_faction_key or enemy_faction_key == "" then
        enemy_faction_key = DEFAULT_ENEMY_FACTION_KEY
        log(
            "prepare_battle_event could not resolve a faction-specific enemy candidate list and is falling back to the default enemy faction key=["
                .. tostring(enemy_faction_key)
                .. "]."
        )
    end

    log(
        "prepare_battle_event deferred enemy faction spawn validation to battle launch time. current_node_faction_key=["
            .. tostring(current_node.faction_key)
            .. "], spawn_content_faction_key=["
            .. tostring(spawn_content_faction_key)
            .. "], seeded_enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "], enemy_faction_candidates=["
            .. table.concat(enemy_faction_candidates, ",")
            .. "]."
    )

    local seed = new_event_seed()
    local payload = create_battle_payload_from_definition(battle_definition, target_value_budget, battle_tier, 0, enemy_faction_key)
    payload.enemy_faction_candidates = table.concat(enemy_faction_candidates, ",")
    payload.current_node_key = current_node.node_key
    payload.current_node_faction_key = current_node.faction_key
    payload.current_cycle = current_cycle
    payload.enemy_value_before_difficulty = budget_context.value_before_difficulty
    payload.enemy_value_after_difficulty = budget_context.value_after_difficulty
    payload.enemy_value_difficulty_multiplier = budget_context.difficulty_multiplier
    payload.elite_battle = budget_context.elite_battle and "true" or "false"
    payload.elite_enemy_value_multiplier = budget_context.elite_multiplier

    set_saved_value(SAVE_KEYS.enemy_faction_key, enemy_faction_key)
    set_current_event_context(EVENT_TYPE.BATTLE, DILEMMA_BATTLE_KEY, seed, payload)
    set_current_state(STATE.BATTLE_PENDING)
    log(
        "Building enemy force with budget ["
            .. tostring(target_value_budget)
            .. "], value_source=["
            .. UNIT_VALUE_SOURCE
            .. "], tier=["
            .. tostring(battle_tier)
            .. "], generated_unit_count=["
            .. tostring(payload.generated_unit_count)
            .. "], min_unit_target=["
            .. tostring(payload.min_unit_target)
            .. "], desired_unit_target=["
            .. tostring(payload.desired_unit_target)
            .. "], battle_content_faction_key=["
            .. tostring(payload.battle_content_faction_key)
            .. "], battle_content_pool_fallback=["
            .. tostring(payload.battle_content_pool_fallback)
            .. "]."
    )
    log(
        "Generated enemy force total_value=["
            .. tostring(battle_definition.generated_total_value)
            .. "], delta=["
            .. tostring(battle_definition.budget_delta)
            .. "], units=["
            .. tostring(payload.enemy_unit_list)
            .. "], enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "], current_node_key=["
            .. tostring(current_node.node_key)
            .. "], current_node_faction_key=["
            .. tostring(current_node.faction_key)
            .. "]."
    )
    log_unit_list_details("prepare_battle_event_generated_payload", payload.enemy_unit_list)
    log(
        "Prepared battle event for faction ["
            .. faction:name()
            .. "] against enemy faction ["
            .. enemy_faction_key
            .. "]. current_cycle=["
            .. tostring(current_cycle)
            .. "], elite_battle=["
            .. tostring(budget_context.elite_battle)
            .. "], target_value_budget=["
            .. tostring(target_value_budget)
            .. "]."
    )
    return true
end

local function prepare_equipment_reward_event()
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot prepare equipment reward event because the local faction is unsupported.")
        return false
    end

    local current_node = get_current_node_data()
    if not current_node then
        log("prepare_equipment_reward_event aborted because the current node could not be resolved.")
        return false
    end

    local completed_battle_count = get_completed_battle_count()
    local battle_tier = get_battle_tier_for_progress(completed_battle_count)
    local current_cycle = get_current_cycle()
    local elite_battle = is_elite_battle_cycle(current_cycle)
    local rarity_context = get_equipment_rarity_context_for_cycle(current_cycle)
    local resolved_player_content_faction_key, player_content_resolution = resolve_player_content_faction_key(faction:name())
    local payload = generate_equipment_reward_payload(
        completed_battle_count,
        battle_tier,
        resolved_player_content_faction_key,
        current_node.faction_key,
        {
            current_cycle = current_cycle,
            elite_battle = elite_battle,
            force_highest_rarity = elite_battle and BALANCE_CONFIG.elite_battles and BALANCE_CONFIG.elite_battles.reward_highest_tier == true
        }
    )
    if not payload or type(payload) ~= "table" or tonumber(payload.candidate_count) == 0 then
        log("prepare_equipment_reward_event aborted because no equipment reward candidates were generated.")
        return false
    end

    payload.current_node_key = current_node.node_key
    payload.current_node_faction_key = current_node.faction_key
    local seed = new_event_seed()
    set_current_event_context(EVENT_TYPE.EQUIPMENT_REWARD, DILEMMA_EQUIPMENT_REWARD_KEY, seed, payload)
    set_current_state(STATE.EQUIPMENT_REWARD_PENDING)
    log(
        "Prepared equipment reward event for faction ["
            .. faction:name()
            .. "], current_node_key=["
            .. tostring(current_node.node_key)
            .. "], current_node_faction_key=["
            .. tostring(current_node.faction_key)
            .. "], current_cycle=["
            .. tostring(current_cycle)
            .. "], resolved_player_content_faction_key=["
            .. tostring(resolved_player_content_faction_key)
            .. "], player_content_resolution=["
            .. tostring(player_content_resolution)
            .. "], cycle_allowed_rarity_bands=["
            .. table.concat(rarity_context.tiers, ",")
            .. "], elite_battle=["
            .. tostring(elite_battle)
            .. "]. selected_rarity_band=["
            .. tostring(payload.selected_rarity_band)
            .. "], candidate_count=["
            .. tostring(payload.candidate_count)
            .. "], fallback_strategy_used=["
            .. tostring(payload.fallback_strategy_used)
            .. "]."
    )
    return true
end

local function prepare_destination_event()
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot prepare destination event because the local faction is unsupported.")
        return false
    end

    local current_node = get_current_node_data()
    if not current_node then
        log("prepare_destination_event aborted because the current node could not be resolved.")
        return false
    end

    local current_cycle = get_current_cycle()

    local enabled_candidates = {}
    for _, node_data in ipairs(NODE_POOL) do
        if node_data.enabled and node_data.node_key ~= current_node.node_key then
            enabled_candidates[#enabled_candidates + 1] = node_data
        end
    end

    if #enabled_candidates < 2 then
        log(
            "prepare_destination_event aborted because fewer than two alternate destination nodes are available. current_node_key=["
                .. tostring(current_node.node_key)
                .. "], enabled_candidate_count=["
                .. tostring(#enabled_candidates)
                .. "]."
        )
        return false
    end

    local seed = new_event_seed()
    local generation_attempts = 1
    local first_index = cm:random_number(#enabled_candidates, 1)
    local second_index = cm:random_number(#enabled_candidates, 1)
    while second_index == first_index and generation_attempts < 20 do
        generation_attempts = generation_attempts + 1
        second_index = cm:random_number(#enabled_candidates, 1)
    end

    if second_index == first_index then
        second_index = first_index == #enabled_candidates and 1 or (first_index + 1)
    end

    local candidate_a = enabled_candidates[first_index]
    local candidate_b = enabled_candidates[second_index]
    local payload = {
        current_node_key = current_node.node_key,
        current_node_faction_key = current_node.faction_key,
        destination_candidate_node_0 = candidate_a.node_key,
        destination_candidate_faction_0 = candidate_a.faction_key,
        destination_candidate_node_1 = candidate_b.node_key,
        destination_candidate_faction_1 = candidate_b.faction_key,
        destination_generation_seed = seed,
        destination_generation_attempts = generation_attempts,
        leave_current_enabled = "true",
        stay_choice = 2,
        pause_choice = 3
    }

    -- Persist the drawn candidates themselves so pause/resume and save/load never reroll this choice set.
    set_saved_value(
        SAVE_KEYS.destination_candidate_node_keys,
        table.concat({ candidate_a.node_key, candidate_b.node_key }, ",")
    )
    set_saved_value(
        SAVE_KEYS.destination_candidate_faction_keys,
        table.concat({ candidate_a.faction_key, candidate_b.faction_key }, ",")
    )
    set_saved_value(SAVE_KEYS.destination_leave_current_enabled, "true")
    set_saved_value(SAVE_KEYS.destination_selection_generated, "true")
    set_saved_value(SAVE_KEYS.destination_generation_seed, seed)
    set_saved_value(SAVE_KEYS.destination_generation_attempts, generation_attempts)

    set_current_event_context(EVENT_TYPE.DESTINATION, DILEMMA_DESTINATION_KEY, seed, payload)
    set_current_state(STATE.DESTINATION_PENDING)
    try_relocate_player_force_for_variety("destination_event_prepared")
    log(
        "Prepared destination event. current_node_key=["
            .. tostring(current_node.node_key)
            .. "], current_node_faction_key=["
            .. tostring(current_node.faction_key)
            .. "], current_cycle=["
            .. tostring(current_cycle)
            .. "], candidate_a=["
            .. tostring(candidate_a.node_key)
            .. "/"
            .. tostring(candidate_a.faction_key)
            .. "], candidate_b=["
            .. tostring(candidate_b.node_key)
            .. "/"
            .. tostring(candidate_b.faction_key)
            .. "], generation_seed=["
            .. tostring(seed)
            .. "], generation_attempts=["
            .. tostring(generation_attempts)
            .. "]."
    )
    return true
end

local function launch_equipment_reward_dilemma(faction)
    local payload = get_current_event_payload()
    if not payload or type(payload) ~= "table" then
        log("launch_equipment_reward_dilemma aborted because the current equipment reward payload could not be decoded.")
        return false
    end

    local dilemma_builder = cm:create_dilemma_builder(DILEMMA_EQUIPMENT_REWARD_KEY)
    local payload_builder = cm:create_payload()
    local choice_keys = { "FIRST", "SECOND", "THIRD", "FOURTH" }
    local valid_choice_count = 0

    -- Rebuild the dilemma from the saved payload so the same item choices survive save/load.
    for choice_index = 0, 3 do
        local ancillary_key = payload["ancillary_" .. tostring(choice_index)]
        local item_category = payload["category_" .. tostring(choice_index)] or "unknown"
        local item_rarity = payload["rarity_" .. tostring(choice_index)] or "unknown"
        local reward_slot = payload["slot_" .. tostring(choice_index)] or "unknown"
        local choice_key = choice_keys[choice_index + 1]

        if ancillary_key and ancillary_key ~= "" then
            payload_builder:faction_ancillary_gain(faction, ancillary_key)
            dilemma_builder:add_choice_payload(choice_key, payload_builder)
            payload_builder:clear()
            valid_choice_count = valid_choice_count + 1

            log(
                "launch_equipment_reward_dilemma added runtime payload for choice_key=["
                    .. tostring(choice_key)
                    .. "], ancillary_key=["
                    .. tostring(ancillary_key)
                    .. "], slot=["
                    .. tostring(reward_slot)
                    .. "], category=["
                    .. tostring(item_category)
                    .. "], rarity=["
                    .. tostring(item_rarity)
                    .. "]."
            )
        else
            log("launch_equipment_reward_dilemma skipped missing ancillary payload for choice_index=[" .. tostring(choice_index) .. "].")
        end
    end

    if valid_choice_count == 0 then
        log("launch_equipment_reward_dilemma aborted because no valid runtime choice payloads were generated.")
        return false
    end

    cm:launch_custom_dilemma_from_builder(dilemma_builder, faction)
    log(
        "Launched custom equipment reward dilemma for faction ["
            .. faction:name()
            .. "] with valid_choice_count=["
            .. tostring(valid_choice_count)
            .. "]."
    )
    return true
end

local function launch_hero_reward_dilemma(faction)
    log("launch_hero_reward_dilemma entered.")
    local payload = get_current_event_payload()
    if not payload or type(payload) ~= "table" then
        log("launch_hero_reward_dilemma aborted: payload could not be decoded.")
        return false
    end
    log("launch_hero_reward_dilemma: payload OK.")

    local player_force = get_saved_player_force()
    if not player_force then
        log("launch_hero_reward_dilemma aborted: saved player force is unavailable.")
        return false
    end
    log("launch_hero_reward_dilemma: player_force OK.")

    local ok_build, build_err = pcall(function()
        local dilemma_builder = cm:create_dilemma_builder(DILEMMA_HERO_REWARD_KEY)
        if not dilemma_builder then
            log("launch_hero_reward_dilemma aborted: create_dilemma_builder returned nil for key=[" .. tostring(DILEMMA_HERO_REWARD_KEY) .. "].")
            return
        end
        log("launch_hero_reward_dilemma: dilemma_builder created.")

        local payload_builder = cm:create_payload()
        local choice_keys = { "FIRST", "SECOND", "THIRD" }

        for choice_index = 0, 2 do
            local agent_subtype = payload["hero_" .. tostring(choice_index) .. "_agent_subtype"]
            local choice_key = choice_keys[choice_index + 1]
            if not agent_subtype or agent_subtype == "" then
                log("launch_hero_reward_dilemma aborted: hero choice missing. choice_index=[" .. tostring(choice_index) .. "].")
                return
            end
            local component_key = build_hero_reward_payload_component_key(agent_subtype)
            log("launch_hero_reward_dilemma: adding choice. index=[" .. tostring(choice_index) .. "], subtype=[" .. tostring(agent_subtype) .. "], component_key=[" .. tostring(component_key) .. "].")
            payload_builder:text_display(component_key)
            dilemma_builder:add_choice_payload(choice_key, payload_builder)
            payload_builder:clear()
        end

        payload_builder:text_display("dummy_do_nothing")
        dilemma_builder:add_choice_payload("FOURTH", payload_builder)
        payload_builder:clear()

        payload_builder:text_display("dummy_do_nothing")
        dilemma_builder:add_choice_payload("FIFTH", payload_builder)
        payload_builder:clear()

        dilemma_builder:add_target("default", player_force)
        cm:launch_custom_dilemma_from_builder(dilemma_builder, faction)
        log(
            "launch_hero_reward_dilemma: launched. faction=["
                .. tostring(faction:name())
                .. "], heroes=["
                .. tostring(payload.hero_0_agent_subtype)
                .. ","
                .. tostring(payload.hero_1_agent_subtype)
                .. ","
                .. tostring(payload.hero_2_agent_subtype)
                .. "]."
        )
    end)
    if not ok_build then
        log("launch_hero_reward_dilemma: pcall caught error. error=[" .. tostring(build_err) .. "].")
        return false
    end
    return true
end

local function launch_hero_reward_full_dilemma(faction)
    local player_force = get_saved_player_force()
    if not player_force then
        log("launch_hero_reward_full_dilemma aborted because the saved player force is unavailable.")
        return false
    end

    local dilemma_builder = cm:create_dilemma_builder(DILEMMA_HERO_REWARD_FULL_KEY)
    local payload_builder = cm:create_payload()

    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("FIRST", payload_builder)
    payload_builder:clear()
    dilemma_builder:add_target("default", player_force)

    cm:launch_custom_dilemma_from_builder(dilemma_builder, faction)
    log("Launched hero reward full-stack warning dilemma for faction [" .. tostring(faction:name()) .. "].")
    return true
end

local function launch_reward_dilemma(faction)
    local payload = get_current_event_payload()
    if not payload or type(payload) ~= "table" then
        log("launch_reward_dilemma aborted because the current reward payload could not be decoded.")
        return false
    end

    local player_force = get_saved_player_force()
    if not player_force then
        log("launch_reward_dilemma aborted because the saved player force is unavailable.")
        return false
    end

    local dilemma_builder = cm:create_dilemma_builder(DILEMMA_REWARD_KEY)
    local payload_builder = cm:create_payload()

    for choice_index = 0, 2 do
        local reward_unit_key = payload["unit_" .. tostring(choice_index)]
        local reward_unit_count = tonumber(payload["unit_" .. tostring(choice_index) .. "_count"]) or 1
        local choice_key = ({ "FIRST", "SECOND", "THIRD" })[choice_index + 1]
        if reward_unit_key and reward_unit_key ~= "" then
            -- Mirror the original caravan reward flow: the dilemma payload itself adds the
            -- chosen unit(s) to the active force, which lets the campaign UI render it as a
            -- real unit reward instead of a generic text-only choice.
            -- reward_unit_count is 2 when the unit value falls in the double-reward band.
            payload_builder:add_unit(player_force, reward_unit_key, reward_unit_count, 0, true)
            dilemma_builder:add_choice_payload(choice_key, payload_builder)
            payload_builder:clear()
        else
            log("launch_reward_dilemma aborted because a saved reward unit choice is missing. choice_index=[" .. tostring(choice_index) .. "].")
            return false
        end
    end

    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("FOURTH", payload_builder)
    payload_builder:clear()

    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("FIFTH", payload_builder)
    payload_builder:clear()
    dilemma_builder:add_target("default", player_force)

    cm:launch_custom_dilemma_from_builder(dilemma_builder, faction)
    log("Launched custom reward dilemma for faction [" .. faction:name() .. "].")
    return true
end

local function launch_battle_dilemma(faction)
    local payload = get_current_event_payload()
    if not payload or type(payload) ~= "table" then
        log("launch_battle_dilemma aborted because the current battle payload could not be decoded.")
        return false
    end

    if not payload.enemy_unit_list or payload.enemy_unit_list == "" then
        log("launch_battle_dilemma aborted because the current battle payload has no enemy_unit_list.")
        return false
    end

    log_battle_balance_check(payload)

    local dilemma_builder = cm:create_dilemma_builder(DILEMMA_BATTLE_KEY)
    local payload_builder = cm:create_payload()

    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("FIRST", payload_builder)
    payload_builder:clear()

    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("SECOND", payload_builder)
    payload_builder:clear()

    cm:launch_custom_dilemma_from_builder(dilemma_builder, faction)
    log("Launched custom battle dilemma for faction [" .. faction:name() .. "].")
    return true
end

local function launch_destination_dilemma(faction)
    local payload = get_current_event_payload()
    if not payload or type(payload) ~= "table" then
        log("launch_destination_dilemma aborted because the current destination payload could not be decoded.")
        return false
    end

    local candidate_node_a = find_node_data_by_key(payload.destination_candidate_node_0)
    local candidate_node_b = find_node_data_by_key(payload.destination_candidate_node_1)
    local current_node = find_node_data_by_key(payload.current_node_key) or get_current_node_data()
    if not candidate_node_a or not candidate_node_b or not current_node then
        log(
            "launch_destination_dilemma aborted because one or more saved destination nodes are invalid. payload=["
                .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
                .. "]."
        )
        return false
    end

    local dilemma_builder = cm:create_dilemma_builder(DILEMMA_DESTINATION_KEY)
    local payload_builder = cm:create_payload()

    payload_builder:text_display(build_destination_payload_component_key(candidate_node_a.node_key))
    dilemma_builder:add_choice_payload("FIRST", payload_builder)
    payload_builder:clear()

    payload_builder:text_display(build_destination_payload_component_key(candidate_node_b.node_key))
    dilemma_builder:add_choice_payload("SECOND", payload_builder)
    payload_builder:clear()

    payload_builder:text_display(build_destination_current_payload_component_key(current_node.node_key))
    dilemma_builder:add_choice_payload("THIRD", payload_builder)
    payload_builder:clear()

    payload_builder:text_display("adamrogue_destination_payload_delay")
    dilemma_builder:add_choice_payload("FOURTH", payload_builder)
    payload_builder:clear()

    cm:launch_custom_dilemma_from_builder(dilemma_builder, faction)
    log(
        "Launched custom destination dilemma for faction ["
            .. faction:name()
            .. "] with current_node_key=["
            .. tostring(current_node.node_key)
            .. "], candidate_a=["
            .. tostring(candidate_node_a.node_key)
            .. "], candidate_b=["
            .. tostring(candidate_node_b.node_key)
            .. "]."
    )
    return true
end

launch_army_preview_dilemma = function(faction)
    local player_force = get_saved_player_force()
    if not player_force then
        log("launch_army_preview_dilemma aborted: player preview force is unavailable.")
        return false
    end

    local dilemma_builder = cm:create_dilemma_builder(DILEMMA_ARMY_PREVIEW_KEY)
    local payload_builder = cm:create_payload()

    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("FIRST", payload_builder)
    payload_builder:clear()

    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("SECOND", payload_builder)
    payload_builder:clear()

    payload_builder:text_display("dummy_do_nothing")
    dilemma_builder:add_choice_payload("THIRD", payload_builder)
    payload_builder:clear()

    dilemma_builder:add_target("default", player_force)
    cm:launch_custom_dilemma_from_builder(dilemma_builder, faction)
    log("launch_army_preview_dilemma: launched for faction [" .. faction:name() .. "].")
    return true
end

local function pause_current_event()
    set_paused_state(get_current_state())
end

local function open_current_event(reason)
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Formal entry was triggered but the local faction is not supported.")
        return
    end

    ensure_current_node_initialized("open_current_event")
    ensure_initial_peace_on_first_entry(faction, reason)

    local state = get_current_state()
    log("Entry triggered by player. reason=[" .. tostring(reason) .. "], current_state=[" .. tostring(state) .. "]")

    if state == STATE.PAUSED then
        local paused_from_state = get_paused_from_state()
        log("Current state is [PAUSED], paused_from_state=[" .. tostring(paused_from_state) .. "].")
        set_current_state(paused_from_state)
        state = paused_from_state
    elseif state == STATE.INIT then
        local run_started = get_saved_value(SAVE_KEYS.run_started, false)
        if not run_started then
            -- Run 未确认：检查是否已有预览部队
            local preview_general = get_saved_player_general()
            if preview_general then
                -- 预览部队已存在（玩家选了"稍后"），直接弹出预览困境
                set_current_state(STATE.ARMY_PREVIEW_PENDING)
                state = STATE.ARMY_PREVIEW_PENDING
            else
                -- 首次或重新随机后：异步生成部队，callback 内自动弹出预览困境
                spawn_new_preview_army(faction)
                return
            end
        else
            -- Run 已确认：进入常规奖励流程
            if adamrogue_is_hero_reward_cycle(get_current_cycle()) and adamrogue_prepare_player_hero_reward_event() then
                state = STATE.HERO_REWARD_PENDING
            else
                if not prepare_unit_reward_event() then
                    return
                end
                state = STATE.UNIT_REWARD_PENDING
            end
        end
    end

    local event_type = get_current_event_type()
    local event_key = get_current_event_key()
    local event_seed = get_current_event_seed()

    log(
        "Opening event from state ["
            .. tostring(state)
            .. "] with type=["
            .. tostring(event_type)
            .. "], key=["
            .. tostring(event_key)
            .. "], seed=["
            .. tostring(event_seed)
            .. "], payload=["
            .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
            .. "]"
    )

    if state == STATE.ARMY_PREVIEW_PENDING then
        launch_army_preview_dilemma(faction)
    elseif state == STATE.HERO_REWARD_PENDING then
        if not launch_hero_reward_dilemma(faction) then
            return
        end
    elseif state == STATE.HERO_REWARD_FULL_PENDING then
        if not launch_hero_reward_full_dilemma(faction) then
            return
        end
    elseif state == STATE.UNIT_REWARD_PENDING then
        if not launch_reward_dilemma(faction) then
            return
        end
    elseif state == STATE.BATTLE_PENDING then
        if not launch_battle_dilemma(faction) then
            return
        end
    elseif state == STATE.EQUIPMENT_REWARD_PENDING then
        if not launch_equipment_reward_dilemma(faction) then
            return
        end
    elseif state == STATE.DESTINATION_PENDING then
        if not launch_destination_dilemma(faction) then
            return
        end
    elseif state == STATE.GAME_OVER then
        log("Run is in GAME_OVER. Phase A leaves this as a placeholder and does not open a summary window yet.")
    else
        log("Formal entry found an unsupported state [" .. tostring(state) .. "].")
    end
end

local function record_reward_unit_choice(choice)
    local payload = get_current_event_payload()
    local reward_unit_key = payload and payload["unit_" .. tostring(choice)] or nil
    if not reward_unit_key then
        log("Reward dilemma choice is not a reward unit: " .. tostring(choice))
        return false
    end

    local force = get_saved_player_force()
    if not force then
        log("Cannot record reward unit choice because the player test force is missing.")
        return false
    end

    local unit_count = count_units_in_force(force)
    set_saved_value(SAVE_KEYS.last_reward_unit, reward_unit_key)
    log(
        "Recorded reward unit choice ["
            .. reward_unit_key
            .. "] for reward choice ["
            .. tostring(choice)
            .. "]. The dilemma payload is responsible for adding it to the player force. current_unit_count=["
            .. tostring(unit_count)
            .. "]."
    )
    return true
end

local function finalize_reward_resolution(skip_unit_reward)
    local prepare_ok, prepare_result = pcall(prepare_battle_event)
    if not prepare_ok then
        log("prepare_battle_event raised a Lua error after reward resolution. error=[" .. tostring(prepare_result) .. "].")
        return false
    end

    if not prepare_result then
        return false
    end

    if skip_unit_reward then
        log("Reward resolution skipped unit granting. Battle event is now pending and will be opened immediately.")
    else
        log("Reward resolved. Battle event is now pending and will be opened immediately.")
    end

    cm:callback(function()
        if get_current_state() == STATE.BATTLE_PENDING then
            open_current_event("reward_resolved_auto_open")
        end
    end, 0.1)

    return true
end

local function record_reward_ancillary_choice(choice)
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot record reward ancillary choice because the local faction is unsupported.")
        return false
    end

    local payload = get_current_event_payload()
    if not payload or type(payload) ~= "table" then
        log("Cannot record reward ancillary choice because the current equipment reward payload could not be decoded.")
        return false
    end

    local ancillary_key = payload["ancillary_" .. tostring(choice)]
    local item_category = payload["category_" .. tostring(choice)] or "unknown"
    local item_rarity = payload["rarity_" .. tostring(choice)] or "unknown"
    local reward_slot = payload["slot_" .. tostring(choice)] or "unknown"
    local source_scope = payload["source_scope_" .. tostring(choice)] or "unknown"
    local source_faction_key = payload["source_faction_" .. tostring(choice)] or "unknown"

    if not ancillary_key or ancillary_key == "" then
        log("record_reward_ancillary_choice aborted because choice [" .. tostring(choice) .. "] has no ancillary key in the payload.")
        return false
    end

    -- The custom dilemma payload grants the item. We only audit the selected key here.
    local had_before = faction:ancillary_exists(ancillary_key)
    local refreshed_faction = get_local_player_faction()
    local has_after = refreshed_faction and refreshed_faction:ancillary_exists(ancillary_key) or false

    set_saved_value(SAVE_KEYS.last_reward_ancillary, ancillary_key)
    log(
        "Recorded equipment reward ancillary choice ["
            .. tostring(ancillary_key)
            .. "] from choice=["
            .. tostring(choice)
            .. "], slot=["
            .. tostring(reward_slot)
            .. "], category=["
            .. tostring(item_category)
            .. "], rarity=["
            .. tostring(item_rarity)
            .. "], source_scope=["
            .. tostring(source_scope)
            .. "], source_faction_key=["
            .. tostring(source_faction_key)
            .. "], had_before=["
            .. tostring(had_before)
            .. "], has_after=["
            .. tostring(has_after)
            .. "]."
    )
    return true
end

local function player_force_participated_in_pending_battle()
    local player_force_cqi = get_saved_value(SAVE_KEYS.player_force_cqi, 0)
    if player_force_cqi == 0 then
        return nil
    end

    for i = 1, cm:pending_battle_cache_num_attackers() do
        local _, mf_cqi = cm:pending_battle_cache_get_attacker(i)
        if mf_cqi == player_force_cqi then
            return "attacker"
        end
    end

    for i = 1, cm:pending_battle_cache_num_defenders() do
        local _, mf_cqi = cm:pending_battle_cache_get_defender(i)
        if mf_cqi == player_force_cqi then
            return "defender"
        end
    end

    return nil
end

local function build_caravan_battle_bridge(force_interface, general_interface)
    return {
        caravan_force = function()
            return force_interface
        end,
        caravan_master = function()
            return {
                character = function()
                    return general_interface
                end
            }
        end
    }
end

local function get_enemy_faction_fallback_stage_index(stage_label)
    if type(stage_label) ~= "string" then
        return nil
    end

    return tonumber(string.match(stage_label, "^faction_fallback_(%d+)$"))
end

local function update_payload_enemy_faction_key(enemy_faction_key, reason)
    local payload = get_current_event_payload()
    if not payload or type(payload) ~= "table" then
        log("update_payload_enemy_faction_key aborted because the current payload could not be decoded.")
        return
    end

    payload.enemy_faction_key = enemy_faction_key
    overwrite_current_battle_payload(payload, reason or "enemy_faction_key_updated")
end

local function resolve_enemy_general_option_for_spawn_faction(content_faction_key, enemy_faction_key, preferred_unit_key)
    local options = ENEMY_GENERAL_OPTIONS_BY_CONTENT_FACTION[content_faction_key] or {}
    if #options == 0 then
        log(
            "[ERROR] resolve_enemy_general_option_for_spawn_faction found no configured general options. content_faction_key=["
                .. tostring(content_faction_key)
                .. "], enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], preferred_unit_key=["
                .. tostring(preferred_unit_key)
                .. "]."
        )
        return nil
    end

    local compatible_options = {}
    for _, option in ipairs(options) do
        local allowed_factions = option.allowed_factions or {}
        for _, allowed_faction_key in ipairs(allowed_factions) do
            if allowed_faction_key == enemy_faction_key then
                compatible_options[#compatible_options + 1] = option
                break
            end
        end
    end

    if #compatible_options == 0 then
        log(
            "[ERROR] resolve_enemy_general_option_for_spawn_faction found no subtype compatible with the selected enemy faction. content_faction_key=["
                .. tostring(content_faction_key)
                .. "], enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], preferred_unit_key=["
                .. tostring(preferred_unit_key)
                .. "]."
        )
        return nil
    end

    if preferred_unit_key and preferred_unit_key ~= "" then
        for _, option in ipairs(compatible_options) do
            if option.unit_key == preferred_unit_key then
                log(
                    "resolve_enemy_general_option_for_spawn_faction matched the preferred unit key for the selected enemy faction. content_faction_key=["
                        .. tostring(content_faction_key)
                        .. "], enemy_faction_key=["
                        .. tostring(enemy_faction_key)
                        .. "], agent_subtype=["
                        .. tostring(option.agent_subtype)
                        .. "], unit_key=["
                        .. tostring(option.unit_key)
                        .. "], unit_value=["
                        .. tostring(option.unit_value)
                        .. "]."
                )
                return option
            end
        end
    end

    local fallback_option = compatible_options[1]
    log(
        "resolve_enemy_general_option_for_spawn_faction fell back to the first compatible subtype for the selected enemy faction. content_faction_key=["
            .. tostring(content_faction_key)
            .. "], enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "], preferred_unit_key=["
            .. tostring(preferred_unit_key)
            .. "], fallback_agent_subtype=["
            .. tostring(fallback_option.agent_subtype)
            .. "], fallback_unit_key=["
            .. tostring(fallback_option.unit_key)
            .. "], fallback_unit_value=["
            .. tostring(fallback_option.unit_value)
            .. "]."
    )
    return fallback_option
end

local function get_enemy_general_target_rank_for_cycle(cycle)
    local normalized_cycle = math.max(DEFAULT_CURRENT_CYCLE, math.floor(tonumber(cycle) or DEFAULT_CURRENT_CYCLE))
    return normalized_cycle
end

local function log_character_skill_point_state(character, context_label)
    if not character or character:is_null_interface() then
        return
    end

    local ok, skill_points_or_error = pcall(function()
        return character:skill_points()
    end)
    if ok then
        log(
            "Character skill point state observed. context=["
                .. tostring(context_label)
                .. "], character_cqi=["
                .. tostring(character:command_queue_index())
                .. "], subtype=["
                .. tostring(character:character_subtype_key())
                .. "], skill_points=["
                .. tostring(skill_points_or_error)
                .. "]."
        )
    else
        log(
            "Character skill point state is unavailable on this interface. context=["
                .. tostring(context_label)
                .. "], character_cqi=["
                .. tostring(character:command_queue_index())
                .. "], error=["
                .. tostring(skill_points_or_error)
                .. "]."
        )
    end
end

local function apply_enemy_general_rank_for_current_cycle(character, reason, on_complete)
    if not character or character:is_null_interface() then
        log("apply_enemy_general_rank_for_current_cycle skipped because the character interface is invalid.")
        if on_complete then on_complete("lord_invalid") end
        return
    end

    local current_cycle = get_current_cycle()
    local target_rank = get_enemy_general_target_rank_for_cycle(current_cycle)
    local current_rank = character:rank()
    local character_cqi = character:command_queue_index()
    log(
        "apply_enemy_general_rank_for_current_cycle started. reason=["
            .. tostring(reason)
            .. "], character_cqi=["
            .. tostring(character_cqi)
            .. "], subtype=["
            .. tostring(character:character_subtype_key())
            .. "], current_cycle=["
            .. tostring(current_cycle)
            .. "], current_rank=["
            .. tostring(current_rank)
            .. "], target_rank=["
            .. tostring(target_rank)
            .. "]."
    )

    if target_rank > current_rank then
        -- Keep spawned enemy lords roughly synced with run progress so late-cycle battles
        -- do not field rank-1 enemy commanders with empty progression.
        cm:add_agent_experience(cm:char_lookup_str(character), target_rank, true)
    end

    -- 等一帧让引擎结算 rank 和技能点，再开始加点。
    cm:callback(function()
        local refreshed_character = cm:get_character_by_cqi(character_cqi)
        if not refreshed_character or refreshed_character:is_null_interface() then
            log(
                "apply_enemy_general_rank_for_current_cycle skill allocation skipped: character no longer valid after rank delay. reason=["
                    .. tostring(reason)
                    .. "], character_cqi=["
                    .. tostring(character_cqi)
                    .. "]."
            )
            if on_complete then on_complete("lord_invalid") end
            return
        end

        local skill_allocation_result = adamrogue_enemy_skill_allocator_module.apply_skills_for_character(
            refreshed_character,
            target_rank,
            log,
            reason or "enemy_rank_scaled"
        )

        log(
            "apply_enemy_general_rank_for_current_cycle completed. reason=["
                .. tostring(reason)
                .. "], character_cqi=["
                .. tostring(character_cqi)
                .. "], final_rank=["
                .. tostring(refreshed_character:rank())
                .. "], skill_allocation_reason=["
                .. tostring(skill_allocation_result.reason or "")
                .. "], applied_skill_levels=["
                .. tostring(skill_allocation_result.applied_levels or 0)
                .. "], applied_mount_skill_levels=["
                .. tostring(skill_allocation_result.mount_skills_applied or 0)
                .. "]."
        )
        log_character_skill_point_state(refreshed_character, reason or "enemy_rank_scaled")
        if on_complete then on_complete("lord") end
    end, 0.05)
end

local function apply_player_character_minimum_rank_for_cycle(reason)
    local player_faction = get_local_player_faction()
    if not player_faction or player_faction:is_null_interface() then
        log("apply_player_character_minimum_rank_for_cycle aborted because the local player faction is unavailable.")
        return
    end

    local player_force_cqi = tonumber(get_saved_value(SAVE_KEYS.player_force_cqi, 0)) or 0
    if player_force_cqi <= 0 then
        log("apply_player_character_minimum_rank_for_cycle aborted because the saved player force CQI is invalid.")
        return
    end

    local target_rank = get_current_cycle()
    local adjusted_count = 0
    local inspected_count = 0
    local seen_character_cqis = {}

    log(
        "apply_player_character_minimum_rank_for_cycle started. reason=["
            .. tostring(reason)
            .. "], target_rank=["
            .. tostring(target_rank)
            .. "]."
    )

    local function inspect_character(character, context_label)
        if not character or character:is_null_interface() then
            log(
                "apply_player_character_minimum_rank_for_cycle skipped an invalid character interface. reason=["
                    .. tostring(reason)
                    .. "], context=["
                    .. tostring(context_label)
                    .. "]."
            )
            return
        end

        local character_cqi = character:command_queue_index()
        if seen_character_cqis[character_cqi] then
            return
        end
        seen_character_cqis[character_cqi] = true
        inspected_count = inspected_count + 1

        local current_rank_ok, current_rank_or_error = pcall(function()
            return character:rank()
        end)
        if not current_rank_ok then
            log(
                "apply_player_character_minimum_rank_for_cycle could not query character rank. reason=["
                    .. tostring(reason)
                    .. "], context=["
                    .. tostring(context_label)
                    .. "], character_cqi=["
                    .. tostring(character_cqi)
                    .. "], error=["
                    .. tostring(current_rank_or_error)
                    .. "]."
            )
            return
        end

        local current_rank = tonumber(current_rank_or_error) or 0
        if current_rank < target_rank then
            local add_rank_ok, add_rank_error = pcall(function()
                cm:add_agent_experience(cm:char_lookup_str(character), target_rank, true)
            end)
            if not add_rank_ok then
                log(
                    "apply_player_character_minimum_rank_for_cycle failed while raising character rank. reason=["
                        .. tostring(reason)
                        .. "], context=["
                        .. tostring(context_label)
                        .. "], character_cqi=["
                        .. tostring(character_cqi)
                        .. "], subtype=["
                        .. tostring(character:character_subtype_key())
                        .. "], previous_rank=["
                        .. tostring(current_rank)
                        .. "], target_rank=["
                        .. tostring(target_rank)
                        .. "], error=["
                        .. tostring(add_rank_error)
                        .. "]."
                )
                return
            end

            adjusted_count = adjusted_count + 1
            local refreshed_character = cm:get_character_by_cqi(character_cqi)
            if refreshed_character and not refreshed_character:is_null_interface() then
                character = refreshed_character
            end

            local final_rank_ok, final_rank_or_error = pcall(function()
                return character:rank()
            end)
            log(
                "apply_player_character_minimum_rank_for_cycle raised character rank. reason=["
                    .. tostring(reason)
                    .. "], context=["
                    .. tostring(context_label)
                    .. "], character_cqi=["
                    .. tostring(character_cqi)
                    .. "], subtype=["
                    .. tostring(character:character_subtype_key())
                    .. "], previous_rank=["
                    .. tostring(current_rank)
                    .. "], target_rank=["
                    .. tostring(target_rank)
                    .. "], final_rank=["
                    .. tostring(final_rank_ok and final_rank_or_error or "unavailable")
                    .. "]."
            )
        end
    end

    local saved_general = get_saved_player_general()
    if saved_general and not saved_general:is_null_interface() then
        inspect_character(saved_general, "saved_player_general")
    else
        log(
            "apply_player_character_minimum_rank_for_cycle could not resolve the saved player general by CQI. reason=["
                .. tostring(reason)
                .. "]."
        )
    end

    local character_list_ok, character_list = pcall(function()
        return player_faction:character_list()
    end)
    if character_list_ok and character_list and not character_list:is_null_interface() then
        local iteration_ok, iteration_error = pcall(function()
            for index = 0, character_list:num_items() - 1 do
                local character = character_list:item_at(index)
                if character and not character:is_null_interface() then
                    local belongs_to_player_force_ok, belongs_to_player_force = pcall(function()
                        if not character:has_military_force() then
                            return false
                        end

                        local force = character:military_force()
                        if not force or force:is_null_interface() then
                            return false
                        end

                        return force:command_queue_index() == player_force_cqi
                    end)

                    if belongs_to_player_force_ok and belongs_to_player_force then
                        inspect_character(character, "faction_character_list_" .. tostring(index))
                    elseif not belongs_to_player_force_ok then
                        log(
                            "apply_player_character_minimum_rank_for_cycle could not inspect whether a faction character belongs to the saved player force. reason=["
                                .. tostring(reason)
                                .. "], character_index=["
                                .. tostring(index)
                                .. "], error=["
                                .. tostring(belongs_to_player_force)
                                .. "]."
                        )
                    end
                end
            end
        end)
        if not iteration_ok then
            log(
                "apply_player_character_minimum_rank_for_cycle failed while iterating faction:character_list(). reason=["
                    .. tostring(reason)
                    .. "], error=["
                    .. tostring(iteration_error)
                    .. "]."
            )
        end
    else
        log(
            "apply_player_character_minimum_rank_for_cycle could not enumerate faction:character_list(); only the saved player general was inspected. reason=["
                .. tostring(reason)
                .. "]."
        )
    end

    log(
        "apply_player_character_minimum_rank_for_cycle completed. reason=["
            .. tostring(reason)
            .. "], target_rank=["
            .. tostring(target_rank)
            .. "], inspected_count=["
            .. tostring(inspected_count)
            .. "], adjusted_count=["
            .. tostring(adjusted_count)
            .. "]."
    )
end

local spawn_enemy_force_and_start_battle
local spawn_enemy_force_with_direct_create_force_fallback

local function issue_enemy_force_spawn_with_general(
    enemy_faction_key,
    enemy_unit_list,
    enemy_general_subtype,
    enemy_agent_subtype,
    player_faction_name,
    player_region_name,
    spawn_x,
    spawn_y,
    spawn_reason_label,
    enemy_hero_list_str
)
    log(
        "issue_enemy_force_spawn_with_general started. spawn_reason_label=["
            .. tostring(spawn_reason_label)
            .. "], enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "], enemy_general_subtype=["
            .. tostring(enemy_general_subtype)
            .. "], enemy_agent_subtype=["
            .. tostring(enemy_agent_subtype)
            .. "], player_region_name=["
            .. tostring(player_region_name)
            .. "], spawn_x=["
            .. tostring(spawn_x)
            .. "], spawn_y=["
            .. tostring(spawn_y)
            .. "], enemy_unit_list=["
            .. tostring(enemy_unit_list)
            .. "]."
    )

    cm:create_force_with_general(
        enemy_faction_key,
        enemy_unit_list,
        player_region_name,
        spawn_x,
        spawn_y,
        "general",
        enemy_general_subtype,
        "",
        "",
        "",
        "",
        false,
        function(char_cqi)
            log(
                "issue_enemy_force_spawn_with_general callback fired. spawn_reason_label=["
                    .. tostring(spawn_reason_label)
                    .. "], char_cqi=["
                    .. tostring(char_cqi)
                    .. "]."
            )

            local enemy_general = nil
            local enemy_force = nil
            local enemy_force_cqi = 0
            if char_cqi and char_cqi > 0 then
                enemy_general = cm:get_character_by_cqi(char_cqi)
            end

            if enemy_general and not enemy_general:is_null_interface() and enemy_general:has_military_force() then
                enemy_force = enemy_general:military_force()
                if enemy_force and not enemy_force:is_null_interface() then
                    enemy_force_cqi = enemy_force:command_queue_index()
                end
            else
                log(
                    "issue_enemy_force_spawn_with_general callback could not resolve a valid enemy general or force. spawn_reason_label=["
                        .. tostring(spawn_reason_label)
                        .. "], char_cqi=["
                        .. tostring(char_cqi)
                        .. "]."
                )
            end

            if caravans then
                caravans.enemy_force_cqi = enemy_force_cqi or 0
            end
            set_saved_value(SAVE_KEYS.enemy_force_cqi, enemy_force_cqi or 0)
            set_saved_value(SAVE_KEYS.enemy_leader_cqi, char_cqi or 0)

            cm:disable_event_feed_events(true, "", "", "diplomacy_faction_destroyed")
            cm:disable_event_feed_events(true, "", "", "character_dies_battle")
            cm:disable_event_feed_events(true, "", "", "diplomacy_war_declared")
            cm:force_declare_war(enemy_faction_key, player_faction_name, false, false, false)
            cm:callback(function()
                cm:disable_event_feed_events(false, "", "", "diplomacy_war_declared")
            end, 0.2)

            -- Parse valid hero entries from the serialized list up front so we know the count.
            local hero_entries_valid = {}
            if enemy_force_cqi and enemy_force_cqi > 0
                and enemy_hero_list_str and enemy_hero_list_str ~= "" then
                for _, hero_entry_str in ipairs(split_string(enemy_hero_list_str, "|")) do
                    local parts = split_string(hero_entry_str, ":")
                    local h_agent_type = parts[1] or ""
                    local h_agent_subtype = parts[2] or ""
                    if h_agent_type ~= "" and h_agent_subtype ~= "" then
                        hero_entries_valid[#hero_entries_valid + 1] = {
                            agent_type = h_agent_type,
                            agent_subtype = h_agent_subtype,
                        }
                    end
                end
            end

            -- Counted battle launch: fire force_attack_of_opportunity only after the lord
            -- AND every hero have finished skill setup.  Any failure path also decrements so
            -- the battle is never permanently blocked.
            local pending_setup_count = 1 + #hero_entries_valid
            local enemy_char_cqi_for_attack = char_cqi or 0
            local player_force_cqi_for_attack = tonumber(get_saved_value(SAVE_KEYS.player_force_cqi, 0)) or 0
            local battle_launched = false

            local function fire_battle_attack()
                if battle_launched then
                    return
                end
                battle_launched = true
                if enemy_char_cqi_for_attack <= 0 or player_force_cqi_for_attack <= 0 then
                    log(
                        "fire_battle_attack aborted: CQIs invalid. spawn_reason_label=["
                            .. tostring(spawn_reason_label)
                            .. "], enemy_char_cqi=["
                            .. tostring(enemy_char_cqi_for_attack)
                            .. "], player_force_cqi=["
                            .. tostring(player_force_cqi_for_attack)
                            .. "]."
                    )
                    return
                end
                local enemy_char_ref = cm:get_character_by_cqi(enemy_char_cqi_for_attack)
                if not enemy_char_ref or enemy_char_ref:is_null_interface() or not enemy_char_ref:has_military_force() then
                    log(
                        "fire_battle_attack aborted: enemy character is no longer valid. spawn_reason_label=["
                            .. tostring(spawn_reason_label)
                            .. "], char_cqi=["
                            .. tostring(enemy_char_cqi_for_attack)
                            .. "]."
                    )
                    return
                end
                local player_force_ref = cm:get_military_force_by_cqi(player_force_cqi_for_attack)
                if not player_force_ref or player_force_ref:is_null_interface() then
                    log(
                        "fire_battle_attack aborted: player force is no longer valid. spawn_reason_label=["
                            .. tostring(spawn_reason_label)
                            .. "], player_force_cqi=["
                            .. tostring(player_force_cqi_for_attack)
                            .. "]."
                    )
                    return
                end
                local enemy_mf_cqi = enemy_char_ref:military_force():command_queue_index()
                local player_mf_cqi = player_force_ref:command_queue_index()
                log(
                    "fire_battle_attack issuing force_attack_of_opportunity. spawn_reason_label=["
                        .. tostring(spawn_reason_label)
                        .. "], enemy_mf_cqi=["
                        .. tostring(enemy_mf_cqi)
                        .. "], player_mf_cqi=["
                        .. tostring(player_mf_cqi)
                        .. "]."
                )
                cm:force_attack_of_opportunity(enemy_mf_cqi, player_mf_cqi, false)
            end

            local function on_character_setup_done(context_label)
                pending_setup_count = pending_setup_count - 1
                log(
                    "on_character_setup_done: context=["
                        .. tostring(context_label)
                        .. "], remaining=["
                        .. tostring(pending_setup_count)
                        .. "]."
                )
                if pending_setup_count <= 0 then
                    fire_battle_attack()
                end
            end

            -- Set up lord.
            if enemy_general and not enemy_general:is_null_interface() then
                apply_enemy_general_rank_for_current_cycle(enemy_general, spawn_reason_label, on_character_setup_done)
                -- Replenish action points so the enemy force can attack immediately.
                cm:replenish_action_points(cm:char_lookup_str(enemy_general))
                cm:disable_movement_for_character(cm:char_lookup_str(enemy_general))
            else
                -- Lord is unavailable; decrement immediately so heroes-only spawns still launch.
                on_character_setup_done("lord_invalid")
            end

            -- Set up heroes.
            local current_cycle_for_heroes = get_current_cycle()
            local hero_target_rank = math.max(1, math.floor(tonumber(current_cycle_for_heroes) or 1))
            log(
                "hero_setup_start: hero_count=["
                    .. tostring(#hero_entries_valid)
                    .. "], pending_setup_count=["
                    .. tostring(pending_setup_count)
                    .. "], hero_target_rank=["
                    .. tostring(hero_target_rank)
                    .. "], enemy_force_cqi=["
                    .. tostring(enemy_force_cqi)
                    .. "]."
            )
            for hero_index, hero_entry in ipairs(hero_entries_valid) do
                local h_agent_type = hero_entry.agent_type
                local h_agent_subtype = hero_entry.agent_subtype
                local listener_name = MODULE_KEY
                    .. "_enemy_hero_created_"
                    .. tostring(enemy_force_cqi)
                    .. "_"
                    .. tostring(hero_index)

                log(
                    "hero_setup_dispatch: hero_index=["
                        .. tostring(hero_index)
                        .. "], agent_type=["
                        .. tostring(h_agent_type)
                        .. "], agent_subtype=["
                        .. tostring(h_agent_subtype)
                        .. "]. Scheduling spawn_agent_at_military_force in 0.05s."
                )

                core:remove_listener(listener_name)
                core:add_listener(
                    listener_name,
                    "CharacterCreated",
                    function(ctx)
                        local created_character = ctx:character()
                        local created_subtype = created_character
                            and not created_character:is_null_interface()
                            and created_character:character_subtype_key()
                            or ""
                        local created_faction = created_character
                            and not created_character:is_null_interface()
                            and created_character:faction():name()
                            or ""
                        log(
                            "hero_character_created_listener_seen: listener=["
                                .. tostring(listener_name)
                                .. "], expected_faction=["
                                .. tostring(enemy_faction_key)
                                .. "], created_faction=["
                                .. tostring(created_faction)
                                .. "], expected_subtype=["
                                .. tostring(h_agent_subtype)
                                .. "], created_subtype=["
                                .. tostring(created_subtype)
                                .. "]."
                        )
                        return created_character
                            and not created_character:is_null_interface()
                            and created_faction == enemy_faction_key
                            and created_subtype == h_agent_subtype
                    end,
                    function(ctx)
                        local created_character = ctx:character()
                        local hero_cqi = created_character and created_character:command_queue_index() or 0
                        log(
                            "hero_character_created_listener_matched: listener=["
                                .. tostring(listener_name)
                                .. "], hero_cqi=["
                                .. tostring(hero_cqi)
                                .. "], agent_subtype=["
                                .. tostring(h_agent_subtype)
                                .. "]."
                        )

                        cm:callback(function()
                            local fresh_force = cm:get_military_force_by_cqi(enemy_force_cqi)
                            if not fresh_force or fresh_force:is_null_interface() then
                                log(
                                    "hero_embed_callback: force no longer valid. enemy_force_cqi=["
                                        .. tostring(enemy_force_cqi)
                                        .. "], agent_subtype=["
                                        .. tostring(h_agent_subtype)
                                        .. "]. Decrementing counter."
                                )
                                on_character_setup_done("hero_force_invalid_" .. h_agent_subtype)
                                return
                            end

                            local hero_char = cm:get_character_by_cqi(hero_cqi)
                            if not hero_char or hero_char:is_null_interface() then
                                log(
                                    "hero_embed_callback: character interface invalid. hero_cqi=["
                                        .. tostring(hero_cqi)
                                        .. "], agent_subtype=["
                                        .. tostring(h_agent_subtype)
                                        .. "]. Decrementing counter."
                                )
                                on_character_setup_done("hero_char_invalid_" .. h_agent_subtype)
                                return
                            end

                            log(
                                "hero_embed_callback: calling embed_agent_in_force. hero_cqi=["
                                    .. tostring(hero_cqi)
                                    .. "], force_cqi=["
                                    .. tostring(enemy_force_cqi)
                                    .. "], agent_subtype=["
                                    .. tostring(h_agent_subtype)
                                    .. "]."
                            )
                            cm:embed_agent_in_force(hero_char, fresh_force)

                            cm:callback(function()
                                local refreshed_hero = cm:get_character_by_cqi(hero_cqi)
                                if not refreshed_hero or refreshed_hero:is_null_interface() then
                                    log(
                                        "hero_rank_callback: character no longer valid. hero_cqi=["
                                            .. tostring(hero_cqi)
                                            .. "], agent_subtype=["
                                            .. tostring(h_agent_subtype)
                                            .. "]. Decrementing counter."
                                    )
                                    on_character_setup_done("hero_refresh_invalid_" .. h_agent_subtype)
                                    return
                                end

                                log(
                                    "hero_rank_callback: embedded=["
                                        .. tostring(refreshed_hero:is_embedded_in_military_force())
                                        .. "], current_rank=["
                                        .. tostring(refreshed_hero:rank())
                                        .. "], target_rank=["
                                        .. tostring(hero_target_rank)
                                        .. "], agent_subtype=["
                                        .. tostring(h_agent_subtype)
                                        .. "]."
                                )
                                if refreshed_hero:rank() < hero_target_rank then
                                    cm:add_agent_experience(cm:char_lookup_str(refreshed_hero), hero_target_rank, true)
                                end

                                cm:callback(function()
                                    local hero_for_skills = cm:get_character_by_cqi(hero_cqi)
                                    if not hero_for_skills or hero_for_skills:is_null_interface() then
                                        log(
                                            "hero_skills_callback: character no longer valid. hero_cqi=["
                                                .. tostring(hero_cqi)
                                                .. "], agent_subtype=["
                                                .. tostring(h_agent_subtype)
                                                .. "]. Decrementing counter."
                                        )
                                        on_character_setup_done("hero_skills_invalid_" .. h_agent_subtype)
                                        return
                                    end

                                    log(
                                        "hero_skills_callback: applying skills. hero_cqi=["
                                            .. tostring(hero_cqi)
                                            .. "], agent_subtype=["
                                            .. tostring(h_agent_subtype)
                                            .. "]."
                                    )
                                    adamrogue_enemy_skill_allocator_module.apply_skills_for_character(
                                        hero_for_skills,
                                        hero_target_rank,
                                        log,
                                        "enemy_hero_spawn"
                                    )
                                    log(
                                        "hero_skills_callback: setup complete. agent_subtype=["
                                            .. tostring(h_agent_subtype)
                                            .. "], final_rank=["
                                            .. tostring(hero_for_skills:rank())
                                            .. "]."
                                    )
                                    on_character_setup_done(h_agent_subtype)
                                end, 0.05)
                            end, 0.05)
                        end, 0.05)
                    end,
                    false
                )

                cm:callback(function()
                    local fresh_force = cm:get_military_force_by_cqi(enemy_force_cqi)
                    if not fresh_force or fresh_force:is_null_interface() then
                        log(
                            "hero_spawn_agent_at_military_force: force no longer valid before spawn. enemy_force_cqi=["
                                .. tostring(enemy_force_cqi)
                                .. "], agent_subtype=["
                                .. tostring(h_agent_subtype)
                                .. "]. Decrementing counter."
                        )
                        core:remove_listener(listener_name)
                        on_character_setup_done("hero_force_invalid_" .. h_agent_subtype)
                        return
                    end

                    local enemy_faction = cm:get_faction(enemy_faction_key)
                    if not enemy_faction or enemy_faction:is_null_interface() then
                        log(
                            "hero_spawn_agent_at_military_force: faction invalid before spawn. enemy_faction_key=["
                                .. tostring(enemy_faction_key)
                                .. "], agent_subtype=["
                                .. tostring(h_agent_subtype)
                                .. "]. Decrementing counter."
                        )
                        core:remove_listener(listener_name)
                        on_character_setup_done("hero_faction_invalid_" .. h_agent_subtype)
                        return
                    end

                    log(
                        "hero_spawn_agent_at_military_force: calling API. faction=["
                            .. tostring(enemy_faction_key)
                            .. "], force_cqi=["
                            .. tostring(enemy_force_cqi)
                            .. "], agent_type=["
                            .. tostring(h_agent_type)
                            .. "], agent_subtype=["
                            .. tostring(h_agent_subtype)
                            .. "]."
                    )
                    local spawn_ok, spawn_err = pcall(function()
                        cm:spawn_agent_at_military_force(enemy_faction, fresh_force, h_agent_type, h_agent_subtype)
                    end)

                    if spawn_ok then
                        log(
                            "hero_spawn_agent_at_military_force: API call completed, waiting CharacterCreated. agent_subtype=["
                                .. tostring(h_agent_subtype)
                                .. "]."
                        )
                    else
                        log(
                            "hero_spawn_agent_at_military_force: API call failed. agent_subtype=["
                                .. tostring(h_agent_subtype)
                                .. "], error=["
                                .. tostring(spawn_err)
                                .. "]. Decrementing counter."
                        )
                        core:remove_listener(listener_name)
                        on_character_setup_done("hero_spawn_failed_" .. h_agent_subtype)
                    end
                end, 0.05)
            end

            if enemy_force and not enemy_force:is_null_interface() then
                cm:set_force_has_retreated_this_turn(enemy_force)
            end

            if enemy_agent_subtype and enemy_agent_subtype ~= "" then
                log(
                    "issue_enemy_force_spawn_with_general did not embed the configured enemy agent subtype during this spawn path. enemy_agent_subtype=["
                        .. tostring(enemy_agent_subtype)
                        .. "]."
                )
            end
        end,
        true
    )
end

local function launch_spawned_enemy_force_battle(caravan_bridge, player_region_name, is_ambush, spawn_x, spawn_y, attempt, spawn_attempt)
    local current_attempt = attempt or 1
    local current_spawn_attempt = spawn_attempt or 1
    local current_spawn_attempt_number = tonumber(current_spawn_attempt)
    local current_fallback_stage_index = get_enemy_faction_fallback_stage_index(current_spawn_attempt)
    local is_same_faction_direct_fallback = current_spawn_attempt == "direct_same_faction"
    local enemy_force_cqi = caravans and caravans.enemy_force_cqi or 0
    log(
        "launch_spawned_enemy_force_battle polling. attempt=["
            .. tostring(current_attempt)
            .. "], spawn_attempt=["
            .. tostring(current_spawn_attempt)
            .. "], enemy_force_cqi=["
            .. tostring(enemy_force_cqi)
            .. "], x=["
            .. tostring(spawn_x)
            .. "], y=["
            .. tostring(spawn_y)
            .. "]."
    )

    if enemy_force_cqi and enemy_force_cqi > 0 then
        set_saved_value(SAVE_KEYS.enemy_force_cqi, enemy_force_cqi)
        local enemy_force = cm:get_military_force_by_cqi(enemy_force_cqi)
        if enemy_force and not enemy_force:is_null_interface() then
            local enemy_general = enemy_force:general_character()
            if enemy_general and not enemy_general:is_null_interface() then
                set_saved_value(SAVE_KEYS.enemy_leader_cqi, enemy_general:command_queue_index())
            else
                log("launch_spawned_enemy_force_battle could not resolve the spawned enemy general before battle launch.")
            end
        else
            log("launch_spawned_enemy_force_battle could not resolve the spawned enemy force interface before battle launch.")
        end
        log(
            "Enemy battle force is ready. enemy_force_cqi=["
                .. tostring(enemy_force_cqi)
                .. "], region=["
                .. tostring(player_region_name)
                .. "], attempt=["
                .. tostring(current_attempt)
                .. "], spawn_attempt=["
                .. tostring(current_spawn_attempt)
                .. "]. Battle attack has been scheduled from spawn callback; locking retreat UI and exiting poll."
        )
        -- 战斗攻击已由 issue_enemy_force_spawn_with_general 回调内的 force_declare_war+WAR_ATTACK_DELAY 延迟负责发起。
        -- 此处仅做 UI retreat 锁定，不再通过 caravans:create_caravan_battle 传送玩家部队（该函数
        -- 会将玩家部队传送到敌军生成坐标附近，在 AdamRogue 语境下会导致战斗无法正常触发）。
        local uim = cm:get_campaign_ui_manager()
        if uim then
            uim:override("retreat"):lock()
        end
        return
    end

    if current_attempt >= MAX_BATTLE_SPAWN_POLL_ATTEMPTS then
        log(
            "Enemy battle force was not ready in time. enemy_force_cqi=["
                .. tostring(enemy_force_cqi)
                .. "], region=["
                .. tostring(player_region_name)
                .. "], attempts=["
                .. tostring(current_attempt)
                .. "], spawn_attempt=["
                .. tostring(current_spawn_attempt)
                .. "], current_payload=["
                .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
                .. "]."
        )

        if current_spawn_attempt_number and current_spawn_attempt_number < MAX_BATTLE_SPAWN_RETRIES then
            log(
                "Primary caravan spawn timed out. Switching to the next enemy faction candidate and retrying spawn_caravan_battle_force. next_spawn_attempt=["
                    .. tostring(current_spawn_attempt_number + 1)
                    .. "], max_spawn_retries=["
                    .. tostring(MAX_BATTLE_SPAWN_RETRIES)
                    .. "]."
            )
            spawn_enemy_force_and_start_battle(current_spawn_attempt_number + 1, "enemy_force_not_ready_after_polling")
        elseif is_same_faction_direct_fallback then
            log(
                "Direct create_force fallback using the original faction also timed out. Escalating to alternate faction fallback stage=[2], max_spawn_retries=["
                    .. tostring(MAX_BATTLE_SPAWN_RETRIES)
                    .. "]."
            )
            spawn_enemy_force_with_direct_create_force_fallback(
                caravan_bridge,
                player_region_name,
                is_ambush,
                "faction_fallback_2",
                "direct_same_faction_not_ready_after_polling"
            )
        elseif current_fallback_stage_index and current_fallback_stage_index < MAX_BATTLE_SPAWN_RETRIES then
            log(
                "Faction fallback stage timed out. Advancing to the next candidate stage=["
                    .. tostring(current_fallback_stage_index + 1)
                    .. "], max_spawn_retries=["
                    .. tostring(MAX_BATTLE_SPAWN_RETRIES)
                    .. "]."
            )
            spawn_enemy_force_with_direct_create_force_fallback(
                caravan_bridge,
                player_region_name,
                is_ambush,
                "faction_fallback_" .. tostring(current_fallback_stage_index + 1),
                "fallback_enemy_force_not_ready_after_polling"
            )
        else
            log(
                "Enemy battle spawn retries exhausted after polling timeout. max_spawn_retries=["
                    .. tostring(MAX_BATTLE_SPAWN_RETRIES)
                    .. "]."
            )
            log(
                "Direct create_force fallback also timed out. spawn_attempt_label=["
                    .. tostring(current_spawn_attempt)
                    .. "]."
            )
        end
        return
    end

    cm:callback(function()
        launch_spawned_enemy_force_battle(caravan_bridge, player_region_name, is_ambush, spawn_x, spawn_y, current_attempt + 1, current_spawn_attempt)
    end, 0.2)
end

spawn_enemy_force_with_direct_create_force_fallback = function(
    caravan_bridge,
    player_region_name,
    is_ambush,
    fallback_stage_label,
    fallback_reason,
    preferred_x,
    preferred_y
)
    local player_general = get_saved_player_general()
    local player_faction_name = get_saved_value(SAVE_KEYS.player_faction_key, "")
    local active_payload = get_current_event_payload()
    if not active_payload or type(active_payload) ~= "table" then
        log("spawn_enemy_force_with_direct_create_force_fallback aborted because the current payload could not be decoded.")
        return
    end

    local enemy_unit_list = active_payload.enemy_unit_list or ""
    local enemy_faction_key = active_payload.enemy_faction_key or DEFAULT_ENEMY_FACTION_KEY
    local enemy_general_subtype = active_payload.enemy_general_subtype or ""
    local enemy_general_unit_key = active_payload.enemy_general_unit_key or ""
    local enemy_agent_subtype = active_payload.enemy_agent_subtype or ""
    local enemy_hero_list = active_payload.enemy_hero_list or ""
    local enemy_faction_candidates = active_payload.enemy_faction_candidates or ""
    local battle_content_faction_key = active_payload.battle_content_faction_key or DEFAULT_CONTENT_FACTION_KEY
    local fallback_stage_index = get_enemy_faction_fallback_stage_index(fallback_stage_label) or 2
    local use_same_faction_coordinates = fallback_stage_label == "direct_same_faction"

    log(
        "spawn_enemy_force_with_direct_create_force_fallback started. fallback_stage_label=["
            .. tostring(fallback_stage_label)
            .. "], fallback_reason=["
            .. tostring(fallback_reason)
            .. "], fallback_stage_index=["
            .. tostring(fallback_stage_index)
            .. "], enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "], preferred_x=["
            .. tostring(preferred_x)
            .. "], preferred_y=["
            .. tostring(preferred_y)
            .. "], use_same_faction_coordinates=["
            .. tostring(use_same_faction_coordinates)
            .. "], enemy_faction_candidates=["
            .. tostring(enemy_faction_candidates)
            .. "], battle_content_faction_key=["
            .. tostring(battle_content_faction_key)
            .. "], enemy_unit_list=["
            .. tostring(enemy_unit_list)
            .. "]."
    )

    if not player_general or player_faction_name == "" then
        log("spawn_enemy_force_with_direct_create_force_fallback aborted because the player general or faction is unavailable.")
        return
    end

    if enemy_unit_list == "" then
        log("spawn_enemy_force_with_direct_create_force_fallback aborted because the current payload has no enemy unit list.")
        return
    end

    local fallback_x = -1
    local fallback_y = -1
    local fallback_source = "not_found"
    local selected_enemy_faction_key, selected_index

    if use_same_faction_coordinates and preferred_x and preferred_y and preferred_x >= 0 and preferred_y >= 0 then
        fallback_x = preferred_x
        fallback_y = preferred_y
        fallback_source = "previous_spawn_coordinates"
        selected_index = 1
        log(
            "spawn_enemy_force_with_direct_create_force_fallback will first reuse the caravan spawn coordinates with the current enemy faction. enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], fallback_x=["
                .. tostring(fallback_x)
                .. "], fallback_y=["
                .. tostring(fallback_y)
                .. "]."
        )
    else
        local fallback_ok, selected_faction_or_error, resolved_x, resolved_y, resolved_source, resolved_index = pcall(
            find_enemy_faction_fallback_candidate,
            player_faction_name,
            enemy_faction_key,
            player_general,
            fallback_stage_index,
            enemy_faction_candidates,
            battle_content_faction_key
        )

        if not fallback_ok then
            log(
                "spawn_enemy_force_with_direct_create_force_fallback encountered a Lua error while evaluating alternate faction candidates. error=["
                    .. tostring(selected_faction_or_error)
                    .. "]. It will retry the current payload faction with a broader spawn query."
            )
        else
            selected_enemy_faction_key = selected_faction_or_error
            fallback_x = resolved_x
            fallback_y = resolved_y
            fallback_source = resolved_source
            selected_index = resolved_index
        end

        if selected_enemy_faction_key then
            enemy_faction_key = selected_enemy_faction_key
        else
            log(
                "spawn_enemy_force_with_direct_create_force_fallback could not find an alternate faction candidate. It will retry the current payload faction with a broader spawn query."
            )
            fallback_x, fallback_y, fallback_source = find_alternative_enemy_spawn_position(enemy_faction_key, player_general, -1, -1)
        end
    end

    log(
        "spawn_enemy_force_with_direct_create_force_fallback resolved candidate position. x=["
            .. tostring(fallback_x)
            .. "], y=["
            .. tostring(fallback_y)
            .. "], source=["
            .. tostring(fallback_source)
            .. "], selected_enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "], selected_index=["
            .. tostring(selected_index)
            .. "]."
    )

    if fallback_x < 0 or fallback_y < 0 then
        log("spawn_enemy_force_with_direct_create_force_fallback aborted because no valid fallback position could be found.")
        return
    end

    local resolved_general_option = resolve_enemy_general_option_for_spawn_faction(
        battle_content_faction_key,
        enemy_faction_key,
        enemy_general_unit_key
    )
    if not resolved_general_option then
        log(
            "spawn_enemy_force_with_direct_create_force_fallback aborted because no compatible general subtype could be resolved for the selected enemy faction. enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], battle_content_faction_key=["
                .. tostring(battle_content_faction_key)
                .. "], enemy_general_unit_key=["
                .. tostring(enemy_general_unit_key)
                .. "]."
        )
        return
    end
    enemy_general_subtype = resolved_general_option.agent_subtype or enemy_general_subtype

    -- Keep the payload in sync with the fallback result so resume/retrigger keeps using the same faction.
    update_payload_enemy_faction_key(enemy_faction_key, "fallback_enemy_faction_selected")
    set_saved_value(SAVE_KEYS.enemy_faction_key, enemy_faction_key)
    cleanup_enemy_force_before_spawn("direct_create_force_fallback")
    if caravans then
        caravans.enemy_force_cqi = 0
    end

    issue_enemy_force_spawn_with_general(
        enemy_faction_key,
        enemy_unit_list,
        enemy_general_subtype,
        enemy_agent_subtype,
        player_faction_name,
        player_region_name,
        fallback_x,
        fallback_y,
        "direct_create_force_callback",
        enemy_hero_list
    )

    log(
        "spawn_enemy_force_with_direct_create_force_fallback issued create_force_with_general. player_region_name=["
            .. tostring(player_region_name)
            .. "], fallback_x=["
            .. tostring(fallback_x)
            .. "], fallback_y=["
            .. tostring(fallback_y)
            .. "], fallback_source=["
            .. tostring(fallback_source)
            .. "]."
    )

    launch_spawned_enemy_force_battle(
        caravan_bridge,
        player_region_name,
        is_ambush,
        fallback_x,
        fallback_y,
        1,
        fallback_stage_label
    )
end

spawn_enemy_force_and_start_battle = function(spawn_attempt, retry_reason)
    local current_spawn_attempt = spawn_attempt or 1
    log(
        "spawn_enemy_force_and_start_battle entered. spawn_attempt=["
            .. tostring(current_spawn_attempt)
            .. "], retry_reason=["
            .. tostring(retry_reason)
            .. "]."
    )
    local player_force = get_saved_player_force()
    local player_general = get_saved_player_general()
    local player_faction_name = get_saved_value(SAVE_KEYS.player_faction_key, "")

    if not player_force or not player_general or player_faction_name == "" then
        log("Cannot start the test battle because the player force state is incomplete.")
        return
    end

    local player_region = player_general:region()
    if not player_region or player_region:is_null_interface() then
        log("Player general has no valid region, so the enemy test army could not be spawned.")
        return
    end

    if not caravans or not caravans.create_caravan_battle then
        log("Caravan battle core is not available, so the bridge battle could not be launched.")
        return
    end

    local active_payload
    if current_spawn_attempt > 1 then
        active_payload = regenerate_battle_payload_for_spawn_retry(current_spawn_attempt, retry_reason or "retry_requested")
        if not active_payload then
            log("spawn_enemy_force_and_start_battle aborted because retry payload regeneration failed.")
            return
        end
    else
        active_payload = get_current_event_payload()
    end

    if not active_payload or type(active_payload) ~= "table" then
        log("spawn_enemy_force_and_start_battle aborted because the current payload could not be decoded.")
        return
    end

    local enemy_unit_list = active_payload.enemy_unit_list or ""
    local battle_force_source = active_payload.battle_force_source or "unknown"
    local target_value_budget = active_payload.target_value_budget or ""
    local enemy_faction_key = active_payload.enemy_faction_key or DEFAULT_ENEMY_FACTION_KEY
    local enemy_general_subtype = active_payload.enemy_general_subtype or ""
    local enemy_general_unit_key = active_payload.enemy_general_unit_key or ""
    local enemy_agent_subtype = active_payload.enemy_agent_subtype or ""
    local enemy_hero_list = active_payload.enemy_hero_list or ""
    local battle_content_faction_key = active_payload.battle_content_faction_key or DEFAULT_CONTENT_FACTION_KEY
    local enemy_faction_candidates = active_payload.enemy_faction_candidates or ""
    if not enemy_unit_list or enemy_unit_list == "" then
        log("Battle payload does not contain a generated enemy unit list. raw_payload=[" .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, "")) .. "]")
        return
    end

    set_saved_value(SAVE_KEYS.enemy_faction_key, enemy_faction_key)
    set_saved_value(SAVE_KEYS.enemy_force_cqi, 0)
    set_saved_value(SAVE_KEYS.enemy_leader_cqi, 0)
    set_saved_value(SAVE_KEYS.enemy_agent_cqi, 0)
    set_saved_value(SAVE_KEYS.last_battle_force_source, battle_force_source)
    set_saved_value(SAVE_KEYS.last_battle_budget, tonumber(target_value_budget) or 0)
    cleanup_enemy_force_before_spawn("spawn_attempt_" .. tostring(current_spawn_attempt))
    if caravans then
        caravans.enemy_force_cqi = 0
    end
    if current_spawn_attempt == 1 then
        capture_pre_battle_force_snapshot()
    end

    local caravan_bridge = build_caravan_battle_bridge(player_force, player_general)
    -- The generated unit list is now the canonical battle definition; retries only swap faction/spawn path.
    log_unit_list_details("spawn_attempt_" .. tostring(current_spawn_attempt) .. "_payload", enemy_unit_list)

    log(
        "spawn_enemy_force_and_start_battle resolving spawn position. preferred_enemy_faction_key=["
            .. tostring(enemy_faction_key)
            .. "], battle_content_faction_key=["
            .. tostring(battle_content_faction_key)
            .. "], enemy_faction_candidates=["
            .. tostring(enemy_faction_candidates)
            .. "]."
    )

    local resolved_enemy_faction_key, spawn_x, spawn_y = pick_initial_enemy_faction_key(
        player_faction_name,
        player_general,
        enemy_faction_key,
        enemy_faction_candidates,
        battle_content_faction_key
    )
    if not resolved_enemy_faction_key or spawn_x < 0 or spawn_y < 0 then
        log(
            "spawn_enemy_force_and_start_battle could not resolve a valid spawn position for create_force_with_general. preferred_enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], battle_content_faction_key=["
                .. tostring(battle_content_faction_key)
                .. "], enemy_faction_candidates=["
                .. tostring(enemy_faction_candidates)
                .. "]."
        )
        spawn_enemy_force_with_direct_create_force_fallback(
            caravan_bridge,
            player_region:name(),
            false,
            "faction_fallback_2",
            "primary_spawn_position_not_found"
        )
        return
    end

    if resolved_enemy_faction_key ~= enemy_faction_key then
        update_payload_enemy_faction_key(resolved_enemy_faction_key, "primary_spawn_enemy_faction_selected")
        enemy_faction_key = resolved_enemy_faction_key
    end

    local resolved_general_option = resolve_enemy_general_option_for_spawn_faction(
        battle_content_faction_key,
        enemy_faction_key,
        enemy_general_unit_key
    )
    if not resolved_general_option then
        log(
            "spawn_enemy_force_and_start_battle aborted because no compatible general subtype could be resolved for the selected enemy faction. enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], battle_content_faction_key=["
                .. tostring(battle_content_faction_key)
                .. "], enemy_general_unit_key=["
                .. tostring(enemy_general_unit_key)
                .. "]."
        )
        return
    end
    enemy_general_subtype = resolved_general_option.agent_subtype or enemy_general_subtype

    log(
        "Launching create_force_with_general bridge battle for faction ["
            .. player_faction_name
            .. "] in region ["
            .. player_region:name()
            .. "] against enemy faction ["
            .. enemy_faction_key
            .. "], spawn_attempt=["
            .. tostring(current_spawn_attempt)
            .. "], source=["
            .. tostring(battle_force_source)
            .. "], budget=["
            .. tostring(target_value_budget)
            .. "], enemy_general_subtype=["
            .. tostring(enemy_general_subtype)
            .. "], enemy_general_unit_key=["
            .. tostring(enemy_general_unit_key)
            .. "], enemy_agent_subtype=["
            .. tostring(enemy_agent_subtype)
            .. "], spawn_x=["
            .. tostring(spawn_x)
            .. "], spawn_y=["
            .. tostring(spawn_y)
            .. "], enemy_unit_list=["
            .. tostring(enemy_unit_list)
            .. "]"
    )

    issue_enemy_force_spawn_with_general(
        enemy_faction_key,
        enemy_unit_list,
        enemy_general_subtype,
        enemy_agent_subtype,
        player_faction_name,
        player_region:name(),
        spawn_x,
        spawn_y,
        "caravan_spawn_ready",
        enemy_hero_list
    )

    log(
        "Enemy battle force spawn requested via create_force_with_general. cached_enemy_force_cqi=["
            .. tostring(caravans.enemy_force_cqi)
            .. "], spawn_attempt=["
            .. tostring(current_spawn_attempt)
            .. "], x=["
            .. tostring(spawn_x)
            .. "], y=["
            .. tostring(spawn_y)
            .. "]."
    )

    launch_spawned_enemy_force_battle(caravan_bridge, player_region:name(), false, spawn_x, spawn_y, 1, current_spawn_attempt)
end

local function handle_post_battle_state_transition(player_won)
    log("handle_post_battle_state_transition started. player_won=[" .. tostring(player_won) .. "]")
    local completed_battle_count = get_completed_battle_count()
    local victory_count = get_saved_value(SAVE_KEYS.victory_count, 0)
    local defeat_count = get_saved_value(SAVE_KEYS.defeat_count, 0)
    local consecutive_defeat_count = get_consecutive_defeat_count()
    local result = player_won and "victory" or "defeat"

    set_saved_value(SAVE_KEYS.last_battle_result, result)
    set_saved_value(SAVE_KEYS.completed_battle_count, completed_battle_count + 1)

    if player_won then
        victory_count = victory_count + 1
        consecutive_defeat_count = 0
        set_saved_value(SAVE_KEYS.victory_count, victory_count)
        set_saved_value(SAVE_KEYS.consecutive_defeat_count, consecutive_defeat_count)
    else
        defeat_count = defeat_count + 1
        consecutive_defeat_count = consecutive_defeat_count + 1
        set_saved_value(SAVE_KEYS.defeat_count, defeat_count)
        set_saved_value(SAVE_KEYS.consecutive_defeat_count, consecutive_defeat_count)
    end

    log(
        "Battle resolved as ["
            .. result
            .. "]. completed="
            .. tostring(completed_battle_count + 1)
            .. ", victory="
            .. tostring(victory_count)
            .. ", defeat="
            .. tostring(defeat_count)
            .. ", consecutive_defeat="
            .. tostring(consecutive_defeat_count)
            .. "."
    )

    restore_player_force_after_battle()

    if player_won then
        set_saved_value(SAVE_KEYS.paused_from_state, "")
        if prepare_equipment_reward_event() then
            log("Battle victory advanced to EQUIPMENT_REWARD_PENDING. The equipment reward event will be opened immediately so the run can continue toward destination selection.")
            cm:callback(function()
                if get_current_state() == STATE.EQUIPMENT_REWARD_PENDING then
                    open_current_event("battle_victory_equipment_reward_auto_open")
                end
            end, 0.1)
            return
        end

        log("Battle victory could not prepare the equipment reward event and will fall back to INIT.")
    end

    if not player_won and consecutive_defeat_count >= MAX_CONSECUTIVE_DEFEATS then
        set_current_state(STATE.GAME_OVER)
        clear_current_event_context()
        clear_destination_selection_state("game_over")
        set_saved_value(SAVE_KEYS.paused_from_state, "")
        log("Entering GAME_OVER because consecutive defeats reached [" .. tostring(consecutive_defeat_count) .. "].")
        return
    end

    set_saved_value(SAVE_KEYS.paused_from_state, "")
    if prepare_destination_event() then
        log("Battle defeat advanced to DESTINATION_PENDING. The next node choice will be opened immediately.")
        cm:callback(function()
            if get_current_state() == STATE.DESTINATION_PENDING then
                open_current_event("battle_defeat_destination_auto_open")
            end
        end, 0.1)
        return
    end

    set_current_state(STATE.INIT)
    clear_current_event_context()
    clear_destination_selection_state("battle_flow_reset_to_init")
    log("Battle defeat could not prepare a destination event and fell back to INIT. The current node remains unchanged for the next loop.")
end

function adamrogue_get_player_hero_reward_entry_from_payload(payload, choice)
    if not payload or type(payload) ~= "table" then
        return nil
    end
    if choice < 0 or choice > 2 then
        return nil
    end

    local prefix = "hero_" .. tostring(choice)
    local agent_type = payload[prefix .. "_agent_type"] or ""
    local agent_subtype = payload[prefix .. "_agent_subtype"] or ""
    if agent_type == "" or agent_subtype == "" then
        return nil
    end

    return {
        agent_type = agent_type,
        agent_subtype = agent_subtype,
        unit_key = payload[prefix .. "_unit_key"] or "",
        unit_value = tonumber(payload[prefix .. "_unit_value"]) or 0,
    }
end

function adamrogue_show_hero_reward_full_warning()
    set_current_state(STATE.HERO_REWARD_FULL_PENDING)
    cm:callback(function()
        if get_current_state() == STATE.HERO_REWARD_FULL_PENDING then
            open_current_event("hero_reward_full_warning")
        end
    end, 0.1)
end

function adamrogue_grant_player_hero_reward(hero_entry, on_complete)
    local faction = get_local_player_faction()
    local force = get_saved_player_force()
    if not faction or faction:is_null_interface() or not force or force:is_null_interface() then
        log("grant_player_hero_reward aborted because faction or force is invalid.")
        if on_complete then on_complete(false) end
        return
    end

    if force:unit_list():num_items() >= 20 then
        log(
            "grant_player_hero_reward detected full player force. unit_count=["
                .. tostring(force:unit_list():num_items())
                .. "], agent_subtype=["
                .. tostring(hero_entry and hero_entry.agent_subtype or "")
                .. "]."
        )
        adamrogue_show_hero_reward_full_warning()
        return
    end

    local agent_type = hero_entry.agent_type
    local agent_subtype = hero_entry.agent_subtype
    local target_rank = math.max(1, math.floor(tonumber(get_current_cycle()) or 1))
    local force_cqi = force:command_queue_index()
    local listener_name = MODULE_KEY
        .. "_player_hero_reward_created_"
        .. tostring(force_cqi)
        .. "_"
        .. tostring(agent_subtype)

    core:remove_listener(listener_name)
    core:add_listener(
        listener_name,
        "CharacterCreated",
        function(ctx)
            local created_character = ctx:character()
            local created_subtype = created_character
                and not created_character:is_null_interface()
                and created_character:character_subtype_key()
                or ""
            local created_faction = created_character
                and not created_character:is_null_interface()
                and created_character:faction():name()
                or ""
            log(
                "player_hero_reward_character_created_seen: expected_faction=["
                    .. tostring(faction:name())
                    .. "], created_faction=["
                    .. tostring(created_faction)
                    .. "], expected_subtype=["
                    .. tostring(agent_subtype)
                    .. "], created_subtype=["
                    .. tostring(created_subtype)
                    .. "]."
            )
            return created_character
                and not created_character:is_null_interface()
                and created_faction == faction:name()
                and created_subtype == agent_subtype
        end,
        function(ctx)
            local created_character = ctx:character()
            local hero_cqi = created_character and created_character:command_queue_index() or 0
            log(
                "player_hero_reward_character_created_matched. agent_subtype=["
                    .. tostring(agent_subtype)
                    .. "], hero_cqi=["
                    .. tostring(hero_cqi)
                    .. "]."
            )

            cm:callback(function()
                local refreshed_force = cm:get_military_force_by_cqi(force_cqi)
                local hero_char = cm:get_character_by_cqi(hero_cqi)
                if not refreshed_force or refreshed_force:is_null_interface()
                    or not hero_char or hero_char:is_null_interface() then
                    log("player_hero_reward embed aborted because hero or force is invalid.")
                    if on_complete then on_complete(false) end
                    return
                end

                cm:embed_agent_in_force(hero_char, refreshed_force)
                log(
                    "player_hero_reward embedded hero. agent_subtype=["
                        .. tostring(agent_subtype)
                        .. "], embedded=["
                        .. tostring(hero_char:is_embedded_in_military_force())
                        .. "]."
                )
                cm:replenish_action_points(cm:char_lookup_str(hero_char:command_queue_index()))

                cm:callback(function()
                    local hero_for_rank = cm:get_character_by_cqi(hero_cqi)
                    if not hero_for_rank or hero_for_rank:is_null_interface() then
                        log("player_hero_reward rank setup aborted because hero is invalid.")
                        if on_complete then on_complete(false) end
                        return
                    end
                    if hero_for_rank:rank() < target_rank then
                        cm:add_agent_experience(cm:char_lookup_str(hero_for_rank), target_rank, true)
                    end

                    log(
                        "player_hero_reward completed rank setup without auto-skilling. agent_subtype=["
                            .. tostring(agent_subtype)
                            .. "], final_rank=["
                            .. tostring(hero_for_rank:rank())
                            .. "]."
                    )
                    if on_complete then on_complete(true) end
                end, 0.05)
            end, 0.05)
        end,
        false
    )

    log(
        "grant_player_hero_reward calling spawn_agent_at_military_force. faction=["
            .. tostring(faction:name())
            .. "], force_cqi=["
            .. tostring(force_cqi)
            .. "], agent_type=["
            .. tostring(agent_type)
            .. "], agent_subtype=["
            .. tostring(agent_subtype)
            .. "]."
    )
    local spawn_ok, spawn_err = pcall(function()
        cm:spawn_agent_at_military_force(faction, force, agent_type, agent_subtype)
    end)
    if not spawn_ok then
        core:remove_listener(listener_name)
        log("grant_player_hero_reward spawn_agent_at_military_force failed. error=[" .. tostring(spawn_err) .. "].")
        if on_complete then on_complete(false) end
    end
end

function adamrogue_handle_hero_reward_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_HERO_REWARD_KEY then
        return
    end

    local choice = context:choice()
    log(
        "Hero reward dilemma choice received: "
            .. tostring(choice)
            .. ", current_state=["
            .. tostring(get_current_state())
            .. "], payload=["
            .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
            .. "]"
    )

    cm:callback(function()
        if choice == 3 then
            pause_current_event()
            return
        end

        if choice == 4 then
            log("Hero reward fifth choice selected. Switching to normal unit reward event.")
            if prepare_unit_reward_event() then
                cm:callback(function()
                    if get_current_state() == STATE.UNIT_REWARD_PENDING then
                        open_current_event("hero_reward_switched_to_unit_reward")
                    end
                end, 0.1)
            end
            return
        end

        if choice >= 0 and choice <= 2 then
            local payload = get_current_event_payload()
            local hero_entry = adamrogue_get_player_hero_reward_entry_from_payload(payload, choice)
            if not hero_entry then
                log("handle_hero_reward_dilemma_choice aborted because selected hero payload is missing. choice=[" .. tostring(choice) .. "].")
                return
            end

            adamrogue_grant_player_hero_reward(hero_entry, function(success)
                if not success then
                    log("Player hero reward did not complete successfully; continuing to battle event to avoid blocking the run.")
                end
                finalize_reward_resolution(true)
            end)
            return
        end

        log("Hero reward dilemma choice did not match any known action.")
    end, 0.1)
end

function adamrogue_handle_hero_reward_full_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_HERO_REWARD_FULL_KEY then
        return
    end

    local choice = context:choice()
    log("Hero reward full warning choice received: " .. tostring(choice))
    cm:callback(function()
        set_current_state(STATE.HERO_REWARD_PENDING)
        open_current_event("hero_reward_full_return")
    end, 0.1)
end

local function handle_reward_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_REWARD_KEY then
        return
    end

    local choice = context:choice()
    log(
        "Reward dilemma choice received: "
            .. tostring(choice)
            .. ", current_state=["
            .. tostring(get_current_state())
            .. "], payload=["
            .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
            .. "]"
    )

    cm:callback(function()
        log("Processing deferred reward dilemma choice: " .. tostring(choice))

        if choice == 3 then
            pause_current_event()
            return
        end

        if choice == 4 then
            log("Reward dilemma fifth choice selected. Skipping unit reward and continuing directly to the battle event.")
            finalize_reward_resolution(true)
            return
        end

        if choice >= 0 and choice <= 2 then
            if not record_reward_unit_choice(choice) then
                return
            end
            finalize_reward_resolution(false)
        else
            log("Reward dilemma choice did not match any known action.")
        end
    end, 0.1)
end

local function handle_battle_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_BATTLE_KEY then
        return
    end

    local choice = context:choice()
    log(
        "Battle dilemma choice received: "
            .. tostring(choice)
            .. ", current_state=["
            .. tostring(get_current_state())
            .. "], payload=["
            .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
            .. "]"
    )

    cm:callback(function()
        log("Processing deferred battle dilemma choice: " .. tostring(choice))

        if choice == 1 then
            pause_current_event()
            return
        end

        if choice == 0 then
            spawn_enemy_force_and_start_battle()
        else
            log("Battle dilemma choice did not match any known action.")
        end
    end, 0.1)
end

local function handle_equipment_reward_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_EQUIPMENT_REWARD_KEY then
        return
    end

    local choice = context:choice()
    log(
        "Equipment reward dilemma choice received: "
            .. tostring(choice)
            .. ", current_state=["
            .. tostring(get_current_state())
            .. "], payload=["
            .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
            .. "]"
    )

    cm:callback(function()
        log("Processing deferred equipment reward dilemma choice: " .. tostring(choice))

        if choice >= 0 and choice <= 3 then
            if not record_reward_ancillary_choice(choice) then
                return
            end

            if not prepare_destination_event() then
                return
            end

            log("Equipment reward resolved. The destination event is now pending and will be opened immediately.")
            cm:callback(function()
                if get_current_state() == STATE.DESTINATION_PENDING then
                    open_current_event("equipment_reward_resolved_auto_open")
                end
            end, 0.1)
        else
            log("Equipment reward dilemma choice did not match any known action.")
        end
    end, 0.1)
end

local function handle_destination_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_DESTINATION_KEY then
        return
    end

    local choice = context:choice()
    log(
        "Destination dilemma choice received: "
            .. tostring(choice)
            .. ", current_state=["
            .. tostring(get_current_state())
            .. "], payload=["
            .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
            .. "]"
    )

    cm:callback(function()
        log("Processing deferred destination dilemma choice: " .. tostring(choice))

        if choice == 3 then
            pause_current_event()
            return
        end

        local payload = get_current_event_payload()
        if not payload or type(payload) ~= "table" then
            log("handle_destination_dilemma_choice aborted because the current destination payload could not be decoded.")
            return
        end

        local selected_node
        if choice == 0 then
            selected_node = find_node_data_by_key(payload.destination_candidate_node_0)
        elseif choice == 1 then
            selected_node = find_node_data_by_key(payload.destination_candidate_node_1)
        elseif choice == 2 then
            selected_node = find_node_data_by_key(payload.current_node_key)
        else
            log("Destination dilemma choice did not match any known action.")
            return
        end

        if not selected_node then
            log("handle_destination_dilemma_choice aborted because the selected node could not be resolved from the payload.")
            return
        end

        local previous_cycle = get_current_cycle()
        set_current_node(selected_node, "destination_choice_" .. tostring(choice))
        set_current_cycle(previous_cycle + 1)
        log(
            "Destination resolved without applying player character minimum-rank scaling. reason=[destination_choice_"
                .. tostring(choice)
                .. "]."
        )

        local prepared_next_reward = false
        if adamrogue_is_hero_reward_cycle(get_current_cycle()) then
            prepared_next_reward = adamrogue_prepare_player_hero_reward_event()
        end
        if not prepared_next_reward then
            prepared_next_reward = prepare_unit_reward_event()
        end
        if not prepared_next_reward then
            set_current_cycle(previous_cycle)
            return
        end

        clear_destination_selection_state("destination_choice_resolved")

        log(
            "Destination resolved. selected_node_key=["
                .. tostring(selected_node.node_key)
                .. "], selected_node_faction_key=["
                .. tostring(selected_node.faction_key)
                .. "], previous_cycle=["
                .. tostring(previous_cycle)
                .. "], current_cycle=["
                .. tostring(get_current_cycle())
                .. "]. The next reward event is now pending and will be opened immediately."
        )
        cm:callback(function()
            if get_current_state() == STATE.UNIT_REWARD_PENDING
                or get_current_state() == STATE.HERO_REWARD_PENDING then
                open_current_event("destination_resolved_auto_open")
            end
        end, 0.1)
    end, 0.1)
end

local function handle_army_preview_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_ARMY_PREVIEW_KEY then
        return
    end

    local choice = context:choice()
    log(
        "handle_army_preview_dilemma_choice: choice=["
            .. tostring(choice)
            .. "], current_state=["
            .. tostring(get_current_state())
            .. "]."
    )

    cm:callback(function()
        if choice == 0 then
            -- FIRST: 重新随机 - 删除旧部队，重新生成
            local preview_general = get_saved_player_general()
            if preview_general then
                log("handle_army_preview_dilemma_choice: killing old preview army for reroll.")
                cm:kill_character(cm:char_lookup_str(preview_general), true)
            end
            set_saved_value(SAVE_KEYS.player_leader_cqi, 0)
            set_saved_value(SAVE_KEYS.player_force_cqi, 0)
            set_current_state(STATE.INIT)
            cm:callback(function()
                local faction = get_local_player_faction()
                if faction and not faction:is_null_interface() then
                    open_current_event("army_preview_reroll")
                end
            end, 0.5)

        elseif choice == 1 then
            -- SECOND: 稍后再选 - 部队保留，状态回 INIT，等待下次按钮点击
            set_current_state(STATE.INIT)
            log("handle_army_preview_dilemma_choice: player chose Later. Preview army remains on map. State reset to INIT.")

        elseif choice == 2 then
            -- THIRD: 就要这个 - 确认部队，正式开始 run
            local faction = get_local_player_faction()
            if not faction or faction:is_null_interface() then
                log("handle_army_preview_dilemma_choice: cannot confirm - faction unavailable.")
                return
            end
            set_saved_value(SAVE_KEYS.run_started, true)
            set_saved_value(SAVE_KEYS.completed_battle_count, get_saved_value(SAVE_KEYS.completed_battle_count, 0))
            set_saved_value(SAVE_KEYS.victory_count, get_saved_value(SAVE_KEYS.victory_count, 0))
            set_saved_value(SAVE_KEYS.defeat_count, get_saved_value(SAVE_KEYS.defeat_count, 0))
            set_saved_value(SAVE_KEYS.consecutive_defeat_count, get_saved_value(SAVE_KEYS.consecutive_defeat_count, 0))
            set_current_state(STATE.INIT)
            log("handle_army_preview_dilemma_choice: run confirmed. run_started=true. Proceeding to reward event.")
            cm:callback(function()
                open_current_event("army_preview_confirmed")
            end, 0.1)
        else
            log("handle_army_preview_dilemma_choice: unrecognised choice [" .. tostring(choice) .. "].")
        end
    end, 0.1)
end

local function register_listeners()
    core:remove_listener("adamrogue_phase_a_entry_button")
    core:add_listener(
        "adamrogue_phase_a_entry_button",
        "ContextTriggerEvent",
        function(context)
            return type(context.string) == "string" and context.string:starts_with(BUTTON_CONTEXT_PREFIX .. ":")
        end,
        function(context)
            local faction_name = string.sub(context.string, string.len(BUTTON_CONTEXT_PREFIX) + 2)
            local faction = cm:get_faction(faction_name)
            if not faction or faction:is_null_interface() or not faction:is_human() then
                log("Formal entry was triggered for an invalid faction key [" .. tostring(faction_name) .. "].")
                return
            end

            open_current_event("ui_button")
        end,
        true
    )

    core:remove_listener("adamrogue_phase_a_dilemma_choice")
    core:add_listener(
        "adamrogue_phase_a_dilemma_choice",
        "DilemmaChoiceMadeEvent",
        function(context)
            local dilemma_key = context:dilemma()
            return dilemma_key == DILEMMA_REWARD_KEY
                or dilemma_key == DILEMMA_HERO_REWARD_KEY
                or dilemma_key == DILEMMA_HERO_REWARD_FULL_KEY
                or dilemma_key == DILEMMA_BATTLE_KEY
                or dilemma_key == DILEMMA_EQUIPMENT_REWARD_KEY
                or dilemma_key == DILEMMA_DESTINATION_KEY
                or dilemma_key == DILEMMA_ARMY_PREVIEW_KEY
        end,
        function(context)
            if context:dilemma() == DILEMMA_ARMY_PREVIEW_KEY then
                handle_army_preview_dilemma_choice(context)
            elseif context:dilemma() == DILEMMA_HERO_REWARD_KEY then
                adamrogue_handle_hero_reward_dilemma_choice(context)
            elseif context:dilemma() == DILEMMA_HERO_REWARD_FULL_KEY then
                adamrogue_handle_hero_reward_full_dilemma_choice(context)
            elseif context:dilemma() == DILEMMA_REWARD_KEY then
                handle_reward_dilemma_choice(context)
            elseif context:dilemma() == DILEMMA_BATTLE_KEY then
                handle_battle_dilemma_choice(context)
            elseif context:dilemma() == DILEMMA_EQUIPMENT_REWARD_KEY then
                handle_equipment_reward_dilemma_choice(context)
            else
                handle_destination_dilemma_choice(context)
            end
        end,
        true
    )

    if AUTO_RESUME_ON_TURN_START then
        core:remove_listener("adamrogue_phase_a_turn_resume")
        core:add_listener(
            "adamrogue_phase_a_turn_resume",
            "FactionTurnStart",
            function(context)
                local saved_player_faction_key = get_saved_value(SAVE_KEYS.player_faction_key, "")
                return saved_player_faction_key ~= "" and context:faction():name() == saved_player_faction_key and context:faction():is_human()
            end,
            function(context)
                log("FactionTurnStart debug resume for player faction [" .. context:faction():name() .. "] at turn " .. tostring(cm:model():turn_number()))
                open_current_event("turn_start_debug")
            end,
            true
        )
    end

    core:remove_listener("adamrogue_phase_a_battle_completed")
    core:add_listener(
        "adamrogue_phase_a_battle_completed",
        "BattleCompleted",
        true,
        function()
            local uim = cm:get_campaign_ui_manager()
            uim:override("retreat"):unlock()

            local side = player_force_participated_in_pending_battle()
            if not side then
                return
            end

            local attacker_victory = cm:pending_battle_cache_attacker_victory()
            local player_won = (side == "attacker" and attacker_victory) or (side == "defender" and not attacker_victory)
            local result = player_won and "victory" or "defeat"

            log(
                "Tracked battle resolved. Attackers="
                    .. tostring(cm:pending_battle_cache_num_attackers())
                    .. ", Defenders="
                    .. tostring(cm:pending_battle_cache_num_defenders())
                    .. ", Attacker victory="
                    .. tostring(attacker_victory)
            )

            log("Player test force completed a tracked battle as [" .. side .. "] with result [" .. result .. "].")
            handle_post_battle_state_transition(player_won)

            cm:callback(function()
                cleanup_enemy_force()
                cm:disable_event_feed_events(false, "", "", "diplomacy_faction_destroyed")
                cm:disable_event_feed_events(false, "", "", "character_dies_battle")
            end, 0.2)
        end,
        true
    )
end

local function reset_saved_flow_state_if_needed()
    local run_started = get_saved_value(SAVE_KEYS.run_started, false)
    if not run_started then
        set_saved_value(SAVE_KEYS.current_state, STATE.INIT)
        set_saved_value(SAVE_KEYS.paused_from_state, "")
        ensure_balance_state_initialized("reset_saved_flow_state_if_needed_no_run")
        clear_current_event_context()
        return
    end

    local current_state = get_current_state()
    if not is_supported_runtime_state(current_state) then
        log("Normalizing unsupported saved state [" .. tostring(current_state) .. "] back to INIT.")
        set_saved_value(SAVE_KEYS.current_state, STATE.INIT)
        set_saved_value(SAVE_KEYS.paused_from_state, "")
        clear_current_event_context()
    end

    ensure_balance_state_initialized("reset_saved_flow_state_if_needed_existing_run")
end

cm:add_first_tick_callback(function()
    log("First tick initialization started.")
    reset_saved_flow_state_if_needed()
    ensure_balance_state_initialized("first_tick_initialization")
    log(
        "Balance config initialized. current_cycle=["
            .. tostring(get_current_cycle())
            .. "], difficulty_level=["
            .. tostring(get_difficulty_level())
            .. "], initial_player_value=["
            .. tostring(BALANCE_CONFIG.initial_player_value)
            .. "], initial_enemy_value=["
            .. tostring(BALANCE_CONFIG.initial_enemy_value)
            .. "]."
    )
    register_listeners()
    create_formal_entry_button()
    log("First tick initialization finished.")
end)
