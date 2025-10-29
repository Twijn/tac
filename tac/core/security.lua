-- TAC Core Security System
-- Handles tag matching, access control logic, and hierarchical permissions

local SecurityCore = {}

-- Default configuration
SecurityCore.DEFAULT_OPEN_TIME = 1.5

--- Generate a random string of given length
-- @param length number (default 128)
-- @return string
function SecurityCore.randomString(length)
  local chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  local result = ""
  length = length or 128

  for i = 1, length do
    local r = math.random(1, #chars)
    result = result .. chars:sub(r, r)
  end

  return result
end

--- Truncate card ID for display
-- @param cardId string
-- @return string
function SecurityCore.truncateCardId(cardId)
  if not cardId then return "nil" end
  return cardId:sub(1, 9) .. "..."
end

--- Parse tags from string
-- @param str string - comma or space separated tags
-- @return table - array of tags
function SecurityCore.parseTags(str)
    local tags = {}
    if not str or str == "" then return tags end

    -- Replace commas with spaces, then split on whitespace
    str = str:gsub(",", " ")

    for tag in str:gmatch("%S+") do
        table.insert(tags, tag)
    end

    return tags
end

--- Expand a tag into its hierarchy (e.g., "tenant.1.a" -> {"tenant", "tenant.1", "tenant.1.a"})
-- @param tag string
-- @return table - array of hierarchical tags
function SecurityCore.expandTagHierarchy(tag)
    local hierarchy = {}
    local parts = {}
    
    -- Split tag on dots
    for part in tag:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    
    -- Build hierarchy from most general to most specific
    for i = 1, #parts do
        local currentTag = table.concat(parts, ".", 1, i)
        table.insert(hierarchy, currentTag)
    end
    
    return hierarchy
end

--- Expand a list of tags to include all parent tags
-- Wildcard tags (ending with .*) are kept as-is and not expanded
-- @param tags table - array of tags
-- @return table - array of expanded tags
function SecurityCore.expandCardTags(tags)
    local expandedTags = {}
    local seen = {}
    
    for _, tag in ipairs(tags) do
        if tag:sub(-2) == ".*" then
            -- Wildcard tags are kept as-is, not expanded
            if not seen[tag] then
                table.insert(expandedTags, tag)
                seen[tag] = true
            end
        else
            -- Regular tags are expanded into hierarchy
            local hierarchy = SecurityCore.expandTagHierarchy(tag)
            for _, hierarchyTag in ipairs(hierarchy) do
                if not seen[hierarchyTag] then
                    table.insert(expandedTags, hierarchyTag)
                    seen[hierarchyTag] = true
                end
            end
        end
    end
    
    return expandedTags
end

--- Check if a card tag satisfies a door requirement
-- @param cardTag string - tag on the card
-- @param doorTag string - tag required by door
-- @return boolean - true if card tag satisfies door requirement
function SecurityCore.tagMatches(cardTag, doorTag)
    -- Exact match always works
    if cardTag == doorTag then
        return true
    end
    
    -- Handle wildcard card tags (e.g., "tenant.*")
    if cardTag:sub(-2) == ".*" then
        local prefix = cardTag:sub(1, -3)  -- Remove ".*" suffix
        -- Wildcard matches if door tag starts with the prefix
        if doorTag == prefix or doorTag:sub(1, #prefix + 1) == prefix .. "." then
            return true
        end
    end
    
    -- Card tag can satisfy door requirement if card tag is more specific
    -- e.g., card has "tenant.1.a", door wants "tenant" -> YES
    -- e.g., card has "tenant", door wants "tenant.1" -> NO
    if cardTag:sub(1, #doorTag + 1) == doorTag .. "." then
        return true
    end
    
    return false
end

--- Check access permissions for a card against a door
-- @param cardTags table - array of tags on the card
-- @param doorTags table - array of tags required by door
-- @return boolean, string - granted, matchReason
function SecurityCore.checkAccess(cardTags, doorTags)
    local granted = false
    local matchReason = nil
    
    cardTags = cardTags or {}
    doorTags = doorTags or {}
    
    -- Expand card tags to include parent hierarchy
    local expandedCardTags = SecurityCore.expandCardTags(cardTags)
    
    -- Check for wildcard door access
    local tables = require("tables")
    if tables.includes(doorTags, "*") and #cardTags > 0 then
        matchReason = "*"
        granted = true
    else
        -- Check each door requirement against expanded card tags
        for _, doorTag in pairs(doorTags) do
            for _, cardTag in pairs(expandedCardTags) do
                if SecurityCore.tagMatches(cardTag, doorTag) then
                    matchReason = cardTag .. " -> " .. doorTag
                    granted = true
                    break
                end
            end
            if granted then break end
        end
    end
    
    return granted, matchReason
end

return SecurityCore