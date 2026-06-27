local runtime_state = {}

runtime_state.STATE = {
    INIT = "INIT",
    OPENING_PENDING = "OPENING_PENDING",
    ARMY_PREVIEW_PENDING = "ARMY_PREVIEW_PENDING",
    HERO_REWARD_PENDING = "HERO_REWARD_PENDING",
    HERO_REWARD_FULL_PENDING = "HERO_REWARD_FULL_PENDING",
    UNIT_REWARD_PENDING = "UNIT_REWARD_PENDING",
    BATTLE_PENDING = "BATTLE_PENDING",
    EQUIPMENT_REWARD_PENDING = "EQUIPMENT_REWARD_PENDING",
    FIRST_DEFEAT_PENDING = "FIRST_DEFEAT_PENDING",
    DESTINATION_PENDING = "DESTINATION_PENDING",
    PAUSED = "PAUSED",
    GAME_OVER = "GAME_OVER"
}

runtime_state.SAVE_KEYS = {
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
    opening_dilemma_shown = "adamrogue_opening_dilemma_shown",
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

local function split_serialized_payload(input)
    local result = {}
    if type(input) ~= "string" or input == "" then
        return result
    end

    for token in string.gmatch(input, "([^|]+)") do
        result[#result + 1] = token
    end

    return result
end

function runtime_state.new(context)
    local self = {}
    local cm = context.cm
    local log = context.log or function()
    end
    local state_keys = context.state_keys or runtime_state.STATE
    local save_keys = context.save_keys or runtime_state.SAVE_KEYS
    local default_state = context.default_state or state_keys.INIT

    function self.get_saved_value(key, default_value)
        local value = cm:get_saved_value(key)
        if value == nil then
            return default_value
        end
        return value
    end

    function self.set_saved_value(key, value)
        cm:set_saved_value(key, value)
    end

    function self.get_current_state()
        return self.get_saved_value(save_keys.current_state, default_state)
    end

    function self.set_current_state(state)
        self.set_saved_value(save_keys.current_state, state)
        log("State -> " .. tostring(state))
    end

    function self.set_paused_state(from_state)
        self.set_saved_value(save_keys.paused_from_state, from_state)
        self.set_current_state(state_keys.PAUSED)
        log("Paused from state -> " .. tostring(from_state))
    end

    function self.get_paused_from_state()
        local paused_from_state = self.get_saved_value(save_keys.paused_from_state, default_state)
        if paused_from_state == nil or paused_from_state == "" then
            return default_state
        end

        return paused_from_state
    end

    function self.encode_payload(payload)
        local entries = {}

        for key, value in pairs(payload or {}) do
            entries[#entries + 1] = tostring(key) .. "=" .. tostring(value)
        end

        table.sort(entries)
        return table.concat(entries, "|")
    end

    function self.decode_payload(serialized)
        local payload = {}
        log("decode_payload called. serialized=[" .. tostring(serialized) .. "]")

        if type(serialized) ~= "string" or serialized == "" then
            return payload
        end

        for _, entry in ipairs(split_serialized_payload(serialized)) do
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

    function self.get_current_event_type()
        return self.get_saved_value(save_keys.current_event_type, "")
    end

    function self.get_current_event_key()
        return self.get_saved_value(save_keys.current_event_key, "")
    end

    function self.get_current_event_seed()
        return self.get_saved_value(save_keys.current_event_seed, 0)
    end

    function self.get_current_event_payload()
        local serialized = self.get_saved_value(save_keys.current_event_payload, "")
        log("get_current_event_payload called. serialized=[" .. tostring(serialized) .. "]")
        return self.decode_payload(serialized)
    end

    function self.set_current_event_context(event_type, event_key, event_seed, payload)
        self.set_saved_value(save_keys.current_event_type, event_type)
        self.set_saved_value(save_keys.current_event_key, event_key)
        self.set_saved_value(save_keys.current_event_seed, event_seed)
        self.set_saved_value(save_keys.current_event_payload, self.encode_payload(payload))

        log(
            "Event context saved. type=["
                .. tostring(event_type)
                .. "], key=["
                .. tostring(event_key)
                .. "], seed=["
                .. tostring(event_seed)
                .. "], payload=["
                .. tostring(self.get_saved_value(save_keys.current_event_payload, ""))
                .. "]."
        )
    end

    function self.clear_current_event_context()
        self.set_saved_value(save_keys.current_event_type, "")
        self.set_saved_value(save_keys.current_event_key, "")
        self.set_saved_value(save_keys.current_event_seed, 0)
        self.set_saved_value(save_keys.current_event_payload, "")
    end

    function self.get_saved_payload_field(field_name, default_value)
        log("get_saved_payload_field requested. field=[" .. tostring(field_name) .. "]")
        local serialized_before_decode = self.get_saved_value(save_keys.current_event_payload, "")
        log(
            "get_saved_payload_field raw serialized payload before decode. field=["
                .. tostring(field_name)
                .. "], serialized=["
                .. tostring(serialized_before_decode)
                .. "]."
        )

        local decode_ok, payload_or_error = pcall(self.get_current_event_payload)
        if not decode_ok then
            log(
                "get_saved_payload_field failed while decoding payload. field=["
                    .. tostring(field_name)
                    .. "], error=["
                    .. tostring(payload_or_error)
                    .. "]."
            )
            payload_or_error = {}
        else
            log("get_saved_payload_field decode step completed successfully. field=[" .. tostring(field_name) .. "]")
        end

        local payload = payload_or_error
        local value = payload[field_name]
        if value ~= nil and value ~= "" then
            log(
                "get_saved_payload_field resolved from decoded payload. field=["
                    .. tostring(field_name)
                    .. "], value=["
                    .. tostring(value)
                    .. "]."
            )
            return value
        end

        if type(serialized_before_decode) ~= "string" or serialized_before_decode == "" then
            log(
                "get_saved_payload_field fell back to default because serialized payload is empty. field=["
                    .. tostring(field_name)
                    .. "]."
            )
            return default_value
        end

        local pattern = field_name .. "=([^|]+)"
        local matched_value = string.match(serialized_before_decode, pattern)
        if matched_value ~= nil and matched_value ~= "" then
            log(
                "get_saved_payload_field resolved from serialized payload. field=["
                    .. tostring(field_name)
                    .. "], value=["
                    .. tostring(matched_value)
                    .. "]."
            )
            return matched_value
        end

        log(
            "get_saved_payload_field returned default. field=["
                .. tostring(field_name)
                .. "], default=["
                .. tostring(default_value)
                .. "]."
        )
        return default_value
    end

    return self
end

return runtime_state
