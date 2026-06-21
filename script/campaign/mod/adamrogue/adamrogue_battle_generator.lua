local battle_generator = {}

function battle_generator.new(context)
    local self = {}
    local log = context.log
    local cm = context.cm
    local split_string = context.split_string
    local default_unit_pool = context.default_unit_pool or {}
    local unit_pools_by_faction = context.unit_pools_by_faction or {}
    local battle_tier_keys = context.battle_tier
    local enemy_general_subtype = context.enemy_general_subtype
    local enemy_general_subtypes_by_faction = context.enemy_general_subtypes_by_faction or {}
    local enemy_embedded_agent_subtype = context.enemy_embedded_agent_subtype
    local enemy_embedded_agent_subtypes_by_faction = context.enemy_embedded_agent_subtypes_by_faction or {}
    local default_enemy_faction_key = context.default_enemy_faction_key
    local enemy_unit_count_config = context.enemy_unit_count_config or {}

    function self.get_unit_pool_for_faction(content_faction_key)
        local faction_key = content_faction_key or ""
        local selected_pool = unit_pools_by_faction[faction_key]
        if selected_pool and #selected_pool > 0 then
            log(
                "get_unit_pool_for_faction resolved faction-specific pool. content_faction_key=["
                    .. tostring(faction_key)
                    .. "], pool_size=["
                    .. tostring(#selected_pool)
                    .. "]."
            )
            return selected_pool, faction_key, false
        end

        log(
            "[ERROR] get_unit_pool_for_faction is falling back to the default pool. requested_content_faction_key=["
                .. tostring(faction_key)
                .. "], default_pool_size=["
                .. tostring(#default_unit_pool)
                .. "]."
        )
        return default_unit_pool, context.default_content_faction_key or "default", true
    end

    function self.get_battle_tier_for_progress(completed_battle_count)
        log("get_battle_tier_for_progress called. completed_battle_count=[" .. tostring(completed_battle_count) .. "]")
        if completed_battle_count >= 6 then
            log("get_battle_tier_for_progress resolved tier=[LATE]")
            return battle_tier_keys.LATE
        elseif completed_battle_count >= 3 then
            log("get_battle_tier_for_progress resolved tier=[MID]")
            return battle_tier_keys.MID
        end

        log("get_battle_tier_for_progress resolved tier=[EARLY]")
        return battle_tier_keys.EARLY
    end

    function self.get_target_battle_budget(completed_battle_count)
        local budget = 2600 + (completed_battle_count * 450)
        log("get_target_battle_budget resolved budget=[" .. tostring(budget) .. "] from completed_battle_count=[" .. tostring(completed_battle_count) .. "]")
        return budget
    end

    function self.get_battle_unit_pool_entry(unit_key)
        for _, pool in pairs(unit_pools_by_faction) do
            for _, unit_entry in ipairs(pool) do
                if unit_entry.unit_key == unit_key then
                    return unit_entry
                end
            end
        end

        for _, unit_entry in ipairs(default_unit_pool) do
            if unit_entry.unit_key == unit_key then
                return unit_entry
            end
        end

        return nil
    end

    function self.build_weighted_unit_pool_for_tier(battle_tier, content_faction_key)
        local pool = {}
        local source_pool, resolved_content_faction_key, used_fallback = self.get_unit_pool_for_faction(content_faction_key)
        log(
            "build_weighted_unit_pool_for_tier called. battle_tier=["
                .. tostring(battle_tier)
                .. "], requested_content_faction_key=["
                .. tostring(content_faction_key)
                .. "], resolved_content_faction_key=["
                .. tostring(resolved_content_faction_key)
                .. "], used_fallback=["
                .. tostring(used_fallback)
                .. "]."
        )

        for _, unit_entry in ipairs(source_pool) do
            if battle_tier >= unit_entry.min_battle_tier and battle_tier <= unit_entry.max_battle_tier then
                for _ = 1, unit_entry.weight do
                    pool[#pool + 1] = unit_entry
                end
            end
        end

        log(
            "build_weighted_unit_pool_for_tier completed. weighted_pool_size=["
                .. tostring(#pool)
                .. "], resolved_content_faction_key=["
                .. tostring(resolved_content_faction_key)
                .. "]."
        )
        return pool, resolved_content_faction_key, used_fallback
    end

    function self.pick_enemy_general_subtype_for_tier(battle_tier, content_faction_key)
        local resolved_subtype = enemy_general_subtypes_by_faction[content_faction_key] or enemy_general_subtype
        log(
            "pick_enemy_general_subtype_for_tier called. battle_tier=["
                .. tostring(battle_tier)
                .. "], content_faction_key=["
                .. tostring(content_faction_key)
                .. "], resolved_subtype=["
                .. tostring(resolved_subtype)
                .. "]."
        )
        if battle_tier >= battle_tier_keys.LATE then
            if content_faction_key == "wh3_main_cth_the_northern_provinces" then
                log("pick_enemy_general_subtype_for_tier resolved Cathay late-tier subtype=[wh3_main_cth_dragon_blooded_shugengan_yin]")
                return "wh3_main_cth_dragon_blooded_shugengan_yin"
            end
        end

        log("pick_enemy_general_subtype_for_tier resolved subtype=[" .. tostring(resolved_subtype) .. "]")
        return resolved_subtype
    end

    function self.pick_enemy_agent_subtype_for_tier(battle_tier, allow_embedded_agent, content_faction_key)
        local resolved_subtype = enemy_embedded_agent_subtypes_by_faction[content_faction_key]
            or enemy_embedded_agent_subtype
        log(
            "pick_enemy_agent_subtype_for_tier called. battle_tier=["
                .. tostring(battle_tier)
                .. "], allow_embedded_agent=["
                .. tostring(allow_embedded_agent)
                .. "], content_faction_key=["
                .. tostring(content_faction_key)
                .. "], resolved_subtype=["
                .. tostring(resolved_subtype)
                .. "]"
        )
        if not allow_embedded_agent then
            log("pick_enemy_agent_subtype_for_tier resolved subtype=[] because embedded agents are disabled.")
            return ""
        end

        if battle_tier >= battle_tier_keys.MID and resolved_subtype and resolved_subtype ~= "" then
            log("pick_enemy_agent_subtype_for_tier resolved subtype=[" .. tostring(resolved_subtype) .. "]")
            return resolved_subtype
        end

        log("pick_enemy_agent_subtype_for_tier resolved subtype=[] because battle tier is below MID or the faction has no supported embedded agent.")
        return ""
    end

    function self.get_enemy_unit_count_targets(current_cycle)
        local normalized_cycle = math.max(1, math.floor(tonumber(current_cycle) or 1))
        local minimum_units_base = tonumber(enemy_unit_count_config.minimum_units_base) or 2
        local minimum_units_per_cycle = tonumber(enemy_unit_count_config.minimum_units_per_cycle) or 1
        local hard_cap = math.max(1, math.floor(tonumber(enemy_unit_count_config.hard_cap) or 20))
        local minimum_units_from_cycle_11 = tonumber(enemy_unit_count_config.minimum_units_from_cycle_11) or 12
        local full_stack_from_cycle_19 = enemy_unit_count_config.full_stack_from_cycle_19 == true

        local min_units = minimum_units_base + (minimum_units_per_cycle * normalized_cycle)
        if normalized_cycle >= 11 then
            min_units = math.max(min_units, minimum_units_from_cycle_11)
        end

        min_units = math.min(hard_cap, math.max(1, math.floor(min_units)))
        local target_units = min_units
        if full_stack_from_cycle_19 and normalized_cycle >= 19 then
            target_units = hard_cap
        end

        return {
            current_cycle = normalized_cycle,
            min_units = min_units,
            target_units = math.min(hard_cap, math.max(min_units, target_units)),
            hard_cap = hard_cap
        }
    end

    function self.build_budget_enemy_force_definition(target_value_budget, battle_tier, allow_embedded_agent, content_faction_key, generation_context)
        local build_context = generation_context or {}
        local unit_count_targets = self.get_enemy_unit_count_targets(build_context.current_cycle)
        log(
            "build_budget_enemy_force_definition called. budget=["
                .. tostring(target_value_budget)
                .. "], tier=["
                .. tostring(battle_tier)
                .. "], allow_embedded_agent=["
                .. tostring(allow_embedded_agent)
                .. "], content_faction_key=["
                .. tostring(content_faction_key)
                .. "], current_cycle=["
                .. tostring(unit_count_targets.current_cycle)
                .. "], min_units=["
                .. tostring(unit_count_targets.min_units)
                .. "], target_units=["
                .. tostring(unit_count_targets.target_units)
                .. "], hard_cap=["
                .. tostring(unit_count_targets.hard_cap)
                .. "]"
        )
        local weighted_pool, resolved_content_faction_key, used_pool_fallback = self.build_weighted_unit_pool_for_tier(
            battle_tier,
            content_faction_key
        )
        if #weighted_pool == 0 then
            log("build_budget_enemy_force_definition aborted because the weighted pool is empty.")
            return nil
        end

        local chosen_units = {}
        local chosen_unit_counts = {}
        local total_value = 0
        local max_units = unit_count_targets.hard_cap
        local attempts = 0
        local preferred_budget_floor = math.floor(target_value_budget * 0.9)
        local fallback_budget_floor = math.floor(target_value_budget * 0.85)
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

        while attempts < 400 and #chosen_units < max_units do
            attempts = attempts + 1

            local unit_entry = weighted_pool[cm:random_number(#weighted_pool, 1)]
            local current_count = chosen_unit_counts[unit_entry.unit_key] or 0
            local projected_total = total_value + unit_entry.unit_value
            local should_take = false

            if projected_total <= target_value_budget then
                if #chosen_units < unit_count_targets.min_units then
                    should_take = true
                elseif total_value < preferred_budget_floor then
                    should_take = true
                elseif #chosen_units < unit_count_targets.target_units then
                    should_take = true
                elseif (target_value_budget - total_value) >= math.min(350, unit_entry.unit_value) then
                    should_take = true
                end
            end

            if should_take then
                chosen_units[#chosen_units + 1] = unit_entry.unit_key
                chosen_unit_counts[unit_entry.unit_key] = current_count + 1
                total_value = projected_total
                log(
                    "build_budget_enemy_force_definition accepted unit_key=["
                        .. tostring(unit_entry.unit_key)
                        .. "], total_value=["
                        .. tostring(total_value)
                        .. "], chosen_count=["
                        .. tostring(#chosen_units)
                        .. "]."
                )
            end

            if total_value >= preferred_budget_floor and #chosen_units >= unit_count_targets.target_units then
                log("build_budget_enemy_force_definition reached stop threshold and will exit the selection loop.")
                break
            end
        end

        -- If the weighted random pass undershoots the target stack shape, pad with the cheapest
        -- legal units that still fit in budget before giving up on the quantity curve.
        local fill_attempts = 0
        while #chosen_units < max_units and fill_attempts < max_units do
            fill_attempts = fill_attempts + 1
            local should_continue_fill = #chosen_units < unit_count_targets.min_units
                or (#chosen_units < unit_count_targets.target_units and total_value < target_value_budget)
                or total_value < fallback_budget_floor

            if not should_continue_fill then
                break
            end

            local selected_filler = nil
            for _, unit_entry in ipairs(unique_pool) do
                local projected_total = total_value + unit_entry.unit_value
                if projected_total <= target_value_budget then
                    selected_filler = unit_entry
                    break
                end
            end

            if not selected_filler then
                log("build_budget_enemy_force_definition could not find a legal low-cost filler unit within the remaining budget.")
                break
            end

            chosen_units[#chosen_units + 1] = selected_filler.unit_key
            chosen_unit_counts[selected_filler.unit_key] = (chosen_unit_counts[selected_filler.unit_key] or 0) + 1
            total_value = total_value + selected_filler.unit_value
            log(
                "build_budget_enemy_force_definition applied low-cost filler. unit_key=["
                    .. tostring(selected_filler.unit_key)
                    .. "], total_value=["
                    .. tostring(total_value)
                    .. "], chosen_count=["
                    .. tostring(#chosen_units)
                    .. "]."
            )
        end

        if #chosen_units == 0 then
            log("build_budget_enemy_force_definition failed because no units were chosen.")
            return nil
        end

        log(
            "build_budget_enemy_force_definition completed. total_value=["
                .. tostring(total_value)
                .. "], unit_count=["
                .. tostring(#chosen_units)
                .. "], min_units=["
                .. tostring(unit_count_targets.min_units)
                .. "], target_units=["
                .. tostring(unit_count_targets.target_units)
                .. "], attempts=["
                .. tostring(attempts)
                .. "]."
        )
        return {
            template_type = "generated_by_budget",
            battle_force_source = "budget_generator_v1",
            lord_subtype = self.pick_enemy_general_subtype_for_tier(battle_tier, resolved_content_faction_key),
            unit_list = chosen_units,
            embedded_agent_subtype = self.pick_enemy_agent_subtype_for_tier(
                battle_tier,
                allow_embedded_agent,
                resolved_content_faction_key
            ),
            generated_total_value = total_value,
            budget_delta = total_value - target_value_budget,
            content_faction_key = resolved_content_faction_key,
            used_pool_fallback = used_pool_fallback and "true" or "false",
            generated_unit_count = #chosen_units,
            min_unit_target = unit_count_targets.min_units,
            desired_unit_target = unit_count_targets.target_units
        }
    end

    function self.create_battle_payload_from_definition(battle_definition, target_value_budget, battle_tier, spawn_retry_index, enemy_faction_key)
        local payload = {
            battle_template_key = battle_definition.template_type,
            battle_force_source = battle_definition.battle_force_source,
            battle_content_faction_key = battle_definition.content_faction_key or context.default_content_faction_key or "",
            battle_content_pool_fallback = battle_definition.used_pool_fallback or "false",
            target_value_budget = target_value_budget,
            battle_budget_tier = battle_tier,
            enemy_faction_key = enemy_faction_key or default_enemy_faction_key,
            enemy_general_subtype = battle_definition.lord_subtype,
            enemy_unit_list = table.concat(battle_definition.unit_list, ","),
            enemy_agent_subtype = battle_definition.embedded_agent_subtype,
            generated_total_value = battle_definition.generated_total_value,
            budget_delta = battle_definition.budget_delta,
            generated_unit_count = battle_definition.generated_unit_count or 0,
            min_unit_target = battle_definition.min_unit_target or 0,
            desired_unit_target = battle_definition.desired_unit_target or 0,
            spawn_retry_index = spawn_retry_index or 0,
            attack_choice = 0,
            pause_choice = 1
        }

        log(
            "create_battle_payload_from_definition completed. target_value_budget=["
                .. tostring(target_value_budget)
                .. "], battle_tier=["
                .. tostring(battle_tier)
                .. "], spawn_retry_index=["
                .. tostring(payload.spawn_retry_index)
                .. "], enemy_unit_list=["
                .. tostring(payload.enemy_unit_list)
                .. "]."
        )
        return payload
    end

    function self.log_unit_list_details(context_label, serialized_unit_list)
        local units = split_string(serialized_unit_list, ",")
        if #units == 0 then
            return
        end

        local summary_entries = {}
        for index, unit_key in ipairs(units) do
            local unit_entry = self.get_battle_unit_pool_entry(unit_key)
            if unit_entry then
                summary_entries[#summary_entries + 1] =
                    tostring(index) .. ":" .. tostring(unit_key) .. "(" .. tostring(unit_entry.role_tag) .. "," .. tostring(unit_entry.unit_value) .. ")"
            else
                summary_entries[#summary_entries + 1] = tostring(index) .. ":" .. tostring(unit_key) .. "(unknown)"
            end
        end

        log("log_unit_list_details context=[" .. tostring(context_label) .. "], units=[" .. table.concat(summary_entries, ";") .. "].")
    end

    return self
end

return battle_generator
