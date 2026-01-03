-- TAC Logs Command Module
-- Handles access log viewing and management

local pager = require("pager")
local LogsCommand = {}

-- Display logs using pager
local function displayLogs(logs, filterType, tac)
    if #logs == 0 then
        -- No logs - this is informational, use standard print
        term.setTextColor(colors.yellow)
        print("No logs found.")
        term.setTextColor(colors.white)
        return
    end
    
    -- Reverse logs to show newest first
    local reversedLogs = {}
    for i = #logs, 1, -1 do
        table.insert(reversedLogs, logs[i])
    end
    
    local title = filterType and ("LOGS: " .. filterType:upper()) or "ACCESS LOGS"
    title = title .. " (" .. #logs .. " entries)"
    
    -- Build pager output
    local p = pager.new(title)
    
    for i, log in ipairs(reversedLogs) do
        -- Format short line
        local timestamp = tac.logger.formatTimestamp(log.timestamp)
        p:write("[" .. timestamp .. "] ")
        
        -- Color code by type
        if log.type == "access_granted" then
            p:setColor(colors.lime)
        elseif log.type == "access_denied" then
            p:setColor(colors.red)
        elseif log.type == "card_created" then
            p:setColor(colors.cyan)
        else
            p:setColor(colors.yellow)
        end
        
        local parts = {}
        if log.card then
            table.insert(parts, log.card.name or "??")
        end
        if log.door then
            table.insert(parts, log.door.name or "??")
        end
        
        p:print(table.concat(parts, " | "))
        
        -- Add details below if available
        if log.reason or log.matched_tag then
            p:setColor(colors.lightGray)
            local details = {}
            if log.matched_tag then
                table.insert(details, "Tag: " .. log.matched_tag)
            end
            if log.reason then
                table.insert(details, "Reason: " .. log.reason)
            end
            p:print("  " .. table.concat(details, " | "))
        end
        
        p:setColor(colors.white)
        
        -- Add spacing every few entries for readability
        if i < #reversedLogs and i % 5 == 0 then
            p:print("")
        end
    end
    
    -- Show the pager
    p:show()
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