--[[
    TAC Core Security System
    
    Handles tag matching, access control logic, and hierarchical permissions.
    Provides utilities for generating random tokens, parsing tags, and checking
    access permissions with support for hierarchical and wildcard tags.
    
    @module tac.core.security
    @author Twijn
    @version 1.0.1
    @license MIT
    
    @example
    -- In your extension:
    function MyExtension.init(tac)
        local Security = require("tac.core.security")
        
        -- Check if a card has access to a door
        local hasAccess, reason = Security.checkAccess(
            {"tenant.1", "vip"},  -- Card tags
            {"tenant.1"}           -- Required tags
        )
        
        -- Parse tag strings
        local tags = Security.parseTags("tenant.1, vip, admin.*")
        -- Returns: {"tenant.1", "vip", "admin.*"}
        
        -- Check wildcard tags
        if Security.tagMatch("admin.view", {"admin.*"}) then
            print("Has admin access")
        end
    end
]]

local SecurityCore = {}

-- Default configuration
SecurityCore.DEFAULT_OPEN_TIME = 1.5

--- Generate a random string of given length
--
-- Creates a cryptographically random string using alphanumeric characters.
-- Useful for generating unique card IDs, tokens, or session identifiers.
--
---@param length number Optional length of string (default: 128)
---@return string Random alphanumeric string
---@usage local cardId = SecurityCore.randomString(16)
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
--
-- Shortens a card ID to first 9 characters followed by "..." for readable logging.
--
---@param cardId string The full card ID to truncate
---@return string Truncated card ID (e.g., "abc123def...")
---@usage print("Card: " .. SecurityCore.truncateCardId(card.id))
function SecurityCore.truncateCardId(cardId)
  if not cardId then return "nil" end
  return cardId:sub(1, 9) .. "..."
end

--- Parse tags from string
--
-- Converts a comma or space-separated string of tags into an array.
-- Useful for parsing user input from forms or configuration files.
--
---@param str string Comma or space-separated tags (e.g., "tenant.1, admin staff")
---@return table Array of individual tag strings
---@usage local tags = SecurityCore.parseTags("tenant.1, admin")
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

--- Expand a tag into its hierarchy
--
-- Splits a hierarchical tag into all its parent levels. For example,
-- "tenant.1.a" expands to {"tenant", "tenant.1", "tenant.1.a"}.
-- This allows a specific tag to satisfy requirements for any parent level.
--
---@param tag string Dot-separated hierarchical tag
---@return table Array of tags from most general to most specific
---@usage local hierarchy = SecurityCore.expandTagHierarchy("tenant.1.a")
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
--
-- Processes an array of tags, expanding each hierarchical tag into its parent
-- levels. Wildcard tags (ending with ".*") are preserved as-is without expansion.
-- Removes duplicates in the resulting array.
--
---@param tags table Array of tag strings
---@return table Array of expanded tags with all parent levels included
---@usage local expanded = SecurityCore.expandCardTags({"tenant.1.a", "admin"})
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
--
-- Determines if a single card tag grants access for a door requirement.
-- Supports exact matches, hierarchical matching (card "tenant.1.a" satisfies door "tenant"),
-- and wildcard card tags (card "tenant.*" satisfies any door tag starting with "tenant").
--
---@param cardTag string Tag present on the card (may include ".*" wildcard)
---@param doorTag string Tag required by the door
---@return boolean True if the card tag satisfies the door requirement
---@usage if SecurityCore.tagMatches("tenant.1", "tenant") then print("Access granted") end
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
--
-- Main access control function that determines if a card's tags grant access to a door.
-- Automatically expands card tags to include parent hierarchies, then checks if any
-- card tag satisfies any door requirement. Special case: door tag "*" grants access
-- to any card with at least one tag.
--
---@param cardTags table Array of tag strings on the card
---@param doorTags table Array of tag strings required by the door
---@return boolean Whether access is granted
---@return string Match reason showing which card tag satisfied which door requirement
---@usage local granted, reason = SecurityCore.checkAccess({"tenant.1.a"}, {"tenant"})
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