--[[
    Example TAC Extension
    
    This file demonstrates how to create a TAC extension. Extensions can register
    commands, add hooks to TAC events, and provide custom functionality.
    
    @module tac.extensions._example
    @author Twijn
    @version 1.0.1
    @license MIT
    
    @example
    -- To use this extension from another extension:
    function MyExtension.init(tac)
        -- Load the example extension
        local example = tac.require("example")
        
        -- Call exported methods
        local stats = example.getStats()
        print("Processed " .. stats.processedCount .. " messages")
        
        -- Use optional dependencies
        local result = example.useOptionalExtension()
        
        -- Process a message
        example.processMessage("Hello, TAC!")
    end
]]

local ExampleExtension = {
    name = "example",
    version = "1.0.1",
    description = "Example extension demonstrating TAC extension features",
    author = "Twijn",
    dependencies = {},
    optional_dependencies = {}
}

--- Initialize the extension
--
-- This function is called when the extension is loaded by TAC. Use this to:
-- - Register commands with tac.registerCommand()
-- - Add hooks with tac.addHook()
-- - Register background processes with tac.registerBackgroundProcess()
-- - Access TAC settings, cards, doors, etc.
--
---@param tac table The TAC instance with methods:
--   - registerCommand(name, commandDef): Register a new command
--   - registerExtension(name, extension): Register an extension
--   - addHook(hookName, callback): Add a hook callback
--   - registerBackgroundProcess(name, fn): Register a background process
--   - settings: Persistent settings storage
--   - cards: Persistent card storage
--   - doors: Persistent door storage
--   - logger: Logger instance
---@usage ExampleExtension.init(tac)
function ExampleExtension.init(tac)
    print("*** Example extension initialized! ***")
    print("    Try typing 'example hello' to test it!")
    
    -- Add custom command
    tac.registerCommand("example", {
        description = "Example extension command",
        complete = function(args)
            if #args == 1 then
                return {"hello", "info", "stats"}
            end
            return {}
        end,
        execute = function(args, d)
            local cmd = (args[1] or "hello"):lower()
            
            if cmd == "hello" then
                d.mess("Hello from the example extension!")
            elseif cmd == "info" then
                d.mess("Extension: " .. ExampleExtension.name .. " v" .. ExampleExtension.version)
                d.mess("Description: " .. ExampleExtension.description)
            elseif cmd == "stats" then
                local stats = tac.logger.getStats()
                d.mess("Quick stats from extension:")
                d.mess("- Total events: " .. stats.total)
                d.mess("- Success rate: " .. string.format("%.1f%%", 
                    stats.total > 0 and (stats.access_granted / stats.total * 100) or 0))
            else
                d.err("Unknown example command! Use: hello, info, stats")
            end
        end
    })
    
    -- Add hooks for access events
    tac.addHook("beforeAccess", function(card, door, data, side)
        -- Log before access attempts (could be used for additional security checks)
        print("Extension: Before access check for card " .. (card and card.name or "unknown"))
    end)
    
    tac.addHook("afterAccess", function(granted, matchReason, card, door)
        -- Log after access attempts (could be used for notifications, alerts, etc.)
        if granted then
            print("Extension: Access granted - " .. (matchReason or "unknown reason"))
        else
            print("Extension: Access denied")
        end
    end)
end

--- Custom function that can be called by other extensions
--
-- Demonstrates how extensions can provide APIs for inter-extension communication.
--
---@return string A greeting message
---@usage local greeting = ExampleExtension.customFunction()
function ExampleExtension.customFunction()
    return "Hello from example extension!"
end

--- Hook for card creation events
--
-- This function will be called when cards are created (if hooked into TAC).
-- Can be used to extend or validate card data.
--
---@param cardData table The card data being created
---@usage ExampleExtension.onCardCreated(cardData)
function ExampleExtension.onCardCreated(cardData)
    print("Example: Card created - " .. (cardData.name or "unnamed"))
end

--- Example of safely requiring another extension
--
-- Demonstrates how to check if an extension is loaded and access its functionality.
-- This is useful for optional dependencies or inter-extension communication.
--
---@param tac table The TAC instance
---@return boolean True if extension was found and used
---@usage ExampleExtension.useOptionalExtension(tac)
function ExampleExtension.useOptionalExtension(tac)
    -- Use tac.require() to load another extension's API
    local shopk, err = tac.require("shopk_access")
    if shopk then
        print("Found shopk_access extension v" .. (shopk.version or "unknown"))
        -- Can now use shopk's exported API methods
        if shopk.someMethod then
            shopk.someMethod()
        end
        return true
    else
        print("Optional extension not available: " .. err)
        return false
    end
end

--- Example API method that other extensions can call
--
-- Shows how to export methods that other extensions can use.
--
---@param message string Message to process
---@return string Processed message
---@usage local result = exampleExt.processMessage("hello")
function ExampleExtension.processMessage(message)
    return "Processed: " .. message
end

--- Get extension statistics
--
-- Example of exposing data through the extension API.
--
---@return table Statistics object
---@usage local stats = exampleExt.getStats()
function ExampleExtension.getStats()
    return {
        name = ExampleExtension.name,
        version = ExampleExtension.version,
        calls = 0  -- Track how many times methods were called
    }
end

return ExampleExtension