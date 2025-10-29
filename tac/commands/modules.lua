local ModulesCommand = {}

function ModulesCommand.create(tac)
    return {
        description = "List and manage TAC modules",
        complete = function(args)
            if #args == 1 then
                return {"list", "enable", "disable"}
            elseif #args == 2 and (args[1] == "enable" or args[1] == "disable") then
                -- List available modules from filesystem
                local modules = {}
                local success, files = pcall(fs.list, "tac/extensions")
                if success then
                    for _, filename in ipairs(files) do
                        if filename:match("%.lua$") and not fs.isDir("tac/extensions/" .. filename) then
                            local extName = filename:gsub("%.lua$", "")
                            if args[1] == "enable" and extName:match("^_") then
                                -- Show disabled modules for enable command
                                local displayName = extName:gsub("^_", "")
                                if displayName and displayName ~= "" then
                                    table.insert(modules, displayName)
                                end
                            elseif args[1] == "disable" and not extName:match("^_") then
                                -- Show enabled modules for disable command
                                if extName and extName ~= "" then
                                    table.insert(modules, extName)
                                end
                            end
                        end
                    end
                end
                return modules
            end
            return {}
        end,
        execute = function(args, d)
            local cmd = args[1] or "list"
            
            if cmd == "list" then
                -- Show loaded modules
                d.mess("=== Loaded TAC Modules ===")
                local count = 0
                for name, ext in pairs(tac.extensions) do
                    d.mess(string.format("  %s (v%s): %s", name, ext.version or "unknown", ext.description or "No description"))
                    count = count + 1
                end
                
                if count == 0 then
                    d.mess("  No modules loaded")
                end
                
                -- Show available but disabled modules
                d.mess("")
                d.mess("=== Disabled Modules ===")
                local success, files = pcall(fs.list, "tac/extensions")
                local disabledCount = 0
                if success then
                    for _, filename in ipairs(files) do
                        if filename:match("%.lua$") and not fs.isDir("tac/extensions/" .. filename) then
                            local extName = filename:gsub("%.lua$", "")
                            if extName:match("^_") then
                                local displayName = extName:gsub("^_", "")
                                d.mess(string.format("  %s (disabled)", displayName))
                                disabledCount = disabledCount + 1
                            end
                        end
                    end
                end
                
                if disabledCount == 0 then
                    d.mess("  No disabled modules")
                end
                
                sleep()
                
            elseif cmd == "enable" then
                local moduleName = args[2]
                if not moduleName then
                    d.err("Usage: modules enable <module_name>")
                    return
                end
                
                -- Check if file exists with underscore prefix
                local disabledPath = "tac/extensions/_" .. moduleName .. ".lua"
                local enabledPath = "tac/extensions/" .. moduleName .. ".lua"
                
                if not fs.exists(disabledPath) then
                    d.err("Module '" .. moduleName .. "' is not disabled or does not exist")
                    return
                end
                
                -- Rename file to remove underscore
                fs.move(disabledPath, enabledPath)
                d.mess("Module '" .. moduleName .. "' enabled")
                d.mess("Restart now? (y/N)")

                local input = read():lower()
                if input == "y" then
                    d.mess("Restarting...")
                    sleep()
                    os.reboot()
                    return
                end
                d.mess("Restart the system to load the module")
                
            elseif cmd == "disable" then
                local moduleName = args[2]
                if not moduleName then
                    d.err("Usage: modules disable <module_name>")
                    return
                end
                
                -- Check if file exists without underscore
                local enabledPath = "tac/extensions/" .. moduleName .. ".lua"
                local disabledPath = "tac/extensions/_" .. moduleName .. ".lua"
                
                if not fs.exists(enabledPath) then
                    d.err("Module '" .. moduleName .. "' is not enabled or does not exist")
                    return
                end
                
                -- Don't allow disabling example module (it's already prefixed with _)
                if moduleName == "_example" then
                    d.err("Cannot disable the example module")
                    return
                end
                
                -- Rename file to add underscore
                fs.move(enabledPath, disabledPath)
                d.mess("Module '" .. moduleName .. "' disabled")
                d.mess("Restart the system to unload the module")
                
            else
                d.err("Unknown subcommand. Use: list, enable, or disable")
            end
        end
    }
end

return ModulesCommand
