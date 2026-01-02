-- TAC Migration Command Module
-- Migrates legacy cards to the new identity system

local MigrateCommand = {}

function MigrateCommand.create(tac)
    local SecurityCore = tac.Security or require("tac.core.security")
    
    return {
        name = "migrate",
        description = "Migrate legacy cards to identities",
        complete = function(args)
            if #args == 1 then
                return {"cards", "preview", "status"}
            end
            return {}
        end,
        execute = function(args, d)
            local cmd = (args[1] or "status"):lower()
            
            if cmd == "status" then
                local cardCount = 0
                local identityCount = 0
                
                for _ in pairs(tac.cards.getAll()) do
                    cardCount = cardCount + 1
                end
                
                for _ in pairs(tac.identities.getAll()) do
                    identityCount = identityCount + 1
                end
                
                d.mess("=== Migration Status ===")
                d.mess("")
                d.mess("Legacy Cards: " .. cardCount)
                d.mess("Identities: " .. identityCount)
                d.mess("")
                
                if cardCount > 0 then
                    d.mess("Run 'migrate preview' to see what will be migrated.")
                    d.mess("Run 'migrate cards' to perform the migration.")
                else
                    d.mess("No legacy cards to migrate!")
                end
                
            elseif cmd == "preview" then
                local cards = tac.cards.getAll()
                local count = 0
                
                d.mess("=== Migration Preview ===")
                d.mess("")
                
                for cardId, cardData in pairs(cards) do
                    count = count + 1
                    d.mess(count .. ". " .. (cardData.name or "Unnamed"))
                    d.mess("   ID: " .. SecurityCore.truncateCardId(cardId))
                    d.mess("   Tags: " .. table.concat(cardData.tags or {}, ", "))
                    
                    local scanType = cardData.scanType or "both"
                    local nfcEnabled = scanType == "nfc" or scanType == "both"
                    local rfidEnabled = scanType == "rfid" or scanType == "both"
                    
                    d.mess("   Will enable: " .. 
                        (nfcEnabled and "NFC " or "") .. 
                        (rfidEnabled and "RFID" or ""))
                    d.mess("")
                end
                
                if count == 0 then
                    d.mess("No legacy cards to migrate!")
                else
                    d.mess("Total: " .. count .. " cards will be migrated.")
                    d.mess("")
                    d.mess("Note: Legacy cards will be preserved for backwards compatibility.")
                    d.mess("Run 'migrate cards' to perform the migration.")
                end
                
            elseif cmd == "cards" then
                local cards = tac.cards.getAll()
                local count = 0
                local migrated = 0
                local skipped = 0
                
                for cardId, cardData in pairs(cards) do
                    count = count + 1
                end
                
                if count == 0 then
                    d.mess("No legacy cards to migrate!")
                    return
                end
                
                d.mess("Migrating " .. count .. " legacy cards to identities...")
                d.mess("This will create identities with the same NFC data.")
                d.mess("Continue? (y/N)")
                
                local response = read():lower()
                if response ~= "y" then
                    d.mess("Cancelled.")
                    return
                end
                
                d.mess("")
                
                for cardId, cardData in pairs(cards) do
                    -- Check if identity already exists with this name
                    local exists = false
                    for _, identity in pairs(tac.identities.getAll()) do
                        if identity.name == cardData.name then
                            exists = true
                            break
                        end
                    end
                    
                    if exists then
                        d.mess("Skipped: " .. (cardData.name or "Unnamed") .. " (already exists)")
                        skipped = skipped + 1
                    else
                        local scanType = cardData.scanType or "both"
                        local nfcEnabled = scanType == "nfc" or scanType == "both"
                        local rfidEnabled = scanType == "rfid" or scanType == "both"
                        
                        -- Create identity with the same NFC data
                        local identity, err = tac.identityManager.createIdentity({
                            name = cardData.name or "Migrated Card",
                            tags = cardData.tags or {},
                            nfcEnabled = nfcEnabled,
                            rfidEnabled = rfidEnabled,
                            nfcData = cardId,  -- Use the card ID as NFC data
                            expiration = cardData.expiration,
                            createdBy = "migration",
                            metadata = {
                                migratedFrom = "card",
                                originalCardId = cardId,
                                originalCreatedBy = cardData.createdBy,
                                migrationDate = os.epoch("utc")
                            }
                        })
                        
                        if identity then
                            d.mess("Migrated: " .. (cardData.name or "Unnamed"))
                            migrated = migrated + 1
                        else
                            d.mess("Failed: " .. (cardData.name or "Unnamed") .. " - " .. (err or "Unknown error"))
                            skipped = skipped + 1
                        end
                    end
                end
                
                d.mess("")
                d.mess("=== Migration Complete ===")
                d.mess("Migrated: " .. migrated)
                d.mess("Skipped: " .. skipped)
                d.mess("")
                d.mess("Legacy cards have been preserved.")
                d.mess("You can use 'card list' to view them.")
            else
                d.err("Unknown migrate command!")
                d.mess("Usage: migrate [status|preview|cards]")
            end
        end
    }
end

return MigrateCommand
