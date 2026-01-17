--[[
    ODY.FARM Farm Script Loader v1.1
    Automatically creates config file and loads enabled farm scripts from ody.farm
    
    Config file: ody_farm_loader_config.json (in exploit workspace)
    All scripts are enabled by default
    
    v1.1: Added safe_mode toggle (sync only, no farming)
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- ============== CONFIGURATION ==============
local CONFIG_FILE = "ody_farm_loader_config.json"
local BASE_URL = "https://scripts.ody.farm/"

-- Available farm scripts with their load order (lower = loads first)
local AVAILABLE_SCRIPTS = {
    { id = "check_server_type", name = "Check Server Type", file = "check_server_type.lua", order = 1, enabled = true },
    { id = "farm_config", name = "Farm Config (GUI)", file = "farm_config.lua", order = 2, enabled = true },
    { id = "farm", name = "Brainrot Farm", file = "farm.lua", order = 3, enabled = true },
    { id = "panel_sync", name = "Panel Sync", file = "panel_sync.lua", order = 4, enabled = true },
}

-- Global settings (not per-script toggles)
local GLOBAL_SETTINGS = {
    safe_mode = false, -- When true: only sync brainrots to panel, no farming/stealing
}

-- ============== CONFIG MANAGEMENT ==============

local function loadConfig()
    local config = {}
    
    -- Set defaults for scripts
    for _, script in ipairs(AVAILABLE_SCRIPTS) do
        config[script.id] = script.enabled
    end
    
    -- Set defaults for global settings
    for key, value in pairs(GLOBAL_SETTINGS) do
        config[key] = value
    end
    
    -- Try to load existing config
    local success, result = pcall(function()
        if isfile and isfile(CONFIG_FILE) then
            local data = readfile(CONFIG_FILE)
            local saved = HttpService:JSONDecode(data)
            
            -- Merge with defaults
            for key, value in pairs(saved) do
                config[key] = value
            end
        end
    end)
    
    return config
end

local function saveConfig(config)
    local success, err = pcall(function()
        local data = HttpService:JSONEncode(config)
        writefile(CONFIG_FILE, data)
    end)
    
    if not success then
        warn("[Farm Loader] Failed to save config: " .. tostring(err))
    end
end

local function createDefaultConfig()
    local config = {}
    
    -- Scripts
    for _, script in ipairs(AVAILABLE_SCRIPTS) do
        config[script.id] = script.enabled
    end
    
    -- Global settings
    for key, value in pairs(GLOBAL_SETTINGS) do
        config[key] = value
    end
    
    saveConfig(config)
    return config
end

-- ============== SCRIPT LOADING ==============

local function loadScript(scriptInfo)
    local url = BASE_URL .. scriptInfo.file
    
    local success, result = pcall(function()
        local response = game:HttpGet(url)
        if response and #response > 0 then
            local fn, err = loadstring(response)
            if fn then
                task.spawn(fn)
                return true
            else
                warn("[Farm Loader] Failed to parse " .. scriptInfo.name .. ": " .. tostring(err))
                return false
            end
        else
            warn("[Farm Loader] Empty response for " .. scriptInfo.name)
            return false
        end
    end)
    
    if not success then
        warn("[Farm Loader] Failed to load " .. scriptInfo.name .. ": " .. tostring(result))
        return false
    end
    
    return result
end

-- ============== MAIN ==============

local function main()
    print("[Farm Loader] Starting...")
    
    -- Create or load config
    local config
    
    local configExists = pcall(function()
        return isfile and isfile(CONFIG_FILE)
    end)
    
    if configExists and isfile(CONFIG_FILE) then
        config = loadConfig()
        print("[Farm Loader] Config loaded from " .. CONFIG_FILE)
    else
        config = createDefaultConfig()
        print("[Farm Loader] Created default config at " .. CONFIG_FILE)
    end
    
    -- Apply global settings to _G for other scripts to read
    _G.FarmLoaderSettings = _G.FarmLoaderSettings or {}
    _G.FarmLoaderSettings.safe_mode = config.safe_mode or false
    
    if config.safe_mode then
        print("[Farm Loader] ⚠️ SAFE MODE ENABLED - sync only, no farming")
    end
    
    -- Sort scripts by load order
    local scriptsToLoad = {}
    for _, script in ipairs(AVAILABLE_SCRIPTS) do
        if config[script.id] then
            table.insert(scriptsToLoad, script)
        end
    end
    
    table.sort(scriptsToLoad, function(a, b)
        return a.order < b.order
    end)
    
    -- Load enabled scripts
    local loaded = 0
    local failed = 0
    
    for _, script in ipairs(scriptsToLoad) do
        print("[Farm Loader] Loading: " .. script.name)
        
        if loadScript(script) then
            loaded = loaded + 1
        else
            failed = failed + 1
        end
        
        -- Small delay between scripts (farm scripts need more time)
        task.wait(0.5)
    end
    
    print(string.format("[Farm Loader] Completed! Loaded: %d, Failed: %d", loaded, failed))
    
    -- Save config (in case new scripts were added)
    saveConfig(config)
end

-- Run
main()
