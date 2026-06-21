local force_snapshot = {}

function force_snapshot.new(context)
    local self = {}
    local cm = context.cm
    local log = context.log
    local save_keys = context.save_keys
    local get_default_player_general_subtype_for_faction = context.get_default_player_general_subtype_for_faction
    local get_saved_value = context.get_saved_value
    local set_saved_value = context.set_saved_value
    local split_string = context.split_string
    local count_units_in_force = context.count_units_in_force
    local get_spawn_region_and_position_for_faction = context.get_spawn_region_and_position_for_faction
    local get_saved_player_force = context.get_saved_player_force
    local get_saved_player_general = context.get_saved_player_general

    local function get_respawn_player_general_subtype()
        local saved_subtype = tostring(get_saved_value(save_keys.player_general_subtype, "") or "")
        if saved_subtype ~= "" then
            return saved_subtype
        end

        local saved_player_faction_key = tostring(get_saved_value(save_keys.player_faction_key, "") or "")
        if saved_player_faction_key ~= "" and get_default_player_general_subtype_for_faction then
            return get_default_player_general_subtype_for_faction(saved_player_faction_key)
        end

        return ""
    end

    function self.snapshot_force_units(force)
        local units = {}

        if not force or force:is_null_interface() then
            log("snapshot_force_units aborted because the force interface is missing.")
            return units
        end

        local unit_list = force:unit_list()
        if not unit_list then
            log("snapshot_force_units aborted because force:unit_list() returned nil.")
            return units
        end

        for i = 0, unit_list:num_items() - 1 do
            local unit = unit_list:item_at(i)
            if not unit then
                log("snapshot_force_units encountered a nil unit at index [" .. tostring(i) .. "].")
                return units
            end

            if unit:is_null_interface() then
                log("snapshot_force_units encountered a null unit interface at index [" .. tostring(i) .. "].")
                return units
            end

            if unit:unit_class() == "com" then
            else
                units[#units + 1] = unit:unit_key()
            end
        end

        log("snapshot_force_units finished. snapshot_size=[" .. tostring(#units) .. "]")
        return units
    end

    function self.encode_unit_snapshot(unit_keys)
        return table.concat(unit_keys, ",")
    end

    function self.decode_unit_snapshot(serialized)
        if type(serialized) ~= "string" or serialized == "" then
            return {}
        end

        return split_string(serialized, ",")
    end

    function self.respawn_player_force_from_snapshot(serialized_snapshot, reason)
        log(
            "respawn_player_force_from_snapshot started. reason=["
                .. tostring(reason)
                .. "], serialized_snapshot=["
                .. tostring(serialized_snapshot)
                .. "]"
        )

        local player_faction_name = get_saved_value(save_keys.player_faction_key, "")
        if player_faction_name == "" then
            log("respawn_player_force_from_snapshot aborted because the saved player faction key is empty.")
            return
        end

        local faction = cm:get_faction(player_faction_name)
        if not faction or faction:is_null_interface() or faction:is_dead() then
            log("respawn_player_force_from_snapshot aborted because the saved player faction is invalid.")
            return
        end

        local unit_keys = self.decode_unit_snapshot(serialized_snapshot)
        if #unit_keys == 0 then
            log("respawn_player_force_from_snapshot aborted because the saved snapshot is empty.")
            return
        end

        local region_key, x, y = get_spawn_region_and_position_for_faction(faction)
        if not region_key then
            log("respawn_player_force_from_snapshot aborted because no valid spawn position was found.")
            return
        end

        local unit_list = self.encode_unit_snapshot(unit_keys)
        local saved_rank = tonumber(get_saved_value(save_keys.pre_battle_general_rank, 1)) or 1
        log(
            "respawn_player_force_from_snapshot creating a replacement army for faction ["
                .. tostring(player_faction_name)
                .. "] in region ["
                .. tostring(region_key)
                .. "] at ("
                .. tostring(x)
                .. ", "
                .. tostring(y)
                .. ") with unit_count=["
                .. tostring(#unit_keys)
                .. "]."
        )

        cm:create_force_with_general(
            player_faction_name,
            unit_list,
            region_key,
            x,
            y,
            "general",
            get_respawn_player_general_subtype(),
            "",
            "",
            "",
            "",
            false,
            function(character_cqi)
                local character = cm:get_character_by_cqi(character_cqi)
                if not character or character:is_null_interface() or not character:has_military_force() then
                    log("respawn_player_force_from_snapshot callback failed because the replacement general is invalid.")
                    return
                end

                local force = character:military_force()
                local current_rank = character:rank()
                set_saved_value(save_keys.player_general_subtype, character:character_subtype_key())
                set_saved_value(save_keys.player_leader_cqi, character:command_queue_index())
                set_saved_value(save_keys.player_force_cqi, force:command_queue_index())
                log(
                    "respawn_player_force_from_snapshot callback captured replacement general rank state. current_rank=["
                        .. tostring(current_rank)
                        .. "], saved_rank=["
                        .. tostring(saved_rank)
                        .. "]."
                )

                if saved_rank > current_rank then
                    cm:add_agent_experience(cm:char_lookup_str(character:command_queue_index()), saved_rank, true)
                    log(
                        "respawn_player_force_from_snapshot restored replacement general rank using add_agent_experience. target_rank=["
                            .. tostring(saved_rank)
                            .. "]."
                    )
                    current_rank = character:rank()
                end

                set_saved_value(save_keys.pre_battle_unit_snapshot, "")
                set_saved_value(save_keys.pre_battle_general_rank, 1)

                log(
                    "respawn_player_force_from_snapshot completed. General CQI=["
                        .. tostring(character:command_queue_index())
                        .. "], Force CQI=["
                        .. tostring(force:command_queue_index())
                        .. "], Units=["
                        .. tostring(count_units_in_force(force))
                        .. "], FinalRank=["
                        .. tostring(current_rank)
                        .. "]."
                )
            end
        )
    end

    function self.capture_pre_battle_force_snapshot()
        log("capture_pre_battle_force_snapshot started.")
        local force = get_saved_player_force()
        if not force then
            log("capture_pre_battle_force_snapshot aborted because get_saved_player_force() returned nil.")
            return
        end

        local unit_keys = self.snapshot_force_units(force)
        local general = force:general_character()
        local general_rank = 1
        if general and not general:is_null_interface() then
            general_rank = general:rank()
        end
        log("capture_pre_battle_force_snapshot encoding snapshot. units=[" .. tostring(#unit_keys) .. "]")
        set_saved_value(save_keys.pre_battle_unit_snapshot, self.encode_unit_snapshot(unit_keys))
        set_saved_value(save_keys.pre_battle_general_rank, general_rank)
        log(
            "Captured pre-battle force snapshot. units=["
                .. tostring(#unit_keys)
                .. "], general_rank=["
                .. tostring(general_rank)
                .. "]."
        )
    end

    function self.restore_player_force_after_battle()
        log("restore_player_force_after_battle started.")
        local general = get_saved_player_general()
        local force = get_saved_player_force()
        local serialized_snapshot = get_saved_value(save_keys.pre_battle_unit_snapshot, "")
        if not general or not force then
            log("Could not restore battle losses because the player force is missing. Attempting to respawn the player force from the saved snapshot.")
            self.respawn_player_force_from_snapshot(serialized_snapshot, "post_battle_missing_force")
            return
        end

        local expected_units = self.decode_unit_snapshot(serialized_snapshot)
        if #expected_units == 0 then
            log("No pre-battle snapshot was available. Skipping force restore.")
            return
        end

        local live_counts = {}
        local unit_list = force:unit_list()
        for i = 0, unit_list:num_items() - 1 do
            local unit = unit_list:item_at(i)
            local unit_key = unit:unit_key()
            live_counts[unit_key] = (live_counts[unit_key] or 0) + 1
            cm:set_unit_hp_to_unary_of_maximum(unit, 1)
        end

        local expected_counts = {}
        for _, unit_key in ipairs(expected_units) do
            expected_counts[unit_key] = (expected_counts[unit_key] or 0) + 1
        end

        local restored_units = 0
        for unit_key, expected_count in pairs(expected_counts) do
            local live_count = live_counts[unit_key] or 0
            while live_count < expected_count do
                log(
                    "restore_player_force_after_battle granting replacement unit_key=["
                        .. tostring(unit_key)
                        .. "], live_count=["
                        .. tostring(live_count)
                        .. "], expected_count=["
                        .. tostring(expected_count)
                        .. "]."
                )
                cm:grant_unit_to_character(cm:char_lookup_str(general), unit_key)
                restored_units = restored_units + 1
                live_count = live_count + 1
            end
        end

        set_saved_value(save_keys.pre_battle_unit_snapshot, "")
        set_saved_value(save_keys.pre_battle_general_rank, 1)
        log("Losses are not persisted. Strategy=[rebuild_force]. restored_units=[" .. tostring(restored_units) .. "]")
    end

    return self
end

return force_snapshot
