--[[
    ShopK Access Extension Module Entry Point
    
    Module loader that provides access to all ShopK access submodules.
    This is used internally by the parent shopk_access.lua extension.
    
    @module tac.extensions.shopk_access.init
    @author Twijn
]]

local shopk_access = {}

-- Export all modules
shopk_access.utils = require("tac.extensions.shopk_access.utils")
shopk_access.config = require("tac.extensions.shopk_access.config")
shopk_access.slots = require("tac.extensions.shopk_access.slots")
shopk_access.ui = require("tac.extensions.shopk_access.ui")
shopk_access.shop = require("tac.extensions.shopk_access.shop")
shopk_access.commands = require("tac.extensions.shopk_access.commands")

return shopk_access