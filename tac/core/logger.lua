--[[
    TAC Access Logger
    
    Handles all access logging functionality for the TAC system.
    Logs access events, card creation, and other security-related activities.
    Uses lib/log.lua for file logging with automatic daily rotation.
    
    @module tac.core.logger
    @author Twijn
    @version 1.1.0
    
    @example
    -- In your extension:
    function MyExtension.init(tac)
        -- Log an access event
        tac.logger.logAccess({
            cardId = "tenant_1_player1",
            cardName = "Player One",
            doorId = "main_entrance",
            doorName = "Main Entrance",
            granted = true,
            reason = "Valid card"
        })
        
        -- Get all logs
        local logs = tac.logger.getAllLogs()
        for _, log in ipairs(logs) do
            print(log.cardName .. " accessed " .. log.doorName)
        end
        
        -- Get statistics
        local stats = tac.logger.getStats()
        print("Total accesses: " .. stats.totalAccesses)
        print("Granted: " .. stats.granted)
        print("Denied: " .. stats.denied)
    end
]]

local log = require("log")
local AccessLogger = {}

--- Initialize the logger with a persistent storage backend
--
-- Creates a new logger instance that stores logs in persistent storage.
-- The logger provides methods for recording access events and retrieving statistics.
--
---@param persistBackend function The persist function for creating storage backends
---@return table Logger instance with logAccess(), getAllLogs(), clearLogs(), getStats() methods
---@usage local logger = AccessLogger.new(require("persist"))
function AccessLogger.new(persistBackend)
    local logger = {}
    local accessLog = persistBackend("accesslog.json")
    
    --- Log an access event
    --
    -- Records an access event with details about the card, door, and outcome.
    -- Events are stored with timestamps and can be retrieved for auditing.
    -- Also writes to daily log files via lib/log.lua
    --
    ---@param eventType string Type of event: "access_granted", "access_denied", "card_created", "card_creation_cancelled"
    ---@param options table Event details with fields:
    --   - message (string): Human-readable message
    --   - card (table): Card info with id, name, tags
    --   - door (table): Door info with name, tags
    --   - matched_tag (string): Tag that granted access
    --   - reason (string): Reason for denial or other outcome
    ---@usage logger.logAccess("access_granted", {card=card, door=door, matched_tag="admin"})
    function logger.logAccess(eventType, options)
        options = options or {}
        
        local entry = {
            timestamp = os.epoch("utc"),
            type = eventType,
            message = options.message or "No message provided"
        }
        
        -- Add card information if provided
        if options.card then
            entry.card = {
                id = options.card.id,
                name = options.card.name,
                tags = options.card.tags or {}
            }
        end
        
        -- Add door information if provided
        if options.door then
            entry.door = {
                name = options.door.name,
                tags = options.door.tags or {}
            }
        end
        
        -- Add access-specific fields
        if options.matched_tag then
            entry.matched_tag = options.matched_tag
        end
        
        if options.reason then
            entry.reason = options.reason
        end
        
        accessLog.push(entry)
        
        -- Also log to file via lib/log.lua
        local logMsg = string.format("[%s] %s", eventType, entry.message)
        if entry.card and entry.card.name then
            logMsg = logMsg .. " - Card: " .. entry.card.name
        end
        if entry.door and entry.door.name then
            logMsg = logMsg .. " - Door: " .. entry.door.name
        end
        
        if eventType == "access_granted" then
            log.info(logMsg)
        elseif eventType == "access_denied" then
            log.warn(logMsg)
        elseif eventType == "card_created" then
            log.info(logMsg)
        elseif eventType == "card_creation_cancelled" then
            log.debug(logMsg)
        else
            log.debug(logMsg)
        end
    end
    
    --- Get all access logs
    --
    -- Returns all logged events ordered chronologically.
    --
    ---@return table Array of log entry objects with timestamp, type, message, card, door, etc.
    ---@usage local logs = logger.getAllLogs()
    function logger.getAllLogs()
        return accessLog.getAll()
    end
    
    --- Clear all access logs
    --
    -- Permanently deletes all logged events. Use with caution.
    --
    ---@usage logger.clearLogs()
    function logger.clearLogs()
        accessLog.clear()
    end
    
    --- Get access log statistics
    --
    -- Returns statistics about logged events including totals for each event type.
    --
    ---@return table Statistics object with fields:
    --   - total (number): Total number of events
    --   - access_granted (number): Count of successful accesses
    --   - access_denied (number): Count of denied accesses
    --   - card_created (number): Count of created cards
    --   - card_creation_cancelled (number): Count of cancelled card creations
    ---@usage local stats = logger.getStats()
    function logger.getStats()
        local logs = accessLog.getAll()
        local stats = {
            total = #logs,
            access_granted = 0,
            access_denied = 0,
            card_created = 0,
            card_creation_cancelled = 0
        }
        
        for _, log in ipairs(logs) do
            if log.type then
                stats[log.type] = (stats[log.type] or 0) + 1
            end
        end
        
        return stats
    end
    
    --- Format timestamp for display
    -- @param timestamp number - Unix timestamp in milliseconds
    -- @return string - formatted time
    function logger.formatTimestamp(timestamp)
        local seconds = math.floor(timestamp / 1000)
        return os.date("%H:%M:%S", seconds)
    end
    
    return logger
end

return AccessLogger