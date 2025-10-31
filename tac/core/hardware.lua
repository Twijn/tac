--[[
    TAC Hardware Manager
    
    Handles peripheral detection, door control, and sign updates for the TAC system.
    Provides utilities for finding and interacting with ComputerCraft peripherals.
    
    @module tac.core.hardware
    @author Twijn
    @version 1.0.1
    
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
        
        -- Update a sign after access
        Hardware.updateSign("back", "Access Granted", "Welcome!")
        
        -- Show access animations
        Hardware.showEnterAnimation()
        Hardware.showDenyAnimation()
    end
]]

local HardwareManager = {}

--- Find peripherals of a specific type
--
-- Searches all connected peripherals and returns a list of names matching the specified type.
-- Useful for finding NFC readers, modems, monitors, etc.
--
---@param filter string The peripheral type to search for (e.g., "nfc_reader", "modem", "monitor")
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

--- Update all door signs
--
-- Iterates through all doors and updates their signs with current information.
--
---@param doors table Persistent doors storage object with .getAll() method
---@usage HardwareManager.updateAllSigns(tac.doors)
function HardwareManager.updateAllSigns(doors)
    for reader, door in pairs(doors.getAll()) do
        HardwareManager.updateDoorSign(door)
    end
end

--- Show enter animation on monitors
--
-- Displays a welcome animation on a door's sign, gradually revealing the user's name.
-- After the animation completes, restores the sign to its normal state.
--
---@param door table Door configuration with sign peripheral
---@param name string Name to display in the welcome message
---@param delay number Total animation duration in seconds
---@usage HardwareManager.showEnterAnimation(door, "Player", 1.0)
function HardwareManager.showEnterAnimation(door, name, delay)
    local startBars = 15
    delay = delay / startBars - .05
    for i = startBars, 1, -1 do
        peripheral.call(door.sign, "setSignText", string.rep("=", i), "Welcome,", name .. "!", string.rep("=", i))
        sleep(delay)
    end
    -- Restore sign to normal state
    HardwareManager.updateDoorSign(door)
end

--- Show access denied message on door sign
--
-- Displays a flashing "ACCESS DENIED" message on a door's sign with a custom reason.
-- The message flashes 3 times before restoring the sign to its normal state.
--
---@param door table Door configuration with sign peripheral
---@param reason string|nil Reason for denial (defaults to "ACCESS DENIED")
---@usage HardwareManager.showAccessDenied(door, "Card Expired")
function HardwareManager.showAccessDenied(door, reason)
    if door and door.sign then
        reason = reason or "ACCESS DENIED"
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
--
---@param door table Door configuration
---@param name string|nil User name to display in animation (nil to skip animation)
---@param openTime number|nil Time in seconds to keep door open (defaults to door.openTime or DEFAULT_OPEN_TIME)
---@usage HardwareManager.openDoor(door, "Player", 3.0)
function HardwareManager.openDoor(door, name, openTime)
    local SecurityCore = require("tac.core.security")
    openTime = openTime or door.openTime or SecurityCore.DEFAULT_OPEN_TIME
    
    HardwareManager.controlDoor(door, true)

    if name then
        HardwareManager.showEnterAnimation(door, name, openTime)
    else
        sleep(openTime)
    end

    HardwareManager.controlDoor(door, false)
end

return HardwareManager