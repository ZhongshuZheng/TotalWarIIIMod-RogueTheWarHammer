local player_bootstrap = {}

function player_bootstrap.new(context)
    local self = {}
    local cm = context.cm
    local log = context.log
    local balance_config = context.balance_config
    local state_keys = context.state_keys
    local save_keys = context.save_keys
    local default_supported_player_faction_key = context.default_supported_player_faction_key
    local default_player_content_faction_key = context.default_player_content_faction_key
    local default_content_faction_key = context.default_content_faction_key
    local player_content_faction_by_faction = context.player_content_faction_by_faction or {}
    local player_general_options_by_faction = context.player_general_options_by_faction or {}
    local default_player_general_subtype_by_faction = context.default_player_general_subtype_by_faction or {}
    local battle_unit_pools_by_content_faction = context.battle_unit_pools_by_content_faction or {}
    local get_saved_value = context.get_saved_value
    local set_saved_value = context.set_saved_value
    local get_current_state = context.get_current_state
    local clear_current_event_context = context.clear_current_event_context
    local clear_destination_selection_state = context.clear_destination_selection_state
    local ensure_current_node_initialized = context.ensure_current_node_initialized
    local find_node_data_by_faction_key = context.find_node_data_by_faction_key
    local set_current_node = context.set_current_node
    local ensure_balance_state_initialized = context.ensure_balance_state_initialized
    local set_current_state = context.set_current_state
    local get_local_player_faction = context.get_local_player_faction
    local get_saved_player_general = context.get_saved_player_general
    local get_saved_player_force = context.get_saved_player_force
    local count_units_in_force = context.count_units_in_force
    local get_current_cycle = context.get_current_cycle
    local get_difficulty_level = context.get_difficulty_level
    local get_spawn_region_and_position_for_faction = context.get_spawn_region_and_position_for_faction
    local dilemma_army_preview_key = context.dilemma_army_preview_key

    local open_current_event_fn = nil

    function self.set_open_current_event(fn)
        open_current_event_fn = fn
    end

    function self.resolve_player_content_faction_key(player_faction_key)
        if type(player_faction_key) ~= "string" or player_faction_key == "" then
            return default_player_content_faction_key or default_content_faction_key, "default_empty_player_faction"
        end

        local mapped_content_faction_key = player_content_faction_by_faction[player_faction_key]
        if mapped_content_faction_key and mapped_content_faction_key ~= "" then
            return mapped_content_faction_key, "player_mapping"
        end

        if battle_unit_pools_by_content_faction[player_faction_key] then
            return player_faction_key, "direct_content_pool"
        end

        return default_player_content_faction_key or default_content_faction_key, "default_fallback"
    end

    local function get_player_general_options_for_faction(player_faction_key)
        local options = player_general_options_by_faction[player_faction_key]
        if options and #options > 0 then
            return options, player_faction_key, "exact_player_faction"
        end

        local resolved_content_faction_key = self.resolve_player_content_faction_key(player_faction_key)
        for supported_faction_key, content_faction_key in pairs(player_content_faction_by_faction) do
            if content_faction_key == resolved_content_faction_key then
                local shared_options = player_general_options_by_faction[supported_faction_key]
                if shared_options and #shared_options > 0 then
                    return shared_options, supported_faction_key, "shared_content_faction"
                end
            end
        end

        local default_options = player_general_options_by_faction[default_supported_player_faction_key] or {}
        return default_options, default_supported_player_faction_key, "default_supported_player_faction"
    end

    function self.get_default_player_general_subtype_for_faction(player_faction_key)
        local default_subtype = default_player_general_subtype_by_faction[player_faction_key]
        if default_subtype and default_subtype ~= "" then
            return default_subtype
        end

        local options = player_general_options_by_faction[player_faction_key]
        if options and options[1] and options[1].subtype and options[1].subtype ~= "" then
            return options[1].subtype
        end

        if default_supported_player_faction_key and default_supported_player_faction_key ~= "" then
            local fallback_subtype = default_player_general_subtype_by_faction[default_supported_player_faction_key]
            if fallback_subtype and fallback_subtype ~= "" then
                return fallback_subtype
            end
        end

        return ""
    end

    function self.pick_random_player_general_option(player_faction_key)
        local player_general_options, resolved_general_pool_faction_key, resolution =
            get_player_general_options_for_faction(player_faction_key)
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

        local fallback_subtype = self.get_default_player_general_subtype_for_faction(player_faction_key)
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

    function self.build_starting_player_unit_list(player_faction_key, selected_general_option)
        local total_value_budget = tonumber(balance_config.initial_player_value) or 4500
        local selected_general_value = tonumber(selected_general_option and selected_general_option.unit_value) or 0
        local target_value_budget = math.max(0, total_value_budget - selected_general_value)
        local resolved_faction_key, content_resolution = self.resolve_player_content_faction_key(player_faction_key)
        local source_pool = battle_unit_pools_by_content_faction[resolved_faction_key]

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
            source_pool = battle_unit_pools_by_content_faction[default_content_faction_key] or {}
            resolved_faction_key = default_content_faction_key
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

    function self.spawn_new_preview_army(faction)
        local region_key, x, y = get_spawn_region_and_position_for_faction(faction)
        if not region_key then
            log("spawn_new_preview_army: failed to find a valid spawn position for faction [" .. faction:name() .. "].")
            return false
        end

        local resolved_player_content_faction_key = self.resolve_player_content_faction_key(faction:name())
        local selected_player_general_option = self.pick_random_player_general_option(faction:name())
        local player_general_subtype = selected_player_general_option.subtype
            or self.get_default_player_general_subtype_for_faction(faction:name())
        local starting_unit_list, logged_starting_unit_list, starting_unit_value =
            self.build_starting_player_unit_list(faction:name(), selected_player_general_option)
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
                set_saved_value(save_keys.player_faction_key, faction_name_capture)
                set_saved_value(save_keys.player_general_subtype, character:character_subtype_key())
                set_saved_value(save_keys.player_leader_cqi, character:command_queue_index())
                set_saved_value(save_keys.player_force_cqi, force:command_queue_index())

                clear_current_event_context()
                clear_destination_selection_state("preview_army_created")
                local starting_node = find_node_data_by_faction_key(resolved_player_content_faction_key)
                if not starting_node then
                    starting_node = ensure_current_node_initialized("preview_army_created")
                else
                    set_current_node(starting_node, "preview_army_created_from_player_faction")
                end
                ensure_balance_state_initialized("preview_army_created")
                set_saved_value(save_keys.paused_from_state, "")
                set_current_state(state_keys.ARMY_PREVIEW_PENDING)

                log(
                    "spawn_new_preview_army callback: preview army created. cqi=["
                        .. tostring(character_cqi)
                        .. "], subtype=["
                        .. tostring(character:character_subtype_key())
                        .. "]. Launching army preview dilemma."
                )

                local preview_faction = cm:get_faction(faction_name_capture)
                if preview_faction and not preview_faction:is_null_interface() then
                    self.launch_army_preview_dilemma(preview_faction)
                end
            end
        )
        return true
    end

    function self.launch_army_preview_dilemma(faction)
        local player_force = get_saved_player_force()
        if not player_force then
            log("launch_army_preview_dilemma aborted: player preview force is unavailable.")
            return false
        end

        local dilemma_builder = cm:create_dilemma_builder(dilemma_army_preview_key)
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

    function self.handle_army_preview_dilemma_choice(context)
        if context:dilemma() ~= dilemma_army_preview_key then
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
                local preview_general = get_saved_player_general()
                if preview_general then
                    log("handle_army_preview_dilemma_choice: killing old preview army for reroll.")
                    cm:kill_character(cm:char_lookup_str(preview_general), true)
                end
                set_saved_value(save_keys.player_leader_cqi, 0)
                set_saved_value(save_keys.player_force_cqi, 0)
                set_current_state(state_keys.INIT)
                cm:callback(function()
                    local faction = get_local_player_faction()
                    if faction and not faction:is_null_interface() and open_current_event_fn then
                        open_current_event_fn("army_preview_reroll")
                    end
                end, 0.5)
            elseif choice == 1 then
                set_current_state(state_keys.INIT)
                log("handle_army_preview_dilemma_choice: player chose Later. Preview army remains on map. State reset to INIT.")
            elseif choice == 2 then
                local faction = get_local_player_faction()
                if not faction or faction:is_null_interface() then
                    log("handle_army_preview_dilemma_choice: cannot confirm - faction unavailable.")
                    return
                end
                set_saved_value(save_keys.run_started, true)
                set_saved_value(save_keys.completed_battle_count, get_saved_value(save_keys.completed_battle_count, 0))
                set_saved_value(save_keys.victory_count, get_saved_value(save_keys.victory_count, 0))
                set_saved_value(save_keys.defeat_count, get_saved_value(save_keys.defeat_count, 0))
                set_saved_value(save_keys.consecutive_defeat_count, get_saved_value(save_keys.consecutive_defeat_count, 0))
                set_current_state(state_keys.INIT)
                log("handle_army_preview_dilemma_choice: run confirmed. run_started=true. Proceeding to reward event.")
                cm:callback(function()
                    if open_current_event_fn then
                        open_current_event_fn("army_preview_confirmed")
                    end
                end, 0.1)
            else
                log("handle_army_preview_dilemma_choice: unrecognised choice [" .. tostring(choice) .. "].")
            end
        end, 0.1)
    end

    return self
end

return player_bootstrap
