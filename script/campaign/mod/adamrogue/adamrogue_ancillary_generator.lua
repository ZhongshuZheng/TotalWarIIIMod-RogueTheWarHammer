local ancillary_generator = {}

function ancillary_generator.new(context)
    local self = {}
    local log = context.log
    local cm = context.cm
    local pool = context.pool
    local battle_tier_keys = context.battle_tier
    local rarity_keys = context.equipment_rarity
    local slot_order = context.slot_order

    function self.pick_rarity_band_for_tier(battle_tier)
        local roll = cm:random_number(100, 1)
        local rarity = rarity_keys.COMMON

        if battle_tier >= battle_tier_keys.LATE then
            if roll <= 50 then
                rarity = rarity_keys.RARE
            elseif roll <= 85 then
                rarity = rarity_keys.UNCOMMON
            else
                rarity = rarity_keys.COMMON
            end
        elseif battle_tier >= battle_tier_keys.MID then
            if roll <= 65 then
                rarity = rarity_keys.UNCOMMON
            else
                rarity = rarity_keys.COMMON
            end
        end

        log(
            "pick_equipment_rarity_band_for_tier resolved rarity=["
                .. tostring(rarity)
                .. "] from battle_tier=["
                .. tostring(battle_tier)
                .. "], roll=["
                .. tostring(roll)
                .. "]."
        )
        return rarity
    end

    function self.get_allowed_rarity_bands_for_tier(battle_tier)
        if battle_tier >= battle_tier_keys.LATE then
            return { rarity_keys.COMMON, rarity_keys.UNCOMMON, rarity_keys.RARE }
        elseif battle_tier >= battle_tier_keys.MID then
            return { rarity_keys.COMMON, rarity_keys.UNCOMMON }
        end

        return { rarity_keys.COMMON }
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

    function self.build_weighted_pool_for_slot(slot_key, battle_tier, allowed_bands)
        local weighted_pool = {}

        for _, entry in ipairs(pool) do
            if entry.enabled
                and entry.reward_slot == slot_key
                and battle_tier >= entry.min_battle_tier
                and battle_tier <= entry.max_battle_tier
                and rarity_band_allowed(entry.item_rarity, allowed_bands) then
                for _ = 1, entry.weight do
                    weighted_pool[#weighted_pool + 1] = entry
                end
            end
        end

        log(
            "build_weighted_pool_for_slot completed. slot=["
                .. tostring(slot_key)
                .. "], battle_tier=["
                .. tostring(battle_tier)
                .. "], allowed_bands=["
                .. tostring(allowed_bands and table.concat(allowed_bands, ",") or "all")
                .. "], weighted_pool_size=["
                .. tostring(#weighted_pool)
                .. "]."
        )
        return weighted_pool
    end

    function self.generate_equipment_reward_payload(completed_battle_count, battle_tier)
        local selected_rarity_band = self.pick_rarity_band_for_tier(battle_tier)
        local tier_allowed_bands = self.get_allowed_rarity_bands_for_tier(battle_tier)
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
            candidate_count = 0
        }

        log(
            "generate_equipment_reward_payload started. completed_battle_count=["
                .. tostring(completed_battle_count)
                .. "], battle_tier=["
                .. tostring(battle_tier)
                .. "], selected_rarity_band=["
                .. tostring(selected_rarity_band)
                .. "], generation_seed=["
                .. tostring(generation_seed)
                .. "]."
        )

        -- Dilemma buttons are static, so each choice is bound to a fixed slot category and
        -- the exact ancillary key is carried in the saved payload for grant/resume correctness.
        for choice_index, slot_key in ipairs(slot_order) do
            local zero_based_choice = choice_index - 1
            local weighted_pool = self.build_weighted_pool_for_slot(slot_key, battle_tier, { selected_rarity_band })

            if #weighted_pool == 0 then
                fallback_steps[#fallback_steps + 1] = tostring(slot_key) .. ":expand_to_tier_allowed_rarities"
                weighted_pool = self.build_weighted_pool_for_slot(slot_key, battle_tier, tier_allowed_bands)
            end

            if #weighted_pool == 0 then
                fallback_steps[#fallback_steps + 1] = tostring(slot_key) .. ":expand_to_any_tier_item"
                weighted_pool = self.build_weighted_pool_for_slot(slot_key, battle_tier, nil)
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
