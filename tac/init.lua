--[[
    TAC (Terminal Access Control) Core Module
    
    The main package interface for the TAC access control system. This module
    provides the core functionality for managing identity-based access control,
    including extension management, command registration, hooks, and background
    process management.
    
    Identities support both NFC (secure, requires physical tap) and RFID 
    (proximity-based, less secure) access methods with distance limits.
    
    @module tac
    @author Twijn
    @version 2.0.0
    @license MIT
    
    @example
    -- Basic TAC usage:
    local TAC = require("tac")
    
    -- Initialize TAC
    local tac = TAC.new({
        autoload_extensions = true,
        extension_dir = "tac/extensions"
    })
    
    -- Start the system
    tac.run()
    
    @example
    -- Create a custom extension:
    local MyExtension = {
        name = "my_extension",
        version = "1.0.0",
        description = "My custom extension"
    }
    
    function MyExtension.init(tac)
        -- Access TAC functionality
        local identities = tac.identities.getAll()
        tac.logger.logAccess({...})
        
        -- Load other extensions
        local shopk = tac.require("shopk_access")
        
        -- Register commands
        tac.registerCommand("mycommand", {...})
    end
    
    return MyExtension
]]

local TAC = {
    version = "2.0.0",
    name = "tAC"
}

-- Core components
TAC.Security = require("tac.core.security")
TAC.Logger = require("tac.core.logger")
TAC.Hardware = require("tac.core.hardware")
TAC.ExtensionLoader = require("tac.core.extension_loader")

-- Extension registry
TAC.extensions = {}
TAC.commands = {}

--- Initialize TAC with configuration
--
-- Creates a new TAC instance with the provided configuration. This is the main
-- entry point for setting up the access control system.
--
-- @param config table Optional configuration options
-- @return table A new TAC instance with methods for extension/command registration
-- @usage local tac = TAC.new({})
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
    instance.cards = persist("cards.json")  -- Legacy support
    instance.identities = persist("identities.json")
    instance.identityLookup = persist("identity_lookup.json")
    
    -- Initialize logger
    instance.logger = TAC.Logger.new(persist)
    
    -- Initialize card manager (legacy)
    local CardManager = require("tac.core.card_manager")
    instance.cardManager = CardManager.create(instance)
    
    -- Initialize identity manager (new system)
    local IdentityManager = require("tac.core.identity_manager")
    instance.identityManager = IdentityManager.create(instance)
    
    -- Initialize extension loader
    instance.extensionLoader = TAC.ExtensionLoader.create(instance)
    
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
    --
    -- Registers a TAC extension module. If the extension has an init function,
    -- it will be called immediately with the TAC instance. Extensions can register
    -- commands, hooks, and background processes.
    --
    -- @param name string The unique name identifier for the extension
    -- @param extension table The extension module (must have .init(tac) method)
    -- @usage tac.registerExtension("myextension", MyExtension)
    function instance.registerExtension(name, extension)
        instance.extensions[name] = extension
        if extension.init then
            extension.init(instance)
        end
    end
    
    --- Register a command
    --
    -- Registers a new command that can be executed from the TAC command prompt.
    -- Commands can include autocompletion and help text.
    --
    -- @param name string The command name (what users type)
    -- @param commandDef table Command definition with fields:
    --   - description (string): Brief description of the command
    --   - complete (function): Autocomplete function(args) -> suggestions
    --   - execute (function): Execution function(args, d) where d has .mess() and .err()
    -- @usage tac.registerCommand("mycommand", {description="...", execute=function(args, d) ... end})
    function instance.registerCommand(name, commandDef)
        instance.commands[name] = commandDef
    end
    
    --- Add a hook
    --
    -- Registers a callback function for a specific hook point in TAC's execution.
    -- Multiple callbacks can be registered for the same hook.
    --
    -- Available hooks:
    -- - beforeAccess: Called before access check (card, door, data, side)
    -- - afterAccess: Called after access check (granted, matchReason, card, door)
    -- - beforeCommand: Called before command execution (commandName, args)
    -- - afterCommand: Called after command execution (commandName, args, success)
    -- - beforeShutdown: Called before TAC shuts down ()
    --
    -- @param hookName string Name of the hook point
    -- @param callback function The callback function to invoke
    -- @usage tac.addHook("afterAccess", function(granted, reason, card, door) ... end)
    function instance.addHook(hookName, callback)
        if instance.hooks[hookName] then
            table.insert(instance.hooks[hookName], callback)
        end
    end
    
    --- Register a background process
    --
    -- Registers a function to run in parallel with the main TAC event loop.
    -- Background processes are useful for monitoring, periodic tasks, or
    -- maintaining connections to external services.
    --
    -- @param name string Unique identifier for the process
    -- @param processFunction function The function to run in parallel
    -- @usage tac.registerBackgroundProcess("monitor", function() while true do ... end end)
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
    --
    -- Marks a registered background process as disabled, preventing it from running.
    -- The process will not be started until re-enabled.
    --
    ---@param name string Unique identifier of the background process
    ---@return boolean True if process was disabled, false if process not found
    ---@usage tac.disableBackgroundProcess("monitor")
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
    --
    -- Re-enables a previously disabled background process, allowing it to run.
    --
    ---@param name string Unique identifier of the background process
    ---@return boolean True if process was enabled, false if process not found
    ---@usage tac.enableBackgroundProcess("monitor")
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
    --
    -- Returns status information for a specific background process or all processes.
    --
    ---@param name string|nil Optional process name (returns all processes if nil)
    ---@return table Status information with fields:
    --   - status (string): Current status ("registered", "running", "disabled", etc.)
    --   - startTime (number|nil): When process started
    --   - lastError (string|nil): Last error message if failed
    --   - restartCount (number): Number of times process has restarted
    ---@usage local status = tac.getProcessStatus("monitor")
    function instance.getProcessStatus(name)
        if name then
            return instance.processStatus[name]
        else
            return instance.processStatus
        end
    end
    
    --- Execute hooks
    --
    -- Triggers all registered callbacks for a specific hook point.
    -- If any callback returns false, the hook execution stops and returns false with an optional message.
    --
    ---@param hookName string Name of the hook to execute
    ---@param ... any Arguments to pass to all hook callbacks
    ---@return boolean False if any hook returned false (action denied), true otherwise
    ---@return string|nil Optional message from hook (e.g. reason for denial)
    ---@usage local allowed, message = tac.executeHooks("beforeAccess", card, door, data, side)
    function instance.executeHooks(hookName, ...)
        if instance.hooks[hookName] then
            for _, callback in ipairs(instance.hooks[hookName]) do
                local result, message = callback(...)
                -- If any hook returns false, deny the action and pass along the message
                if result == false then
                    return false, message
                end
            end
        end
        return true
    end
    
    -- Extension settings registry
    instance.extensionSettings = {}
    
    --- Register extension settings requirements
    --
    -- Declares settings that an extension requires. TAC will prompt for missing
    -- settings when the extension is loaded.
    --
    ---@param extensionName string Name of the extension
    ---@param settingsConfig table Configuration with fields:
    --   - title (string, optional): Form title for settings prompt
    --   - required (table): Array of setting definitions, each with:
    --     - key (string): Settings key to store value
    --     - label (string): Display label in form
    --     - type (string): "text", "number", "select", or "peripheral"
    --     - default (any, optional): Default value
    --     - validate (function, optional): Validation function
    --     - options (table, for "select"): Array of options
    --     - filter (string, for "peripheral"): Peripheral type filter
    ---@usage tac.registerExtensionSettings("myext", {required = {{key = "my_setting", label = "My Setting", type = "text"}}})
    function instance.registerExtensionSettings(extensionName, settingsConfig)
        instance.extensionSettings[extensionName] = settingsConfig
    end
    
    --- Check for missing extension settings and prompt if needed
    --
    -- Validates that all required extension settings are configured.
    -- If any are missing, prompts the user with a form to enter them.
    --
    ---@param d table Optional display interface (uses instance.d if not provided)
    ---@usage tac.checkExtensionSettings()
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
    --
    -- Returns the configured server NFC reader peripheral.
    --
    ---@return table|nil Server NFC reader peripheral, or nil if not configured
    ---@usage local nfc = tac.getServerNfc()
    function instance.getServerNfc()
        local serverNfcName = instance.settings.get("server-nfc-reader")
        if serverNfcName then
            return peripheral.wrap(serverNfcName)
        end
        return nil
    end
    
    --- Require an extension
    --
    -- Safely loads and returns an extension by name. Returns the extension's
    -- exported API or nil if not loaded.
    --
    ---@param extensionName string Name of the extension to require
    ---@return table|nil Extension API object if loaded, nil if not available
    ---@return string|nil Error message if extension not available
    ---@usage local shopk, err = tac.require("shopk_access")
    function instance.require(extensionName)
        if instance.extensions[extensionName] then
            return instance.extensions[extensionName], nil
        else
            return nil, "Extension '" .. extensionName .. "' is not loaded"
        end
    end
    
    --- Main access control loop (NFC)
    -- Listens for NFC card scans and processes access
    -- Uses debouncing to prevent multiple rapid scans
    function instance.nfcAccessLoop()
        -- Track recently processed NFC scans to prevent spam
        local recentScans = {}
        local NFC_COOLDOWN = 2  -- seconds
        
        while true do
            local e, side, data = os.pullEvent("nfc_data")
            
            local now = os.epoch("utc") / 1000
            
            -- Clean up old entries
            for key, timestamp in pairs(recentScans) do
                if now - timestamp > NFC_COOLDOWN then
                    recentScans[key] = nil
                end
            end
            
            -- Create unique key for this scan
            local scanKey = side .. ":" .. (data or "")
            
            -- Check cooldown
            if recentScans[scanKey] then
                goto continue
            end
            recentScans[scanKey] = now

            -- Skip server NFC reader
            if side == instance.settings.get("server-nfc-reader") then
                goto continue
            end
            
            -- Try to find identity by NFC data first (new system)
            local identity = instance.identityManager.findByNfc(data)
            
            -- Fall back to legacy card system
            local card = instance.cards.get(data)
            local door = instance.doors.get(side)
            
            -- Also check if this side matches any door's nfcReader field
            if not door then
                for reader, doorData in pairs(instance.doors.getAll()) do
                    if doorData.nfcReader == side then
                        door = doorData
                        break
                    end
                end
            end
            
            -- Handle identity-based access (new system)
            if identity then
                -- Check if NFC is enabled for this identity
                if not identity.nfcEnabled then
                    instance.logger.logAccess("access_denied", {
                        identity = {
                            id = identity.id,
                            name = identity.name or "Unknown",
                            tags = identity.tags or {}
                        },
                        door = door and {
                            name = door.name or "Unknown",
                            tags = door.tags or {}
                        } or nil,
                        reason = "nfc_disabled",
                        message = string.format("NFC access not enabled for identity: %s", identity.name or "Unknown")
                    })
                    
                    if door then
                        TAC.Hardware.showAccessDenied(door, "NFC DISABLED")
                    end
                    goto continue
                end
                
                -- Check expiration
                if identity.expiration then
                    local nowMs = os.epoch("utc")
                    if nowMs >= identity.expiration then
                        instance.logger.logAccess("access_denied", {
                            identity = {
                                id = identity.id,
                                name = identity.name or "Unknown",
                                tags = identity.tags or {}
                            },
                            door = door and {
                                name = door.name or "Unknown",
                                tags = door.tags or {}
                            } or nil,
                            reason = "expired",
                            message = string.format("Identity expired: %s", identity.name or "Unknown")
                        })
                        
                        if door then
                            TAC.Hardware.showAccessDenied(door, "EXPIRED")
                        end
                        goto continue
                    end
                end
                
                -- Execute before access hooks
                local hookResult, hookMessage = instance.executeHooks("beforeAccess", identity, door, data, side, "nfc")
                if not hookResult then
                    if door then
                        TAC.Hardware.showAccessDenied(door, hookMessage or "ACCESS DENIED")
                    end
                    instance.executeHooks("afterAccess", false, "hook_denied", identity, door)
                    goto continue
                end
                
                if not door then
                    goto continue
                end
                
                local granted, matchReason = TAC.Security.checkAccess(identity.tags, door.tags)
                
                if granted then
                    instance.logger.logAccess("access_granted", {
                        identity = {
                            id = identity.id,
                            name = identity.name or "Unknown",
                            tags = identity.tags or {}
                        },
                        door = {
                            name = door.name or "Unknown",
                            tags = door.tags or {}
                        },
                        matched_tag = matchReason,
                        scan_type = "nfc",
                        message = string.format("NFC access granted for %s on %s: Matched %s", 
                            identity.name or "Unknown", door.name or "Unknown", matchReason)
                    })

                    TAC.Hardware.openDoor(door, identity.name)
                else
                    instance.logger.logAccess("access_denied", {
                        identity = {
                            id = identity.id,
                            name = identity.name or "Unknown",
                            tags = identity.tags or {}
                        },
                        door = {
                            name = door.name or "Unknown",
                            tags = door.tags or {}
                        },
                        reason = "insufficient_permissions",
                        message = string.format("Access denied for %s on %s", 
                            identity.name or "Unknown", door.name or "Unknown")
                    })
                    
                    TAC.Hardware.showAccessDenied(door, "ACCESS DENIED")
                end

                instance.executeHooks("afterAccess", granted, matchReason, identity, door)
                goto continue
            end

            -- Legacy card-based access
            -- Ensure card has ID field for compatibility
            if card and not card.id then
                card.id = data
            end
            
            -- Check if card is allowed for NFC access
            if card and card.scanType and card.scanType ~= "nfc" and card.scanType ~= "both" then
                instance.logger.logAccess("access_denied", {
                    card = {
                        id = data,
                        name = card.name or "Unknown",
                        tags = card.tags or {}
                    },
                    door = door and {
                        name = door.name or "Unknown",
                        tags = door.tags or {}
                    } or nil,
                    reason = "scan_type_mismatch",
                    message = string.format("Card not authorized for NFC access (scanType: %s)", card.scanType or "none")
                })
                
                if door then
                    TAC.Hardware.showAccessDenied(door, "WRONG SCAN TYPE")
                end
                goto continue
            end

            -- Execute before access hooks - if any hook returns false, deny access
            local hookResult, hookMessage = instance.executeHooks("beforeAccess", card, door, data, side, "nfc")
            if not hookResult then
                -- Hook denied access, show message on sign and execute after access hooks
                if door then
                    TAC.Hardware.showAccessDenied(door, hookMessage or "ACCESS DENIED")
                end
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
    
    --- RFID access control loop
    -- Periodically scans RFID readers and processes access
    -- Supports distance limits from both doors and identities
    function instance.rfidAccessLoop()
        -- Get all doors with RFID scanners
        local function getRfidDoors()
            local rfidDoors = {}
            for key, doorData in pairs(instance.doors.getAll()) do
                if doorData.rfidScanner then
                    rfidDoors[doorData.rfidScanner] = doorData
                end
            end
            return rfidDoors
        end
        
        -- Track recently processed badges to prevent spam (per door)
        local recentBadges = {}
        local COOLDOWN_TIME = 3 -- seconds
        
        -- Track currently processing badges to prevent parallel processing
        local processingBadges = {}
        
        while true do
            local rfidDoors = getRfidDoors()
            local now = os.epoch("utc") / 1000
            
            -- Clean up old entries
            for badge, timestamp in pairs(recentBadges) do
                if now - timestamp > COOLDOWN_TIME then
                    recentBadges[badge] = nil
                end
            end
            
            for scannerName, door in pairs(rfidDoors) do
                local badges = TAC.Hardware.scanRFID(scannerName)
                
                if badges and #badges > 0 then
                    -- Process each badge in range
                    for _, badge in ipairs(badges) do
                        if badge and badge.data then
                            local data = badge.data
                            local distance = badge.distance or 0
                            local badgeKey = scannerName .. ":" .. data
                            
                            -- Skip if on cooldown or currently processing
                            if recentBadges[badgeKey] or processingBadges[badgeKey] then
                                goto nextBadge
                            end
                            
                            -- Check door max distance first
                            if door.maxDistance and distance > door.maxDistance then
                                goto nextBadge
                            end
                            
                            -- Mark as processing
                            processingBadges[badgeKey] = true
                            recentBadges[badgeKey] = now
                            
                            -- Try to find identity by RFID data first (new system)
                            local identity = instance.identityManager.findByRfid(data)
                            
                            -- Fall back to legacy card system
                            local card = instance.cards.get(data)
                            
                            -- Handle identity-based access (new system)
                            if identity then
                                -- Check if RFID is enabled for this identity
                                if not identity.rfidEnabled then
                                    instance.logger.logAccess("access_denied", {
                                        identity = {
                                            id = identity.id,
                                            name = identity.name or "Unknown",
                                            tags = identity.tags or {}
                                        },
                                        door = {
                                            name = door.name or "Unknown",
                                            tags = door.tags or {}
                                        },
                                        reason = "rfid_disabled",
                                        scan_type = "rfid",
                                        distance = distance,
                                        message = string.format("RFID access not enabled for identity: %s", identity.name or "Unknown")
                                    })
                                    
                                    TAC.Hardware.showAccessDenied(door, "RFID DISABLED")
                                    processingBadges[badgeKey] = nil
                                    goto nextBadge
                                end
                                
                                -- Check identity max distance
                                if identity.maxDistance and distance > identity.maxDistance then
                                    instance.logger.logAccess("access_denied", {
                                        identity = {
                                            id = identity.id,
                                            name = identity.name or "Unknown",
                                            tags = identity.tags or {}
                                        },
                                        door = {
                                            name = door.name or "Unknown",
                                            tags = door.tags or {}
                                        },
                                        reason = "too_far",
                                        scan_type = "rfid",
                                        distance = distance,
                                        maxDistance = identity.maxDistance,
                                        message = string.format("Too far: %s (%.1fm > %.1fm limit)", 
                                            identity.name or "Unknown", distance, identity.maxDistance)
                                    })
                                    
                                    TAC.Hardware.showAccessDenied(door, "TOO FAR")
                                    processingBadges[badgeKey] = nil
                                    goto nextBadge
                                end
                                
                                -- Check expiration
                                if identity.expiration then
                                    local nowMs = os.epoch("utc")
                                    if nowMs >= identity.expiration then
                                        instance.logger.logAccess("access_denied", {
                                            identity = {
                                                id = identity.id,
                                                name = identity.name or "Unknown",
                                                tags = identity.tags or {}
                                            },
                                            door = {
                                                name = door.name or "Unknown",
                                                tags = door.tags or {}
                                            },
                                            reason = "expired",
                                            scan_type = "rfid",
                                            message = string.format("Identity expired: %s", identity.name or "Unknown")
                                        })
                                        
                                        TAC.Hardware.showAccessDenied(door, "EXPIRED")
                                        processingBadges[badgeKey] = nil
                                        goto nextBadge
                                    end
                                end
                                
                                -- Execute before access hooks
                                local hookResult, hookMessage = instance.executeHooks("beforeAccess", identity, door, data, scannerName, "rfid")
                                
                                if not hookResult then
                                    TAC.Hardware.showAccessDenied(door, hookMessage or "ACCESS DENIED")
                                    instance.executeHooks("afterAccess", false, "hook_denied", identity, door)
                                    processingBadges[badgeKey] = nil
                                    goto nextBadge
                                end
                                
                                local granted, matchReason = TAC.Security.checkAccess(identity.tags, door.tags)
                                
                                if granted then
                                    instance.logger.logAccess("access_granted", {
                                        identity = {
                                            id = identity.id,
                                            name = identity.name or "Unknown",
                                            tags = identity.tags or {}
                                        },
                                        door = {
                                            name = door.name or "Unknown",
                                            tags = door.tags or {}
                                        },
                                        matched_tag = matchReason,
                                        scan_type = "rfid",
                                        distance = distance,
                                        message = string.format("RFID access granted for %s on %s (%.1fm): Matched %s", 
                                            identity.name or "Unknown", door.name or "Unknown", distance, matchReason)
                                    })

                                    TAC.Hardware.openDoor(door, identity.name)
                                else
                                    instance.logger.logAccess("access_denied", {
                                        identity = {
                                            id = identity.id,
                                            name = identity.name or "Unknown",
                                            tags = identity.tags or {}
                                        },
                                        door = {
                                            name = door.name or "Unknown",
                                            tags = door.tags or {}
                                        },
                                        reason = "insufficient_permissions",
                                        scan_type = "rfid",
                                        message = string.format("RFID access denied for %s on %s", 
                                            identity.name or "Unknown", door.name or "Unknown")
                                    })
                                    
                                    TAC.Hardware.showAccessDenied(door, "ACCESS DENIED")
                                end

                                instance.executeHooks("afterAccess", granted, matchReason, identity, door)
                                processingBadges[badgeKey] = nil
                                goto nextBadge
                            end
                            
                            -- Legacy card-based access
                            -- Ensure card has ID field for compatibility
                            if card and not card.id then
                                card.id = data
                            end
                            
                            -- Check if card is allowed for RFID access
                            if card and card.scanType and card.scanType ~= "rfid" and card.scanType ~= "both" then
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
                                    reason = "scan_type_mismatch",
                                    message = string.format("Card not authorized for RFID access (scanType: %s)", card.scanType or "none")
                                })
                                
                                TAC.Hardware.showAccessDenied(door, "WRONG SCAN TYPE")
                                processingBadges[badgeKey] = nil
                                goto nextBadge
                            end
                            
                            -- Execute before access hooks
                            local hookResult, hookMessage = instance.executeHooks("beforeAccess", card, door, data, scannerName, "rfid")
                            
                            if not hookResult then
                                TAC.Hardware.showAccessDenied(door, hookMessage or "ACCESS DENIED")
                                instance.executeHooks("afterAccess", false, "hook_denied", card, door)
                            elseif not card then
                                instance.logger.logAccess("access_denied", {
                                    card = {
                                        id = data,
                                        name = "Unknown",
                                        tags = {}
                                    },
                                    door = {
                                        name = door.name or "Unknown",
                                        tags = door.tags or {}
                                    },
                                    reason = "invalid_card",
                                    message = string.format("Access denied: Invalid RFID badge (%s)", TAC.Security.truncateCardId(data))
                                })
                                
                                TAC.Hardware.showAccessDenied(door, "INVALID BADGE")
                                instance.executeHooks("afterAccess", false, nil, card, door)
                            else
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
                                        scan_type = "rfid",
                                        distance = distance,
                                        message = string.format("RFID access granted for %s on %s (%.1fm): Matched %s", 
                                            card.name or "Unknown", door.name or "Unknown", distance, matchReason)
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
                                        message = string.format("RFID access denied for %s on %s", 
                                            card.name or "Unknown", door.name or "Unknown")
                                    })
                                    
                                    TAC.Hardware.showAccessDenied(door, "ACCESS DENIED")
                                end

                                instance.executeHooks("afterAccess", granted, matchReason, card, door)
                            end
                            
                            processingBadges[badgeKey] = nil
                            ::nextBadge::
                        end
                    end
                end
            end
            
            -- Poll interval (100ms)
            sleep(0.1)
        end
    end
    
    --- Combined access control loop (backwards compatible)
    -- Runs both NFC and RFID access loops in parallel
    function instance.accessLoop()
        -- Check if there are any RFID scanners configured
        local hasRfid = false
        for _, doorData in pairs(instance.doors.getAll()) do
            if doorData.rfidScanner then
                hasRfid = true
                break
            end
        end
        
        if hasRfid then
            -- Run both NFC and RFID loops in parallel
            parallel.waitForAny(
                function() instance.nfcAccessLoop() end,
                function() instance.rfidAccessLoop() end
            )
        else
            -- Only run NFC loop
            instance.nfcAccessLoop()
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
        local identityCount = tables.count(instance.identities.getAll())
        
        term.setTextColor(colors.lightBlue)
        print("Doors loaded: " .. doorCount)
        term.setTextColor(colors.lime)
        print("Identities loaded: " .. identityCount)
        if cardCount > 0 then
            term.setTextColor(colors.yellow)
            print("Legacy cards loaded: " .. cardCount)
        end
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
--- Load extensions from directory
--
-- Discovers and loads all extensions using the extension loader system.
-- Handles dependencies, errors gracefully, and provides detailed feedback.
--
---@param instance table The TAC instance
---@param options table Optional configuration (passed to extensionLoader.loadFromDirectory)
---@return table Results with loaded, failed, and skipped extensions
---@usage local results = TAC.loadExtensions(tac, {silent = false})
function TAC.loadExtensions(instance, options)
    if not instance.extensionLoader then
        term.setTextColor(colors.red)
        print("Extension loader not initialized")
        term.setTextColor(colors.white)
        return {loaded = {}, failed = {}, skipped = {}}
    end
    
    return instance.extensionLoader.loadFromDirectory(options)
end

return TAC