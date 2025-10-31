--[[
    TAC Shop Monitor Extension
    
    Displays available shop items on a monitor with payment commands.
    Shows access tiers, pricing, and renewal information on an external monitor.
    Optionally integrates with shopk_access extension for enhanced functionality.
    
    @module tac.extensions.shop_monitor
    @author Twijn
    @version 1.0.4
    
    @example
    -- This extension is loaded automatically by TAC.
    -- Configure in TAC shell:
    
    -- > monitor config monitor_side top
    -- > monitor config display_title "ACCESS SHOP"
    -- > monitor start
    -- > monitor stop
    
    -- From another extension:
    function MyExtension.init(tac)
        local monitor = tac.require("shop_monitor")
        if monitor then
            -- Monitor extension provides display functionality
            print("Shop monitor available")
        end
    end
]]

local ShopMonitorExtension = {
    name = "shop_monitor",
    version = "1.0.4",
    description = "Display available shop items on a monitor",
    author = "Twijn",
    dependencies = {},
    optional_dependencies = {"shopk_access"}  -- Enhanced if shopk_access is available
}

-- Load required libraries
local formui = require("formui")
local shopk_shared = require("tac.lib.shopk_shared")

-- Default configuration for monitor extension
MONITOR_CONFIG = {
    monitor_side = "right",
    refresh_rate = 10,
    refresh_interval = 10,
    show_unavailable = true,
    show_renewal = true,
    show_address = true,
    display_title = "SHOP DIRECTORY",
    available_header = "AVAILABLE ACCESS:",
    display_tiers = {"Basic", "Plus", "Premium"},
    background_color = colors.black,
    title_color = colors.yellow,
    header_color = colors.cyan,
    text_color = colors.white
}

-- Monitor state
local monitor = nil
local updateTimer = nil

--- Get shop data for display (using shared utility)
-- @param tac table - TAC instance
-- @return table - shop data
local function getShopData(tac)
    return shopk_shared.getShopData(tac)
end

--- Get available slots for each tier (using shared utility)
-- @param tac table - TAC instance
-- @param pattern string - tier pattern
-- @return number - available slots count
local function getAvailableSlots(tac, pattern)
    return shopk_shared.getAvailableSlots(tac, pattern)
end

--- Format payment metadata (using shared utility)
-- @param tierPattern string - tier pattern
-- @param tierData table - tier configuration data
-- @return string - formatted metadata
local function formatPaymentMeta(tierPattern, tierData)
    return shopk_shared.formatPaymentMeta(tierPattern, tierData)
end

--- Update monitor display
-- @param tac table - TAC instance
local function updateMonitorDisplay(tac)
    if not monitor then return end
    
    local shopData = getShopData(tac)
    
    monitor.setBackgroundColor(MONITOR_CONFIG.background_color)
    monitor.clear()
    monitor.setCursorPos(1, 1)
    
    -- Title
    monitor.setTextColor(MONITOR_CONFIG.title_color)
    monitor.write("=== " .. (MONITOR_CONFIG.display_title or "SHOP DIRECTORY") .. " ===")
    monitor.setCursorPos(1, 2)
    
    -- Shop status
    monitor.setTextColor(MONITOR_CONFIG.header_color)
    if shopData.running then
        monitor.write("Status: ONLINE")
    else
        monitor.write("Status: OFFLINE")
    end
    monitor.setCursorPos(1, 3)
    
    -- Shop address
    if MONITOR_CONFIG.show_address and shopData.address then
        monitor.setTextColor(MONITOR_CONFIG.text_color)
        monitor.write("Address: " .. shopData.address)
        monitor.setCursorPos(1, 4)
    end
    
    monitor.write("")
    local currentLine = monitor.getCursorPos() and (select(2, monitor.getCursorPos()) + 1) or 5
    
    -- Available items
    monitor.setTextColor(MONITOR_CONFIG.header_color)
    monitor.setCursorPos(1, currentLine)
    monitor.write(MONITOR_CONFIG.available_header or "AVAILABLE ACCESS:")
    currentLine = currentLine + 1
    
    if not shopData.running then
        monitor.setCursorPos(1, currentLine)
        monitor.setTextColor(colors.red)
        monitor.write("Shop is currently offline")
        return
    end
    
    if not next(shopData.tiers) then
        monitor.setCursorPos(1, currentLine)
        monitor.setTextColor(colors.orange)
        monitor.write("No items available")
        return
    end
    
    -- List each tier
    for pattern, tier in pairs(shopData.tiers) do
        local available = getAvailableSlots(tac, pattern)
        
        monitor.setCursorPos(1, currentLine)
        monitor.setTextColor(MONITOR_CONFIG.text_color)
        monitor.write(tier.description or pattern)
        currentLine = currentLine + 1
        
        monitor.setCursorPos(3, currentLine)
        monitor.write("Price: " .. tier.price .. " KRO (" .. tier.duration .. " days)")
        currentLine = currentLine + 1
        
        if MONITOR_CONFIG.show_renewal then
            monitor.setCursorPos(3, currentLine)
            monitor.write("Renewal: " .. tier.renewal_price .. " KRO")
            currentLine = currentLine + 1
        end
        
        monitor.setCursorPos(3, currentLine)
        if available > 0 then
            monitor.setTextColor(colors.lime)
            monitor.write("Available: " .. available .. " slots")
        else
            monitor.setTextColor(colors.red)
            monitor.write("SOLD OUT")
        end
        currentLine = currentLine + 1
        
        -- Payment commands
        if available > 0 then
            if shopData.address then
                local monitorWidth, monitorHeight = monitor.getSize()
                
                -- New purchase command
                monitor.setCursorPos(1, currentLine)
                monitor.setTextColor(colors.orange)
                monitor.write("BUY: ")
                monitor.setTextColor(colors.yellow)
                local meta = formatPaymentMeta(pattern, tier)
                local buyCommand = "/pay " .. shopData.address .. " " .. tier.price .. " " .. meta
            
            -- Split command if too long
            if #buyCommand > (monitorWidth - 5) then
                -- Write command on new line with indentation
                currentLine = currentLine + 1
                monitor.setCursorPos(3, currentLine)
                monitor.write(buyCommand)
            else
                -- Write on same line
                monitor.write(buyCommand)
            end
            currentLine = currentLine + 1
            
            -- Renewal command
            if MONITOR_CONFIG.show_renewal then
                monitor.setCursorPos(1, currentLine)
                monitor.setTextColor(colors.orange)
                monitor.write("RENEW: ")
                monitor.setTextColor(colors.yellow)
                local renewMeta = "sku=renewal"
                local renewCommand = "/pay " .. shopData.address .. " " .. tier.renewal_price .. " " .. renewMeta
                
                -- Split command if too long
                if #renewCommand > (monitorWidth - 7) then
                    -- Write command on new line with indentation
                    currentLine = currentLine + 1
                    monitor.setCursorPos(3, currentLine)
                    monitor.write(renewCommand)
                else
                    -- Write on same line
                    monitor.write(renewCommand)
                end
                currentLine = currentLine + 1
            end
            else
                -- No shop address available
                monitor.setCursorPos(1, currentLine)
                monitor.setTextColor(colors.red)
                monitor.write("Shop address not available - start shop first")
                currentLine = currentLine + 1
            end
        end
        
        monitor.setCursorPos(1, currentLine)
        monitor.write("")
        currentLine = currentLine + 1
    end
    
    -- Footer
    monitor.setCursorPos(1, currentLine)
    monitor.setTextColor(colors.gray)
    monitor.write("Plugin will auto-detect your username for renewals")
    monitor.setCursorPos(1, currentLine + 1)
    monitor.write("Updated: " .. os.date("%H:%M:%S"))
end

--- Start monitor updates
-- @param tac table - TAC instance
local function startMonitorUpdates(tac)
    if updateTimer then
        os.cancelTimer(updateTimer)
    end

    -- Set up recurring updates
    local function scheduleUpdate(time)
        time = time or MONITOR_CONFIG.refresh_interval
        updateTimer = os.startTimer(time)
    end

    tac.addHook("timer", function(timerID)
        if timerID == updateTimer then
            term.setTextColor(colors.gray)
            print("Monitor: Auto-updating display...")
            term.setTextColor(colors.white)
            updateMonitorDisplay(tac)
            scheduleUpdate()
        end
    end)

    scheduleUpdate(3)
end

--- Configuration form
-- @param tac table - TAC instance
-- @param d table - display interface
local function showConfig(tac, d)
    -- Get available monitors
    local monitors = {}
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "monitor" then
            table.insert(monitors, side)
        end
    end
    
    if #monitors == 0 then
        d.err("No monitors found! Connect a monitor first.")
        return
    end
    
    local form = formui.new("Shop Monitor Configuration")
    
    -- Monitor selection
    local currentIndex = 1
    if MONITOR_CONFIG.monitor_side then
        for i, side in ipairs(monitors) do
            if side == MONITOR_CONFIG.monitor_side then
                currentIndex = i
                break
            end
        end
    end
    
    form:select("Monitor", monitors, currentIndex)
    form:number("Refresh Interval (seconds)", MONITOR_CONFIG.refresh_interval, formui.validation.number_positive)
    form:text("Title Color", tostring(MONITOR_CONFIG.title_color))
    form:text("Header Color", tostring(MONITOR_CONFIG.header_color))
    form:text("Text Color", tostring(MONITOR_CONFIG.text_color))
    form:text("Background Color", tostring(MONITOR_CONFIG.background_color))
    
    local result = form:run()
    
    if result then
        MONITOR_CONFIG.monitor_side = result["Monitor"]
        MONITOR_CONFIG.refresh_interval = result["Refresh Interval (seconds)"]
        MONITOR_CONFIG.title_color = tonumber(result["Title Color"]) or colors.yellow
        MONITOR_CONFIG.header_color = tonumber(result["Header Color"]) or colors.cyan
        MONITOR_CONFIG.text_color = tonumber(result["Text Color"]) or colors.white
        MONITOR_CONFIG.background_color = tonumber(result["Background Color"]) or colors.black
        
        -- Save configuration
        tac.settings.set("shop_monitor_config", MONITOR_CONFIG)
        
        -- Initialize monitor
        monitor = peripheral.wrap(MONITOR_CONFIG.monitor_side)
        if monitor then
            d.mess("Monitor configured: " .. MONITOR_CONFIG.monitor_side)
            startMonitorUpdates(tac)
        else
            d.err("Failed to connect to monitor: " .. MONITOR_CONFIG.monitor_side)
        end
    else
        d.mess("Configuration cancelled")
    end
end

--- Extension initialization
-- @param tac table - TAC instance
function ShopMonitorExtension.init(tac)
    term.setTextColor(colors.magenta)
    print("*** Shop Monitor Extension Loading ***")
    term.setTextColor(colors.white)
    
    -- Register extension settings requirements
    tac.registerExtensionSettings("shop_monitor", {
        title = "Shop Monitor Configuration",
        required = {
            {
                key = "shop_monitor_side",
                label = "Monitor Side",
                type = "peripheral",
                filter = "monitor",
                validate = function(v) return v ~= nil and v ~= "", "Please select a monitor" end
            },
            {
                key = "shop_monitor_title",
                label = "Display Title",
                type = "text",
                default = "SHOP DIRECTORY",
                validate = function(v) return v ~= nil and v ~= "", "Please enter a title" end
            },
            {
                key = "shop_monitor_header",
                label = "Available Items Header",
                type = "text", 
                default = "AVAILABLE ACCESS:",
                validate = function(v) return v ~= nil and v ~= "", "Please enter a header" end
            }
        }
    })
    
    -- Load saved configuration
    local saved_config = tac.settings.get("shop_monitor_config")
    if saved_config then
        for k, v in pairs(saved_config) do
            MONITOR_CONFIG[k] = v
        end
    end
    
    -- Use new settings system for monitor configuration
    local monitor_side = tac.settings.get("shop_monitor_side")
    if monitor_side then
        MONITOR_CONFIG.monitor_side = monitor_side
    end
    
    local display_title = tac.settings.get("shop_monitor_title")
    if display_title then
        MONITOR_CONFIG.display_title = display_title
    end
    
    local available_header = tac.settings.get("shop_monitor_header")
    if available_header then
        MONITOR_CONFIG.available_header = available_header
    end
    
    -- Initialize monitor - auto-detect if not configured
    if MONITOR_CONFIG.monitor_side then
        monitor = peripheral.wrap(MONITOR_CONFIG.monitor_side)
        if monitor then
            print("Monitor connected: " .. MONITOR_CONFIG.monitor_side)
        else
            print("Warning: Configured monitor not found, will auto-detect")
        end
    end
    
    -- Auto-detect first available monitor if none configured
    if not monitor then
        for _, side in ipairs(peripheral.getNames()) do
            if peripheral.getType(side) == "monitor" then
                MONITOR_CONFIG.monitor_side = side
                monitor = peripheral.wrap(side)
                tac.settings.set("shop_monitor_config", MONITOR_CONFIG)
                print("Monitor auto-configured: " .. side)
                break
            end
        end
    end
    
        -- Register monitor update background process
    tac.registerBackgroundProcess("monitor_updates", function()
        print("Monitor background process starting...")
        
        -- Wait for ShopK to be ready first, but don't wait forever
        local attempts = 0
        while attempts < 100 do -- Wait up to 10 seconds (100 * 0.1s)
            local shopData = getShopData(tac)
            if shopData.address and shopData.running then
                print("Monitor: ShopK ready, starting updates...")
                break
            end
            if attempts % 50 == 0 then -- Every 5 seconds
                print("Monitor: Still waiting for ShopK... (" .. attempts/10 .. "s)")
            end
            sleep(0.1)
            attempts = attempts + 1
        end
        
        -- Update monitor periodically regardless of ShopK status
        while true do
            -- Check if monitor UI is in use (showing interactive screens)
            local monitor_ui = tac.extensions.shopk_access and tac.extensions.shopk_access.monitor_ui
            local isMonitorBusy = monitor_ui and monitor_ui.isInUse and monitor_ui.isInUse()
            
            -- Debug: Log when monitor is busy
            if isMonitorBusy and MONITOR_CONFIG.debug then
                print("[shop_monitor] Monitor UI is busy, skipping update")
            end
            
            if not isMonitorBusy then
                -- Force monitor detection every time
                local currentMonitor = nil
                if MONITOR_CONFIG.monitor_side then
                    currentMonitor = peripheral.wrap(MONITOR_CONFIG.monitor_side)
                end
                
                if not currentMonitor then
                    -- Auto-detect monitor
                    for _, side in ipairs(peripheral.getNames()) do
                        if peripheral.getType(side) == "monitor" then
                            currentMonitor = peripheral.wrap(side)
                            if currentMonitor then
                                MONITOR_CONFIG.monitor_side = side
                                monitor = currentMonitor
                                print("Monitor: Auto-detected " .. side)
                                break
                            end
                        end
                    end
                else
                    monitor = currentMonitor
                end
                
                if monitor then
                    local success, err = pcall(updateMonitorDisplay, tac)
                    if not success then
                        print("Monitor update error: " .. tostring(err))
                    end
                end
            else
                -- Monitor is busy, skip this update
                -- print("Monitor: Skipping update (interactive UI active)")
            end
            
            sleep(MONITOR_CONFIG.refresh_interval or 10)
        end
    end)
    
    -- Add commands
    tac.registerCommand("monitor", {
        description = "Configure and manage shop monitor display",
        complete = function(args)
            if #args > 0 then
                return {"config", "start", "stop", "update", "debug"}
            end
            return {}
        end,
        execute = function(args, d)
            local cmd = args[1] or "update"  -- Default to update, not config
            
            if cmd == "config" then
                showConfig(tac, d)
            elseif cmd == "update" then
                -- ALWAYS try to find and use a monitor, no configuration required
                local foundMonitor = nil
                
                -- Try configured monitor first
                if MONITOR_CONFIG.monitor_side then
                    foundMonitor = peripheral.wrap(MONITOR_CONFIG.monitor_side)
                end
                
                -- If no configured monitor or it's not working, find any monitor
                if not foundMonitor then
                    for _, side in ipairs(peripheral.getNames()) do
                        if peripheral.getType(side) == "monitor" then
                            foundMonitor = peripheral.wrap(side)
                            if foundMonitor then
                                MONITOR_CONFIG.monitor_side = side
                                monitor = foundMonitor
                                d.mess("Auto-detected monitor on " .. side)
                                break
                            end
                        end
                    end
                end
                
                if foundMonitor then
                    monitor = foundMonitor
                    updateMonitorDisplay(tac)
                    d.mess("Monitor display updated successfully!")
                else
                    d.err("No monitor connected! Available peripherals:")
                    for _, side in ipairs(peripheral.getNames()) do
                        d.mess("  " .. side .. ": " .. peripheral.getType(side))
                    end
                end
            elseif cmd == "debug" then
                -- Debug command to show what the monitor sees
                local shopData = getShopData(tac)
                d.mess("=== Monitor Debug Info ===")
                d.mess("Shop running: " .. tostring(shopData.running))
                d.mess("Shop address: " .. tostring(shopData.address))
                
                if next(shopData.tiers) then
                    d.mess("Available tiers:")
                    for pattern, tier in pairs(shopData.tiers) do
                        local available = getAvailableSlots(tac, pattern)
                        d.mess("  " .. pattern .. ": " .. available .. " slots (" .. tier.price .. " KRO)")
                    end
                else
                    d.mess("No tiers configured")
                end
            else
                d.err("Unknown command: " .. cmd)
                d.mess("Available commands: config, update, debug")
            end
        end
    })
    
    term.setTextColor(colors.lime)
    print("Shop Monitor Extension loaded successfully!")
    term.setTextColor(colors.white)
end

return ShopMonitorExtension