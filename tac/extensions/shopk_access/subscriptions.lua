--[[
    ShopK Access Extension - Subscription Management
    
    Handles viewing, canceling, and refunding active subscriptions.
    Provides tools for managing user subscription lifecycles.
    
    @module tac.extensions.shopk_access.subscriptions
    @author Twijn
]]

local utils = require("tac.extensions.shopk_access.utils")
local config = require("tac.extensions.shopk_access.config")

local subscriptions = {}

--- Get all active subscriptions
-- @param tac table - TAC instance
-- @return table - array of active subscription data
function subscriptions.getActiveSubscriptions(tac)
    local active = {}
    local now = os.epoch("utc")
    
    for identityId, identity in pairs(tac.identities.getAll()) do
        if identity.expiration and identity.expiration > now then
            -- Identity is active, add to subscriptions list
            local sub = {
                cardId = identityId,
                cardData = identity,
                daysRemaining = utils.getDaysUntilExpiration(cardData.expiration),
                timeRemaining = cardData.expiration - now,
                tierPattern = nil,
                tier = nil
            }
            
            -- Find which tier this subscription belongs to
            if cardData.tags and #cardData.tags > 0 then
                local tag = cardData.tags[1]
                local pattern, tier = config.findTierForTag(tag)
                if pattern and tier then
                    sub.tierPattern = pattern
                    sub.tier = tier
                end
            end
            
            table.insert(active, sub)
        end
    end
    
    -- Sort by expiration date (soonest first)
    table.sort(active, function(a, b)
        return a.cardData.expiration < b.cardData.expiration
    end)
    
    return active
end

--- Get expired subscriptions that could be cleaned up
-- @param tac table - TAC instance
-- @return table - array of expired subscription data
function subscriptions.getExpiredSubscriptions(tac)
    local expired = {}
    local now = os.epoch("utc")
    
    for identityId, identity in pairs(tac.identities.getAll()) do
        if identity.expiration and identity.expiration <= now then
            local sub = {
                cardId = identityId,
                cardData = identity,
                daysExpired = math.abs(utils.getDaysUntilExpiration(cardData.expiration)),
                expiredTime = now - cardData.expiration
            }
            table.insert(expired, sub)
        end
    end
    
    -- Sort by most recently expired first
    table.sort(expired, function(a, b)
        return a.cardData.expiration > b.cardData.expiration
    end)
    
    return expired
end

--- Calculate refund amount for a subscription
-- @param subscription table - subscription data
-- @param cancelTime number - cancellation time (UTC epoch)
-- @return number, string - refund amount, refund reason
function subscriptions.calculateRefund(subscription, cancelTime)
    if not subscription.tier then
        return 0, "No tier information available"
    end
    
    local tier = subscription.tier
    local cardData = subscription.cardData
    local cfg = config.get()
    
    -- Check refund policy
    if tier.refund_policy == "none" then
        return 0, "No refunds allowed for this tier"
    end
    
    if not cardData.expiration or not cardData.created then
        return 0, "Missing subscription timing data"
    end
    
    local subscriptionStart = cardData.created
    local subscriptionEnd = cardData.expiration
    local totalDuration = subscriptionEnd - subscriptionStart
    local timeUsed = cancelTime - subscriptionStart
    local timeRemaining = subscriptionEnd - cancelTime
    
    -- If already expired, no refund
    if timeRemaining <= 0 then
        return 0, "Subscription has already expired"
    end
    
    -- Check grace period for full refund
    local gracePeriod = (cfg.refund_settings.grace_period_hours or 24) * 60 * 60 * 1000
    if timeUsed <= gracePeriod then
        return tier.price, "Full refund (within grace period)"
    end
    
    -- Calculate prorated refund
    if tier.refund_policy == "prorated" then
        local daysTotal = math.ceil(totalDuration / (24 * 60 * 60 * 1000))
        local daysUsed = math.ceil(timeUsed / (24 * 60 * 60 * 1000))
        local daysRemaining = daysTotal - daysUsed
        
        -- Check minimum days to charge
        local minDays = cfg.refund_settings.prorated_minimum_days or 3
        if daysUsed < minDays then
            daysUsed = minDays
            daysRemaining = daysTotal - daysUsed
        end
        
        if daysRemaining <= 0 then
            return 0, "Minimum usage period exceeded"
        end
        
        local refundPercent = daysRemaining / daysTotal
        local grossRefund = tier.price * refundPercent
        
        -- Apply refund fee
        local feePercent = (cfg.refund_settings.refund_fee_percent or 5) / 100
        local refundFee = grossRefund * feePercent
        local netRefund = grossRefund - refundFee
        
        -- Check minimum refund amount
        local minRefund = cfg.refund_settings.min_refund_amount or 50
        if netRefund < minRefund then
            return 0, string.format("Refund amount (%.0f %s) below minimum (%.0f %s)", 
                netRefund, cfg.general_settings.currency_name or "KRO",
                minRefund, cfg.general_settings.currency_name or "KRO")
        end
        
        return math.floor(netRefund), string.format("Prorated refund (%d days remaining, %.0f%% fee)", 
            daysRemaining, (cfg.refund_settings.refund_fee_percent or 5))
    end
    
    -- Full refund policy
    if tier.refund_policy == "full" then
        return tier.price, "Full refund policy"
    end
    
    return 0, "Unknown refund policy"
end

--- Cancel a subscription and process refund
-- @param tac table - TAC instance
-- @param cardId string - card ID to cancel
-- @param reason string - cancellation reason
-- @param processRefund boolean - whether to process the refund
-- @return boolean, string, number - success, message, refund amount
function subscriptions.cancelSubscription(tac, cardId, reason, processRefund)
    local cardData = tac.identities.get(cardId)
    if not cardData then
        return false, "Subscription not found", 0
    end
    
    if not cardData.expiration then
        return false, "Not a subscription (permanent access)", 0
    end
    
    local now = os.epoch("utc")
    if cardData.expiration <= now then
        return false, "Subscription already expired", 0
    end
    
    -- Find subscription info
    local sub = {
        cardId = cardId,
        cardData = cardData,
        tierPattern = nil,
        tier = nil
    }
    
    if cardData.tags and #cardData.tags > 0 then
        local pattern, tier = config.findTierForTag(cardData.tags[1])
        sub.tierPattern = pattern
        sub.tier = tier
    end
    
    local refundAmount = 0
    local refundReason = "No refund processed"
    
    -- Calculate refund if requested
    if processRefund then
        refundAmount, refundReason = subscriptions.calculateRefund(sub, now)
    end
    
    -- Cancel the subscription by removing the identity
    tac.identities.unset(cardId)
    
    -- Log the cancellation
    tac.logger.logAccess("subscription_cancelled", {
        card = cardData,
        reason = reason or "Manual cancellation",
        refund_amount = refundAmount,
        refund_reason = refundReason,
        cancelled_by = "admin",
        time_remaining = cardData.expiration - now,
        message = string.format("Subscription cancelled: %s (refund: %.0f %s)", 
            cardData.name or "Unknown", 
            refundAmount, 
            config.get().general_settings.currency_name or "KRO")
    })
    
    local message = string.format("Subscription cancelled successfully. Refund: %.0f %s (%s)", 
        refundAmount, 
        config.get().general_settings.currency_name or "KRO",
        refundReason)
    
    return true, message, refundAmount
end

--- Display subscription details
-- @param subscription table - subscription data
-- @param index number - display index
function subscriptions.displaySubscription(subscription, index)
    local cardData = subscription.cardData
    local tier = subscription.tier
    
    print(string.format("%d. %s", index, cardData.name or "Unknown"))
    print(string.format("   ID: %s", cardData.id and cardData.id:sub(1, 12) .. "..." or "Unknown"))
    print(string.format("   Type: %s", tier and tier.name or "Unknown"))
    print(string.format("   Category: %s", tier and tier.category or "Unknown"))
    
    if cardData.expiration then
        print(string.format("   Expires: %s", utils.formatExpiration(cardData.expiration)))
        print(string.format("   Days Remaining: %d", subscription.daysRemaining))
    end
    
    if cardData.tags then
        print(string.format("   Access: %s", table.concat(cardData.tags, ", ")))
    end
    
    if tier and tier.features then
        print(string.format("   Features: %s", table.concat(tier.features, ", ")))
    end
    
    if cardData.metadata then
        if cardData.metadata.purchaseValue then
            print(string.format("   Original Price: %.0f %s", cardData.metadata.purchaseValue, 
                config.get().general_settings.currency_name or "KRO"))
        end
        if cardData.metadata.transactionId then
            print(string.format("   Transaction: %s", cardData.metadata.transactionId))
        end
    end
    
    print(string.format("   Created: %s", cardData.created and os.date("!%Y-%m-%d %H:%M:%S", cardData.created / 1000) or "Unknown"))
    print()
end

--- Bulk cleanup expired subscriptions
-- @param tac table - TAC instance
-- @param maxAge number - maximum age in days (optional, default 30)
-- @return number - number of subscriptions cleaned up
function subscriptions.cleanupExpired(tac, maxAge)
    maxAge = maxAge or 30
    local maxAgeMs = maxAge * 24 * 60 * 60 * 1000
    local now = os.epoch("utc")
    local cutoff = now - maxAgeMs
    
    local removed = 0
    local toRemove = {}
    
    for identityId, identity in pairs(tac.identities.getAll()) do
        if identity.expiration and identity.expiration < cutoff then
            table.insert(toRemove, {id = identityId, data = identity})
        end
    end
    
    for _, item in ipairs(toRemove) do
        tac.identities.unset(item.id)
        removed = removed + 1
        
        tac.logger.logAccess("subscription_cleanup", {
            card = item.data,
            reason = string.format("Expired more than %d days ago", maxAge),
            message = "Automatic cleanup of expired subscription: " .. (item.data.name or "Unknown")
        })
    end
    
    return removed
end

return subscriptions