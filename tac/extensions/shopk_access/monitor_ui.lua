--[[
    ShopK Access Extension - Monitor UI
    
    Provides interactive monitor-based UI for card purchases and renewals.
    Allows users without terminal access to make choices and see transaction progress.
    
    @module tac.extensions.shopk_access.monitor_ui
    @author Twijn
]]

local monitor_ui = {}

-- UI state
local activeMonitor = nil
local activeSession = nil
local touchListener = nil
local isInUse = false  -- Flag to indicate if monitor is showing interactive UI
local clearTimer = nil  -- Timer for clearing success/error screens

--- Check if monitor is currently in use (showing interactive UI)
-- @return boolean - true if monitor is showing interactive screens
function monitor_ui.isInUse()
    return isInUse
end

--- Lock the monitor (set isInUse flag) to prevent shop_monitor updates
-- This should be called at the start of a transaction flow
function monitor_ui.lock()
    isInUse = true
end

--- Unlock the monitor (clear isInUse flag) to allow shop_monitor updates
-- Note: clearSession() also unlocks
function monitor_ui.unlock()
    isInUse = false
end

--- Initialize monitor UI
-- @param tac table - TAC instance
-- @param monitorSide string - side where monitor is attached (optional, will auto-detect)
-- @return boolean - success status
function monitor_ui.init(tac, monitorSide)
    -- Try to find monitor
    if monitorSide then
        if peripheral.getType(monitorSide) == "monitor" then
            activeMonitor = peripheral.wrap(monitorSide)
        end
    else
        -- Auto-detect monitor
        for _, side in ipairs(peripheral.getNames()) do
            if peripheral.getType(side) == "monitor" then
                activeMonitor = peripheral.wrap(side)
                term.setTextColor(colors.cyan)
                print("Monitor UI: Found monitor on " .. side)
                term.setTextColor(colors.white)
                break
            end
        end
    end
    
    if not activeMonitor then
        term.setTextColor(colors.yellow)
        print("Monitor UI: No monitor found, UI features disabled")
        term.setTextColor(colors.white)
        return false
    end
    
    -- Test monitor
    activeMonitor.setTextScale(1)
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.clear()
    
    return true
end

--- Clear monitor and show default screen
local function showDefaultScreen()
    if not activeMonitor then return end
    
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.clear()
    activeMonitor.setCursorPos(1, 1)
    activeMonitor.setTextColor(colors.cyan)
    activeMonitor.write("ShopK Access System")
    activeMonitor.setCursorPos(1, 2)
    activeMonitor.setTextColor(colors.white)
    activeMonitor.write("Ready for transactions...")
end

--- Draw a button on the monitor
-- @param x number - X position
-- @param y number - Y position
-- @param width number - button width
-- @param text string - button text
-- @param bgColor number - background color
-- @param textColor number - text color
-- @return table - button bounds {x1, y1, x2, y2}
local function drawButton(x, y, width, text, bgColor, textColor)
    if not activeMonitor then return nil end
    
    activeMonitor.setBackgroundColor(bgColor)
    activeMonitor.setTextColor(textColor)
    
    -- Draw button background
    for i = 0, 2 do
        activeMonitor.setCursorPos(x, y + i)
        activeMonitor.write(string.rep(" ", width))
    end
    
    -- Draw text centered
    local textX = x + math.floor((width - #text) / 2)
    activeMonitor.setCursorPos(textX, y + 1)
    activeMonitor.write(text)
    
    -- Reset colors
    activeMonitor.setBackgroundColor(colors.black)
    
    return {
        x1 = x,
        y1 = y,
        x2 = x + width - 1,
        y2 = y + 2
    }
end

--- Check if touch is within button bounds
-- @param touch table - touch event {x, y}
-- @param button table - button bounds
-- @return boolean
local function isTouchInButton(touch, button)
    return touch.x >= button.x1 and touch.x <= button.x2 and
           touch.y >= button.y1 and touch.y <= button.y2
end

--- Show renewal choice screen
-- @param data table - transaction and card data
-- @param callback function - callback(choice) where choice is "data" or "nfc" or nil for cancel
function monitor_ui.showRenewalChoice(data, callback)
    if not activeMonitor then
        -- Fall back to terminal prompt
        term.setTextColor(colors.yellow)
        print("No monitor available, using terminal prompt")
        term.setTextColor(colors.white)
        return false
    end
    
    isInUse = true  -- Mark monitor as in use
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.clear()
    
    -- Header
    activeMonitor.setCursorPos(1, 1)
    activeMonitor.setBackgroundColor(colors.blue)
    local width = select(1, activeMonitor.getSize())
    activeMonitor.write(string.rep(" ", width))
    activeMonitor.setCursorPos(2, 1)
    activeMonitor.setTextColor(colors.white)
    activeMonitor.write("CARD RENEWAL")
    
    -- Transaction details
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.setCursorPos(2, 3)
    activeMonitor.setTextColor(colors.cyan)
    activeMonitor.write("Player: " .. data.username)
    
    activeMonitor.setCursorPos(2, 4)
    activeMonitor.write("Access: " .. data.accessTag)
    
    activeMonitor.setCursorPos(2, 5)
    activeMonitor.write("Duration: " .. data.tier.duration .. " days")
    
    activeMonitor.setCursorPos(2, 6)
    activeMonitor.write("Amount: " .. data.transaction.value .. " KRO")
    
    -- Instructions
    activeMonitor.setCursorPos(2, 8)
    activeMonitor.setTextColor(colors.white)
    activeMonitor.write("Choose renewal option:")
    
    activeMonitor.setCursorPos(2, 9)
    activeMonitor.setTextColor(colors.lightGray)
    activeMonitor.write("Touch a button below to select")
    
    -- Draw buttons
    local button1 = drawButton(2, 11, 20, "Renew Data Only", colors.green, colors.white)
    local button2 = drawButton(24, 11, 20, "Write New Card", colors.orange, colors.white)
    local cancelButton = drawButton(2, 15, 15, "Cancel", colors.red, colors.white)
    
    -- Add descriptions below buttons
    activeMonitor.setTextColor(colors.gray)
    activeMonitor.setCursorPos(2, 14)
    activeMonitor.write("(Recommended)")
    activeMonitor.setCursorPos(24, 14)
    activeMonitor.write("(Requires NFC card)")
    
    -- Wait for touch event
    activeSession = {
        type = "renewal_choice",
        data = data,
        callback = callback,
        buttons = {
            {bounds = button1, action = "data"},
            {bounds = button2, action = "nfc"},
            {bounds = cancelButton, action = "cancel"}
        }
    }
    
    return true
end

--- Show new purchase choice screen
-- @param data table - transaction and purchase data
-- @param callback function - callback(choice) where choice is "write" or nil for cancel
function monitor_ui.showPurchaseChoice(data, callback)
    if not activeMonitor then
        return false
    end
    
    isInUse = true  -- Mark monitor as in use
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.clear()
    
    -- Header
    activeMonitor.setCursorPos(1, 1)
    activeMonitor.setBackgroundColor(colors.green)
    local width = select(1, activeMonitor.getSize())
    activeMonitor.write(string.rep(" ", width))
    activeMonitor.setCursorPos(2, 1)
    activeMonitor.setTextColor(colors.white)
    activeMonitor.write("NEW ACCESS PURCHASE")
    
    -- Transaction details
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.setCursorPos(2, 3)
    activeMonitor.setTextColor(colors.cyan)
    activeMonitor.write("Player: " .. data.username)
    
    activeMonitor.setCursorPos(2, 4)
    activeMonitor.write("Access: " .. data.slot)
    
    activeMonitor.setCursorPos(2, 5)
    activeMonitor.write("Duration: " .. data.tier.duration .. " days")
    
    activeMonitor.setCursorPos(2, 6)
    activeMonitor.write("Amount: " .. data.transaction.value .. " KRO")
    
    -- Instructions
    activeMonitor.setCursorPos(2, 8)
    activeMonitor.setTextColor(colors.white)
    activeMonitor.write("Ready to write NFC card")
    
    activeMonitor.setCursorPos(2, 9)
    activeMonitor.setTextColor(colors.lightGray)
    activeMonitor.write("Touch 'Continue' to proceed")
    
    -- Draw buttons
    local continueButton = drawButton(2, 11, 20, "Continue", colors.green, colors.white)
    local cancelButton = drawButton(24, 11, 15, "Cancel", colors.red, colors.white)
    
    -- Wait for touch event
    activeSession = {
        type = "purchase_choice",
        data = data,
        callback = callback,
        buttons = {
            {bounds = continueButton, action = "write"},
            {bounds = cancelButton, action = "cancel"}
        }
    }
    
    return true
end

--- Show NFC card writing progress screen
-- @param data table - card writing data
function monitor_ui.showNFCWriting(data)
    if not activeMonitor then return end
    
    isInUse = true  -- Keep monitor marked as in use during NFC writing
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.clear()
    
    -- Header
    activeMonitor.setCursorPos(1, 1)
    activeMonitor.setBackgroundColor(colors.yellow)
    local width = select(1, activeMonitor.getSize())
    activeMonitor.write(string.rep(" ", width))
    activeMonitor.setCursorPos(2, 1)
    activeMonitor.setTextColor(colors.black)
    activeMonitor.write("NFC CARD WRITING")
    
    -- Instructions
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.setCursorPos(2, 3)
    activeMonitor.setTextColor(colors.white)
    activeMonitor.write("Please place a blank NFC card")
    activeMonitor.setCursorPos(2, 4)
    activeMonitor.write("on the card reader...")
    
    -- Show card details
    activeMonitor.setCursorPos(2, 6)
    activeMonitor.setTextColor(colors.cyan)
    activeMonitor.write("Player: " .. (data.username or "N/A"))
    
    if data.cardId then
        activeMonitor.setCursorPos(2, 7)
        activeMonitor.write("Card ID: " .. string.sub(data.cardId, 1, 16) .. "...")
    end
    
    -- Animated waiting indicator
    activeMonitor.setCursorPos(2, 9)
    activeMonitor.setTextColor(colors.yellow)
    activeMonitor.write("Waiting for card...")
    
    activeSession = {
        type = "nfc_writing",
        data = data
    }
end

--- Show success screen
-- @param message string - success message
-- @param details table - optional details to display
function monitor_ui.showSuccess(message, details)
    if not activeMonitor then return end
    
    isInUse = true  -- Keep monitor locked during success screen
    
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.clear()
    
    -- Header
    activeMonitor.setCursorPos(1, 1)
    activeMonitor.setBackgroundColor(colors.green)
    local width = select(1, activeMonitor.getSize())
    activeMonitor.write(string.rep(" ", width))
    activeMonitor.setCursorPos(2, 1)
    activeMonitor.setTextColor(colors.white)
    activeMonitor.write("SUCCESS!")
    
    -- Message
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.setCursorPos(2, 3)
    activeMonitor.setTextColor(colors.lime)
    activeMonitor.write(message)
    
    -- Details
    if details then
        local line = 5
        for key, value in pairs(details) do
            activeMonitor.setCursorPos(2, line)
            activeMonitor.setTextColor(colors.cyan)
            activeMonitor.write(key .. ": ")
            activeMonitor.setTextColor(colors.white)
            activeMonitor.write(tostring(value))
            line = line + 1
        end
    end
    
    -- Clear session immediately
    activeSession = nil
    
    -- Schedule clearing of screen and flag reset after delay
    -- This allows the success message to stay visible for 5 seconds
    -- before the monitor can be used for other purposes again
    if clearTimer then os.cancelTimer(clearTimer) end
    clearTimer = os.startTimer(5)
end

--- Show error screen
-- @param message string - error message
function monitor_ui.showError(message)
    if not activeMonitor then return end
    
    isInUse = true  -- Keep monitor locked during error screen
    
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.clear()
    
    -- Header
    activeMonitor.setCursorPos(1, 1)
    activeMonitor.setBackgroundColor(colors.red)
    local width = select(1, activeMonitor.getSize())
    activeMonitor.write(string.rep(" ", width))
    activeMonitor.setCursorPos(2, 1)
    activeMonitor.setTextColor(colors.white)
    activeMonitor.write("ERROR")
    
    -- Message
    activeMonitor.setBackgroundColor(colors.black)
    activeMonitor.setCursorPos(2, 3)
    activeMonitor.setTextColor(colors.red)
    
    -- Word wrap the message
    local maxWidth = select(1, activeMonitor.getSize()) - 4
    local words = {}
    for word in message:gmatch("%S+") do
        table.insert(words, word)
    end
    
    local line = 3
    local currentLine = ""
    for _, word in ipairs(words) do
        if #currentLine + #word + 1 > maxWidth then
            activeMonitor.setCursorPos(2, line)
            activeMonitor.write(currentLine)
            line = line + 1
            currentLine = word
        else
            if #currentLine > 0 then
                currentLine = currentLine .. " " .. word
            else
                currentLine = word
            end
        end
    end
    if #currentLine > 0 then
        activeMonitor.setCursorPos(2, line)
        activeMonitor.write(currentLine)
    end
    
    -- Clear session immediately
    activeSession = nil
    
    -- Schedule clearing of screen and flag reset after delay
    if clearTimer then os.cancelTimer(clearTimer) end
    clearTimer = os.startTimer(5)
end

--- Handle touch events
-- @param x number - touch X coordinate
-- @param y number - touch Y coordinate
function monitor_ui.handleTouch(x, y)
    if not activeSession or not activeSession.buttons then return end
    
    local touch = {x = x, y = y}
    
    for _, button in ipairs(activeSession.buttons) do
        if isTouchInButton(touch, button.bounds) then
            -- Button pressed
            local callback = activeSession.callback
            local action = button.action
            
            -- Clear session
            activeSession = nil
            
            -- Call callback
            if callback then
                if action == "cancel" then
                    callback(nil)
                else
                    callback(action)
                end
            end
            
            return
        end
    end
end

--- Handle timer events for clearing screens
-- @param timerID number - the timer ID that fired
function monitor_ui.handleTimer(timerID)
    if clearTimer and timerID == clearTimer then
        clearTimer = nil
        monitor_ui.clearSession()
    end
end

--- Start touch listener in background
-- @param tac table - TAC instance
function monitor_ui.startTouchListener(tac)
    if touchListener then return end
    
    touchListener = true
    
    -- Register as background process
    tac.registerBackgroundProcess("monitor_ui_touch", function()
        while touchListener do
            local event, side, x, y = os.pullEvent()
            
            if event == "monitor_touch" then
                -- Check if touch is on our monitor
                if activeMonitor and peripheral.wrap(side) == activeMonitor then
                    monitor_ui.handleTouch(x, y)
                end
            elseif event == "timer" then
                -- Handle timer events for clearing screens
                monitor_ui.handleTimer(side)  -- side contains timerID in timer events
            end
        end
    end)
end

--- Stop touch listener
function monitor_ui.stopTouchListener()
    touchListener = false
end

--- Clear active session and return to default screen
function monitor_ui.clearSession()
    activeSession = nil
    isInUse = false  -- Reset the in-use flag
    showDefaultScreen()
end

--- Check if monitor UI is available
-- @return boolean
function monitor_ui.isAvailable()
    return activeMonitor ~= nil
end

--- Get active monitor
-- @return table - monitor peripheral or nil
function monitor_ui.getMonitor()
    return activeMonitor
end

return monitor_ui
