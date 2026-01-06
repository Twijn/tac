-- Shared ShopK utilities for TAC extensions
-- Provides common access to shop data, configuration, and status

local shopk_shared = {}

-- Cache for shop instance and data
local cached_shop = nil
local cached_config = nil
local last_config_check = 0

--- Get the current ShopK configuration
-- @param tac table - TAC instance (optional, for settings fallback)
-- @return table - configuration data
function shopk_shared.getConfig(tac)
    local current_time = os.epoch("utc")
    
    -- Cache config for 1 second to avoid repeated file reads
    if cached_config and (current_time - last_config_check) < 1000 then
        return cached_config
    end
    
    -- Try to get from shopk_access extension first
    local shopk_ext = tac and tac.extensions and tac.extensions.shopk_access
    if shopk_ext then
        local success, config_module = pcall(require, "tac.extensions.shopk_access.config")
        if success and config_module then
            cached_config = config_module.get()
            last_config_check = current_time
            return cached_config
        end
    end
    
    -- Fallback to settings if extension not available
    if tac then
        -- Try new config format first, then legacy
        cached_config = tac.settings.get("shopk_subscription_config") or tac.settings.get("shopk_access_config") or {}
        last_config_check = current_time
        return cached_config
    end
    
    -- Return empty config if nothing available
    return {}
end

--- Get shop status and data
-- @param tac table - TAC instance
-- @return table - shop status {running, address, tiers}
function shopk_shared.getShopData(tac)
    local config = shopk_shared.getConfig(tac)
    
    local shopData = {
        running = false,
        address = nil,
        tiers = config.subscription_tiers or config.access_tiers or {}
    }
    
    -- Try to get live status from shop module
    local shopk_ext = tac and tac.extensions and tac.extensions.shopk_access
    if shopk_ext then
        local success, shop_module = pcall(require, "tac.extensions.shopk_access.shop")
        if success and shop_module and shop_module.getStatus then
            local status = shop_module.getStatus(tac)
            shopData.running = status.running or false
            shopData.address = status.address or config.shop_address
        end
    end
    
    -- Fallback: use config address if no live status
    if not shopData.address then
        shopData.address = config.shop_address
    end
    
    -- Simple running check if no live status available
    if not shopData.running and shopData.address and shopData.address ~= "" then
        shopData.running = true  -- Assume running if address is configured
    end
    
    return shopData
end

--- Check if shop is properly configured
-- @param tac table - TAC instance
-- @return boolean - true if shop has required configuration
function shopk_shared.isConfigured(tac)
    local config = shopk_shared.getConfig(tac)
    return config.private_key and config.private_key ~= "" and 
           config.shop_address and config.shop_address ~= ""
end

--- Get available slots for a tier pattern
-- @param tac table - TAC instance
-- @param pattern string - tier pattern (e.g., "tenant.*")
-- @return number - available slots count
function shopk_shared.getAvailableSlots(tac, pattern)
    if not tac or not pattern then return 0 end
    
    local pattern_regex = "^" .. pattern:gsub("%*", ".*") .. "$"
    local allTags = {}
    local occupiedTags = {}
    
    -- Find all matching tags in identities and doors
    for identityId, identity in pairs(tac.identities.getAll()) do
        if identity.tags then
            for _, tag in ipairs(identity.tags) do
                if tag:match(pattern_regex) then
                    allTags[tag] = true
                    -- Check if occupied (non-expired)
                    if not identity.expiration or os.epoch("utc") <= identity.expiration then
                        occupiedTags[tag] = true
                    end
                end
            end
        end
    end
    
    for doorId, doorData in pairs(tac.doors.getAll()) do
        if doorData.tags then
            for _, tag in ipairs(doorData.tags) do
                if tag:match(pattern_regex) then
                    allTags[tag] = true
                end
            end
        end
    end
    
    -- Count available slots
    local available = 0
    for tag, _ in pairs(allTags) do
        if not occupiedTags[tag] then
            available = available + 1
        end
    end
    
    return available
end

--- Format payment metadata for a tier
-- @param pattern string - tier pattern
-- @param tier table - tier data
-- @return string - formatted metadata
function shopk_shared.formatPaymentMeta(pattern, tier)
    -- Generate simple SKU from pattern - just use the first part before the dot
    local sku = pattern:match("([^%.]+)") or pattern
    sku = sku:gsub("[^%w]", ""):lower() -- Remove special chars, make lowercase
    
    -- No manual tag needed - plugin will provide username automatically
    return "sku=" .. sku
end

--- Clear cached data (useful for testing or config changes)
function shopk_shared.clearCache()
    cached_shop = nil
    cached_config = nil
    last_config_check = 0
end

return shopk_shared