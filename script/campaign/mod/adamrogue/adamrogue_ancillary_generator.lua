local ancillary_generator = {}

function ancillary_generator.new(context)
    local self = {}
    local log = context.log
    local cm = context.cm
    local common_pool = context.common_pool or {}
    local faction_pools = context.faction_pools or {}
    local battle_tier_keys = context.battle_tier
    local rarity_keys = context.equipment_rarity
    local slot_order = context.slot_order
    local equipment_rarity_by_cycle = context.equipment_rarity_by_cycle or {}
    local elite_battle_cycles = context.elite_battle_cycles or {}
    local elite_reward_highest_tier = context.elite_reward_highest_tier == true
    local rarity_order = {
        rarity_keys.COMMON,
        rarity_keys.UNCOMMON,
        rarity_keys.RARE,
        rarity_keys.UNIQUE,
        rarity_keys.LEGENDARY
    }

    function self.get_reward_pool_sources(player_faction_key, current_node_faction_key)
        local pool_sources = {
            { scope = "common", faction_key = "common", entries = common_pool }
        }

        local player_pool = faction_pools[player_faction_key]
        if player_pool and #player_pool > 0 then
            pool_sources[#pool_sources + 1] = {
                scope = "player_faction",
                faction_key = player_faction_key,
                entries = player_pool
            }
        end

        if current_node_faction_key and current_node_faction_key ~= "" and current_node_faction_key ~= player_faction_key then
            local node_pool = faction_pools[current_node_faction_key]
            if node_pool and #node_pool > 0 then
                pool_sources[#pool_sources + 1] = {
                    scope = "current_node_faction",
                    faction_key = current_node_faction_key,
                    entries = node_pool
                }
            end
        end

        return pool_sources
    end

    local function contains_value(list, target)
        for _, value in ipairs(list or {}) do
            if value == target then
                return true
            end
        end

        return false
    end

    function self.is_elite_battle_cycle(current_cycle)
        local normalized_cycle = math.max(1, math.floor(tonumber(current_cycle) or 1))
        for _, elite_cycle in ipairs(elite_battle_cycles) do
            if normalized_cycle == tonumber(elite_cycle) then
                return true
            end
        end

        return false
    end

    function self.get_allowed_rarity_bands_for_cycle(current_cycle)
        local normalized_cycle = math.max(1, math.floor(tonumber(current_cycle) or 1))
        for _, entry in ipairs(equipment_rarity_by_cycle) do
            local min_cycle = tonumber(entry.min_cycle) or 1
            local max_cycle = entry.max_cycle and tonumber(entry.max_cycle) or nil
            if normalized_cycle >= min_cycle and (not max_cycle or normalized_cycle <= max_cycle) then
                return entry.tiers or { rarity_keys.COMMON }
            end
        end

        return { rarity_keys.COMMON }
    end

    function self.pick_rarity_band_for_cycle(current_cycle, allowed_bands, force_highest_rarity)
        local resolved_allowed_bands = allowed_bands or self.get_allowed_rarity_bands_for_cycle(current_cycle)
        local highest_rarity = rarity_keys.COMMON

        for index = #rarity_order, 1, -1 do
            if contains_value(resolved_allowed_bands, rarity_order[index]) then
                highest_rarity = rarity_order[index]
                break
            end
        end

        if force_highest_rarity then
            log(
                "pick_rarity_band_for_cycle forced the highest allowed rarity. current_cycle=["
                    .. tostring(current_cycle)
                    .. "], allowed_bands=["
                    .. table.concat(resolved_allowed_bands, ",")
                    .. "], selected_rarity=["
                    .. tostring(highest_rarity)
                    .. "]."
            )
            return highest_rarity
        end

        local rarity = resolved_allowed_bands[cm:random_number(#resolved_allowed_bands, 1)] or highest_rarity

        log(
            "pick_rarity_band_for_cycle resolved rarity=["
                .. tostring(rarity)
                .. "] from current_cycle=["
                .. tostring(current_cycle)
                .. "], allowed_bands=["
                .. table.concat(resolved_allowed_bands, ",")
                .. "], selection_mode=[uniform_allowed_bands], force_highest_rarity=["
                .. tostring(force_highest_rarity)
                .. "]."
        )
        return rarity
    end

    local function rarity_band_allowed(item_rarity, allowed_bands)
        if not allowed_bands then
            return true
        end

        for _, rarity in ipairs(allowed_bands) do
            if item_rarity == rarity then
                return true
            end
        end

        return false
    end

    function self.build_weighted_pool_for_slot(slot_key, battle_tier, allowed_bands, player_faction_key, current_node_faction_key)
        local weighted_pool = {}
        local source_counts = {}
        local pool_sources = self.get_reward_pool_sources(player_faction_key, current_node_faction_key)

        for _, source in ipairs(pool_sources) do
            local source_count = 0
            for _, entry in ipairs(source.entries) do
                if entry.enabled
                    and entry.reward_slot == slot_key
                    and rarity_band_allowed(entry.item_rarity, allowed_bands) then
                    for _ = 1, entry.weight do
                        local weighted_entry = {}
                        for key, value in pairs(entry) do
                            weighted_entry[key] = value
                        end
                        weighted_entry.source_scope = source.scope
                        weighted_entry.source_faction_key = source.faction_key
                        weighted_pool[#weighted_pool + 1] = weighted_entry
                        source_count = source_count + 1
                    end
                end
            end

            source_counts[#source_counts + 1] =
                tostring(source.scope) .. ":" .. tostring(source.faction_key) .. "=" .. tostring(source_count)
        end

        log(
            "build_weighted_pool_for_slot completed. slot=["
                .. tostring(slot_key)
                .. "], battle_tier=["
                .. tostring(battle_tier)
                .. "], tier_filter_applied=[false], allowed_bands=["
                .. tostring(allowed_bands and table.concat(allowed_bands, ",") or "all")
                .. "], weighted_pool_size=["
                .. tostring(#weighted_pool)
                .. "], player_faction_key=["
                .. tostring(player_faction_key)
                .. "], current_node_faction_key=["
                .. tostring(current_node_faction_key)
                .. "], source_counts=["
                .. table.concat(source_counts, ";")
                .. "]."
        )
        return weighted_pool
    end

    function self.generate_equipment_reward_payload(completed_battle_count, battle_tier, player_faction_key, current_node_faction_key, generation_context)
        local reward_context = generation_context or {}
        local current_cycle = math.max(1, math.floor(tonumber(reward_context.current_cycle) or 1))
        local elite_battle = reward_context.elite_battle == true or reward_context.elite_battle == "true"
        local force_highest_rarity = reward_context.force_highest_rarity == true
        if not force_highest_rarity and elite_battle and elite_reward_highest_tier then
            force_highest_rarity = true
        end

        local cycle_allowed_bands = self.get_allowed_rarity_bands_for_cycle(current_cycle)
        local selected_rarity_band = self.pick_rarity_band_for_cycle(current_cycle, cycle_allowed_bands, force_highest_rarity)
        local generation_seed = cm:random_number(99999, 1)
        local generation_attempts = 0
        local fallback_steps = {}
        local payload = {
            selected_rarity_band = selected_rarity_band,
            candidate_generation_seed = generation_seed,
            candidate_generation_attempts = 0,
            fallback_strategy_used = "none",
            equipment_reward_completed_battle_count = completed_battle_count,
            equipment_reward_battle_tier = battle_tier,
            equipment_reward_current_cycle = current_cycle,
            equipment_reward_player_faction_key = player_faction_key or "",
            equipment_reward_node_faction_key = current_node_faction_key or "",
            cycle_allowed_rarity_bands = table.concat(cycle_allowed_bands, ","),
            equipment_reward_elite_battle = elite_battle and "true" or "false",
            candidate_count = 0
        }

        log(
            "generate_equipment_reward_payload started. completed_battle_count=["
                .. tostring(completed_battle_count)
                .. "], battle_tier=["
                .. tostring(battle_tier)
                .. "], current_cycle=["
                .. tostring(current_cycle)
                .. "], selected_rarity_band=["
                .. tostring(selected_rarity_band)
                .. "], cycle_allowed_rarity_bands=["
                .. table.concat(cycle_allowed_bands, ",")
                .. "], elite_battle=["
                .. tostring(elite_battle)
                .. "], force_highest_rarity=["
                .. tostring(force_highest_rarity)
                .. "], generation_seed=["
                .. tostring(generation_seed)
                .. "], player_faction_key=["
                .. tostring(player_faction_key)
                .. "], current_node_faction_key=["
                .. tostring(current_node_faction_key)
                .. "]."
        )

        -- Dilemma buttons are static, so each choice is bound to a fixed slot category and
        -- the exact ancillary key is carried in the saved payload for grant/resume correctness.
        for choice_index, slot_key in ipairs(slot_order) do
            local zero_based_choice = choice_index - 1
            local weighted_pool = self.build_weighted_pool_for_slot(
                slot_key,
                battle_tier,
                { selected_rarity_band },
                player_faction_key,
                current_node_faction_key
            )

            if #weighted_pool == 0 then
                fallback_steps[#fallback_steps + 1] = tostring(slot_key) .. ":expand_to_cycle_allowed_rarities"
                weighted_pool = self.build_weighted_pool_for_slot(
                    slot_key,
                    battle_tier,
                    cycle_allowed_bands,
                    player_faction_key,
                    current_node_faction_key
                )
            end

            if #weighted_pool == 0 then
                fallback_steps[#fallback_steps + 1] = tostring(slot_key) .. ":expand_to_any_tier_item"
                weighted_pool = self.build_weighted_pool_for_slot(
                    slot_key,
                    battle_tier,
                    nil,
                    player_faction_key,
                    current_node_faction_key
                )
            end

            if #weighted_pool == 0 then
                log("generate_equipment_reward_payload could not produce a candidate for slot [" .. tostring(slot_key) .. "].")
            else
                generation_attempts = generation_attempts + 1
                local selected_entry = weighted_pool[cm:random_number(#weighted_pool, 1)]
                payload["ancillary_" .. tostring(zero_based_choice)] = selected_entry.item_key
                payload["category_" .. tostring(zero_based_choice)] = selected_entry.item_category
                payload["rarity_" .. tostring(zero_based_choice)] = selected_entry.item_rarity
                payload["slot_" .. tostring(zero_based_choice)] = selected_entry.reward_slot
                payload["source_scope_" .. tostring(zero_based_choice)] = selected_entry.source_scope or "unknown"
                payload["source_faction_" .. tostring(zero_based_choice)] = selected_entry.source_faction_key or "unknown"
                payload.candidate_count = payload.candidate_count + 1

                log(
                    "generate_equipment_reward_payload selected ancillary for choice=["
                        .. tostring(zero_based_choice)
                        .. "], slot=["
                        .. tostring(slot_key)
                        .. "], item_key=["
                        .. tostring(selected_entry.item_key)
                        .. "], category=["
                        .. tostring(selected_entry.item_category)
                        .. "], rarity=["
                        .. tostring(selected_entry.item_rarity)
                        .. "], source_scope=["
                        .. tostring(selected_entry.source_scope)
                        .. "], source_faction_key=["
                        .. tostring(selected_entry.source_faction_key)
                        .. "]."
                )
            end
        end

        payload.candidate_generation_attempts = generation_attempts
        if #fallback_steps > 0 then
            payload.fallback_strategy_used = table.concat(fallback_steps, ",")
        end

        log(
            "generate_equipment_reward_payload completed. candidate_count=["
                .. tostring(payload.candidate_count)
                .. "], candidate_generation_attempts=["
                .. tostring(payload.candidate_generation_attempts)
                .. "], fallback_strategy_used=["
                .. tostring(payload.fallback_strategy_used)
                .. "]."
        )
        return payload
    end

    return self
end

return ancillary_generator
