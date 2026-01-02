--[[
    TAC Centralized Card Management
    
    Provides consistent card creation, validation, and management APIs.
    Handles standard card creation, subscription cards with expiration,
    card renewal, and card information queries.
    Supports NFC, RFID, or both scan types for cards.
    
    @module tac.core.card_manager
    @author Twijn
    @version 1.1.0
    @license MIT
    
    @example
    -- In your extension:
    function MyExtension.init(tac)
        -- Create a simple card (works with both NFC and RFID by default)
        local card, err = tac.cardManager.createCard({
            name = "John Doe",
            tags = {"tenant.1", "vip"},
            scanType = "both"
        })
        
        -- Create an RFID-only card
        local rfidCard, err = tac.cardManager.createCard({
            name = "Badge User",
            tags = {"staff"},
            scanType = "rfid"
        })
        
        -- Create a subscription card
        local subCard, err = tac.cardManager.createSubscriptionCard({
            username = "player1",
            duration = 30,
            slot = "tenant.premium",
            scanType = "nfc"
        })
        
        -- Renew a card
        tac.cardManager.renewCard("tenant_1_player1", 30)
        
        -- Get card info
        local info, err = tac.cardManager.getCardInfo("tenant_1_player1")
        if info then
            print("Card expires in " .. (info.timeUntilExpiration / 86400000) .. " days")
            print("Scan type: " .. info.scanType)
        end
    end
]]

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

    --- Create a new card with standard validation and logging
    --
    -- Creates a card with the provided options, validates the data, saves it,
    -- and logs the creation event. Auto-generates a card ID if not provided.
    --
    ---@param options table Card creation options:
    --   - id (string, optional): Card ID (auto-generated if not provided)
    --   - name (string, required): Display name for the card
    --   - tags (table, required): Array of access tags
    --   - scanType (string, optional): "nfc", "rfid", or "both" (default: "both")
    --   - expiration (number, optional): UTC epoch timestamp when card expires
    --   - username (string, optional): Username associated with card (used in ID generation)
    --   - prefix (string, optional): Prefix for auto-generated ID
    --   - createdBy (string, optional): Who/what created the card (default: "system")
    --   - metadata (table, optional): Additional custom data
    --   - logMessage (string, optional): Custom log message
    ---@return table|nil Card data object if successful, nil on error
    ---@return string|nil Error message if creation failed
    ---@usage local card, err = cardManager.createCard({name = "John Doe", tags = {"tenant.1"}, scanType = "both"})
    function cardManager.createCard(options)
        local opts = options or {}
        
        -- Generate ID if not provided
        local cardId = opts.id or generateCardId(opts.username, opts.prefix)
        
        -- Validate scanType
        local scanType = opts.scanType or "both"
        if scanType ~= "nfc" and scanType ~= "rfid" and scanType ~= "both" then
            scanType = "both"
        end
        
        -- Build card data
        local cardData = {
            id = cardId,
            name = opts.name or (opts.username and (opts.username .. " Card") or "Unnamed Card"),
            tags = opts.tags or {},
            scanType = scanType,
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
        local logMessage = opts.logMessage or ("Card created: " .. cardData.name .. " (scanType: " .. scanType .. ")")
        tac.logger.logAccess("card_created", {
            card = cardData,
            message = logMessage
        })
        
        return cardData, nil
    end

    --- Create a subscription card (with expiration)
    --
    -- Specialized function for creating time-limited subscription cards.
    -- Commonly used by ShopK integration for selling temporary access.
    --
    ---@param options table Subscription card options:
    --   - username (string, required): Username of the subscriber
    --   - duration (number, required): Subscription duration in days
    --   - slot (string, required): Access level/slot (becomes the card tag)
    --   - scanType (string, optional): "nfc", "rfid", or "both" (default: "both")
    --   - createdBy (string, optional): Creator identifier (default: "shopk")
    --   - purchaseValue (number, optional): Purchase price for metadata
    --   - transactionId (string, optional): Transaction ID for metadata
    --   - logMessage (string, optional): Custom log message
    ---@return table|nil Card data object if successful, nil on error
    ---@return string|nil Error message if creation failed
    ---@usage local card, err = cardManager.createSubscriptionCard({username = "player1", duration = 30, slot = "tenant.1"})
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
            scanType = opts.scanType or "both",
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

    --- Renew an existing card
    --
    -- Extends the expiration date of an existing card by the specified duration.
    -- Updates renewal metadata and logs the renewal event.
    --
    ---@param cardId string ID of the card to renew
    ---@param additionalDuration number Days to add to current expiration
    ---@param options table Optional renewal options:
    --   - renewedBy (string, optional): Who renewed the card (default: "system")
    --   - transactionId (string, optional): Transaction ID for metadata
    --   - logMessage (string, optional): Custom log message
    ---@return table|nil Updated card data if successful, nil on error
    ---@return string|nil Error message if renewal failed
    ---@usage local card, err = cardManager.renewCard("tenant_1_player1", 30, {renewedBy = "admin"})
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

    --- Get card status and info
    --
    -- Retrieves comprehensive information about a card including expiration status.
    -- Returns structured data with calculated fields like isExpired and timeUntilExpiration.
    --
    ---@param cardId string ID of the card to query
    ---@return table|nil Card info object with fields:
    --   - id (string): Card ID
    --   - name (string): Card display name
    --   - tags (table): Access tags array
    --   - scanType (string): "nfc", "rfid", or "both"
    --   - created (number): Creation timestamp
    --   - createdBy (string): Creator identifier
    --   - isExpired (boolean): Whether card is currently expired
    --   - timeUntilExpiration (number|nil): Milliseconds until expiration (nil if no expiration)
    --   - expiration (number|nil): Expiration timestamp if set
    --   - metadata (table): Custom metadata
    ---@return string|nil Error message if card not found
    ---@usage local info, err = cardManager.getCardInfo("tenant_1_player1")
    function cardManager.getCardInfo(cardId)
        local card = tac.cards.get(cardId)
        if not card then
            return nil, "Card not found"
        end
        
        local info = {
            id = card.id,
            name = card.name,
            tags = card.tags,
            scanType = card.scanType or "both",
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

    --- Validate card ID format
    --
    -- Checks if a card ID meets basic format requirements (non-empty string).
    --
    ---@param cardId any Value to validate as a card ID
    ---@return boolean True if valid card ID format
    ---@usage if cardManager.isValidCardId(scannedId) then ... end
    function cardManager.isValidCardId(cardId)
        return cardId and type(cardId) == "string" and #cardId > 0
    end

    return cardManager
end

return { create = create }