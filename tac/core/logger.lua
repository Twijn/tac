-- TAC Access Logger
-- Handles all access logging functionality

local AccessLogger = {}

--- Initialize the logger with a persistent storage backend
-- @param persistBackend function - persist function for storing logs
function AccessLogger.new(persistBackend)
    local logger = {}
    local accessLog = persistBackend("accesslog.json")
    
    --- Log an access event
    -- @param eventType string - Type of event (access_granted, access_denied, card_created, etc.)
    -- @param options table - Event details including card, door, matched_tag, reason, message
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
    end
    
    --- Get all access logs
    -- @return table - array of log entries
    function logger.getAllLogs()
        return accessLog.getAll()
    end
    
    --- Clear all access logs
    function logger.clearLogs()
        accessLog.clear()
    end
    
    --- Get access log statistics
    -- @return table - statistics object
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