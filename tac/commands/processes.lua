-- TAC Processes Command Module
-- View background processes

local ProcessesCommand = {}

function ProcessesCommand.create(tac)
    return {
        name = "processes",
        description = "View background processes",
        complete = function(args)
            if #args == 1 then
                return {"list", "status", "info"}
            elseif #args == 2 and args[1] == "status" then
                local processes = {}
                for name, _ in pairs(tac.backgroundProcesses) do
                    table.insert(processes, name)
                end
                return processes
            end
            return {}
        end,
        execute = function(args, d)
            local cmd = args[1] or "list"
            
            if cmd == "list" then
                local interactiveList = require("tac.lib.interactive_list")
                
                -- Convert processes to list format
                local processItems = {}
                for name, _ in pairs(tac.backgroundProcesses) do
                    local status = tac.processStatus[name]
                    table.insert(processItems, {
                        name = name,
                        status = status
                    })
                end
                
                -- Sort by name
                table.sort(processItems, function(a, b) return a.name < b.name end)
                
                if #processItems == 0 then
                    d.mess("No background processes registered")
                    return
                end
                
                -- Show interactive list
                interactiveList.show({
                    title = "Background Processes",
                    items = processItems,
                    formatItem = function(proc)
                        local statusText = ""
                        if proc.status then
                            statusText = " [" .. proc.status.status:upper() .. "]"
                        end
                        return proc.name .. statusText
                    end,
                    formatDetails = function(proc)
                        local details = {}
                        table.insert(details, "Process: " .. proc.name)
                        table.insert(details, "")
                        
                        if proc.status then
                            table.insert(details, "Status: " .. proc.status.status)
                            
                            if proc.status.startTime then
                                local uptime = (os.epoch("utc") - proc.status.startTime) / 1000
                                table.insert(details, string.format("Uptime: %.1f seconds", uptime))
                            end
                            
                            if proc.status.lastError then
                                table.insert(details, "")
                                table.insert(details, "Last Error:")
                                table.insert(details, "  " .. proc.status.lastError)
                            end
                            
                            if proc.status.crashCount and proc.status.crashCount > 0 then
                                table.insert(details, "")
                                table.insert(details, "Crash Count: " .. proc.status.crashCount)
                            end
                            
                            if proc.status.restartCount and proc.status.restartCount > 0 then
                                table.insert(details, "Restart Count: " .. proc.status.restartCount)
                            end
                        else
                            table.insert(details, "Status: Unknown")
                        end
                        
                        return details
                    end
                })
                
                term.clear()
                term.setCursorPos(1, 1)
                
            elseif cmd == "status" then
                local processName = args[2]
                
                if not processName then
                    -- Show all statuses
                    d.mess("=== Process Status ===")
                    d.mess("")
                    
                    for name, status in pairs(tac.processStatus) do
                        d.mess(string.format("Process: %s", name))
                        d.mess(string.format("  Status: %s", status.status))
                        
                        if status.startTime then
                            local uptime = (os.epoch("utc") - status.startTime) / 1000
                            d.mess(string.format("  Uptime: %.1f seconds", uptime))
                        end
                        
                        if status.lastError then
                            term.setTextColor(colors.red)
                            d.mess(string.format("  Last Error: %s", status.lastError))
                            term.setTextColor(colors.white)
                        end
                        
                        if status.restartCount > 0 then
                            d.mess(string.format("  Restarts: %d", status.restartCount))
                        end
                        
                        d.mess("")
                    end
                else
                    -- Show specific process status
                    local status = tac.processStatus[processName]
                    
                    if not status then
                        d.err("Process not found: " .. processName)
                        return
                    end
                    
                    d.mess("=== Process: " .. processName .. " ===")
                    d.mess(string.format("Status: %s", status.status))
                    
                    if status.startTime then
                        local uptime = (os.epoch("utc") - status.startTime) / 1000
                        d.mess(string.format("Uptime: %.1f seconds", uptime))
                    end
                    
                    if status.lastError then
                        term.setTextColor(colors.red)
                        d.mess(string.format("Last Error: %s", status.lastError))
                        term.setTextColor(colors.white)
                    end
                    
                    if status.restartCount > 0 then
                        d.mess(string.format("Restarts: %d", status.restartCount))
                    end
                end
                
                sleep()
                
            elseif cmd == "info" then
                d.mess("=== Background Process Information ===")
                d.mess("")
                d.mess("Background processes run continuously in parallel")
                d.mess("with the main command loop. They are started when")
                d.mess("the TAC system boots and run until shutdown.")
                d.mess("")
                d.mess("Commands:")
                d.mess("  list   - List all processes with status")
                d.mess("  status - Show detailed status information")
                d.mess("")
                
                local count = 0
                for name, _ in pairs(tac.backgroundProcesses) do
                    count = count + 1
                end
                
                d.mess(string.format("Currently %d process%s registered", 
                    count, count == 1 and "" or "es"))
                
                sleep()
                
            else
                d.err("Unknown subcommand. Use: list, status, or info")
            end
        end
    }
end

return ProcessesCommand
