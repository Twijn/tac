-- TAC Centralized Card Management
-- Provides consistent card creation, validation, and management APIs

local function create(tacInstance)
    local cardManager = {}
    local tac = tacInstance

    -- Generate a unique card ID
    local function generateCardId(username, prefix)
        prefix = prefix or ""
        local sanitizedUsername = username and username:gsub("%s+", "_"):lower() or "unknown"
        local timestamp = os.epoch("utc")
        
        if prefix and #prefix > 0 then
            return prefix .. "_" .. sanitizedUsername .. "_" .. timestamp
        else
            return sanitizedUsername .. "_" .. timestamp
        end
    end

    -- Validate card data
    local function validateCardData(cardData)
        if not cardData then
            return false, "Card data is required"
        end
        
        if not cardData.name or #cardData.name == 0 then
            return false, "Card name is required"
        end
        
        if not cardData.tags or type(cardData.tags) ~= "table" or #cardData.tags == 0 then
            return false, "At least one tag is required"
        end
        
        -- Validate expiration if present
        if cardData.expiration and type(cardData.expiration) ~= "number" then
            return false, "Expiration must be a number (UTC epoch)"
        end
        
        return true, nil
    end

    -- Create a new card with standard validation and logging
    function cardManager.createCard(options)
        local opts = options or {}
        
        -- Generate ID if not provided
        local cardId = opts.id or generateCardId(opts.username, opts.prefix)
        
        -- Build card data
        local cardData = {
            id = cardId,
            name = opts.name or (opts.username and (opts.username .. " Card") or "Unnamed Card"),
            tags = opts.tags or {},
            expiration = opts.expiration,
            created = os.epoch("utc"),
            createdBy = opts.createdBy or "system",
            metadata = opts.metadata or {}
        }
        
        -- Validate the card data
        local isValid, error = validateCardData(cardData)
        if not isValid then
            return nil, error
        end
        
        -- Save the card
        tac.cards.set(cardData.id, cardData)
        
        -- Log the creation
        local logMessage = opts.logMessage or ("Card created: " .. cardData.name)
        tac.logger.logAccess("card_created", {
            card = cardData,
            message = logMessage
        })
        
        return cardData, nil
    end

    -- Create a subscription card (with expiration)
    function cardManager.createSubscriptionCard(options)
        local opts = options or {}
        
        if not opts.username then
            return nil, "Username is required for subscription cards"
        end
        
        if not opts.duration then
            return nil, "Duration is required for subscription cards"
        end
        
        if not opts.slot then
            return nil, "Slot/access level is required for subscription cards"
        end
        
        -- Calculate expiration
        local expiration = os.epoch("utc") + (opts.duration * 24 * 60 * 60 * 1000)
        
        -- Create the card
        local cardOptions = {
            id = opts.slot .. "_" .. opts.username:gsub("%s+", "_"):lower(),
            name = opts.username .. " (" .. opts.slot .. ")",
            tags = {opts.slot},
            expiration = expiration,
            username = opts.username,
            createdBy = opts.createdBy or "shopk",
            metadata = {
                slot = opts.slot,
                duration = opts.duration,
                purchaseValue = opts.purchaseValue,
                transactionId = opts.transactionId
            },
            logMessage = opts.logMessage or string.format(
                "Subscription card created: %s for %s expires %s",
                opts.slot,
                opts.username,
                os.date("!%Y-%m-%d %H:%M:%S", expiration / 1000)
            )
        }
        
        return cardManager.createCard(cardOptions)
    end

    -- Renew an existing card
    function cardManager.renewCard(cardId, additionalDuration, options)
        local opts = options or {}
        
        -- Get existing card
        local existingCard = tac.cards.get(cardId)
        if not existingCard then
            return nil, "Card not found: " .. cardId
        end
        
        -- Calculate new expiration
        local currentExpiration = existingCard.expiration or os.epoch("utc")
        local newExpiration = currentExpiration + (additionalDuration * 24 * 60 * 60 * 1000)
        
        -- Update the card
        existingCard.expiration = newExpiration
        existingCard.renewed = os.epoch("utc")
        existingCard.renewedBy = opts.renewedBy or "system"
        
        if opts.transactionId then
            existingCard.metadata = existingCard.metadata or {}
            existingCard.metadata.lastTransactionId = opts.transactionId
        end
        
        -- Save the updated card
        tac.cards.set(cardId, existingCard)
        
        -- Log the renewal
        local logMessage = opts.logMessage or string.format(
            "Card renewed: %s extended by %d days until %s",
            existingCard.name,
            additionalDuration,
            os.date("!%Y-%m-%d %H:%M:%S", newExpiration / 1000)
        )
        
        tac.logger.logAccess("card_renewed", {
            card = existingCard,
            message = logMessage
        })
        
        return existingCard, nil
    end

    -- Get card status and info
    function cardManager.getCardInfo(cardId)
        local card = tac.cards.get(cardId)
        if not card then
            return nil, "Card not found"
        end
        
        local info = {
            id = card.id,
            name = card.name,
            tags = card.tags,
            created = card.created,
            createdBy = card.createdBy,
            isExpired = false,
            timeUntilExpiration = nil,
            metadata = card.metadata or {}
        }
        
        if card.expiration then
            local now = os.epoch("utc")
            info.expiration = card.expiration
            info.isExpired = now >= card.expiration
            info.timeUntilExpiration = card.expiration - now
        end
        
        return info, nil
    end

    -- Validate card ID format
    function cardManager.isValidCardId(cardId)
        return cardId and type(cardId) == "string" and #cardId > 0
    end

    return cardManager
end

return { create = create }