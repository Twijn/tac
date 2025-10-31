--[[
    ShopK Access Extension - User Interface
    
    FormUI-based configuration interfaces for ShopK access management.
    Provides interactive forms for configuring tiers and settings.
    
    @module tac.extensions.shopk_access.ui
    @author Twijn
]]

local FormUI = require("formui")
local config = require("tac.extensions.shopk_access.config")
local slots = require("tac.extensions.shopk_access.slots")

local ui = {}

--- Main configuration form
-- @param tac table - TAC instance
-- @param d table - display interface
function ui.showConfigForm(tac, d)
    local ACCESS_CONFIG = config.get()
    local form = FormUI.new("ShopK Configuration")
    
    -- Private key field
    form:text("Private Key", ACCESS_CONFIG.private_key or "", FormUI.validation.string_nonempty)
    
    -- Shop address (read-only display)
    if ACCESS_CONFIG.shop_address then
        form:label("Shop Address: " .. ACCESS_CONFIG.shop_address)
    end
    
    -- Add tier configuration section
    form:label("=== Subscription Tiers ===")
    
    local tierCount = 0
    for pattern, tier in pairs(ACCESS_CONFIG.subscription_tiers) do
        tierCount = tierCount + 1
        form:label(string.format("%s (%s) - %s", tier.name, pattern, tier.category))
    end
    
    if tierCount == 0 then
        form:label("No tiers configured. Use 'shop tiers add' to create tiers.")
    else
        form:label(string.format("Total: %d configured tiers", tierCount))
    end
    
    local result = form:run()
    
    if result then
        -- Update private key
        config.set("private_key", result["Private Key"])
        
        -- Update tier configurations (results are in order of form fields)
        -- Note: This is a simplified approach for single tier setups
        -- For multiple tiers, individual tier editing is recommended
        
        -- Save configuration
        config.save(tac)
        
        d.mess("Configuration saved!")
        
        -- Ask if user wants to start the shop
        if result["Private Key"] and result["Private Key"] ~= "" then
            d.mess("Start the shop now? (y/n)")
            local start = read()
            if start:lower() == "y" or start:lower() == "yes" then
                -- Note: This would need to be handled by the main extension
                d.mess("Use 'shop start' to start the shop manually")
            end
        end
    else
        d.mess("Configuration cancelled")
    end
end

--- Tier selection menu
-- @param tac table - TAC instance
-- @param d table - display interface
function ui.showTierMenu(tac, d)
    local SUBSCRIPTION_CONFIG = config.get()
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        print("=== Subscription Tier Management ===")
        print("")
        
        local tiers = {}
        local index = 1
        for pattern, tier in pairs(SUBSCRIPTION_CONFIG.subscription_tiers) do
            print(string.format("%d. %s (%s) - %s", index, tier.name, pattern, tier.category))
            print(string.format("   Price: %d %s, Duration: %d days", 
                tier.price, SUBSCRIPTION_CONFIG.general_settings.currency_name, tier.duration))
            tiers[index] = {pattern = pattern, tier = tier}
            index = index + 1
        end
        
        if #tiers == 0 then
            print("No tiers configured yet.")
        end
        
        print("")
        print("Enter tier number to edit, 'a' to add new, or 'q' to quit:")
        
        local input = read()
        if input:lower() == "q" then
            break
        elseif input:lower() == "a" then
            ui.addTierForm(tac, d)
        else
            local tierIndex = tonumber(input)
            if tierIndex and tierIndex >= 1 and tierIndex <= #tiers then
                ui.editTierForm(tac, d, tiers[tierIndex].pattern, tiers[tierIndex].tier)
            else
                print("Invalid selection!")
                sleep(1)
            end
        end
    end
end

--- Form for editing existing tiers
-- @param tac table - TAC instance
-- @param d table - display interface
-- @param pattern string - tier pattern
-- @param tier table - tier data
function ui.editTierForm(tac, d, pattern, tier)
    local form = FormUI.new("Edit Tier: " .. pattern)
    
    form:label("Pattern: " .. pattern)
    form:text("Description", tier.description or "")
    form:number("Price (KRO)", tier.price, FormUI.validation.number_positive)
    form:number("Renewal (KRO)", tier.renewal_price, FormUI.validation.number_positive)
    form:number("Duration (days)", tier.duration, FormUI.validation.number_positive)
    
    local result = form:run()
    
    if result then
        tier.description = result["Description"]
        tier.price = result["Price (KRO)"]
        tier.renewal_price = result["Renewal (KRO)"]
        tier.duration = result["Duration (days)"]
        
        -- Update tier using new system
        local success, error = config.createTier(pattern, {
            name = result["Name"],
            category = result["Category"],
            price = result["Price"],
            renewal_price = result["Renewal Price"],
            duration = result["Duration"],
            description = result["Description"],
            features = {},  -- Would need to parse features from form
            max_slots = result["Max Slots"],
            refund_policy = result["Refund Policy"]
        })
        
        if success then
            config.save(tac)
            d.mess("Tier updated: " .. pattern)
        else
            d.err("Failed to update tier: " .. (error or "Unknown error"))
        end
    else
        d.mess("Edit cancelled")
    end
end

--- Comprehensive tier creation form
-- @param tac table - TAC instance
-- @param d table - display interface
function ui.addTierForm(tac, d)
    local form = FormUI.new("Create New Subscription Tier")
    
    -- Basic information
    form:label("=== Basic Information ===")
    form:label("Tier Name: e.g., 'Apartment Rental', 'Shop License'")
    form:text("Tier Name", "", FormUI.validation.string_nonempty)
    form:label("Pattern: e.g., 'apartment.*', 'shop.*', 'premium.*'")
    form:text("Pattern", "", FormUI.validation.string_nonempty)
    form:select("Category", {"residential", "commercial", "premium", "special"}, 1)
    form:label("Description: Brief description of what this tier provides")
    form:text("Description", "", FormUI.validation.string_nonempty)
    
    -- Pricing
    form:label("=== Pricing ===")
    form:label("Price: Initial purchase price in KRO")
    form:number("Price", 500, FormUI.validation.number_positive)
    form:label("Renewal Price: Usually discounted")
    form:number("Renewal Price", 450, FormUI.validation.number_positive)
    form:label("Duration: Subscription duration in days")
    form:number("Duration (days)", 30, FormUI.validation.number_positive)
    
    -- Limits
    form:label("=== Availability ===")
    form:label("Max Slots: Maximum number of available slots")
    form:number("Max Slots", 50, FormUI.validation.number_positive)
    
    -- Policies
    form:label("=== Policies ===")
    form:select("Refund Policy", {"none", "prorated", "full"}, 2)
    form:select("Auto Renewal", {"true", "false"}, 2)
    
    -- Features (simplified for now)
    local function clrValidator() return true end
    form:label("=== Features (Optional) ===")
    form:text("Feature 1", "", clrValidator)
    form:text("Feature 2", "", clrValidator)
    form:text("Feature 3", "", clrValidator)

    local result = form:run()
    
    if result then
        -- Build features list
        local features = {}
        if result["Feature 1"] and result["Feature 1"] ~= "" then
            table.insert(features, result["Feature 1"])
        end
        if result["Feature 2"] and result["Feature 2"] ~= "" then
            table.insert(features, result["Feature 2"])
        end
        if result["Feature 3"] and result["Feature 3"] ~= "" then
            table.insert(features, result["Feature 3"])
        end
        
        -- Create tier
        local success, error = config.createTier(result["Pattern"], {
            name = result["Tier Name"],
            category = result["Category"],
            price = result["Price"],
            renewal_price = result["Renewal Price"],
            duration = result["Duration (days)"],
            description = result["Description"],
            features = features,
            max_slots = result["Max Slots"],
            refund_policy = result["Refund Policy"],
            auto_renewal = result["Auto Renewal"] == "true"
        })
        
        if success then
            config.save(tac)
            d.mess("Tier created successfully: " .. result["Tier Name"])
            d.mess("Pattern: " .. result["Pattern"])
            d.mess("Use 'shop status' to see the new tier configuration")
        else
            d.err("Failed to create tier: " .. (error or "Unknown error"))
        end
    else
        d.mess("Tier creation cancelled")
    end
end

return ui