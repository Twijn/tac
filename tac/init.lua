-- TAC (Terminal Access Control) Core Module
-- Main package interface for the access control system

local TAC = {
    version = "1.1.1",
    name = "tAC"
}

-- Core components
TAC.Security = require("tac.core.security")
TAC.Logger = require("tac.core.logger")
TAC.Hardware = require("tac.core.hardware")

-- Extension registry
TAC.extensions = {}
TAC.commands = {}

--- Initialize TAC with configuration
-- @param config table - configuration options
-- @return table - TAC instance
function TAC.new(config)
    config = config or {}
    
    local instance = {
        config = config,
        extensions = {},
        commands = {},
        hooks = {
            beforeAccess = {},
            afterAccess = {},
            beforeCommand = {},
            afterCommand = {},
            beforeShutdown = {}
        },
        backgroundProcesses = {},
        processStatus = {},  -- Track status of background processes
        disabledProcesses = {}  -- Track disabled processes
    }
    
    -- Initialize required dependencies
    local persist = require("persist")
    local formui = require("formui")
    local cmd = require("cmd")
    local tables = require("tables")
    
    -- Initialize storage
    instance.settings = persist("settings.json")
    instance.doors = persist("doors.json")
    instance.cards = persist("cards.json")
    
    -- Initialize logger
    instance.logger = TAC.Logger.new(persist)
    
    -- Initialize card manager
    local CardManager = require("tac.core.card_manager")
    instance.cardManager = CardManager.create(instance)
    
    -- Initialize server NFC reader if not configured
    if not instance.settings.get("server-nfc-reader") then
        local nfcReaders = TAC.Hardware.findPeripheralsOfType("nfc_reader")
        if #nfcReaders > 0 then
            -- Use the first available NFC reader as server reader
            instance.settings.set("server-nfc-reader", nfcReaders[1])
        end
    end
    
    -- Seed random number generator
    math.randomseed(os.epoch("utc"))
    
    --- Register an extension
    -- @param name string - extension name
    -- @param extension table - extension module
    function instance.registerExtension(name, extension)
        instance.extensions[name] = extension
        if extension.init then
            extension.init(instance)
        end
    end
    
    --- Register a command
    -- @param name string - command name
    -- @param commandDef table - command definition with description, complete, execute
    function instance.registerCommand(name, commandDef)
        instance.commands[name] = commandDef
    end
    
    --- Add a hook
    -- @param hookName string - name of hook (beforeAccess, afterAccess, etc.)
    -- @param callback function - callback function
    function instance.addHook(hookName, callback)
        if instance.hooks[hookName] then
            table.insert(instance.hooks[hookName], callback)
        end
    end
    
    --- Register a background process
    -- @param name string - process name
    -- @param processFunction function - function to run in parallel
    function instance.registerBackgroundProcess(name, processFunction)
        instance.backgroundProcesses[name] = processFunction
        instance.processStatus[name] = {
            status = "registered",
            startTime = nil,
            lastError = nil,
            restartCount = 0
        }
    end
    
    --- Disable a background process
    -- @param name string - process name
    function instance.disableBackgroundProcess(name)
        if instance.backgroundProcesses[name] then
            instance.disabledProcesses[name] = true
            if instance.processStatus[name] then
                instance.processStatus[name].status = "disabled"
            end
            return true
        end
        return false
    end
    
    --- Enable a background process
    -- @param name string - process name
    function instance.enableBackgroundProcess(name)
        if instance.backgroundProcesses[name] then
            instance.disabledProcesses[name] = nil
            if instance.processStatus[name] then
                instance.processStatus[name].status = "enabled"
            end
            return true
        end
        return false
    end
    
    --- Get process status
    -- @param name string - process name (optional, returns all if nil)
    -- @return table - status information
    function instance.getProcessStatus(name)
        if name then
            return instance.processStatus[name]
        else
            return instance.processStatus
        end
    end
    
    --- Execute hooks
    -- @param hookName string - name of hook
    -- @param ... any - arguments to pass to hook callbacks
    -- @return boolean - false if any hook returns false (denies action), true otherwise
    function instance.executeHooks(hookName, ...)
        if instance.hooks[hookName] then
            for _, callback in ipairs(instance.hooks[hookName]) do
                local result = callback(...)
                -- If any hook returns false, deny the action
                if result == false then
                    return false
                end
            end
        end
        return true
    end
    
    -- Extension settings registry
    instance.extensionSettings = {}
    
    --- Register extension settings requirements
    -- @param extensionName string - name of extension
    -- @param settingsConfig table - settings configuration
    function instance.registerExtensionSettings(extensionName, settingsConfig)
        instance.extensionSettings[extensionName] = settingsConfig
    end
    
    --- Check for missing extension settings and prompt if needed
    -- @param d table - display interface (optional)
    function instance.checkExtensionSettings(d)
        d = d or instance.d
        
        for extName, config in pairs(instance.extensionSettings) do
            local missing = {}
            
            -- Check required settings
            for _, setting in ipairs(config.required or {}) do
                local value = instance.settings.get(setting.key)
                if not value or (setting.validate and not setting.validate(value)) then
                    table.insert(missing, setting)
                end
            end
            
            -- Prompt for missing settings
            if #missing > 0 then
                local form = formui.new(config.title or ("Configure " .. extName))
                
                for _, setting in ipairs(missing) do
                    if setting.type == "text" then
                        form:text(setting.label, setting.default or "", setting.validate)
                    elseif setting.type == "number" then
                        form:number(setting.label, setting.default or 0, setting.validate)
                    elseif setting.type == "select" then
                        form:select(setting.label, setting.options, setting.default or 1, setting.validate)
                    elseif setting.type == "peripheral" then
                        form:peripheral(setting.label, setting.filter, setting.validate, setting.default)
                    end
                end
                
                local result = form:run()
                if result then
                    -- Save settings
                    local settingIndex = 1
                    for _, setting in ipairs(missing) do
                        local value = result[setting.label]
                        if setting.type == "peripheral" and type(value) == "string" then
                            -- FormUI peripheral returns the peripheral name
                            instance.settings.set(setting.key, value)
                        else
                            instance.settings.set(setting.key, value)
                        end
                        settingIndex = settingIndex + 1
                    end
                    if d and d.mess then
                        d.mess("Settings saved for " .. extName)
                    else
                        term.setTextColor(colors.lime)
                        print("Settings saved for " .. extName)
                        term.setTextColor(colors.white)
                    end
                else
                    if d and d.mess then
                        d.mess("Configuration cancelled for " .. extName)
                    else
                        term.setTextColor(colors.orange)
                        print("Configuration cancelled for " .. extName)
                        term.setTextColor(colors.white)
                    end
                end
            end
        end
    end
    
    --- Get server NFC reader peripheral
    -- @return table|nil - server NFC peripheral or nil if not found
    function instance.getServerNfc()
        local serverNfcName = instance.settings.get("server-nfc-reader")
        if serverNfcName then
            return peripheral.wrap(serverNfcName)
        end
        return nil
    end
    
    --- Main access control loop
    function instance.accessLoop()
        while true do
            local e, side, data = os.pullEvent("nfc_data")

            -- Skip server NFC reader
            if side == instance.settings.get("server-nfc-reader") then
                goto continue
            end

            local card = instance.cards.get(data)
            local door = instance.doors.get(side)

            -- Ensure card has ID field for compatibility
            if card and not card.id then
                card.id = data
            end

            -- Execute before access hooks - if any hook returns false, deny access
            local hookResult = instance.executeHooks("beforeAccess", card, door, data, side)
            if not hookResult then
                -- Hook denied access, execute after access hooks and continue
                instance.executeHooks("afterAccess", false, "hook_denied", card, door)
                goto continue
            end

            if not card then
                instance.logger.logAccess("access_denied", {
                    card = {
                        id = data,
                        name = "Unknown",
                        tags = {}
                    },
                    door = door and {
                        name = door.name or "Unknown",
                        tags = door.tags or {}
                    } or nil,
                    reason = "invalid_card",
                    message = string.format("Access denied: Invalid card (%s)", TAC.Security.truncateCardId(data))
                })
                
                -- Show access denied on sign
                if door then
                    TAC.Hardware.showAccessDenied(door, "INVALID CARD")
                end
                
                instance.executeHooks("afterAccess", false, nil, card, door)
                goto continue
            end

            if not door then
                goto continue
            end

            local granted, matchReason = TAC.Security.checkAccess(card.tags, door.tags)
            
            if granted then
                instance.logger.logAccess("access_granted", {
                    card = {
                        id = data,
                        name = card.name or "Unknown",
                        tags = card.tags or {}
                    },
                    door = {
                        name = door.name or "Unknown",
                        tags = door.tags or {}
                    },
                    matched_tag = matchReason,
                    message = string.format("Access granted for %s on %s: Matched %s", 
                        card.name or "Unknown", door.name or "Unknown", matchReason)
                })

                TAC.Hardware.openDoor(door, card.name)
            else
                instance.logger.logAccess("access_denied", {
                    card = {
                        id = data,
                        name = card.name or "Unknown",
                        tags = card.tags or {}
                    },
                    door = {
                        name = door.name or "Unknown",
                        tags = door.tags or {}
                    },
                    reason = "insufficient_permissions",
                    message = string.format("Access denied for %s (%s) on %s (%s)", 
                        card.name or "Unknown", table.concat(card.tags or {}, ","), 
                        door.name or "Unknown", table.concat(door.tags or {}, ","))
                })
                
                -- Show access denied on sign
                TAC.Hardware.showAccessDenied(door, "ACCESS DENIED")
            end

            -- Execute after access hooks
            instance.executeHooks("afterAccess", granted, matchReason, card, door)

            ::continue::
        end
    end
    
    --- Command line interface loop
    function instance.commandLoop()
        -- Dynamically load commands from commands directory
        local commandsDir = "tac/commands"
        local success, files = pcall(fs.list, commandsDir)
        
        if success then
            for _, filename in ipairs(files) do
                -- Only load .lua files
                if filename:match("%.lua$") and not fs.isDir(commandsDir .. "/" .. filename) then
                    local cmdName = filename:gsub("%.lua$", "")  -- Remove .lua extension
                    
                    local loadSuccess, cmdModule = pcall(require, commandsDir .. "." .. cmdName)
                    if loadSuccess then
                        -- Check if module has a create function
                        if type(cmdModule.create) == "function" then
                            local createSuccess, cmdDef = pcall(cmdModule.create, instance)
                            if createSuccess and cmdDef then
                                -- Use the name from the command definition if available, otherwise use filename
                                local commandName = cmdDef.name or cmdName
                                instance.registerCommand(commandName, cmdDef)
                            else
                                term.setTextColor(colors.red)
                                print("Warning: Failed to create command '" .. cmdName .. "': " .. tostring(cmdDef))
                                term.setTextColor(colors.white)
                            end
                        else
                            term.setTextColor(colors.yellow)
                            print("Warning: Command module '" .. cmdName .. "' has no create function")
                            term.setTextColor(colors.white)
                        end
                    else
                        term.setTextColor(colors.red)
                        print("Warning: Failed to load command '" .. cmdName .. "': " .. tostring(cmdModule))
                        term.setTextColor(colors.white)
                    end
                end
            end
        end

        local shutdownCmd = function(args, d)
            instance.shutdown()
            error("shutdown") -- This will break out of the command loop
        end
        
        -- Add shutdown command
        instance.registerCommand("shutdown", {
            description = "Shutdown TAC gracefully",
            execute = shutdownCmd
        })
        
        instance.registerCommand("exit", {
            description = "Exit TAC (alias for shutdown)",
            execute = shutdownCmd
        })

        instance.registerCommand("reboot", {
            description = "Reboot the computer",
            execute = function(args, d)
                d.mess("Rebooting computer...")
                sleep()
                os.reboot()
            end
        })

        -- Wait a couple of seconds to allow system to complete initialization
        sleep(2)
        
        -- Execute command interface
        cmd(TAC.name, TAC.version, instance.commands)
    end
    
        --- Start the TAC system
    function instance.start()
        -- Update all door signs at startup
        TAC.Hardware.updateAllSigns(instance.doors)
        
        -- Print status information
        local doorCount = tables.count(instance.doors.getAll())
        local cardCount = tables.count(instance.cards.getAll())
        
        term.setTextColor(colors.lightBlue)
        print("Doors loaded: " .. doorCount)
        term.setTextColor(colors.lime)
        print("Cards loaded: " .. cardCount)
        term.setTextColor(colors.white)
        
        term.setTextColor(colors.cyan)
        print("*** " .. TAC.name .. " v" .. TAC.version .. " READY ***")
        term.setTextColor(colors.white)
        
        -- Collect all processes to run in parallel
        local processes = {}
        
        -- Always start access control (default behavior)
        local mode = instance.config.mode or "access"
        if mode == "access" then
            term.setTextColor(colors.yellow)
            print("Starting in ACCESS mode - NFC scanning active")
            term.setTextColor(colors.white)
            
            -- Add access control process
            table.insert(processes, function()
                local success, err = pcall(instance.accessLoop)
                if not success then
                    term.setTextColor(colors.red)
                    print("Access loop error: " .. tostring(err))
                    term.setTextColor(colors.white)
                end
            end)
        end
        
        -- Add command interface process
        table.insert(processes, function()
            local success, err = pcall(instance.commandLoop)
            if not success then
                term.setTextColor(colors.red)
                print("Command loop error: " .. tostring(err))
                term.setTextColor(colors.white)
            end
        end)
        
        -- Add all registered background processes
        for name, processFunc in pairs(instance.backgroundProcesses) do
            -- Skip disabled processes
            if not instance.disabledProcesses[name] then
                print("Starting background process: " .. name)
                table.insert(processes, function()
                    -- Mark as running
                    if instance.processStatus[name] then
                        instance.processStatus[name].status = "running"
                        instance.processStatus[name].startTime = os.epoch("utc")
                    end
                    
                    local success, err = pcall(processFunc, instance)
                    
                    -- Update status
                    if instance.processStatus[name] then
                        if not success then
                            instance.processStatus[name].status = "crashed"
                            instance.processStatus[name].lastError = tostring(err)
                            printError("Background process '" .. name .. "' error: " .. tostring(err))
                        else
                            instance.processStatus[name].status = "stopped"
                        end
                    end
                end)
            else
                print("Skipping disabled process: " .. name)
            end
        end
        
        -- Run all processes in parallel with interrupt handling
        local success, err = pcall(parallel.waitForAny, table.unpack(processes))
        
        if not success then
            if err == "shutdown" then
                -- Graceful shutdown requested
                return
            elseif err == "Terminated" then
                -- CTRL+C pressed
                term.setTextColor(colors.yellow)
                print("Interrupt received, shutting down...")
                term.setTextColor(colors.white)
                instance.shutdown()
            else
                -- Other error
                term.setTextColor(colors.red)
                print("TAC error: " .. tostring(err))
                term.setTextColor(colors.white)
                instance.shutdown()
            end
        end
    end
    
    --- Shutdown the TAC system gracefully
    function instance.shutdown()
        term.setTextColor(colors.yellow)
        print("Shutting down TAC...")
        term.setTextColor(colors.white)
        
        -- Execute shutdown hooks
        instance.executeHooks("beforeShutdown")
        
        term.setTextColor(colors.lime)
        print("TAC shutdown complete.")
        term.setTextColor(colors.white)
    end
    
    return instance
end

--- Load extensions from extensions directory
function TAC.loadExtensions(instance)
    local extensionDir = "tac/extensions"
    
    -- Try to iterate through extension files
    -- Note: In CC:Tweaked, we need to use fs.list() to discover files
    local success, files = pcall(fs.list, "tac/extensions")

    if not success then
        return
    end
    
    for _, filename in ipairs(files) do
        -- Only load .lua files and skip directories
        if filename:match("%.lua$") and not fs.isDir("tac/extensions/" .. filename) then
            local extName = filename:gsub("%.lua$", "")  -- Remove .lua extension
            
            -- Skip disabled extensions (prefixed with _ or disabled_)
            if not extName:match("^_") and not extName:match("^disabled_") then
                local loadSuccess, extension = pcall(require, extensionDir .. "." .. extName)
                if loadSuccess then
                    instance.registerExtension(extName, extension)
                end
            end
        end
    end
end

return TAC