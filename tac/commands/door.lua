-- TAC Door Command Module
-- Handles door management commands

local DoorCommand = {}

function DoorCommand.create(tac)
    local formui = require("formui")
    local SecurityCore = tac.Security or require("tac.core.security")
    local HardwareManager = tac.Hardware or require("tac.core.hardware")
    
    return {
        name = "door",
        description = "Control, manage, and add doors",
        complete = function(args)
            if #args == 1 then
                return {"setup", "delete", "list", "edit"}
            elseif #args == 2 and args[1]:lower() == "edit" then
                -- Return list of existing door names for editing
                local doorNames = {}
                for _, doorData in pairs(tac.doors.getAll()) do
                    table.insert(doorNames, doorData.name)
                end
                return doorNames
            end
            return {}
        end,
        execute = function(args, d)
            local cmd = (args[1] or ""):lower()

            if cmd == "setup" then
                local setupForm = formui.new("Setup new Door")

                local getName = setupForm:text("Name")
                local getReader = setupForm:peripheral("NFC Reader", "nfc_reader", function(v, f)
                    local value = f.options[v]
                    if value then
                        if tac.doors.get(value) then
                            return false, "NFC reader already used for " .. tac.doors.get(value).name
                        else
                            return true
                        end
                    end
                    return false, "No NFC reader selected"
                end, 0)
                local getRelay = setupForm:peripheral("Redstone Relay", "redstone_relay", nil, 0)
                local getSign = setupForm:peripheral("Sign", "minecraft:sign", nil, 0)
                local getTagsText = setupForm:text("Tags", "admin,staff")
                setupForm:addSubmitCancel()

                local result = setupForm:run()

                if result then
                    local name = getName()
                    local tags = SecurityCore.parseTags(getTagsText())
                    tac.doors.set(getReader(), {
                        name = name,
                        relay = getRelay(),
                        sign = getSign(),
                        tags = tags
                    })
                    d.mess("Door created!")
                    sleep()
                else
                    d.err("Door setup aborted.")
                end
                
            elseif cmd == "delete" then
                local doorName = table.concat(args, " ", 2)
                if not doorName or doorName == "" then
                    d.err("You must specify a door name to delete!")
                    return
                end
                
                -- Find and delete door
                for reader, doorData in pairs(tac.doors.getAll()) do
                    if doorData.name == doorName then
                        d.mess("Are you sure you want to delete door '" .. doorName .. "'? (y/N)")
                        local response = read():lower()
                        if response == "y" then
                            tac.doors.unset(reader)
                            d.mess("Door deleted successfully.")
                        else
                            d.mess("Cancelled.")
                        end
                        return
                    end
                end
                d.err("Door '" .. doorName .. "' not found!")
                
            elseif cmd == "list" then
                local interactiveList = require("tac.lib.interactive_list")
                local allDoors = tac.doors.getAll()
                
                -- Convert doors to list format
                local doorItems = {}
                for reader, doorData in pairs(allDoors) do
                    table.insert(doorItems, {
                        name = doorData.name,
                        reader = reader,
                        relay = doorData.relay,
                        sign = doorData.sign,
                        tags = doorData.tags
                    })
                end
                
                -- Sort by name
                table.sort(doorItems, function(a, b) return a.name < b.name end)
                
                if #doorItems == 0 then
                    d.mess("No doors configured.")
                    return
                end
                
                -- Show interactive list
                interactiveList.show({
                    title = "Configured Doors",
                    items = doorItems,
                    formatItem = function(door) return door.name end,
                    formatDetails = function(door)
                        local details = {}
                        table.insert(details, "Name: " .. door.name)
                        table.insert(details, "")
                        table.insert(details, "Hardware:")
                        table.insert(details, "  Reader: " .. (door.reader or "None"))
                        table.insert(details, "  Relay:  " .. (door.relay or "None"))
                        table.insert(details, "  Sign:   " .. (door.sign or "None"))
                        table.insert(details, "")
                        table.insert(details, "Tags: " .. table.concat(door.tags or {}, ", "))
                        return details
                    end
                })
                
                term.clear()
                term.setCursorPos(1, 1)
                
            elseif cmd == "edit" then
                local doorName = table.concat(args, " ", 2)
                
                if not doorName or doorName == "" then
                    d.err("You must specify a door name to edit!")
                    d.mess("Usage: door edit <door_name>")
                    d.mess("Available doors:")
                    for _, doorData in pairs(tac.doors.getAll()) do
                        d.mess("  - " .. doorData.name)
                    end
                    return
                end
                
                -- Find the door by name
                local doorReader = nil
                local currentDoor = nil
                for reader, doorData in pairs(tac.doors.getAll()) do
                    if doorData.name == doorName then
                        doorReader = reader
                        currentDoor = doorData
                        break
                    end
                end
                
                if not currentDoor then
                    d.err("Door '" .. doorName .. "' not found!")
                    return
                end
                
                d.mess("Editing door: " .. doorName)
                
                -- Create edit form with current values pre-filled
                local editForm = formui.new("Edit Door: " .. doorName)
                
                local getName = editForm:text("Name", currentDoor.name)
                local getTagsText = editForm:text("Tags", table.concat(currentDoor.tags or {}, ","))
                local getOpenTime = editForm:text("Open Time (seconds)", tostring(currentDoor.openTime or SecurityCore.DEFAULT_OPEN_TIME))
                
                editForm:label("Note: To change hardware connections (NFC reader, relay, sign), delete and re-setup the door")
                editForm:addSubmitCancel()
                
                local result = editForm:run()
                
                if result then
                    local newName = getName()
                    local newTagsString = getTagsText()
                    local newOpenTimeStr = getOpenTime()
                    
                    -- Validate and parse new values
                    local newTags = SecurityCore.parseTags(newTagsString)
                    local newOpenTime = tonumber(newOpenTimeStr) or SecurityCore.DEFAULT_OPEN_TIME
                    
                    if newName and newName ~= "" then
                        -- Update the door data
                        currentDoor.name = newName
                        currentDoor.tags = newTags
                        currentDoor.openTime = newOpenTime
                        
                        tac.doors.set(doorReader, currentDoor)
                        
                        d.mess("Door updated successfully!")
                        d.mess("Name: " .. newName)
                        d.mess("Tags: " .. table.concat(newTags, ", "))
                        d.mess("Open Time: " .. newOpenTime .. " seconds")
                    else
                        d.err("Door name cannot be empty!")
                    end
                else
                    d.err("Door edit cancelled.")
                end
            else
                d.err("Unknown door command! Use: setup, delete, list, edit")
            end
            
            -- Update signs after any changes
            HardwareManager.updateAllSigns(tac.doors)
        end
    }
end

return DoorCommand