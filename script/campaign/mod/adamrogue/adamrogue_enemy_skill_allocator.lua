local enemy_skill_data = require("adamrogue_data_enemy_skills")

local M = {}

local function safe_character_skill_points(character)
    local ok, result = pcall(function()
        return character:skill_points()
    end)
    if ok then
        return tonumber(result) or 0
    end

    return nil
end

local function safe_character_has_skill(character, skill_key)
    local ok, result = pcall(function()
        return character:has_skill(skill_key)
    end)
    if ok then
        return result == true
    end

    return nil
end

local function safe_character_skill_level(character, skill_key)
    local ok, result = pcall(function()
        return character:skill_level(skill_key)
    end)
    if ok then
        return tonumber(result) or 0
    end

    return nil
end

local function apply_single_skill_level(character, skill_key)
    local ok, error_or_nil = pcall(function()
        cm:add_skill(character, skill_key, true, false)
    end)
    if not ok then
        return false, tostring(error_or_nil)
    end

    return true, nil
end

function M.apply_skills_for_character(character, target_rank, log_fn, context_label)
    if not character or character:is_null_interface() then
        return {
            applied_levels = 0,
            skipped_entries = 0,
            blocked_entries = 0,
            failed_levels = 0,
            mount_skills_applied = 0,
            reason = "invalid_character",
        }
    end

    local subtype_key = character:character_subtype_key()
    local skill_plan = enemy_skill_data.CHARACTER_SKILL_PLANS_BY_SUBTYPE[subtype_key]
    if not skill_plan or #skill_plan == 0 then
        if log_fn then
            log_fn(
                "Enemy skill allocator found no generated skill plan for subtype=["
                    .. tostring(subtype_key)
                    .. "], context=["
                    .. tostring(context_label)
                    .. "]."
            )
        end
        return {
            applied_levels = 0,
            skipped_entries = 0,
            blocked_entries = 0,
            failed_levels = 0,
            mount_skills_applied = 0,
            reason = "missing_skill_plan",
        }
    end

    local normalized_target_rank = math.max(1, math.floor(tonumber(target_rank) or 1))
    local blocked_node_keys = {}
    local applied_levels = 0
    local skipped_entries = 0
    local blocked_entries = 0
    local failed_levels = 0
    local mount_skills_applied = 0

    if log_fn then
        log_fn(
            "Enemy skill allocator starting. context=["
                .. tostring(context_label)
                .. "], character_cqi=["
                .. tostring(character:command_queue_index())
                .. "], subtype=["
                .. tostring(subtype_key)
                .. "], target_rank=["
                .. tostring(normalized_target_rank)
                .. "], generated_entry_count=["
                .. tostring(#skill_plan)
                .. "], content_faction_key=["
                .. tostring(enemy_skill_data.CONTENT_FACTION_KEY_BY_SUBTYPE[subtype_key] or "")
                .. "]."
        )
    end

    for _, entry in ipairs(skill_plan) do
        local node_key = entry.node_key
        local skill_key = entry.skill_key
        if blocked_node_keys[node_key] then
            blocked_entries = blocked_entries + 1
            if log_fn then
                log_fn(
                    "Enemy skill allocator skipped a locked node. context=["
                        .. tostring(context_label)
                        .. "], subtype=["
                        .. tostring(subtype_key)
                        .. "], node_key=["
                        .. tostring(node_key)
                        .. "], skill_key=["
                        .. tostring(skill_key)
                        .. "]."
                )
            end
        else
            local unlock_ranks_by_level = entry.unlock_ranks_by_level or {}
            local max_level = tonumber(entry.max_level) or #unlock_ranks_by_level or 1
            local applied_this_entry = false

            for level_index = 1, max_level do
                local unlock_rank = tonumber(unlock_ranks_by_level[level_index]) or 0
                if normalized_target_rank < unlock_rank then
                    skipped_entries = skipped_entries + 1
                    if log_fn then
                        log_fn(
                            "Enemy skill allocator stopped advancing this skill because the target rank is below the unlock rank. context=["
                                .. tostring(context_label)
                                .. "], subtype=["
                                .. tostring(subtype_key)
                                .. "], node_key=["
                                .. tostring(node_key)
                                .. "], skill_key=["
                                .. tostring(skill_key)
                                .. "], level_index=["
                                .. tostring(level_index)
                                .. "], unlock_rank=["
                                .. tostring(unlock_rank)
                                .. "], target_rank=["
                                .. tostring(normalized_target_rank)
                                .. "]."
                        )
                    end
                    break
                end

                local before_level = safe_character_skill_level(character, skill_key)
                local before_has_skill = safe_character_has_skill(character, skill_key)
                local before_points = safe_character_skill_points(character)
                local apply_ok, apply_error = apply_single_skill_level(character, skill_key)
                local after_level = safe_character_skill_level(character, skill_key)
                local after_points = safe_character_skill_points(character)
                local has_skill_now = safe_character_has_skill(character, skill_key)
                local success_detected = false

                if before_level ~= nil and after_level ~= nil then
                    success_detected = after_level > before_level
                elseif before_has_skill ~= nil and has_skill_now ~= nil then
                    success_detected = (before_has_skill == false and has_skill_now == true) or before_has_skill == true
                elseif apply_ok then
                    success_detected = true
                end

                if apply_ok and success_detected then
                    applied_levels = applied_levels + 1
                    applied_this_entry = true
                    if entry.is_mount_skill then
                        mount_skills_applied = mount_skills_applied + 1
                    end

                    if log_fn then
                        log_fn(
                            "Enemy skill allocator applied one skill level. context=["
                                .. tostring(context_label)
                                .. "], subtype=["
                                .. tostring(subtype_key)
                                .. "], node_key=["
                                .. tostring(node_key)
                                .. "], skill_key=["
                                .. tostring(skill_key)
                                .. "], level_index=["
                                .. tostring(level_index)
                                .. "], unlock_rank=["
                                .. tostring(unlock_rank)
                                .. "], before_level=["
                                .. tostring(before_level)
                                .. "], after_level=["
                                .. tostring(after_level)
                                .. "], before_points=["
                                .. tostring(before_points)
                                .. "], after_points=["
                                .. tostring(after_points)
                                .. "], is_mount_skill=["
                                .. tostring(entry.is_mount_skill)
                                .. "]."
                        )
                    end
                else
                    failed_levels = failed_levels + 1
                    if log_fn then
                        log_fn(
                            "Enemy skill allocator could not apply a skill level. context=["
                                .. tostring(context_label)
                                .. "], subtype=["
                                .. tostring(subtype_key)
                                .. "], node_key=["
                                .. tostring(node_key)
                                .. "], skill_key=["
                                .. tostring(skill_key)
                                .. "], level_index=["
                                .. tostring(level_index)
                                .. "], unlock_rank=["
                                .. tostring(unlock_rank)
                                .. "], before_level=["
                                .. tostring(before_level)
                                .. "], after_level=["
                                .. tostring(after_level)
                                .. "], before_points=["
                                .. tostring(before_points)
                                .. "], after_points=["
                                .. tostring(after_points)
                                .. "], has_skill_now=["
                                .. tostring(has_skill_now)
                                .. "], error=["
                                .. tostring(apply_error)
                                .. "]."
                        )
                    end
                    break
                end
            end

            if applied_this_entry then
                for _, locked_node_key in ipairs(entry.locked_node_keys or {}) do
                    blocked_node_keys[locked_node_key] = true
                end
            end
        end
    end

    if log_fn then
        log_fn(
            "Enemy skill allocator completed. context=["
                .. tostring(context_label)
                .. "], subtype=["
                .. tostring(subtype_key)
                .. "], applied_levels=["
                .. tostring(applied_levels)
                .. "], mount_skills_applied=["
                .. tostring(mount_skills_applied)
                .. "], blocked_entries=["
                .. tostring(blocked_entries)
                .. "], skipped_entries=["
                .. tostring(skipped_entries)
                .. "], failed_levels=["
                .. tostring(failed_levels)
                .. "], remaining_skill_points=["
                .. tostring(safe_character_skill_points(character))
                .. "]."
        )
    end

    return {
        applied_levels = applied_levels,
        skipped_entries = skipped_entries,
        blocked_entries = blocked_entries,
        failed_levels = failed_levels,
        mount_skills_applied = mount_skills_applied,
        reason = "completed",
    }
end

return M
