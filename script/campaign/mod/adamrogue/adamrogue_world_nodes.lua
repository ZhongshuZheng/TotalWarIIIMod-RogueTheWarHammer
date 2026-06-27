local world_nodes = {}

function world_nodes.new(context)
    local self = {}
    local cm = context.cm
    local log = context.log
    local state_keys = context.state_keys
    local save_keys = context.save_keys
    local node_pool = context.node_pool or {}
    local starting_node_key = context.starting_node_key
    local default_content_faction_key = context.default_content_faction_key
    local event_type = context.event_type
    local dilemma_destination_key = context.dilemma_destination_key
    local get_saved_value = context.get_saved_value
    local set_saved_value = context.set_saved_value
    local set_current_state = context.set_current_state
    local get_current_state = context.get_current_state
    local get_current_cycle = context.get_current_cycle
    local set_current_cycle = context.set_current_cycle
    local set_current_event_context = context.set_current_event_context
    local get_current_event_payload = context.get_current_event_payload
    local get_local_player_faction = context.get_local_player_faction
    local is_supported_player_faction = context.is_supported_player_faction
    local resolve_player_content_faction_key = context.resolve_player_content_faction_key
    local try_relocate_player_force_for_variety = context.try_relocate_player_force_for_variety
    local build_destination_payload_component_key = context.build_destination_payload_component_key
    local build_destination_current_payload_component_key = context.build_destination_current_payload_component_key

    local open_current_event_fn = nil
    local prepare_player_hero_reward_event_fn = nil
    local prepare_unit_reward_event_fn = nil
    local new_event_seed_fn = nil
    local pause_current_event_fn = nil
    local hero_reward_cycle_fn = nil

    function self.set_open_current_event(fn)
        open_current_event_fn = fn
    end

    function self.set_reward_preparers(hero_fn, unit_fn)
        prepare_player_hero_reward_event_fn = hero_fn
        prepare_unit_reward_event_fn = unit_fn
    end

    function self.set_runtime_hooks(seed_fn, pause_fn, hero_cycle_fn)
        new_event_seed_fn = seed_fn
        pause_current_event_fn = pause_fn
        hero_reward_cycle_fn = hero_cycle_fn
    end

    function self.find_node_data_by_key(node_key)
        for _, node_data in ipairs(node_pool) do
            if node_data.node_key == node_key then
                return node_data
            end
        end

        return nil
    end

    function self.find_node_data_by_faction_key(faction_key)
        for _, node_data in ipairs(node_pool) do
            if node_data.faction_key == faction_key then
                return node_data
            end
        end

        return nil
    end

    function self.clear_destination_selection_state(reason)
        set_saved_value(save_keys.destination_candidate_node_keys, "")
        set_saved_value(save_keys.destination_candidate_faction_keys, "")
        set_saved_value(save_keys.destination_leave_current_enabled, "false")
        set_saved_value(save_keys.destination_selection_generated, "false")
        set_saved_value(save_keys.destination_generation_seed, 0)
        set_saved_value(save_keys.destination_generation_attempts, 0)
        log("Destination selection state cleared. reason=[" .. tostring(reason) .. "].")
    end

    function self.set_current_node(node_data, reason)
        if not node_data then
            log("set_current_node aborted because node_data is nil. reason=[" .. tostring(reason) .. "].")
            return false
        end

        set_saved_value(save_keys.current_node_key, node_data.node_key)
        set_saved_value(save_keys.current_node_faction_key, node_data.faction_key)
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

    function self.ensure_current_node_initialized(reason)
        local current_node_key = get_saved_value(save_keys.current_node_key, "")
        local current_node_faction_key = get_saved_value(save_keys.current_node_faction_key, "")

        if current_node_key ~= "" then
            local existing_node = self.find_node_data_by_key(current_node_key)
            if existing_node then
                if current_node_faction_key ~= existing_node.faction_key then
                    set_saved_value(save_keys.current_node_faction_key, existing_node.faction_key)
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

        local preferred_player_faction_key = tostring(get_saved_value(save_keys.player_faction_key, "") or "")
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
            starting_node = self.find_node_data_by_faction_key(resolved_content_faction_key)
        end
        if not starting_node then
            starting_node = self.find_node_data_by_key(starting_node_key) or self.find_node_data_by_faction_key(default_content_faction_key)
        end
        if not starting_node then
            log("ensure_current_node_initialized failed because no starting node could be resolved.")
            return nil
        end

        self.set_current_node(starting_node, reason or "initialize_default_node")
        return starting_node
    end

    function self.get_current_node_data()
        local node_data = self.ensure_current_node_initialized("get_current_node_data")
        if not node_data then
            return nil
        end

        return node_data
    end

    function self.prepare_destination_event()
        local faction = get_local_player_faction()
        if not is_supported_player_faction(faction) then
            log("Cannot prepare destination event because the local faction is unsupported.")
            return false
        end

        local current_node = self.get_current_node_data()
        if not current_node then
            log("prepare_destination_event aborted because the current node could not be resolved.")
            return false
        end

        local current_cycle = get_current_cycle()
        local enabled_candidates = {}
        for _, node_data in ipairs(node_pool) do
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

        local seed = new_event_seed_fn and new_event_seed_fn() or 0
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

        set_saved_value(save_keys.destination_candidate_node_keys, table.concat({ candidate_a.node_key, candidate_b.node_key }, ","))
        set_saved_value(save_keys.destination_candidate_faction_keys, table.concat({ candidate_a.faction_key, candidate_b.faction_key }, ","))
        set_saved_value(save_keys.destination_leave_current_enabled, "true")
        set_saved_value(save_keys.destination_selection_generated, "true")
        set_saved_value(save_keys.destination_generation_seed, seed)
        set_saved_value(save_keys.destination_generation_attempts, generation_attempts)

        set_current_event_context(event_type.DESTINATION, dilemma_destination_key, seed, payload)
        set_current_state(state_keys.DESTINATION_PENDING)
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

    function self.launch_destination_dilemma(faction)
        local payload = get_current_event_payload()
        if not payload or type(payload) ~= "table" then
            log("launch_destination_dilemma aborted because the current destination payload could not be decoded.")
            return false
        end

        local candidate_node_a = self.find_node_data_by_key(payload.destination_candidate_node_0)
        local candidate_node_b = self.find_node_data_by_key(payload.destination_candidate_node_1)
        local current_node = self.find_node_data_by_key(payload.current_node_key) or self.get_current_node_data()
        if not candidate_node_a or not candidate_node_b or not current_node then
            log(
                "launch_destination_dilemma aborted because one or more saved destination nodes are invalid. payload=["
                    .. tostring(get_saved_value(save_keys.current_event_payload, ""))
                    .. "]."
            )
            return false
        end

        local dilemma_builder = cm:create_dilemma_builder(dilemma_destination_key)
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

    function self.handle_destination_dilemma_choice(context)
        cm:callback(function()
            local choice = context:choice()
            log("Processing deferred destination dilemma choice: " .. tostring(choice))

            if choice == 3 then
                if pause_current_event_fn then
                    pause_current_event_fn()
                end
                return
            end

            local payload = get_current_event_payload()
            if not payload or type(payload) ~= "table" then
                log("handle_destination_dilemma_choice aborted because the current destination payload could not be decoded.")
                return
            end

            local selected_node = nil
            if choice == 0 then
                selected_node = self.find_node_data_by_key(payload.destination_candidate_node_0)
            elseif choice == 1 then
                selected_node = self.find_node_data_by_key(payload.destination_candidate_node_1)
            elseif choice == 2 then
                selected_node = self.find_node_data_by_key(payload.current_node_key)
            else
                log("Destination dilemma choice did not match any known action.")
                return
            end

            if not selected_node then
                log("handle_destination_dilemma_choice aborted because the selected node could not be resolved from the payload.")
                return
            end

            local previous_cycle = get_current_cycle()
            self.set_current_node(selected_node, "destination_choice_" .. tostring(choice))
            set_current_cycle(previous_cycle + 1)
            log(
                "Destination resolved without applying player character minimum-rank scaling. reason=[destination_choice_"
                    .. tostring(choice)
                    .. "]."
            )

            local prepared_next_reward = false
            if hero_reward_cycle_fn and hero_reward_cycle_fn(get_current_cycle()) then
                prepared_next_reward = prepare_player_hero_reward_event_fn and prepare_player_hero_reward_event_fn() or false
            end
            if not prepared_next_reward then
                prepared_next_reward = prepare_unit_reward_event_fn and prepare_unit_reward_event_fn() or false
            end
            if not prepared_next_reward then
                set_current_cycle(previous_cycle)
                return
            end

            self.clear_destination_selection_state("destination_choice_resolved")
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
                if (get_current_state() == state_keys.UNIT_REWARD_PENDING or get_current_state() == state_keys.HERO_REWARD_PENDING)
                    and open_current_event_fn then
                    open_current_event_fn("destination_resolved_auto_open")
                end
            end, 0.1)
        end, 0.1)
    end

    return self
end

return world_nodes
