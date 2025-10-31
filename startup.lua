-- TAC (Terminal Access Control) - Modular Startup Script
-- This is the new modular version that uses the TAC package system

-- Setup library paths
if not package.path:find("lib") then
  package.path = package.path .. ";lib/?.lua;disk/lib/?.lua;disk/?.lua"
end

-- Add TAC package to path
if not package.path:find("tac") then
  package.path = package.path .. ";tac/?.lua"
end

-- Load the TAC system
local TAC = require("tac.init")

-- Create TAC instance with configuration
local tac = TAC.new({
  -- Add any custom configuration here
  name = "TAC Access Control System",
})

-- Load and register extensions
term.setTextColor(colors.yellow)
print("Loading extensions...")
term.setTextColor(colors.white)
TAC.loadExtensions(tac)

-- Count loaded extensions
local extCount = 0
for _ in pairs(tac.extensions) do
  extCount = extCount + 1
end

if extCount > 0 then
  term.setTextColor(colors.lime)
  print("Extensions loaded: " .. extCount)
  term.setTextColor(colors.white)
end

-- Check for missing extension settings and prompt if needed
if tac.checkExtensionSettings then
  tac.checkExtensionSettings()
end

-- Start the main TAC system with error handling
local success, err = pcall(tac.start)

if not success then
    if err == "shutdown" then
        -- Graceful shutdown requested
        term.setTextColor(colors.lime)
        print("TAC shutdown complete.")
        term.setTextColor(colors.white)
    elseif err == "Terminated" then
        -- CTRL+C pressed
        term.setTextColor(colors.yellow)
        print("Interrupt received, shutting down TAC...")
        term.setTextColor(colors.white)
        if tac.shutdown then
            tac.shutdown()
        end
    else
        -- Other error
        term.setTextColor(colors.red)
        print("TAC startup error: " .. tostring(err))
        term.setTextColor(colors.white)
        if tac.shutdown then
            tac.shutdown()
        end
    end
end