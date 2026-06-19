local MODULE_KEY = "adamrogue_phase_a"
local config_log = true
local LOG_FILE_NAME = "adamrogue_phase_a_log.txt"

local BUTTON_CONTEXT_PREFIX = "adamrogue_phase_a_entry"
local AUTO_RESUME_ON_TURN_START = false

local CATHAY_SUBCULTURE = "wh3_main_sc_cth_cathay"

local DILEMMA_REWARD_KEY = "adamrogue_mvp_reward_dilemma"
local DILEMMA_BATTLE_KEY = "adamrogue_mvp_battle_dilemma"

local PLAYER_GENERAL_SUBTYPE = "wh3_main_cth_lord_magistrate_yang"
local PLAYER_STARTING_UNITS = table.concat({
    "wh3_main_cth_inf_jade_warriors_0",
    "wh3_main_cth_inf_jade_warriors_0",
    "wh3_main_cth_inf_jade_warrior_crossbowmen_0"
}, ",")

local ENEMY_GENERAL_SUBTYPE = "wh3_main_cth_lord_magistrate_yin"
local ENEMY_EMBEDDED_AGENT_TYPE = "engineer"
local ENEMY_EMBEDDED_AGENT_SUBTYPE = "wh3_main_cth_alchemist"
local ENEMY_UNITS = table.concat({
    "wh3_main_cth_inf_jade_warriors_0",
    "wh3_main_cth_inf_jade_warriors_0",
    "wh3_main_cth_inf_jade_warriors_0"
}, ",")

local ENEMY_FACTION_CANDIDATES = {
    "wh3_main_cth_rebel_lords_of_nan_yang",
    "wh3_main_cth_imperial_wardens",
    "wh3_main_cth_burning_wind_nomads",
    "wh3_main_cth_eastern_river_lords"
}

local REWARD_UNITS_BY_CHOICE = {
    [0] = "wh3_main_cth_inf_dragon_guard_0",
    [1] = "wh3_main_cth_inf_dragon_guard_crossbowmen_0",
    [2] = "wh3_main_cth_cav_jade_lancers_0"
}

local EVENT_TYPE = {
    UNIT_REWARD = "unit_reward",
    BATTLE = "battle"
}

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
    last_battle_result = "adamrogue_last_battle_result",
    completed_battle_count = "adamrogue_completed_battle_count",
    victory_count = "adamrogue_victory_count",
    defeat_count = "adamrogue_defeat_count",
    consecutive_defeat_count = "adamrogue_consecutive_defeat_count",
    enemy_faction_key = "adamrogue_enemy_faction_key",
    enemy_force_cqi = "adamrogue_enemy_force_cqi",
    enemy_leader_cqi = "adamrogue_enemy_leader_cqi",
    enemy_agent_cqi = "adamrogue_enemy_agent_cqi"
}

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

local function pick_enemy_faction_key(player_faction_key)
    for _, faction_key in ipairs(ENEMY_FACTION_CANDIDATES) do
        if faction_key ~= player_faction_key then
            local faction = cm:get_faction(faction_key)
            if faction and not faction:is_null_interface() and not faction:is_dead() and not faction:is_human() then
                return faction_key
            end
        end
    end

    return nil
end

local function cleanup_enemy_force()
    local enemy_general = get_saved_enemy_general()
    if enemy_general then
        log("Cleaning up enemy test army [" .. enemy_general:faction():name() .. "]")
        cm:kill_character(cm:char_lookup_str(enemy_general), true)
    end

    local enemy_agent = get_saved_character(SAVE_KEYS.enemy_agent_cqi)
    if enemy_agent and enemy_agent:is_alive() then
        cm:kill_character(cm:char_lookup_str(enemy_agent))
    end

    set_saved_value(SAVE_KEYS.enemy_faction_key, "")
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

    if type(serialized) ~= "string" or serialized == "" then
        return payload
    end

    for _, entry in ipairs(split_string(serialized, "|")) do
        local equals_position = string.find(entry, "=", 1, true)
        if equals_position then
            local key = string.sub(entry, 1, equals_position - 1)
            local value = string.sub(entry, equals_position + 1)
            payload[key] = value
        end
    end

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

local function get_current_event_payload()
    return decode_payload(get_saved_value(SAVE_KEYS.current_event_payload, ""))
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
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Cannot prepare battle event because the local faction is unsupported.")
        return false
    end

    local enemy_faction_key = pick_enemy_faction_key(faction:name())
    if not enemy_faction_key then
        log("Could not find a living non-player Cathay faction for the battle event.")
        return false
    end

    local seed = new_event_seed()
    local payload = {
        battle_template_key = "adamrogue_phase_a_battle_template_fixed_cathay",
        enemy_faction_key = enemy_faction_key,
        attack_choice = 0,
        pause_choice = 1
    }

    set_saved_value(SAVE_KEYS.enemy_faction_key, enemy_faction_key)
    set_current_event_context(EVENT_TYPE.BATTLE, DILEMMA_BATTLE_KEY, seed, payload)
    set_current_state(STATE.BATTLE_PENDING)
    log("Prepared battle event for faction [" .. faction:name() .. "] against enemy faction [" .. enemy_faction_key .. "]")
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

local function create_test_battle(player_faction_name)
    local player_force = get_saved_player_force()
    local enemy_force = get_saved_enemy_force()
    local player_faction = cm:get_faction(player_faction_name)
    local player_general = get_saved_player_general()

    if not player_force or not enemy_force or not player_faction or player_faction:is_null_interface() or not player_general then
        log("Unable to create the test battle because one or more required interfaces were missing.")
        return
    end

    local player_force_cqi = player_force:command_queue_index()
    local enemy_force_cqi = enemy_force:command_queue_index()
    local enemy_general = get_saved_enemy_general()

    if not enemy_general then
        log("Unable to create the test battle because the enemy general interface was missing.")
        return
    end

    local player_x, player_y = cm:find_valid_spawn_location_for_character_from_position(
        player_faction_name,
        enemy_general:logical_position_x(),
        enemy_general:logical_position_y(),
        false
    )

    if player_x < 0 or player_y < 0 then
        log("Unable to find a valid teleport position for the player test force near the enemy army.")
        return
    end

    log("Teleporting player test force near the enemy battle point. Player target position=(" .. tostring(player_x) .. ", " .. tostring(player_y) .. ")")

    cm:teleport_to(cm:char_lookup_str(player_general), player_x, player_y)

    local uim = cm:get_campaign_ui_manager()
    uim:override("retreat"):lock()

    force_attack_once(enemy_force_cqi, player_force_cqi, "caravan_style_enemy_attack")
end

local function spawn_enemy_force_and_start_battle()
    local player_force = get_saved_player_force()
    local player_general = get_saved_player_general()
    local player_faction_name = get_saved_value(SAVE_KEYS.player_faction_key, "")
    local payload = get_current_event_payload()

    if not player_force or not player_general or player_faction_name == "" then
        log("Cannot start the test battle because the player force state is incomplete.")
        return
    end

    local enemy_faction_key = payload.enemy_faction_key or get_saved_value(SAVE_KEYS.enemy_faction_key, "")
    if enemy_faction_key == "" then
        log("Cannot start the test battle because the saved enemy faction key is missing.")
        return
    end

    if get_saved_enemy_force() or get_saved_character(SAVE_KEYS.enemy_agent_cqi) then
        log("A previous enemy test army was still tracked. Cleaning it up before spawning a fresh one.")
        cleanup_enemy_force()
    end

    local player_region = player_general:region()
    if not player_region or player_region:is_null_interface() then
        log("Player general has no valid region, so the enemy test army could not be spawned.")
        return
    end

    local x, y = cm:find_valid_spawn_location_for_character_from_character(
        enemy_faction_key,
        cm:char_lookup_str(player_general),
        true,
        6
    )

    if x < 0 or y < 0 then
        log("Could not find a valid spawn location for the enemy test army.")
        return
    end

    log(string.format("Spawning enemy test force for [%s] at (%s, %s) near the player force.", enemy_faction_key, tostring(x), tostring(y)))

    cm:create_force_with_general(
        enemy_faction_key,
        ENEMY_UNITS,
        player_region:name(),
        x,
        y,
        "general",
        ENEMY_GENERAL_SUBTYPE,
        "",
        "",
        "",
        "",
        false,
        function(character_cqi)
            local enemy_general = cm:get_character_by_cqi(character_cqi)
            if not enemy_general or enemy_general:is_null_interface() or not enemy_general:has_military_force() then
                log("Enemy test force creation callback fired, but the created general was invalid.")
                return
            end

            local enemy_force = enemy_general:military_force()
            set_saved_value(SAVE_KEYS.enemy_faction_key, enemy_faction_key)
            set_saved_value(SAVE_KEYS.enemy_leader_cqi, enemy_general:command_queue_index())
            set_saved_value(SAVE_KEYS.enemy_force_cqi, enemy_force:command_queue_index())

            log("Enemy test force created. General CQI=" .. tostring(enemy_general:command_queue_index()) .. ", Force CQI=" .. tostring(enemy_force:command_queue_index()) .. ", Units=" .. tostring(count_units_in_force(enemy_force)))

            cm:disable_event_feed_events(true, "", "", "diplomacy_faction_destroyed")
            cm:disable_event_feed_events(true, "", "", "character_dies_battle")
            cm:disable_event_feed_events(true, "", "", "diplomacy_war_declared")

            log("Declaring war from enemy test faction [" .. enemy_faction_key .. "] to player faction [" .. player_faction_name .. "].")
            cm:force_declare_war(enemy_faction_key, player_faction_name, false, false)
            cm:callback(function()
                cm:disable_event_feed_events(false, "", "", "diplomacy_war_declared")
            end, 0.2)

            cm:disable_movement_for_character(cm:char_lookup_str(enemy_general))
            cm:set_force_has_retreated_this_turn(enemy_force)
            log("Enemy test force movement disabled and marked as retreated this turn for forced-battle setup.")

            local agent_cqi = cm:create_agent(enemy_faction_key, ENEMY_EMBEDDED_AGENT_TYPE, ENEMY_EMBEDDED_AGENT_SUBTYPE, x, y)
            if agent_cqi then
                local alchemist = cm:get_character_by_cqi(agent_cqi)
                if alchemist and not alchemist:is_null_interface() then
                    cm:embed_agent_in_force(alchemist, enemy_force)
                    set_saved_value(SAVE_KEYS.enemy_agent_cqi, agent_cqi)
                    log("Embedded Cathay Alchemist into the enemy test army. Agent CQI=" .. tostring(agent_cqi))
                else
                    log("Enemy alchemist creation returned CQI [" .. tostring(agent_cqi) .. "] but the interface was invalid.")
                end
            else
                log("Enemy alchemist creation returned no CQI.")
            end

            cm:callback(function()
                create_test_battle(player_faction_name)
            end, 0.5)
        end
    )
end

local function handle_reward_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_REWARD_KEY then
        return
    end

    local choice = context:choice()
    local payload = get_current_event_payload()
    log("Reward dilemma choice received: " .. tostring(choice) .. " payload=[" .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, "")) .. "]")

    if choice == tonumber(payload.pause_choice or "3") then
        pause_current_event()
        return
    end

    if choice >= 0 and choice <= 2 then
        grant_reward_unit(choice)
        if not prepare_battle_event() then
            return
        end

        log("Reward resolved. Battle event is now pending and will be opened by the formal entry.")
    else
        log("Reward dilemma choice did not match any known action.")
    end
end

local function handle_battle_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_BATTLE_KEY then
        return
    end

    local choice = context:choice()
    local payload = get_current_event_payload()
    log("Battle dilemma choice received: " .. tostring(choice) .. " payload=[" .. tostring(get_saved_value(SAVE_KEYS.current_event_payload, "")) .. "]")

    if choice == tonumber(payload.pause_choice or "1") then
        pause_current_event()
        return
    end

    if choice == tonumber(payload.attack_choice or "0") then
        spawn_enemy_force_and_start_battle()
    else
        log("Battle dilemma choice did not match any known action.")
    end
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
            return dilemma_key == DILEMMA_REWARD_KEY or dilemma_key == DILEMMA_BATTLE_KEY
        end,
        function(context)
            if context:dilemma() == DILEMMA_REWARD_KEY then
                handle_reward_dilemma_choice(context)
            else
                handle_battle_dilemma_choice(context)
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

            set_saved_value(SAVE_KEYS.last_battle_result, result)
            set_saved_value(SAVE_KEYS.completed_battle_count, get_saved_value(SAVE_KEYS.completed_battle_count, 0) + 1)

            if player_won then
                set_saved_value(SAVE_KEYS.victory_count, get_saved_value(SAVE_KEYS.victory_count, 0) + 1)
                set_saved_value(SAVE_KEYS.consecutive_defeat_count, 0)
            else
                set_saved_value(SAVE_KEYS.defeat_count, get_saved_value(SAVE_KEYS.defeat_count, 0) + 1)
                set_saved_value(SAVE_KEYS.consecutive_defeat_count, get_saved_value(SAVE_KEYS.consecutive_defeat_count, 0) + 1)
            end

            log("Player test force completed a tracked battle as [" .. side .. "] with result [" .. result .. "].")

            set_current_state(STATE.INIT)
            clear_current_event_context()
            set_saved_value(SAVE_KEYS.paused_from_state, "")

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
