-- ShopK Access Extension - Slot Management
-- Handles slot discovery, availability checking, and assignment

local utils = require("tac.extensions.shopk_access.utils")

local slots = {}

--- Find all tags that exist in the system matching a pattern
-- @param tac table - TAC instance
-- @param pattern string - wildcard pattern (e.g., "tenant.*")
-- @return table - set of matching tags
function slots.getAllMatchingTags(tac, pattern)
    local matchingTags = {}
    local pattern_regex = "^" .. pattern:gsub("%*", ".*") .. "$"
    
    -- Check all existing cards for matching tags
    for cardId, cardData in pairs(tac.cards.getAll()) do
        if cardData.tags then
            for _, tag in ipairs(cardData.tags) do
                if tag:match(pattern_regex) then
                    matchingTags[tag] = true  -- Use set to avoid duplicates
                end
            end
        end
    end
    
    -- Also check all doors for matching tags
    for doorId, doorData in pairs(tac.doors.getAll()) do
        if doorData.tags then
            for _, tag in ipairs(doorData.tags) do
                if tag:match(pattern_regex) then
                    matchingTags[tag] = true
                end
            end
        end
    end
    
    return matchingTags
end

--- Get available slots for a tier pattern
-- @param tac table - TAC instance
-- @param pattern string - wildcard pattern
-- @return table, table - available slots array, occupied slots map
function slots.getAvailableSlots(tac, pattern)
    local allTags = slots.getAllMatchingTags(tac, pattern)
    local availableSlots = {}
    local occupiedSlots = {}
    
    -- Check which tags have active (non-expired) cards
    for cardId, cardData in pairs(tac.cards.getAll()) do
        if cardData.tags then
            for _, tag in ipairs(cardData.tags) do
                if allTags[tag] and (not cardData.expiration or not utils.isCardExpired(cardData)) then
                    occupiedSlots[tag] = {
                        id = cardId,
                        data = cardData,
                        tag = tag
                    }
                end
            end
        end
    end
    
    -- Find available slots (tags that exist but don't have active cards)
    for tag, _ in pairs(allTags) do
        if not occupiedSlots[tag] then
            table.insert(availableSlots, tag)
        end
    end
    
    return availableSlots, occupiedSlots
end

--- Get active subscriptions for a pattern (for backward compatibility)
-- @param tac table - TAC instance
-- @param pattern string - wildcard pattern
-- @return table - array of active subscription info
function slots.getActiveSubscriptions(tac, pattern)
    local _, occupied = slots.getAvailableSlots(tac, pattern)
    local active = {}
    for _, slot in pairs(occupied) do
        table.insert(active, slot)
    end
    return active
end

--- Get next available slot for a tier pattern
-- @param tac table - TAC instance
-- @param pattern string - wildcard pattern
-- @return string|nil - next available tag or nil if none available
function slots.getNextAvailableSlot(tac, pattern)
    local availableSlots, _ = slots.getAvailableSlots(tac, pattern)
    
    if #availableSlots > 0 then
        -- Return the first available slot
        return availableSlots[1]
    end
    
    return nil  -- No slots available
end

return slots