-- TAC Logs Command Module
-- Handles access log viewing and management

local LogsCommand = {}

function LogsCommand.create(tac)
    return {
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
                
                local logsPerPage = 15
                local totalPages = math.ceil(#logs / logsPerPage)
                local currentPage = 1
                
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
                
                local function drawLogs()
                    term.setBackgroundColor(colors.black)
                    term.clear()
                    term.setCursorPos(1, 1)
                    
                    -- Header
                    term.setTextColor(colors.lightBlue)
                    print("========== ACCESS LOGS ==========")
                    term.setTextColor(colors.white)
                    print(string.format("Page %d of %d (%d total logs)", currentPage, totalPages, #logs))
                    print("^ = Previous | v = Next | q = Quit")
                    print("")
                    
                    -- Calculate which logs to show
                    local startIdx = (currentPage - 1) * logsPerPage + 1
                    local endIdx = math.min(startIdx + logsPerPage - 1, #logs)
                    
                    -- Show logs (most recent first) - condensed format
                    for i = endIdx, startIdx, -1 do
                        local log = logs[i]
                        if log then
                            local timestamp = tac.logger.formatTimestamp(log.timestamp)
                            local cardInfo = ""
                            local doorInfo = ""
                            local extraInfo = ""
                            
                            -- Build condensed card info
                            if log.card then
                                cardInfo = (log.card.name or "Unknown")
                                if log.card.id then
                                    local SecurityCore = require("tac.core.security")
                                    cardInfo = cardInfo .. "(" .. SecurityCore.truncateCardId(log.card.id) .. ")"
                                end
                            end
                            
                            -- Build condensed door info
                            if log.door then
                                doorInfo = log.door.name or "Unknown"
                            end
                            
                            -- Build extra info (reason/matched_tag)
                            if log.matched_tag then
                                extraInfo = "via:" .. log.matched_tag
                            elseif log.reason then
                                extraInfo = "(" .. log.reason .. ")"
                            end
                            
                            -- Single line format: [TIME] TYPE | Card:NAME(ID) | Door:NAME | Extra
                            term.setTextColor(getLogColor(log.type))
                            local line = string.format("[%s] %s", timestamp, log.type:upper())
                            
                            if cardInfo ~= "" then
                                line = line .. " | " .. cardInfo
                            end
                            
                            if doorInfo ~= "" then
                                line = line .. " | " .. doorInfo
                            end
                            
                            if extraInfo ~= "" then
                                line = line .. " " .. extraInfo
                            end
                            
                            print(line)
                        end
                    end
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
                    end
                end
                
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
                
                d.mess(string.format("Found %d logs of type '%s':", #filteredLogs, filterType))
                for i = math.max(1, #filteredLogs - 9), #filteredLogs do
                    local log = filteredLogs[i]
                    if log then
                        local timestamp = os.date("%Y-%m-%d %H:%M:%S", log.timestamp / 1000)
                        print(string.format("[%s] %s", timestamp, log.message))
                    end
                end
                
            else
                d.err("Unknown logs command! Use: view, clear, filter, or stats")
            end
        end
    }
end

return LogsCommand