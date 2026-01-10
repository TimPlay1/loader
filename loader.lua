--[[
    ODY.FARM Script Loader
    Automatically creates config file and loads enabled scripts from ody.farm
    
    Config file: ody_loader_config.json (in exploit workspace)
    All scripts are enabled by default
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- ============== CONFIGURATION ==============
local CONFIG_FILE = "ody_loader_config.json"
local BASE_URL = "https://scripts.ody.farm/"

-- Available scripts with their load order (lower = loads first)
local AVAILABLE_SCRIPTS = {
    { id = "adminabuse", name = "Admin Abuse", file = "adminabuse.lua", order = 1, enabled = true },
    { id = "killaura", name = "Killaura", file = "killaura.lua", order = 2, enabled = true },
    { id = "killaura_sync", name = "Killaura Sync (Meowl Greeting)", file = "killaura_sync.lua", order = 3, enabled = true },
    { id = "autosteal", name = "AutoSteal Optimized", file = "autosteal_optimized.lua", order = 4, enabled = true },
    { id = "removeborders", name = "Remove Borders", file = "RemoveBorders.lua", order = 5, enabled = true },
    { id = "disable_camera", name = "Disable Camera Effects", file = "disable_camera_effects.lua", order = 6, enabled = true },
    { id = "customsound", name = "Custom Sound Replacer", file = "CustomSound.lua", order = 7, enabled = true },
    { id = "ambient", name = "Ambient/Skybox Controller", file = "Ambient.lua", order = 8, enabled = true },
}

-- ============== CONFIG MANAGEMENT ==============

local function loadConfig()
    local config = {}
    
    -- Set defaults
    for _, script in ipairs(AVAILABLE_SCRIPTS) do
        config[script.id] = script.enabled
    end
    
    -- Try to load existing config
    local success, result = pcall(function()
        if isfile and isfile(CONFIG_FILE) then
            local data = readfile(CONFIG_FILE)
            local saved = HttpService:JSONDecode(data)
            
            -- Merge with defaults
            for key, value in pairs(saved) do
                if config[key] ~= nil then
                    config[key] = value
                end
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
        warn("[ODY Loader] Failed to save config: " .. tostring(err))
    end
end

local function createDefaultConfig()
    local config = {}
    
    for _, script in ipairs(AVAILABLE_SCRIPTS) do
        config[script.id] = script.enabled
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
                warn("[ODY Loader] Failed to parse " .. scriptInfo.name .. ": " .. tostring(err))
                return false
            end
        else
            warn("[ODY Loader] Empty response for " .. scriptInfo.name)
            return false
        end
    end)
    
    if not success then
        warn("[ODY Loader] Failed to load " .. scriptInfo.name .. ": " .. tostring(result))
        return false
    end
    
    return result
end

-- ============== MAIN ==============

local function main()
    print("[ODY Loader] Starting...")
    
    -- Create or load config
    local config
    
    local configExists = pcall(function()
        return isfile and isfile(CONFIG_FILE)
    end)
    
    if configExists and isfile(CONFIG_FILE) then
        config = loadConfig()
        print("[ODY Loader] Config loaded from " .. CONFIG_FILE)
    else
        config = createDefaultConfig()
        print("[ODY Loader] Created default config at " .. CONFIG_FILE)
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
        print("[ODY Loader] Loading: " .. script.name)
        
        if loadScript(script) then
            loaded = loaded + 1
        else
            failed = failed + 1
        end
        
        -- Small delay between scripts
        task.wait(0.1)
    end
    
    print(string.format("[ODY Loader] Completed! Loaded: %d, Failed: %d", loaded, failed))
    
    -- Save config (in case new scripts were added)
    saveConfig(config)
end

-- Run
main()
