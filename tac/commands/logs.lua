-- TAC Logs Command Module
-- Handles access log viewing and management

local LogsCommand = {}

-- Shared function to display logs with pagination
local function displayLogs(logs, filterType, tac)
    if #logs == 0 then
        print("No logs found.")
        return
    end
    
    local w, h = term.getSize()
    local logsPerPage = h - 5  -- Reserve 5 lines for header/footer
    local totalPages = math.ceil(#logs / logsPerPage)
    local currentPage = 1
    local scrollOffset = 0  -- Horizontal scroll offset
    
    local function getLogColor(logType)
        if logType == "access_granted" then
            return colors.green
        elseif logType == "access_denied" then
            return colors.red
        elseif logType == "card_created" then
            return colors.blue
        elseif logType == "card_creation_cancelled" then
            return colors.yellow
        else
            return colors.white
        end
    end
    
    local function formatLogLine(log)
        local timestamp = tac.logger.formatTimestamp(log.timestamp)
        local parts = {}
        
        -- Add type
        table.insert(parts, log.type:upper())
        
        -- Add card info (condensed)
        if log.card then
            local cardName = log.card.name or "?"
            if log.card.id then
                local SecurityCore = require("tac.core.security")
                cardName = cardName .. "(" .. SecurityCore.truncateCardId(log.card.id) .. ")"
            end
            table.insert(parts, cardName)
        end
        
        -- Add door info
        if log.door then
            table.insert(parts, "@" .. (log.door.name or "?"))
        end
        
        -- Add extra info
        if log.matched_tag then
            table.insert(parts, "tag:" .. log.matched_tag)
        elseif log.reason then
            table.insert(parts, log.reason)
        end
        
        -- Format: [TIME] TYPE | Card(ID) | @Door | extra
        return string.format("[%s] %s", timestamp, table.concat(parts, " | "))
    end
    
    local function drawLogs()
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        
        -- Header
        term.setTextColor(colors.lightBlue)
        local headerText = filterType and ("LOGS: " .. filterType:upper()) or "ACCESS LOGS"
        print("========== " .. headerText .. " ==========")
        term.setTextColor(colors.white)

        print(string.format("Page %d/%d (%d total) | Arrows=Nav Q=Quit", currentPage, totalPages, #logs))
        print(string.format("Scroll: +%d", scrollOffset))

        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        
        -- Calculate which logs to show (newest first)
        local startIdx = #logs - (currentPage - 1) * logsPerPage
        local endIdx = math.max(startIdx - logsPerPage + 1, 1)
        
        -- Show logs (most recent first)
        for i = startIdx, endIdx, -1 do
            local log = logs[i]
            if log then
                term.setTextColor(getLogColor(log.type))
                local fullLine = formatLogLine(log)
                
                -- Apply horizontal scrolling
                local displayLine = fullLine
                if scrollOffset > 0 then
                    if #fullLine > scrollOffset then
                        displayLine = fullLine:sub(scrollOffset + 1)
                    else
                        displayLine = ""
                    end
                end
                
                -- Truncate if too long
                if #displayLine > w then
                    displayLine = displayLine:sub(1, w - 3) .. "..."
                end
                
                print(displayLine)
            end
        end
        
        -- Footer
        term.setTextColor(colors.gray)
        term.setCursorPos(1, h)
        term.write(string.rep("-", w))
    end
    
    drawLogs()
    
    -- Handle navigation
    while true do
        local event, key = os.pullEvent("key")
        if key == keys.q then
            sleep()
            break
        elseif key == keys.up and currentPage > 1 then
            currentPage = currentPage - 1
            drawLogs()
        elseif key == keys.down and currentPage < totalPages then
            currentPage = currentPage + 1
            drawLogs()
        elseif key == keys.left and scrollOffset > 0 then
            scrollOffset = math.max(0, scrollOffset - 10)
            drawLogs()
        elseif key == keys.right then
            scrollOffset = scrollOffset + 10
            drawLogs()
        end
    end
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