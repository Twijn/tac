--[[
    TAC Centralized Identity Management
    
    Provides consistent identity creation, validation, and management APIs.
    An "identity" represents a user with separate NFC and RFID credentials.
    NFC cards are high-security (require physical tap), while RFID badges
    are lower-security (can be scanned at distance).
    
    @module tac.core.identity_manager
    @author Twijn
    @version 2.0.0
    @license MIT
    
    @example
    -- In your extension:
    function MyExtension.init(tac)
        -- Create an identity with both NFC and RFID
        local identity, err = tac.identityManager.createIdentity({
            name = "John Doe",
            tags = {"tenant.1", "vip"},
            nfcEnabled = true,
            rfidEnabled = true,
            maxDistance = 3.0  -- Max RFID scan distance
        })
        
        -- Create a subscription identity
        local subIdentity, err = tac.identityManager.createSubscriptionIdentity({
            username = "player1",
            duration = 30,
            slot = "tenant.premium",
            nfcEnabled = true,
            rfidEnabled = false
        })
        
        -- Renew an identity
        tac.identityManager.renewIdentity("tenant_1_player1", 30)
        
        -- Get identity info
        local info, err = tac.identityManager.getIdentityInfo("tenant_1_player1")
        if info then
            print("Identity expires in " .. (info.timeUntilExpiration / 86400000) .. " days")
        end
        
        -- Regenerate RFID data for an identity
        tac.identityManager.regenerateRfid("tenant_1_player1")
    end
]]

local function create(tacInstance)
    local identityManager = {}
    local tac = tacInstance
    local SecurityCore = require("tac.core.security")

    -- Generate a unique identity ID
    local function generateIdentityId(username, prefix)
        prefix = prefix or ""
        local sanitizedUsername = username and username:gsub("%s+", "_"):lower() or "unknown"
        local timestamp = os.epoch("utc")
        
        if prefix and #prefix > 0 then
            return prefix .. "_" .. sanitizedUsername .. "_" .. timestamp
        else
            return sanitizedUsername .. "_" .. timestamp
        end
    end

    -- Validate identity data
    local function validateIdentityData(identityData)
        if not identityData then
            return false, "Identity data is required"
        end
        
        if not identityData.name or #identityData.name == 0 then
            return false, "Identity name is required"
        end
        
        if not identityData.tags or type(identityData.tags) ~= "table" or #identityData.tags == 0 then
            return false, "At least one tag is required"
        end
        
        -- Validate expiration if present
        if identityData.expiration and type(identityData.expiration) ~= "number" then
            return false, "Expiration must be a number (UTC epoch)"
        end
        
        -- Validate at least one access method is enabled
        if not identityData.nfcEnabled and not identityData.rfidEnabled then
            return false, "At least one access method (NFC or RFID) must be enabled"
        end
        
        return true, nil
    end

    --- Create a new identity with standard validation and logging
    --
    -- Creates an identity with separate NFC and RFID credentials.
    -- NFC data is the primary identifier, RFID data is a separate scannable token.
    --
    ---@param options table Identity creation options:
    --   - id (string, optional): Identity ID (auto-generated if not provided)
    --   - name (string, required): Display name for the identity
    --   - tags (table, required): Array of access tags
    --   - nfcEnabled (boolean, optional): Enable NFC access (default: true)
    --   - rfidEnabled (boolean, optional): Enable RFID access (default: true)
    --   - nfcData (string, optional): NFC card data (auto-generated if not provided)
    --   - rfidData (string, optional): RFID badge data (auto-generated if not provided)
    --   - maxDistance (number, optional): Max RFID scan distance (default: nil = use door setting)
    --   - expiration (number, optional): UTC epoch timestamp when identity expires
    --   - username (string, optional): Username associated with identity (used in ID generation)
    --   - prefix (string, optional): Prefix for auto-generated ID
    --   - createdBy (string, optional): Who/what created the identity (default: "system")
    --   - metadata (table, optional): Additional custom data
    --   - logMessage (string, optional): Custom log message
    ---@return table|nil Identity data object if successful, nil on error
    ---@return string|nil Error message if creation failed
    ---@usage local identity, err = identityManager.createIdentity({name = "John Doe", tags = {"tenant.1"}})
    function identityManager.createIdentity(options)
        local opts = options or {}
        
        -- Generate ID if not provided
        local identityId = opts.id or generateIdentityId(opts.username, opts.prefix)
        
        -- Default to both enabled
        local nfcEnabled = opts.nfcEnabled ~= false
        local rfidEnabled = opts.rfidEnabled ~= false
        
        -- Build identity data
        local identityData = {
            id = identityId,
            name = opts.name or (opts.username and (opts.username .. " Identity") or "Unnamed Identity"),
            tags = opts.tags or {},
            
            -- Access methods
            nfcEnabled = nfcEnabled,
            rfidEnabled = rfidEnabled,
            
            -- Credentials (NFC data is the primary identifier)
            nfcData = opts.nfcData or nil,  -- Will be set when NFC card is written
            rfidData = opts.rfidData or (rfidEnabled and SecurityCore.randomString(64) or nil),
            
            -- Distance settings
            maxDistance = opts.maxDistance,  -- nil = use door setting
            
            -- Timestamps and metadata
            expiration = opts.expiration,
            created = os.epoch("utc"),
            createdBy = opts.createdBy or "system",
            metadata = opts.metadata or {}
        }
        
        -- Validate the identity data
        local isValid, error = validateIdentityData(identityData)
        if not isValid then
            return nil, error
        end
        
        -- Save the identity
        tac.identities.set(identityData.id, identityData)
        
        -- Also create lookup entries for NFC and RFID data
        if identityData.nfcData then
            tac.identityLookup.set("nfc:" .. identityData.nfcData, identityData.id)
        end
        if identityData.rfidData then
            tac.identityLookup.set("rfid:" .. identityData.rfidData, identityData.id)
        end
        
        -- Log the creation
        local accessMethods = {}
        if nfcEnabled then table.insert(accessMethods, "NFC") end
        if rfidEnabled then table.insert(accessMethods, "RFID") end
        
        local logMessage = opts.logMessage or ("Identity created: " .. identityData.name .. " (access: " .. table.concat(accessMethods, ", ") .. ")")
        tac.logger.logAccess("identity_created", {
            identity = identityData,
            message = logMessage
        })
        
        return identityData, nil
    end

    --- Create a subscription identity (with expiration)
    --
    -- Specialized function for creating time-limited subscription identities.
    -- Commonly used by ShopK integration for selling temporary access.
    --
    ---@param options table Subscription identity options:
    --   - username (string, required): Username of the subscriber
    --   - duration (number, required): Subscription duration in days
    --   - slot (string, required): Access level/slot (becomes the identity tag)
    --   - nfcEnabled (boolean, optional): Enable NFC access (default: true)
    --   - rfidEnabled (boolean, optional): Enable RFID access (default: true)
    --   - maxDistance (number, optional): Max RFID scan distance
    --   - createdBy (string, optional): Creator identifier (default: "shopk")
    --   - purchaseValue (number, optional): Purchase price for metadata
    --   - transactionId (string, optional): Transaction ID for metadata
    --   - logMessage (string, optional): Custom log message
    ---@return table|nil Identity data object if successful, nil on error
    ---@return string|nil Error message if creation failed
    ---@usage local identity, err = identityManager.createSubscriptionIdentity({username = "player1", duration = 30, slot = "tenant.1"})
    function identityManager.createSubscriptionIdentity(options)
        local opts = options or {}
        
        if not opts.username then
            return nil, "Username is required for subscription identities"
        end
        
        if not opts.duration then
            return nil, "Duration is required for subscription identities"
        end
        
        if not opts.slot then
            return nil, "Slot/access level is required for subscription identities"
        end
        
        -- Calculate expiration
        local expiration = os.epoch("utc") + (opts.duration * 24 * 60 * 60 * 1000)
        
        -- Create the identity
        local identityOptions = {
            id = opts.slot .. "_" .. opts.username:gsub("%s+", "_"):lower(),
            name = opts.username .. " (" .. opts.slot .. ")",
            tags = {opts.slot},
            nfcEnabled = opts.nfcEnabled ~= false,
            rfidEnabled = opts.rfidEnabled ~= false,
            maxDistance = opts.maxDistance,
            expiration = expiration,
            username = opts.username,
            createdBy = opts.createdBy or "shopk",
            metadata = {
                slot = opts.slot,
                duration = opts.duration,
                purchaseValue = opts.purchaseValue,
                transactionId = opts.transactionId
            },
            logMessage = opts.logMessage or string.format(
                "Subscription identity created: %s for %s expires %s",
                opts.slot,
                opts.username,
                os.date("!%Y-%m-%d %H:%M:%S", expiration / 1000)
            )
        }
        
        return identityManager.createIdentity(identityOptions)
    end

    --- Renew an existing identity
    --
    -- Extends the expiration date of an existing identity by the specified duration.
    -- Updates renewal metadata and logs the renewal event.
    --
    ---@param identityId string ID of the identity to renew
    ---@param additionalDuration number Days to add to current expiration
    ---@param options table Optional renewal options:
    --   - renewedBy (string, optional): Who renewed the identity (default: "system")
    --   - transactionId (string, optional): Transaction ID for metadata
    --   - logMessage (string, optional): Custom log message
    ---@return table|nil Updated identity data if successful, nil on error
    ---@return string|nil Error message if renewal failed
    ---@usage local identity, err = identityManager.renewIdentity("tenant_1_player1", 30, {renewedBy = "admin"})
    function identityManager.renewIdentity(identityId, additionalDuration, options)
        local opts = options or {}
        
        -- Get existing identity
        local existingIdentity = tac.identities.get(identityId)
        if not existingIdentity then
            return nil, "Identity not found: " .. identityId
        end
        
        -- Calculate new expiration
        local currentExpiration = existingIdentity.expiration or os.epoch("utc")
        local newExpiration = currentExpiration + (additionalDuration * 24 * 60 * 60 * 1000)
        
        -- Update the identity
        existingIdentity.expiration = newExpiration
        existingIdentity.renewed = os.epoch("utc")
        existingIdentity.renewedBy = opts.renewedBy or "system"
        
        if opts.transactionId then
            existingIdentity.metadata = existingIdentity.metadata or {}
            existingIdentity.metadata.lastTransactionId = opts.transactionId
        end
        
        -- Save the updated identity
        tac.identities.set(identityId, existingIdentity)
        
        -- Log the renewal
        local logMessage = opts.logMessage or string.format(
            "Identity renewed: %s extended by %d days until %s",
            existingIdentity.name,
            additionalDuration,
            os.date("!%Y-%m-%d %H:%M:%S", newExpiration / 1000)
        )
        
        tac.logger.logAccess("identity_renewed", {
            identity = existingIdentity,
            message = logMessage
        })
        
        return existingIdentity, nil
    end

    --- Regenerate RFID data for an identity
    --
    -- Creates a new RFID token for the identity, invalidating the old one.
    -- Useful if an RFID badge is lost or compromised.
    --
    ---@param identityId string ID of the identity
    ---@return table|nil Updated identity data if successful, nil on error
    ---@return string|nil Error message if regeneration failed
    ---@usage local identity, err = identityManager.regenerateRfid("tenant_1_player1")
    function identityManager.regenerateRfid(identityId)
        local existingIdentity = tac.identities.get(identityId)
        if not existingIdentity then
            return nil, "Identity not found: " .. identityId
        end
        
        if not existingIdentity.rfidEnabled then
            return nil, "RFID is not enabled for this identity"
        end
        
        -- Remove old lookup
        if existingIdentity.rfidData then
            tac.identityLookup.unset("rfid:" .. existingIdentity.rfidData)
        end
        
        -- Generate new RFID data
        local newRfidData = SecurityCore.randomString(64)
        existingIdentity.rfidData = newRfidData
        existingIdentity.rfidRegenerated = os.epoch("utc")
        
        -- Save and create new lookup
        tac.identities.set(identityId, existingIdentity)
        tac.identityLookup.set("rfid:" .. newRfidData, identityId)
        
        tac.logger.logAccess("rfid_regenerated", {
            identity = existingIdentity,
            message = "RFID data regenerated for " .. existingIdentity.name
        })
        
        return existingIdentity, nil
    end

    --- Set NFC data for an identity
    --
    -- Associates NFC card data with an identity. Called after writing an NFC card.
    --
    ---@param identityId string ID of the identity
    ---@param nfcData string The NFC card data
    ---@return table|nil Updated identity data if successful, nil on error
    ---@return string|nil Error message if update failed
    ---@usage local identity, err = identityManager.setNfcData("tenant_1_player1", "abc123...")
    function identityManager.setNfcData(identityId, nfcData)
        local existingIdentity = tac.identities.get(identityId)
        if not existingIdentity then
            return nil, "Identity not found: " .. identityId
        end
        
        if not existingIdentity.nfcEnabled then
            return nil, "NFC is not enabled for this identity"
        end
        
        -- Remove old lookup if exists
        if existingIdentity.nfcData then
            tac.identityLookup.unset("nfc:" .. existingIdentity.nfcData)
        end
        
        -- Set new NFC data
        existingIdentity.nfcData = nfcData
        
        -- Save and create new lookup
        tac.identities.set(identityId, existingIdentity)
        tac.identityLookup.set("nfc:" .. nfcData, identityId)
        
        tac.logger.logAccess("nfc_data_set", {
            identity = existingIdentity,
            message = "NFC data set for " .. existingIdentity.name
        })
        
        return existingIdentity, nil
    end

    --- Look up identity by NFC data
    --
    ---@param nfcData string The NFC card data
    ---@return table|nil Identity data if found, nil otherwise
    ---@usage local identity = identityManager.findByNfc("abc123...")
    function identityManager.findByNfc(nfcData)
        local identityId = tac.identityLookup.get("nfc:" .. nfcData)
        if identityId then
            return tac.identities.get(identityId)
        end
        return nil
    end

    --- Look up identity by RFID data
    --
    ---@param rfidData string The RFID badge data
    ---@return table|nil Identity data if found, nil otherwise
    ---@usage local identity = identityManager.findByRfid("xyz789...")
    function identityManager.findByRfid(rfidData)
        local identityId = tac.identityLookup.get("rfid:" .. rfidData)
        if identityId then
            return tac.identities.get(identityId)
        end
        return nil
    end

    --- Get identity status and info
    --
    -- Retrieves comprehensive information about an identity including expiration status.
    -- Returns structured data with calculated fields like isExpired and timeUntilExpiration.
    --
    ---@param identityId string ID of the identity to query
    ---@return table|nil Identity info object with fields:
    --   - id (string): Identity ID
    --   - name (string): Identity display name
    --   - tags (table): Access tags array
    --   - nfcEnabled (boolean): Whether NFC is enabled
    --   - rfidEnabled (boolean): Whether RFID is enabled
    --   - hasNfcData (boolean): Whether NFC card data is set
    --   - hasRfidData (boolean): Whether RFID badge data is set
    --   - maxDistance (number|nil): Max RFID scan distance
    --   - created (number): Creation timestamp
    --   - createdBy (string): Creator identifier
    --   - isExpired (boolean): Whether identity is currently expired
    --   - timeUntilExpiration (number|nil): Milliseconds until expiration (nil if no expiration)
    --   - expiration (number|nil): Expiration timestamp if set
    --   - metadata (table): Custom metadata
    ---@return string|nil Error message if identity not found
    ---@usage local info, err = identityManager.getIdentityInfo("tenant_1_player1")
    function identityManager.getIdentityInfo(identityId)
        local identity = tac.identities.get(identityId)
        if not identity then
            return nil, "Identity not found"
        end
        
        local info = {
            id = identity.id,
            name = identity.name,
            tags = identity.tags,
            nfcEnabled = identity.nfcEnabled,
            rfidEnabled = identity.rfidEnabled,
            hasNfcData = identity.nfcData ~= nil,
            hasRfidData = identity.rfidData ~= nil,
            maxDistance = identity.maxDistance,
            created = identity.created,
            createdBy = identity.createdBy,
            isExpired = false,
            timeUntilExpiration = nil,
            metadata = identity.metadata or {}
        }
        
        if identity.expiration then
            local now = os.epoch("utc")
            info.expiration = identity.expiration
            info.isExpired = now >= identity.expiration
            info.timeUntilExpiration = identity.expiration - now
        end
        
        return info, nil
    end

    --- Validate identity ID format
    --
    -- Checks if an identity ID meets basic format requirements (non-empty string).
    --
    ---@param identityId any Value to validate as an identity ID
    ---@return boolean True if valid identity ID format
    ---@usage if identityManager.isValidIdentityId(scannedId) then ... end
    function identityManager.isValidIdentityId(identityId)
        return identityId and type(identityId) == "string" and #identityId > 0
    end

    --- Check if identity is valid for a specific access method
    --
    ---@param identityId string Identity ID
    ---@param accessMethod string "nfc" or "rfid"
    ---@return boolean True if identity can use this access method
    ---@return string|nil Error message if not valid
    function identityManager.canAccess(identityId, accessMethod)
        local identity = tac.identities.get(identityId)
        if not identity then
            return false, "Identity not found"
        end
        
        -- Check expiration
        if identity.expiration then
            local now = os.epoch("utc")
            if now >= identity.expiration then
                return false, "Identity expired"
            end
        end
        
        -- Check access method
        if accessMethod == "nfc" then
            if not identity.nfcEnabled then
                return false, "NFC access not enabled"
            end
            if not identity.nfcData then
                return false, "NFC card not configured"
            end
        elseif accessMethod == "rfid" then
            if not identity.rfidEnabled then
                return false, "RFID access not enabled"
            end
            if not identity.rfidData then
                return false, "RFID badge not configured"
            end
        end
        
        return true, nil
    end

    --- Update identity settings (enable/disable access methods, distance, etc.)
    --
    ---@param identityId string Identity ID
    ---@param updates table Fields to update (nfcEnabled, rfidEnabled, maxDistance, tags, name)
    ---@return table|nil Updated identity data if successful, nil on error
    ---@return string|nil Error message if update failed
    function identityManager.updateIdentity(identityId, updates)
        local identity = tac.identities.get(identityId)
        if not identity then
            return nil, "Identity not found: " .. identityId
        end
        
        -- Apply updates
        if updates.name ~= nil then
            identity.name = updates.name
        end
        if updates.tags ~= nil then
            identity.tags = updates.tags
        end
        if updates.nfcEnabled ~= nil then
            identity.nfcEnabled = updates.nfcEnabled
        end
        if updates.rfidEnabled ~= nil then
            identity.rfidEnabled = updates.rfidEnabled
            -- Generate RFID data if enabling and none exists
            if updates.rfidEnabled and not identity.rfidData then
                identity.rfidData = SecurityCore.randomString(64)
                tac.identityLookup.set("rfid:" .. identity.rfidData, identityId)
            end
        end
        if updates.maxDistance ~= nil then
            identity.maxDistance = updates.maxDistance
        end
        
        identity.updated = os.epoch("utc")
        
        -- Validate
        local isValid, error = validateIdentityData(identity)
        if not isValid then
            return nil, error
        end
        
        -- Save
        tac.identities.set(identityId, identity)
        
        tac.logger.logAccess("identity_updated", {
            identity = identity,
            updates = updates,
            message = "Identity updated: " .. identity.name
        })
        
        return identity, nil
    end

    --- Get all identities
    --
    ---@return table All identities
    function identityManager.getAll()
        return tac.identities.getAll()
    end

    --- Delete an identity
    --
    ---@param identityId string Identity ID
    ---@return boolean Success
    ---@return string|nil Error message if failed
    function identityManager.deleteIdentity(identityId)
        local identity = tac.identities.get(identityId)
        if not identity then
            return false, "Identity not found: " .. identityId
        end
        
        -- Remove lookups
        if identity.nfcData then
            tac.identityLookup.unset("nfc:" .. identity.nfcData)
        end
        if identity.rfidData then
            tac.identityLookup.unset("rfid:" .. identity.rfidData)
        end
        
        -- Delete identity
        tac.identities.unset(identityId)
        
        tac.logger.logAccess("identity_deleted", {
            identity = identity,
            message = "Identity deleted: " .. identity.name
        })
        
        return true, nil
    end

    return identityManager
end

return { create = create }
