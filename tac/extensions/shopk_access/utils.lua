-- ShopK Access Extension - Utility Functions
-- Core utilities for time, formatting, and basic functions

local utils = {}

--- Check if a card is expired
-- @param cardData table - card data with expiration field
-- @return boolean - true if expired
function utils.isCardExpired(cardData)
    if not cardData.expiration then
        return false  -- No expiration = permanent card
    end
    return os.epoch("utc") > cardData.expiration
end

--- Format expiration time for display
-- @param timestamp number - expiration timestamp
-- @return string - formatted time
function utils.formatExpiration(timestamp)
    if not timestamp then
        return "Never"
    end
    local date = os.date("*t", timestamp / 1000)  -- Convert from epoch milliseconds
    return string.format("%04d-%02d-%02d %02d:%02d", 
        date.year, date.month, date.day, date.hour, date.min)
end

--- Get days until expiration
-- @param timestamp number - expiration timestamp
-- @return number - days until expiration (negative if expired)
function utils.getDaysUntilExpiration(timestamp)
    if not timestamp then
        return math.huge  -- Never expires
    end
    local now = os.epoch("utc")
    return math.floor((timestamp - now) / (24 * 60 * 60 * 1000))
end

return utils