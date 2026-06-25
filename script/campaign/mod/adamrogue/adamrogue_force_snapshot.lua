local force_snapshot = {}

function force_snapshot.new(context)
    local self = {}
    local cm = context.cm
    local core = context.core
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

    local function clear_pre_battle_snapshots()
        set_saved_value(save_keys.pre_battle_unit_snapshot, "")
        set_saved_value(save_keys.pre_battle_embedded_hero_snapshot, "")
        set_saved_value(save_keys.pre_battle_general_rank, 1)
    end

    local HERO_SPAWN_CHAIN_START_DELAY = 0.05
    local HERO_SPAWN_API_DELAY = 0.05
    local HERO_EMBED_DELAY = 0.1

    local function invoke_restore_complete(on_complete, success, reason, scope_label)
        if not success then
            log(
                "restore_complete failed. scope=["
                    .. tostring(scope_label or "restore")
                    .. "], reason=["
                    .. tostring(reason or "")
                    .. "]."
            )
        end
        if on_complete then
            on_complete(success == true, reason or "")
        end
    end

    local function make_restore_complete_guard(on_complete, scope_label)
        local invoked = false
        local label = scope_label or "restore"
        return function(success, reason)
            if invoked then
                return
            end
            invoked = true
            invoke_restore_complete(on_complete, success, reason, label)
        end
    end

    local function build_hero_spawn_listener_name(force_cqi, index)
        return "adamrogue_restore_embedded_hero_" .. tostring(force_cqi) .. "_" .. tostring(index)
    end

    local function collect_missing_embedded_heroes(self, force, heroes, player_faction_name)
        local existing_counts = {}
        local current_heroes = self.snapshot_embedded_heroes(force)
        for _, hero in ipairs(current_heroes) do
            existing_counts[hero.agent_subtype] = (existing_counts[hero.agent_subtype] or 0) + 1
        end

        local missing_heroes = {}
        for index, hero in ipairs(heroes) do
            local existing_count = existing_counts[hero.agent_subtype] or 0
            if existing_count > 0 then
                existing_counts[hero.agent_subtype] = existing_count - 1
            else
                local restored_existing = false
                if (tonumber(hero.cqi) or 0) > 0 then
                    local existing_character = cm:get_character_by_cqi(hero.cqi)
                    if existing_character and not existing_character:is_null_interface() then
                        local existing_ok, existing_can_embed = pcall(function()
                            return existing_character:faction():name() == player_faction_name
                                and existing_character:character_subtype_key() == hero.agent_subtype
                                and not existing_character:has_military_force()
                        end)

                        if not existing_ok then
                            log(
                                "restore_embedded_heroes_to_force: cqi inspect failed. index=["
                                    .. tostring(index)
                                    .. "], subtype=["
                                    .. tostring(hero.agent_subtype)
                                    .. "], error=["
                                    .. tostring(existing_can_embed)
                                    .. "]."
                            )
                        elseif existing_can_embed then
                            cm:embed_agent_in_force(existing_character, force)
                            if existing_character:rank() < hero.rank then
                                cm:add_agent_experience(cm:char_lookup_str(existing_character:command_queue_index()), hero.rank, true)
                            end
                            restored_existing = true
                            log(
                                "restore_embedded_heroes_to_force re-embedded existing hero. subtype=["
                                    .. tostring(hero.agent_subtype)
                                    .. "], cqi=["
                                    .. tostring(hero.cqi)
                                    .. "]."
                            )
                        else
                            log(
                                "restore_embedded_heroes_to_force: cqi exists but cannot re-embed. index=["
                                    .. tostring(index)
                                    .. "], subtype=["
                                    .. tostring(hero.agent_subtype)
                                    .. "], cqi=["
                                    .. tostring(hero.cqi)
                                    .. "]."
                            )
                        end
                    end
                end

                if not restored_existing then
                    missing_heroes[#missing_heroes + 1] = hero
                end
            end
        end

        return missing_heroes, #current_heroes
    end

    local advance_hero_spawn_chain

    local function hero_spawn_character_created_matches(hero_ctx, index, ctx)
        local hero = hero_ctx.missing_heroes[index]
        if not hero then
            return false
        end

        local character = ctx:character()
        local created_subtype = character
            and not character:is_null_interface()
            and character:character_subtype_key()
            or ""
        local created_faction = character
            and not character:is_null_interface()
            and character:faction():name()
            or ""
        return character
            and not character:is_null_interface()
            and created_faction == hero_ctx.player_faction_name
            and created_subtype == hero.agent_subtype
    end

    local function embed_spawned_hero_and_continue(hero_ctx, index, hero_cqi)
        local hero = hero_ctx.missing_heroes[index]
        if not hero then
            advance_hero_spawn_chain(hero_ctx, index + 1)
            return
        end

        local refreshed_force = cm:get_military_force_by_cqi(hero_ctx.force_cqi)
        local hero_character = cm:get_character_by_cqi(hero_cqi)
        if not refreshed_force or refreshed_force:is_null_interface()
            or not hero_character or hero_character:is_null_interface() then
            log(
                "restore_embedded_heroes_to_force embed failed: force or hero invalid. subtype=["
                    .. tostring(hero.agent_subtype)
                    .. "], force_cqi=["
                    .. tostring(hero_ctx.force_cqi)
                    .. "], hero_cqi=["
                    .. tostring(hero_cqi)
                    .. "]."
            )
            advance_hero_spawn_chain(hero_ctx, index + 1)
            return
        end

        cm:embed_agent_in_force(hero_character, refreshed_force)
        if hero_character:rank() < hero.rank then
            cm:add_agent_experience(cm:char_lookup_str(hero_character:command_queue_index()), hero.rank, true)
        end
        cm:replenish_action_points(cm:char_lookup_str(hero_character:command_queue_index()))
        log(
            "restore_embedded_heroes_to_force restored embedded hero. subtype=["
                .. tostring(hero.agent_subtype)
                .. "], target_rank=["
                .. tostring(hero.rank)
                .. "], embedded=["
                .. tostring(hero_character:is_embedded_in_military_force())
                .. "]."
        )
        advance_hero_spawn_chain(hero_ctx, index + 1)
    end

    local function on_hero_spawn_character_created(hero_ctx, index, listener_name, ctx)
        local character = ctx:character()
        local hero_cqi = character and character:command_queue_index() or 0
        cm:callback(function()
            embed_spawned_hero_and_continue(hero_ctx, index, hero_cqi)
        end, HERO_EMBED_DELAY)
    end

    local function register_hero_spawn_listener(hero_ctx, index, listener_name)
        if not core then
            log("restore_embedded_heroes_to_force aborted because core is nil.")
            error("core is nil")
        end
        core:remove_listener(listener_name)
        core:add_listener(
            listener_name,
            "CharacterCreated",
            function(ctx)
                return hero_spawn_character_created_matches(hero_ctx, index, ctx)
            end,
            function(ctx)
                on_hero_spawn_character_created(hero_ctx, index, listener_name, ctx)
            end,
            false
        )
    end

    local function schedule_hero_spawn_api_call(hero_ctx, index, listener_name)
        cm:callback(function()
            local hero = hero_ctx.missing_heroes[index]
            if not hero then
                advance_hero_spawn_chain(hero_ctx, index + 1)
                return
            end

            local fresh_force = cm:get_military_force_by_cqi(hero_ctx.force_cqi)
            local fresh_faction = cm:get_faction(hero_ctx.player_faction_name)
            if not fresh_force or fresh_force:is_null_interface() then
                log(
                    "restore_embedded_heroes_to_force spawn aborted because force is invalid. force_cqi=["
                        .. tostring(hero_ctx.force_cqi)
                        .. "]."
                )
                core:remove_listener(listener_name)
                advance_hero_spawn_chain(hero_ctx, index + 1)
                return
            end
            if not fresh_faction or fresh_faction:is_null_interface() then
                log(
                    "restore_embedded_heroes_to_force spawn aborted because faction is invalid. faction=["
                        .. tostring(hero_ctx.player_faction_name)
                        .. "]."
                )
                core:remove_listener(listener_name)
                advance_hero_spawn_chain(hero_ctx, index + 1)
                return
            end

            log(
                "restore_embedded_heroes_to_force spawning missing embedded hero. index=["
                    .. tostring(index)
                    .. "], subtype=["
                    .. tostring(hero.agent_subtype)
                    .. "], force_cqi=["
                    .. tostring(hero_ctx.force_cqi)
                    .. "]."
            )
            local spawn_ok, spawn_error = pcall(function()
                cm:spawn_agent_at_military_force(fresh_faction, fresh_force, hero.agent_type, hero.agent_subtype)
            end)
            if not spawn_ok then
                core:remove_listener(listener_name)
                log(
                    "restore_embedded_heroes_to_force failed to spawn missing embedded hero. subtype=["
                        .. tostring(hero.agent_subtype)
                        .. "], error=["
                        .. tostring(spawn_error)
                        .. "]."
                )
                advance_hero_spawn_chain(hero_ctx, index + 1)
            end
        end, HERO_SPAWN_API_DELAY)
    end

    advance_hero_spawn_chain = function(hero_ctx, index)
        local hero = hero_ctx.missing_heroes[index]
        if not hero then
            log(
                "restore_embedded_heroes_to_force: all missing heroes processed. force_cqi=["
                    .. tostring(hero_ctx.force_cqi)
                    .. "], reason=["
                    .. tostring(hero_ctx.reason)
                    .. "]."
            )
            hero_ctx.finish(true, "heroes_restored")
            return
        end

        local listener_name = build_hero_spawn_listener_name(hero_ctx.force_cqi, index)
        local listener_ok, listener_err = pcall(function()
            register_hero_spawn_listener(hero_ctx, index, listener_name)
        end)
        if not listener_ok then
            log(
                "restore_embedded_heroes_to_force add_listener failed. index=["
                    .. tostring(index)
                    .. "], subtype=["
                    .. tostring(hero.agent_subtype)
                    .. "], error=["
                    .. tostring(listener_err)
                    .. "]."
            )
            hero_ctx.finish(false, "add_listener_failed")
            return
        end

        schedule_hero_spawn_api_call(hero_ctx, index, listener_name)
    end

    local function begin_missing_hero_spawn_chain(hero_ctx)
        log(
            "restore_embedded_heroes_to_force: spawning missing_count=["
                .. tostring(#hero_ctx.missing_heroes)
                .. "], force_cqi=["
                .. tostring(hero_ctx.force_cqi)
                .. "], reason=["
                .. tostring(hero_ctx.reason)
                .. "]."
        )
        cm:callback(function()
            advance_hero_spawn_chain(hero_ctx, 1)
        end, HERO_SPAWN_CHAIN_START_DELAY)
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

    function self.snapshot_embedded_heroes(force)
        local heroes = {}
        if not force or force:is_null_interface() then
            log("snapshot_embedded_heroes aborted: force is nil or null.")
            return heroes
        end

        -- Resolve the general CQI so we can skip the commanding character.
        local general_cqi = 0
        local ok_gen, err_gen = pcall(function()
            local g = force:general_character()
            if g and not g:is_null_interface() then
                general_cqi = g:command_queue_index()
            end
        end)
        if not ok_gen then
            log("snapshot_embedded_heroes: general_character() failed. error=[" .. tostring(err_gen) .. "].")
        end

        -- Use force:character_list() – includes embedded heroes, is safe to iterate.
        local ok_list, char_list = pcall(function()
            return force:character_list()
        end)
        if not ok_list or not char_list then
            log("snapshot_embedded_heroes: force:character_list() failed. error=[" .. tostring(char_list) .. "].")
            return heroes
        end

        local num = char_list:num_items()
        log(
            "snapshot_embedded_heroes: iterating. count=["
                .. tostring(num)
                .. "], general_cqi=["
                .. tostring(general_cqi)
                .. "]."
        )

        for i = 0, num - 1 do
            local ok_item, character = pcall(function()
                return char_list:item_at(i)
            end)
            if not ok_item or not character then
                log("snapshot_embedded_heroes: item_at(" .. tostring(i) .. ") failed. error=[" .. tostring(character) .. "].")
            elseif not character:is_null_interface() then
                local ok_cqi, cqi = pcall(function()
                    return character:command_queue_index()
                end)
                if not ok_cqi then
                    log("snapshot_embedded_heroes: cqi failed at index [" .. tostring(i) .. "]. error=[" .. tostring(cqi) .. "].")
                elseif cqi ~= general_cqi then
                    local ok_data, hero_data = pcall(function()
                        local a_type = character:character_type_key()
                        local a_sub  = character:character_subtype_key()
                        local a_rank = math.max(1, tonumber(character:rank()) or 1)
                        return { agent_type = a_type, agent_subtype = a_sub, rank = a_rank, cqi = cqi }
                    end)
                    if ok_data and hero_data and hero_data.agent_type ~= "" and hero_data.agent_subtype ~= "" then
                        heroes[#heroes + 1] = hero_data
                        log(
                            "snapshot_embedded_heroes: captured hero. subtype=["
                                .. tostring(hero_data.agent_subtype)
                                .. "], rank=["
                                .. tostring(hero_data.rank)
                                .. "], cqi=["
                                .. tostring(cqi)
                                .. "]."
                        )
                    elseif not ok_data then
                        log("snapshot_embedded_heroes: read failed at index [" .. tostring(i) .. "]. error=[" .. tostring(hero_data) .. "].")
                    end
                end
            end
        end

        log("snapshot_embedded_heroes finished. hero_count=[" .. tostring(#heroes) .. "].")
        return heroes
    end

    function self.encode_embedded_hero_snapshot(heroes)
        local encoded = {}
        for _, hero in ipairs(heroes or {}) do
            encoded[#encoded + 1] = tostring(hero.agent_type)
                .. ":"
                .. tostring(hero.agent_subtype)
                .. ":"
                .. tostring(hero.rank or 1)
                .. ":"
                .. tostring(hero.cqi or 0)
        end
        return table.concat(encoded, "|")
    end

    function self.decode_embedded_hero_snapshot(serialized)
        local heroes = {}
        if type(serialized) ~= "string" or serialized == "" then
            return heroes
        end

        for _, entry in ipairs(split_string(serialized, "|")) do
            local parts = split_string(entry, ":")
            local agent_type = parts[1] or ""
            local agent_subtype = parts[2] or ""
            if agent_type ~= "" and agent_subtype ~= "" then
                heroes[#heroes + 1] = {
                    agent_type = agent_type,
                    agent_subtype = agent_subtype,
                    rank = math.max(1, tonumber(parts[3]) or 1),
                    cqi = tonumber(parts[4]) or 0,
                }
            end
        end
        return heroes
    end

    function self.restore_embedded_heroes_to_force(force, serialized_snapshot, reason, on_complete)
        log(
            "restore_embedded_heroes_to_force entered. reason=["
                .. tostring(reason)
                .. "], serialized_snapshot=["
                .. tostring(serialized_snapshot)
                .. "]."
        )
        local finish = make_restore_complete_guard(on_complete, "restore_embedded_heroes_to_force")
        local heroes = self.decode_embedded_hero_snapshot(serialized_snapshot)
        if #heroes == 0 then
            log("restore_embedded_heroes_to_force skipped because no embedded hero snapshot exists. reason=[" .. tostring(reason) .. "].")
            finish(true, "no_embedded_hero_snapshot")
            return
        end

        if not force or force:is_null_interface() then
            log("restore_embedded_heroes_to_force aborted because force is invalid. reason=[" .. tostring(reason) .. "].")
            finish(false, "invalid_force")
            return
        end

        local player_faction_name = get_saved_value(save_keys.player_faction_key, "")
        local faction = cm:get_faction(player_faction_name)
        if not faction or faction:is_null_interface() then
            log("restore_embedded_heroes_to_force aborted because player faction is invalid. reason=[" .. tostring(reason) .. "].")
            finish(false, "invalid_player_faction")
            return
        end

        local force_cqi = force:command_queue_index()
        local missing_heroes, current_embedded_count = collect_missing_embedded_heroes(
            self,
            force,
            heroes,
            player_faction_name
        )
        log(
            "restore_embedded_heroes_to_force: expected_count=["
                .. tostring(#heroes)
                .. "], currently_embedded_count=["
                .. tostring(current_embedded_count)
                .. "], missing_count=["
                .. tostring(#missing_heroes)
                .. "], force_cqi=["
                .. tostring(force_cqi)
                .. "]."
        )

        if #missing_heroes == 0 then
            log("restore_embedded_heroes_to_force: all heroes already present, nothing to spawn. reason=[" .. tostring(reason) .. "].")
            finish(true, "heroes_already_present")
            return
        end

        begin_missing_hero_spawn_chain({
            missing_heroes = missing_heroes,
            force_cqi = force_cqi,
            player_faction_name = player_faction_name,
            reason = reason,
            finish = finish,
        })
    end

    function self.respawn_player_force_from_snapshot(serialized_snapshot, reason, on_complete)
        log(
            "respawn_player_force_from_snapshot started. reason=["
                .. tostring(reason)
                .. "], serialized_snapshot=["
                .. tostring(serialized_snapshot)
                .. "]"
        )
        local finish = make_restore_complete_guard(on_complete, "respawn_player_force_from_snapshot")

        local player_faction_name = get_saved_value(save_keys.player_faction_key, "")
        if player_faction_name == "" then
            log("respawn_player_force_from_snapshot aborted because the saved player faction key is empty.")
            finish(false, "empty_player_faction_key")
            return
        end

        local faction = cm:get_faction(player_faction_name)
        if not faction or faction:is_null_interface() or faction:is_dead() then
            log("respawn_player_force_from_snapshot aborted because the saved player faction is invalid.")
            finish(false, "invalid_player_faction")
            return
        end

        local unit_keys = self.decode_unit_snapshot(serialized_snapshot)
        local embedded_hero_snapshot = get_saved_value(save_keys.pre_battle_embedded_hero_snapshot, "")
        local embedded_heroes_preview = self.decode_embedded_hero_snapshot(embedded_hero_snapshot)
        log(
            "respawn_player_force_from_snapshot snapshot resolved. unit_count=["
                .. tostring(#unit_keys)
                .. "], embedded_hero_count=["
                .. tostring(#embedded_heroes_preview)
                .. "], embedded_hero_snapshot=["
                .. tostring(embedded_hero_snapshot)
                .. "], saved_general_rank=["
                .. tostring(get_saved_value(save_keys.pre_battle_general_rank, 1))
                .. "]."
        )
        if #unit_keys == 0 then
            log("respawn_player_force_from_snapshot aborted because the saved snapshot is empty.")
            finish(false, "empty_unit_snapshot")
            return
        end

        local region_key, x, y = get_spawn_region_and_position_for_faction(faction)
        if not region_key then
            log("respawn_player_force_from_snapshot aborted because no valid spawn position was found.")
            finish(false, "no_spawn_position")
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
                log(
                    "respawn_player_force_from_snapshot callback fired. character_cqi=["
                        .. tostring(character_cqi)
                        .. "], embedded_hero_count=["
                        .. tostring(#embedded_heroes_preview)
                        .. "]."
                )
                local character = cm:get_character_by_cqi(character_cqi)
                if not character or character:is_null_interface() or not character:has_military_force() then
                    log("respawn_player_force_from_snapshot callback failed because the replacement general is invalid.")
                    finish(false, "invalid_replacement_general")
                    return
                end

                local force = character:military_force()
                local current_rank = character:rank()
                set_saved_value(save_keys.player_general_subtype, character:character_subtype_key())
                set_saved_value(save_keys.player_leader_cqi, character:command_queue_index())
                set_saved_value(save_keys.player_force_cqi, force:command_queue_index())
                log(
                    "respawn_player_force_from_snapshot callback: new force ready, restoring heroes. force_cqi=["
                        .. tostring(force:command_queue_index())
                        .. "], embedded_hero_snapshot=["
                        .. tostring(embedded_hero_snapshot)
                        .. "]."
                )

                local function finalize_respawn(success, restore_reason)
                    if not success then
                        finish(false, restore_reason or "hero_restore_failed")
                        return
                    end

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

                    clear_pre_battle_snapshots()

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
                    finish(true, "respawn_completed")
                end

                self.restore_embedded_heroes_to_force(
                    force,
                    embedded_hero_snapshot,
                    "respawn_player_force_from_snapshot",
                    finalize_respawn
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

        log("capture_pre_battle_force_snapshot: step 1 – snapshot_force_units.")
        local unit_keys = self.snapshot_force_units(force)

        log("capture_pre_battle_force_snapshot: step 2 – snapshot_embedded_heroes.")
        local embedded_heroes = {}
        local ok_heroes, err_heroes = pcall(function()
            embedded_heroes = self.snapshot_embedded_heroes(force)
        end)
        if not ok_heroes then
            log("capture_pre_battle_force_snapshot: snapshot_embedded_heroes raised an error. error=[" .. tostring(err_heroes) .. "]. Proceeding with empty hero list.")
            embedded_heroes = {}
        end

        log("capture_pre_battle_force_snapshot: step 3 – read general rank.")
        local general_rank = 1
        local ok_rank, err_rank = pcall(function()
            local general = force:general_character()
            if general and not general:is_null_interface() then
                general_rank = general:rank()
            end
        end)
        if not ok_rank then
            log("capture_pre_battle_force_snapshot: general rank read failed. error=[" .. tostring(err_rank) .. "]. Defaulting to rank 1.")
        end

        log(
            "capture_pre_battle_force_snapshot: step 4 – persisting. units=["
                .. tostring(#unit_keys)
                .. "], heroes=["
                .. tostring(#embedded_heroes)
                .. "], general_rank=["
                .. tostring(general_rank)
                .. "]."
        )
        set_saved_value(save_keys.pre_battle_unit_snapshot, self.encode_unit_snapshot(unit_keys))
        set_saved_value(save_keys.pre_battle_embedded_hero_snapshot, self.encode_embedded_hero_snapshot(embedded_heroes))
        set_saved_value(save_keys.pre_battle_general_rank, general_rank)
        log("capture_pre_battle_force_snapshot completed.")
    end

    function self.restore_player_force_after_battle(on_complete)
        log("restore_player_force_after_battle started.")
        local finish = make_restore_complete_guard(on_complete, "restore_player_force_after_battle")
        local general = get_saved_player_general()
        local force = get_saved_player_force()
        local serialized_snapshot = get_saved_value(save_keys.pre_battle_unit_snapshot, "")
        local embedded_hero_snapshot = get_saved_value(save_keys.pre_battle_embedded_hero_snapshot, "")
        local embedded_heroes_preview = self.decode_embedded_hero_snapshot(embedded_hero_snapshot)
        local expected_units = self.decode_unit_snapshot(serialized_snapshot)
        log(
            "restore_player_force_after_battle snapshot summary. general_valid=["
                .. tostring(general ~= nil)
                .. "], force_valid=["
                .. tostring(force ~= nil)
                .. "], unit_count=["
                .. tostring(#expected_units)
                .. "], embedded_hero_count=["
                .. tostring(#embedded_heroes_preview)
                .. "], embedded_hero_snapshot=["
                .. tostring(embedded_hero_snapshot)
                .. "]."
        )
        if not general or not force then
            log(
                "restore_player_force_after_battle: force missing, taking respawn path. reason=[post_battle_missing_force], general_valid=["
                    .. tostring(general ~= nil)
                    .. "], force_valid=["
                    .. tostring(force ~= nil)
                    .. "]."
            )
            self.respawn_player_force_from_snapshot(serialized_snapshot, "post_battle_missing_force", finish)
            return
        end

        log("restore_player_force_after_battle: force still alive, taking in-place rebuild path.")
        if #expected_units == 0 then
            if embedded_hero_snapshot ~= "" then
                self.restore_embedded_heroes_to_force(
                    force,
                    embedded_hero_snapshot,
                    "restore_player_force_after_battle_heroes_only",
                    function(success, reason)
                        clear_pre_battle_snapshots()
                        finish(success, reason or "heroes_only_restore_completed")
                    end
                )
            else
                log("No pre-battle unit snapshot was available. Skipping unit restore.")
                finish(true, "no_unit_snapshot")
            end
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

        log(
            "restore_player_force_after_battle: rebuilding units in place, then restoring heroes. force_cqi=["
                .. tostring(force:command_queue_index())
                .. "], embedded_hero_count=["
                .. tostring(#embedded_heroes_preview)
                .. "]."
        )
        self.restore_embedded_heroes_to_force(
            force,
            embedded_hero_snapshot,
            "restore_player_force_after_battle",
            function(success, reason)
                clear_pre_battle_snapshots()
                log("Losses are not persisted. Strategy=[rebuild_force]. restored_units=[" .. tostring(restored_units) .. "]")
                finish(success, reason or "rebuild_force_completed")
            end
        )
    end

    return self
end

return force_snapshot
