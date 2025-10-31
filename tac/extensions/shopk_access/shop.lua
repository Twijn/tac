--[[
    ShopK Access Extension - Transaction Handling
    
    Handles ShopK shop instance and transaction processing. Manages the
    ShopK integration, processes purchases, and handles payment events.
    
    @module tac.extensions.shopk_access.shop
    @author Twijn
]]

local utils = require("tac.extensions.shopk_access.utils")
local config = require("tac.extensions.shopk_access.config")
local slots = require("tac.extensions.shopk_access.slots")
local monitor_ui = require("tac.extensions.shopk_access.monitor_ui")
local persist = require("persist")

local shop_handler = {}

-- Shop instance (will be set when shop starts)
local shop = nil
local shopCoroutine = nil

-- Persistent NFC write state
local nfcWriteState = persist("nfc_write_state.json")

--- Helper to issue refund with error metadata
-- @param transaction table - original transaction
-- @param errorMessage string - error description
local function refundWithError(transaction, errorMessage)
    term.setTextColor(colors.yellow)
    print("Issuing refund: " .. errorMessage)
    term.setTextColor(colors.white)
    
    shop_handler.sendRefund(transaction.from, transaction.value, errorMessage, function(success, message)
        if success then
            term.setTextColor(colors.green)
            print("Refund issued successfully")
            term.setTextColor(colors.white)
        else
            term.setTextColor(colors.red)
            print("Failed to issue refund: " .. (message or "Unknown error"))
            print("MANUAL REFUND REQUIRED for transaction " .. transaction.id)
            term.setTextColor(colors.white)
        end
    end)
end

--- Resume any pending NFC writes from before restart
-- @param tac table - TAC instance
function shop_handler.resumePendingWrites(tac)
    local pendingWrite = nfcWriteState.get("active")
    if not pendingWrite then return end
    
    term.setTextColor(colors.cyan)
    print("=== Resuming Pending NFC Write ===")
    term.setTextColor(colors.white)
    
    if pendingWrite.type == "new_subscription" then
        print("Type: New Subscription")
        print("Player: " .. pendingWrite.username)
        print("Slot: " .. pendingWrite.slot)
        shop_handler.writeNFCCard(tac, {
            username = pendingWrite.username,
            slot = pendingWrite.slot,
            tier = pendingWrite.tier,
            transaction = pendingWrite.transaction
        })
    elseif pendingWrite.type == "renewal" then
        print("Type: Renewal")
        print("Player: " .. pendingWrite.username)
        print("Access: " .. pendingWrite.accessTag)
        shop_handler.writeRenewalNFCCard(tac, {
            username = pendingWrite.username,
            accessTag = pendingWrite.accessTag,
            tier = pendingWrite.tier,
            transaction = pendingWrite.transaction,
            originalCard = pendingWrite.originalCard
        })
    end
end

--- Start the ShopK shop
-- @param tac table - TAC instance
-- @param d table - display interface
function shop_handler.startShop(tac)
    local ACCESS_CONFIG = config.get()
    local shopk = require("lib.shopk")
    
    -- Check for pending NFC writes and resume them
    shop_handler.resumePendingWrites(tac)
    
    -- Build shop configuration
    local shopConfig = {
        privatekey = ACCESS_CONFIG.private_key
    }
    
    -- Inject syncNode if configured
    local syncNode = tac.settings.get("shopk_syncNode")
    if syncNode then
        shopConfig.syncNode = syncNode
        term.setTextColor(colors.cyan)
        print("Using custom Kromer node: " .. syncNode)
        term.setTextColor(colors.white)
    end
    
    shop = shopk(shopConfig)

    -- Set up transaction handler immediately
    shop.on("transaction", function(transaction)
        shop_handler.handleTransaction(tac, transaction)
    end)
    
    -- Wait for connection to be established
    shop.on("ready", function()
        term.setTextColor(colors.lime)
        print("Connected to ShopK WebSocket!")
        term.setTextColor(colors.white)
        
        -- Get shop address after connection is established
        shop.me(function(data)
            if data.ok then
                config.set("shop_address", data.address.address)
                config.save(tac)
                term.setTextColor(colors.cyan)
                print("Shop address: " .. data.address.address)
                term.setTextColor(colors.lime)
                print("ShopK is now running!")
                term.setTextColor(colors.white)
            else
                term.setTextColor(colors.red)
                print("Failed to get shop address: " .. tostring(data.error))
                term.setTextColor(colors.white)
            end
        end)
    end)
    
    -- Add error handler
    shop.on("error", function(err)
        term.setTextColor(colors.red)
        print("ShopK error event: " .. tostring(err))
        term.setTextColor(colors.white)
    end)
    
    -- Add close handler
    shop.on("close", function()
        term.setTextColor(colors.orange)
        print("ShopK connection closed")
        term.setTextColor(colors.white)
    end)
    
    -- Register ShopK as a background process that runs in parallel
    tac.registerBackgroundProcess("shopk", function()
        term.setTextColor(colors.yellow)
        print("Starting ShopK in background process...")
        term.setTextColor(colors.white)
        
        -- Keep the process alive even if shop closes
        while true do
            if shop then
                local success, err = pcall(shop.run)
                if not success then
                    term.setTextColor(colors.red)
                    print("ShopK error: " .. tostring(err))
                    term.setTextColor(colors.white)
                end
            end
            
            -- Sleep to avoid busy-waiting when shop is stopped
            os.sleep(1)
        end
    end)
    
    -- Add shutdown hook
    tac.addHook("beforeShutdown", function()
        if shop then
            term.setTextColor(colors.orange)
            print("Stopping ShopK shop...")
            term.setTextColor(colors.white)
            
            -- Try to close the shop gracefully
            local success, err = pcall(function()
                if shop.close then
                    shop.close()
                elseif shop.ws and shop.ws.close then
                    shop.ws.close()
                end
            end)
            
            if not success then
                print("Warning: Error closing ShopK: " .. tostring(err))
            else
                print("ShopK shop closed successfully")
            end
            
            -- Clear shop reference
            shop = nil
            shopCoroutine = nil
        end
    end)
end

--- Handle incoming transactions
-- @param tac table - TAC instance
-- @param transaction table - transaction data
function shop_handler.handleTransaction(tac, transaction)
    term.setTextColor(colors.yellow)
    print("Received transaction: " .. transaction.value .. " KRO from " .. transaction.from)
    term.setTextColor(colors.white)
    
    -- Parse metadata
    local sku = transaction.meta.keys.sku
    local accessTag = transaction.meta.keys.tag
    local username = transaction.meta.keys.username
    
    -- Check for required fields
    if not sku then
        term.setTextColor(colors.red)
        print("Invalid transaction metadata - missing sku")
        term.setTextColor(colors.white)
        refundWithError(transaction, "Invalid transaction: missing SKU")
        return
    end
    
    if not username then
        term.setTextColor(colors.red)
        print("Invalid transaction metadata - missing username")
        term.setTextColor(colors.white)
        refundWithError(transaction, "Invalid transaction: missing username")
        return
    end
    
    -- Handle renewal transactions
    if sku == "renewal" then
        shop_handler.handleRenewal(tac, transaction, username)
        return
    end
    
    -- Handle new subscription transactions
    shop_handler.handleNewSubscription(tac, transaction, sku, username)
end

--- Handle renewal transactions
-- @param tac table - TAC instance
-- @param transaction table - transaction data
-- @param username string - player username
function shop_handler.handleRenewal(tac, transaction, username)
    -- Find cards belonging to this user
    local userCards = {}
    for cardId, cardData in pairs(tac.cards.getAll()) do
        if cardData.name and cardData.name:lower():find(username:lower()) then
            cardData.id = cardId
            table.insert(userCards, cardData)
        end
    end
    
    if #userCards == 0 then
        term.setTextColor(colors.red)
        print("No cards found for user: " .. username)
        term.setTextColor(colors.white)
        refundWithError(transaction, "Renewal failed: no existing cards found for " .. username)
        return
    end
    
    -- Use the first card found (or could be made smarter)
    local targetCard = userCards[1]
    
    -- Find tier for this card's first tag
    local accessTag = targetCard.tags and targetCard.tags[1]
    if not accessTag then
        term.setTextColor(colors.red)
        print("Card has no tags to renew")
        term.setTextColor(colors.white)
        refundWithError(transaction, "Renewal failed: card has no access tags")
        return
    end
    
    local tierPattern, tier = config.findTierForTag(accessTag)
    if not tier then
        term.setTextColor(colors.red)
        print("No tier found for tag: " .. accessTag)
        term.setTextColor(colors.white)
        refundWithError(transaction, "Renewal failed: no tier found for access level " .. accessTag)
        return
    end
    
    -- Check if renewal price matches
    if transaction.value ~= tier.renewal_price then
        term.setTextColor(colors.red)
        print("Incorrect renewal price. Expected: " .. tier.renewal_price .. " KRO")
        term.setTextColor(colors.white)
        refundWithError(transaction, string.format("Incorrect price: expected %d KRO, received %d KRO", tier.renewal_price, transaction.value))
        return
    end
    
    term.setTextColor(colors.cyan)
    print("=== Card Renewal Process ===")
    print("Renewing access for " .. username)
    print("Access Level: " .. accessTag)
    print("Additional Duration: " .. tier.duration .. " days")
    print("Amount Paid: " .. transaction.value .. " KRO")
    term.setTextColor(colors.white)
    
    -- Prepare renewal data
    local renewalData = {
        username = username,
        accessTag = accessTag,
        tier = tier,
        transaction = transaction,
        originalCard = targetCard
    }
    
    -- Try to use monitor UI if available
    local choice = nil
    if monitor_ui.isAvailable() then
        term.setTextColor(colors.cyan)
        print("Using monitor UI for renewal choice...")
        term.setTextColor(colors.white)
        
        -- Show choice on monitor
        monitor_ui.showRenewalChoice(renewalData, function(selectedChoice)
            choice = selectedChoice
        end)
        
        -- Wait for user choice via monitor
        while choice == nil do
            os.sleep(0.1)
        end
    else
        -- Fall back to terminal prompt
        print("")
        print("Choose renewal option:")
        print("1. Renew existing card data only (recommended)")
        print("2. Write new NFC card with renewed access")
        print("")
        print("Press '1' for data renewal, '2' for new NFC card, or 'q' to cancel:")
        
        while choice == nil do
            local event, key = os.pullEvent("key")
            if key == keys.one then
                choice = "data"
                break
            elseif key == keys.two then
                choice = "nfc"
                break
            elseif key == keys.q then
                term.setTextColor(colors.yellow)
                print("Renewal cancelled.")
                term.setTextColor(colors.white)
                return
            end
        end
    end
    
    -- Handle cancellation
    if not choice then
        term.setTextColor(colors.yellow)
        print("Renewal cancelled.")
        term.setTextColor(colors.white)
        if monitor_ui.isAvailable() then
            monitor_ui.showError("Renewal cancelled by user")
            os.sleep(2)
        end
        return
    end
    
    if choice == "data" then
        -- Standard renewal - just update the card data
        local renewedCard, error = tac.cardManager.renewCard(targetCard.id, tier.duration, {
            renewedBy = "shopk",
            transactionId = transaction.id,
            logMessage = "Card renewed via ShopK: " .. accessTag .. " for " .. username .. " (" .. transaction.value .. " KRO)"
        })

        if not renewedCard then
            term.setTextColor(colors.red)
            print("Failed to renew card: " .. (error or "Unknown error"))
            term.setTextColor(colors.white)
            if monitor_ui.isAvailable() then
                monitor_ui.showError("Failed to renew card: " .. (error or "Unknown error"))
                os.sleep(3)
            end
            return
        end

        term.setTextColor(colors.lime)
        print("Card data renewed successfully!")
        print("Player: " .. username)
        print("Access Level: " .. accessTag)
        print("New Expiration: " .. utils.formatExpiration(renewedCard.expiration))
        term.setTextColor(colors.white)
        
        if monitor_ui.isAvailable() then
            monitor_ui.showSuccess("Card renewed successfully!", {
                ["Player"] = username,
                ["Access"] = accessTag,
                ["Expires"] = utils.formatExpiration(renewedCard.expiration)
            })
            -- Timer will auto-clear after 5 seconds
        end
        
    elseif choice == "nfc" then
        -- Write new NFC card with renewed access
        local success = shop_handler.writeRenewalNFCCard(tac, {
            username = username,
            accessTag = accessTag,
            tier = tier,
            transaction = transaction,
            originalCard = targetCard
        })
        
        if not success then
            term.setTextColor(colors.red)
            print("Failed to write new NFC card for renewal!")
            term.setTextColor(colors.white)
            if monitor_ui.isAvailable() then
                monitor_ui.showError("Failed to write new NFC card for renewal!")
                os.sleep(3)
            end
            return
        end
    end
end

--- Handle new subscription transactions
-- @param tac table - TAC instance
-- @param transaction table - transaction data
-- @param sku string - SKU pattern
-- @param username string - player username
function shop_handler.handleNewSubscription(tac, transaction, sku, username)
    -- Find matching tier by simple SKU
    local tierPattern, tier = nil, nil
    local ACCESS_CONFIG = config.get()
    
    for pattern, tierData in pairs(ACCESS_CONFIG.subscription_tiers or {}) do
        -- Generate simple SKU from pattern (same logic as formatPaymentMeta)
        local patternSku = pattern:match("([^%.]+)") or pattern
        patternSku = patternSku:gsub("[^%w]", ""):lower()
        
        if patternSku == sku then
            tierPattern = pattern
            tier = tierData
            break
        end
    end
    
    if not tier then
        term.setTextColor(colors.red)
        print("No tier found for SKU: " .. sku)
        term.setTextColor(colors.white)
        refundWithError(transaction, "Invalid SKU: " .. sku .. " does not match any available tier")
        return
    end
    
    -- Check if price matches
    if transaction.value ~= tier.price then
        term.setTextColor(colors.red)
        print("Incorrect price for " .. sku .. ". Expected: " .. tier.price .. " KRO")
        term.setTextColor(colors.white)
        refundWithError(transaction, string.format("Incorrect price for %s: expected %d KRO, received %d KRO", sku, tier.price, transaction.value))
        return
    end
    
    -- Get next available slot
    local nextSlot = slots.getNextAvailableSlot(tac, tierPattern)
    if not nextSlot then
        term.setTextColor(colors.red)
        print("No available slots for " .. tierPattern)
        term.setTextColor(colors.white)
        refundWithError(transaction, "No available slots for " .. tierPattern .. " tier - all slots occupied")
        return
    end
    
    -- Start NFC card writing process
    term.setTextColor(colors.cyan)
    print("=== NFC Card Writing Process ===")
    print("Purchase confirmed for " .. username)
    print("Access Level: " .. nextSlot)
    print("Duration: " .. tier.duration .. " days")
    print("Amount Paid: " .. transaction.value .. " KRO")
    term.setTextColor(colors.white)
    
    -- Prepare purchase data
    local purchaseData = {
        username = username,
        slot = nextSlot,
        tier = tier,
        transaction = transaction
    }
    
    -- Show purchase confirmation on monitor if available
    local userConfirmed = true -- Default to true for terminal-only mode
    if monitor_ui.isAvailable() then
        term.setTextColor(colors.cyan)
        print("Using monitor UI for purchase confirmation...")
        term.setTextColor(colors.white)
        
        local choice = nil
        monitor_ui.showPurchaseChoice(purchaseData, function(selectedChoice)
            choice = selectedChoice
        end)
        
        -- Wait for user choice via monitor
        while choice == nil do
            os.sleep(0.1)
        end
        
        userConfirmed = (choice == "write")
        
        if not userConfirmed then
            term.setTextColor(colors.yellow)
            print("Purchase cancelled by user.")
            term.setTextColor(colors.white)
            monitor_ui.showError("Purchase cancelled by user")
            os.sleep(2)
            return
        end
    end
    
    local success = shop_handler.writeNFCCard(tac, purchaseData)
    
    if not success then
        term.setTextColor(colors.red)
        print("Failed to create NFC card for " .. username)
        print("Transaction completed but card creation failed!")
        term.setTextColor(colors.white)
        if monitor_ui.isAvailable() then
            monitor_ui.showError("Failed to create NFC card. Transaction completed but card creation failed!")
            os.sleep(3)
        end
        return
    end
    
    term.setTextColor(colors.lime)
    print("NFC card successfully created and activated!")
    term.setTextColor(colors.white)
    
    if monitor_ui.isAvailable() then
        monitor_ui.showSuccess("NFC card created successfully!", {
            ["Player"] = username,
            ["Access"] = nextSlot,
            ["Duration"] = tier.duration .. " days"
        })
        os.sleep(5)
    end
end

--- Stop the shop
-- @param d table - display interface
function shop_handler.stopShop(d)
    if shop then
        d.mess("Stopping shop...")
        
        -- Try to close the shop gracefully
        local success, err = pcall(function()
            if shop.close then
                shop.close()
            elseif shop.ws and shop.ws.close then
                shop.ws.close()
            end
        end)
        
        if not success then
            d.err("Warning: Error closing ShopK: " .. tostring(err))
        else
            d.mess("ShopK connection closed successfully")
        end
        
        -- Clear shop reference
        shop = nil
        shopCoroutine = nil
        d.mess("Shop stopped")
    else
        d.mess("Shop is not running")
    end
end

--- Check if shop is running
-- @return boolean - true if shop is running
function shop_handler.isRunning()
    return shop ~= nil
end

--- Get shop status
-- @param tac table - TAC instance
-- @return table - status information
function shop_handler.getStatus(tac)
    local ACCESS_CONFIG = config.get()
    return {
        running = shop_handler.isRunning(),
        address = ACCESS_CONFIG.shop_address,
        privateKeyConfigured = ACCESS_CONFIG.private_key ~= nil and ACCESS_CONFIG.private_key ~= ""
    }
end

--- Write NFC card with subscription data
-- @param tac table - TAC instance
-- @param options table - card creation options
-- @return boolean - success status
function shop_handler.writeNFCCard(tac, options)
    local username = options.username
    local slot = options.slot
    local tier = options.tier
    local transaction = options.transaction
    
    -- Generate card ID using TAC security core
    local SecurityCore = require("tac.core.security")
    local cardId = SecurityCore.randomString(128)
    
    -- Persist write state before starting
    nfcWriteState.set("active", {
        type = "new_subscription",
        cardId = cardId,
        username = username,
        slot = slot,
        tier = tier,
        transaction = transaction,
        startTime = os.epoch("utc")
    })
    
    term.setTextColor(colors.yellow)
    print("Generated card ID: " .. SecurityCore.truncateCardId(cardId))
    print("")
    print("Please place a blank NFC card on the server NFC reader...")
    print("Press 'q' to cancel the card writing process.")
    term.setTextColor(colors.white)
    
    -- Show NFC writing screen on monitor if available
    if monitor_ui.isAvailable() then
        monitor_ui.showNFCWriting({
            username = username,
            cardId = cardId
        })
    end
    
    -- Get server NFC reader
    local serverNfc = tac.getServerNfc()
    if not serverNfc then
        term.setTextColor(colors.red)
        print("ERROR: No server NFC reader configured!")
        print("Please ensure an NFC reader is connected and configured.")
        term.setTextColor(colors.white)
        return false
    end
    
    -- Prepare card data BEFORE writing
    local expiration = os.epoch("utc") + (tier.duration * 24 * 60 * 60 * 1000)
    local cardData = {
        id = cardId,
        name = username .. " (" .. slot .. ")",
        tags = {slot},
        expiration = expiration,
        username = username,
        created = os.epoch("utc"),
        createdBy = "shopk",
        metadata = {
            slot = slot,
            duration = tier.duration,
            purchaseValue = transaction.value,
            transactionId = transaction.id,
            fromAddress = transaction.from
        }
    }
    
    -- Start the NFC writing process
    term.setTextColor(colors.cyan)
    print("Starting NFC write process...")
    term.setTextColor(colors.white)
    
    serverNfc.write(cardId, username .. " (" .. slot .. ")")
    
    -- Wait for NFC write completion or cancellation
    local writeSuccessful = false
    local timeout = os.startTimer(30) -- 30 second timeout
    
    while true do
        local event, param1, param2 = os.pullEvent()
        
        -- Check for successful NFC write
        if event == "nfc_write" and param1 == peripheral.getName(serverNfc) then
            term.setTextColor(colors.lime)
            print("✓ NFC card written successfully!")
            term.setTextColor(colors.white)
            writeSuccessful = true
            break
            
        -- Check for user cancellation
        elseif event == "key" and param1 == keys.q then
            term.setTextColor(colors.yellow)
            print("Card writing cancelled by user.")
            term.setTextColor(colors.white)
            serverNfc.cancelWrite()
            nfcWriteState.unset("active")  -- Clear persisted state
            if monitor_ui.isAvailable() then
                monitor_ui.showError("Card writing cancelled by user")
                os.sleep(2)
            end
            refundWithError(transaction, "Card writing cancelled by user")
            return false
            
        -- Check for timeout
        elseif event == "timer" and param1 == timeout then
            term.setTextColor(colors.red)
            print("Card writing timed out after 30 seconds.")
            print("Please try again or check the NFC reader.")
            term.setTextColor(colors.white)
            serverNfc.cancelWrite()
            nfcWriteState.unset("active")  -- Clear persisted state
            if monitor_ui.isAvailable() then
                monitor_ui.showError("Card writing timed out (30 seconds). Please try again.")
                os.sleep(3)
            end
            -- Issue refund for timeout
            refundWithError(transaction, "NFC card write timeout - no card placed within 30 seconds")
            return false
            
        -- Check for NFC write error
        elseif event == "nfc_write_error" then
            term.setTextColor(colors.red)
            print("NFC write error: " .. tostring(param2))
            term.setTextColor(colors.white)
            nfcWriteState.unset("active")  -- Clear persisted state
            if monitor_ui.isAvailable() then
                monitor_ui.showError("NFC write error: " .. tostring(param2))
                os.sleep(3)
            end
            refundWithError(transaction, "NFC write error: " .. tostring(param2))
            return false
        end
    end
    
    -- If NFC write was successful, save the card data
    if writeSuccessful then
        -- Clear persisted write state
        nfcWriteState.unset("active")
        
        -- Save card using centralized card manager
        local savedCard, error = tac.cardManager.createCard({
            id = cardId,
            name = cardData.name,
            tags = cardData.tags,
            expiration = cardData.expiration,
            username = cardData.username,
            createdBy = cardData.createdBy,
            metadata = cardData.metadata,
            logMessage = "ShopK NFC card created: " .. slot .. " for " .. username .. " expires " .. utils.formatExpiration(expiration) .. " (" .. transaction.value .. " KRO)"
        })
        
        if not savedCard then
            term.setTextColor(colors.red)
            print("ERROR: Card was written to NFC but failed to save to database!")
            print("Error: " .. (error or "Unknown error"))
            print("Card ID: " .. SecurityCore.truncateCardId(cardId))
            term.setTextColor(colors.white)
            if monitor_ui.isAvailable() then
                monitor_ui.showError("Card written to NFC but failed to save to database: " .. (error or "Unknown error"))
                os.sleep(3)
            end
            -- Note: No refund here since card was physically written
            return false
        end
        
        -- Display success information
        term.setTextColor(colors.lime)
        print("=== Card Creation Successful ===")
        print("Player: " .. username)
        print("Access Level: " .. slot)
        print("Card ID: " .. SecurityCore.truncateCardId(cardId))
        print("Expires: " .. utils.formatExpiration(expiration))
        print("Valid for: " .. tier.duration .. " days")
        print("Cost: " .. transaction.value .. " KRO")
        print("")
        print("The NFC card is now ready to use!")
        term.setTextColor(colors.white)
        
        -- Note: Success message already shown in handleNewSubscription
        
        return true
    end
    
    return false
end

--- Write NFC card for renewal with extended expiration
-- @param tac table - TAC instance
-- @param options table - renewal options
-- @return boolean - success status
function shop_handler.writeRenewalNFCCard(tac, options)
    local username = options.username
    local accessTag = options.accessTag
    local tier = options.tier
    local transaction = options.transaction
    local originalCard = options.originalCard
    
    -- Generate new card ID
    local SecurityCore = require("tac.core.security")
    local newCardId = SecurityCore.randomString(128)
    
    -- Calculate new expiration (extend from current expiration or now, whichever is later)
    local currentExpiration = originalCard.expiration or os.epoch("utc")
    local baseTime = math.max(currentExpiration, os.epoch("utc"))
    local newExpiration = baseTime + (tier.duration * 24 * 60 * 60 * 1000)
    
    -- Persist write state before starting
    nfcWriteState.set("active", {
        type = "renewal",
        cardId = newCardId,
        username = username,
        accessTag = accessTag,
        tier = tier,
        transaction = transaction,
        originalCard = originalCard,
        newExpiration = newExpiration,
        startTime = os.epoch("utc")
    })
    
    term.setTextColor(colors.yellow)
    print("Writing new NFC card for renewal...")
    print("New Card ID: " .. SecurityCore.truncateCardId(newCardId))
    print("New Expiration: " .. utils.formatExpiration(newExpiration))
    print("")
    print("Please place a blank NFC card on the server NFC reader...")
    print("Press 'q' to cancel the card writing process.")
    term.setTextColor(colors.white)
    
    -- Show NFC writing screen on monitor if available
    if monitor_ui.isAvailable() then
        monitor_ui.showNFCWriting({
            username = username,
            cardId = newCardId
        })
    end
    
    -- Get server NFC reader
    local serverNfc = tac.getServerNfc()
    if not serverNfc then
        term.setTextColor(colors.red)
        print("ERROR: No server NFC reader configured!")
        term.setTextColor(colors.white)
        return false
    end
    
    -- Start NFC writing
    serverNfc.write(newCardId, username .. " (" .. accessTag .. " - Renewed)")
    
    -- Wait for completion
    local writeSuccessful = false
    local timeout = os.startTimer(30)
    
    while true do
        local event, param1, param2 = os.pullEvent()
        
        if event == "nfc_write" and param1 == peripheral.getName(serverNfc) then
            writeSuccessful = true
            break
        elseif event == "key" and param1 == keys.q then
            serverNfc.cancelWrite()
            nfcWriteState.unset("active")
            term.setTextColor(colors.yellow)
            print("Card writing cancelled.")
            term.setTextColor(colors.white)
            if monitor_ui.isAvailable() then
                monitor_ui.showError("Card writing cancelled")
                os.sleep(2)
            end
            refundWithError(transaction, "Renewal card writing cancelled by user")
            return false
        elseif event == "timer" and param1 == timeout then
            serverNfc.cancelWrite()
            nfcWriteState.unset("active")
            term.setTextColor(colors.red)
            print("Card writing timed out.")
            term.setTextColor(colors.white)
            if monitor_ui.isAvailable() then
                monitor_ui.showError("Card writing timed out (30 seconds)")
                os.sleep(3)
            end
            refundWithError(transaction, "Renewal NFC write timeout - no card placed within 30 seconds")
            return false
        elseif event == "nfc_write_error" then
            nfcWriteState.unset("active")
            term.setTextColor(colors.red)
            print("NFC write error: " .. tostring(param2))
            term.setTextColor(colors.white)
            if monitor_ui.isAvailable() then
                monitor_ui.showError("NFC write error: " .. tostring(param2))
                os.sleep(3)
            end
            refundWithError(transaction, "Renewal NFC write error: " .. tostring(param2))
            return false
        end
    end
    
    if writeSuccessful then
        -- Clear persisted write state
        nfcWriteState.unset("active")
        
        -- Remove old card and create new one
        tac.cards.unset(originalCard.id)
        
        -- Create new card with renewed access
        local newCard, error = tac.cardManager.createCard({
            id = newCardId,
            name = username .. " (" .. accessTag .. " - Renewed)",
            tags = originalCard.tags,
            expiration = newExpiration,
            username = username,
            createdBy = "shopk_renewal",
            metadata = {
                originalCardId = originalCard.id,
                accessTag = accessTag,
                renewalTransactionId = transaction.id,
                renewalValue = transaction.value,
                renewedFrom = originalCard.expiration,
                fromAddress = transaction.from
            },
            logMessage = "Renewal NFC card created: " .. accessTag .. " for " .. username .. " expires " .. utils.formatExpiration(newExpiration) .. " (" .. transaction.value .. " KRO)"
        })
        
        if not newCard then
            term.setTextColor(colors.red)
            print("ERROR: NFC card written but failed to save renewal data!")
            print("Error: " .. (error or "Unknown error"))
            term.setTextColor(colors.white)
            if monitor_ui.isAvailable() then
                monitor_ui.showError("NFC card written but failed to save renewal data: " .. (error or "Unknown error"))
                os.sleep(3)
            end
            return false
        end
        
        term.setTextColor(colors.lime)
        print("=== Renewal NFC Card Created ===")
        print("Player: " .. username)
        print("Access Level: " .. accessTag)
        print("New Card ID: " .. SecurityCore.truncateCardId(newCardId))
        print("Extended Until: " .. utils.formatExpiration(newExpiration))
        print("Old card has been deactivated.")
        print("New NFC card is ready to use!")
        term.setTextColor(colors.white)
        
        if monitor_ui.isAvailable() then
            monitor_ui.showSuccess("Renewal card created successfully!", {
                ["Player"] = username,
                ["Access"] = accessTag,
                ["Expires"] = utils.formatExpiration(newExpiration),
                ["Note"] = "Old card deactivated"
            })
            os.sleep(5)
        end
        
        return true
    end
    
    return false
end

--- Send a refund to a Krist address
-- @param toAddress string - address to send refund to
-- @param amount number - amount to refund in KRO
-- @param reason string - reason for refund (used in transaction metadata)
-- @param callback function - callback function to handle result
function shop_handler.sendRefund(toAddress, amount, reason, callback)
    if not shop then
        if callback then callback(false, "Shop is not running") end
        return
    end
    
    -- Send the refund transaction with error metadata
    shop.makeTransaction(toAddress, amount, {
        refund = "true",
        error = reason or "Subscription refund"
    }, function(data)
        if data.ok then
            term.setTextColor(colors.green)
            print(string.format("Refund sent: %d KRO to %s", amount, toAddress))
            term.setTextColor(colors.white)
            if callback then callback(true, "Refund sent successfully", data.transaction) end
        else
            term.setTextColor(colors.red)
            print(string.format("Refund failed: %s", data.error or "Unknown error"))
            term.setTextColor(colors.white)
            if callback then callback(false, data.error or "Refund transaction failed") end
        end
    end)
end

--- Check if shop is running and can send refunds
-- @return boolean - true if shop can send refunds
function shop_handler.canSendRefunds()
    return shop ~= nil and shop.makeTransaction ~= nil
end

return shop_handler