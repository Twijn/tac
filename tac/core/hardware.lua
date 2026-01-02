--[[
    TAC Hardware Manager
    
    Handles peripheral detection, door control, and sign updates for the TAC system.
    Provides utilities for finding and interacting with ComputerCraft peripherals.
    Supports NFC readers, RFID scanners, monitors, and signs for door displays.
    
    @module tac.core.hardware
    @author Twijn
    @version 1.1.0
    
    @example
    -- In your extension:
    function MyExtension.init(tac)
        local Hardware = require("tac.core.hardware")
        
        -- Open a door by ID
        Hardware.openDoor("tenant_door_1")
        
        -- Find all NFC readers
        local readers = Hardware.findPeripheralsOfType("nfc_reader")
        for _, reader in ipairs(readers) do
            print("Found reader: " .. reader)
        end
        
        -- Find all RFID scanners
        local rfidScanners = Hardware.findPeripheralsOfType("rfid_scanner")
        for _, scanner in ipairs(rfidScanners) do
            print("Found RFID scanner: " .. scanner)
        end
        
        -- Update a sign after access
        Hardware.updateSign("back", "Access Granted", "Welcome!")
        
        -- Show access animations
        Hardware.showEnterAnimation()
        Hardware.showDenyAnimation()
    end
]]

local HardwareManager = {}

-- Monitor UI defaults
HardwareManager.MONITOR_COLORS = {
    background = colors.black,
    title = colors.cyan,
    text = colors.white,
    textDim = colors.lightGray,
    success = colors.lime,
    error = colors.red,
    warning = colors.orange,
    accent = colors.yellow,
    border = colors.gray
}

--- Find peripherals of a specific type
--
-- Searches all connected peripherals and returns a list of names matching the specified type.
-- Useful for finding NFC readers, RFID scanners, modems, monitors, etc.
--
---@param filter string The peripheral type to search for (e.g., "nfc_reader", "rfid_scanner", "modem", "monitor")
---@return table Array of peripheral names matching the filter
---@usage local readers = HardwareManager.findPeripheralsOfType("nfc_reader")
function HardwareManager.findPeripheralsOfType(filter)
    local peripherals = peripheral.getNames()
    local found = {}

    for _, name in pairs(peripherals) do
        if peripheral.getType(name) == filter then
            table.insert(found, name)
        end
    end

    return found
end

--- Scan for RFID badges in range
--
-- Uses an RFID scanner to find badges in the area.
-- Returns a list of detected badges with their data and distance.
--
---@param scannerName string The name of the RFID scanner peripheral
---@return table|nil Array of badge tables with {data, distance}, or nil if scanner not found
---@usage local badges = HardwareManager.scanRFID("rfid_scanner_0")
function HardwareManager.scanRFID(scannerName)
    if not scannerName or not peripheral.isPresent(scannerName) then
        return nil
    end
    
    local scanner = peripheral.wrap(scannerName)
    if not scanner or not scanner.scan then
        return nil
    end
    
    return scanner.scan()
end

--- Find the closest RFID badge
--
-- Scans for RFID badges and returns the one with the smallest distance.
--
---@param scannerName string The name of the RFID scanner peripheral
---@return table|nil The closest badge {data, distance}, or nil if none found
---@usage local badge = HardwareManager.findClosestRFID("rfid_scanner_0")
function HardwareManager.findClosestRFID(scannerName)
    local badges = HardwareManager.scanRFID(scannerName)
    if not badges or #badges == 0 then
        return nil
    end
    
    local closest = badges[1]
    for _, badge in ipairs(badges) do
        if badge.distance < closest.distance then
            closest = badge
        end
    end
    
    return closest
end

--- Update a door sign with door information
--
-- Updates a sign peripheral to display the door name and tags.
-- The sign will show the door name on line 2 with decorative borders.
--
---@param door table Door configuration with fields:
--   - sign (string): Peripheral name of the sign
--   - name (string): Door name to display
--   - tags (table): Array of tag strings
---@usage HardwareManager.updateDoorSign(door)
function HardwareManager.updateDoorSign(door)
    if door and door.sign then
        peripheral.call(door.sign, "setSignText", "===============", door.name, "===============", table.concat(door.tags, ","))
    end
end

--- Center text on a monitor line
--
-- Helper to write centered text on a monitor at a specific Y position.
--
---@param mon table Monitor peripheral
---@param y number Y coordinate
---@param text string Text to center
local function centerTextOnMonitor(mon, y, text)
    local w, _ = mon.getSize()
    local x = math.floor((w - #text) / 2) + 1
    mon.setCursorPos(x, y)
    mon.write(text)
end

--- Draw a horizontal line on a monitor
--
-- Helper to draw a line across the monitor.
--
---@param mon table Monitor peripheral
---@param y number Y coordinate
---@param char string Character to use (default "-")
local function drawMonitorLine(mon, y, char)
    char = char or "-"
    local w, _ = mon.getSize()
    mon.setCursorPos(1, y)
    mon.write(string.rep(char, w))
end

--- Update door monitor with door information
--
-- Updates a monitor peripheral to display the door name, tags, and status.
-- Adapts display based on monitor size.
--
---@param door table Door configuration with fields:
--   - monitor (string): Peripheral name of the monitor
--   - name (string): Door name to display
--   - tags (table): Array of tag strings
---@usage HardwareManager.updateDoorMonitor(door)
function HardwareManager.updateDoorMonitor(door)
    if not door or not door.monitor then return end
    
    local mon = peripheral.wrap(door.monitor)
    if not mon then return end
    
    local w, h = mon.getSize()
    local colors = HardwareManager.MONITOR_COLORS
    
    -- Set up monitor
    mon.setTextScale(0.5)
    mon.setBackgroundColor(colors.background)
    mon.clear()
    
    -- Minimal display for very small monitors (1x1 or similar)
    if w < 10 or h < 5 then
        mon.setTextColor(colors.title)
        mon.setCursorPos(1, 1)
        local shortName = door.name:sub(1, w)
        mon.write(shortName)
        return
    end
    
    -- Small monitor (up to 2x2)
    if w < 20 or h < 8 then
        mon.setTextColor(colors.border)
        drawMonitorLine(mon, 1, "=")
        
        mon.setTextColor(colors.title)
        centerTextOnMonitor(mon, math.floor(h/2), door.name)
        
        mon.setTextColor(colors.border)
        drawMonitorLine(mon, h, "=")
        return
    end
    
    -- Medium to large monitors
    local cursorY = 1
    
    -- Top border
    mon.setTextColor(colors.border)
    drawMonitorLine(mon, cursorY, "=")
    cursorY = cursorY + 1
    
    -- Door name (centered and prominent)
    mon.setTextColor(colors.title)
    centerTextOnMonitor(mon, cursorY, door.name)
    cursorY = cursorY + 1
    
    -- Separator
    mon.setTextColor(colors.border)
    drawMonitorLine(mon, cursorY, "-")
    cursorY = cursorY + 1
    
    -- Tags section (if space permits)
    if h > 6 and door.tags and #door.tags > 0 then
        mon.setTextColor(colors.textDim)
        centerTextOnMonitor(mon, cursorY, "Access Tags:")
        cursorY = cursorY + 1
        
        mon.setTextColor(colors.text)
        local tagStr = table.concat(door.tags, ", ")
        -- Wrap tags if needed
        if #tagStr > w - 2 then
            -- Split into multiple lines
            local remaining = tagStr
            while #remaining > 0 and cursorY < h - 1 do
                local line = remaining:sub(1, w - 2)
                mon.setCursorPos(2, cursorY)
                mon.write(line)
                remaining = remaining:sub(w - 1)
                cursorY = cursorY + 1
            end
        else
            centerTextOnMonitor(mon, cursorY, tagStr)
            cursorY = cursorY + 1
        end
    end
    
    -- Bottom border
    mon.setTextColor(colors.border)
    drawMonitorLine(mon, h, "=")
end

--- Show door status on monitor
--
-- Displays a status message on the door monitor (for access granted/denied).
--
---@param door table Door configuration with monitor field
---@param status string "granted" or "denied"
---@param message string Message to display
---@param subtext string|nil Optional subtext (e.g., person's name)
function HardwareManager.showDoorMonitorStatus(door, status, message, subtext)
    if not door or not door.monitor then return end
    
    local mon = peripheral.wrap(door.monitor)
    if not mon then return end
    
    local w, h = mon.getSize()
    local colors = HardwareManager.MONITOR_COLORS
    
    mon.setBackgroundColor(colors.background)
    mon.clear()
    
    local statusColor = status == "granted" and colors.success or colors.error
    local centerY = math.floor(h / 2)
    
    -- Very small monitor
    if w < 10 or h < 3 then
        mon.setTextColor(statusColor)
        mon.setCursorPos(1, 1)
        mon.write(status == "granted" and "OK" or "NO")
        return
    end
    
    -- Small monitor
    if w < 15 or h < 5 then
        mon.setTextColor(statusColor)
        centerTextOnMonitor(mon, centerY, message:sub(1, w))
        return
    end
    
    -- Medium to large monitors
    -- Border
    mon.setTextColor(statusColor)
    drawMonitorLine(mon, 1, status == "granted" and "=" or "X")
    drawMonitorLine(mon, h, status == "granted" and "=" or "X")
    
    -- Main message
    mon.setTextColor(statusColor)
    centerTextOnMonitor(mon, centerY, message)
    
    -- Subtext (name or reason)
    if subtext and h > 5 then
        mon.setTextColor(colors.text)
        centerTextOnMonitor(mon, centerY + 1, subtext)
    end
end

--- Show identity information on door monitor
--
-- Displays comprehensive identity information during access attempts.
-- Shows name, tags, access method, and status on door monitors.
--
---@param door table Door configuration with monitor field
---@param identity table Identity data with name, tags, etc.
---@param status string "scanning", "granted", "denied", "expired", etc.
---@param distance number|nil Optional distance for RFID scans
function HardwareManager.showIdentityOnDoorMonitor(door, identity, status, distance)
    if not door or not door.monitor then return end
    
    local mon = peripheral.wrap(door.monitor)
    if not mon then return end
    
    local w, h = mon.getSize()
    local colors = HardwareManager.MONITOR_COLORS
    
    mon.setBackgroundColor(colors.background)
    mon.clear()
    
    local statusColor = colors.text
    local statusText = "SCANNING"
    
    if status == "granted" then
        statusColor = colors.success
        statusText = "ACCESS GRANTED"
    elseif status == "denied" then
        statusColor = colors.error
        statusText = "ACCESS DENIED"
    elseif status == "expired" then
        statusColor = colors.error
        statusText = "EXPIRED"
    elseif status == "too_far" then
        statusColor = colors.warning
        statusText = "TOO FAR"
    elseif status == "scanning" then
        statusColor = colors.warning
        statusText = "SCANNING..."
    end
    
    -- Very small monitor
    if w < 10 or h < 5 then
        mon.setTextColor(statusColor)
        mon.setCursorPos(1, 1)
        if status == "granted" then
            mon.write("OK")
        elseif identity then
            mon.write(identity.name:sub(1, w))
        else
            mon.write(statusText:sub(1, w))
        end
        return
    end
    
    local y = 1
    
    -- Top border
    mon.setTextColor(statusColor)
    drawMonitorLine(mon, y, status == "granted" and "=" or (status == "denied" and "X" or "-"))
    y = y + 1
    
    -- Status
    centerTextOnMonitor(mon, y, statusText)
    y = y + 1
    
    if identity then
        y = y + 1
        
        -- Name
        mon.setTextColor(colors.accent)
        local displayName = identity.name or "Unknown"
        if #displayName > w - 4 then
            displayName = displayName:sub(1, w - 7) .. "..."
        end
        centerTextOnMonitor(mon, y, displayName)
        y = y + 1
        
        if h > 8 then
            y = y + 1
            
            -- Tags
            mon.setTextColor(colors.textDim)
            local tagStr = table.concat(identity.tags or {}, ", ")
            if #tagStr > w - 4 then
                tagStr = tagStr:sub(1, w - 7) .. "..."
            end
            centerTextOnMonitor(mon, y, tagStr)
            y = y + 1
        end
        
        if h > 10 and distance then
            y = y + 1
            mon.setTextColor(colors.textDim)
            centerTextOnMonitor(mon, y, string.format("Distance: %.1fm", distance))
        end
    end
    
    -- Bottom border
    mon.setTextColor(statusColor)
    drawMonitorLine(mon, h, status == "granted" and "=" or (status == "denied" and "X" or "-"))
end

--- Update all door displays (signs and monitors)
--
-- Iterates through all doors and updates their signs and monitors with current information.
--
---@param doors table Persistent doors storage object with .getAll() method
---@usage HardwareManager.updateAllDisplays(tac.doors)
function HardwareManager.updateAllDisplays(doors)
    for reader, door in pairs(doors.getAll()) do
        HardwareManager.updateDoorSign(door)
        HardwareManager.updateDoorMonitor(door)
    end
end

--- Update all door signs
--
-- Iterates through all doors and updates their signs with current information.
-- For backwards compatibility - prefer updateAllDisplays for new code.
--
---@param doors table Persistent doors storage object with .getAll() method
---@usage HardwareManager.updateAllSigns(tac.doors)
function HardwareManager.updateAllSigns(doors)
    HardwareManager.updateAllDisplays(doors)
end

--- Show enter animation on monitors
--
-- Displays a welcome animation on a door's monitor, gradually revealing the user's name.
-- After the animation completes, restores the monitor to its normal state.
--
---@param door table Door configuration with monitor peripheral
---@param name string Name to display in the welcome message
---@param delay number Total animation duration in seconds
---@usage HardwareManager.showEnterAnimationMonitor(door, "Player", 1.0)
function HardwareManager.showEnterAnimationMonitor(door, name, delay)
    if not door or not door.monitor then return end
    
    local mon = peripheral.wrap(door.monitor)
    if not mon then return end
    
    local w, h = mon.getSize()
    local colors = HardwareManager.MONITOR_COLORS
    local steps = math.min(10, math.floor(delay / 0.1))
    local stepDelay = delay / steps
    
    for i = 1, steps do
        mon.setBackgroundColor(colors.background)
        mon.clear()
        
        mon.setTextColor(colors.success)
        local barLen = math.floor(w * (1 - i / steps))
        if barLen > 0 then
            mon.setCursorPos(1, 1)
            mon.write(string.rep("=", barLen))
            mon.setCursorPos(w - barLen + 1, h)
            mon.write(string.rep("=", barLen))
        end
        
        centerTextOnMonitor(mon, math.floor(h / 2) - 1, "Welcome,")
        mon.setTextColor(colors.accent)
        centerTextOnMonitor(mon, math.floor(h / 2), name .. "!")
        
        sleep(stepDelay)
    end
    
    -- Restore to normal state
    HardwareManager.updateDoorMonitor(door)
end

--- Show access denied animation on monitor
--
-- Displays a flashing "ACCESS DENIED" message on a door's monitor with a custom reason.
-- The message flashes before restoring the monitor to its normal state.
--
---@param door table Door configuration with monitor peripheral
---@param reason string|nil Reason for denial (defaults to "ACCESS DENIED")
---@usage HardwareManager.showAccessDeniedMonitor(door, "Card Expired")
function HardwareManager.showAccessDeniedMonitor(door, reason)
    if not door or not door.monitor then return end
    
    local mon = peripheral.wrap(door.monitor)
    if not mon then return end
    
    local w, h = mon.getSize()
    local colors = HardwareManager.MONITOR_COLORS
    reason = reason or "ACCESS DENIED"
    
    -- Flash animation
    for i = 1, 3 do
        mon.setBackgroundColor(colors.error)
        mon.clear()
        mon.setTextColor(colors.text)
        centerTextOnMonitor(mon, math.floor(h / 2), reason)
        sleep(0.3)
        
        mon.setBackgroundColor(colors.background)
        mon.clear()
        sleep(0.2)
    end
    
    -- Restore to normal state
    HardwareManager.updateDoorMonitor(door)
end

--- Show enter animation on signs
--
-- Displays a welcome animation on a door's sign, gradually revealing the user's name.
-- After the animation completes, restores the sign to its normal state.
--
---@param door table Door configuration with sign peripheral
---@param name string Name to display in the welcome message
---@param delay number Total animation duration in seconds
---@usage HardwareManager.showEnterAnimation(door, "Player", 1.0)
function HardwareManager.showEnterAnimation(door, name, delay)
    -- Handle sign animation
    if door and door.sign then
        local startBars = 15
        local signDelay = delay / startBars - .05
        for i = startBars, 1, -1 do
            peripheral.call(door.sign, "setSignText", string.rep("=", i), "Welcome,", name .. "!", string.rep("=", i))
            sleep(signDelay)
        end
        -- Restore sign to normal state
        HardwareManager.updateDoorSign(door)
    end
    
    -- Also trigger monitor animation if present (non-blocking for signs)
    if door and door.monitor then
        -- Note: Parallel animation could be done here, but for simplicity we keep it sequential
        -- The sign animation takes priority
    end
end

--- Show access denied message on door sign
--
-- Displays a flashing "ACCESS DENIED" message on a door's sign with a custom reason.
-- The message flashes 3 times before restoring the sign to its normal state.
-- Also shows on monitor if present.
--
---@param door table Door configuration with sign peripheral
---@param reason string|nil Reason for denial (defaults to "ACCESS DENIED")
---@usage HardwareManager.showAccessDenied(door, "Card Expired")
function HardwareManager.showAccessDenied(door, reason)
    reason = reason or "ACCESS DENIED"
    
    -- Handle sign
    if door and door.sign then
        -- Flash red warning message
        for i = 1, 3 do
            peripheral.call(door.sign, "setSignText", "XXXXXXXXXXXXX", reason, "XXXXXXXXXXXXX", "")
            sleep(0.5)
            peripheral.call(door.sign, "setSignText", "", "", "", "")
            sleep(0.3)
        end
        -- Restore sign to normal state
        HardwareManager.updateDoorSign(door)
    end
    
    -- Handle monitor
    if door and door.monitor then
        HardwareManager.showAccessDeniedMonitor(door, reason)
    end
end

--- Open door with combined display animation
--
-- Opens a door, optionally displays a welcome animation on all displays, then automatically closes it.
-- The door will remain open for the specified duration or the door's default open time.
-- Works with both signs and monitors.
--
---@param door table Door configuration
---@param name string|nil User name to display in animation (nil to skip animation)
---@param openTime number|nil Time in seconds to keep door open (defaults to door.openTime or DEFAULT_OPEN_TIME)
---@usage HardwareManager.openDoorWithDisplay(door, "Player", 3.0)
function HardwareManager.openDoorWithDisplay(door, name, openTime)
    local SecurityCore = require("tac.core.security")
    openTime = openTime or door.openTime or SecurityCore.DEFAULT_OPEN_TIME
    
    HardwareManager.controlDoor(door, true)

    if name then
        -- Prefer monitor animation if available, else use sign
        if door.monitor then
            HardwareManager.showEnterAnimationMonitor(door, name, openTime)
        elseif door.sign then
            HardwareManager.showEnterAnimation(door, name, openTime)
        else
            sleep(openTime)
        end
    else
        sleep(openTime)
    end

    HardwareManager.controlDoor(door, false)
end

--- Control door relay (open/close)
--
-- Sets the redstone output state for all sides of a door's relay peripheral.
-- Used to physically open or close doors connected via redstone.
--
---@param door table Door configuration with fields:
--   - relay (string): Peripheral name of the redstone relay
---@param state boolean true to activate relay (open door), false to deactivate (close door)
---@usage HardwareManager.controlDoor(door, true)
function HardwareManager.controlDoor(door, state)
    if door and door.relay then
        for _, side in pairs(redstone.getSides()) do
            peripheral.call(door.relay, "setOutput", side, state)
        end
    end
end

--- Open door for specified time
--
-- Opens a door, optionally displays a welcome animation, then automatically closes it.
-- The door will remain open for the specified duration or the door's default open time.
-- Supports both signs and monitors for display.
--
---@param door table Door configuration
---@param name string|nil User name to display in animation (nil to skip animation)
---@param openTime number|nil Time in seconds to keep door open (defaults to door.openTime or DEFAULT_OPEN_TIME)
---@usage HardwareManager.openDoor(door, "Player", 3.0)
function HardwareManager.openDoor(door, name, openTime)
    -- Use the combined display function
    HardwareManager.openDoorWithDisplay(door, name, openTime)
end

return HardwareManager