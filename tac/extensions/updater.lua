
-- TAC Updater Extension
-- Provides auto-update functionality for libraries (and eventually tsc)

local UpdaterExtension = {
    name = "updater",
    version = "1.0.1",
    description = "Auto-update TAC libraries and (eventually) tac via lib/updater.lua"
}

--- Initialize the extension
-- @param tac table - TAC instance
function UpdaterExtension.init(tac)
    local updater = require("lib/updater")

    -- Check for updates on startup
    if updater.checkUpdates then
        local ok, updatesOrErr = pcall(updater.checkUpdates)
        if ok then
            local updates = updatesOrErr
            if type(updates) == "table" and #updates > 0 then
                term.setTextColor(colors.yellow)
                print("TAC Updater: Updates available for the following libraries:")
                for _, lib in ipairs(updates) do
                    print(string.format("- %s: %s -> %s", lib.name, lib.current or "?", lib.latest or "?"))
                end
                print("Run 'updater update' to update.")
                term.setTextColor(colors.white)
            end
        end
    end

    tac.registerCommand("updater", {
        description = "Auto-update TAC libraries (and eventually tsc)",
        complete = function(args)
            if #args == 1 then
                return {"check", "update"}
            end
            return {}
        end,
        execute = function(args, d)
            local cmd = (args[1] or "check"):lower()
            if cmd == "check" then
                d.mess("TAC Updater: Checking for available updates...")
                local ok, updatesOrErr = pcall(updater.checkUpdates)
                if not ok then
                    d.err("Updater error: " .. tostring(updatesOrErr))
                else
                    local updates = updatesOrErr
                    if type(updates) ~= "table" or #updates == 0 then
                        d.mess("All libraries are up to date!")
                    else
                        d.mess("Updates available for the following libraries:")
                        for _, lib in ipairs(updates) do
                            d.mess(string.format("- %s: %s -> %s", lib.name, lib.current or "?", lib.latest or "?"))
                        end
                    end
                end
            elseif cmd == "update" then
                d.mess("TAC Updater: Checking for library updates...")
                local ok, err = pcall(function()
                    updater.updateAll() -- Assumes updater.lua provides updateAll() and prints its own status
                end)
                if not ok then
                    d.err("Updater error: " .. tostring(err))
                end
            else
                d.err("Unknown updater command! Use: check, update")
            end
        end
    })
end

return UpdaterExtension
