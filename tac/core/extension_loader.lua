--[[
    TAC Extension Loader
    
    Provides robust extension loading with dependency management, error handling,
    and graceful degradation. Supports extension metadata, version checking,
    and load order resolution based on dependencies.
    
    @module tac.core.extension_loader
    @author Twijn
    @version 1.0.1
    @license MIT
    
    @example
    -- Load extensions (usually done in tac/init.lua):
    local ExtensionLoader = require("tac.core.extension_loader")
    local loader = ExtensionLoader.new(tacInstance)
    
    -- Load all extensions from directory
    local success, errors = loader.loadFromDirectory("tac/extensions")
    
    -- Check loaded extensions
    local loaded = loader.getLoadedExtensions()
    for name, metadata in pairs(loaded) do
        log.debug(name .. " v" .. metadata.version)
    end
    
    -- Load specific extension
    local ext, err = loader.loadExtension("shopk_access", "tac/extensions/shopk_access.lua")
]]

local log = require("log")

local ExtensionLoader = {}

--- Parse extension metadata from module
--
-- Extracts metadata like name, version, description, dependencies, and author
-- from an extension module.
--
---@param extension table The extension module
---@param filename string The filename of the extension
---@return table Metadata object with name, version, description, dependencies, author
local function parseMetadata(extension, filename)
    local metadata = {
        name = extension.name or filename,
        version = extension.version or "unknown",
        description = extension.description or "No description provided",
        dependencies = extension.dependencies or {},
        author = extension.author or "unknown",
        filename = filename,
        optional_dependencies = extension.optional_dependencies or {}
    }
    return metadata
end

--- Check if dependencies are met
--
-- Validates that all required dependencies are loaded and available.
--
---@param dependencies table Array of dependency names
---@param loadedExtensions table Table of loaded extension names
---@return boolean True if all dependencies met
---@return string|nil Error message if dependencies missing
local function checkDependencies(dependencies, loadedExtensions)
    local missing = {}
    
    for _, dep in ipairs(dependencies) do
        if not loadedExtensions[dep] then
            table.insert(missing, dep)
        end
    end
    
    if #missing > 0 then
        return false, "Missing dependencies: " .. table.concat(missing, ", ")
    end
    
    return true, nil
end

--- Sort extensions by dependency order
--
-- Uses topological sort to determine the correct load order based on dependencies.
--
---@param extensions table Map of extension name to metadata
---@return table Array of extension names in load order
---@return table|nil Circular dependency error info if detected
local function sortByDependencies(extensions)
    local sorted = {}
    local visiting = {}
    local visited = {}
    
    local function visit(name)
        if visited[name] then
            return true
        end
        
        if visiting[name] then
            return false, "Circular dependency detected involving: " .. name
        end
        
        visiting[name] = true
        
        local ext = extensions[name]
        if ext and ext.dependencies then
            for _, dep in ipairs(ext.dependencies) do
                if extensions[dep] then
                    local success, err = visit(dep)
                    if not success then
                        return false, err
                    end
                end
            end
        end
        
        visiting[name] = nil
        visited[name] = true
        table.insert(sorted, name)
        
        return true
    end
    
    for name in pairs(extensions) do
        if not visited[name] then
            local success, err = visit(name)
            if not success then
                return nil, err
            end
        end
    end
    
    return sorted, nil
end

--- Load a single extension
--
-- Attempts to load an extension module with error handling and metadata parsing.
--
---@param extensionPath string Lua module path (e.g., "tac.extensions.shop_monitor")
---@param filename string The extension filename
---@return table|nil Extension module if successful, nil on error
---@return string|nil Error message if loading failed
local function loadExtension(extensionPath, filename)
    local success, result = pcall(require, extensionPath)
    
    if not success then
        return nil, "Failed to require: " .. tostring(result)
    end
    
    if type(result) ~= "table" then
        return nil, "Extension must return a table"
    end
    
    return result, nil
end

--- Create extension loader for TAC instance
--
-- Returns a loader interface with methods for discovering, loading, and managing extensions.
--
---@param tacInstance table The TAC instance
---@return table Loader interface with load methods
---@usage local loader = ExtensionLoader.create(tac)
function ExtensionLoader.create(tacInstance)
    local loader = {}
    local tac = tacInstance
    
    --- Load extensions from directory
    --
    -- Discovers and loads all extensions from the extensions directory,
    -- respecting dependencies and handling errors gracefully.
    --
    ---@param options table Optional configuration:
    --   - directory (string): Extension directory path (default: "tac/extensions")
    --   - skipPrefixes (table): Array of filename prefixes to skip (default: {"_", "disabled_"})
    --   - silent (boolean): Suppress output messages (default: false)
    ---@return table Results with fields:
    --   - loaded (table): Array of successfully loaded extension names
    --   - failed (table): Array of objects with name and error for failed extensions
    --   - skipped (table): Array of skipped extension names
    ---@usage local results = loader.loadFromDirectory({silent = false})
    function loader.loadFromDirectory(options)
        options = options or {}
        local directory = options.directory or "tac/extensions"
        local skipPrefixes = options.skipPrefixes or {"_", "disabled_"}
        local silent = options.silent or false
        
        local results = {
            loaded = {},
            failed = {},
            skipped = {}
        }
        
        -- Discover extensions
        local success, files = pcall(fs.list, directory)
        if not success then
            if not silent then
                log.error("Failed to list extensions directory: " .. directory)
            end
            return results
        end
        
        -- First pass: Load all extensions and gather metadata
        local discovered = {}
        
        for _, filename in ipairs(files) do
            -- Only load .lua files and skip directories
            if filename:match("%.lua$") and not fs.isDir(directory .. "/" .. filename) then
                local extName = filename:gsub("%.lua$", "")
                
                -- Check if should skip
                local shouldSkip = false
                for _, prefix in ipairs(skipPrefixes) do
                    if extName:sub(1, #prefix) == prefix then
                        shouldSkip = true
                        table.insert(results.skipped, extName)
                        break
                    end
                end
                
                if not shouldSkip then
                    local modulePath = directory:gsub("/", ".") .. "." .. extName
                    local extension, err = loadExtension(modulePath, extName)
                    
                    if extension then
                        local metadata = parseMetadata(extension, extName)
                        metadata.module = extension
                        discovered[extName] = metadata
                    else
                        table.insert(results.failed, {
                            name = extName,
                            error = err,
                            phase = "load"
                        })
                        
                        if not silent then
                            log.error("Failed to load extension '" .. extName .. "': " .. err)
                        end
                    end
                end
            end
        end
        
        -- Second pass: Sort by dependencies
        local loadOrder, sortErr = sortByDependencies(discovered)
        
        if not loadOrder then
            if not silent then
                log.error("Extension dependency error: " .. sortErr)
            end
            
            -- Load what we can without sorting
            loadOrder = {}
            for name in pairs(discovered) do
                table.insert(loadOrder, name)
            end
        end
        
        -- Third pass: Initialize extensions in dependency order
        local loadedExtensions = {}
        
        for _, extName in ipairs(loadOrder) do
            local metadata = discovered[extName]
            local extension = metadata.module
            
            -- Check dependencies
            local depsOk, depsErr = checkDependencies(metadata.dependencies, loadedExtensions)
            
            if not depsOk then
                table.insert(results.failed, {
                    name = extName,
                    error = depsErr,
                    phase = "dependencies"
                })
                
                if not silent then
                    log.error("Cannot load '" .. extName .. "': " .. depsErr)
                end
            else
                -- Check optional dependencies
                local missingOptional = {}
                for _, optDep in ipairs(metadata.optional_dependencies) do
                    if not loadedExtensions[optDep] then
                        table.insert(missingOptional, optDep)
                    end
                end
                
                if #missingOptional > 0 and not silent then
                    log.warn("'" .. extName .. "' missing optional dependencies: " .. table.concat(missingOptional, ", "))
                end
                
                -- Register and initialize
                local initSuccess, initErr = pcall(function()
                    tac.registerExtension(extName, extension)
                end)
                
                if initSuccess then
                    loadedExtensions[extName] = true
                    table.insert(results.loaded, extName)
                    
                    if not silent then
                        log.info("Loaded: " .. extName .. " v" .. metadata.version)
                    end
                else
                    table.insert(results.failed, {
                        name = extName,
                        error = tostring(initErr),
                        phase = "init"
                    })
                    
                    if not silent then
                        log.error("Failed to initialize '" .. extName .. "': " .. tostring(initErr))
                    end
                end
            end
        end
        
        return results
    end
    
    --- Load a specific extension by name
    --
    -- Loads a single extension from the extensions directory.
    --
    ---@param extensionName string Name of the extension (without .lua)
    ---@param options table Optional configuration:
    --   - directory (string): Extension directory path (default: "tac/extensions")
    --   - silent (boolean): Suppress output messages (default: false)
    ---@return boolean True if loaded successfully
    ---@return string|nil Error message if loading failed
    ---@usage local success, err = loader.loadExtension("shop_monitor")
    function loader.loadExtension(extensionName, options)
        options = options or {}
        local directory = options.directory or "tac/extensions"
        local silent = options.silent or false
        
        local modulePath = directory:gsub("/", ".") .. "." .. extensionName
        local extension, err = loadExtension(modulePath, extensionName)
        
        if not extension then
            if not silent then
                log.error("Failed to load '" .. extensionName .. "': " .. err)
            end
            return false, err
        end
        
        local metadata = parseMetadata(extension, extensionName)
        
        -- Check dependencies
        local depsOk, depsErr = checkDependencies(metadata.dependencies, tac.extensions)
        if not depsOk then
            if not silent then
                log.error("Cannot load '" .. extensionName .. "': " .. depsErr)
            end
            return false, depsErr
        end
        
        -- Register and initialize
        local initSuccess, initErr = pcall(function()
            tac.registerExtension(extensionName, extension)
        end)
        
        if not initSuccess then
            if not silent then
                log.error("Failed to initialize '" .. extensionName .. "': " .. tostring(initErr))
            end
            return false, tostring(initErr)
        end
        
        if not silent then
            log.info("Loaded: " .. extensionName .. " v" .. metadata.version)
        end
        
        return true, nil
    end
    
    --- Get information about loaded extensions
    --
    -- Returns metadata for all currently loaded extensions.
    --
    ---@return table Array of extension metadata objects
    ---@usage local extensions = loader.getLoadedExtensions()
    function loader.getLoadedExtensions()
        local info = {}
        
        for name, ext in pairs(tac.extensions) do
            local metadata = parseMetadata(ext, name)
            table.insert(info, metadata)
        end
        
        return info
    end
    
    return loader
end

return ExtensionLoader
