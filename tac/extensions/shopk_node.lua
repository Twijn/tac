--[[
    ShopK Node Configuration Extension
    
    Allows configuring the ShopK syncNode option for connecting to different
    Krist nodes. Provides UI and commands for managing node settings.
    
    @module tac.extensions.shopk_node
    @author Twijn
    @version 1.0.0
]]

local FormUI = require("formui")

local extension = {
    name = "shopk_node",
    version = "1.0.0",
    description = "Configure ShopK syncNode setting"
}

--- Initialize the extension
-- @param tac table - TAC instance
function extension.init(tac)
    --- Get current syncNode setting
    -- @return string|nil - Current syncNode or nil if not set
    local function getSyncNode()
        return tac.settings.get("shopk_syncNode")
    end
    
    --- Set syncNode setting
    -- @param node string - Node URL or nil to use default
    local function setSyncNode(node)
        if node and node ~= "" then
            tac.settings.set("shopk_syncNode", node)
        else
            tac.settings.unset("shopk_syncNode")
        end
    end
    
    --- Show current node configuration
    -- @param args table - command arguments
    -- @param d table - display interface
    local function showNodeConfig(args, d)
        local currentNode = getSyncNode()
        
        d.mess("=== ShopK Node Configuration ===")
        if currentNode then
            d.mess("Current Node: " .. currentNode)
        else
            d.mess("Current Node: (default)")
        end
        d.mess("")
        d.mess("Usage:")
        d.mess("  node set                  - Interactive node selection")
        d.mess("  node set <url>            - Set node directly")
        d.mess("  node set <preset>         - Set using preset name")
        d.mess("  node reset                - Reset to default node")
        d.mess("")
        d.mess("Available presets:")
        d.mess("  - Official, ReconnectedCC, Default")
        d.mess("  - Sophie, Test")
        d.mess("  - HerrKatze, Katze")
    end
    
    --- Set node using interactive form
    -- @param args table - command arguments
    -- @param d table - display interface
    local function setNodeInteractive(args, d)
        local currentNode = getSyncNode()
        
        -- Available nodes
        local nodes = {
            {name = "Official/Default (ReconnectedCC)", url = "https://kromer.reconnected.cc/api/krist/"},
            {name = "HerrKatze's Test Instance", url = "https://kromer.herrkatze.com/api/krist/"},
            {name = "Sophie's Test Instance", url = "https://kromer.sad.ovh/api/krist/"},
            {name = "Custom", url = ""}
        }
        
        -- Check if a direct URL was provided as argument
        if args[1] then
            local url = args[1]
            
            -- Check if it's a preset name
            for _, node in ipairs(nodes) do
                if node.name:lower():find(url:lower(), 1, true) and node.url ~= "" then
                    setSyncNode(node.url)
                    d.mess("Node set to: " .. node.name .. " (" .. node.url .. ")")
                    d.mess("")
                    d.mess("IMPORTANT: Restart the shop for changes to take effect:")
                    d.mess("  shop stop")
                    d.mess("  shop start")
                    return
                end
            end
            
            -- Otherwise treat it as a custom URL
            if url:match("^https?://") then
                setSyncNode(url)
                d.mess("Node set to: " .. url)
                d.mess("")
                d.mess("IMPORTANT: Restart the shop for changes to take effect:")
                d.mess("  shop stop")
                d.mess("  shop start")
                return
            else
                d.err("Invalid node URL. Must start with http:// or https://")
                d.mess("")
                d.mess("Available preset nodes:")
                for _, node in ipairs(nodes) do
                    if node.url ~= "" then
                        d.mess("  - " .. node.name)
                    end
                end
                return
            end
        end
        
        local form = FormUI.new("ShopK Node Configuration")
        form:label("=== Krist Node Configuration ===")
        form:label("Select a Krist node to use:")
        form:label("")
        
        -- Build list of node names for dropdown
        local nodeNames = {}
        local selectedIndex = 1 -- Default to Official/Default
        for i, node in ipairs(nodes) do
            table.insert(nodeNames, node.name)
            if currentNode and node.url == currentNode then
                selectedIndex = i
            end
        end
        
        form:select("Node", nodeNames, selectedIndex)
        form:label("")
        form:label("Or enter a custom node URL:")
        form:text("Custom URL", (currentNode and selectedIndex == #nodes) and currentNode or "", function(v)
            if #v > 0 then
                form:setValue("Node", "Custom")
            end
            return true
        end)
        
        local result = form:run()
        
        if result then
            local selectedNodeName = result["Node"]
            local customURL = result["Custom URL"]
            
            local newNode
            
            -- Find the selected node
            for _, node in ipairs(nodes) do
                if node.name == selectedNodeName then
                    if node.name == "Custom" then
                        newNode = customURL
                    else
                        newNode = node.url
                    end
                    break
                end
            end
            
            if newNode and newNode ~= "" then
                -- Basic validation
                if not newNode:match("^https?://") then
                    d.err("Invalid node URL. Must start with http:// or https://")
                    return
                end
                
                setSyncNode(newNode)
                d.mess("Node set to: " .. newNode)
                d.mess("")
                d.mess("IMPORTANT: Restart the shop for changes to take effect:")
                d.mess("  shop stop")
                d.mess("  shop start")
            else
                setSyncNode(nil)
                d.mess("Node reset to default")
                d.mess("")
                d.mess("IMPORTANT: Restart the shop for changes to take effect:")
                d.mess("  shop stop")
                d.mess("  shop start")
            end
        else
            d.mess("Node configuration cancelled")
        end
    end
    
    --- Reset to default node
    -- @param args table - command arguments
    -- @param d table - display interface
    local function resetNode(args, d)
        setSyncNode(nil)
        d.mess("Node reset to default")
        d.mess("")
        d.mess("IMPORTANT: Restart the shop for changes to take effect:")
        d.mess("  shop stop")
        d.mess("  shop start")
    end
    
    --- Handle node command
    -- @param args table - command arguments
    -- @param d table - display interface
    local function handleNodeCommand(args, d)
        local subcmd = (args[1] or "status"):lower()
        
        -- Remove the subcommand from args for the handler functions
        table.remove(args, 1)
        
        if subcmd == "status" or subcmd == "show" then
            showNodeConfig(args, d)
        elseif subcmd == "set" or subcmd == "config" then
            setNodeInteractive(args, d)
        elseif subcmd == "reset" or subcmd == "default" then
            resetNode(args, d)
        else
            d.err("Unknown node command! Use: status, set, reset")
        end
    end
    
    --- Get command completions
    -- @param args table - current arguments
    -- @return table - completion options
    local function getCompletions(args)
        if #args == 1 then
            return {"status", "set", "reset", "show", "config", "default"}
        elseif #args == 2 and (args[1]:lower() == "set" or args[1]:lower() == "config") then
            return {"official", "reconnected", "default", "katze", "herrkatze", "sophie", "test"}
        end
        return {}
    end
    
    -- Register the node command
    tac.registerCommand("node", {
        description = "Configure ShopK Krist node",
        complete = getCompletions,
        execute = handleNodeCommand
    })
end

return extension
