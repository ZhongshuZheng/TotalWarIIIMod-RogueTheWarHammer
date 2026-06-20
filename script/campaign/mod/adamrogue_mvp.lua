local MODULE_KEY = "adamrogue_phase_a"
local config_log = true
local LOG_FILE_NAME = "adamrogue_phase_a_log.txt"
local get_current_event_payload

package.path = "script/campaign/mod/adamrogue/?.lua;" .. package.path

local adamrogue_data_cth = require("adamrogue_data_cth")
local adamrogue_data_ancillaries = require("adamrogue_data_ancillaries")
local adamrogue_battle_generator_module = require("adamrogue_battle_generator")
local adamrogue_ancillary_generator_module = require("adamrogue_ancillary_generator")
local adamrogue_force_snapshot_module = require("adamrogue_force_snapshot")

local BUTTON_CONTEXT_PREFIX = "adamrogue_phase_a_entry"
local AUTO_RESUME_ON_TURN_START = false
local MAX_CONSECUTIVE_DEFEATS = 3
local MAX_BATTLE_SPAWN_POLL_ATTEMPTS = 10
-- Keep this aligned with the Cathay enemy faction pool so each candidate can be tried once.
local MAX_BATTLE_SPAWN_RETRIES = 5
local UNIT_VALUE_SOURCE = "main_units_tables.multiplayer_cost"

local CATHAY_SUBCULTURE = "wh3_main_sc_cth_cathay"

local DILEMMA_REWARD_KEY = "adamrogue_mvp_reward_dilemma"
local DILEMMA_BATTLE_KEY = "adamrogue_mvp_battle_dilemma"
local DILEMMA_EQUIPMENT_REWARD_KEY = "adamrogue_mvp_equipment_reward_dilemma"

local PLAYER_GENERAL_SUBTYPE = adamrogue_data_cth.PLAYER_GENERAL_SUBTYPE
local PLAYER_STARTING_UNITS = adamrogue_data_cth.PLAYER_STARTING_UNITS

local ENEMY_GENERAL_SUBTYPE = adamrogue_data_cth.ENEMY_GENERAL_SUBTYPE
local ENEMY_EMBEDDED_AGENT_SUBTYPE = adamrogue_data_cth.ENEMY_EMBEDDED_AGENT_SUBTYPE
local DEFAULT_ENEMY_FACTION_KEY = adamrogue_data_cth.DEFAULT_ENEMY_FACTION_KEY
local ENEMY_FACTION_CANDIDATES = adamrogue_data_cth.ENEMY_FACTION_CANDIDATES
local REWARD_UNITS_BY_CHOICE = adamrogue_data_cth.REWARD_UNITS_BY_CHOICE
local EQUIPMENT_RARITY = adamrogue_data_ancillaries.EQUIPMENT_RARITY
local EQUIPMENT_REWARD_SLOT_ORDER = adamrogue_data_ancillaries.EQUIPMENT_REWARD_SLOT_ORDER
local EQUIPMENT_REWARD_POOL = adamrogue_data_ancillaries.EQUIPMENT_REWARD_POOL

local EVENT_TYPE = {
    UNIT_REWARD = "unit_reward",
    BATTLE = "battle",
    EQUIPMENT_REWARD = "equipment_reward"
}

local BATTLE_TIER = adamrogue_data_cth.BATTLE_TIER

local STATE = {
    INIT = "INIT",
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
    pre_battle_general_rank = "adamrogue_pre_battle_general_rank",
    enemy_faction_key = "adamrogue_enemy_faction_key",
    enemy_force_cqi = "adamrogue_enemy_force_cqi",
    enemy_leader_cqi = "adamrogue_enemy_leader_cqi",
    enemy_agent_cqi = "adamrogue_enemy_agent_cqi"
}

local CATHAY_BATTLE_UNIT_POOL = adamrogue_data_cth.CATHAY_BATTLE_UNIT_POOL

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

local function get_current_state()
    return get_saved_value(SAVE_KEYS.current_state, STATE.INIT)
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
    return faction and not faction:is_null_interface() and not faction:is_dead() and faction:subculture() == CATHAY_SUBCULTURE
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

    local x, y = cm:find_valid_spawn_location_for_character_from_settlement(
        faction:name(),
        region:name(),
        false,
        true,
        5
    )

    if x < 0 or y < 0 then
        x, y = cm:find_valid_spawn_location_for_character_from_character(
            faction:name(),
            cm:char_lookup_str(leader),
            true,
            5
        )
    end

    if x < 0 or y < 0 then
        return nil
    end

    return region:name(), x, y
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

    local x, y = cm:find_valid_spawn_location_for_character_from_character(
        enemy_faction_key,
        cm:char_lookup_str(player_general),
        true,
        12
    )
    local resolved_x, resolved_y, resolved_source = evaluate_candidate(x, y, "from_character_r12")
    if resolved_x then
        return resolved_x, resolved_y, resolved_source
    end

    x, y = cm:find_valid_spawn_location_for_character_from_character(
        enemy_faction_key,
        cm:char_lookup_str(player_general),
        true,
        20
    )
    resolved_x, resolved_y, resolved_source = evaluate_candidate(x, y, "from_character_r20")
    if resolved_x then
        return resolved_x, resolved_y, resolved_source
    end

    x, y = cm:find_valid_spawn_location_for_character_from_position(
        enemy_faction_key,
        player_general:logical_position_x(),
        player_general:logical_position_y(),
        false
    )
    resolved_x, resolved_y, resolved_source = evaluate_candidate(x, y, "from_position_false")
    if resolved_x then
        return resolved_x, resolved_y, resolved_source
    end

    local player_region = player_general:region()
    if player_region and not player_region:is_null_interface() then
        x, y = cm:find_valid_spawn_location_for_character_from_settlement(
            enemy_faction_key,
            player_region:name(),
            false,
            true,
            20
        )
        resolved_x, resolved_y, resolved_source = evaluate_candidate(x, y, "from_settlement_r20")
        if resolved_x then
            return resolved_x, resolved_y, resolved_source
        end
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

    return -1, -1, "not_found"
end

local function get_enemy_faction_candidate_sequence(player_faction_key, preferred_enemy_faction_key)
    local candidate_keys = {}

    if preferred_enemy_faction_key and preferred_enemy_faction_key ~= "" and preferred_enemy_faction_key ~= player_faction_key then
        candidate_keys[#candidate_keys + 1] = preferred_enemy_faction_key
    end

    for _, faction_key in ipairs(ENEMY_FACTION_CANDIDATES) do
        if faction_key ~= player_faction_key and faction_key ~= preferred_enemy_faction_key then
            candidate_keys[#candidate_keys + 1] = faction_key
        end
    end

    return candidate_keys
end

local function find_enemy_faction_fallback_candidate(player_faction_key, current_enemy_faction_key, player_general, fallback_index)
    local candidate_keys = get_enemy_faction_candidate_sequence(player_faction_key, current_enemy_faction_key)
    local target_index = fallback_index or 2

    for index = target_index, #candidate_keys do
        local faction_key = candidate_keys[index]
        local faction = cm:get_faction(faction_key)
        if faction and not faction:is_null_interface() and not faction:is_dead() and not faction:is_human() then
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

local function pick_initial_enemy_faction_key(player_faction_key, player_general)
    local candidate_keys = get_enemy_faction_candidate_sequence(player_faction_key, DEFAULT_ENEMY_FACTION_KEY)

    for _, faction_key in ipairs(candidate_keys) do
        local faction = cm:get_faction(faction_key)
        if faction and not faction:is_null_interface() and not faction:is_dead() and not faction:is_human() then
            local x, y, source = find_alternative_enemy_spawn_position(faction_key, player_general, -1, -1)

            if x >= 0 and y >= 0 then
                log(
                    "pick_initial_enemy_faction_key selected faction candidate. faction_key=["
                        .. tostring(faction_key)
                        .. "], source=["
                        .. tostring(source)
                        .. "]."
                )
                return faction_key, x, y
            end

            log("pick_initial_enemy_faction_key rejected faction candidate because no valid spawn point was found. faction_key=[" .. faction_key .. "].")
        end
    end

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

local adamrogue_battle_generator = adamrogue_battle_generator_module.new({
    log = log,
    cm = cm,
    split_string = split_string,
    unit_pool = CATHAY_BATTLE_UNIT_POOL,
    battle_tier = BATTLE_TIER,
    enemy_general_subtype = ENEMY_GENERAL_SUBTYPE,
    enemy_embedded_agent_subtype = ENEMY_EMBEDDED_AGENT_SUBTYPE,
    default_enemy_faction_key = DEFAULT_ENEMY_FACTION_KEY
})

local get_battle_tier_for_progress = adamrogue_battle_generator.get_battle_tier_for_progress
local get_target_battle_budget = adamrogue_battle_generator.get_target_battle_budget
local build_budget_enemy_force_definition = adamrogue_battle_generator.build_budget_enemy_force_definition
local create_battle_payload_from_definition = adamrogue_battle_generator.create_battle_payload_from_definition
local log_unit_list_details = adamrogue_battle_generator.log_unit_list_details

local adamrogue_ancillary_generator = adamrogue_ancillary_generator_module.new({
    log = log,
    cm = cm,
    pool = EQUIPMENT_REWARD_POOL,
    battle_tier = BATTLE_TIER,
    equipment_rarity = EQUIPMENT_RARITY,
    slot_order = EQUIPMENT_REWARD_SLOT_ORDER
})

local generate_equipment_reward_payload = adamrogue_ancillary_generator.generate_equipment_reward_payload

local adamrogue_force_snapshot = adamrogue_force_snapshot_module.new({
    cm = cm,
    log = log,
    save_keys = SAVE_KEYS,
    player_general_subtype = PLAYER_GENERAL_SUBTYPE,
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

    existing_payload.spawn_retry_index = spawn_attempt - 1
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
        log("Local player faction is not supported yet. Waiting for a Cathay human faction.")
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

    cm:create_force_with_general(
        faction:name(),
        PLAYER_STARTING_UNITS,
        region_key,
        x,
        y,
        "general",
        PLAYER_GENERAL_SUBTYPE,
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
            set_saved_value(SAVE_KEYS.player_leader_cqi, character:command_queue_index())
            set_saved_value(SAVE_KEYS.player_force_cqi, force:command_queue_index())
            set_saved_value(SAVE_KEYS.completed_battle_count, get_saved_value(SAVE_KEYS.completed_battle_count, 0))
            set_saved_value(SAVE_KEYS.victory_count, get_saved_value(SAVE_KEYS.victory_count, 0))
            set_saved_value(SAVE_KEYS.defeat_count, get_saved_value(SAVE_KEYS.defeat_count, 0))
            set_saved_value(SAVE_KEYS.consecutive_defeat_count, get_saved_value(SAVE_KEYS.consecutive_defeat_count, 0))

            clear_current_event_context()
            set_saved_value(SAVE_KEYS.paused_from_state, "")
            set_current_state(STATE.INIT)

            log("Player test force created. General CQI=" .. tostring(character:command_queue_index()) .. ", Force CQI=" .. tostring(force:command_queue_index()) .. ", Units=" .. tostring(count_units_in_force(force)))
        end
    )

    return true
end

local function prepare_unit_reward_event()
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot prepare unit reward event because the local faction is unsupported.")
        return false
    end

    local seed = new_event_seed()
    local payload = {
        unit_0 = REWARD_UNITS_BY_CHOICE[0],
        unit_1 = REWARD_UNITS_BY_CHOICE[1],
        unit_2 = REWARD_UNITS_BY_CHOICE[2],
        pause_choice = 3
    }

    set_current_event_context(EVENT_TYPE.UNIT_REWARD, DILEMMA_REWARD_KEY, seed, payload)
    set_current_state(STATE.UNIT_REWARD_PENDING)
    log("Prepared unit reward event for faction [" .. faction:name() .. "]")
    return true
end

local function prepare_battle_event()
    log("prepare_battle_event started.")
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot prepare battle event because the local faction is unsupported.")
        return false
    end

    local completed_battle_count = get_completed_battle_count()
    local battle_tier = get_battle_tier_for_progress(completed_battle_count)
    local target_value_budget = get_target_battle_budget(completed_battle_count)
    log(
        "prepare_battle_event progress resolved. completed_battle_count=["
            .. tostring(completed_battle_count)
            .. "], battle_tier=["
            .. tostring(battle_tier)
            .. "], target_value_budget=["
            .. tostring(target_value_budget)
            .. "]."
    )
    local battle_definition = build_budget_enemy_force_definition(target_value_budget, battle_tier, true)
    if not battle_definition then
        log("Failed to generate a budget-based Cathay enemy force for the battle event.")
        return false
    end

    local player_general = get_saved_player_general()
    if not player_general then
        log("prepare_battle_event aborted because the saved player general could not be resolved.")
        return false
    end

    local enemy_faction_key = pick_initial_enemy_faction_key(faction:name(), player_general)
    if not enemy_faction_key or enemy_faction_key == "" then
        log("prepare_battle_event aborted because no Cathay enemy faction candidate could find a valid spawn position.")
        return false
    end

    local seed = new_event_seed()
    local payload = create_battle_payload_from_definition(battle_definition, target_value_budget, battle_tier, 0, enemy_faction_key)

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
            .. "]."
    )
    log_unit_list_details("prepare_battle_event_generated_payload", payload.enemy_unit_list)
    log("Prepared battle event for faction [" .. faction:name() .. "] against enemy faction [" .. enemy_faction_key .. "]")
    return true
end

local function prepare_equipment_reward_event()
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot prepare equipment reward event because the local faction is unsupported.")
        return false
    end

    local completed_battle_count = get_completed_battle_count()
    local battle_tier = get_battle_tier_for_progress(completed_battle_count)
    local payload = generate_equipment_reward_payload(completed_battle_count, battle_tier)
    if not payload or type(payload) ~= "table" or tonumber(payload.candidate_count) == 0 then
        log("prepare_equipment_reward_event aborted because no equipment reward candidates were generated.")
        return false
    end

    local seed = new_event_seed()
    set_current_event_context(EVENT_TYPE.EQUIPMENT_REWARD, DILEMMA_EQUIPMENT_REWARD_KEY, seed, payload)
    set_current_state(STATE.EQUIPMENT_REWARD_PENDING)
    log(
        "Prepared equipment reward event for faction ["
            .. faction:name()
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

local function pause_current_event()
    set_paused_state(get_current_state())
end

local function open_current_event(reason)
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Formal entry was triggered but the local faction is not supported.")
        return
    end

    local state = get_current_state()
    log("Entry triggered by player. reason=[" .. tostring(reason) .. "], current_state=[" .. tostring(state) .. "]")

    if state == STATE.PAUSED then
        local paused_from_state = get_paused_from_state()
        log("Current state is [PAUSED], paused_from_state=[" .. tostring(paused_from_state) .. "].")
        set_current_state(paused_from_state)
        state = paused_from_state
    elseif state == STATE.INIT then
        if not prepare_unit_reward_event() then
            return
        end
        state = STATE.UNIT_REWARD_PENDING
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

    if state == STATE.UNIT_REWARD_PENDING then
        cm:trigger_dilemma(faction:name(), DILEMMA_REWARD_KEY)
        log("Triggered reward dilemma for faction [" .. faction:name() .. "]")
    elseif state == STATE.BATTLE_PENDING then
        cm:trigger_dilemma(faction:name(), DILEMMA_BATTLE_KEY)
        log("Triggered battle dilemma for faction [" .. faction:name() .. "]")
    elseif state == STATE.EQUIPMENT_REWARD_PENDING then
        cm:trigger_dilemma(faction:name(), DILEMMA_EQUIPMENT_REWARD_KEY)
        log("Triggered equipment reward dilemma for faction [" .. faction:name() .. "]")
    elseif state == STATE.GAME_OVER then
        log("Run is in GAME_OVER. Phase A leaves this as a placeholder and does not open a summary window yet.")
    else
        log("Formal entry found an unsupported state [" .. tostring(state) .. "].")
    end
end

local function grant_reward_unit(choice)
    local reward_unit_key = REWARD_UNITS_BY_CHOICE[choice]
    if not reward_unit_key then
        log("Reward dilemma choice is not a reward unit: " .. tostring(choice))
        return
    end

    local general = get_saved_player_general()
    local force = get_saved_player_force()
    if not general or not force then
        log("Cannot grant reward unit because the player test force is missing.")
        return
    end

    local before_count = count_units_in_force(force)
    cm:grant_unit_to_character(cm:char_lookup_str(general), reward_unit_key)

    local refreshed_force = get_saved_player_force()
    local after_count = count_units_in_force(refreshed_force)

    if after_count > before_count then
        set_saved_value(SAVE_KEYS.last_reward_unit, reward_unit_key)
        log("Granted reward unit [" .. reward_unit_key .. "] to player force. Unit count " .. tostring(before_count) .. " -> " .. tostring(after_count))
    else
        log("Reward unit grant attempted for [" .. reward_unit_key .. "], but the unit count did not increase. The force may be full.")
    end
end

local function grant_reward_ancillary(choice)
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot grant reward ancillary because the local faction is unsupported.")
        return false
    end

    local payload = get_current_event_payload()
    if not payload or type(payload) ~= "table" then
        log("Cannot grant reward ancillary because the current equipment reward payload could not be decoded.")
        return false
    end

    local ancillary_key = payload["ancillary_" .. tostring(choice)]
    local item_category = payload["category_" .. tostring(choice)] or "unknown"
    local item_rarity = payload["rarity_" .. tostring(choice)] or "unknown"
    local reward_slot = payload["slot_" .. tostring(choice)] or "unknown"

    if not ancillary_key or ancillary_key == "" then
        log("grant_reward_ancillary aborted because choice [" .. tostring(choice) .. "] has no ancillary key in the payload.")
        return false
    end

    local had_before = faction:ancillary_exists(ancillary_key)
    local add_ok, add_error = pcall(function()
        cm:add_ancillary_to_faction(faction, ancillary_key, false)
    end)

    if not add_ok then
        log(
            "grant_reward_ancillary failed while adding ancillary_key=["
                .. tostring(ancillary_key)
                .. "], error=["
                .. tostring(add_error)
                .. "]."
        )
        return false
    end

    local refreshed_faction = get_local_player_faction()
    local has_after = refreshed_faction and refreshed_faction:ancillary_exists(ancillary_key) or false

    set_saved_value(SAVE_KEYS.last_reward_ancillary, ancillary_key)
    log(
        "Granted equipment reward ancillary ["
            .. tostring(ancillary_key)
            .. "] from choice=["
            .. tostring(choice)
            .. "], slot=["
            .. tostring(reward_slot)
            .. "], category=["
            .. tostring(item_category)
            .. "], rarity=["
            .. tostring(item_rarity)
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

local spawn_enemy_force_and_start_battle
local spawn_enemy_force_with_direct_create_force_fallback

local function launch_spawned_enemy_force_battle(caravan_bridge, player_region_name, is_ambush, spawn_x, spawn_y, attempt, spawn_attempt)
    local current_attempt = attempt or 1
    local current_spawn_attempt = spawn_attempt or 1
    local current_spawn_attempt_number = tonumber(current_spawn_attempt)
    local current_fallback_stage_index = get_enemy_faction_fallback_stage_index(current_spawn_attempt)
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
        log(
            "Enemy battle force is ready. enemy_force_cqi=["
                .. tostring(enemy_force_cqi)
                .. "], region=["
                .. tostring(player_region_name)
                .. "], attempt=["
                .. tostring(current_attempt)
                .. "], spawn_attempt=["
                .. tostring(current_spawn_attempt)
                .. "]. Launching caravan battle."
        )
        caravans:create_caravan_battle(caravan_bridge, enemy_force_cqi, spawn_x, spawn_y, is_ambush)
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
                "Primary caravan spawn timed out. Switching to faction fallback stage=["
                    .. tostring(current_spawn_attempt_number + 1)
                    .. "], max_spawn_retries=["
                    .. tostring(MAX_BATTLE_SPAWN_RETRIES)
                    .. "]."
            )
            spawn_enemy_force_with_direct_create_force_fallback(
                caravan_bridge,
                player_region_name,
                is_ambush,
                "faction_fallback_" .. tostring(current_spawn_attempt_number + 1),
                "enemy_force_not_ready_after_polling"
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
    fallback_reason
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
    local fallback_stage_index = get_enemy_faction_fallback_stage_index(fallback_stage_label) or 2

    log(
        "spawn_enemy_force_with_direct_create_force_fallback started. fallback_stage_label=["
            .. tostring(fallback_stage_label)
            .. "], fallback_reason=["
            .. tostring(fallback_reason)
            .. "], fallback_stage_index=["
            .. tostring(fallback_stage_index)
            .. "], enemy_faction_key=["
            .. tostring(enemy_faction_key)
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

    selected_enemy_faction_key, fallback_x, fallback_y, fallback_source, selected_index = find_enemy_faction_fallback_candidate(
        player_faction_name,
        enemy_faction_key,
        player_general,
        fallback_stage_index
    )

    if selected_enemy_faction_key then
        enemy_faction_key = selected_enemy_faction_key
    else
        log(
            "spawn_enemy_force_with_direct_create_force_fallback could not find an alternate faction candidate. It will retry the current payload faction with a broader spawn query."
        )
        fallback_x, fallback_y, fallback_source = find_alternative_enemy_spawn_position(enemy_faction_key, player_general, -1, -1)
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

    -- Keep the payload in sync with the fallback result so resume/retrigger keeps using the same faction.
    update_payload_enemy_faction_key(enemy_faction_key, "fallback_enemy_faction_selected")
    set_saved_value(SAVE_KEYS.enemy_faction_key, enemy_faction_key)
    cleanup_enemy_force_before_spawn("direct_create_force_fallback")
    if caravans then
        caravans.enemy_force_cqi = 0
    end

    cm:create_force(
        enemy_faction_key,
        enemy_unit_list,
        player_region_name,
        fallback_x,
        fallback_y,
        true,
        function(char_cqi, force_cqi)
            log(
                "spawn_enemy_force_with_direct_create_force_fallback callback fired. char_cqi=["
                    .. tostring(char_cqi)
                    .. "], force_cqi=["
                    .. tostring(force_cqi)
                    .. "]."
            )

            if caravans then
                caravans.enemy_force_cqi = force_cqi
            end
            set_saved_value(SAVE_KEYS.enemy_force_cqi, force_cqi or 0)
            set_saved_value(SAVE_KEYS.enemy_leader_cqi, char_cqi or 0)

            cm:disable_event_feed_events(true, "", "", "diplomacy_faction_destroyed")
            cm:disable_event_feed_events(true, "", "", "character_dies_battle")
            cm:disable_event_feed_events(true, "", "", "diplomacy_war_declared")
            -- Direct create_force does not inherit the caravan helper's combat setup, so we force the war state here.
            cm:force_declare_war(enemy_faction_key, player_faction_name, false, false)
            cm:callback(function()
                cm:disable_event_feed_events(false, "", "", "diplomacy_war_declared")
            end, 0.2)

            if char_cqi and char_cqi > 0 then
                cm:disable_movement_for_character(cm:char_lookup_str(char_cqi))
            end

            if force_cqi and force_cqi > 0 then
                local enemy_force = cm:get_military_force_by_cqi(force_cqi)
                if enemy_force then
                    cm:set_force_has_retreated_this_turn(enemy_force)
                end
            end
        end
    )

    log(
        "spawn_enemy_force_with_direct_create_force_fallback issued create_force. player_region_name=["
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

    if not caravans or not caravans.spawn_caravan_battle_force then
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
        "Launching caravan-core bridge battle for faction ["
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
            .. "], enemy_unit_list=["
            .. tostring(enemy_unit_list)
            .. "]"
    )

    local spawned_enemy_force_cqi, spawn_x, spawn_y = caravans:spawn_caravan_battle_force(
        caravan_bridge,
        enemy_unit_list,
        player_region:name(),
        false,
        false,
        enemy_faction_key
    )

    if spawned_enemy_force_cqi and spawned_enemy_force_cqi > 0 then
        set_saved_value(SAVE_KEYS.enemy_force_cqi, spawned_enemy_force_cqi)
    end

    log(
        "Enemy battle force spawn requested. returned_enemy_force_cqi=["
            .. tostring(spawned_enemy_force_cqi)
            .. "], cached_enemy_force_cqi=["
            .. tostring(caravans.enemy_force_cqi)
            .. "], spawn_attempt=["
            .. tostring(current_spawn_attempt)
            .. "], x=["
            .. tostring(spawn_x)
            .. "], y=["
            .. tostring(spawn_y)
            .. "]."
    )

    if (not spawned_enemy_force_cqi or spawned_enemy_force_cqi <= 0) and (not caravans.enemy_force_cqi or caravans.enemy_force_cqi <= 0) then
        log(
            "Enemy battle force spawn returned no valid CQI immediately, but polling will continue because the caravan callback can populate the CQI asynchronously. spawn_attempt=["
                .. tostring(current_spawn_attempt)
                .. "], raw_payload=["
                .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, ""))
                .. "]."
        )
    end

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
            log("Battle flow advanced to EQUIPMENT_REWARD_PENDING. The player must manually trigger the entry button to claim this reward.")
            return
        end

        log("Battle victory could not prepare the equipment reward event and will fall back to INIT.")
    end

    if not player_won and consecutive_defeat_count >= MAX_CONSECUTIVE_DEFEATS then
        set_current_state(STATE.GAME_OVER)
        clear_current_event_context()
        set_saved_value(SAVE_KEYS.paused_from_state, "")
        log("Entering GAME_OVER because consecutive defeats reached [" .. tostring(consecutive_defeat_count) .. "].")
        return
    end

    set_current_state(STATE.INIT)
    clear_current_event_context()
    set_saved_value(SAVE_KEYS.paused_from_state, "")
    log("Battle flow returned to INIT. Stage C entry remains a placeholder in phase B.")
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

        if choice >= 0 and choice <= 2 then
            grant_reward_unit(choice)
            if not prepare_battle_event() then
                return
            end

            log("Reward resolved. Battle event is now pending and will be opened immediately.")
            cm:callback(function()
                if get_current_state() == STATE.BATTLE_PENDING then
                    open_current_event("reward_resolved_auto_open")
                end
            end, 0.1)
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

        if choice >= 0 and choice <= 2 then
            if not grant_reward_ancillary(choice) then
                return
            end

            if not prepare_unit_reward_event() then
                return
            end

            log("Equipment reward resolved. The next unit reward event is now pending and will be opened immediately.")
            cm:callback(function()
                if get_current_state() == STATE.UNIT_REWARD_PENDING then
                    open_current_event("equipment_reward_resolved_auto_open")
                end
            end, 0.1)
        else
            log("Equipment reward dilemma choice did not match any known action.")
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
                or dilemma_key == DILEMMA_BATTLE_KEY
                or dilemma_key == DILEMMA_EQUIPMENT_REWARD_KEY
        end,
        function(context)
            if context:dilemma() == DILEMMA_REWARD_KEY then
                handle_reward_dilemma_choice(context)
            elseif context:dilemma() == DILEMMA_BATTLE_KEY then
                handle_battle_dilemma_choice(context)
            else
                handle_equipment_reward_dilemma_choice(context)
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
end

cm:add_first_tick_callback(function()
    log("First tick initialization started.")
    reset_saved_flow_state_if_needed()
    register_listeners()
    create_formal_entry_button()
    ensure_run_started()
    log("First tick initialization finished.")
end)
