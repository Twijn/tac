-- TAC (Terminal Access Control) Installer
-- Version 1.2.0
-- A comprehensive installer for the TAC system with module management


-- List of all required libraries
local libs = {"cmd", "formui", "persist", "s", "shopk", "tables", "updater"}

local TAC_INSTALLER = {
    version = "1.2.0",
    name = "TAC Installer",
    
    -- API configuration
    api = {
        base_url = "https://tac.twijn.dev/api",
        versions_url = "https://tac.twijn.dev/api/versions.json"
    },
    
    -- GitHub configuration
    github = {
        tac_base_url = "https://raw.githubusercontent.com/Twijn/tac/main",
        tac_repo = {
            owner = "Twijn",
            repo = "tac",
            branch = "main"
        }
    },
    
    -- Cached data (populated from API)
    versions = nil,
    modules = nil,
    
    -- Default data files
    data_files = {
        "data/settings.json",
        "data/doors.json",
        "data/identities.json",
        "data/identity_lookup.json",
        "data/accesslog.json"
    }
}

-- API utilities
local function fetchJSON(url)
    local response = http.get(url)
    if not response then
        return nil, "Failed to fetch: " .. url
    end
    local content = response.readAll()
    response.close()
    return textutils.unserializeJSON(content)
end

function TAC_INSTALLER.fetchVersions()
    if TAC_INSTALLER.versions then
        return TAC_INSTALLER.versions
    end
    
    local versions, err = fetchJSON(TAC_INSTALLER.api.versions_url)
    if not versions then
        error("Failed to fetch version info: " .. tostring(err))
    end
    
    TAC_INSTALLER.versions = versions
    return versions
end

function TAC_INSTALLER.fetchModuleInfo(moduleName)
    local url = TAC_INSTALLER.api.base_url .. "/" .. moduleName .. ".json"
    return fetchJSON(url)
end

function TAC_INSTALLER.buildModulesFromAPI()
    if TAC_INSTALLER.modules then
        return TAC_INSTALLER.modules
    end
    
    local versions = TAC_INSTALLER.fetchVersions()
    local modules = {}
    
    -- Build module list from extensions in versions.json
    for extName, extData in pairs(versions.tac.extensions) do
        if extName ~= "_example" then  -- Skip example extension
            -- Fetch detailed module info
            local moduleInfo = TAC_INSTALLER.fetchModuleInfo(extName)
            
            if moduleInfo then
                local files = {extData.path}
                
                -- Add submodules if they exist
                if moduleInfo.submodules then
                    for _, submodule in ipairs(moduleInfo.submodules) do
                        table.insert(files, submodule.path)
                    end
                end
                
                modules[extName] = {
                    name = moduleInfo.name or extName,
                    description = moduleInfo.description or "No description available",
                    version = extData.version,
                    files = files
                }
            else
                -- Fallback to basic info from versions.json
                modules[extName] = {
                    name = extName,
                    description = "TAC extension",
                    version = extData.version,
                    files = {extData.path}
                }
            end
        end
    end
    
    TAC_INSTALLER.modules = modules
    return modules
end

function TAC_INSTALLER.getCoreFiles()
    local versions = TAC_INSTALLER.fetchVersions()
    local files = {}
    
    -- Add startup.lua if it exists
    if fs.exists("startup.lua") then
        -- Don't overwrite existing startup.lua
    else
        table.insert(files, {path = "startup.lua", url = TAC_INSTALLER.github.tac_base_url .. "/startup.lua"})
    end
    
    -- Add init.lua
    if versions.tac.init then
        table.insert(files, {path = versions.tac.init.path, url = versions.tac.init.download_url})
    end
    
    -- Add core files
    for name, info in pairs(versions.tac.core) do
        table.insert(files, {path = info.path, url = info.download_url})
    end
    
    -- Add lib files
    if versions.tac.lib then
        for name, info in pairs(versions.tac.lib) do
            table.insert(files, {path = info.path, url = info.download_url})
        end
    end
    
    -- Add command files
    if versions.tac.commands then
        for name, info in pairs(versions.tac.commands) do
            table.insert(files, {path = info.path, url = info.download_url})
        end
    end
    
    -- Add _example extension
    if versions.tac.extensions._example then
        table.insert(files, {path = versions.tac.extensions._example.path, url = versions.tac.extensions._example.download_url})
    end
    
    return files
end

-- Progress bar utilities
local function drawProgressBar(current, total, filename)
    local width = term.getSize()
    local barWidth = width - 20
    local progress = current / total
    local filledWidth = math.floor(progress * barWidth)
    
    -- Clear the line
    term.setCursorPos(1, select(2, term.getCursorPos()))
    term.clearLine()
    
    -- Draw progress bar
    term.setTextColor(colors.white)
    term.write("Progress: [")
    
    term.setTextColor(colors.lime)
    term.write(string.rep("=", filledWidth))
    
    term.setTextColor(colors.gray)
    term.write(string.rep("-", barWidth - filledWidth))
    
    term.setTextColor(colors.white)
    term.write("] ")
    
    -- Show percentage
    term.setTextColor(colors.yellow)
    term.write(string.format("%d%%", math.floor(progress * 100)))
    
    -- Show current file on next line
    local x, y = term.getCursorPos()
    term.setCursorPos(1, y + 1)
    term.clearLine()
    term.setTextColor(colors.cyan)
    term.write("Installing: " .. filename)
    term.setCursorPos(1, y)
end

-- HTTP utilities
local function downloadFile(url, path, filename)
    local response = http.get(url)
    if not response then
        error("Failed to download: " .. filename)
    end
    
    local content = response.readAll()
    response.close()
    
    -- Create directory if needed
    local dir = fs.getDir(path)
    if not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    -- Write file
    local file = fs.open(path, "w")
    if not file then
        error("Failed to create file: " .. path)
    end
    
    file.write(content)
    file.close()
    
    return true
end

-- Main installation functions
function TAC_INSTALLER.installFiles(type, files)
    print("Installing " .. type .. " files...")

    local total = #files
    for i, fileInfo in ipairs(files) do
        local filename = fileInfo.path or fileInfo
        drawProgressBar(i - 1, total, filename)

        local url = fileInfo.url or (TAC_INSTALLER.github.tac_base_url .. "/" .. filename)
        local path = fileInfo.path or filename
        
        downloadFile(url, path, filename)
        sleep(0.1) -- Small delay for visual feedback
    end
    
    drawProgressBar(total, total, "Complete!")
    print("\n")
    term.setTextColor(colors.lime)
    print(type .. " files installed successfully!")
    term.setTextColor(colors.white)
end

function TAC_INSTALLER.installLibraries()
    shell.run("wget", "run", "https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua", table.unpack(libs))
end

function TAC_INSTALLER.installCore()
    local coreFiles = TAC_INSTALLER.getCoreFiles()
    TAC_INSTALLER.installFiles("Core", coreFiles)
end

function TAC_INSTALLER.installModule(moduleName)
    -- Build modules from API if not already cached
    local modules = TAC_INSTALLER.buildModulesFromAPI()
    local module = modules[moduleName]
    
    if not module then
        term.setTextColor(colors.red)
        print("Module not found: " .. moduleName)
        term.setTextColor(colors.white)
        return false
    end
    
    print("Installing module: " .. module.name)
    print("Description: " .. module.description)
    
    -- Get module info from API for accurate file list
    local moduleInfo = TAC_INSTALLER.fetchModuleInfo(moduleName)
    local files = {}
    
    if moduleInfo then
        -- Add main file
        table.insert(files, {path = moduleInfo.main_file, url = moduleInfo.download_url})
        
        -- Add submodules
        if moduleInfo.submodules then
            for _, submodule in ipairs(moduleInfo.submodules) do
                table.insert(files, {path = submodule.path, url = submodule.download_url})
            end
        end
    else
        -- Fallback to cached module info
        for _, path in ipairs(module.files) do
            table.insert(files, {path = path, url = TAC_INSTALLER.github.tac_base_url .. "/" .. path})
        end
    end
    
    TAC_INSTALLER.installFiles("Module '" .. module.name .. "'", files)
    return true
end

function TAC_INSTALLER.removeModule(moduleName)
    local modules = TAC_INSTALLER.buildModulesFromAPI()
    local module = modules[moduleName]
    
    if not module then
        term.setTextColor(colors.red)
        print("Module not found: " .. moduleName)
        term.setTextColor(colors.white)
        return false
    end
    
    print("Removing module: " .. module.name)
    
    for _, filename in ipairs(module.files) do
        if fs.exists(filename) then
            fs.delete(filename)
            print("Removed: " .. filename)
        end
    end
    
    term.setTextColor(colors.lime)
    print("Module '" .. module.name .. "' removed successfully!")
    term.setTextColor(colors.white)
    return true
end

function TAC_INSTALLER.listModules()
    print("Fetching module list from API...")
    local modules = TAC_INSTALLER.buildModulesFromAPI()
    
    print("Available modules:")
    
    for name, module in pairs(modules) do
        -- Check if installed
        local installed = true
        for _, filename in ipairs(module.files) do
            if not fs.exists(filename) then
                installed = false
                break
            end
        end
        
        -- Compact single-line format with status indicator
        term.setTextColor(colors.yellow)
        term.write(name)
        term.setTextColor(colors.white)
        term.write(" - ")
        
        if installed then
            term.setTextColor(colors.lime)
            term.write("[INSTALLED]")
        else
            term.setTextColor(colors.gray)
            term.write("[NOT INSTALLED]")
        end
        
        term.setTextColor(colors.white)
        term.write(" v" .. (module.version or "?"))
        print()
    end
end

function TAC_INSTALLER.fullInstall(selectedModules)
    selectedModules = selectedModules or {}
    
    term.clear()
    term.setCursorPos(1, 1)
    
    term.setTextColor(colors.cyan)
    print("+==========================================+")
    print("|         TAC System Installer            |")
    print("|              Version "..TAC_INSTALLER.version.."              |")
    print("+==========================================+")
    term.setTextColor(colors.white)
    print()
    
    -- Fetch version info from API
    print("Fetching latest version information...")
    local ok, err = pcall(TAC_INSTALLER.fetchVersions)
    if not ok then
        term.setTextColor(colors.red)
        print("Error: " .. tostring(err))
        term.setTextColor(colors.white)
        return
    end
    print()
    
    -- Install libraries
    TAC_INSTALLER.installLibraries()
    print()
    
    -- Install core
    TAC_INSTALLER.installCore()
    print()
    
    -- Install selected modules
    if #selectedModules > 0 then
        print("Installing selected modules...")
        for _, moduleName in ipairs(selectedModules) do
            TAC_INSTALLER.installModule(moduleName)
            print()
        end
    end
    
    term.setTextColor(colors.lime)
    print("+==========================================+")
    print("|        Installation Complete!           |")
    print("+==========================================+")
    term.setTextColor(colors.white)
    print()
    print("You can now run 'startup' to start the TAC system.")
    print("Use 'installer.lua --help' for more options.")
end

-- Command line interface
local function showHelp()
    print("TAC Installer v" .. TAC_INSTALLER.version)
    print("Usage: installer [command] [options]")
    print()
    print("Commands:")
    print("  install              - Full installation with module selection")
    print("  install-libs         - Install/refresh library files only")
    print("  install-core         - Install core TAC files only")
    print("  install-module <name> - Install specific module")
    print("  remove-module <name>  - Remove specific module")
    print("  list-modules         - List available modules")
    print("  --help, -h           - Show this help")
    print()
    print("Note: Module information is dynamically fetched from")
    print("      https://tac.twijn.dev/api/versions.json")
    print()
    print("Examples:")
    print("  installer install")
    print("  installer install-libs")
    print("  installer install-module shopk_access")
    print("  installer remove-module shop_monitor")
end

-- Main execution
local args = {...}

if #args == 0 or args[1] == "install" then
    -- Interactive installation
    print("TAC Installer - Module Selection")
    print()
    
    TAC_INSTALLER.listModules()
    
    local selectedModules = {}
    print()
    print("Enter modules (comma-separated) or 'all':")
    term.setTextColor(colors.gray)
    print("(Press Enter for core only)")
    term.setTextColor(colors.white)
    term.write("> ")
    
    local input = read()
    if input and input ~= "" then
        local modules = TAC_INSTALLER.buildModulesFromAPI()
        if input == "all" then
            for name, _ in pairs(modules) do
                table.insert(selectedModules, name)
            end
        else
            for module in input:gmatch("([^,]+)") do
                module = module:match("^%s*(.-)%s*$") -- trim whitespace
                if modules[module] then
                    table.insert(selectedModules, module)
                end
            end
        end
    end
    
    TAC_INSTALLER.fullInstall(selectedModules)
    
elseif args[1] == "install-libs" then
    TAC_INSTALLER.installLibraries()
    
elseif args[1] == "install-core" then
    TAC_INSTALLER.installCore()
    
elseif args[1] == "install-module" and args[2] then
    TAC_INSTALLER.installModule(args[2])
    
elseif args[1] == "remove-module" and args[2] then
    TAC_INSTALLER.removeModule(args[2])
    
elseif args[1] == "list-modules" then
    TAC_INSTALLER.listModules()
    
elseif args[1] == "--help" or args[1] == "-h" then
    showHelp()
    
else
    term.setTextColor(colors.red)
    print("Unknown command: " .. tostring(args[1]))
    term.setTextColor(colors.white)
    showHelp()
end
