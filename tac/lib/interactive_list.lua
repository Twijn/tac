--[[
    TAC Interactive List Library
    
    Provides an interactive list UI with keyboard navigation for browsing items.
    Supports arrow key navigation, detail view, and customizable rendering.
    
    @module tac.lib.interactive_list
    @author Twijn
    @version 1.0.0
    
    @example
    local interactiveList = require("tac.lib.interactive_list")
    
    -- Simple list
    local items = {
        {name = "Item 1", description = "First item"},
        {name = "Item 2", description = "Second item"}
    }
    
    local selected = interactiveList.show({
        title = "Select an Item",
        items = items,
        formatItem = function(item) return item.name end,
        formatDetails = function(item)
            return {
                "Name: " .. item.name,
                "Description: " .. item.description
            }
        end
    })
]]

local interactiveList = {}

--- Show an interactive list with navigation
-- @param options table - Configuration options
-- @return table|nil - Selected item or nil if cancelled
function interactiveList.show(options)
    local title = options.title or "Select Item"
    local items = options.items or {}
    local formatItem = options.formatItem or function(item) return tostring(item) end
    local formatDetails = options.formatDetails or nil
    local allowMultiSelect = options.allowMultiSelect or false
    local showHelp = options.showHelp ~= false -- Default true
    
    if #items == 0 then
        term.setTextColor(colors.yellow)
        print("No items to display")
        term.setTextColor(colors.white)
        return nil
    end
    
    local selectedIndex = 1
    local scrollOffset = 0
    local showingDetails = false
    local selectedItems = {}
    
    -- Get terminal size
    local function getScreenDimensions()
        local w, h = term.getSize()
        return w, h
    end
    
    -- Calculate how many items fit on screen
    local function getMaxVisibleItems()
        local _, h = getScreenDimensions()
        local headerLines = 3 -- Title + separator + help
        local footerLines = showHelp and 3 or 1 -- Help text
        return h - headerLines - footerLines
    end
    
    -- Render the list
    local function render()
        term.clear()
        term.setCursorPos(1, 1)
        local w, h = getScreenDimensions()
        
        if not showingDetails then
            -- List view
            term.setTextColor(colors.yellow)
            print(title)
            term.setTextColor(colors.gray)
            print(string.rep("-", w))
            term.setTextColor(colors.white)
            
            local maxVisible = getMaxVisibleItems()
            
            -- Adjust scroll if needed
            if selectedIndex < scrollOffset + 1 then
                scrollOffset = selectedIndex - 1
            elseif selectedIndex > scrollOffset + maxVisible then
                scrollOffset = selectedIndex - maxVisible
            end
            
            -- Render visible items
            for i = 1, maxVisible do
                local itemIndex = scrollOffset + i
                if itemIndex <= #items then
                    local item = items[itemIndex]
                    local itemText = formatItem(item)
                    
                    -- Highlight selected item
                    if itemIndex == selectedIndex then
                        term.setBackgroundColor(colors.gray)
                        term.setTextColor(colors.white)
                    else
                        term.setBackgroundColor(colors.black)
                        term.setTextColor(colors.white)
                    end
                    
                    -- Show selection marker for multi-select
                    local prefix = ""
                    if allowMultiSelect then
                        prefix = selectedItems[itemIndex] and "[x] " or "[ ] "
                    end
                    
                    -- Truncate if too long
                    local displayText = prefix .. itemText
                    if #displayText > w then
                        displayText = displayText:sub(1, w - 3) .. "..."
                    end
                    
                    print(displayText .. string.rep(" ", w - #displayText))
                    
                    term.setBackgroundColor(colors.black)
                end
            end
            
            -- Show help
            if showHelp then
                term.setCursorPos(1, h - 2)
                term.setTextColor(colors.gray)
                print(string.rep("-", w))
                term.setTextColor(colors.lightGray)
                if allowMultiSelect then
                    print("↑↓: Navigate | Space: Select | →: Details | Enter: Confirm | Q: Cancel")
                else
                    print("↑↓: Navigate | →: Details | Enter: Select | Q: Cancel")
                end
            end
            
            -- Show scroll indicator
            if #items > maxVisible then
                term.setCursorPos(w, 4)
                term.setTextColor(colors.gray)
                if scrollOffset > 0 then
                    print("↑")
                end
                term.setCursorPos(w, h - 3)
                if scrollOffset + maxVisible < #items then
                    print("↓")
                end
            end
            
        else
            -- Details view
            local item = items[selectedIndex]
            
            term.setTextColor(colors.yellow)
            print(title .. " - Details")
            term.setTextColor(colors.gray)
            print(string.rep("-", w))
            term.setTextColor(colors.white)
            
            if formatDetails then
                local details = formatDetails(item)
                if type(details) == "table" then
                    for _, line in ipairs(details) do
                        print(line)
                    end
                else
                    print(tostring(details))
                end
            else
                -- Default detail view: pretty-print the item
                print("Item: " .. formatItem(item))
                if type(item) == "table" then
                    for k, v in pairs(item) do
                        if k ~= "name" and k ~= "title" then
                            print("  " .. k .. ": " .. tostring(v))
                        end
                    end
                end
            end
            
            -- Help text
            term.setCursorPos(1, h - 1)
            term.setTextColor(colors.gray)
            print(string.rep("-", w))
            term.setTextColor(colors.lightGray)
            print("←: Back to list | Q: Cancel")
        end
        
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
    end
    
    -- Main loop
    while true do
        render()
        
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            if not showingDetails and selectedIndex > 1 then
                selectedIndex = selectedIndex - 1
            end
        elseif key == keys.down then
            if not showingDetails and selectedIndex < #items then
                selectedIndex = selectedIndex + 1
            end
        elseif key == keys.right then
            if not showingDetails and formatDetails then
                showingDetails = true
            end
        elseif key == keys.left then
            if showingDetails then
                showingDetails = false
            end
        elseif key == keys.enter then
            if allowMultiSelect then
                -- Return all selected items
                local result = {}
                for idx, _ in pairs(selectedItems) do
                    table.insert(result, items[idx])
                end
                return result
            else
                -- Return single selected item
                return items[selectedIndex]
            end
        elseif key == keys.space then
            if allowMultiSelect and not showingDetails then
                -- Toggle selection
                selectedItems[selectedIndex] = not selectedItems[selectedIndex]
            end
        elseif key == keys.q then
            return nil
        end
    end
end

--- Show a simple menu with text options
-- @param title string - Menu title
-- @param options table - Array of option strings
-- @return string|nil - Selected option or nil if cancelled
function interactiveList.menu(title, options)
    local items = {}
    for _, opt in ipairs(options) do
        table.insert(items, {text = opt})
    end
    
    local result = interactiveList.show({
        title = title,
        items = items,
        formatItem = function(item) return item.text end,
        formatDetails = nil,
        showHelp = true
    })
    
    return result and result.text or nil
end

return interactiveList
