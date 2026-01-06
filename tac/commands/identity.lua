-- TAC Identity Command Module
-- Handles identity management with separate NFC/RFID credentials

local IdentityCommand = {}

function IdentityCommand.create(tac)
    local formui = require("formui")
    local SecurityCore = tac.Security or require("tac.core.security")
    local HardwareManager = tac.Hardware or require("tac.core.hardware")
    
    --- Get list of all available tags from identities and doors for multiselect
    -- @return table Array of unique tags
    local function getAvailableTags()
        local tags = {}
        local seen = {}
        
        -- Collect tags from all identities
        for _, identityData in pairs(tac.identities.getAll()) do
            for _, tag in ipairs(identityData.tags or {}) do
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
    -- @param currentTags table Current identity tags
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
    
    --- Show identity details on monitor if available
    local function showIdentityOnMonitor(identity, status)
        local serverMonitor = tac.settings.get("server-monitor")
        if not serverMonitor then return end
        
        local mon = peripheral.wrap(serverMonitor)
        if not mon then return end
        
        local w, h = mon.getSize()
        local colors = HardwareManager.MONITOR_COLORS
        
        mon.setBackgroundColor(colors.background)
        mon.clear()
        
        local function centerText(y, text, color)
            color = color or colors.text
            mon.setTextColor(color)
            local x = math.floor((w - #text) / 2) + 1
            mon.setCursorPos(x, y)
            mon.write(text)
        end
        
        local function drawLine(y, char)
            char = char or "-"
            mon.setTextColor(colors.border)
            mon.setCursorPos(1, y)
            mon.write(string.rep(char, w))
        end
        
        local y = 1
        
        -- Status header
        drawLine(y, "=")
        y = y + 1
        
        if status == "scanning" then
            centerText(y, "SCANNING...", colors.warning)
        elseif status == "found" then
            centerText(y, "IDENTITY FOUND", colors.success)
        elseif status == "created" then
            centerText(y, "IDENTITY CREATED", colors.success)
        elseif status == "error" then
            centerText(y, "ERROR", colors.error)
        else
            centerText(y, "IDENTITY", colors.title)
        end
        y = y + 1
        
        drawLine(y, "-")
        y = y + 1
        
        if identity then
            -- Name
            centerText(y, identity.name, colors.accent)
            y = y + 1
            
            if h > 8 then
                y = y + 1
                
                -- Tags
                mon.setTextColor(colors.textDim)
                mon.setCursorPos(2, y)
                mon.write("Tags:")
                y = y + 1
                
                local tagStr = table.concat(identity.tags or {}, ", ")
                if #tagStr > w - 4 then
                    tagStr = tagStr:sub(1, w - 7) .. "..."
                end
                mon.setTextColor(colors.text)
                mon.setCursorPos(3, y)
                mon.write(tagStr)
                y = y + 1
            end
            
            if h > 12 then
                y = y + 1
                
                -- Access methods
                mon.setTextColor(colors.textDim)
                mon.setCursorPos(2, y)
                mon.write("Access:")
                y = y + 1
                
                local methods = {}
                if identity.nfcEnabled then
                    local nfcStatus = identity.nfcData and "Ready" or "Needs Card"
                    table.insert(methods, "NFC: " .. nfcStatus)
                end
                if identity.rfidEnabled then
                    table.insert(methods, "RFID: Ready")
                end
                
                for _, method in ipairs(methods) do
                    mon.setTextColor(colors.text)
                    mon.setCursorPos(3, y)
                    mon.write(method)
                    y = y + 1
                end
            end
            
            if h > 16 and identity.maxDistance then
                y = y + 1
                mon.setTextColor(colors.textDim)
                mon.setCursorPos(2, y)
                mon.write("Max Distance: " .. identity.maxDistance .. "m")
                y = y + 1
            end
            
            if h > 18 and identity.expiration then
                local now = os.epoch("utc")
                local daysLeft = math.floor((identity.expiration - now) / (24 * 60 * 60 * 1000))
                y = y + 1
                
                if daysLeft > 0 then
                    mon.setTextColor(colors.textDim)
                    mon.setCursorPos(2, y)
                    mon.write("Expires: " .. daysLeft .. " days")
                else
                    mon.setTextColor(colors.error)
                    mon.setCursorPos(2, y)
                    mon.write("EXPIRED")
                end
            end
        end
        
        -- Bottom border
        drawLine(h, "=")
    end
    
    --- Clear monitor display
    local function clearMonitor()
        local serverMonitor = tac.settings.get("server-monitor")
        if not serverMonitor then return end
        
        local mon = peripheral.wrap(serverMonitor)
        if mon then
            mon.setBackgroundColor(colors.black)
            mon.clear()
        end
    end
    
    return {
        name = "identity",
        description = "Manage identities with NFC/RFID support",
        complete = function(args)
            if #args == 1 then
                return {"create", "delete", "list", "edit", "rfid", "nfc", "scan"}
            elseif #args > 1 then
                local cmd = args[1]:lower()
                if cmd == "delete" or cmd == "edit" or cmd == "rfid" or cmd == "nfc" then
                    local identityNames = {}
                    for _, data in pairs(tac.identities.getAll()) do
                        table.insert(identityNames, data.name)
                    end
                    return identityNames
                elseif cmd == "rfid" and #args == 2 then
                    return {"regenerate", "show"}
                end
            end
            return {}
        end,
        execute = function(args, d)
            local cmdName = (args[1] or "list"):lower()

            if cmdName == "create" then
                -- Use formui for identity creation
                local createForm = formui.new("Create New Identity")
                
                local getName = createForm:text("Name")
                
                -- Tags section
                createForm:label("Access Tags")
                local availableTags = getAvailableTags()
                local getTagsMulti
                if #availableTags > 0 then
                    getTagsMulti = createForm:multiselect("Select Tags", availableTags, {})
                    -- Override the default validation to make it optional (custom tags can be used instead)
                    createForm.fields[#createForm.fields].validate = function() return true end
                end
                local getTagsCustom = createForm:text("Custom Tags", "", nil, true)
                
                -- Access methods section
                createForm:label("Access Methods")
                local getNfcEnabled = createForm:checkbox("Enable NFC (secure)", true)
                local getRfidEnabled = createForm:checkbox("Enable RFID (proximity)", true)
                
                -- Distance settings
                createForm:label("RFID Settings")
                local getMaxDistance = createForm:number("Max Distance (0=unlimited)", 0, function(v)
                    return v >= 0, "Distance must be >= 0"
                end)
                
                createForm:addSubmitCancel()
                
                local result = createForm:run()
                
                if result then
                    local identityName = getName()
                    
                    if not identityName or identityName == "" then
                        d.err("Identity name cannot be empty!")
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
                    local maxDistance = getMaxDistance()
                    if maxDistance == 0 then maxDistance = nil end
                    
                    if not nfcEnabled and not rfidEnabled then
                        d.err("At least one access method must be enabled!")
                        return
                    end
                    
                    -- Generate NFC data
                    local nfcData = SecurityCore.randomString(128)
                    
                    -- Create identity first
                    local identityData, error = tac.identityManager.createIdentity({
                        name = identityName,
                        tags = tags,
                        nfcEnabled = nfcEnabled,
                        rfidEnabled = rfidEnabled,
                        maxDistance = maxDistance,
                        nfcData = nfcData,
                        createdBy = "manual"
                    })
                    
                    if not identityData then
                        d.err("Failed to create identity: " .. (error or "Unknown error"))
                        return
                    end
                    
                    d.mess("Identity created: " .. identityName)
                    
                    if nfcEnabled then
                        d.mess("")
                        d.mess("Right-click card to program ID slot #1.")
                        d.mess("Press 'q' to skip card programming.")
                        
                        showIdentityOnMonitor(identityData, "scanning")
                        
                        -- Get server NFC reader
                        local serverNfc = tac.getServerNfc()
                        if not serverNfc then
                            d.err("No server card reader configured!")
                            d.mess("Card must be programmed manually later.")
                        else
                            serverNfc.write(nfcData, identityName)
                            
                            while true do
                                local e = table.pack(os.pullEvent())
                                
                                if e[1] == "nfc_write" and e[2] == peripheral.getName(serverNfc) then
                                    -- Card written successfully
                                    tac.identityManager.setNfcData(identityData.id, nfcData)
                                    
                                    showIdentityOnMonitor(identityData, "created")
                                    d.mess("")
                                    d.mess("Card (ID slot #1) programmed successfully!")
                                    break
                                elseif e[1] == "key" and e[2] == keys.q then
                                    serverNfc.cancelWrite()
                                    d.mess("Card programming skipped.")
                                    break
                                end
                            end
                        end
                    end
                    
                    -- Show summary
                    d.mess("")
                    d.mess("=== Identity Summary ===")
                    d.mess("Name: " .. identityName)
                    d.mess("Tags: " .. table.concat(tags, ", "))
                    d.mess("NFC: " .. (nfcEnabled and "Enabled" or "Disabled"))
                    d.mess("RFID: " .. (rfidEnabled and "Enabled" or "Disabled"))
                    if maxDistance then
                        d.mess("Max Distance: " .. maxDistance .. "m")
                    end
                    if rfidEnabled then
                        d.mess("")
                        d.mess("RFID Code: " .. SecurityCore.truncateCardId(identityData.rfidData))
                        d.mess("Use 'identity rfid " .. identityName .. " show' to display full code")
                    end
                    
                    showIdentityOnMonitor(identityData, "created")
                    sleep(2)
                    clearMonitor()
                else
                    d.err("Identity creation cancelled.")
                end
                
            elseif cmdName == "delete" then
                local identityName = table.concat(args, " ", 2)
                if identityName and #identityName > 0 then
                    local identitiesToRemove = {}
                    for id, data in pairs(tac.identities.getAll()) do
                        if data.name == identityName then
                            table.insert(identitiesToRemove, id)
                        end
                    end
                    
                    if #identitiesToRemove > 0 then
                        d.mess(string.format("Found %d identity(s) with name '%s'. Delete all? (y/N)", #identitiesToRemove, identityName))
                        local response = read():lower()
                        if response == "y" then
                            for _, id in pairs(identitiesToRemove) do
                                tac.identityManager.deleteIdentity(id)
                            end
                            d.mess(string.format("Deleted %d identity(s)", #identitiesToRemove))
                        else
                            d.mess("Cancelled.")
                        end
                    else
                        d.err("No identities found with name: " .. identityName)
                    end
                else
                    d.err("You must provide an identity name to delete!")
                end
                
            elseif cmdName == "list" then
                local interactiveList = require("tac.lib.interactive_list")
                local allIdentities = tac.identities.getAll()
                
                -- Convert identities to list format
                local identityItems = {}
                for identityId, data in pairs(allIdentities) do
                    table.insert(identityItems, {
                        id = identityId,
                        name = data.name or "Unknown",
                        tags = data.tags or {},
                        nfcEnabled = data.nfcEnabled,
                        rfidEnabled = data.rfidEnabled,
                        nfcData = data.nfcData,
                        rfidData = data.rfidData,
                        maxDistance = data.maxDistance,
                        expiration = data.expiration,
                        createdBy = data.createdBy,
                        created = data.created,
                        metadata = data.metadata
                    })
                end
                
                -- Sort by name
                table.sort(identityItems, function(a, b) return a.name < b.name end)
                
                if #identityItems == 0 then
                    d.mess("No identities registered.")
                    return
                end
                
                -- Show interactive list
                interactiveList.show({
                    title = "Registered Identities",
                    items = identityItems,
                    formatItem = function(identity)
                        local icons = ""
                        if identity.nfcEnabled then
                            icons = icons .. (identity.nfcData and "[NFC]" or "[nfc]")
                        end
                        if identity.rfidEnabled then
                            icons = icons .. "[RFID]"
                        end
                        return identity.name .. " " .. icons .. " (" .. SecurityCore.truncateCardId(identity.id) .. ")"
                    end,
                    formatDetails = function(identity)
                        local details = {}
                        table.insert(details, "Name: " .. identity.name)
                        table.insert(details, "ID: " .. SecurityCore.truncateCardId(identity.id))
                        table.insert(details, "")
                        table.insert(details, "Tags: " .. table.concat(identity.tags, ", "))
                        table.insert(details, "")
                        table.insert(details, "=== Access Methods ===")
                        if identity.nfcEnabled then
                            local nfcStatus = identity.nfcData and "Programmed" or "Needs Card"
                            table.insert(details, "NFC: Enabled (" .. nfcStatus .. ")")
                            if identity.nfcGenerated then
                                local nfcDate = os.date("!%Y-%m-%d %H:%M", identity.nfcGenerated / 1000)
                                table.insert(details, "  Generated: " .. nfcDate)
                            end
                            if identity.nfcRegenerated and identity.nfcRegenerated ~= identity.nfcGenerated then
                                local nfcRegenDate = os.date("!%Y-%m-%d %H:%M", identity.nfcRegenerated / 1000)
                                table.insert(details, "  Last Regen: " .. nfcRegenDate)
                            end
                        else
                            table.insert(details, "NFC: Disabled")
                        end
                        if identity.rfidEnabled then
                            table.insert(details, "RFID: Enabled")
                            table.insert(details, "  Code: " .. SecurityCore.truncateCardId(identity.rfidData or "none"))
                            if identity.rfidGenerated then
                                local rfidDate = os.date("!%Y-%m-%d %H:%M", identity.rfidGenerated / 1000)
                                table.insert(details, "  Generated: " .. rfidDate)
                            end
                            if identity.rfidRegenerated and identity.rfidRegenerated ~= identity.rfidGenerated then
                                local rfidRegenDate = os.date("!%Y-%m-%d %H:%M", identity.rfidRegenerated / 1000)
                                table.insert(details, "  Last Regen: " .. rfidRegenDate)
                            end
                        else
                            table.insert(details, "RFID: Disabled")
                        end
                        
                        if identity.maxDistance then
                            table.insert(details, "")
                            table.insert(details, "Max RFID Distance: " .. identity.maxDistance .. "m")
                        end
                        
                        if identity.expiration then
                            local now = os.epoch("utc")
                            local expired = identity.expiration < now
                            local timeLeft = identity.expiration - now
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
                        
                        if identity.createdBy then
                            table.insert(details, "")
                            table.insert(details, "Created by: " .. identity.createdBy)
                        end
                        
                        return details
                    end
                })
                
                term.clear()
                term.setCursorPos(1, 1)
                
            elseif cmdName == "edit" then
                local identityName = table.concat(args, " ", 2)
                
                if not identityName or identityName == "" then
                    d.err("You must specify an identity name to edit!")
                    d.mess("Usage: identity edit <identity_name>")
                    d.mess("Available identities:")
                    for _, identityData in pairs(tac.identities.getAll()) do
                        d.mess("  - " .. identityData.name)
                    end
                    return
                end
                
                -- Find the identity by name
                local targetIdentityId = nil
                local targetIdentity = nil
                for identityId, identityData in pairs(tac.identities.getAll()) do
                    if identityData.name == identityName then
                        targetIdentityId = identityId
                        targetIdentity = identityData
                        break
                    end
                end
                
                if not targetIdentity then
                    d.err("Identity '" .. identityName .. "' not found!")
                    return
                end
                
                d.mess("Editing identity: " .. identityName)
                d.mess("Identity ID: " .. SecurityCore.truncateCardId(targetIdentityId))
                
                -- Create edit form with current values pre-filled
                local editForm = formui.new("Edit Identity: " .. identityName)
                
                local getName = editForm:text("Name", targetIdentity.name)
                
                -- Tags section
                editForm:label("Access Tags")
                local availableTags = getAvailableTags()
                local currentTagIndices = tagsToIndices(targetIdentity.tags, availableTags)
                
                local getTagsMulti
                if #availableTags > 0 then
                    getTagsMulti = editForm:multiselect("Select Tags", availableTags, currentTagIndices)
                end
                
                -- Find custom tags not in available list
                local customTags = {}
                for _, tag in ipairs(targetIdentity.tags or {}) do
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
                
                -- Access methods section
                editForm:label("Access Methods")
                local getNfcEnabled = editForm:checkbox("Enable NFC", targetIdentity.nfcEnabled ~= false)
                local getRfidEnabled = editForm:checkbox("Enable RFID", targetIdentity.rfidEnabled ~= false)
                
                -- Distance settings
                editForm:label("RFID Settings")
                local getMaxDistance = editForm:number("Max Distance (0=unlimited)", targetIdentity.maxDistance or 0)
                
                editForm:label("Identity ID cannot be changed")
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
                    local maxDistance = getMaxDistance()
                    if maxDistance == 0 then maxDistance = nil end
                    
                    if not nfcEnabled and not rfidEnabled then
                        d.err("At least one access method must be enabled!")
                        return
                    end
                    
                    if newName and newName ~= "" then
                        -- Update the identity
                        local updated, err = tac.identityManager.updateIdentity(targetIdentityId, {
                            name = newName,
                            tags = tags,
                            nfcEnabled = nfcEnabled,
                            rfidEnabled = rfidEnabled,
                            maxDistance = maxDistance
                        })
                        
                        if updated then
                            d.mess("Identity updated successfully!")
                            d.mess("Name: " .. newName)
                            d.mess("Tags: " .. table.concat(tags, ", "))
                            d.mess("NFC: " .. (nfcEnabled and "Enabled" or "Disabled"))
                            d.mess("RFID: " .. (rfidEnabled and "Enabled" or "Disabled"))
                            if maxDistance then
                                d.mess("Max Distance: " .. maxDistance .. "m")
                            end
                        else
                            d.err("Failed to update identity: " .. (err or "Unknown error"))
                        end
                    else
                        d.err("Identity name cannot be empty!")
                    end
                else
                    d.err("Identity edit cancelled.")
                end
                
            elseif cmdName == "rfid" then
                local identityName = args[2]
                local subCmd = args[3] or "show"
                
                if not identityName then
                    d.err("Usage: identity rfid <identity_name> [regenerate|show]")
                    return
                end
                
                -- Find identity
                local targetIdentityId = nil
                local targetIdentity = nil
                for identityId, identityData in pairs(tac.identities.getAll()) do
                    if identityData.name == identityName then
                        targetIdentityId = identityId
                        targetIdentity = identityData
                        break
                    end
                end
                
                if not targetIdentity then
                    d.err("Identity '" .. identityName .. "' not found!")
                    return
                end
                
                if not targetIdentity.rfidEnabled then
                    d.err("RFID is not enabled for this identity!")
                    return
                end
                
                if subCmd == "regenerate" then
                    d.mess("Regenerating RFID code for: " .. identityName)
                    d.mess("This will invalidate the old RFID code!")
                    d.mess("Continue? (y/N)")
                    
                    local response = read():lower()
                    if response == "y" then
                        local updated, err = tac.identityManager.regenerateRfid(targetIdentityId)
                        if updated then
                            d.mess("RFID code regenerated!")
                            d.mess("New Code: " .. updated.rfidData)
                        else
                            d.err("Failed to regenerate: " .. (err or "Unknown error"))
                        end
                    else
                        d.mess("Cancelled.")
                    end
                else
                    -- Show RFID code
                    d.mess("RFID Code for: " .. identityName)
                    d.mess("")
                    d.mess(targetIdentity.rfidData or "Not set")
                    d.mess("")
                    d.mess("Use this code to program RFID badges.")
                end
                
            elseif cmdName == "nfc" then
                local identityName = table.concat(args, " ", 2)
                
                if not identityName or identityName == "" then
                    d.err("Usage: identity nfc <identity_name>")
                    d.mess("Programs ID slot #1 for an existing identity")
                    return
                end
                
                -- Find identity
                local targetIdentityId = nil
                local targetIdentity = nil
                for identityId, identityData in pairs(tac.identities.getAll()) do
                    if identityData.name == identityName then
                        targetIdentityId = identityId
                        targetIdentity = identityData
                        break
                    end
                end
                
                if not targetIdentity then
                    d.err("Identity '" .. identityName .. "' not found!")
                    return
                end
                
                if not targetIdentity.nfcEnabled then
                    d.err("NFC is not enabled for this identity!")
                    return
                end
                
                local serverNfc = tac.getServerNfc()
                if not serverNfc then
                    d.err("No server card reader configured!")
                    return
                end
                
                -- Generate new NFC data
                local nfcData = SecurityCore.randomString(128)
                
                d.mess("Programming ID slot #1 for: " .. identityName)
                d.mess("Right-click card to program. Press 'q' to cancel.")
                
                showIdentityOnMonitor(targetIdentity, "scanning")
                serverNfc.write(nfcData, identityName)
                
                while true do
                    local e = table.pack(os.pullEvent())
                    
                    if e[1] == "nfc_write" and e[2] == peripheral.getName(serverNfc) then
                        tac.identityManager.setNfcData(targetIdentityId, nfcData)
                        showIdentityOnMonitor(targetIdentity, "created")
                        d.mess("Card (ID slot #1) programmed successfully!")
                        sleep(2)
                        clearMonitor()
                        break
                    elseif e[1] == "key" and e[2] == keys.q then
                        serverNfc.cancelWrite()
                        clearMonitor()
                        d.mess("Cancelled.")
                        break
                    end
                end
                
            elseif cmdName == "scan" then
                -- Scan for identities using server NFC
                local serverNfc = tac.getServerNfc()
                if not serverNfc then
                    d.err("No server NFC reader configured!")
                    return
                end
                
                d.mess("Tap a card to identify...")
                d.mess("Press 'q' to cancel.")
                
                showIdentityOnMonitor(nil, "scanning")
                
                while true do
                    local e = table.pack(os.pullEvent())
                    
                    if e[1] == "nfc_data" and e[2] == peripheral.getName(serverNfc) then
                        local nfcData = e[3]
                        local identity = tac.identityManager.findByNfc(nfcData)
                        
                        if identity then
                            showIdentityOnMonitor(identity, "found")
                            d.mess("")
                            d.mess("=== Identity Found ===")
                            d.mess("Name: " .. identity.name)
                            d.mess("Tags: " .. table.concat(identity.tags or {}, ", "))
                            d.mess("NFC: " .. (identity.nfcEnabled and "Enabled" or "Disabled"))
                            d.mess("RFID: " .. (identity.rfidEnabled and "Enabled" or "Disabled"))
                            if identity.expiration then
                                local now = os.epoch("utc")
                                local daysLeft = math.floor((identity.expiration - now) / (24 * 60 * 60 * 1000))
                                if daysLeft > 0 then
                                    d.mess("Expires: " .. daysLeft .. " days")
                                else
                                    d.mess("Status: EXPIRED")
                                end
                            end
                        else
                            showIdentityOnMonitor(nil, "error")
                            d.mess("")
                            d.mess("Unknown card!")
                            d.mess("Card ID: " .. SecurityCore.truncateCardId(nfcData))
                        end
                        
                        sleep(3)
                        clearMonitor()
                        break
                    elseif e[1] == "key" and e[2] == keys.q then
                        clearMonitor()
                        d.mess("Cancelled.")
                        break
                    end
                end
            else
                d.err("Unknown identity command! Use: create, delete, list, edit, rfid, nfc, scan")
            end
        end
    }
end

return IdentityCommand
