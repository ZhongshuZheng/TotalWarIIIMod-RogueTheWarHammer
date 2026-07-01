local travel_anchor_manager = {}

local CONFIG = {
    TARGET_ANCHOR_COUNT = 30,
    MIN_UNITS = 8,
    EMPTY_POOL_SENTINEL = "__empty",
    SEARCH_RADII = { 8, 12, 16, 24 },
    MAX_RELOCATION_ATTEMPTS = 8
}

local function interface_ok(value)
    return value and not value:is_null_interface()
end

local function call_bool(object, method_name, fallback)
    local ok, result = pcall(function()
        return object[method_name](object)
    end)
    if not ok then
        return fallback
    end
    return result == true
end

local function call_value(object, method_name, fallback)
    local ok, result = pcall(function()
        return object[method_name](object)
    end)
    if not ok or result == nil then
        return fallback
    end
    return result
end

local function split(input, delimiter)
    local result = {}
    if type(input) ~= "string" or input == "" then
        return result
    end

    local pattern = string.format("([^%s]+)", delimiter)
    for token in string.gmatch(input, pattern) do
        result[#result + 1] = token
    end

    return result
end

function travel_anchor_manager.new(context)
    local self = {}
    local cm = context.cm
    local log = context.log or function()
    end
    local save_keys = context.save_keys
    local get_saved_value = context.get_saved_value
    local set_saved_value = context.set_saved_value

    local function encode_anchor(anchor)
        return table.concat({
            tostring(anchor.key or ""),
            tostring(anchor.x or 0),
            tostring(anchor.y or 0),
            tostring(anchor.faction_key or ""),
            tostring(anchor.subculture_key or "")
        }, ",")
    end

    local function decode_anchor(token)
        local fields = split(token, ",")
        if #fields < 3 then
            return nil
        end

        local x = tonumber(fields[2])
        local y = tonumber(fields[3])
        if not x or not y then
            return nil
        end

        return {
            key = fields[1],
            x = x,
            y = y,
            faction_key = fields[4] or "",
            subculture_key = fields[5] or ""
        }
    end

    local function encode_pool(anchors)
        local encoded = {}
        for _, anchor in ipairs(anchors or {}) do
            encoded[#encoded + 1] = encode_anchor(anchor)
        end
        return table.concat(encoded, "|")
    end

    function self.decode_pool(serialized)
        local anchors = {}
        for _, token in ipairs(split(serialized, "|")) do
            local anchor = decode_anchor(token)
            if anchor then
                anchors[#anchors + 1] = anchor
            end
        end
        return anchors
    end

    local function is_valid_faction(faction, player_faction_key)
        if not interface_ok(faction) then
            return false
        end
        if call_bool(faction, "is_dead", true) then
            return false
        end
        if call_bool(faction, "is_human", false) then
            return false
        end
        if call_bool(faction, "is_rebel", false) then
            return false
        end
        return faction:name() ~= player_faction_key
    end

    local function is_valid_general(general)
        if not interface_ok(general) then
            return false
        end
        if call_bool(general, "is_at_sea", false) then
            return false
        end
        if call_bool(general, "has_region", false) == false then
            return false
        end
        return true
    end

    local function candidate_from_force(faction, force, index)
        if not interface_ok(force) then
            return nil
        end
        if call_bool(force, "is_armed_citizenry", true) then
            return nil
        end
        if call_bool(force, "is_army", true) == false then
            return nil
        end
        if call_bool(force, "has_general", false) == false then
            return nil
        end
        if call_value(force:unit_list(), "num_items", 0) < CONFIG.MIN_UNITS then
            return nil
        end

        local general = force:general_character()
        if not is_valid_general(general) then
            return nil
        end

        return {
            key = faction:name() .. "_" .. tostring(index),
            x = general:logical_position_x(),
            y = general:logical_position_y(),
            faction_key = faction:name(),
            subculture_key = call_value(faction, "subculture", ""),
            strength = call_value(force, "strength", 0)
        }
    end

    local function best_candidate_for_faction(faction)
        local force_list = faction:military_force_list()
        local best = nil
        for index = 0, force_list:num_items() - 1 do
            local candidate = candidate_from_force(faction, force_list:item_at(index), index)
            if candidate and (not best or candidate.strength > best.strength) then
                best = candidate
            end
        end
        return best
    end

    local function collect_candidates(player_faction_key)
        local candidates = {}
        local faction_list = cm:get_faction_list()
        for index = 0, faction_list:num_items() - 1 do
            local faction = faction_list:item_at(index)
            if is_valid_faction(faction, player_faction_key) then
                local candidate = best_candidate_for_faction(faction)
                if candidate then
                    candidates[#candidates + 1] = candidate
                end
            end
        end
        return candidates
    end

    local function draw_static_pool(candidates)
        local pool = {}
        while #candidates > 0 and #pool < CONFIG.TARGET_ANCHOR_COUNT do
            local index = cm:random_number(#candidates, 1)
            pool[#pool + 1] = candidates[index]
            table.remove(candidates, index)
        end
        return pool
    end

    function self.ensure_pool(player_faction_key)
        local saved_pool = tostring(get_saved_value(save_keys.travel_anchor_pool, "") or "")
        if saved_pool == CONFIG.EMPTY_POOL_SENTINEL then
            return {}
        end

        local anchors = self.decode_pool(saved_pool)
        if #anchors > 0 then
            return anchors
        end

        anchors = draw_static_pool(collect_candidates(player_faction_key))
        set_saved_value(save_keys.travel_anchor_pool, #anchors > 0 and encode_pool(anchors) or CONFIG.EMPTY_POOL_SENTINEL)
        log(
            "Generated static travel anchor pool. player_faction_key=["
                .. tostring(player_faction_key)
                .. "], anchor_count=["
                .. tostring(#anchors)
                .. "]."
        )
        return anchors
    end

    local function resolve_spawn_position(player_faction_key, anchor)
        for _, radius in ipairs(CONFIG.SEARCH_RADII) do
            local x, y = cm:find_valid_spawn_location_for_character_from_position(
                player_faction_key,
                anchor.x,
                anchor.y,
                false,
                radius
            )
            if x and y and x >= 0 and y >= 0 then
                return x, y, radius
            end
        end
        return nil
    end

    function self.relocate_player_near_saved_anchor(player_faction, player_general, reason)
        local anchors = self.ensure_pool(player_faction:name())
        if #anchors == 0 then
            log("Static travel anchor relocation skipped because no anchors were generated. reason=[" .. tostring(reason) .. "].")
            return false
        end

        local last_key = tostring(get_saved_value(save_keys.last_travel_anchor_key, "") or "")
        for attempt = 1, math.min(CONFIG.MAX_RELOCATION_ATTEMPTS, #anchors) do
            local anchor = anchors[cm:random_number(#anchors, 1)]
            if #anchors == 1 or anchor.key ~= last_key or attempt == CONFIG.MAX_RELOCATION_ATTEMPTS then
                local x, y, radius = resolve_spawn_position(player_faction:name(), anchor)
                if x and y then
                    cm:teleport_to(cm:char_lookup_str(player_general:command_queue_index()), x, y)
                    set_saved_value(save_keys.last_travel_anchor_key, anchor.key)
                    log(
                        "Relocated player near static travel anchor. reason=["
                            .. tostring(reason)
                            .. "], anchor_key=["
                            .. tostring(anchor.key)
                            .. "], anchor_faction=["
                            .. tostring(anchor.faction_key)
                            .. "], anchor_x=["
                            .. tostring(anchor.x)
                            .. "], anchor_y=["
                            .. tostring(anchor.y)
                            .. "], radius=["
                            .. tostring(radius)
                            .. "], x=["
                            .. tostring(x)
                            .. "], y=["
                            .. tostring(y)
                            .. "]."
                    )
                    return true
                end
            end
        end

        log("Static travel anchor relocation failed to resolve a valid spawn position. reason=[" .. tostring(reason) .. "].")
        return false
    end

    return self
end

return travel_anchor_manager
