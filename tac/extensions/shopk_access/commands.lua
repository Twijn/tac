--[[
    ShopK Access Extension - Command Handlers
    
    Command implementations for shop management. Handles all CLI commands
    for configuring and managing the ShopK integration.
    
    @module tac.extensions.shopk_access.commands
    @author Twijn
]]

local config = require("tac.extensions.shopk_access.config")
local slots = require("tac.extensions.shopk_access.slots")
local ui = require("tac.extensions.shopk_access.ui")
local shop = require("tac.extensions.shopk_access.shop")
local utils = require("tac.extensions.shopk_access.utils")
local subscriptions = require("tac.extensions.shopk_access.subscriptions")
local interactive_list = require("tac.lib.interactive_list")

local commands = {}

--- Handle shop command
-- @param args table - command arguments
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.handleShopCommand(args, tac, d)
    local cmd = (args[1] or "status"):lower()
    
    if cmd == "config" then
        -- Use FormUI for configuration
        ui.showConfigForm(tac, d)
        
    elseif cmd == "start" then
        if shop.isRunning() then
            d.mess("Shop is already running")
        else
            local ACCESS_CONFIG = config.get()
            if not ACCESS_CONFIG.private_key or ACCESS_CONFIG.private_key == "" then
                d.err("No private key configured! Use 'shop config' first.")
            else
                shop.startShop(tac)
            end
        end
        
    elseif cmd == "stop" then
        shop.stopShop(d)
        
    elseif cmd == "restart" then
        d.mess("Restarting shop...")
        shop.stopShop(d)
        os.sleep(1) -- Give it a moment to fully stop
        
        local ACCESS_CONFIG = config.get()
        if not ACCESS_CONFIG.private_key or ACCESS_CONFIG.private_key == "" then
            d.err("No private key configured! Use 'shop config' first.")
        else
            shop.startShop(tac)
            d.mess("Shop restarted")
        end
        
    elseif cmd == "status" then
        commands.showStatus(tac, d)
        
    elseif cmd == "tiers" then
        commands.handleTiersCommand(args, tac, d)
        
    elseif cmd == "sales" then
        commands.showSales(tac, d)
        
    elseif cmd == "subscriptions" then
        commands.handleSubscriptionsCommand(args, tac, d)
        
    elseif cmd == "cleanup" then
        commands.cleanupExpired(tac, d)
        
    elseif cmd == "reset" then
        commands.resetData(tac, d)
        
    else
        d.err("Unknown shop command! Use: config, start, stop, restart, status, tiers, sales, subscriptions, cleanup, reset")
    end
end

--- Show shop status
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.showStatus(tac, d)
    local status = shop.getStatus(tac)
    
    d.mess("=== ShopK Status ===")
    d.mess("Running: " .. (status.running and "Yes" or "No"))
    d.mess("Private Key: " .. (status.privateKeyConfigured and "Configured" or "Not configured"))
    
    if status.address then
        d.mess("Shop Address: " .. status.address)
    end
    
    -- Show sync node configuration
    local syncNode = tac.settings.get("shopk_syncNode")
    if syncNode then
        d.mess("Sync Node: " .. syncNode)
    else
        d.mess("Sync Node: (default)")
    end
end

--- Handle tiers subcommand
-- @param args table - command arguments
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.handleTiersCommand(args, tac, d)
    local subcmd = (args[2] or "list"):lower()
    
    if subcmd == "list" then
        commands.listTiers(tac, d)
    elseif subcmd == "add" then
        ui.addTierForm(tac, d)
    elseif subcmd == "edit" then
        ui.showTierMenu(tac, d)
    elseif subcmd == "remove" then
        commands.removeTier(args, tac, d)
    else
        d.err("Unknown tiers command! Use: list, add, edit, remove")
    end
end

--- List all tiers
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.listTiers(tac, d)
    local ACCESS_CONFIG = config.get()
    
    -- Build list of tiers with their data
    local tiersList = {}
    for pattern, tier in pairs(ACCESS_CONFIG.subscription_tiers) do
        local availableSlots, occupiedSlots = slots.getAvailableSlots(tac, pattern)
        local allMatchingTags = slots.getAllMatchingTags(tac, pattern)
        local totalSlots = 0
        for _ in pairs(allMatchingTags) do
            totalSlots = totalSlots + 1
        end
        
        table.insert(tiersList, {
            pattern = pattern,
            tier = tier,
            availableSlots = availableSlots,
            occupiedSlots = occupiedSlots,
            totalSlots = totalSlots
        })
    end
    
    -- Sort by tier name
    table.sort(tiersList, function(a, b)
        return a.tier.name < b.tier.name
    end)
    
    if #tiersList == 0 then
        d.mess("No subscription tiers configured")
        return
    end
    
    -- Show interactive list
    interactive_list.show({
        title = "Subscription Tiers",
        items = tiersList,
        formatItem = function(item)
            local occupied = item.totalSlots - #item.availableSlots
            return string.format("%s (%d/%d slots)", item.tier.name, occupied, item.totalSlots)
        end,
        formatDetails = function(item)
            local details = {}
            table.insert(details, "Name: " .. item.tier.name)
            table.insert(details, "Pattern: " .. item.pattern)
            table.insert(details, "Category: " .. item.tier.category)
            table.insert(details, "Description: " .. item.tier.description)
            table.insert(details, "")
            table.insert(details, string.format("Price: %d %s", item.tier.price, ACCESS_CONFIG.general_settings.currency_name))
            table.insert(details, string.format("Renewal: %d %s", item.tier.renewal_price, ACCESS_CONFIG.general_settings.currency_name))
            table.insert(details, string.format("Duration: %d days", item.tier.duration))
            table.insert(details, "")
            
            local occupied = item.totalSlots - #item.availableSlots
            table.insert(details, string.format("Slots: %d available, %d occupied, %d total", 
                #item.availableSlots, occupied, item.totalSlots))
            
            if #item.availableSlots > 0 then
                table.insert(details, "")
                table.insert(details, "Available Slots:")
                for i = 1, math.min(10, #item.availableSlots) do
                    table.insert(details, "  " .. item.availableSlots[i])
                end
                if #item.availableSlots > 10 then
                    table.insert(details, "  ... and " .. (#item.availableSlots - 10) .. " more")
                end
            end
            
            return details
        end
    })
end

--- Remove a tier
-- @param args table - command arguments
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.removeTier(args, tac, d)
    local pattern = args[3]
    if not pattern then
        d.err("Usage: shop tiers remove <pattern>")
        return
    end
    
    if not config.removeTier(pattern) then
        d.err("Tier not found: " .. pattern)
        return
    end
    
    config.save(tac)
    d.mess("Tier removed: " .. pattern)
end

--- Show sales data
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.showSales(tac, d)
    local sales_data = tac.settings.get("shopk_sales") or {}
    
    d.mess("=== Sales Summary ===")
    if next(sales_data) then
        for sku, count in pairs(sales_data) do
            d.mess(sku .. ": " .. count .. " sold")
        end
    else
        d.mess("No sales recorded yet")
    end
end

--- Handle subscriptions subcommand
-- @param args table - command arguments
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.handleSubscriptionsCommand(args, tac, d)
    local subcmd = (args[2] or "list"):lower()
    
    if subcmd == "list" then
        commands.listAllSubscriptions(tac, d)
    elseif subcmd == "active" then
        commands.listActiveSubscriptions(tac, d)
    elseif subcmd == "expired" then
        commands.listExpiredSubscriptions(tac, d)
    elseif subcmd == "cancel" then
        commands.cancelSubscriptionInteractive(args, tac, d)
    elseif subcmd == "cleanup" then
        commands.cleanupExpiredSubscriptions(args, tac, d)
    else
        d.err("Usage: shop subscriptions <list|active|expired|cancel|cleanup>")
        d.mess("  list    - Show all subscriptions (active and expired)")
        d.mess("  active  - Show only active subscriptions")
        d.mess("  expired - Show only expired subscriptions")
        d.mess("  cancel  - Cancel a subscription (with refund options)")
        d.mess("  cleanup - Remove old expired subscriptions")
        d.mess("")
        d.mess("EXPIRATION INFO:")
        d.mess("  When a subscription expires, the card remains in the system")
        d.mess("  but access is automatically revoked. The cardholder can:")
        d.mess("  - Renew via ShopK (if enabled)")
        d.mess("  - Request renewal from an admin")
        d.mess("  - Purchase a new subscription")
        d.mess("")
        d.mess("  To permanently remove expired cards, use 'shop subscriptions cleanup'")
    end
end

--- Show all subscriptions (active and expired)
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.listAllSubscriptions(tac, d)
    local active = subscriptions.getActiveSubscriptions(tac)
    local expired = subscriptions.getExpiredSubscriptions(tac)
    
    -- Combine both lists
    local allSubs = {}
    for _, sub in ipairs(active) do
        table.insert(allSubs, {
            cardData = sub.cardData,
            tier = sub.tier,
            daysRemaining = sub.daysRemaining,
            daysExpired = nil,
            isExpired = false
        })
    end
    for _, sub in ipairs(expired) do
        table.insert(allSubs, {
            cardData = sub.cardData,
            tier = nil,
            daysRemaining = nil,
            daysExpired = sub.daysExpired,
            isExpired = true
        })
    end
    
    if #allSubs == 0 then
        d.mess("No subscriptions found")
        return
    end
    
    -- Sort: active first (by days remaining), then expired (by days expired)
    table.sort(allSubs, function(a, b)
        if a.isExpired ~= b.isExpired then
            return not a.isExpired -- Active first
        end
        if a.isExpired then
            return a.daysExpired < b.daysExpired -- Most recently expired first
        else
            return a.daysRemaining < b.daysRemaining -- Soonest expiration first
        end
    end)
    
    local ACCESS_CONFIG = config.get()
    
    interactive_list.show({
        title = string.format("All Subscriptions (Active: %d, Expired: %d)", #active, #expired),
        items = allSubs,
        formatItem = function(item)
            local cardData = item.cardData
            if item.isExpired then
                return string.format("[EXPIRED] %s (%d days ago)", 
                    cardData.name or "Unknown",
                    item.daysExpired)
            else
                local tier = item.tier
                local expiryBadge = item.daysRemaining <= 7 and " [!]" or ""
                return string.format("%s - %s (%dd)%s", 
                    cardData.name or "Unknown",
                    tier and tier.name or "Unknown",
                    item.daysRemaining,
                    expiryBadge)
            end
        end,
        formatDetails = function(item)
            local cardData = item.cardData
            local details = {}
            
            table.insert(details, "Name: " .. (cardData.name or "Unknown"))
            
            if item.isExpired then
                table.insert(details, "Status: EXPIRED")
                table.insert(details, "")
                table.insert(details, "Expired: " .. utils.formatExpiration(cardData.expiration))
                table.insert(details, string.format("Days Ago: %d", item.daysExpired))
                table.insert(details, "")
                table.insert(details, "WHAT HAPPENS WHEN EXPIRED:")
                table.insert(details, "- Card remains in system but access is revoked")
                table.insert(details, "- Cardholder can renew via ShopK or request renewal")
                table.insert(details, "- Use 'shop subscriptions cleanup' to permanently remove")
            else
                local tier = item.tier
                table.insert(details, "Status: ACTIVE")
                table.insert(details, "Type: " .. (tier and tier.name or "Unknown"))
                table.insert(details, "Category: " .. (tier and tier.category or "Unknown"))
                table.insert(details, "")
                table.insert(details, "Expires: " .. utils.formatExpiration(cardData.expiration))
                table.insert(details, string.format("Days Remaining: %d", item.daysRemaining))
                
                if item.daysRemaining <= 7 then
                    table.insert(details, "WARNING: Expiring soon!")
                end
                
                table.insert(details, "")
                
                if cardData.metadata and cardData.metadata.purchaseValue then
                    table.insert(details, string.format("Original Purchase: %d %s", 
                        cardData.metadata.purchaseValue, 
                        ACCESS_CONFIG.general_settings.currency_name))
                end
                
                if tier then
                    table.insert(details, string.format("Renewal Price: %d %s", 
                        tier.renewal_price, 
                        ACCESS_CONFIG.general_settings.currency_name))
                end
            end
            
            if cardData.username then
                table.insert(details, "")
                table.insert(details, "Username: " .. cardData.username)
            end
            
            if cardData.id then
                table.insert(details, "")
                table.insert(details, "Card ID:")
                table.insert(details, "  " .. cardData.id)
            end
            
            return details
        end
    })
end

--- Show active subscriptions
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.listActiveSubscriptions(tac, d)
    local active = subscriptions.getActiveSubscriptions(tac)
    
    if #active == 0 then
        d.mess("No active subscriptions found")
        return
    end
    
    -- Sort by days remaining (soonest expiration first)
    table.sort(active, function(a, b)
        return a.daysRemaining < b.daysRemaining
    end)
    
    local ACCESS_CONFIG = config.get()
    
    interactive_list.show({
        title = string.format("Active Subscriptions (%d)", #active),
        items = active,
        formatItem = function(item)
            local cardData = item.cardData
            local tier = item.tier
            local expiryBadge = item.daysRemaining <= 7 and " [!]" or ""
            return string.format("%s - %s (%dd)%s", 
                cardData.name or "Unknown",
                tier and tier.name or "Unknown",
                item.daysRemaining,
                expiryBadge)
        end,
        formatDetails = function(item)
            local cardData = item.cardData
            local tier = item.tier
            local details = {}
            
            table.insert(details, "Name: " .. (cardData.name or "Unknown"))
            table.insert(details, "Type: " .. (tier and tier.name or "Unknown"))
            table.insert(details, "Category: " .. (tier and tier.category or "Unknown"))
            table.insert(details, "")
            table.insert(details, "Expires: " .. utils.formatExpiration(cardData.expiration))
            table.insert(details, string.format("Days Remaining: %d", item.daysRemaining))
            
            if item.daysRemaining <= 7 then
                table.insert(details, "WARNING: Expiring soon!")
            end
            
            table.insert(details, "")
            
            if cardData.metadata and cardData.metadata.purchaseValue then
                table.insert(details, string.format("Original Purchase: %d %s", 
                    cardData.metadata.purchaseValue, 
                    ACCESS_CONFIG.general_settings.currency_name))
            end
            
            if tier then
                table.insert(details, string.format("Renewal Price: %d %s", 
                    tier.renewal_price, 
                    ACCESS_CONFIG.general_settings.currency_name))
            end
            
            if cardData.username then
                table.insert(details, "Username: " .. cardData.username)
            end
            
            if cardData.id then
                table.insert(details, "")
                table.insert(details, "Card ID:")
                table.insert(details, "  " .. cardData.id)
            end
            
            return details
        end
    })
end

--- Show expired subscriptions
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.listExpiredSubscriptions(tac, d)
    local expired = subscriptions.getExpiredSubscriptions(tac)
    
    if #expired == 0 then
        d.mess("No expired subscriptions found")
        return
    end
    
    -- Sort by days expired (most recently expired first)
    table.sort(expired, function(a, b)
        return a.daysExpired < b.daysExpired
    end)
    
    interactive_list.show({
        title = string.format("Expired Subscriptions (%d)", #expired),
        items = expired,
        formatItem = function(item)
            local cardData = item.cardData
            return string.format("%s (%d days ago)", 
                cardData.name or "Unknown",
                item.daysExpired)
        end,
        formatDetails = function(item)
            local cardData = item.cardData
            local details = {}
            
            table.insert(details, "Name: " .. (cardData.name or "Unknown"))
            table.insert(details, "")
            table.insert(details, "Expired: " .. utils.formatExpiration(cardData.expiration))
            table.insert(details, string.format("Days Ago: %d", item.daysExpired))
            
            if cardData.username then
                table.insert(details, "")
                table.insert(details, "Username: " .. cardData.username)
            end
            
            if cardData.id then
                table.insert(details, "")
                table.insert(details, "Card ID:")
                table.insert(details, "  " .. cardData.id)
            end
            
            table.insert(details, "")
            table.insert(details, "Use 'shop subscriptions cleanup' to remove old expired subscriptions")
            
            return details
        end
    })
end

--- Interactive subscription cancellation
-- @param args table - command arguments
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.cancelSubscriptionInteractive(args, tac, d)
    local active = subscriptions.getActiveSubscriptions(tac)
    
    if #active == 0 then
        d.mess("No active subscriptions to cancel")
        return
    end
    
    -- Show list of active subscriptions
    d.mess("=== Cancel Subscription ===")
    for i, sub in ipairs(active) do
        local cardData = sub.cardData
        local tier = sub.tier
        d.mess(string.format("%d. %s (%s, %d days remaining)", 
            i, cardData.name or "Unknown", 
            tier and tier.name or "Unknown", 
            sub.daysRemaining))
    end
    
    d.mess("")
    d.mess("Enter subscription number to cancel (1-" .. #active .. ") or 'q' to quit:")
    
    local input = read()
    if input == "q" then
        d.mess("Cancelled")
        return
    end
    
    local index = tonumber(input)
    if not index or index < 1 or index > #active then
        d.err("Invalid selection")
        return
    end
    
    local selectedSub = active[index]
    
    -- Show refund calculation
    d.mess("")
    d.mess("=== Refund Calculation ===")
    local refundAmount, refundReason = subscriptions.calculateRefund(selectedSub, os.epoch("utc"))
    d.mess(string.format("Refund Amount: %d %s", refundAmount, config.get().general_settings.currency_name))
    d.mess(string.format("Reason: %s", refundReason))
    
    d.mess("")
    d.mess("Confirm cancellation? (y/N):")
    local confirm = read()
    
    if confirm:lower() ~= "y" and confirm:lower() ~= "yes" then
        d.mess("Cancellation aborted")
        return
    end
    
    local success, message, actualRefund = subscriptions.cancelSubscription(tac, selectedSub.cardId, "Manual cancellation", true)
    
    if success then
        d.mess("SUCCESS: " .. message)
        if actualRefund > 0 then
            -- Check if we have the original transaction's from address
            local fromAddress = selectedSub.cardData.metadata and selectedSub.cardData.metadata.fromAddress
            
            if fromAddress and shop.canSendRefunds() then
                d.mess(string.format("Processing refund: %d %s to %s", actualRefund, config.get().general_settings.currency_name, fromAddress))
                
                -- Send the actual refund
                shop.sendRefund(fromAddress, actualRefund, "Subscription cancellation refund", function(refundSuccess, refundMessage, transaction)
                    if refundSuccess then
                        d.mess("Refund sent successfully!")
                        if transaction and transaction.id then
                            d.mess("Transaction ID: " .. transaction.id)
                        end
                    else
                        d.err("Refund failed: " .. refundMessage)
                        d.mess(string.format("Manual refund required: %d %s to %s", actualRefund, config.get().general_settings.currency_name, fromAddress))
                    end
                end)
            else
                if not fromAddress then
                    d.mess(string.format("MANUAL REFUND REQUIRED: %.02f %s", actualRefund, config.get().general_settings.currency_name))
                    d.mess("Reason: Original transaction address not found in card metadata")
                    d.mess("Please refund manually to: " .. (selectedSub.cardData.username or "customer"))
                elseif not shop.canSendRefunds() then
                    d.mess(string.format("MANUAL REFUND REQUIRED: %.02f %s to %s", actualRefund, config.get().general_settings.currency_name, fromAddress))
                    d.mess("Reason: Shop is not running or cannot send transactions")
                end
            end
        end
    else
        d.err("FAILED: " .. message)
    end
end

--- Clean up expired subscriptions
-- @param args table - command arguments  
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.cleanupExpiredSubscriptions(args, tac, d)
    local maxAge = tonumber(args[3]) or 30
    
    d.mess(string.format("Cleaning up subscriptions expired more than %d days ago...", maxAge))
    
    local removed = subscriptions.cleanupExpired(tac, maxAge)
    
    d.mess(string.format("Cleanup complete: %d expired subscriptions removed", removed))
end

--- Legacy function for compatibility
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.showSubscriptions(tac, d)
    -- Redirect to new function
    commands.listActiveSubscriptions(tac, d)
end

--- Show active subscriptions (legacy version to update)
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.showLegacySubscriptions(tac, d)
    local ACCESS_CONFIG = config.get()
    
    d.mess("=== Active Subscriptions (Legacy View) ===")
    
    for pattern, tier in pairs(ACCESS_CONFIG.subscription_tiers) do
        local active = slots.getActiveSubscriptions(tac, pattern)
        
        if #active > 0 then
            d.mess(pattern .. " (" .. #active .. " active):")
            for _, sub in ipairs(active) do
                local days = utils.getDaysUntilExpiration(sub.data.expiration)
                local timeStr = days == math.huge and "Never" or (days .. " days")
                d.mess("  " .. sub.tag .. " - " .. sub.data.name .. " (expires in " .. timeStr .. ")")
            end
        end
    end
end

--- Clean up expired cards
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.cleanupExpired(tac, d)
    local removedCount = 0
    local identitiesToRemove = {}
    
    -- Find expired identities
    for identityId, identity in pairs(tac.identities.getAll()) do
        if identity.expiration and utils.isCardExpired(identity) then
            table.insert(identitiesToRemove, {
                id = identityId,
                name = identity.name or "Unknown"
            })
        end
    end
    
    -- Remove expired identities
    for _, identityInfo in pairs(identitiesToRemove) do
        tac.identities.unset(identityInfo.id)
        removedCount = removedCount + 1
        d.mess("Removed: " .. identityInfo.name)
    end
    
    d.mess("Cleanup complete: " .. removedCount .. " expired cards removed")
end

--- Reset sales data
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.resetData(tac, d)
    tac.settings.set("shopk_sales", {})
    d.mess("Sales data reset")
end

--- Get command completions
-- @param args table - current arguments
-- @return table - completion options
function commands.getCompletions(args)
    if #args == 1 then
        return {"config", "status", "sales", "reset", "subscriptions", "cleanup", "tiers", "start", "stop", "restart"}
    elseif #args == 2 and args[1]:lower() == "tiers" then
        return {"list", "add", "remove", "edit"}
    elseif #args == 2 and args[1]:lower() == "subscriptions" then
        return {"list", "active", "expired", "cancel", "cleanup"}
    elseif #args == 3 and args[1]:lower() == "tiers" and args[2]:lower() == "remove" then
        local ACCESS_CONFIG = config.get()
        local tierNames = {}
        for pattern, _ in pairs(ACCESS_CONFIG.subscription_tiers) do
            table.insert(tierNames, pattern)
        end
        return tierNames
    end
    return {}
end

return commands