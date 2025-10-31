-- TAC (Terminal Access Control) Installer
-- Version 1.1.0
-- A comprehensive installer for the TAC system with module management


-- List of all required libraries
local libs = {"cmd", "formui", "persist", "s", "shopk", "tables", "updater"}

local TAC_INSTALLER = {
    version = "1.1.1",
    name = "TAC Installer",
    
    -- GitHub configuration
    github = {
        tac_base_url = "https://raw.githubusercontent.com/Twijn/tac/main",
        tac_repo = {
            owner = "Twijn",
            repo = "tac",
            branch = "main"
        }
    },
    
    -- Core files that are always installed
    core_files = {
        "startup.lua",
        "tac/init.lua",
        "tac/commands/card.lua",
        "tac/commands/door.lua",
        "tac/commands/logs.lua",
        "tac/core/card_manager.lua",
        "tac/core/hardware.lua",
        "tac/core/logger.lua",
        "tac/core/security.lua",
        "tac/lib/shopk_shared.lua",
        "tac/extensions/_example.lua"
    },
    
    -- Library files from GitHub
    lib_files = {
        "cmd.lua",
        "formui.lua",
        "persist.lua",
        "s.lua",
        "shopk.lua",
        "tables.lua",
        "shopk_node.lua"
    },
    
    -- Available modules
    modules = {
        shopk_access = {
            name = "ShopK Access Integration",
            description = "Integrates TAC with ShopK for payment-based access control",
            files = {
                "tac/extensions/shopk_access.lua",
                "tac/extensions/shopk_access/init.lua",
                "tac/extensions/shopk_access/commands.lua",
                "tac/extensions/shopk_access/config.lua",
                "tac/extensions/shopk_access/shop.lua",
                "tac/extensions/shopk_access/slots.lua",
                "tac/extensions/shopk_access/subscriptions.lua",
                "tac/extensions/shopk_access/ui.lua",
                "tac/extensions/shopk_access/utils.lua"
            }
        },
        shop_monitor = {
            name = "Shop Monitor",
            description = "Monitor and display shop information",
            files = {
                "tac/extensions/shop_monitor.lua"
            }
        },
        updater = {
            name = "Auto-Updater",
            description = "Enables auto-update of libraries and (eventually) tsc via lib/updater.lua",
            files = {
                "lib/updater.lua"
            }
        }
    },
    
    -- Default data files
    data_files = {
        "data/settings.json",
        "data/cards.json", 
        "data/doors.json",
        "data/accesslog.json"
    }
}

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
function TAC_INSTALLER.install(type, files, baseUrl)
    print("Installing " .. type .. " files from GitHub (" .. baseUrl .. ")...")

    local total = #files
    for i, filename in ipairs(files) do
        drawProgressBar(i - 1, total, filename)

        local url = baseUrl .. "/" .. filename
        local path = "lib/" .. filename
        
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
    TAC_INSTALLER.install("Core", TAC_INSTALLER.core_files, TAC_INSTALLER.github.tac_base_url)
end

function TAC_INSTALLER.installModule(moduleName)
    local module = TAC_INSTALLER.modules[moduleName]
    if not module then
        term.setTextColor(colors.red)
        print("Module not found: " .. moduleName)
        term.setTextColor(colors.white)
        return false
    end
    
    print("Installing module: " .. module.name)
    print("Description: " .. module.description)
    
    local total = #module.files
    for i, filename in ipairs(module.files) do
        drawProgressBar(i - 1, total, filename)
        
        local url = TAC_INSTALLER.github.tac_base_url .. "/" .. filename
        local path = filename
        
        downloadFile(url, path, filename)
        sleep(0.1)
    end
    
    drawProgressBar(total, total, "Complete!")
    print("\n")
    term.setTextColor(colors.lime)
    print("Module '" .. module.name .. "' installed successfully!")
    term.setTextColor(colors.white)
    return true
end

function TAC_INSTALLER.removeModule(moduleName)
    local module = TAC_INSTALLER.modules[moduleName]
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
    print("Available TAC modules:")
    print(string.rep("=", 50))
    
    for name, module in pairs(TAC_INSTALLER.modules) do
        term.setTextColor(colors.yellow)
        print(name .. " - " .. module.name)
        term.setTextColor(colors.white)
        print("  " .. module.description)
        
        -- Check if installed
        local installed = true
        for _, filename in ipairs(module.files) do
            if not fs.exists(filename) then
                installed = false
                break
            end
        end
        
        if installed then
            term.setTextColor(colors.lime)
            print("  Status: INSTALLED")
        else
            term.setTextColor(colors.red)
            print("  Status: NOT INSTALLED")
        end
        term.setTextColor(colors.white)
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
    print("|              Version 1.0.0              |")
    print("+==========================================+")
    term.setTextColor(colors.white)
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
    print("Select modules to install (press Enter to toggle, 'done' when finished):")
    print()
    
    TAC_INSTALLER.listModules()
    
    local selectedModules = {}
    print("Enter module names to install (comma-separated), or 'all' for all modules:")
    print("Press Enter for no additional modules.")
    
    local input = read()
    if input and input ~= "" then
        if input == "all" then
            for name, _ in pairs(TAC_INSTALLER.modules) do
                table.insert(selectedModules, name)
            end
        else
            for module in input:gmatch("([^,]+)") do
                module = module:match("^%s*(.-)%s*$") -- trim whitespace
                if TAC_INSTALLER.modules[module] then
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
