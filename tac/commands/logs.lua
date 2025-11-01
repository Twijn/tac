-- TAC Logs Command Module
-- Handles access log viewing and management

local interactiveList = require("tac.lib.interactive_list")
local LogsCommand = {}

-- Format a short log line for list display
local function formatLogLine(log, tac)
    local timestamp = tac.logger.formatTimestamp(log.timestamp)
    local parts = {}
    
    -- Add card info (condensed)
    if log.card then
        local cardName = log.card.name or "??"
        table.insert(parts, cardName)
    end
    
    -- Add door info
    if log.door then
        table.insert(parts, log.door.name or "??")
    end
    
    -- Format: [TIME] [C] TYPE | Card | @Door
    return string.format("[%s] %s", timestamp, table.concat(parts, " | "))
end

-- Format detailed log information for detail view
local function formatLogDetails(log, tac)
    local SecurityCore = require("tac.core.security")
    local details = {}
    
    -- Header
    table.insert(details, "=== LOG ENTRY DETAILS ===")
    table.insert(details, "")
    
    -- Timestamp
    table.insert(details, "Timestamp: " .. tac.logger.formatTimestamp(log.timestamp))
    table.insert(details, "Type: " .. log.type:upper())
    table.insert(details, "")
    
    -- Card information
    if log.card then
        table.insert(details, "--- Card Information ---")
        table.insert(details, "Name: " .. (log.card.name or "Unknown"))
        if log.card.id then
            table.insert(details, "Short ID: " .. SecurityCore.truncateCardId(log.card.id))
        end
        if log.card.tags then
            table.insert(details, "Tags: " .. table.concat(log.card.tags, ", "))
        end
        if log.card.expiration then
            table.insert(details, "Expiration: " .. tac.logger.formatTimestamp(log.card.expiration))
        end
        table.insert(details, "")
    end
    
    -- Door information
    if log.door then
        table.insert(details, "--- Door Information ---")
        table.insert(details, "Name: " .. (log.door.name or "Unknown"))
        if log.door.side then
            table.insert(details, "Side: " .. log.door.side)
        end
        if log.door.required_tags then
            table.insert(details, "Required Tags: " .. table.concat(log.door.required_tags, ", "))
        end
        table.insert(details, "")
    end
    
    -- Additional information
    if log.matched_tag then
        table.insert(details, "Matched Tag: " .. log.matched_tag)
    end
    if log.reason then
        table.insert(details, "Reason: " .. log.reason)
    end
    if log.message then
        table.insert(details, "Message: " .. log.message)
    end
    
    -- Raw data (for debugging)
    if log.data then
        table.insert(details, "")
        table.insert(details, "--- Additional Data ---")
        for k, v in pairs(log.data) do
            if type(v) ~= "table" then
                table.insert(details, k .. ": " .. tostring(v))
            end
        end
    end
    
    return details
end

-- Display logs using interactive list
local function displayLogs(logs, filterType, tac)
    if #logs == 0 then
        print("No logs found.")
        return
    end
    
    -- Reverse logs to show newest first
    local reversedLogs = {}
    for i = #logs, 1, -1 do
        table.insert(reversedLogs, logs[i])
    end
    
    local title = filterType and ("LOGS: " .. filterType:upper()) or "ACCESS LOGS"
    title = title .. " (" .. #logs .. " entries)"
    
    interactiveList.show({
        title = title,
        items = reversedLogs,
        formatItem = function(log) 
            return formatLogLine(log, tac) 
        end,
        formatDetails = function(log)
            return formatLogDetails(log, tac)
        end,
        showHelp = true
    })
end

function LogsCommand.create(tac)
    return {
        name = "logs",
        description = "View access logs with pretty UI",
        complete = function(args)
            if #args == 1 then
                return {"view", "clear", "filter", "stats"}
            elseif #args > 1 and args[1]:lower() == "filter" then
                return {"access_granted", "access_denied", "card_created", "card_creation_cancelled"}
            end
            return {}
        end,
        execute = function(args, d)
            local cmd = (args[1] or "view"):lower()
            
            if cmd == "view" then
                local logs = tac.logger.getAllLogs()
                if #logs == 0 then
                    d.mess("No access logs found.")
                    return
                end
                displayLogs(logs, nil, tac)
                
            elseif cmd == "clear" then
                d.mess("Are you sure you want to clear all access logs? (y/N)")
                local response = read():lower()
                if response == "y" then
                    tac.logger.clearLogs()
                    d.mess("Access logs cleared.")
                else
                    d.mess("Cancelled.")
                end
                
            elseif cmd == "stats" then
                local stats = tac.logger.getStats()
                d.mess("=== Access Log Statistics ===")
                d.mess("Total entries: " .. stats.total)
                d.mess("Access granted: " .. stats.access_granted)
                d.mess("Access denied: " .. stats.access_denied)
                d.mess("Cards created: " .. stats.card_created)
                d.mess("Card creation cancelled: " .. stats.card_creation_cancelled)
                
            elseif cmd == "filter" then
                local filterType = args[2]
                if not filterType then
                    d.err("You must specify a filter type!")
                    d.mess("Available filters: access_granted, access_denied, card_created, card_creation_cancelled")
                    return
                end
                
                local logs = tac.logger.getAllLogs()
                local filteredLogs = {}
                
                for _, log in ipairs(logs) do
                    if log.type == filterType then
                        table.insert(filteredLogs, log)
                    end
                end
                
                if #filteredLogs == 0 then
                    d.mess("No logs found for filter: " .. filterType)
                    return
                end
                
                displayLogs(filteredLogs, filterType, tac)
                
            else
                d.err("Unknown logs command! Use: view, clear, filter, or stats")
            end
        end
    }
end

return LogsCommand