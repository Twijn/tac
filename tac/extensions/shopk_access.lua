--[[
    TAC ShopK Access Extension
    
    Sells access tags as SKUs via ShopK/Kromer payments. Integrates with ShopK
    to allow users to purchase access tags through the Kromer payment system.
    Modular version using separate modules for different functionality.
    
    @module tac.extensions.shopk_access
    @author Twijn
    @version 1.4.3
    
    @example
    -- This extension is loaded automatically by TAC.
    -- Once loaded, it provides ShopK integration commands:
    
    -- In TAC shell:
    -- > shopk help              -- Show available commands
    -- > shopk slot add tenant.1 Premium Access 500 30
    -- > shopk slot list         -- List all configured slots
    -- > shopk start             -- Start the ShopK shop
    
    -- From another extension:
    function MyExtension.init(tac)
        -- Wait for shopk_access to load, then use its functionality
        local shopk = tac.require("shopk_access")
        if shopk then
            print("ShopK integration available")
        end
    end
]]

local ShopKAccessExtension = {
    name = "shopk_access",
    version = "1.4.3",
    description = "Sell access tags via ShopK/Kromer payments with monitor UI",
    author = "Twijn",
    dependencies = {},
    optional_dependencies = {}
}

-- Load modules
local utils = require("tac.extensions.shopk_access.utils")
local config = require("tac.extensions.shopk_access.config")
local slots = require("tac.extensions.shopk_access.slots")
local ui = require("tac.extensions.shopk_access.ui")
local monitor_ui = require("tac.extensions.shopk_access.monitor_ui")
local shop = require("tac.extensions.shopk_access.shop")
local commands = require("tac.extensions.shopk_access.commands")

-- Module storage for cross-module access
local sales_data = {}

-- Extension initialization
-- @param tac table - TAC instance
function ShopKAccessExtension.init(tac)
    term.setTextColor(colors.magenta)
    print("*** ShopK Access Extension Loading ***")
    term.setTextColor(colors.white)
    
    -- Initialize sales tracking
    if not tac.settings.get("shopk_sales") then
        tac.settings.set("shopk_sales", {})
    end
    sales_data = tac.settings.get("shopk_sales")
    
    -- Load configuration
    config.load(tac)
    
    -- Initialize monitor UI (auto-detects monitor)
    local monitorInitialized = monitor_ui.init(tac)
    if monitorInitialized then
        print("Monitor UI initialized for interactive purchases")
        monitor_ui.startTouchListener(tac)
    end
    
    -- Auto-start shop if private key is configured
    local ACCESS_CONFIG = config.get()
    if ACCESS_CONFIG.private_key and ACCESS_CONFIG.private_key ~= "" then
        print("Private key found - auto-starting ShopK...")
        -- Start shop directly - no need for timer delay
        shop.startShop(tac)
    else
        print("No private key configured. Use 'shop config' to set up ShopK.")
    end
    
    -- Add ShopK commands
    tac.registerCommand("shop", {
        description = "Manage ShopK access sales and subscriptions",
        complete = function(args)
            return commands.getCompletions(args)
        end,
        execute = function(args, d)
            commands.handleShopCommand(args, tac, d)
        end
    })
    
    -- Add hook to check expiration before access
    tac.addHook("beforeAccess", function(card, door, data, side)
        if card and card.expiration and utils.isCardExpired(card) then
            tac.logger.logAccess("access_denied_expired", {
                card = card,
                door = door,
                message = "Access denied: Card expired"
            })
            return false, "CARD EXPIRED"  -- Deny access with message for sign
        end
        return true  -- Allow access check to continue
    end)
    
    term.setTextColor(colors.lime)
    print("ShopK Access Extension loaded successfully!")
    term.setTextColor(colors.white)
end

-- Expose some functions for compatibility (if needed)
ShopKAccessExtension.showConfigForm = ui.showConfigForm
ShopKAccessExtension.addTierForm = ui.addTierForm
ShopKAccessExtension.startShop = shop.startShop
ShopKAccessExtension.monitor_ui = monitor_ui  -- Export monitor_ui for shop_monitor coordination

return ShopKAccessExtension