-- TAC Hardware Manager
-- Handles peripheral detection, door control, and sign updates

local HardwareManager = {}

--- Find peripherals of a specific type
-- @param filter string - peripheral type to search for
-- @return table - array of peripheral names
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
-- @param door table - door configuration
function HardwareManager.updateDoorSign(door)
    if door and door.sign then
        peripheral.call(door.sign, "setSignText", "===============", door.name, "===============", table.concat(door.tags, ","))
    end
end

--- Update all door signs
-- @param doors table - doors storage object
function HardwareManager.updateAllSigns(doors)
    for reader, door in pairs(doors.getAll()) do
        HardwareManager.updateDoorSign(door)
    end
end

--- Show enter animation on monitors
-- @param door table - door configuration
-- @param name string - name to display
-- @param delay number - delay before showing the animation
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
-- @param door table - door configuration
-- @param reason string - reason for denial (optional)
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
-- @param door table - door configuration
-- @param state boolean - true to open, false to close
function HardwareManager.controlDoor(door, state)
    if door and door.relay then
        for _, side in pairs(redstone.getSides()) do
            peripheral.call(door.relay, "setOutput", side, state)
        end
    end
end

--- Open door for specified time
-- @param door table - door configuration
-- @param openTime number - time to keep door open (optional)
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