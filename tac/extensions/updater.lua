
--[[
    TAC Updater Extension
    
    Provides auto-update functionality for TAC libraries and (eventually) the TAC
    system itself via lib/updater.lua. This extension checks for updates on startup
    and provides commands to check for and install updates.
    
    @module updater
    @author Twijn
    @version 1.1.2
    @license MIT
]]

local UpdaterExtension = {
    name = "updater",
    version = "1.1.2",
    description = "Auto-update TAC core, extensions, and libraries",
    author = "Twijn",
    dependencies = {},
    optional_dependencies = {}
}

-- Configuration
local API_BASE = "https://tac.twijn.dev/api"
local GITHUB_RAW = "https://raw.githubusercontent.com/Twijn/tac/main"

-- Helper functions
local function fetchJSON(url)
    local response = http.get(url)
    if not response then
        return nil, "Failed to fetch: " .. url
    end
    local content = response.readAll()
    response.close()
    return textutils.unserializeJSON(content)
end

local function downloadFile(url, path)
    local response = http.get(url)
    if not response then
        return false, "Failed to download: " .. url
    end
    
    local content = response.readAll()
    response.close()
    
    local dir = fs.getDir(path)
    if not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    local file = fs.open(path, "w")
    if not file then
        return false, "Failed to write file: " .. path
    end
    
    file.write(content)
    file.close()
    return true
end

local function compareVersions(v1, v2)
    -- Returns true if v1 < v2
    if not v1 or not v2 then return false end
    
    local parts1 = {}
    for part in v1:gmatch("%d+") do
        table.insert(parts1, tonumber(part))
    end
    
    local parts2 = {}
    for part in v2:gmatch("%d+") do
        table.insert(parts2, tonumber(part))
    end
    
    for i = 1, math.max(#parts1, #parts2) do
        local p1 = parts1[i] or 0
        local p2 = parts2[i] or 0
        if p1 < p2 then return true end
        if p1 > p2 then return false end
    end
    
    return false
end

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
        description = "Update TAC core, extensions, and libraries",
        complete = function(args)
            if #args == 1 then
                return {"check", "update", "update-libs", "update-core", "update-extension"}
            elseif #args == 2 and args[1] == "update-extension" then
                -- Autocomplete extension names
                local extensions = {}
                for name, _ in pairs(tac.extensions) do
                    table.insert(extensions, name)
                end
                return extensions
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
            
            if cmd == "check" then
                d.mess("Checking for updates...")
                
                -- Check TAC core version
                local versions, err = fetchJSON(API_BASE .. "/versions.json")
                if not versions then
                    d.err("Failed to fetch version info: " .. tostring(err))
                    return
                end
                
                local updates = {}
                local currentTACVersion = tac.version
                
                if compareVersions(currentTACVersion, versions.tac.version) then
                    table.insert(updates, {
                        type = "core",
                        name = "TAC Core",
                        current = currentTACVersion,
                        latest = versions.tac.version
                    })
                end
                
                -- Check extensions
                for extName, extData in pairs(tac.extensions) do
                    if versions.tac.extensions[extName] then
                        local remoteVersion = versions.tac.extensions[extName].version
                        local localVersion = extData.version
                        if compareVersions(localVersion, remoteVersion) then
                            table.insert(updates, {
                                type = "extension",
                                name = extName,
                                current = localVersion,
                                latest = remoteVersion
                            })
                        end
                    end
                end
                
                -- Check libraries
                local ok, libUpdates = pcall(updater.checkUpdates)
                if ok and type(libUpdates) == "table" then
                    for _, lib in ipairs(libUpdates) do
                        table.insert(updates, {
                            type = "library",
                            name = lib.name,
                            current = lib.current,
                            latest = lib.latest
                        })
                    end
                end
                
                if #updates == 0 then
                    d.mess("Everything is up to date!")
                else
                    d.mess("Updates available:")
                    for _, update in ipairs(updates) do
                        term.setTextColor(colors.yellow)
                        term.write("  " .. update.name)
                        term.setTextColor(colors.white)
                        term.write(": ")
                        term.setTextColor(colors.red)
                        term.write(update.current or "?")
                        term.setTextColor(colors.white)
                        term.write(" -> ")
                        term.setTextColor(colors.lime)
                        print(update.latest or "?")
                        term.setTextColor(colors.white)
                    end
                    d.mess("Run 'updater update' to update all, or use specific commands.")
                end
                
            elseif cmd == "update" then
                d.mess("Updating all components...")
                
                -- Update libraries
                d.mess("Updating libraries...")
                local ok, err = pcall(function()
                    updater.updateAll()
                end)
                if not ok then
                    d.err("Library update failed: " .. tostring(err))
                end
                
                -- Update core files
                d.mess("Updating TAC core...")
                local versions, err = fetchJSON(API_BASE .. "/versions.json")
                if versions then
                    -- Update main init.lua
                    if versions.tac.init then
                        local success, downloadErr = downloadFile(versions.tac.init.download_url, versions.tac.init.path)
                        if success then
                            d.mess("Updated: " .. versions.tac.init.path)
                        else
                            d.err("Failed to update " .. versions.tac.init.path .. ": " .. tostring(downloadErr))
                        end
                    end
                    
                    -- Update core modules
                    for name, info in pairs(versions.tac.core) do
                        local success, downloadErr = downloadFile(info.download_url, info.path)
                        if success then
                            d.mess("Updated: " .. info.path)
                        else
                            d.err("Failed to update " .. info.path .. ": " .. tostring(downloadErr))
                        end
                    end
                end
                
                d.mess("Update complete! Restart TAC to apply changes.")
                
            elseif cmd == "update-libs" then
                d.mess("Updating libraries...")
                local ok, err = pcall(function()
                    updater.updateAll()
                end)
                if not ok then
                    d.err("Update failed: " .. tostring(err))
                else
                    d.mess("Libraries updated!")
                end
                
            elseif cmd == "update-core" then
                d.mess("Updating TAC core...")
                local versions, err = fetchJSON(API_BASE .. "/versions.json")
                if not versions then
                    d.err("Failed to fetch version info: " .. tostring(err))
                    return
                end
                
                -- Update main init.lua
                if versions.tac.init then
                    local success, downloadErr = downloadFile(versions.tac.init.download_url, versions.tac.init.path)
                    if success then
                        d.mess("Updated: " .. versions.tac.init.path)
                    else
                        d.err("Failed: " .. versions.tac.init.path)
                    end
                end
                
                -- Update core modules
                for name, info in pairs(versions.tac.core) do
                    local success, downloadErr = downloadFile(info.download_url, info.path)
                    if success then
                        d.mess("Updated: " .. info.path)
                    else
                        d.err("Failed: " .. info.path)
                    end
                end
                
                d.mess("Core updated! Restart to apply changes.")
                
            elseif cmd == "update-extension" then
                local extName = args[2]
                if not extName then
                    d.err("Usage: updater update-extension <name>")
                    return
                end
                
                d.mess("Updating extension: " .. extName)
                local manifest, err = fetchJSON(API_BASE .. "/" .. extName .. ".json")
                if not manifest then
                    d.err("Failed to fetch extension manifest: " .. tostring(err))
                    return
                end
                
                -- Update main file
                local success = downloadFile(manifest.download_url, manifest.main_file)
                if success then
                    d.mess("Updated: " .. manifest.main_file)
                end
                
                -- Update submodules
                if manifest.submodules then
                    for _, submodule in ipairs(manifest.submodules) do
                        local success, downloadErr = downloadFile(submodule.download_url, submodule.path)
                        if success then
                            d.mess("Updated: " .. submodule.path)
                        else
                            d.err("Failed: " .. submodule.path)
                        end
                    end
                end
                
                d.mess("Extension updated! Restart to apply changes.")
                
            else
                d.err("Unknown command! Use: check, update, update-libs, update-core, update-extension")
            end
        end
    })
end

return UpdaterExtension
