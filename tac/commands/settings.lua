-- TAC Settings Command Module
-- Handles system settings configuration

local SettingsCommand = {}

function SettingsCommand.create(tac)
    local formui = require("formui")
    local HardwareManager = tac.Hardware or require("tac.core.hardware")
    
    return {
        name = "settings",
        description = "Configure TAC system settings",
        complete = function(args)
            if #args == 1 then
                return {"show", "server-nfc", "server-monitor", "shopk-monitor", "card-expiry", "reset"}
            end
            return {}
        end,
        execute = function(args, d)
            local cmd = (args[1] or "show"):lower()
            
            if cmd == "show" then
                d.mess("=== TAC System Settings ===")
                d.mess("")
                
                local serverNfc = tac.settings.get("server-nfc-reader")
                local serverMonitor = tac.settings.get("server-monitor")
                local shopkMonitor = tac.settings.get("shopk-purchase-monitor")
                local cardExpiry = tac.settings.get("card_expiration_threshold") or 7
                
                d.mess("Server NFC Reader: " .. (serverNfc or "Not configured"))
                d.mess("Server Monitor: " .. (serverMonitor or "Not configured"))
                d.mess("ShopK Purchase Monitor: " .. (shopkMonitor or "Auto-detect"))
                d.mess("Card Expiry Threshold: " .. cardExpiry .. " days")
                d.mess("")
                
                -- Show available peripherals
                d.mess("=== Available Peripherals ===")
                
                local nfcReaders = HardwareManager.findPeripheralsOfType("nfc_reader")
                local monitors = HardwareManager.findPeripheralsOfType("monitor")
                local rfidScanners = HardwareManager.findPeripheralsOfType("rfid_scanner")
                
                d.mess("NFC Readers: " .. (#nfcReaders > 0 and table.concat(nfcReaders, ", ") or "None"))
                d.mess("RFID Scanners: " .. (#rfidScanners > 0 and table.concat(rfidScanners, ", ") or "None"))
                d.mess("Monitors: " .. (#monitors > 0 and table.concat(monitors, ", ") or "None"))
                
            elseif cmd == "server-nfc" then
                local setupForm = formui.new("Configure Server NFC Reader")
                
                -- Find unused NFC readers
                local usedReaders = {}
                for _, doorData in pairs(tac.doors.getAll()) do
                    if doorData.nfcReader then
                        usedReaders[doorData.nfcReader] = true
                    end
                end
                
                local getNfc = setupForm:peripheral("Server NFC Reader", "nfc_reader", function(v, f)
                    local value = f.options[v]
                    if value and usedReaders[value] then
                        return false, "This reader is assigned to a door"
                    end
                    return true
                end, tac.settings.get("server-nfc-reader"))
                
                setupForm:addSubmitCancel()
                
                local result = setupForm:run()
                
                if result then
                    local nfcReader = getNfc()
                    if nfcReader and nfcReader ~= "" then
                        tac.settings.set("server-nfc-reader", nfcReader)
                        d.mess("Server NFC reader set to: " .. nfcReader)
                    else
                        tac.settings.unset("server-nfc-reader")
                        d.mess("Server NFC reader cleared.")
                    end
                else
                    d.mess("Cancelled.")
                end
                
            elseif cmd == "server-monitor" then
                local setupForm = formui.new("Configure Server Monitor")
                
                -- Find unused monitors
                local usedMonitors = {}
                for _, doorData in pairs(tac.doors.getAll()) do
                    if doorData.monitor then
                        usedMonitors[doorData.monitor] = true
                    end
                end
                
                local getMonitor = setupForm:peripheral("Server Monitor", "monitor", function(v, f)
                    local value = f.options[v]
                    if value and usedMonitors[value] then
                        return false, "This monitor is assigned to a door"
                    end
                    return true
                end, tac.settings.get("server-monitor"))
                
                setupForm:addSubmitCancel()
                
                local result = setupForm:run()
                
                if result then
                    local monitor = getMonitor()
                    if monitor and monitor ~= "" then
                        tac.settings.set("server-monitor", monitor)
                        d.mess("Server monitor set to: " .. monitor)
                    else
                        tac.settings.unset("server-monitor")
                        d.mess("Server monitor cleared.")
                    end
                else
                    d.mess("Cancelled.")
                end
                
            elseif cmd == "shopk-monitor" then
                local setupForm = formui.new("Configure ShopK Purchase Monitor")
                
                -- Find unused monitors
                local usedMonitors = {}
                for _, doorData in pairs(tac.doors.getAll()) do
                    if doorData.monitor then
                        usedMonitors[doorData.monitor] = true
                    end
                end
                
                local getMonitor = setupForm:peripheral("ShopK Purchase Monitor", "monitor", function(v, f)
                    local value = f.options[v]
                    if value and usedMonitors[value] then
                        return false, "This monitor is assigned to a door"
                    end
                    return true
                end, tac.settings.get("shopk-purchase-monitor"))
                
                setupForm:addSubmitCancel()
                
                local result = setupForm:run()
                
                if result then
                    local monitor = getMonitor()
                    if monitor and monitor ~= "" then
                        tac.settings.set("shopk-purchase-monitor", monitor)
                        d.mess("ShopK purchase monitor set to: " .. monitor)
                        d.mess("Restart TAC for changes to take effect")
                    else
                        tac.settings.unset("shopk-purchase-monitor")
                        d.mess("ShopK purchase monitor cleared (will auto-detect)")
                        d.mess("Restart TAC for changes to take effect")
                    end
                else
                    d.mess("Cancelled.")
                end
                
            elseif cmd == "card-expiry" then
                local setupForm = formui.new("Configure Card Expiry Threshold")
                
                local currentThreshold = tac.settings.get("card_expiration_threshold") or 7
                
                local getThreshold = setupForm:number("Days until card expiry", function(v)
                    if v < 1 then
                        return false, "Must be at least 1 day"
                    end
                    if v > 365 then
                        return false, "Must be less than 365 days"
                    end
                    return true
                end, currentThreshold)
                
                setupForm:addSubmitCancel()
                
                local result = setupForm:run()
                
                if result then
                    local threshold = getThreshold()
                    tac.settings.set("card_expiration_threshold", threshold)
                    d.mess("Card expiry threshold set to: " .. threshold .. " days")
                    d.mess("Cards will show warnings when they reach this age")
                else
                    d.mess("Cancelled.")
                end
                
            elseif cmd == "reset" then
                d.mess("This will reset all TAC settings. Continue? (y/N)")
                local response = read():lower()
                
                if response == "y" then
                    -- Clear all settings
                    local settings = tac.settings.getAll()
                    for key, _ in pairs(settings) do
                        tac.settings.unset(key)
                    end
                    d.mess("All settings have been reset.")
                else
                    d.mess("Cancelled.")
                end
            else
                d.err("Unknown settings command!")
                d.mess("Usage: settings [show|server-nfc|server-monitor|shopk-monitor|card-expiry|reset]")
            end
        end
    }
end

return SettingsCommand
