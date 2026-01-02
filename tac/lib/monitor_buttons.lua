--[[
    TAC Monitor Buttons Library
    
    Provides reusable button UI components for monitor-based interfaces.
    Used by server NFC monitor, ShopK access, and other monitor-based UIs.
    
    @module tac.lib.monitor_buttons
    @author Twijn
    @version 1.0.0
]]

local monitor_buttons = {}

-- Default color scheme
monitor_buttons.COLORS = {
    background = colors.black,
    text = colors.white,
    textDim = colors.lightGray,
    title = colors.yellow,
    accent = colors.cyan,
    success = colors.lime,
    warning = colors.orange,
    error = colors.red,
    border = colors.gray,
    buttonBg = colors.blue,
    buttonText = colors.white,
    buttonSuccess = colors.green,
    buttonDanger = colors.red,
    buttonWarning = colors.orange,
    buttonDisabled = colors.gray
}

--- Create a new button manager for a monitor
-- @param monitor table - the monitor peripheral
-- @return table - button manager instance
function monitor_buttons.create(monitor)
    local manager = {
        monitor = monitor,
        buttons = {},
        activeCallback = nil,
        timeoutTimer = nil,
        timeoutCallback = nil
    }
    
    --- Get monitor dimensions
    -- @return number, number - width and height
    function manager.getSize()
        return manager.monitor.getSize()
    end
    
    --- Clear all buttons
    function manager.clearButtons()
        manager.buttons = {}
        manager.activeCallback = nil
        if manager.timeoutTimer then
            os.cancelTimer(manager.timeoutTimer)
            manager.timeoutTimer = nil
        end
        manager.timeoutCallback = nil
    end
    
    --- Clear the monitor
    -- @param bgColor number - optional background color
    function manager.clear(bgColor)
        bgColor = bgColor or monitor_buttons.COLORS.background
        manager.monitor.setBackgroundColor(bgColor)
        manager.monitor.clear()
    end
    
    --- Center text on the monitor
    -- @param y number - line number
    -- @param text string - text to display
    -- @param color number - optional text color
    function manager.centerText(y, text, color)
        local w, h = manager.getSize()
        color = color or monitor_buttons.COLORS.text
        manager.monitor.setTextColor(color)
        local x = math.floor((w - #text) / 2) + 1
        manager.monitor.setCursorPos(x, y)
        manager.monitor.write(text)
    end
    
    --- Draw text at position
    -- @param x number - X position
    -- @param y number - Y position
    -- @param text string - text to display
    -- @param color number - optional text color
    function manager.drawText(x, y, text, color)
        color = color or monitor_buttons.COLORS.text
        manager.monitor.setTextColor(color)
        manager.monitor.setCursorPos(x, y)
        manager.monitor.write(text)
    end
    
    --- Draw a horizontal line
    -- @param y number - line number
    -- @param char string - optional character to use (default "-")
    -- @param color number - optional color
    function manager.drawLine(y, char, color)
        local w, h = manager.getSize()
        char = char or "-"
        color = color or monitor_buttons.COLORS.border
        manager.monitor.setTextColor(color)
        manager.monitor.setCursorPos(1, y)
        manager.monitor.write(string.rep(char, w))
    end
    
    --- Draw a header bar
    -- @param y number - line number
    -- @param text string - header text
    -- @param bgColor number - optional background color
    -- @param textColor number - optional text color
    function manager.drawHeader(y, text, bgColor, textColor)
        local w, h = manager.getSize()
        bgColor = bgColor or monitor_buttons.COLORS.accent
        textColor = textColor or monitor_buttons.COLORS.text
        
        manager.monitor.setBackgroundColor(bgColor)
        manager.monitor.setCursorPos(1, y)
        manager.monitor.write(string.rep(" ", w))
        manager.monitor.setCursorPos(2, y)
        manager.monitor.setTextColor(textColor)
        manager.monitor.write(text)
        manager.monitor.setBackgroundColor(monitor_buttons.COLORS.background)
    end
    
    --- Draw a button and register it
    -- @param x number - X position
    -- @param y number - Y position
    -- @param width number - button width
    -- @param height number - button height (default 3)
    -- @param text string - button text
    -- @param action string - action identifier returned when pressed
    -- @param bgColor number - optional background color
    -- @param textColor number - optional text color
    -- @return table - button bounds {x1, y1, x2, y2}
    function manager.drawButton(x, y, width, height, text, action, bgColor, textColor)
        height = height or 3
        bgColor = bgColor or monitor_buttons.COLORS.buttonBg
        textColor = textColor or monitor_buttons.COLORS.buttonText
        
        manager.monitor.setBackgroundColor(bgColor)
        manager.monitor.setTextColor(textColor)
        
        -- Draw button background
        for i = 0, height - 1 do
            manager.monitor.setCursorPos(x, y + i)
            manager.monitor.write(string.rep(" ", width))
        end
        
        -- Draw text centered vertically and horizontally
        local textY = y + math.floor(height / 2)
        local textX = x + math.floor((width - #text) / 2)
        manager.monitor.setCursorPos(textX, textY)
        manager.monitor.write(text)
        
        -- Reset background
        manager.monitor.setBackgroundColor(monitor_buttons.COLORS.background)
        
        local bounds = {
            x1 = x,
            y1 = y,
            x2 = x + width - 1,
            y2 = y + height - 1
        }
        
        -- Register button
        table.insert(manager.buttons, {
            bounds = bounds,
            action = action
        })
        
        return bounds
    end
    
    --- Draw a simple 3-row button (convenience method)
    -- @param x number - X position
    -- @param y number - Y position
    -- @param width number - button width
    -- @param text string - button text
    -- @param action string - action identifier
    -- @param bgColor number - optional background color
    -- @param textColor number - optional text color
    -- @return table - button bounds
    function manager.addButton(x, y, width, text, action, bgColor, textColor)
        return manager.drawButton(x, y, width, 3, text, action, bgColor, textColor)
    end
    
    --- Check if a touch is within button bounds
    -- @param x number - touch X
    -- @param y number - touch Y
    -- @param button table - button with bounds
    -- @return boolean
    function manager.isTouchInButton(x, y, button)
        return x >= button.bounds.x1 and x <= button.bounds.x2 and
               y >= button.bounds.y1 and y <= button.bounds.y2
    end
    
    --- Set callback for button presses
    -- @param callback function - called with (action) when button pressed
    function manager.setCallback(callback)
        manager.activeCallback = callback
    end
    
    --- Set a timeout for the current screen
    -- @param seconds number - timeout in seconds
    -- @param callback function - called when timeout occurs (optional, uses activeCallback with nil)
    function manager.setTimeout(seconds, callback)
        if manager.timeoutTimer then
            os.cancelTimer(manager.timeoutTimer)
        end
        manager.timeoutTimer = os.startTimer(seconds)
        manager.timeoutCallback = callback
    end
    
    --- Handle a touch event
    -- @param x number - touch X
    -- @param y number - touch Y
    -- @return string|nil - action if button was pressed, nil otherwise
    function manager.handleTouch(x, y)
        for _, button in ipairs(manager.buttons) do
            if manager.isTouchInButton(x, y, button) then
                local action = button.action
                
                if manager.activeCallback then
                    manager.activeCallback(action)
                end
                
                return action
            end
        end
        return nil
    end
    
    --- Handle a timer event
    -- @param timerID number - the timer that fired
    -- @return boolean - true if this was our timeout timer
    function manager.handleTimer(timerID)
        if manager.timeoutTimer and timerID == manager.timeoutTimer then
            manager.timeoutTimer = nil
            
            if manager.timeoutCallback then
                manager.timeoutCallback()
            elseif manager.activeCallback then
                manager.activeCallback(nil)  -- nil indicates timeout/cancel
            end
            
            return true
        end
        return false
    end
    
    --- Show a countdown timer on the monitor
    -- @param y number - line to show countdown on
    -- @param prefix string - text before countdown
    -- @param seconds number - starting seconds
    function manager.showCountdown(y, prefix, seconds)
        local w, h = manager.getSize()
        manager.monitor.setCursorPos(2, y)
        manager.monitor.setTextColor(monitor_buttons.COLORS.warning)
        manager.monitor.write(prefix .. seconds .. "s" .. string.rep(" ", 10))
    end
    
    --- Show a success screen
    -- @param title string - success title
    -- @param message string - success message
    -- @param details table - optional key-value pairs to display
    function manager.showSuccess(title, message, details)
        manager.clear()
        manager.clearButtons()
        
        local w, h = manager.getSize()
        
        manager.drawHeader(1, title or "SUCCESS", monitor_buttons.COLORS.success)
        
        manager.drawText(2, 3, message or "Operation completed", monitor_buttons.COLORS.success)
        
        if details then
            local line = 5
            for key, value in pairs(details) do
                if line < h - 1 then
                    manager.drawText(2, line, key .. ": ", monitor_buttons.COLORS.accent)
                    manager.monitor.setTextColor(monitor_buttons.COLORS.text)
                    manager.monitor.write(tostring(value))
                    line = line + 1
                end
            end
        end
        
        manager.drawLine(h, "=")
    end
    
    --- Show an error screen
    -- @param title string - error title
    -- @param message string - error message
    function manager.showError(title, message)
        manager.clear()
        manager.clearButtons()
        
        local w, h = manager.getSize()
        
        manager.drawHeader(1, title or "ERROR", monitor_buttons.COLORS.error)
        
        -- Word wrap the message
        local maxWidth = w - 4
        local words = {}
        for word in (message or "An error occurred"):gmatch("%S+") do
            table.insert(words, word)
        end
        
        local line = 3
        local currentLine = ""
        manager.monitor.setTextColor(monitor_buttons.COLORS.error)
        
        for _, word in ipairs(words) do
            if #currentLine + #word + 1 > maxWidth then
                manager.monitor.setCursorPos(2, line)
                manager.monitor.write(currentLine)
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
            manager.monitor.setCursorPos(2, line)
            manager.monitor.write(currentLine)
        end
        
        manager.drawLine(h, "=")
    end
    
    --- Check if there are active buttons
    -- @return boolean
    function manager.hasActiveButtons()
        return #manager.buttons > 0
    end
    
    return manager
end

return monitor_buttons
