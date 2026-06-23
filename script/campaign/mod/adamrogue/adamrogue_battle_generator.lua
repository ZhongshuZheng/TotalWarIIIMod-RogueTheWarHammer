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
    local enemy_general_options_by_faction = context.enemy_general_options_by_faction or {}
    local enemy_general_unit_values_by_faction = context.enemy_general_unit_values_by_faction or {}
    local enemy_embedded_agent_subtype = context.enemy_embedded_agent_subtype
    local enemy_embedded_agent_subtypes_by_faction = context.enemy_embedded_agent_subtypes_by_faction or {}
    local default_enemy_faction_key = context.default_enemy_faction_key
    local enemy_unit_count_config = context.enemy_unit_count_config or {}
    local enemy_hero_pools_by_faction = context.enemy_hero_pools_by_faction or {}
    local enemy_growth_config = context.enemy_growth_config or {}

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

    function self.get_enemy_general_options_for_faction(content_faction_key)
        local options = enemy_general_options_by_faction[content_faction_key]
        if options and #options > 0 then
            return options, content_faction_key
        end

        local fallback_options = enemy_general_options_by_faction[context.default_content_faction_key]
        if fallback_options and #fallback_options > 0 then
            log(
                "[ERROR] get_enemy_general_options_for_faction is falling back to the default content faction options. requested_content_faction_key=["
                    .. tostring(content_faction_key)
                    .. "], resolved_content_faction_key=["
                    .. tostring(context.default_content_faction_key)
                    .. "], option_count=["
                    .. tostring(#fallback_options)
                    .. "]."
            )
            return fallback_options, context.default_content_faction_key
        end

        local resolved_subtype = enemy_general_subtypes_by_faction[content_faction_key] or enemy_general_subtype
        return {
            {
                agent_subtype = resolved_subtype,
                unit_key = resolved_subtype,
                unit_value = tonumber(enemy_general_unit_values_by_faction[content_faction_key]) or 0,
            }
        }, content_faction_key
    end

    function self.pick_enemy_general_option_for_tier(battle_tier, content_faction_key)
        local general_options, resolved_content_faction_key = self.get_enemy_general_options_for_faction(content_faction_key)
        local resolved_option = general_options[cm:random_number(#general_options, 1)]
        log(
            "pick_enemy_general_option_for_tier called. battle_tier=["
                .. tostring(battle_tier)
                .. "], content_faction_key=["
                .. tostring(content_faction_key)
                .. "], resolved_content_faction_key=["
                .. tostring(resolved_content_faction_key)
                .. "], option_count=["
                .. tostring(#general_options)
                .. "], selected_agent_subtype=["
                .. tostring(resolved_option and resolved_option.agent_subtype or "")
                .. "], selected_unit_key=["
                .. tostring(resolved_option and resolved_option.unit_key or "")
                .. "], selected_unit_value=["
                .. tostring(resolved_option and resolved_option.unit_value or 0)
                .. "]."
        )
        return resolved_option, resolved_content_faction_key
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

    function self.get_hero_num_for_cycle(current_cycle)
        local normalized_cycle = math.max(1, math.floor(tonumber(current_cycle) or 1))
        for _, entry in ipairs(enemy_growth_config) do
            local min_c = tonumber(entry.min_cycle) or 1
            local max_c = entry.max_cycle and tonumber(entry.max_cycle) or math.huge
            if normalized_cycle >= min_c and normalized_cycle <= max_c then
                return math.max(0, math.floor(tonumber(entry.hero_num) or 0))
            end
        end
        return 0
    end

    function self.pick_heroes_for_faction(content_faction_key, hero_num)
        if not hero_num or hero_num <= 0 then
            return {}, 0
        end
        local pool = enemy_hero_pools_by_faction[content_faction_key]
        if not pool or #pool == 0 then
            log(
                "pick_heroes_for_faction: no hero pool found for content_faction_key=["
                    .. tostring(content_faction_key)
                    .. "]. Returning empty hero list."
            )
            return {}, 0
        end

        local weighted_pool = {}
        for _, hero_entry in ipairs(pool) do
            for _ = 1, (tonumber(hero_entry.weight) or 1) do
                weighted_pool[#weighted_pool + 1] = hero_entry
            end
        end

        local selected_heroes = {}
        local total_hero_value = 0
        for _ = 1, hero_num do
            local picked = weighted_pool[cm:random_number(#weighted_pool, 1)]
            if picked then
                selected_heroes[#selected_heroes + 1] = {
                    agent_type = picked.agent_type,
                    agent_subtype = picked.agent_subtype,
                    unit_key = picked.unit_key,
                    unit_value = tonumber(picked.unit_value) or 0,
                }
                total_hero_value = total_hero_value + (tonumber(picked.unit_value) or 0)
                log(
                    "pick_heroes_for_faction picked hero. agent_subtype=["
                        .. tostring(picked.agent_subtype)
                        .. "], unit_value=["
                        .. tostring(picked.unit_value)
                        .. "]."
                )
            end
        end

        log(
            "pick_heroes_for_faction completed. content_faction_key=["
                .. tostring(content_faction_key)
                .. "], hero_num=["
                .. tostring(hero_num)
                .. "], selected=["
                .. tostring(#selected_heroes)
                .. "], total_hero_value=["
                .. tostring(total_hero_value)
                .. "]."
        )
        return selected_heroes, total_hero_value
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

        local selected_general_option, resolved_general_content_faction_key = self.pick_enemy_general_option_for_tier(
            battle_tier,
            resolved_content_faction_key
        )
        local enemy_general_unit_value = math.max(
            0,
            math.floor(tonumber(selected_general_option and selected_general_option.unit_value) or 0)
        )

        -- Pick heroes based on the current cycle's hero_num setting.
        local current_cycle_for_heroes = (build_context and build_context.current_cycle) or 1
        local hero_num = self.get_hero_num_for_cycle(current_cycle_for_heroes)
        local slots_for_troops = math.max(0, unit_count_targets.hard_cap - 1 - hero_num)
        local effective_hard_cap = unit_count_targets.hard_cap - 1 - hero_num

        local selected_heroes, total_hero_value = self.pick_heroes_for_faction(
            resolved_content_faction_key,
            hero_num
        )

        local unit_only_target_value_budget = math.max(
            0,
            (tonumber(target_value_budget) or 0) - enemy_general_unit_value - total_hero_value
        )
        log(
            "build_budget_enemy_force_definition resolved enemy general and hero budget deductions. total_budget=["
                .. tostring(target_value_budget)
                .. "], selected_general_agent_subtype=["
                .. tostring(selected_general_option and selected_general_option.agent_subtype or "")
                .. "], enemy_general_unit_value=["
                .. tostring(enemy_general_unit_value)
                .. "], hero_num=["
                .. tostring(hero_num)
                .. "], total_hero_value=["
                .. tostring(total_hero_value)
                .. "], unit_only_target_value_budget=["
                .. tostring(unit_only_target_value_budget)
                .. "], slots_for_troops=["
                .. tostring(slots_for_troops)
                .. "]."
        )

        local chosen_units = {}
        local chosen_unit_counts = {}
        local total_value = 0
        local max_units = math.max(0, effective_hard_cap)
        local attempts = 0
        local preferred_budget_floor = math.floor(unit_only_target_value_budget * 0.9)
        local fallback_budget_floor = math.floor(unit_only_target_value_budget * 0.85)
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
        local unit_entry_by_key = {}
        for _, unit_entry in ipairs(unique_pool) do
            unit_entry_by_key[unit_entry.unit_key] = unit_entry
        end

        while attempts < 400 and #chosen_units < max_units do
            attempts = attempts + 1

            local unit_entry = weighted_pool[cm:random_number(#weighted_pool, 1)]
            local current_count = chosen_unit_counts[unit_entry.unit_key] or 0
            local projected_total = total_value + unit_entry.unit_value
            local should_take = false

            if projected_total <= unit_only_target_value_budget then
                if #chosen_units < unit_count_targets.min_units then
                    should_take = true
                elseif total_value < preferred_budget_floor then
                    should_take = true
                elseif #chosen_units < unit_count_targets.target_units then
                    should_take = true
                elseif (unit_only_target_value_budget - total_value) >= math.min(350, unit_entry.unit_value) then
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
                or (#chosen_units < unit_count_targets.target_units and total_value < unit_only_target_value_budget)
                or total_value < fallback_budget_floor

            if not should_continue_fill then
                break
            end

            local selected_filler = nil
            for _, unit_entry in ipairs(unique_pool) do
                local projected_total = total_value + unit_entry.unit_value
                if projected_total <= unit_only_target_value_budget then
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

        if total_value < preferred_budget_floor and #chosen_units > 0 then
            local upgrade_pass = 0
            while total_value < preferred_budget_floor do
                upgrade_pass = upgrade_pass + 1
                local upgraded_this_pass = false
                local upgrade_indexes = {}

                for index, unit_key in ipairs(chosen_units) do
                    local unit_entry = unit_entry_by_key[unit_key]
                    if unit_entry then
                        upgrade_indexes[#upgrade_indexes + 1] = {
                            index = index,
                            unit_key = unit_key,
                            unit_value = tonumber(unit_entry.unit_value) or 0,
                            weight = tonumber(unit_entry.weight) or 0
                        }
                    end
                end

                table.sort(upgrade_indexes, function(a, b)
                    if a.weight == b.weight then
                        if a.unit_value == b.unit_value then
                            return a.index < b.index
                        end
                        return a.unit_value < b.unit_value
                    end
                    return a.weight > b.weight
                end)

                for _, upgrade_target in ipairs(upgrade_indexes) do
                    if total_value >= preferred_budget_floor then
                        break
                    end

                    local current_entry = unit_entry_by_key[upgrade_target.unit_key]
                    if current_entry then
                        local current_value = tonumber(current_entry.unit_value) or 0
                        local current_weight = tonumber(current_entry.weight) or 0
                        local remaining_headroom = unit_only_target_value_budget - total_value
                        local upgrade_candidates = {}

                        if remaining_headroom > 0 then
                            for _, candidate_entry in ipairs(unique_pool) do
                                local candidate_value = tonumber(candidate_entry.unit_value) or 0
                                local candidate_weight = tonumber(candidate_entry.weight) or 0
                                local upgrade_delta = candidate_value - current_value

                                if upgrade_delta > 0
                                    and upgrade_delta <= remaining_headroom
                                    and (candidate_weight < current_weight or candidate_value > current_value) then
                                    upgrade_candidates[#upgrade_candidates + 1] = candidate_entry
                                end
                            end
                        end

                        if #upgrade_candidates > 0 then
                            local selected_upgrade = upgrade_candidates[cm:random_number(#upgrade_candidates, 1)]
                            local selected_upgrade_value = tonumber(selected_upgrade.unit_value) or 0
                            total_value = total_value - current_value + selected_upgrade_value
                            chosen_units[upgrade_target.index] = selected_upgrade.unit_key
                            chosen_unit_counts[upgrade_target.unit_key] = math.max(
                                0,
                                (chosen_unit_counts[upgrade_target.unit_key] or 1) - 1
                            )
                            chosen_unit_counts[selected_upgrade.unit_key] = (chosen_unit_counts[selected_upgrade.unit_key] or 0) + 1
                            upgraded_this_pass = true
                            log(
                                "build_budget_enemy_force_definition upgraded a low-tier unit to improve budget utilization. pass=["
                                    .. tostring(upgrade_pass)
                                    .. "], replaced_unit_key=["
                                    .. tostring(upgrade_target.unit_key)
                                    .. "], replaced_unit_value=["
                                    .. tostring(current_value)
                                    .. "], replaced_unit_weight=["
                                    .. tostring(current_weight)
                                    .. "], upgraded_unit_key=["
                                    .. tostring(selected_upgrade.unit_key)
                                    .. "], upgraded_unit_value=["
                                    .. tostring(selected_upgrade_value)
                                    .. "], upgraded_unit_weight=["
                                    .. tostring(selected_upgrade.weight)
                                    .. "], total_value=["
                                    .. tostring(total_value)
                                    .. "], preferred_budget_floor=["
                                    .. tostring(preferred_budget_floor)
                                    .. "]."
                            )
                            break
                        end
                    end
                end

                if not upgraded_this_pass then
                    log(
                        "build_budget_enemy_force_definition could not find any further legal unit upgrades and will stop upgrade iteration. pass=["
                            .. tostring(upgrade_pass)
                            .. "], total_value=["
                            .. tostring(total_value)
                            .. "], preferred_budget_floor=["
                            .. tostring(preferred_budget_floor)
                            .. "]."
                    )
                    break
                end
            end
        end

        if #chosen_units == 0 then
            log("build_budget_enemy_force_definition failed because no units were chosen.")
            return nil
        end

        log(
            "build_budget_enemy_force_definition completed. total_value=["
                .. tostring(total_value)
                .. "], enemy_general_unit_value=["
                .. tostring(enemy_general_unit_value)
                .. "], total_hero_value=["
                .. tostring(total_hero_value)
                .. "], combined_total_value=["
                .. tostring(total_value + enemy_general_unit_value + total_hero_value)
                .. "], unit_count=["
                .. tostring(#chosen_units)
                .. "], hero_count=["
                .. tostring(#selected_heroes)
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
            lord_subtype = selected_general_option and selected_general_option.agent_subtype or enemy_general_subtype,
            lord_unit_key = selected_general_option and selected_general_option.unit_key or "",
            unit_list = chosen_units,
            hero_list = selected_heroes,
            embedded_agent_subtype = self.pick_enemy_agent_subtype_for_tier(
                battle_tier,
                allow_embedded_agent,
                resolved_content_faction_key
            ),
            enemy_general_unit_value = enemy_general_unit_value,
            total_hero_value = total_hero_value,
            generated_total_value = total_value,
            budget_delta = (total_value + enemy_general_unit_value + total_hero_value) - target_value_budget,
            content_faction_key = resolved_general_content_faction_key or resolved_content_faction_key,
            used_pool_fallback = used_pool_fallback and "true" or "false",
            generated_unit_count = #chosen_units,
            generated_hero_count = #selected_heroes,
            min_unit_target = unit_count_targets.min_units,
            desired_unit_target = unit_count_targets.target_units
        }
    end

    function self.create_battle_payload_from_definition(battle_definition, target_value_budget, battle_tier, spawn_retry_index, enemy_faction_key)
        -- Serialize the hero list as a pipe-delimited string: "agent_type:agent_subtype:unit_key"
        local hero_list_parts = {}
        local hero_list_raw = battle_definition.hero_list or {}
        for _, hero in ipairs(hero_list_raw) do
            hero_list_parts[#hero_list_parts + 1] = tostring(hero.agent_type)
                .. ":" .. tostring(hero.agent_subtype)
                .. ":" .. tostring(hero.unit_key)
        end
        local serialized_hero_list = table.concat(hero_list_parts, "|")

        local payload = {
            battle_template_key = battle_definition.template_type,
            battle_force_source = battle_definition.battle_force_source,
            battle_content_faction_key = battle_definition.content_faction_key or context.default_content_faction_key or "",
            battle_content_pool_fallback = battle_definition.used_pool_fallback or "false",
            target_value_budget = target_value_budget,
            battle_budget_tier = battle_tier,
            enemy_faction_key = enemy_faction_key or default_enemy_faction_key,
            enemy_general_subtype = battle_definition.lord_subtype,
            enemy_general_unit_key = battle_definition.lord_unit_key or "",
            enemy_general_unit_value = battle_definition.enemy_general_unit_value or 0,
            enemy_unit_list = table.concat(battle_definition.unit_list, ","),
            enemy_hero_list = serialized_hero_list,
            enemy_agent_subtype = battle_definition.embedded_agent_subtype,
            generated_total_value = battle_definition.generated_total_value,
            total_hero_value = battle_definition.total_hero_value or 0,
            budget_delta = battle_definition.budget_delta,
            generated_unit_count = battle_definition.generated_unit_count or 0,
            generated_hero_count = battle_definition.generated_hero_count or 0,
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
                .. "], enemy_general_unit_value=["
                .. tostring(payload.enemy_general_unit_value)
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
