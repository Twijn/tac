
--[[
    TAC Updater Extension
    
    Provides auto-update functionality for TAC libraries and (eventually) the TAC
    system itself via lib/updater.lua. This extension checks for updates on startup
    and provides commands to check for and install updates.
    
    @module updater
    @author Twijn
    @version 1.0.1
    @license MIT
]]

local UpdaterExtension = {
    name = "updater",
    version = "1.0.1",
    description = "Auto-update TAC libraries and (eventually) tac via lib/updater.lua",
    author = "Twijn",
    dependencies = {},  -- No dependencies
    optional_dependencies = {}
}

--- Initialize the updater extension
-- 
-- This function is called when the extension is loaded by TAC. It performs the
-- following actions:
-- 1. Checks for available updates on startup and notifies the user if any are found
-- 2. Registers the 'updater' command with 'check' and 'update' subcommands
-- 
-- The extension will silently check for updates and only print a message if updates
-- are available. If no updates are found, no message is displayed.
--
-- @param tac table The TAC instance that provides command registration and hooks
-- @usage UpdaterExtension.init(tac)
function UpdaterExtension.init(tac)
    local updater = require("lib/updater")

    --- Check for updates on startup
    -- 
    -- This function runs automatically when the extension initializes. It checks
    -- for available updates to installed libraries and prints a notification if
    -- any updates are found. If all libraries are up to date, no message is shown.
    -- 
    -- The check is wrapped in a pcall to ensure that any errors in the updater
    -- library don't prevent the extension from loading.
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

    --- Register the updater command
    --
    -- Provides two subcommands:
    -- - check: Check for available updates without applying them
    -- - update: Update all libraries to their latest versions
    --
    -- @command updater
    -- @subcommand check Check for available updates
    -- @subcommand update Update all libraries
    tac.registerCommand("updater", {
        description = "Auto-update TAC libraries",
        
        --- Provide autocomplete suggestions for the updater command
        --
        -- Returns available subcommands when the user is typing the first argument.
        -- This enables tab completion for 'check' and 'update'.
        --
        -- @param args table List of current command arguments
        -- @return table List of available subcommands ('check', 'update')
        complete = function(args)
            if #args == 1 then
                return {"check", "update"}
            end
            return {}
        end,
        
        --- Execute the updater command
        --
        -- Handles both 'check' and 'update' subcommands:
        -- 
        -- **check**: Queries lib/updater.lua for available updates and displays
        -- them to the user with current and latest version information. If no
        -- updates are available, displays a confirmation message.
        -- 
        -- **update**: Downloads and installs all available updates using
        -- lib/updater.lua. The updater library handles progress output and
        -- error reporting.
        --
        -- @param args table Command arguments (first element is the subcommand)
        -- @param d table Display utilities with methods:
        --   - mess(string): Display an informational message
        --   - err(string): Display an error message
        execute = function(args, d)
            local cmd = (args[1] or "check"):lower()
            
            --- Handle 'check' subcommand
            -- Checks for available updates and displays them to the user
            if cmd == "check" then
                d.mess("TAC Updater: Checking for available updates...")
                -- Call updater.checkUpdates() which returns a table of available updates
                local ok, updatesOrErr = pcall(updater.checkUpdates)
                if not ok then
                    -- If the call failed, display the error
                    d.err("Updater error: " .. tostring(updatesOrErr))
                else
                    local updates = updatesOrErr
                    if type(updates) ~= "table" or #updates == 0 then
                        -- No updates available
                        d.mess("All libraries are up to date!")
                    else
                        -- Display each available update with version information
                        d.mess("Updates available for the following libraries:")
                        for _, lib in ipairs(updates) do
                            d.mess(string.format("- %s: %s -> %s", lib.name, lib.current or "?", lib.latest or "?"))
                        end
                    end
                end
            
            --- Handle 'update' subcommand
            -- Downloads and installs all available library updates
            elseif cmd == "update" then
                d.mess("TAC Updater: Checking for library updates...")
                -- Call updater.updateAll() which handles downloading and installing updates
                -- The updater library prints its own progress and status messages
                local ok, err = pcall(function()
                    updater.updateAll()
                end)
                if not ok then
                    -- If the update process failed, display the error
                    d.err("Updater error: " .. tostring(err))
                end
            
            --- Handle unknown subcommands
            else
                d.err("Unknown updater command! Use: check, update")
            end
        end
    })
end

return UpdaterExtension
