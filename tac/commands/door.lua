-- TAC Door Command Module
-- Handles door management commands with NFC and RFID support

local DoorCommand = {}

function DoorCommand.create(tac)
    local formui = require("formui")
    local SecurityCore = tac.Security or require("tac.core.security")
    local HardwareManager = tac.Hardware or require("tac.core.hardware")
    
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
        local defaults = {"*", "admin", "staff", "tenant", "visitor", "vip"}
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
    -- @param currentTags table Current door tags
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
    
    return {
        name = "door",
        description = "Control, manage, and add doors with NFC/RFID support",
        complete = function(args)
            if #args == 1 then
                return {"setup", "delete", "list", "edit", "test"}
            elseif #args == 2 and (args[1]:lower() == "edit" or args[1]:lower() == "delete" or args[1]:lower() == "test") then
                -- Return list of existing door names
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
                local setupForm = formui.new("Setup New Door")

                local getName = setupForm:text("Name")
                
                -- Scanner section label
                setupForm:label("Scanner Config (at least one required)")
                
                -- NFC Reader (optional now)
                local getNfcReader = setupForm:peripheral("NFC Reader", "nfc_reader", function(v, f)
                    local value = f.options[v]
                    if value then
                        if tac.doors.get(value) then
                            return false, "NFC reader already used for " .. tac.doors.get(value).name
                        end
                    end
                    return true -- Allow empty selection
                end, 0)
                
                -- RFID Scanner (optional)
                local getRfidScanner = setupForm:peripheral("RFID Scanner", "rfid_scanner", function(v, f)
                    local value = f.options[v]
                    if value then
                        -- Check if already used by another door
                        for _, doorData in pairs(tac.doors.getAll()) do
                            if doorData.rfidScanner == value then
                                return false, "RFID scanner already used for " .. doorData.name
                            end
                        end
                    end
                    return true -- Allow empty selection
                end, 0)
                
                -- Display section
                setupForm:label("Display Config (both optional)")
                
                local getSign = setupForm:peripheral("Sign", "minecraft:sign", nil, 0)
                local getMonitor = setupForm:peripheral("Monitor", "monitor", nil, 0)
                
                -- Hardware section
                setupForm:label("Door Control")
                
                local getRelay = setupForm:peripheral("Redstone Relay", "redstone_relay", nil, 0)
                local getOpenTime = setupForm:number("Open Time (seconds)", SecurityCore.DEFAULT_OPEN_TIME, formui.validation.number_positive)
                
                -- RFID Distance settings
                setupForm:label("RFID Distance Limit")
                local getMaxDistance = setupForm:number("Max Distance (0=unlimited)", 0, function(v)
                    return v >= 0, "Distance must be >= 0"
                end)
                
                -- Tags section
                setupForm:label("Access Tags")
                
                local availableTags = getAvailableTags()
                local getTagsMulti
                if #availableTags > 0 then
                    getTagsMulti = setupForm:multiselect("Select Tags", availableTags, {})
                end
                local getTagsCustom = setupForm:text("Custom Tags", "", nil, true)
                
                setupForm:addSubmitCancel()

                local result = setupForm:run()

                if result then
                    local name = getName()
                    local nfcReader = getNfcReader()
                    local rfidScanner = getRfidScanner()
                    
                    -- Validate at least one scanner
                    if (not nfcReader or nfcReader == "") and (not rfidScanner or rfidScanner == "") then
                        d.err("At least one scanner (NFC or RFID) is required!")
                        return
                    end
                    
                    -- Combine tags from multiselect and custom text
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
                            -- Avoid duplicates
                            local exists = false
                            for _, t in ipairs(tags) do
                                if t == tag then exists = true break end
                            end
                            if not exists then
                                table.insert(tags, tag)
                            end
                        end
                    end
                    
                    -- Default to wildcard if no tags
                    if #tags == 0 then
                        tags = {"*"}
                    end
                    
                    local sign = getSign()
                    local monitor = getMonitor()
                    local relay = getRelay()
                    local openTime = getOpenTime()
                    local maxDistance = getMaxDistance()
                    if maxDistance == 0 then maxDistance = nil end
                    
                    -- Determine primary key (prefer NFC reader for backwards compatibility)
                    local doorKey = nfcReader
                    if not doorKey or doorKey == "" then
                        doorKey = rfidScanner
                    end
                    
                    local doorData = {
                        name = name,
                        relay = (relay and relay ~= "") and relay or nil,
                        sign = (sign and sign ~= "") and sign or nil,
                        monitor = (monitor and monitor ~= "") and monitor or nil,
                        nfcReader = (nfcReader and nfcReader ~= "") and nfcReader or nil,
                        rfidScanner = (rfidScanner and rfidScanner ~= "") and rfidScanner or nil,
                        tags = tags,
                        openTime = openTime,
                        maxDistance = maxDistance
                    }
                    
                    tac.doors.set(doorKey, doorData)
                    
                    -- Update displays
                    HardwareManager.updateDoorSign(doorData)
                    HardwareManager.updateDoorMonitor(doorData)
                    
                    d.mess("Door created successfully!")
                    d.mess("Name: " .. name)
                    d.mess("Scanner(s): " .. (doorData.nfcReader or "none") .. " / " .. (doorData.rfidScanner or "none"))
                    d.mess("Tags: " .. table.concat(tags, ", "))
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
                        nfcReader = doorData.nfcReader or (doorData.rfidScanner == nil and reader or nil),
                        rfidScanner = doorData.rfidScanner,
                        relay = doorData.relay,
                        sign = doorData.sign,
                        monitor = doorData.monitor,
                        tags = doorData.tags,
                        openTime = doorData.openTime,
                        maxDistance = doorData.maxDistance
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
                        table.insert(details, "Scanners:")
                        table.insert(details, "  NFC:  " .. (door.nfcReader or "None"))
                        table.insert(details, "  RFID: " .. (door.rfidScanner or "None"))
                        table.insert(details, "")
                        table.insert(details, "Display:")
                        table.insert(details, "  Sign:    " .. (door.sign or "None"))
                        table.insert(details, "  Monitor: " .. (door.monitor or "None"))
                        table.insert(details, "")
                        table.insert(details, "Control:")
                        table.insert(details, "  Relay: " .. (door.relay or "None"))
                        table.insert(details, "  Open Time: " .. (door.openTime or SecurityCore.DEFAULT_OPEN_TIME) .. "s")
                        if door.maxDistance then
                            table.insert(details, "  Max Distance: " .. door.maxDistance .. "m")
                        end
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
                local getOpenTime = editForm:number("Open Time (seconds)", currentDoor.openTime or SecurityCore.DEFAULT_OPEN_TIME)
                
                -- RFID Distance settings
                editForm:label("RFID Distance Limit")
                local getMaxDistance = editForm:number("Max Distance (0=unlimited)", currentDoor.maxDistance or 0, function(v)
                    return v >= 0, "Distance must be >= 0"
                end)
                
                -- Tags section
                editForm:label("Access Tags")
                local availableTags = getAvailableTags()
                local currentTagIndices = tagsToIndices(currentDoor.tags, availableTags)
                
                local getTagsMulti
                if #availableTags > 0 then
                    getTagsMulti = editForm:multiselect("Select Tags", availableTags, currentTagIndices)
                end
                
                -- Find custom tags not in available list
                local customTags = {}
                for _, tag in ipairs(currentDoor.tags or {}) do
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
                
                -- Scanner info (read-only display)
                editForm:label("Hardware (delete & re-setup to change):")
                editForm:label("  NFC: " .. (currentDoor.nfcReader or "None"))
                editForm:label("  RFID: " .. (currentDoor.rfidScanner or "None"))
                editForm:label("  Sign: " .. (currentDoor.sign or "None"))
                editForm:label("  Monitor: " .. (currentDoor.monitor or "None"))
                
                editForm:addSubmitCancel()
                
                local result = editForm:run()
                
                if result then
                    local newName = getName()
                    local newOpenTime = getOpenTime()
                    local newMaxDistance = getMaxDistance()
                    if newMaxDistance == 0 then newMaxDistance = nil end
                    
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
                    
                    if newName and newName ~= "" then
                        -- Update the door data
                        currentDoor.name = newName
                        currentDoor.tags = tags
                        currentDoor.openTime = newOpenTime
                        currentDoor.maxDistance = newMaxDistance
                        
                        tac.doors.set(doorReader, currentDoor)
                        
                        -- Update displays
                        HardwareManager.updateDoorSign(currentDoor)
                        HardwareManager.updateDoorMonitor(currentDoor)
                        
                        d.mess("Door updated successfully!")
                        d.mess("Name: " .. newName)
                        d.mess("Tags: " .. table.concat(tags, ", "))
                        d.mess("Open Time: " .. newOpenTime .. " seconds")
                    else
                        d.err("Door name cannot be empty!")
                    end
                else
                    d.err("Door edit cancelled.")
                end
                
            elseif cmd == "test" then
                local doorName = table.concat(args, " ", 2)
                
                if not doorName or doorName == "" then
                    d.err("You must specify a door name to test!")
                    d.mess("Usage: door test <door_name>")
                    return
                end
                
                -- Find the door by name
                local currentDoor = nil
                for reader, doorData in pairs(tac.doors.getAll()) do
                    if doorData.name == doorName then
                        currentDoor = doorData
                        break
                    end
                end
                
                if not currentDoor then
                    d.err("Door '" .. doorName .. "' not found!")
                    return
                end
                
                d.mess("Testing door: " .. doorName)
                d.mess("Opening for " .. (currentDoor.openTime or SecurityCore.DEFAULT_OPEN_TIME) .. " seconds...")
                
                HardwareManager.openDoor(currentDoor, "Test User", currentDoor.openTime)
                
                d.mess("Door test complete.")
                
            else
                d.err("Unknown door command! Use: setup, delete, list, edit, test")
            end
            
            -- Update displays after any changes
            HardwareManager.updateAllDisplays(tac.doors)
        end
    }
end

return DoorCommand