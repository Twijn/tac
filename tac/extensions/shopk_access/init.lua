-- ShopK Access Extension Module Entry Point
-- This provides access to all the submodules

local shopk_access = {}

-- Export all modules
shopk_access.utils = require("tac.extensions.shopk_access.utils")
shopk_access.config = require("tac.extensions.shopk_access.config")
shopk_access.slots = require("tac.extensions.shopk_access.slots")
shopk_access.ui = require("tac.extensions.shopk_access.ui")
shopk_access.shop = require("tac.extensions.shopk_access.shop")
shopk_access.commands = require("tac.extensions.shopk_access.commands")

return shopk_access