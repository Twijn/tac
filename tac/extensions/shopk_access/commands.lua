-- ShopK Access Extension - Command Handlers
-- Command implementations for shop management

local config = require("tac.extensions.shopk_access.config")
local slots = require("tac.extensions.shopk_access.slots")
local ui = require("tac.extensions.shopk_access.ui")
local shop = require("tac.extensions.shopk_access.shop")
local utils = require("tac.extensions.shopk_access.utils")
local subscriptions = require("tac.extensions.shopk_access.subscriptions")

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
        d.err("Unknown shop command! Use: config, start, stop, status, tiers, sales, subscriptions, cleanup, reset")
    end
end

--- Show shop status
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.showStatus(tac, d)
    local status = shop.getStatus(tac)
    local ACCESS_CONFIG = config.get()
    
    d.mess("=== ShopK Status ===")
    d.mess("Running: " .. (status.running and "Yes" or "No"))
    d.mess("Private Key: " .. (status.privateKeyConfigured and "Configured" or "Not configured"))
    
    if status.address then
        d.mess("Shop Address: " .. status.address)
    end
    
    d.mess("")
    d.mess("=== Subscription Tiers ===")
    for pattern, tier in pairs(ACCESS_CONFIG.subscription_tiers) do
        local availableSlots, occupiedSlots = slots.getAvailableSlots(tac, pattern)
        local allMatchingTags = slots.getAllMatchingTags(tac, pattern)
        local totalSlots = 0
        local usedSlots = 0
        
        -- Count total slots that exist (from doors/cards)
        for _ in pairs(allMatchingTags) do
            totalSlots = totalSlots + 1
        end
        
        -- Count used slots
        for _ in pairs(occupiedSlots) do
            usedSlots = usedSlots + 1
        end
        
        d.mess(string.format("%s (%s)", tier.name, pattern))
        d.mess(string.format("  Category: %s", tier.category))
        d.mess(string.format("  Price: %d %s (%d days)", tier.price, ACCESS_CONFIG.general_settings.currency_name, tier.duration))
        d.mess(string.format("  Renewal: %d %s", tier.renewal_price, ACCESS_CONFIG.general_settings.currency_name))
        d.mess(string.format("  Slots: %d used / %d total (%d available)", usedSlots, totalSlots, #availableSlots))
        d.mess(string.format("  Features: %s", table.concat(tier.features, ", ")))
        
        if #availableSlots > 0 then
            local nextSlot = slots.getNextAvailableSlot(tac, pattern)
            if nextSlot then
                d.mess("    Next available: " .. nextSlot)
            end
        else
            d.mess("    No slots available")
        end
        d.mess("")
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
    
    d.mess("=== Subscription Tiers ===")
    for pattern, tier in pairs(ACCESS_CONFIG.subscription_tiers) do
        local availableSlots, occupiedSlots = slots.getAvailableSlots(tac, pattern)
        local allMatchingTags = slots.getAllMatchingTags(tac, pattern)
        local totalSlots = 0
        for _ in pairs(allMatchingTags) do
            totalSlots = totalSlots + 1
        end
        local usedSlots = 0
        for _ in pairs(occupiedSlots) do
            usedSlots = usedSlots + 1
        end
        
        d.mess(string.format("%s (%s) - %s", tier.name, pattern, tier.description))
        d.mess(string.format("  Category: %s", tier.category))
        d.mess(string.format("  Price: %d %s, Renewal: %d %s", tier.price, ACCESS_CONFIG.general_settings.currency_name, tier.renewal_price, ACCESS_CONFIG.general_settings.currency_name))
        d.mess(string.format("  Duration: %d days", tier.duration))
        d.mess("  Slots: " .. #availableSlots .. " available, " .. 
               totalSlots - #availableSlots .. " occupied, " .. 
               totalSlots .. " total")
        
        if #availableSlots > 0 then
            local sampleSlots = {}
            for i = 1, math.min(3, #availableSlots) do
                table.insert(sampleSlots, availableSlots[i])
            end
            local more = #availableSlots > 3 and " (+" .. (#availableSlots - 3) .. " more)" or ""
            d.mess("  Available: " .. table.concat(sampleSlots, ", ") .. more)
        end
    end
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
        commands.listActiveSubscriptions(tac, d)
    elseif subcmd == "expired" then
        commands.listExpiredSubscriptions(tac, d)
    elseif subcmd == "cancel" then
        commands.cancelSubscriptionInteractive(args, tac, d)
    elseif subcmd == "cleanup" then
        commands.cleanupExpiredSubscriptions(args, tac, d)
    else
        d.err("Usage: shop subscriptions <list|expired|cancel|cleanup>")
        d.mess("  list    - Show active subscriptions")
        d.mess("  expired - Show expired subscriptions")
        d.mess("  cancel  - Cancel a subscription (with refund options)")
        d.mess("  cleanup - Remove old expired subscriptions")
    end
end

--- Show active subscriptions
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.listActiveSubscriptions(tac, d)
    local active = subscriptions.getActiveSubscriptions(tac)
    
    d.mess("=== Active Subscriptions ===")
    if #active == 0 then
        d.mess("No active subscriptions found")
        return
    end
    
    for i, sub in ipairs(active) do
        local cardData = sub.cardData
        local tier = sub.tier
        
        d.mess(string.format("%d. %s", i, cardData.name or "Unknown"))
        d.mess(string.format("   Type: %s (%s)", tier and tier.name or "Unknown", tier and tier.category or "Unknown"))
        d.mess(string.format("   Expires: %s (%d days)", utils.formatExpiration(cardData.expiration), sub.daysRemaining))
        
        if cardData.metadata and cardData.metadata.purchaseValue then
            d.mess(string.format("   Original: %d %s", cardData.metadata.purchaseValue, config.get().general_settings.currency_name))
        end
        
        if cardData.id then
            d.mess(string.format("   ID: %s", cardData.id:sub(1, 12) .. "..."))
        end
        d.mess("")
    end
    
    d.mess(string.format("Total: %d active subscriptions", #active))
end

--- Show expired subscriptions
-- @param tac table - TAC instance
-- @param d table - display interface
function commands.listExpiredSubscriptions(tac, d)
    local expired = subscriptions.getExpiredSubscriptions(tac)
    
    d.mess("=== Expired Subscriptions ===")
    if #expired == 0 then
        d.mess("No expired subscriptions found")
        return
    end
    
    for i, sub in ipairs(expired) do
        local cardData = sub.cardData
        
        d.mess(string.format("%d. %s", i, cardData.name or "Unknown"))
        d.mess(string.format("   Expired: %s (%d days ago)", utils.formatExpiration(cardData.expiration), sub.daysExpired))
        
        if cardData.id then
            d.mess(string.format("   ID: %s", cardData.id:sub(1, 12) .. "..."))
        end
        d.mess("")
    end
    
    d.mess(string.format("Total: %d expired subscriptions", #expired))
    d.mess("Use 'shop subscriptions cleanup' to remove old expired subscriptions")
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
    local cardsToRemove = {}
    
    -- Find expired cards
    for cardId, cardData in pairs(tac.cards.getAll()) do
        if cardData.expiration and utils.isCardExpired(cardData) then
            table.insert(cardsToRemove, {
                id = cardId,
                name = cardData.name or "Unknown"
            })
        end
    end
    
    -- Remove expired cards
    for _, cardInfo in pairs(cardsToRemove) do
        tac.cards.unset(cardInfo.id)
        removedCount = removedCount + 1
        d.mess("Removed: " .. cardInfo.name)
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
        return {"config", "status", "sales", "reset", "subscriptions", "cleanup", "tiers", "start", "stop"}
    elseif #args == 2 and args[1]:lower() == "tiers" then
        return {"list", "add", "remove", "edit"}
    elseif #args == 2 and args[1]:lower() == "subscriptions" then
        return {"list", "expired", "cancel", "cleanup"}
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