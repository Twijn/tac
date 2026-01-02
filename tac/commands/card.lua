-- TAC Card Command Module
-- Handles card management commands with NFC/RFID scan type support

local CardCommand = {}

function CardCommand.create(tac)
    local formui = require("formui")
    local SecurityCore = tac.Security or require("tac.core.security")
    
    --- Get list of all available tags from cards and doors for multiselect
    -- @return table Array of unique tags
    local function getAvailableTags()
        local tags = {}
        local seen = {}
        
        -- Collect tags from all cards
        for _, cardData in pairs(tac.cards.getAll()) do
            for _, tag in ipairs(cardData.tags or {}) do
                if not seen[tag] then
                    seen[tag] = true
                    table.insert(tags, tag)
                end
            end
        end
        
        -- Collect tags from all doors
        for _, doorData in pairs(tac.doors.getAll()) do
            for _, tag in ipairs(doorData.tags or {}) do
                if not seen[tag] then
                    seen[tag] = true
                    table.insert(tags, tag)
                end
            end
        end
        
        -- Add common default tags
        local defaults = {"admin", "staff", "tenant", "visitor", "vip"}
        for _, tag in ipairs(defaults) do
            if not seen[tag] then
                seen[tag] = true
                table.insert(tags, tag)
            end
        end
        
        table.sort(tags)
        return tags
    end
    
    --- Find which index the current tags match in the available options
    -- @param currentTags table Current card tags
    -- @param availableTags table All available tags
    -- @return table Map of indices to boolean
    local function tagsToIndices(currentTags, availableTags)
        local indices = {}
        for i, tag in ipairs(availableTags) do
            for _, currentTag in ipairs(currentTags or {}) do
                if tag == currentTag then
                    indices[i] = true
                    break
                end
            end
        end
        return indices
    end
    
    --- Convert scanType checkboxes to string format
    -- @param nfc boolean NFC enabled
    -- @param rfid boolean RFID enabled
    -- @return string "nfc", "rfid", "both", or nil
    local function getScanTypeFromCheckboxes(nfc, rfid)
        if nfc and rfid then
            return "both"
        elseif nfc then
            return "nfc"
        elseif rfid then
            return "rfid"
        else
            return "both" -- Default to both if nothing selected
        end
    end
    
    --- Get checkbox states from scanType string
    -- @param scanType string "nfc", "rfid", "both", or nil
    -- @return boolean, boolean - nfc, rfid enabled states
    local function getCheckboxesFromScanType(scanType)
        if scanType == "nfc" then
            return true, false
        elseif scanType == "rfid" then
            return false, true
        else
            return true, true -- Default to both
        end
    end
    
    return {
        name = "card",
        description = "Manage access cards with NFC/RFID support",
        complete = function(args)
            if #args == 1 then
                return {"grant", "revoke", "list", "edit"}
            elseif #args > 1 and (args[1]:lower() == "revoke" or args[1]:lower() == "edit") then
                local cardNames = {}
                for _, data in pairs(tac.cards.getAll()) do
                    table.insert(cardNames, data.name)
                end
                return cardNames
            end
            return {}
        end,
        execute = function(args, d)
            local cmdName = (args[1] or "list"):lower()

            if cmdName == "grant" then
                -- Use formui for card creation
                local grantForm = formui.new("Create New Card")
                
                local getName = grantForm:text("Name")
                
                -- Tags section
                grantForm:label("Access Tags")
                local availableTags = getAvailableTags()
                local getTagsMulti
                if #availableTags > 0 then
                    getTagsMulti = grantForm:multiselect("Select Tags", availableTags, {})
                end
                local getTagsCustom = grantForm:text("Custom Tags", "", nil, true)
                
                -- Scan type section
                grantForm:label("Scanner Compatibility")
                local getNfcEnabled = grantForm:checkbox("Allow NFC", true)
                local getRfidEnabled = grantForm:checkbox("Allow RFID", true)
                
                grantForm:addSubmitCancel()
                
                local result = grantForm:run()
                
                if result then
                    local cardName = getName()
                    
                    if not cardName or cardName == "" then
                        d.err("Card name cannot be empty!")
                        return
                    end
                    
                    -- Combine tags
                    local tags = {}
                    if getTagsMulti then
                        local selectedTags = getTagsMulti()
                        for _, tag in ipairs(selectedTags) do
                            table.insert(tags, tag)
                        end
                    end
                    
                    local customTagsStr = getTagsCustom()
                    if customTagsStr and customTagsStr ~= "" then
                        local customTags = SecurityCore.parseTags(customTagsStr)
                        for _, tag in ipairs(customTags) do
                            local exists = false
                            for _, t in ipairs(tags) do
                                if t == tag then exists = true break end
                            end
                            if not exists then
                                table.insert(tags, tag)
                            end
                        end
                    end
                    
                    -- Default to admin if no tags
                    if #tags == 0 then
                        tags = {"admin"}
                    end
                    
                    local nfcEnabled = getNfcEnabled()
                    local rfidEnabled = getRfidEnabled()
                    local scanType = getScanTypeFromCheckboxes(nfcEnabled, rfidEnabled)
                    
                    local data = SecurityCore.randomString(128)
                    
                    tac.logger.logAccess("card_creation_started", {
                        card = {
                            name = cardName,
                            tags = tags,
                            scanType = scanType
                        },
                        message = string.format("Creating card named %s with tags: %s (scanType: %s)", 
                            cardName, table.concat(tags, ", "), scanType)
                    })
                    
                    d.mess("Right-click the NFC card to create. Press 'q' to cancel.")

                    -- Get server NFC reader
                    local serverNfc = tac.getServerNfc()
                    if not serverNfc then
                        d.err("No server NFC reader configured!")
                        d.mess("Please ensure an NFC reader is connected.")
                        return
                    end

                    serverNfc.write(data, cardName)

                    while true do
                        local e = table.pack(os.pullEvent())

                        if e[1] == "nfc_write" and e[2] == peripheral.getName(serverNfc) then
                            local cardData, error = tac.cardManager.createCard({
                                id = data,
                                name = cardName,
                                tags = tags,
                                scanType = scanType,
                                createdBy = "manual",
                                logMessage = "Card creation successful"
                            })
                            
                            if cardData then
                                d.mess("Card created successfully!")
                                d.mess("Name: " .. cardName)
                                d.mess("Tags: " .. table.concat(tags, ", "))
                                d.mess("Scan Type: " .. scanType)
                            else
                                d.err("Card creation failed: " .. (error or "Unknown error"))
                            end
                            break
                        elseif e[1] == "key" and e[2] == keys.q then
                            serverNfc.cancelWrite()
                            tac.logger.logAccess("card_creation_cancelled", {
                                card = {
                                    name = cardName,
                                    tags = tags
                                },
                                message = "Card creation was cancelled"
                            })
                            d.mess("Cancelled")
                            break
                        end
                    end
                else
                    d.err("Card creation cancelled.")
                end
                
            elseif cmdName == "revoke" then
                local cardName = table.concat(args, " ", 2)
                if cardName and #cardName > 0 then
                    local cardsToRemove = {}
                    for card, data in pairs(tac.cards.getAll()) do
                        if data.name == cardName then
                            table.insert(cardsToRemove, card)
                        end
                    end
                    
                    if #cardsToRemove > 0 then
                        d.mess(string.format("Found %d card(s) with name '%s'. Delete all? (y/N)", #cardsToRemove, cardName))
                        local response = read():lower()
                        if response == "y" then
                            for _, card in pairs(cardsToRemove) do
                                tac.cards.unset(card)
                            end
                            d.mess(string.format("Deleted %d card(s)", #cardsToRemove))
                        else
                            d.mess("Cancelled.")
                        end
                    else
                        d.err("No cards found with name: " .. cardName)
                    end
                else
                    d.err("You must provide a card name to revoke!")
                end
                
            elseif cmdName == "list" then
                local interactiveList = require("tac.lib.interactive_list")
                local allCards = tac.cards.getAll()
                
                -- Convert cards to list format
                local cardItems = {}
                for cardID, data in pairs(allCards) do
                    table.insert(cardItems, {
                        id = cardID,
                        name = data.name or "Unknown",
                        tags = data.tags or {},
                        scanType = data.scanType or "both",
                        expiration = data.expiration,
                        username = data.username,
                        createdBy = data.createdBy,
                        createdAt = data.createdAt,
                        metadata = data.metadata
                    })
                end
                
                -- Sort by name
                table.sort(cardItems, function(a, b) return a.name < b.name end)
                
                if #cardItems == 0 then
                    d.mess("No cards registered.")
                    return
                end
                
                -- Show interactive list
                interactiveList.show({
                    title = "Registered Cards",
                    items = cardItems,
                    formatItem = function(card)
                        local scanIcon = ""
                        if card.scanType == "nfc" then
                            scanIcon = " [NFC]"
                        elseif card.scanType == "rfid" then
                            scanIcon = " [RFID]"
                        end
                        return card.name .. scanIcon .. " (" .. SecurityCore.truncateCardId(card.id) .. ")"
                    end,
                    formatDetails = function(card)
                        local details = {}
                        table.insert(details, "Name: " .. card.name)
                        table.insert(details, "ID: " .. SecurityCore.truncateCardId(card.id))
                        table.insert(details, "")
                        table.insert(details, "Tags: " .. table.concat(card.tags, ", "))
                        table.insert(details, "")
                        table.insert(details, "Scan Type: " .. (card.scanType or "both"))
                        
                        if card.expiration then
                            local now = os.epoch("utc")
                            local expired = card.expiration < now
                            local timeLeft = card.expiration - now
                            local daysLeft = math.floor(timeLeft / (24 * 60 * 60 * 1000))
                            
                            table.insert(details, "")
                            if expired then
                                table.insert(details, "Status: EXPIRED")
                                table.insert(details, "Expired: " .. math.abs(daysLeft) .. " days ago")
                            else
                                table.insert(details, "Status: Active")
                                table.insert(details, "Expires in: " .. daysLeft .. " days")
                            end
                        end
                        
                        if card.username then
                            table.insert(details, "")
                            table.insert(details, "Username: " .. card.username)
                        end
                        
                        if card.createdBy then
                            table.insert(details, "Created by: " .. card.createdBy)
                        end
                        
                        return details
                    end
                })
                
                term.clear()
                term.setCursorPos(1, 1)
                
            elseif cmdName == "edit" then
                local cardName = table.concat(args, " ", 2)
                
                if not cardName or cardName == "" then
                    d.err("You must specify a card name to edit!")
                    d.mess("Usage: card edit <card_name>")
                    d.mess("Available cards:")
                    for _, cardData in pairs(tac.cards.getAll()) do
                        d.mess("  - " .. cardData.name)
                    end
                    return
                end
                
                -- Find the card by name
                local targetCardId = nil
                local targetCard = nil
                for cardId, cardData in pairs(tac.cards.getAll()) do
                    if cardData.name == cardName then
                        targetCardId = cardId
                        targetCard = cardData
                        break
                    end
                end
                
                if not targetCard then
                    d.err("Card '" .. cardName .. "' not found!")
                    return
                end
                
                d.mess("Editing card: " .. cardName)
                d.mess("Card ID: " .. SecurityCore.truncateCardId(targetCardId))
                
                -- Create edit form with current values pre-filled
                local editForm = formui.new("Edit Card: " .. cardName)
                
                local getName = editForm:text("Name", targetCard.name)
                
                -- Tags section
                editForm:label("Access Tags")
                local availableTags = getAvailableTags()
                local currentTagIndices = tagsToIndices(targetCard.tags, availableTags)
                
                local getTagsMulti
                if #availableTags > 0 then
                    getTagsMulti = editForm:multiselect("Select Tags", availableTags, currentTagIndices)
                end
                
                -- Find custom tags not in available list
                local customTags = {}
                for _, tag in ipairs(targetCard.tags or {}) do
                    local found = false
                    for _, availTag in ipairs(availableTags) do
                        if tag == availTag then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(customTags, tag)
                    end
                end
                local getTagsCustom = editForm:text("Custom Tags", table.concat(customTags, ","), nil, true)
                
                -- Scan type section
                editForm:label("Scanner Compatibility")
                local currentNfc, currentRfid = getCheckboxesFromScanType(targetCard.scanType)
                local getNfcEnabled = editForm:checkbox("Allow NFC", currentNfc)
                local getRfidEnabled = editForm:checkbox("Allow RFID", currentRfid)
                
                editForm:label("Card ID cannot be changed")
                editForm:addSubmitCancel()
                
                local result = editForm:run()
                
                if result then
                    local newName = getName()
                    
                    -- Combine tags
                    local tags = {}
                    if getTagsMulti then
                        local selectedTags = getTagsMulti()
                        for _, tag in ipairs(selectedTags) do
                            table.insert(tags, tag)
                        end
                    end
                    
                    local customTagsStr = getTagsCustom()
                    if customTagsStr and customTagsStr ~= "" then
                        local parsedCustomTags = SecurityCore.parseTags(customTagsStr)
                        for _, tag in ipairs(parsedCustomTags) do
                            local exists = false
                            for _, t in ipairs(tags) do
                                if t == tag then exists = true break end
                            end
                            if not exists then
                                table.insert(tags, tag)
                            end
                        end
                    end
                    
                    local nfcEnabled = getNfcEnabled()
                    local rfidEnabled = getRfidEnabled()
                    local scanType = getScanTypeFromCheckboxes(nfcEnabled, rfidEnabled)
                    
                    if newName and newName ~= "" then
                        -- Update the card data
                        targetCard.name = newName
                        targetCard.tags = tags
                        targetCard.scanType = scanType
                        
                        tac.cards.set(targetCardId, targetCard)
                        
                        d.mess("Card updated successfully!")
                        d.mess("Name: " .. newName)
                        d.mess("Tags: " .. table.concat(tags, ", "))
                        d.mess("Scan Type: " .. scanType)
                        d.mess("Card ID: " .. SecurityCore.truncateCardId(targetCardId))
                    else
                        d.err("Card name cannot be empty!")
                    end
                else
                    d.err("Card edit cancelled.")
                end
            else
                d.err("Unknown card command! Use: grant, revoke, list, edit")
            end
        end
    }
end

return CardCommand