-- TAC Card Command Module
-- Handles card management commands

local CardCommand = {}

function CardCommand.create(tac)
    local formui = require("formui")
    local SecurityCore = tac.Security or require("tac.core.security")
    
    return {
        description = "Manage NFC cards",
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
            local cmdName = (args[1] or ""):lower()

            if cmdName == "grant" then
                local data = SecurityCore.randomString(128)
                local cardName = table.concat(args, " ", 2)

                if cardName and #cardName > 0 then
                    d.mess("Provided name: " .. cardName)
                    d.mess("Enter tags to apply to the card (comma-delimited): ")
                    local tagsString = read()
                    local tags = SecurityCore.parseTags(tagsString)
                    
                    tac.logger.logAccess("card_creation_started", {
                        card = {
                            name = cardName,
                            tags = tags
                        },
                        message = string.format("Creating NFC card named %s with tags: %s", cardName, table.concat(tags, ", "))
                    })
                    
                    d.mess("Right-click the card to create. Press 'q' to cancel.")

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
                                createdBy = "manual",
                                logMessage = "NFC card creation successful"
                            })
                            
                            if cardData then
                                d.mess("Card created successfully!")
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
                                message = "NFC card creation was cancelled"
                            })
                            d.mess("Cancelled")
                            break
                        end
                    end
                else
                    d.err("You must provide a name for the card!")
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
                            d.mess(string.format("Deleted %d NFC card(s)", #cardsToRemove))
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
                local allCards = tac.cards.getAll()
                term.setCursorPos(1,1)
                term.clear()
                print(string.format("%-10s %-15s %-30s", "ID", "Name", "Tags"))
                print(string.rep("-", 60))
                for cardID, data in pairs(allCards) do
                    print(string.format("%-10s %-15s %-30s", 
                        SecurityCore.truncateCardId(cardID), 
                        data.name or "Unknown", 
                        table.concat(data.tags or {}, ", ")))
                end
                print("\nPress any key to continue")
                os.pullEvent("key")
                sleep()
                
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
                local getTagsText = editForm:text("Tags", table.concat(targetCard.tags or {}, ","))
                
                editForm:label("Note: Card ID cannot be changed - it's tied to the physical NFC card")
                editForm:addSubmitCancel()
                
                local result = editForm:run()
                
                if result then
                    local newName = getName()
                    local newTagsString = getTagsText()
                    
                    -- Validate and parse new values
                    local newTags = SecurityCore.parseTags(newTagsString)
                    
                    if newName and newName ~= "" then
                        -- Update the card data
                        targetCard.name = newName
                        targetCard.tags = newTags
                        
                        tac.cards.set(targetCardId, targetCard)
                        
                        d.mess("Card updated successfully!")
                        d.mess("Name: " .. newName)
                        d.mess("Tags: " .. table.concat(newTags, ", "))
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