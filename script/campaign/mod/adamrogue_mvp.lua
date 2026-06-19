local MODULE_KEY = "adamrogue_mvp"

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

local STATE = {
    NONE = "NONE",
    UNIT_REWARD_PENDING = "UNIT_REWARD_PENDING",
    BATTLE_PENDING = "BATTLE_PENDING",
    BATTLE_ACTIVE = "BATTLE_ACTIVE",
    BATTLE_RESOLVED = "BATTLE_RESOLVED"
}

local SAVE_KEYS = {
    run_started = "adamrogue_run_started",
    player_faction_key = "adamrogue_player_faction_key",
    player_force_cqi = "adamrogue_force_cqi",
    player_leader_cqi = "adamrogue_leader_cqi",
    current_state = "adamrogue_current_state",
    last_reward_unit = "adamrogue_last_reward_unit",
    last_battle_result = "adamrogue_last_battle_result",
    last_dilemma_turn = "adamrogue_last_dilemma_turn",
    enemy_faction_key = "adamrogue_enemy_faction_key",
    enemy_force_cqi = "adamrogue_enemy_force_cqi",
    enemy_leader_cqi = "adamrogue_enemy_leader_cqi",
    enemy_agent_cqi = "adamrogue_enemy_agent_cqi"
}

local function log(message)
    out("[" .. MODULE_KEY .. "] " .. tostring(message))
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
    return get_saved_value(SAVE_KEYS.current_state, STATE.NONE)
end

local function set_current_state(state)
    set_saved_value(SAVE_KEYS.current_state, state)
    log("State -> " .. state)
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

local function force_attack_once(player_force_cqi, enemy_force_cqi, source_label)
    log(
        "Launching forced test battle from ["
            .. tostring(source_label)
            .. "]. Player force CQI="
            .. tostring(player_force_cqi)
            .. ", Enemy force CQI="
            .. tostring(enemy_force_cqi)
    )

    set_current_state(STATE.BATTLE_ACTIVE)

    cm:callback(function()
        cm:force_attack_of_opportunity(player_force_cqi, enemy_force_cqi, false, true)
    end, 0.05)
end

local function save_last_dilemma_turn()
    set_saved_value(SAVE_KEYS.last_dilemma_turn, cm:model():turn_number())
end

local function already_triggered_dilemma_this_turn()
    return get_saved_value(SAVE_KEYS.last_dilemma_turn, -1) == cm:model():turn_number()
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

local function trigger_reward_dilemma(faction)
    if already_triggered_dilemma_this_turn() then
        return
    end

    log("Triggering reward dilemma for faction [" .. faction:name() .. "]")
    cm:trigger_dilemma(faction:name(), DILEMMA_REWARD_KEY)
    save_last_dilemma_turn()
end

local function trigger_battle_dilemma(faction)
    if already_triggered_dilemma_this_turn() then
        return
    end

    log("Triggering battle dilemma for faction [" .. faction:name() .. "]")
    cm:trigger_dilemma(faction:name(), DILEMMA_BATTLE_KEY)
    save_last_dilemma_turn()
end

local function maybe_trigger_pending_dilemma(reason)
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        return
    end

    local state = get_current_state()
    if state == STATE.UNIT_REWARD_PENDING then
        log("Pending reward dilemma resume requested by " .. reason)
        trigger_reward_dilemma(faction)
    elseif state == STATE.BATTLE_PENDING then
        log("Pending battle dilemma resume requested by " .. reason)
        trigger_battle_dilemma(faction)
    end
end

local function spawn_player_force_if_needed()
    local faction = get_local_player_faction()
    if not is_supported_player_faction(faction) then
        log("Local player faction is not supported for MVP. Waiting for a Cathay human faction.")
        return
    end

    if get_saved_player_force() then
        log("Player test force already exists.")
        return
    end

    local region_key, x, y = get_spawn_region_and_position_for_faction(faction)
    if not region_key then
        log("Failed to find a valid spawn position for the player test force.")
        return
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
            set_saved_value(SAVE_KEYS.last_reward_unit, "")
            set_saved_value(SAVE_KEYS.last_battle_result, "")

            log("Player test force created. General CQI=" .. tostring(character:command_queue_index()) .. ", Force CQI=" .. tostring(force:command_queue_index()) .. ", Units=" .. tostring(count_units_in_force(force)))

            set_current_state(STATE.UNIT_REWARD_PENDING)

            cm:callback(function()
                maybe_trigger_pending_dilemma("player_force_created")
            end, 0.5)
        end
    )
end

local function grant_reward_unit(choice)
    local reward_unit_key = REWARD_UNITS_BY_CHOICE[choice]
    if not reward_unit_key then
        log("Reward dilemma delayed or unsupported choice selected: " .. tostring(choice))
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

    set_current_state(STATE.BATTLE_PENDING)

    cm:callback(function()
        maybe_trigger_pending_dilemma("reward_choice_resolved")
    end, 0.5)
end

local function begin_test_battle_attack(player_faction_name)
    local player_force = get_saved_player_force()
    local enemy_force = get_saved_enemy_force()
    local player_faction = cm:get_faction(player_faction_name)
    local enemy_general = get_saved_enemy_general()

    if not player_force or not enemy_force or not player_faction or player_faction:is_null_interface() or not enemy_general then
        log("Unable to begin test battle attack because one or more required interfaces were missing.")
        return
    end

    local player_force_cqi = player_force:command_queue_index()
    local enemy_force_cqi = enemy_force:command_queue_index()
    local enemy_faction_name = enemy_general:faction():name()

    log("Preparing forced attack. Player force CQI=" .. tostring(player_force_cqi) .. ", Enemy force CQI=" .. tostring(enemy_force_cqi))

    if not player_faction:at_war_with(enemy_general:faction()) then
        local attack_started = false

        local function launch_attack_from(source_label)
            if attack_started then
                log("Ignored duplicate forced-attack launch from [" .. tostring(source_label) .. "]")
                return
            end

            attack_started = true
            core:remove_listener("adamrogue_mvp_force_war_then_attack")
            force_attack_once(player_force_cqi, enemy_force_cqi, source_label)
        end

        cm:disable_event_feed_events(true, "wh_event_category_diplomacy", "", "")
        cm:disable_event_feed_events(true, "wh_event_category_character", "", "")

        cm:callback(function()
            cm:disable_event_feed_events(false, "wh_event_category_diplomacy", "", "")
            cm:disable_event_feed_events(false, "wh_event_category_character", "", "")
        end, 0.2)

        core:remove_listener("adamrogue_mvp_force_war_then_attack")
        core:add_listener(
            "adamrogue_mvp_force_war_then_attack",
            "FactionLeaderDeclaresWar",
            true,
            function()
                local refreshed_player_faction = cm:get_faction(player_faction_name)
                local refreshed_enemy_general = get_saved_enemy_general()

                if
                    refreshed_player_faction
                    and not refreshed_player_faction:is_null_interface()
                    and refreshed_enemy_general
                    and refreshed_player_faction:at_war_with(refreshed_enemy_general:faction())
                then
                    log("War declaration listener confirmed both factions are now at war.")
                    launch_attack_from("FactionLeaderDeclaresWar")
                else
                    log("FactionLeaderDeclaresWar fired, but the tracked factions are not yet confirmed at war. Waiting for fallback check.")
                end
            end,
            false
        )

        log("Declaring war on enemy test faction [" .. enemy_faction_name .. "] before forced attack.")
        cm:force_declare_war(player_faction_name, enemy_faction_name, false, false)

        cm:callback(function()
            local refreshed_player_faction = cm:get_faction(player_faction_name)
            local refreshed_enemy_general = get_saved_enemy_general()

            if
                refreshed_player_faction
                and not refreshed_player_faction:is_null_interface()
                and refreshed_enemy_general
                and refreshed_player_faction:at_war_with(refreshed_enemy_general:faction())
            then
                log("Fallback war-state check succeeded after force_declare_war.")
                launch_attack_from("war_state_fallback")
            else
                log("Fallback war-state check failed. Battle remains pending for later investigation.")
                set_current_state(STATE.BATTLE_PENDING)
            end
        end, 0.5)
    else
        log("Enemy test faction is already at war with the player. Launching forced test battle directly.")
        force_attack_once(player_force_cqi, enemy_force_cqi, "already_at_war")
    end
end

local function spawn_enemy_force_and_start_battle()
    local player_force = get_saved_player_force()
    local player_general = get_saved_player_general()
    local player_faction_name = get_saved_value(SAVE_KEYS.player_faction_key, "")

    if not player_force or not player_general or player_faction_name == "" then
        log("Cannot start the test battle because the player force state is incomplete.")
        return
    end

    if get_saved_enemy_force() or get_saved_character(SAVE_KEYS.enemy_agent_cqi) then
        log("A previous enemy test army was still tracked. Cleaning it up before spawning a fresh one.")
        cleanup_enemy_force()
    end

    local enemy_faction_key = pick_enemy_faction_key(player_faction_name)
    if not enemy_faction_key then
        log("Could not find a living non-player Cathay faction for the enemy test army.")
        return
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
                begin_test_battle_attack(player_faction_name)
            end, 0.3)
        end
    )
end

local function handle_reward_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_REWARD_KEY then
        return
    end

    local choice = context:choice()
    log("Reward dilemma choice received: " .. tostring(choice))

    if choice >= 0 and choice <= 2 then
        grant_reward_unit(choice)
    else
        log("Reward dilemma postponed by the player.")
    end
end

local function handle_battle_dilemma_choice(context)
    if context:dilemma() ~= DILEMMA_BATTLE_KEY then
        return
    end

    local choice = context:choice()
    log("Battle dilemma choice received: " .. tostring(choice))

    if choice == 0 then
        spawn_enemy_force_and_start_battle()
    else
        log("Battle dilemma postponed by the player.")
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

local function register_listeners()
    core:remove_listener("adamrogue_mvp_dilemma_choice")
    core:add_listener(
        "adamrogue_mvp_dilemma_choice",
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

    core:remove_listener("adamrogue_mvp_resume_turn_start")
    core:add_listener(
        "adamrogue_mvp_resume_turn_start",
        "FactionTurnStart",
        function(context)
            local saved_player_faction_key = get_saved_value(SAVE_KEYS.player_faction_key, "")
            return saved_player_faction_key ~= "" and context:faction():name() == saved_player_faction_key and context:faction():is_human()
        end,
        function(context)
            log("FactionTurnStart for player faction [" .. context:faction():name() .. "] at turn " .. tostring(cm:model():turn_number()))
            maybe_trigger_pending_dilemma("FactionTurnStart")
        end,
        true
    )

    core:remove_listener("adamrogue_mvp_battle_completed")
    core:add_listener(
        "adamrogue_mvp_battle_completed",
        "BattleCompleted",
        true,
        function()
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
            log("Player test force completed a tracked battle as [" .. side .. "] with result [" .. result .. "].")

            set_current_state(STATE.BATTLE_RESOLVED)

            cm:callback(function()
                cleanup_enemy_force()
            end, 0.2)
        end,
        true
    )
end

cm:add_first_tick_callback(function()
    log("First tick initialization started.")
    register_listeners()
    spawn_player_force_if_needed()
    maybe_trigger_pending_dilemma("first_tick_resume")
    log("First tick initialization finished.")
end)
