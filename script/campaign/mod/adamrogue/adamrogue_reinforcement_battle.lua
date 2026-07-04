local reinforcement_battle = {}

function reinforcement_battle.new(context)
    local self = {}
    local cm = context.cm
    local core = context.core
    local log = context.log
    local battle_pools = context.battle_pools or {}
    local apply_enemy_general_rank_for_current_cycle = context.apply_enemy_general_rank_for_current_cycle
    local module_key = context.module_key or "adamrogue_reinforcement_battle"
    local temp_range_bundle_key = context.temp_range_bundle_key or "adamrogue_temp_reinforcement_range"
    local support_army_count = context.support_army_count or 1
    local support_spawn_distance = context.support_spawn_distance or 5
    local support_max_player_distance = context.support_max_player_distance or 5.8
    local support_player_search_radii = context.support_player_search_radii or { 1, 2, 3, 4, 5 }
    local support_spawn_timeout_seconds = context.support_spawn_timeout_seconds or 3
    local default_enemy_faction_key = context.default_enemy_faction_key or battle_pools.DEFAULT_ENEMY_FACTION_KEY or ""

    local state = {
        pending_mode_active = false,
        pending_reinforcements_spawned = false,
        pending_context = nil,
        reinforcement_force_cqis = {},
        reinforcement_character_cqis = {},
        temporary_bundle_force_cqis = {},
    }

    local function payload_flag_is_true(value)
        return value == true or value == "true"
    end

    local function record_reinforcement_force_cqi(force_cqi)
        local normalized_force_cqi = tonumber(force_cqi) or 0
        if normalized_force_cqi <= 0 then
            return
        end
        for _, existing_force_cqi in ipairs(state.reinforcement_force_cqis) do
            if tonumber(existing_force_cqi) == normalized_force_cqi then
                return
            end
        end
        state.reinforcement_force_cqis[#state.reinforcement_force_cqis + 1] = normalized_force_cqi
    end

    local function record_reinforcement_character_cqi(character_cqi)
        local normalized_character_cqi = tonumber(character_cqi) or 0
        if normalized_character_cqi <= 0 then
            return
        end
        for _, existing_character_cqi in ipairs(state.reinforcement_character_cqis) do
            if tonumber(existing_character_cqi) == normalized_character_cqi then
                return
            end
        end
        state.reinforcement_character_cqis[#state.reinforcement_character_cqis + 1] = normalized_character_cqi
    end

    local function safe_character_value(character, accessor, fallback)
        if not character or character:is_null_interface() then
            return fallback
        end

        local ok, value = pcall(accessor)
        if ok then
            return value
        end

        return fallback
    end

    local function describe_character(character, label)
        if not character or character:is_null_interface() then
            return tostring(label) .. "={invalid}"
        end

        local force_cqi = 0
        if character:has_military_force() then
            local force = character:military_force()
            if force and not force:is_null_interface() then
                force_cqi = force:command_queue_index()
            end
        end

        local region_name = "none"
        local region = safe_character_value(character, function() return character:region() end, nil)
        if region and not region:is_null_interface() then
            region_name = region:name()
        end

        return tostring(label)
            .. "={char_cqi="
            .. tostring(character:command_queue_index())
            .. ",force_cqi="
            .. tostring(force_cqi)
            .. ",faction="
            .. tostring(character:faction():name())
            .. ",subtype="
            .. tostring(character:character_subtype_key())
            .. ",region="
            .. tostring(region_name)
            .. ",x="
            .. tostring(safe_character_value(character, function() return character:logical_position_x() end, "unavailable"))
            .. ",y="
            .. tostring(safe_character_value(character, function() return character:logical_position_y() end, "unavailable"))
            .. "}"
    end

    local function character_distance(a, b)
        if not a or a:is_null_interface() or not b or b:is_null_interface() then
            return "unavailable"
        end

        local ax = tonumber(safe_character_value(a, function() return a:logical_position_x() end, nil))
        local ay = tonumber(safe_character_value(a, function() return a:logical_position_y() end, nil))
        local bx = tonumber(safe_character_value(b, function() return b:logical_position_x() end, nil))
        local by = tonumber(safe_character_value(b, function() return b:logical_position_y() end, nil))
        if not ax or not ay or not bx or not by then
            return "unavailable"
        end

        local dx = ax - bx
        local dy = ay - by
        return string.format("%.2f", math.sqrt((dx * dx) + (dy * dy)))
    end

    local function xy_distance(ax, ay, bx, by)
        local normalized_ax = tonumber(ax)
        local normalized_ay = tonumber(ay)
        local normalized_bx = tonumber(bx)
        local normalized_by = tonumber(by)
        if not normalized_ax or not normalized_ay or not normalized_bx or not normalized_by then
            return nil
        end

        local dx = normalized_ax - normalized_bx
        local dy = normalized_ay - normalized_by
        return math.sqrt((dx * dx) + (dy * dy))
    end

    local function format_distance(value)
        if not value then
            return "unavailable"
        end
        return string.format("%.2f", value)
    end

    local function consider_spawn_candidate(best_candidate, candidate)
        if not candidate or candidate.x < 0 or candidate.y < 0 or not candidate.player_distance then
            return best_candidate
        end

        candidate.safe = candidate.player_distance <= support_max_player_distance
        if not best_candidate then
            return candidate
        end
        if candidate.safe and not best_candidate.safe then
            return candidate
        end
        if candidate.safe == best_candidate.safe and candidate.player_distance < best_candidate.player_distance then
            return candidate
        end
        return best_candidate
    end

    local function find_player_near_reinforcement_spawn_location(enemy_faction_key, player_character, attacker_character, reinforcement_index)
        if not player_character or player_character:is_null_interface() then
            return -1, -1, nil
        end

        local player_x = tonumber(safe_character_value(player_character, function() return player_character:logical_position_x() end, nil))
        local player_y = tonumber(safe_character_value(player_character, function() return player_character:logical_position_y() end, nil))
        local attacker_x = nil
        local attacker_y = nil
        if attacker_character and not attacker_character:is_null_interface() then
            attacker_x = tonumber(safe_character_value(attacker_character, function() return attacker_character:logical_position_x() end, nil))
            attacker_y = tonumber(safe_character_value(attacker_character, function() return attacker_character:logical_position_y() end, nil))
        end
        if not player_x or not player_y then
            return -1, -1, nil
        end

        local best_candidate = nil
        local candidate_count = 0
        local offsets = {
            { 0, 0 },
            { 1, 0 },
            { -1, 0 },
            { 0, 1 },
            { 0, -1 },
            { 1, 1 },
            { 1, -1 },
            { -1, 1 },
            { -1, -1 },
        }

        for _, radius in ipairs(support_player_search_radii) do
            local normalized_radius = tonumber(radius) or 0
            if normalized_radius >= 0 then
                for _, offset in ipairs(offsets) do
                    local request_x = math.floor(player_x + (offset[1] * normalized_radius) + 0.5)
                    local request_y = math.floor(player_y + (offset[2] * normalized_radius) + 0.5)
                    local x, y = cm:find_valid_spawn_location_for_character_from_position(
                        enemy_faction_key,
                        request_x,
                        request_y,
                        true
                    )
                    candidate_count = candidate_count + 1
                    best_candidate = consider_spawn_candidate(best_candidate, {
                        x = x,
                        y = y,
                        requested_x = request_x,
                        requested_y = request_y,
                        radius = normalized_radius,
                        player_distance = xy_distance(x, y, player_x, player_y),
                        attacker_distance = xy_distance(x, y, attacker_x, attacker_y),
                    })
                    if best_candidate and best_candidate.safe and best_candidate.player_distance <= 1 then
                        break
                    end
                end
            end
            if best_candidate and best_candidate.safe and best_candidate.player_distance <= 1 then
                break
            end
        end

        if best_candidate then
            log(
                "AR_REINF_SPAWN_PICK index=["
                    .. tostring(reinforcement_index)
                    .. "], candidate_count=["
                    .. tostring(candidate_count)
                    .. "], selected_x=["
                    .. tostring(best_candidate.x)
                    .. "], selected_y=["
                    .. tostring(best_candidate.y)
                    .. "], requested_x=["
                    .. tostring(best_candidate.requested_x)
                    .. "], requested_y=["
                    .. tostring(best_candidate.requested_y)
                    .. "], search_radius=["
                    .. tostring(best_candidate.radius)
                    .. "], reinforcement_player_distance=["
                    .. format_distance(best_candidate.player_distance)
                    .. "], reinforcement_attacker_distance=["
                    .. format_distance(best_candidate.attacker_distance)
                    .. "], max_player_distance=["
                    .. tostring(support_max_player_distance)
                    .. "], safe=["
                    .. tostring(best_candidate.safe)
                    .. "]."
            )
            if not best_candidate.safe then
                log(
                    "AR_REINF_SPAWN_WARN index=["
                        .. tostring(reinforcement_index)
                        .. "], reason=[no_candidate_within_player_distance], selected_player_distance=["
                        .. format_distance(best_candidate.player_distance)
                        .. "], max_player_distance=["
                        .. tostring(support_max_player_distance)
                        .. "]."
                )
            end
            return best_candidate.x, best_candidate.y, best_candidate
        end

        log(
            "AR_REINF_SPAWN_WARN index=["
                .. tostring(reinforcement_index)
                .. "], reason=[no_valid_player_near_candidate], candidate_count=["
                .. tostring(candidate_count)
                .. "]."
        )
        return -1, -1, nil
    end

    local function log_spatial_diagnostic(reason_label, attacker_character, player_character, reinforcement_character)
        local pending_context = state.pending_context or {}
        local attacker_faction = attacker_character and not attacker_character:is_null_interface() and attacker_character:faction() or nil
        local player_faction = player_character and not player_character:is_null_interface() and player_character:faction() or nil
        local reinforcement_faction = reinforcement_character
            and not reinforcement_character:is_null_interface()
            and reinforcement_character:faction()
            or nil
        local attacker_at_war = attacker_faction and player_faction and attacker_faction:at_war_with(player_faction) or "unavailable"
        local reinforcement_at_war = reinforcement_faction and player_faction and reinforcement_faction:at_war_with(player_faction) or "unavailable"

        log(
            "Reinforcement spatial diagnostic. reason=["
                .. tostring(reason_label)
                .. "], "
                .. describe_character(attacker_character, "attacker")
                .. ", "
                .. describe_character(player_character, "player")
                .. ", "
                .. describe_character(reinforcement_character, "reinforcement")
                .. ", attacker_player_distance=["
                .. tostring(character_distance(attacker_character, player_character))
                .. "], reinforcement_attacker_distance=["
                .. tostring(character_distance(reinforcement_character, attacker_character))
                .. "], reinforcement_player_distance=["
                .. tostring(character_distance(reinforcement_character, player_character))
                .. "], attacker_at_war_with_player=["
                .. tostring(attacker_at_war)
                .. "], reinforcement_at_war_with_player=["
                .. tostring(reinforcement_at_war)
                .. "], expected_enemy_faction_key=["
                .. tostring(pending_context.enemy_faction_key)
                .. "], temp_bundle=["
                .. tostring(temp_range_bundle_key)
                .. "]."
        )

        log(
            "AR_REINF_DISTANCE reason=["
                .. tostring(reason_label)
                .. "], attacker_force_cqi=["
                .. tostring(pending_context.attacker_force_cqi)
                .. "], player_force_cqi=["
                .. tostring(pending_context.player_force_cqi)
                .. "], reinforcement_force_cqi=["
                .. tostring(
                    reinforcement_character
                        and not reinforcement_character:is_null_interface()
                        and reinforcement_character:has_military_force()
                        and reinforcement_character:military_force():command_queue_index()
                        or "missing"
                )
                .. "], attacker_player_distance=["
                .. tostring(character_distance(attacker_character, player_character))
                .. "], reinforcement_attacker_distance=["
                .. tostring(character_distance(reinforcement_character, attacker_character))
                .. "], reinforcement_player_distance=["
                .. tostring(character_distance(reinforcement_character, player_character))
                .. "]."
        )
    end

    local function pending_battle_cache_side_summary(side_name, count_fn, get_fn)
        local entries = {}
        local count = count_fn()
        for index = 1, count do
            local char_cqi, force_cqi = get_fn(index)
            entries[#entries + 1] = tostring(index)
                .. ":char="
                .. tostring(char_cqi)
                .. ",force="
                .. tostring(force_cqi)
        end

        return side_name .. "_count=[" .. tostring(count) .. "], " .. side_name .. "=[" .. table.concat(entries, ";") .. "]"
    end

    local function force_cqi_exists_in_pending_battle_cache(target_force_cqi)
        local normalized_target = tonumber(target_force_cqi) or 0
        if normalized_target <= 0 then
            return false, "invalid"
        end

        for index = 1, cm:pending_battle_cache_num_attackers() do
            local _, force_cqi = cm:pending_battle_cache_get_attacker(index)
            if tonumber(force_cqi) == normalized_target then
                return true, "attacker"
            end
        end

        for index = 1, cm:pending_battle_cache_num_defenders() do
            local _, force_cqi = cm:pending_battle_cache_get_defender(index)
            if tonumber(force_cqi) == normalized_target then
                return true, "defender"
            end
        end

        return false, "missing"
    end

    function self.log_pending_battle_cache(reason_label)
        local pending_context = state.pending_context or {}
        local attacker_found, attacker_side = force_cqi_exists_in_pending_battle_cache(pending_context.attacker_force_cqi)
        local player_found, player_side = force_cqi_exists_in_pending_battle_cache(pending_context.player_force_cqi)
        local reinforcement_presence = {}
        local reinforcement_miss_entries = {}
        local any_reinforcement_missing = false

        for _, force_cqi in ipairs(state.reinforcement_force_cqis or {}) do
            local found, side = force_cqi_exists_in_pending_battle_cache(force_cqi)
            reinforcement_presence[#reinforcement_presence + 1] = tostring(force_cqi)
                .. ":"
                .. tostring(found)
                .. "/"
                .. tostring(side)
            if not found then
                any_reinforcement_missing = true
            end
            reinforcement_miss_entries[#reinforcement_miss_entries + 1] = tostring(force_cqi)
                .. ":miss="
                .. tostring(not found)
                .. "/side="
                .. tostring(side)
        end

        log(
            "Reinforcement pending battle cache diagnostic. reason=["
                .. tostring(reason_label)
                .. "], expected_attacker_force_cqi=["
                .. tostring(pending_context.attacker_force_cqi)
                .. "], attacker_found=["
                .. tostring(attacker_found)
                .. "], attacker_side=["
                .. tostring(attacker_side)
                .. "], expected_player_force_cqi=["
                .. tostring(pending_context.player_force_cqi)
                .. "], player_found=["
                .. tostring(player_found)
                .. "], player_side=["
                .. tostring(player_side)
                .. "], expected_reinforcement_force_cqis=["
                .. table.concat(state.reinforcement_force_cqis or {}, ",")
                .. "], reinforcement_presence=["
                .. table.concat(reinforcement_presence, ";")
                .. "], "
                .. pending_battle_cache_side_summary(
                    "attackers",
                    function() return cm:pending_battle_cache_num_attackers() end,
                    function(index) return cm:pending_battle_cache_get_attacker(index) end
                )
                .. ", "
                .. pending_battle_cache_side_summary(
                    "defenders",
                    function() return cm:pending_battle_cache_num_defenders() end,
                    function(index) return cm:pending_battle_cache_get_defender(index) end
                )
                .. "."
        )

        log(
            "AR_REINF_MISS reason=["
                .. tostring(reason_label)
                .. "], attacker_force_cqi=["
                .. tostring(pending_context.attacker_force_cqi)
                .. "], attacker_found=["
                .. tostring(attacker_found)
                .. "], player_force_cqi=["
                .. tostring(pending_context.player_force_cqi)
                .. "], player_found=["
                .. tostring(player_found)
                .. "], reinforcement_force_cqis=["
                .. table.concat(state.reinforcement_force_cqis or {}, ",")
                .. "], any_reinforcement_missing=["
                .. tostring(any_reinforcement_missing)
                .. "], reinforcement_miss_entries=["
                .. table.concat(reinforcement_miss_entries, ";")
                .. "], attackers_count=["
                .. tostring(cm:pending_battle_cache_num_attackers())
                .. "], defenders_count=["
                .. tostring(cm:pending_battle_cache_num_defenders())
                .. "]."
        )
    end

    local function apply_range_bundle_to_force(force_cqi, reason_label)
        local normalized_force_cqi = tonumber(force_cqi) or 0
        if normalized_force_cqi <= 0 then
            log("apply_range_bundle_to_force skipped invalid force. reason=[" .. tostring(reason_label) .. "].")
            return
        end

        cm:apply_effect_bundle_to_force(temp_range_bundle_key, normalized_force_cqi, 0)
        state.temporary_bundle_force_cqis[#state.temporary_bundle_force_cqis + 1] = normalized_force_cqi
        log(
            "Applied temporary reinforcement range bundle. reason=["
                .. tostring(reason_label)
                .. "], force_cqi=["
                .. tostring(normalized_force_cqi)
                .. "], bundle=["
                .. tostring(temp_range_bundle_key)
                .. "]."
        )
    end

    local function clear_range_bundles(reason_label)
        for _, force_cqi in ipairs(state.temporary_bundle_force_cqis or {}) do
            local normalized_force_cqi = tonumber(force_cqi) or 0
            if normalized_force_cqi > 0 then
                cm:remove_effect_bundle_from_force(temp_range_bundle_key, normalized_force_cqi)
                log(
                    "Removed temporary reinforcement range bundle. reason=["
                        .. tostring(reason_label)
                        .. "], force_cqi=["
                        .. tostring(normalized_force_cqi)
                        .. "]."
                )
            end
        end
        state.temporary_bundle_force_cqis = {}
    end

    function self.cleanup(reason_label)
        clear_range_bundles(reason_label)

        for _, force_cqi in ipairs(state.reinforcement_force_cqis or {}) do
            local force = cm:get_military_force_by_cqi(tonumber(force_cqi) or 0)
            if force and not force:is_null_interface() and force:has_general() then
                local general = force:general_character()
                if general and not general:is_null_interface() then
                    cm:kill_character(cm:char_lookup_str(general), true)
                    log(
                        "Killed dynamic reinforcement army general. reason=["
                            .. tostring(reason_label)
                            .. "], force_cqi=["
                            .. tostring(force_cqi)
                            .. "], general_cqi=["
                            .. tostring(general:command_queue_index())
                            .. "]."
                    )
                end
            end
        end

        state.pending_mode_active = false
        state.pending_reinforcements_spawned = false
        state.pending_context = nil
        state.reinforcement_force_cqis = {}
        state.reinforcement_character_cqis = {}
    end

    local function pending_battle_matches_context(event_context)
        if not state.pending_mode_active or state.pending_reinforcements_spawned then
            return false
        end

        local pending_context = state.pending_context
        if not pending_context then
            return false
        end

        local acting_character = event_context:character()
        local target_character = event_context:target_character()
        if not acting_character or acting_character:is_null_interface() then
            return false
        end
        if not target_character or target_character:is_null_interface() then
            return false
        end

        local acting_cqi = acting_character:command_queue_index()
        local target_cqi = target_character:command_queue_index()
        local attacker_cqi = tonumber(pending_context.attacker_general_cqi) or 0
        local player_cqi = tonumber(pending_context.player_general_cqi) or 0
        return (acting_cqi == attacker_cqi and target_cqi == player_cqi)
            or (acting_cqi == player_cqi and target_cqi == attacker_cqi)
    end

    local function spawn_pending_reinforcement_force(reference_character, reference_source, reinforcement_index, on_complete, is_still_expected)
        local pending_context = state.pending_context or {}
        if not reference_character or reference_character:is_null_interface() then
            log("spawn_pending_reinforcement_force failed because no reference character is available.")
            if on_complete then
                on_complete(false)
            end
            return false
        end

        local region = reference_character:region()
        if not region or region:is_null_interface() then
            log("spawn_pending_reinforcement_force failed because reference character has no valid region.")
            if on_complete then
                on_complete(false)
            end
            return false
        end

        local enemy_faction_key = pending_context.enemy_faction_key or default_enemy_faction_key
        local attacker_character = cm:get_character_by_cqi(tonumber(pending_context.attacker_general_cqi) or 0)
        local player_character = cm:get_character_by_cqi(tonumber(pending_context.player_general_cqi) or 0)
        log(
            "spawn_pending_reinforcement_force reference resolved. index=["
                .. tostring(reinforcement_index)
                .. "], reference_source=["
                .. tostring(reference_source)
                .. "], "
                .. describe_character(reference_character, "reference")
                .. "."
        )
        log_spatial_diagnostic("before_reinforcement_spawn_location_search", attacker_character, player_character, nil)

        local x, y, selected_spawn_candidate = find_player_near_reinforcement_spawn_location(
            enemy_faction_key,
            player_character or reference_character,
            attacker_character,
            reinforcement_index
        )

        if x < 0 or y < 0 then
            x, y = cm:find_valid_spawn_location_for_character_from_character(
                enemy_faction_key,
                cm:char_lookup_str(reference_character:command_queue_index()),
                true,
                support_spawn_distance + reinforcement_index
            )
        end
        log(
            "spawn_pending_reinforcement_force spawn location resolved. index=["
                .. tostring(reinforcement_index)
                .. "], enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], x=["
                .. tostring(x)
                .. "], y=["
                .. tostring(y)
                .. "], search_distance=["
                .. tostring(support_spawn_distance + reinforcement_index)
                .. "], selected_player_distance=["
                .. tostring(selected_spawn_candidate and format_distance(selected_spawn_candidate.player_distance) or "fallback")
                .. "]."
        )
        if x < 0 or y < 0 then
            log("spawn_pending_reinforcement_force failed because no valid spawn position was found.")
            if on_complete then
                on_complete(false)
            end
            return false
        end

        cm:create_force(
            enemy_faction_key,
            pending_context.reinforcement_unit_list or "",
            region:name(),
            x,
            y,
            true,
            function(char_cqi, force_cqi)
                local reinforcement_general = cm:get_character_by_cqi(char_cqi or 0)
                if is_still_expected and not is_still_expected() then
                    log(
                        "AR_REINF_SPAWN_LATE_CALLBACK_CLEANUP index=["
                            .. tostring(reinforcement_index)
                            .. "], general_cqi=["
                            .. tostring(char_cqi)
                            .. "], force_cqi=["
                            .. tostring(force_cqi)
                            .. "]."
                    )
                    if reinforcement_general and not reinforcement_general:is_null_interface() then
                        cm:kill_character(cm:char_lookup_str(reinforcement_general), true)
                    end
                    return
                end
                if not reinforcement_general or reinforcement_general:is_null_interface() then
                    log(
                        "AR_REINF_SPAWN_WARN index=["
                            .. tostring(reinforcement_index)
                            .. "], reason=[callback_without_valid_general], general_cqi=["
                            .. tostring(char_cqi)
                            .. "], force_cqi=["
                            .. tostring(force_cqi)
                            .. "]."
                    )
                    if on_complete then
                        on_complete(false)
                    end
                    return
                end

                local is_at_sea = safe_character_value(reinforcement_general, function() return reinforcement_general:is_at_sea() end, false)
                if is_at_sea then
                    log(
                        "AR_REINF_SPAWN_WARN index=["
                            .. tostring(reinforcement_index)
                            .. "], reason=[generated_at_sea], general_cqi=["
                            .. tostring(char_cqi)
                            .. "], force_cqi=["
                            .. tostring(force_cqi)
                            .. "], x=["
                            .. tostring(x)
                            .. "], y=["
                            .. tostring(y)
                            .. "]."
                    )
                    cm:kill_character(cm:char_lookup_str(reinforcement_general), true)
                    if on_complete then
                        on_complete(false)
                    end
                    return
                end

                record_reinforcement_character_cqi(char_cqi)
                record_reinforcement_force_cqi(force_cqi)
                log_spatial_diagnostic(
                    "after_reinforcement_create_force_callback_before_rank_setup",
                    cm:get_character_by_cqi(tonumber(pending_context.attacker_general_cqi) or 0),
                    cm:get_character_by_cqi(tonumber(pending_context.player_general_cqi) or 0),
                    reinforcement_general
                )
                apply_enemy_general_rank_for_current_cycle(
                    reinforcement_general,
                    "pending_reinforcement_" .. tostring(reinforcement_index),
                    nil
                )
                cm:disable_movement_for_character(cm:char_lookup_str(reinforcement_general))

                log(
                    "Dynamic pending reinforcement army created. index=["
                        .. tostring(reinforcement_index)
                        .. "], enemy_faction_key=["
                        .. tostring(enemy_faction_key)
                        .. "], general_cqi=["
                        .. tostring(char_cqi)
                        .. "], force_cqi=["
                        .. tostring(force_cqi)
                        .. "], region=["
                        .. tostring(region:name())
                        .. "], x=["
                        .. tostring(x)
                        .. "], y=["
                        .. tostring(y)
                        .. "], unit_list=["
                        .. tostring(pending_context.reinforcement_unit_list)
                        .. "]."
                )
                cm:update_pending_battle()
                self.log_pending_battle_cache("after_reinforcement_create_force_callback_update")
                cm:callback(function()
                    self.log_pending_battle_cache("delayed_after_reinforcement_create_force_callback_update")
                    log_spatial_diagnostic(
                        "delayed_after_reinforcement_create_force_callback_update",
                        cm:get_character_by_cqi(tonumber(pending_context.attacker_general_cqi) or 0),
                        cm:get_character_by_cqi(tonumber(pending_context.player_general_cqi) or 0),
                        cm:get_character_by_cqi(tonumber(char_cqi) or 0)
                    )
                    cm:update_pending_battle()
                    self.log_pending_battle_cache("delayed_after_second_update_pending_battle")
                end, 0.05)
                if on_complete then
                    on_complete(true)
                end
            end
        )

        log(
            "Dynamic pending reinforcement create_force issued. index=["
                .. tostring(reinforcement_index)
                .. "], enemy_faction_key=["
                .. tostring(enemy_faction_key)
                .. "], region=["
                .. tostring(region:name())
                .. "], x=["
                .. tostring(x)
                .. "], y=["
                .. tostring(y)
                .. "]."
        )
        return true
    end

    local function ensure_pending_battle_listener()
        if _G.__adamrogue_reinforcement_pending_battle_listener_registered then
            return
        end
        _G.__adamrogue_reinforcement_pending_battle_listener_registered = true

        core:add_listener(
            module_key .. "_dynamic_pending_reinforcement",
            "PendingBattleAboutToBeCreated",
            pending_battle_matches_context,
            function(event_context)
                local pending_context = state.pending_context or {}
                local acting_character = event_context:character()
                local target_character = event_context:target_character()
                log(
                    "PendingBattleAboutToBeCreated matched dynamic reinforcement context. attacker_general_cqi=["
                        .. tostring(pending_context.attacker_general_cqi)
                        .. "], player_general_cqi=["
                        .. tostring(pending_context.player_general_cqi)
                        .. "], reinforcement_budget=["
                        .. tostring(pending_context.reinforcement_target_value_budget)
                        .. "]."
                )
                log(
                    "PendingBattleAboutToBeCreated context characters. "
                        .. describe_character(acting_character, "acting")
                        .. ", "
                        .. describe_character(target_character, "target")
                        .. "."
                )
                log_spatial_diagnostic(
                    "pending_listener_matched_before_spawn",
                    cm:get_character_by_cqi(tonumber(pending_context.attacker_general_cqi) or 0),
                    cm:get_character_by_cqi(tonumber(pending_context.player_general_cqi) or 0),
                    nil
                )

                state.pending_reinforcements_spawned = true
                self.log_pending_battle_cache("pending_listener_before_spawn")
                for reinforcement_index = 1, support_army_count do
                    local reference_character = event_context:target_character()
                    local reference_source = "target_character"
                    if not reference_character or reference_character:is_null_interface() then
                        reference_character = event_context:character()
                        reference_source = "acting_character"
                    end
                    spawn_pending_reinforcement_force(reference_character, reference_source, reinforcement_index, nil)
                end
                cm:update_pending_battle()
                self.log_pending_battle_cache("pending_listener_after_initial_update")
            end,
            true
        )

        core:add_listener(
            module_key .. "_dynamic_pending_reinforcement_pre_battle_cache",
            "ScriptEventPreBattlePanelOpened",
            function()
                return state.pending_mode_active
                    or #state.reinforcement_force_cqis > 0
            end,
            function()
                self.log_pending_battle_cache("pre_battle_panel_opened")
            end,
            true
        )
    end

    function self.prepare_pending_context(attacker_character, player_force, payload, enemy_faction_key, player_region_name)
        if not payload_flag_is_true(payload and payload.reinforcement_battle_enabled) then
            log(
                "prepare_reinforcement_pending_context skipped because payload is not reinforcement-enabled. raw_flag=["
                    .. tostring(payload and payload.reinforcement_battle_enabled or "")
                    .. "]."
            )
            self.cleanup("prepare_reinforcement_context_disabled")
            return false
        end

        local reinforcement_unit_list = tostring(payload.reinforcement_unit_list or "")
        if reinforcement_unit_list == "" then
            log("prepare_reinforcement_pending_context skipped because reinforcement_unit_list is empty.")
            self.cleanup("prepare_reinforcement_context_empty_unit_list")
            return false
        end
        if not attacker_character or attacker_character:is_null_interface() or not attacker_character:has_military_force() then
            log("prepare_reinforcement_pending_context skipped because attacker is invalid.")
            self.cleanup("prepare_reinforcement_context_invalid_attacker")
            return false
        end
        if not player_force or player_force:is_null_interface() or not player_force:has_general() then
            log("prepare_reinforcement_pending_context skipped because player force is invalid.")
            self.cleanup("prepare_reinforcement_context_invalid_player")
            return false
        end

        local attacker_force = attacker_character:military_force()
        local player_general = player_force:general_character()
        local attacker_force_cqi = attacker_force:command_queue_index()
        local player_force_cqi = player_force:command_queue_index()

        self.cleanup("prepare_reinforcement_context_reset")
        state.pending_mode_active = true
        state.pending_reinforcements_spawned = false
        state.pending_context = {
            attacker_general_cqi = attacker_character:command_queue_index(),
            attacker_force_cqi = attacker_force_cqi,
            player_general_cqi = player_general:command_queue_index(),
            player_force_cqi = player_force_cqi,
            enemy_faction_key = enemy_faction_key,
            player_region_name = player_region_name,
            reinforcement_unit_list = reinforcement_unit_list,
            reinforcement_target_value_budget = tonumber(payload.reinforcement_target_value_budget) or 0,
            reinforcement_generated_total_value = tonumber(payload.reinforcement_generated_total_value) or 0
        }

        -- Test only the attacker's reinforcement range. Applying the same bundle to
        -- the defender/player can obscure which side actually controls reinforcement pickup.
        apply_range_bundle_to_force(attacker_force_cqi, "reinforcement_attacker")
        ensure_pending_battle_listener()
        log(
            "prepare_reinforcement_pending_context completed. attacker_general_cqi=["
                .. tostring(state.pending_context.attacker_general_cqi)
                .. "], attacker_force_cqi=["
                .. tostring(attacker_force_cqi)
                .. "], player_general_cqi=["
                .. tostring(state.pending_context.player_general_cqi)
                .. "], player_force_cqi=["
                .. tostring(player_force_cqi)
                .. "], reinforcement_budget=["
                .. tostring(state.pending_context.reinforcement_target_value_budget)
                .. "], reinforcement_generated_value=["
                .. tostring(state.pending_context.reinforcement_generated_total_value)
                .. "]."
        )
        log_spatial_diagnostic("prepare_reinforcement_pending_context", attacker_character, player_general, nil)
        return true
    end

    function self.prepare_reinforcements_before_attack(attacker_character, player_force, payload, enemy_faction_key, player_region_name, on_ready, delay_seconds)
        local prepared = self.prepare_pending_context(
            attacker_character,
            player_force,
            payload,
            enemy_faction_key,
            player_region_name
        )
        if not prepared then
            return false
        end

        local player_general = player_force:general_character()
        local remaining = support_army_count
        local success_count = 0
        local completed_by_index = {}
        state.pending_reinforcements_spawned = true
        log(
            "Pre-attack reinforcement spawn started. support_army_count=["
                .. tostring(support_army_count)
                .. "], delay_seconds=["
                .. tostring(delay_seconds or 0)
                .. "]."
        )

        local function finish_pre_attack_spawn(reinforcement_index, spawned, finish_reason)
            if completed_by_index[reinforcement_index] then
                log(
                    "AR_REINF_SPAWN_LATE_COMPLETION index=["
                        .. tostring(reinforcement_index)
                        .. "], spawned=["
                        .. tostring(spawned)
                        .. "], finish_reason=["
                        .. tostring(finish_reason)
                        .. "]."
                )
                return
            end
            completed_by_index[reinforcement_index] = true
            if spawned then
                success_count = success_count + 1
            end
            remaining = remaining - 1
            log(
                "Pre-attack reinforcement spawn progress. spawned=["
                    .. tostring(spawned)
                    .. "], reinforcement_index=["
                    .. tostring(reinforcement_index)
                    .. "], finish_reason=["
                    .. tostring(finish_reason)
                    .. "], success_count=["
                    .. tostring(success_count)
                    .. "], remaining=["
                    .. tostring(remaining)
                    .. "]."
            )
            if remaining > 0 then
                return
            end

            self.log_pending_battle_cache("after_pre_attack_reinforcement_spawn_before_wait")
            for _, reinforcement_character_cqi in ipairs(state.reinforcement_character_cqis or {}) do
                log_spatial_diagnostic(
                    "after_pre_attack_reinforcement_spawn_before_wait_reinforcement_" .. tostring(reinforcement_character_cqi),
                    attacker_character,
                    player_general,
                    cm:get_character_by_cqi(tonumber(reinforcement_character_cqi) or 0)
                )
            end
            log_spatial_diagnostic(
                "after_pre_attack_reinforcement_spawn_before_wait",
                attacker_character,
                player_general,
                nil
            )
            log(
                "Pre-attack reinforcement spawn finished. Scheduling force_attack_of_opportunity. delay_seconds=["
                    .. tostring(delay_seconds or 0)
                    .. "], success_count=["
                    .. tostring(success_count)
                    .. "]."
            )
            cm:callback(function()
                self.log_pending_battle_cache("after_pre_attack_reinforcement_wait_before_attack")
                if on_ready then
                    on_ready(success_count > 0)
                end
            end, delay_seconds or 0)
        end

        for reinforcement_index = 1, support_army_count do
            local issued = spawn_pending_reinforcement_force(
                player_general,
                "pre_attack_player_general",
                reinforcement_index,
                function(spawned)
                    finish_pre_attack_spawn(reinforcement_index, spawned, "callback")
                end,
                function()
                    return not completed_by_index[reinforcement_index]
                end
            )
            if not issued then
                -- Synchronous validation failures do not enter the create_force callback.
            else
                cm:callback(function()
                    if completed_by_index[reinforcement_index] then
                        return
                    end
                    log(
                        "AR_REINF_SPAWN_TIMEOUT index=["
                            .. tostring(reinforcement_index)
                            .. "], timeout_seconds=["
                            .. tostring(support_spawn_timeout_seconds)
                            .. "]."
                    )
                    finish_pre_attack_spawn(reinforcement_index, false, "timeout")
                end, support_spawn_timeout_seconds)
            end
        end
        return true
    end

    return self
end

return reinforcement_battle
