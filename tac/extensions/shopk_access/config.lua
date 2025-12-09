--[[
    ShopK Access Extension - Configuration Management
    
    Handles tier configuration, loading, and saving for ShopK access sales.
    Manages subscription tier definitions, pricing, and duration settings.
    
    @module tac.extensions.shopk_access.config
    @author Twijn
]]

local tables = require("lib.tables")
local config = {}

-- Default configuration for subscription sales (wildcard-based)
local DEFAULT_CONFIG = {
    -- Define subscription tiers and their pricing
    subscription_tiers = {
        ["tenant.*"] = {
            name = "Apartment Rental",
            category = "residential",
            price = 10,              -- 10 KRO for apartment rental
            renewal_price = 8,       -- 8 KRO to renew (20% discount)
            duration = 30,           -- 30 days subscription
            description = "Basic apartment access with storage and crafting facilities",
            features = {"Storage Access", "Crafting Tables", "Bed Spawn"},
            refund_policy = "prorated", -- full, prorated, or none
            auto_renewal = false     -- Whether to allow auto-renewal
        },
        ["shop.*"] = {
            name = "Shop License",
            category = "commercial",
            price = 15,              -- 15 KRO for shop license
            renewal_price = 12,      -- 12 KRO to renew (20% discount)
            duration = 30,           -- 30 days subscription
            description = "Commercial shop space with high-traffic location",
            features = {"Prime Location", "Large Display Area", "Storage Vault", "Advertisement Rights"},
            refund_policy = "prorated",
            auto_renewal = true
        },
        ["premium.*"] = {
            name = "Premium Access",
            category = "premium",
            price = 20,              -- 20 KRO for premium access
            renewal_price = 15,      -- 15 KRO to renew (25% discount)
            duration = 30,           -- 30 days subscription
            description = "Premium access with all available features and priority support",
            features = {"All Residential Features", "All Commercial Features", "Priority Support", "Exclusive Areas", "VIP Status"},
            refund_policy = "prorated",
            auto_renewal = true
        }
    },
    
    -- Shop configuration
    private_key = nil,
    shop_address = "YOUR_SHOP_ADDRESS_HERE",
    
    -- Refund settings
    refund_settings = {
        min_refund_amount = .5,      -- Minimum refund amount (to avoid tiny refunds)
        refund_fee_percent = 5,      -- 5% processing fee for refunds
        grace_period_hours = 24,     -- Full refund within 24 hours
        prorated_minimum_days = 3    -- Minimum days to charge for prorated refunds
    },
    
    -- General settings
    general_settings = {
        currency_name = "KRO",
        date_format = "%Y-%m-%d %H:%M",
        timezone = "UTC",
        support_contact = "Admin",
        terms_url = nil
    }
}

-- Current configuration (starts with defaults)
local SUBSCRIPTION_CONFIG = {}

-- Initialize with deep copy of defaults
SUBSCRIPTION_CONFIG = tables.recursiveCopy(DEFAULT_CONFIG)

--- Get the current configuration
-- @return table - current SUBSCRIPTION_CONFIG
function config.get()
    -- Ensure subscription_tiers exists
    if not SUBSCRIPTION_CONFIG.subscription_tiers then
        SUBSCRIPTION_CONFIG.subscription_tiers = tables.recursiveCopy(DEFAULT_CONFIG.subscription_tiers)
    end
    return SUBSCRIPTION_CONFIG
end

--- Set a configuration value
-- @param key string - configuration key
-- @param value any - configuration value
-- @param tac table|nil - TAC instance (optional, to save settings)
function config.set(key, value, tac)
    SUBSCRIPTION_CONFIG[key] = value
    if tac then
        tac.settings.set("shopk_subscription_config", SUBSCRIPTION_CONFIG)
    end
end

--- Load configuration from TAC settings
-- @param tac table - TAC instance
function config.load(tac)
    local saved = tac.settings.get("shopk_subscription_config")
    if saved then
        -- Clear existing config and copy saved values
        -- This maintains the table reference so other modules see the update
        for k in pairs(SUBSCRIPTION_CONFIG) do
            SUBSCRIPTION_CONFIG[k] = nil
        end
        for k, v in pairs(saved) do
            SUBSCRIPTION_CONFIG[k] = v
        end
        print("Loaded ShopK subscription configuration from settings")
        
        -- Ensure critical fields exist
        if not SUBSCRIPTION_CONFIG.subscription_tiers then
            SUBSCRIPTION_CONFIG.subscription_tiers = tables.recursiveCopy(DEFAULT_CONFIG.subscription_tiers)
            print("Restored missing subscription_tiers from defaults")
        end
        if not SUBSCRIPTION_CONFIG.refund_settings then
            SUBSCRIPTION_CONFIG.refund_settings = tables.recursiveCopy(DEFAULT_CONFIG.refund_settings)
            print("Restored missing refund_settings from defaults")
        end
    end
    
    -- Also load legacy configurations
    local legacy_config = tac.settings.get("shopk_access_config")
    if legacy_config and legacy_config.access_tiers then
        -- Migrate legacy access_tiers to subscription_tiers
        print("Migrating legacy configuration...")
        SUBSCRIPTION_CONFIG.subscription_tiers = legacy_config.access_tiers
        if legacy_config.private_key then
            SUBSCRIPTION_CONFIG.private_key = legacy_config.private_key
        end
        if legacy_config.shop_address then
            SUBSCRIPTION_CONFIG.shop_address = legacy_config.shop_address
        end
    end
    
    -- Load legacy private key
    local saved_key = tac.settings.get("shopk_private_key")
    if saved_key and not SUBSCRIPTION_CONFIG.private_key then
        SUBSCRIPTION_CONFIG.private_key = saved_key
    end
end

--- Save configuration to TAC settings
-- @param tac table - TAC instance
function config.save(tac)
    tac.settings.set("shopk_subscription_config", SUBSCRIPTION_CONFIG)
    if SUBSCRIPTION_CONFIG.private_key then
        tac.settings.set("shopk_private_key", SUBSCRIPTION_CONFIG.private_key)
    end
end

--- Add a new subscription tier
-- @param pattern string - tier pattern
-- @param tierData table - tier configuration
-- @return boolean - success
function config.addTier(pattern, tierData)
    if SUBSCRIPTION_CONFIG.subscription_tiers[pattern] then
        return false  -- Already exists
    end
    
    SUBSCRIPTION_CONFIG.subscription_tiers[pattern] = tierData
    return true
end

--- Remove a subscription tier
-- @param pattern string - tier pattern
-- @return boolean - success
function config.removeTier(pattern)
    if not SUBSCRIPTION_CONFIG.subscription_tiers[pattern] then
        return false  -- Doesn't exist
    end
    
    SUBSCRIPTION_CONFIG.subscription_tiers[pattern] = nil
    return true
end

--- Get a tier configuration
-- @param pattern string - tier pattern
-- @return table|nil - tier data or nil if not found
function config.getTier(pattern)
    return SUBSCRIPTION_CONFIG.subscription_tiers[pattern]
end

--- Get all tiers
-- @return table - all tier configurations
function config.getAllTiers()
    return SUBSCRIPTION_CONFIG.subscription_tiers
end

--- Find tier matching a specific tag
-- @param tag string - specific tag to match
-- @return string|nil, table|nil - pattern and tier data if found
function config.findTierForTag(tag)
    for pattern, tier in pairs(SUBSCRIPTION_CONFIG.subscription_tiers) do
        local pattern_regex = "^" .. pattern:gsub("%*", ".*") .. "$"
        if tag:match(pattern_regex) then
            return pattern, tier
        end
    end
    return nil, nil
end

--- Reset configuration to defaults
function config.reset()
    -- Clear and repopulate to maintain table reference
    for k in pairs(SUBSCRIPTION_CONFIG) do
        SUBSCRIPTION_CONFIG[k] = nil
    end
    local defaults = tables.recursiveCopy(DEFAULT_CONFIG)
    for k, v in pairs(defaults) do
        SUBSCRIPTION_CONFIG[k] = v
    end
end

--- Create a new tier with validation
-- @param pattern string - tier pattern (e.g., "apartment.*")
-- @param options table - tier options
-- @return boolean, string - success, error message
function config.createTier(pattern, options)
    if not pattern or not options then
        return false, "Pattern and options are required"
    end
    
    if SUBSCRIPTION_CONFIG.subscription_tiers[pattern] then
        return false, "Tier already exists: " .. pattern
    end
    
    -- Validate required fields
    local required = {"name", "price", "duration", "description"}
    for _, field in ipairs(required) do
        if not options[field] then
            return false, "Missing required field: " .. field
        end
    end
    
    -- Set defaults for optional fields
    local tierData = {
        name = options.name,
        category = options.category or "general",
        price = options.price,
        renewal_price = options.renewal_price or math.floor(options.price * 0.9), -- 10% discount default
        duration = options.duration,
        description = options.description,
        features = options.features or {},
        refund_policy = options.refund_policy or "prorated",
        auto_renewal = options.auto_renewal or false
    }
    
    SUBSCRIPTION_CONFIG.subscription_tiers[pattern] = tierData
    return true, nil
end

return config