local battle_generator = {}

function battle_generator.new(context)
    local self = {}
    local log = context.log
    local cm = context.cm
    local split_string = context.split_string
    local unit_pool = context.unit_pool
    local battle_tier_keys = context.battle_tier
    local enemy_general_subtype = context.enemy_general_subtype
    local enemy_embedded_agent_subtype = context.enemy_embedded_agent_subtype
    local default_enemy_faction_key = context.default_enemy_faction_key

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
        for _, unit_entry in ipairs(unit_pool) do
            if unit_entry.unit_key == unit_key then
                return unit_entry
            end
        end

        return nil
    end

    function self.build_weighted_unit_pool_for_tier(battle_tier)
        local pool = {}
        log("build_weighted_unit_pool_for_tier called. battle_tier=[" .. tostring(battle_tier) .. "]")

        for _, unit_entry in ipairs(unit_pool) do
            if battle_tier >= unit_entry.min_battle_tier and battle_tier <= unit_entry.max_battle_tier then
                for _ = 1, unit_entry.weight do
                    pool[#pool + 1] = unit_entry
                end
            end
        end

        log("build_weighted_unit_pool_for_tier completed. weighted_pool_size=[" .. tostring(#pool) .. "]")
        return pool
    end

    function self.pick_enemy_general_subtype_for_tier(battle_tier)
        log("pick_enemy_general_subtype_for_tier called. battle_tier=[" .. tostring(battle_tier) .. "]")
        if battle_tier >= battle_tier_keys.LATE then
            log("pick_enemy_general_subtype_for_tier resolved subtype=[wh3_main_cth_dragon_blooded_shugengan_yin]")
            return "wh3_main_cth_dragon_blooded_shugengan_yin"
        end

        log("pick_enemy_general_subtype_for_tier resolved subtype=[" .. tostring(enemy_general_subtype) .. "]")
        return enemy_general_subtype
    end

    function self.pick_enemy_agent_subtype_for_tier(battle_tier, allow_embedded_agent)
        log(
            "pick_enemy_agent_subtype_for_tier called. battle_tier=["
                .. tostring(battle_tier)
                .. "], allow_embedded_agent=["
                .. tostring(allow_embedded_agent)
                .. "]"
        )
        if not allow_embedded_agent then
            log("pick_enemy_agent_subtype_for_tier resolved subtype=[] because embedded agents are disabled.")
            return ""
        end

        if battle_tier >= battle_tier_keys.MID then
            log("pick_enemy_agent_subtype_for_tier resolved subtype=[" .. tostring(enemy_embedded_agent_subtype) .. "]")
            return enemy_embedded_agent_subtype
        end

        log("pick_enemy_agent_subtype_for_tier resolved subtype=[] because battle tier is below MID.")
        return ""
    end

    function self.build_budget_enemy_force_definition(target_value_budget, battle_tier, allow_embedded_agent)
        log(
            "build_budget_enemy_force_definition called. budget=["
                .. tostring(target_value_budget)
                .. "], tier=["
                .. tostring(battle_tier)
                .. "], allow_embedded_agent=["
                .. tostring(allow_embedded_agent)
                .. "]"
        )
        local weighted_pool = self.build_weighted_unit_pool_for_tier(battle_tier)
        if #weighted_pool == 0 then
            log("build_budget_enemy_force_definition aborted because the weighted pool is empty.")
            return nil
        end

        local chosen_units = {}
        local chosen_unit_counts = {}
        local total_value = 0
        local max_units = 10 + battle_tier * 2
        local attempts = 0
        local soft_cap = math.floor(target_value_budget * 1.2)

        while attempts < 200 and #chosen_units < max_units do
            attempts = attempts + 1

            local unit_entry = weighted_pool[cm:random_number(#weighted_pool, 1)]
            local current_count = chosen_unit_counts[unit_entry.unit_key] or 0
            local role_cap = unit_entry.role_tag == "artillery" and 2 or (unit_entry.role_tag == "monster" and 1 or 4)

            if current_count < role_cap then
                local projected_total = total_value + unit_entry.unit_value
                local should_take = projected_total <= target_value_budget
                    or (#chosen_units < 4 and projected_total <= soft_cap)
                    or (target_value_budget - total_value > 500 and projected_total <= soft_cap)

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
            end

            if total_value >= math.floor(target_value_budget * 0.9) and #chosen_units >= 4 then
                log("build_budget_enemy_force_definition reached stop threshold and will exit the selection loop.")
                break
            end
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
                .. "], attempts=["
                .. tostring(attempts)
                .. "]."
        )
        return {
            template_type = "generated_by_budget",
            battle_force_source = "budget_generator_v1",
            lord_subtype = self.pick_enemy_general_subtype_for_tier(battle_tier),
            unit_list = chosen_units,
            embedded_agent_subtype = self.pick_enemy_agent_subtype_for_tier(battle_tier, allow_embedded_agent),
            generated_total_value = total_value,
            budget_delta = total_value - target_value_budget
        }
    end

    function self.create_battle_payload_from_definition(battle_definition, target_value_budget, battle_tier, spawn_retry_index, enemy_faction_key)
        local payload = {
            battle_template_key = battle_definition.template_type,
            battle_force_source = battle_definition.battle_force_source,
            target_value_budget = target_value_budget,
            battle_budget_tier = battle_tier,
            enemy_faction_key = enemy_faction_key or default_enemy_faction_key,
            enemy_general_subtype = battle_definition.lord_subtype,
            enemy_unit_list = table.concat(battle_definition.unit_list, ","),
            enemy_agent_subtype = battle_definition.embedded_agent_subtype,
            generated_total_value = battle_definition.generated_total_value,
            budget_delta = battle_definition.budget_delta,
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
