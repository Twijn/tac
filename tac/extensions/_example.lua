-- TAC Example Extension
-- Demonstrates how to create extensions for the TAC system

local ExampleExtension = {
    name = "example",
    version = "1.0.0",
    description = "Example extension showing how to extend TAC"
}

--- Initialize the extension
-- @param tac table - TAC instance
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

--- Custom functionality that can be called by other extensions
function ExampleExtension.customFunction()
    return "This is a custom function from the example extension"
end

--- Hook into card creation process
function ExampleExtension.onCardCreated(cardData)
    print("Extension: New card created - " .. cardData.name)
end

return ExampleExtension