--[[
    Brainrot Farm v2.2
    With Panel Sync Support
    Updated: 2026-01-17
]]

-- ============ SAFE MODE (БЕЗОПАСНЫЙ РЕЖИМ) ============
-- Когда включён - скрипт ТОЛЬКО собирает информацию о brainrots
-- и отправляет её в панель. Никакого фарминга, кражи и движения!
-- Переключите на true для активации безопасного режима.
local SAFE_MODE = false -- <<< ПЕРЕКЛЮЧАТЕЛЬ БЕЗОПАСНОГО РЕЖИМА
-- ============ END SAFE MODE ============

-- ВАЖНО: Ждём 5 секунд чтобы игра полностью загрузилась
-- Это предотвращает ошибку "Shared is not a valid member of ReplicatedStorage"
-- которая ломает загрузку брейнротов в игре
task.wait(5)

if not _G.FarmConfig or not _G.FarmConfig.isAllowed then
    return
end

local CONFIG = _G.FarmConfig
local updateStatus = CONFIG.updateStatus
local setPlotInfo = CONFIG.setPlotInfo

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- Дополнительно ждём появления критических компонентов
local function waitForGameLoad()
    local maxWait = 30
    local waited = 0
    
    -- Ждём появления Shared в ReplicatedStorage
    while waited < maxWait do
        local success = pcall(function()
            return ReplicatedStorage:FindFirstChild("Shared")
        end)
        if success and ReplicatedStorage:FindFirstChild("Shared") then
            break
        end
        task.wait(0.5)
        waited = waited + 0.5
    end
    
    -- Ждём появления Datas
    waited = 0
    while waited < maxWait do
        local success = pcall(function()
            return ReplicatedStorage:FindFirstChild("Datas")
        end)
        if success and ReplicatedStorage:FindFirstChild("Datas") then
            break
        end
        task.wait(0.5)
        waited = waited + 0.5
    end
    
    return true
end

waitForGameLoad()

-- ============ KEY SYSTEM & PANEL SYNC ============
-- ВАЖНО: Файлы данных хранятся в farm_data (НЕ в ScriptManager/farm), 
-- чтобы Wave не пытался загрузить их как Lua скрипты
local KEY_FILE = "farm_data/key.txt"
local PANEL_DATA_FILE = "farm_data/panel_data.json"
local PANEL_SYNC_INTERVAL = 3 -- секунд между синхронизацией с панелью (быстрее!)
local PANEL_API_URL = "https://ody.farm/api/sync" -- URL веб-панели (VPS)
local PANEL_SYNC_ENABLED = false -- ОТКЛЮЧЕНО - используется panel_sync.lua
local FARM_KEY = nil
local lastPanelHttpSync = 0

-- HTTP запрос для синхронизации с веб-панелью
local function httpPost(url, data)
    local success, response = pcall(function()
        local jsonData = HttpService:JSONEncode(data)
        
        -- Пробуем разные методы HTTP в зависимости от executor'а
        if request then
            return request({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        elseif syn and syn.request then
            return syn.request({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        elseif http_request then
            return http_request({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        elseif fluxus and fluxus.request then
            return fluxus.request({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        else
            warn("[PanelSync] No HTTP request function available")
            return nil
        end
    end)
    
    if success and response then
        return response.StatusCode == 200, response
    end
    return false, nil
end

-- Генерация уникального ключа
local function generateKey()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local key = "FARM-"
    for i = 1, 4 do
        if i > 1 then key = key .. "-" end
        for j = 1, 4 do
            local idx = math.random(1, #chars)
            key = key .. chars:sub(idx, idx)
        end
    end
    return key
end

-- Загрузить или создать ключ
local function loadOrCreateKey()
    local key = nil
    pcall(function()
        if isfile(KEY_FILE) then
            key = readfile(KEY_FILE):gsub("%s+", "")
        end
    end)
    
    if not key or key == "" then
        key = generateKey()
        pcall(function()
            if not isfolder("farm_data") then
                makefolder("farm_data")
            end
            writefile(KEY_FILE, key)
        end)
    end
    
    return key
end

FARM_KEY = loadOrCreateKey()

-- ============ LOGGING SYSTEM (Enhanced) ============
local LOG_FILE = "farm/farm_debug.log"
local LOG_ENABLED = false -- ОТКЛЮЧЕНО
local LOG_DETAILED = false -- Detailed logging for brainrot search
local LOG_PATHFINDING_VERBOSE = false -- ОТКЛЮЧЕНО
local LOG_MAX_SIZE = 500000 -- Максимальный размер лога (500KB) - автоочистка при превышении
local LOG_SESSION_ID = string.format("%s_%d", os.date("%H%M%S"), math.random(1000, 9999))

local function ensureLogFolder()
    pcall(function()
        if not isfolder("farm") then
            makefolder("farm")
        end
    end)
end

-- Проверка размера лога и автоочистка при превышении
local function checkLogSize()
    local shouldClear = false
    pcall(function()
        if isfile(LOG_FILE) then
            local content = readfile(LOG_FILE)
            if content and #content > LOG_MAX_SIZE then
                shouldClear = true
            end
        end
    end)
    return shouldClear
end

local function log(message, level)
    if not LOG_ENABLED then return end
    level = level or "INFO"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local logLine = string.format("[%s] [%s] [%s] %s\n", timestamp, LOG_SESSION_ID, level, message)
    pcall(function()
        ensureLogFolder()
        
        -- Автоочистка при превышении размера
        if checkLogSize() then
            writefile(LOG_FILE, string.format("=== LOG AUTO-CLEARED (size exceeded %dKB) ===\n%s", 
                LOG_MAX_SIZE / 1000, logLine))
        else
            appendfile(LOG_FILE, logLine)
        end
    end)
end

local function logDetailed(message)
    if not LOG_DETAILED then return end
    log(message, "DEBUG")
end

local function logVerbose(message)
    if not LOG_PATHFINDING_VERBOSE then return end
    log(message, "VERBOSE")
end

local function clearLog()
    pcall(function()
        ensureLogFolder()
        local header = string.format([[
============================================================
   FARM DEBUG LOG - Session: %s
   Started: %s
   Player: %s
   PathfindingService: ENABLED
============================================================

]], LOG_SESSION_ID, os.date("%Y-%m-%d %H:%M:%S"), LocalPlayer.Name)
        writefile(LOG_FILE, header)
    end)
end

-- Функция для записи отладочной информации о текущем состоянии
local function logGameState()
    pcall(function()
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChild("Humanoid")
        
        local stateInfo = {
            "=== GAME STATE DUMP ===",
            "Character: " .. tostring(character ~= nil),
            "HRP Position: " .. (hrp and string.format("(%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z) or "N/A"),
            "Health: " .. (humanoid and tostring(humanoid.Health) or "N/A"),
            "WalkSpeed: " .. (humanoid and tostring(humanoid.WalkSpeed) or "N/A"),
            "Farm Enabled: " .. tostring(CONFIG.FARM_ENABLED),
            "Carrying Brainrot: " .. tostring(LocalPlayer:GetAttribute("Stealing") == true),
        }
        
        -- Проверяем Plots
        local plotsFolder = workspace:FindFirstChild("Plots")
        if plotsFolder then
            table.insert(stateInfo, "Plots Count: " .. tostring(#plotsFolder:GetChildren()))
        end
        
        -- Проверяем препятствия
        local shop = workspace:FindFirstChild("Shop")
        local fuseMachine = workspace:FindFirstChild("FuseMachine")
        local adventCalendar = workspace:FindFirstChild("AdventCalendar")
        table.insert(stateInfo, "Obstacles - Shop: " .. tostring(shop ~= nil) .. 
            ", FuseMachine: " .. tostring(fuseMachine ~= nil) ..
            ", AdventCalendar: " .. tostring(adventCalendar ~= nil))
        
        table.insert(stateInfo, "========================")
        
        log(table.concat(stateInfo, "\n"))
    end)
end

-- Clear log on startup (reinject)
clearLog()
log("Farm script started for player: " .. LocalPlayer.Name)
log("Session ID: " .. LOG_SESSION_ID)

-- Логируем режим работы
if SAFE_MODE then
    log("======== SAFE MODE ACTIVE ========")
    log("Only brainrot scanning and panel sync enabled")
    log("All farming/stealing functions DISABLED")
    log("==================================")
else
    log("Normal farming mode")
end

logGameState()

-- ============ SYNCHRONIZER ANTI-CHEAT PATCH ============
do
    local success, err = pcall(function()
        local SyncModule = ReplicatedStorage:WaitForChild("Packages", 10):WaitForChild("Synchronizer", 10)
        if SyncModule then
            local Sync = require(SyncModule)
            local function emptyFunc() end
            local functionsToPatch = {Sync.Get, Sync.Wait}
            for _, targetFunc in ipairs(functionsToPatch) do
                local upvalues = debug.getupvalues(targetFunc)
                for index, val in pairs(upvalues) do
                    if type(val) == "function" then
                        debug.setupvalue(targetFunc, index, emptyFunc)
                    end
                end
            end
            log("[Synchronizer] Anti-cheat patched successfully")
        end
    end)
end

-- ============ SYNCHRONIZER SYSTEM (NEW - from best brainrot logic.txt) ============
-- Synchronizer provides REAL-TIME SERVER DATA about brainrots on all plots
-- This is much more reliable than searching through GUI elements!
local Synchronizer = nil
local AnimalsShared = nil
local PlotsFolder = workspace:WaitForChild("Plots", 30)

local function initializeSynchronizer()
    local success, err = pcall(function()
        local Packages = ReplicatedStorage:WaitForChild("Packages", 10)
        if Packages then
            local SyncModule = Packages:FindFirstChild("Synchronizer")
            if SyncModule then
                Synchronizer = require(SyncModule)
                log("[Synchronizer] Loaded successfully from Packages")
            else
                log("[Synchronizer] Module not found in Packages", "WARN")
            end
        end
        
        local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
        if Shared then
            local AnimalsModule = Shared:FindFirstChild("Animals")
            if AnimalsModule then
                AnimalsShared = require(AnimalsModule)
                log("[AnimalsShared] Loaded successfully from Shared")
            else
                log("[AnimalsShared] Module not found in Shared", "WARN")
            end
        end
    end)
    
    if not success then
        log("[Synchronizer] Init error: " .. tostring(err), "WARN")
    end
    
    return Synchronizer ~= nil and AnimalsShared ~= nil
end

-- Initialize Synchronizer
local SynchronizerReady = initializeSynchronizer()
log("[Synchronizer] Ready: " .. tostring(SynchronizerReady))
-- ============ END SYNCHRONIZER SYSTEM ============

local PRICE_MULTIPLIERS = {[""] = 1, ["K"] = 1e3, ["M"] = 1e6, ["B"] = 1e9, ["T"] = 1e12, ["QA"] = 1e15, ["QI"] = 1e18}

local function parsePrice(priceString)
    local cleanString = tostring(priceString or ""):gsub("[$,]", ""):gsub("/s", "")
    local numericPart, unitPart = cleanString:match("([%d%.]+)%s*([A-Za-z]*)")
    if not numericPart then return 0 end
    return (tonumber(numericPart) or 0) * (PRICE_MULTIPLIERS[string.upper(unitPart or "")] or 1)
end

local function formatPrice(value)
    if value >= 1e12 then return string.format("%.1fT", value / 1e12)
    elseif value >= 1e9 then return string.format("%.1fB", value / 1e9)
    elseif value >= 1e6 then return string.format("%.1fM", value / 1e6)
    elseif value >= 1e3 then return string.format("%.1fK", value / 1e3)
    else return tostring(math.floor(value)) end
end

-- ============ MUTATION & TRAIT MODIFIERS (from Animals.lua GetGeneration) ============
local MUTATION_MODIFIERS = {
    ["Gold"] = 0.25,
    ["Diamond"] = 0.5,
    ["Bloodrot"] = 1,
    ["Candy"] = 3,
    ["Lava"] = 5,
    ["Galaxy"] = 6,
    ["YinYang"] = 6.5,
    ["Yin Yang"] = 6.5,
    ["Radioactive"] = 7.5,
    ["Rainbow"] = 9,
}

local TRAIT_MODIFIERS = {
    ["Taco"] = 2,
    ["Nyan"] = 5,
    ["Galactic"] = 3,
    ["Fireworks"] = 5,
    ["Zombie"] = 4,
    ["Claws"] = 4,
    ["Glitched"] = 4,
    ["Bubblegum"] = 3,
    ["Fire"] = 5,
    ["Wet"] = 1.5,
    ["Snowy"] = 2,
    ["Cometstruck"] = 2.5,
    ["Explosive"] = 3,
    ["Disco"] = 4,
    ["10B"] = 3,
    ["Shark Fin"] = 3,
    ["Matteo Hat"] = 3.5,
    ["Brazil"] = 5,
    ["Lightning"] = 5,
    ["UFO"] = 2,
    ["Spider"] = 3.5,
    ["Strawberry"] = 7,
    ["Paint"] = 5,
    ["Skeleton"] = 3,
    ["Sombrero"] = 4,
    ["Tie"] = 3.75,
    ["Witch Hat"] = 3,
    ["Indonesia"] = 4,
    ["Meowl"] = 6,
    ["RIP Gravestone"] = 3.5,
    ["Jackolantern Pet"] = 4.5,
    ["Festive"] = 1,
    ["Shiny"] = 0.5,
    -- Sleepy обрабатывается отдельно (множитель 0.5 на финальный результат)
}

-- Fallback base generations for common brainrots (when Animals module is unavailable)
-- Updated from ReplicatedStorage.Datas.Animals (2025-12-21)
local FALLBACK_GENERATIONS = {
    -- OG tier (500M+ base)
    ["Strawberry Elephant"] = 500000000,
    ["Meowl"] = 400000000,
    
    -- Secret tier (100M+ base)
    ["Dragon Cannelloni"] = 250000000,
    ["Headless Horseman"] = 175000000,
    ["Capitano Moby"] = 160000000,
    ["Cooki and Milki"] = 155000000,
    ["Burguro And Fryuro"] = 150000000,
    ["La Secret Combinasion"] = 125000000,
    ["La Casa Boo"] = 100000000,
    ["Fragrama and Chocrama"] = 100000000,
    
    -- Secret tier (50M-100M base)
    ["Spooky and Pumpky"] = 80000000,
    ["Los Spaghettis"] = 70000000,
    ["Spaghetti Tualetti"] = 60000000,
    ["Garama and Madundung"] = 50000000,
    ["Lavadorito Spinito"] = 45000000,
    ["Ketchuru and Musturu"] = 42500000,
    ["La Supreme Combinasion"] = 40000000,
    ["Orcaledon"] = 40000000,
    ["Tictac Sahur"] = 37500000,
    ["Ketupat Kepat"] = 35000000,
    ["La Taco Combinasion"] = 35000000,
    ["Tang Tang Keletang"] = 33500000,
    ["Los Tacoritas"] = 32000000,
    ["Eviledon"] = 31500000,
    ["Los Primos"] = 31000000,
    ["Los Puggies"] = 30000000,
    ["W or L"] = 30000000,
    ["Esok Sekolah"] = 30000000,
    ["Gobblino Uniciclino"] = 27500000,
    ["Tralaledon"] = 27500000,
    ["Mieteteira Bicicleteira"] = 26000000,
    ["Chillin Chili"] = 25000000,
    ["Chipso and Queso"] = 25000000,
    ["La Spooky Grande"] = 24500000,
    ["Los Bros"] = 24000000,
    ["La Extinct Grande"] = 23500000,
    ["Los 67"] = 22500000,
    ["Celularcini Viciosini"] = 22500000,
    ["Los Mobilis"] = 22000000,
    ["Money Money Puggy"] = 21000000,
    ["Los Spooky Combinasionas"] = 20000000,
    ["Los Hotspotsitos"] = 20000000,
    ["Los Planitos"] = 18500000,
    ["Las Sis"] = 17500000,
    ["Tacorita Bicicleta"] = 16500000,
    ["Fishino Clownino"] = 15500000,
    ["Los Combinasionas"] = 15000000,
    ["Nuclearo Dinossauro"] = 15000000,
    ["Swag Soda"] = 13000000,
    ["Mariachi Corazoni"] = 12500000,
    ["Los Burritos"] = 8500000,
    ["67"] = 7500000,
    ["Los Chicleteiras"] = 7000000,
    ["Guest 666"] = 6666666,
    ["Rang Ring Bus"] = 6000000,
    ["Los Nooo My Hotspotsitos"] = 5500000,
    ["Noo my Candy"] = 5000000,
    ["Los Quesadillas"] = 4500000,
    ["Chicleteirina Bicicleteirina"] = 4000000,
    ["Burrito Bandito"] = 4000000,
    ["Chicleteira Bicicleteira"] = 3500000,
    ["Quesadillo Vampiro"] = 3500000,
    ["Quesadilla Crocodila"] = 3000000,
    ["Pot Pumpkin"] = 3000000,
    ["Horegini Boom"] = 2750000,
    ["Pot Hotspot"] = 2500000,
    ["Pirulitoita Bicicleteira"] = 2500000,
    ["To to to Sahur"] = 2250000,
    ["La Sahur Combinasion"] = 2000000,
    ["Telemorte"] = 2000000,
    ["Noo my examine"] = 1750000,
    ["Tung Tung Tung Sahur"] = 1500000,
    ["Nooo My Hotspot"] = 1500000,
    ["Los Jobcitos"] = 1500000,
    ["Cuadramat and Pakrahmatmamat"] = 1400000,
    ["Los Cucarachas"] = 1250000,
    ["1x1x1x1"] = 1111111,
    ["Perrito Burrito"] = 1000000,
    ["Graipuss Medussi"] = 1000000,
    ["25"] = 1000000,
    ["Giftini Spyderini"] = 999999,
    ["Trickolino"] = 900000,
    ["La Vacca Jacko Linterino"] = 850000,
    ["Las Vaquitas Saturnitas"] = 750000,
    ["Los Karkeritos"] = 750000,
    ["Karker Sahur"] = 725000,
    ["Frankentteo"] = 700000,
    ["Job Job Job Sahur"] = 700000,
    ["Pumpkini Spyderini"] = 650000,
    ["Las Tralaleritas"] = 650000,
    ["Extinct Matteo"] = 625000,
    ["La Karkerkar Combinasion"] = 600000,
    ["Yess my examine"] = 575000,
    ["Guerriro Digitale"] = 550000,
    ["Boatito Auratito"] = 525000,
    ["Vulturino Skeletono"] = 500000,
    ["Los Tralaleritos"] = 500000,
    ["Los Tortus"] = 500000,
    ["Zombie Tralala"] = 500000,
    ["La Cucaracha"] = 475000,
    ["Extinct Tralalero"] = 450000,
    ["Fragola La La La"] = 450000,
    ["Los Spyderinis"] = 425000,
    ["Agarrini la Palini"] = 425000,
    ["Chachechi"] = 400000,
    ["Blackhole Goat"] = 400000,
    ["Dul Dul Dul"] = 375000,
    ["Torrtuginni Dragonfrutini"] = 350000,
    ["Sammyni Spyderini"] = 325000,
    ["Jackorilla"] = 315000,
    ["Trenostruzzo Turbo 4000"] = 310000,
    ["La Vacca Saturno Saturnita"] = 300000,
    ["Karkerkar Kurkur"] = 300000,
    ["Los Matteos"] = 300000,
    ["Bisonte Giuppitere"] = 300000,
    
    -- Brainrot God tier and lower
    ["La Grande Combinasion"] = 10000000,
    ["Trippi Troppi"] = 15,
    ["Brr Brr Patapim"] = 100,
    ["Cappuccino Assassino"] = 75,
    ["Boneca Ambalabu"] = 40,
    ["Trulimero Trulicina"] = 125,
    ["Bananita Dolphinita"] = 150,
    ["Brri Brri Bicus Dicus Bombicus"] = 175,
}

-- Forward declaration (defined fully in ANIMAL DATA CACHE section)
local AnimalGenerationCache = {}

-- Parse traits from attribute (CSV string, JSON array, or table)
local function parseTraitsAttribute(traitsAttr)
    if not traitsAttr then return nil end
    
    if type(traitsAttr) == "table" then
        return traitsAttr
    end
    
    if type(traitsAttr) == "string" and traitsAttr ~= "" then
        -- Try JSON first
        local success, decoded = pcall(function()
            return HttpService:JSONDecode(traitsAttr)
        end)
        if success and type(decoded) == "table" then
            return decoded
        end
        
        -- CSV format: "Taco,Claws,Nyan,Bubblegum"
        local traits = {}
        for trait in string.gmatch(traitsAttr, "[^,]+") do
            local trimmed = trait:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(traits, trimmed)
            end
        end
        if #traits > 0 then
            return traits
        end
    end
    
    return nil
end

-- Calculate brainrot generation directly from model attributes
-- This is the NEW correct way - no more GUI search!
local function calculateBrainrotGeneration(serverModel)
    if not serverModel then return 0, nil, nil, nil end
    
    local mutation = serverModel:GetAttribute("Mutation")
    local traitsAttr = serverModel:GetAttribute("Traits")
    local indexAttr = serverModel:GetAttribute("Index")
    
    local index = indexAttr or serverModel.Name
    if not index or index == "" then return 0, nil, nil, nil end
    
    -- DEBUG: Log what we found
    log("[calcGen] Model: " .. tostring(serverModel.Name) .. ", Index attr: " .. tostring(indexAttr) .. ", Mutation attr: " .. tostring(mutation) .. ", Traits attr: " .. tostring(traitsAttr))
    
    -- Parse traits
    local traits = parseTraitsAttribute(traitsAttr)
    
    -- Get baseGeneration from Animals module or fallback
    local baseGeneration = 0
    
    -- Try AnimalGenerationCache first (loaded from Datas.Animals)
    if AnimalGenerationCache and AnimalGenerationCache[index] then
        baseGeneration = AnimalGenerationCache[index]
        log("[calcGen] baseGeneration from cache: " .. tostring(baseGeneration))
    end
    
    -- Try Shared.Animals module
    if baseGeneration == 0 and _G.SharedAnimalsModule and _G.SharedAnimalsModule.GetGeneration then
        pcall(function()
            local gen = _G.SharedAnimalsModule:GetGeneration(index)
            if gen and gen > 0 then
                baseGeneration = gen
                log("[calcGen] baseGeneration from SharedAnimals: " .. tostring(baseGeneration))
            end
        end)
    end
    
    -- Fallback to hardcoded values
    if baseGeneration == 0 then
        baseGeneration = FALLBACK_GENERATIONS[index] or 10
        log("[calcGen] baseGeneration from FALLBACK: " .. tostring(baseGeneration))
    end
    
    -- Apply modifiers using game formula: finalGen = base * (1 + mutationMod + sum(traitMods))
    local totalModifier = 1.0
    local hasSleepy = false
    
    if mutation and MUTATION_MODIFIERS[mutation] then
        totalModifier = totalModifier + MUTATION_MODIFIERS[mutation]
        log("[calcGen] Mutation modifier for " .. tostring(mutation) .. ": +" .. tostring(MUTATION_MODIFIERS[mutation]) .. " = " .. tostring(totalModifier))
    end
    
    if traits then
        for _, trait in ipairs(traits) do
            if trait == "Sleepy" then
                hasSleepy = true
            elseif TRAIT_MODIFIERS[trait] then
                totalModifier = totalModifier + TRAIT_MODIFIERS[trait]
            end
        end
    end
    
    local finalGeneration = baseGeneration * totalModifier
    if hasSleepy then
        finalGeneration = finalGeneration * 0.5
    end
    
    log("[calcGen] RESULT: base=" .. formatPrice(baseGeneration) .. " * modifier=" .. tostring(totalModifier) .. " = " .. formatPrice(finalGeneration))
    
    return math.floor(finalGeneration), index, mutation, traits
end

-- ============ ANIMAL DATA CACHE ============
-- Cache animal generation data from ReplicatedStorage.Datas.Animals
-- This is critical because AnimalOverhead is CLIENT-SIDE ONLY and doesn't replicate to other players!
-- NOTE: AnimalGenerationCache is declared above (forward declaration)
local AnimalDataLoaded = false

local function loadAnimalData()
    if AnimalDataLoaded then return end
    log("Loading animal data...")
    
    -- Try method 1: require Datas.Animals
    local success1, err1 = pcall(function()
        local Datas = ReplicatedStorage:WaitForChild("Datas", 5)
        if not Datas then return end
        local AnimalsModule = Datas:FindFirstChild("Animals")
        if not AnimalsModule then return end
        local animalsData = require(AnimalsModule)
        if animalsData then
            local count = 0
            for name, data in pairs(animalsData) do
                if type(data) == "table" and data.Generation then
                    AnimalGenerationCache[name] = data.Generation
                    count = count + 1
                    if data.DisplayName and data.DisplayName ~= name then
                        AnimalGenerationCache[data.DisplayName] = data.Generation
                    end
                end
            end
            if count > 0 then
                AnimalDataLoaded = true
                log("Method 1: Loaded " .. count .. " animals from Datas.Animals")
            end
        end
    end)
    
    -- Try method 2: require Shared.Animals (has GetGeneration function)
    if not AnimalDataLoaded then
        pcall(function()
            local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
            if not Shared then return end
            local AnimalsShared = Shared:FindFirstChild("Animals")
            if not AnimalsShared then return end
            local sharedModule = require(AnimalsShared)
            if sharedModule and sharedModule.GetGeneration then
                -- Store the module reference for dynamic lookup
                _G.SharedAnimalsModule = sharedModule
                AnimalDataLoaded = true
                log("Method 2: Loaded Shared.Animals module with GetGeneration function")
            end
        end)
    end
    
    -- Try method 3: Check if game already has cached data
    if not AnimalDataLoaded then
        pcall(function()
            if _G.AnimalData then
                for name, gen in pairs(_G.AnimalData) do
                    AnimalGenerationCache[name] = gen
                end
                AnimalDataLoaded = true
                log("Method 3: Loaded from _G.AnimalData")
            end
        end)
    end
    
    if not AnimalDataLoaded then
        log("WARNING: Could not load animal data. ProximityPrompt method will not work!", "WARN")
    end
end

-- Get generation (income per second) for a brainrot by name
local function getAnimalGeneration(brainrotName)
    if not AnimalDataLoaded then
        loadAnimalData()
    end
    
    -- First check cache
    if AnimalGenerationCache[brainrotName] then
        return AnimalGenerationCache[brainrotName]
    end
    
    -- Try Shared.Animals module if available
    if _G.SharedAnimalsModule and _G.SharedAnimalsModule.GetGeneration then
        local success, gen = pcall(function()
            return _G.SharedAnimalsModule:GetGeneration(brainrotName)
        end)
        if success and gen and gen > 0 then
            AnimalGenerationCache[brainrotName] = gen -- Cache for future
            return gen
        end
    end
    
    return 0
end

-- Load animal data on startup
loadAnimalData()

local cachedMyPlot, lastCacheTime = nil, 0

local function findPlayerPlot()
    if cachedMyPlot and cachedMyPlot.Parent and (tick() - lastCacheTime) < 3 then return cachedMyPlot end
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local plotSign = plot:FindFirstChild("PlotSign")
        if not plotSign then continue end
        local surfaceGui = plotSign:FindFirstChild("SurfaceGui")
        if not surfaceGui then continue end
        local frame = surfaceGui:FindFirstChild("Frame")
        if not frame then continue end
        local nameLabel = frame:FindFirstChildOfClass("TextLabel")
        if nameLabel and (nameLabel.Text:find(LocalPlayer.DisplayName, 1, true) or nameLabel.Text:find(LocalPlayer.Name, 1, true)) then
            cachedMyPlot, lastCacheTime = plot, tick()
            return plot
        end
    end
    return nil
end

local function getPlotOwnerName(plot)
    if not plot then return nil end
    
    -- Method 1: Get owner from plot attribute (most reliable!)
    local ownerAttr = plot:GetAttribute("Owner")
    if ownerAttr and ownerAttr ~= "" then
        return ownerAttr
    end
    
    -- Method 2: Get owner from PlotSign (fallback)
    local plotSign = plot:FindFirstChild("PlotSign")
    if not plotSign then return "Empty Base" end
    local surfaceGui = plotSign:FindFirstChild("SurfaceGui")
    if not surfaceGui then return "Empty Base" end
    local frame = surfaceGui:FindFirstChild("Frame")
    if not frame then return "Empty Base" end
    local nameLabel = frame:FindFirstChildOfClass("TextLabel")
    if not nameLabel then return "Empty Base" end
    
    local text = nameLabel.Text
    -- Убираем "'s Base" из текста таблички чтобы получить чистое имя
    if text then
        text = text:gsub("'s Base", "")
        text = text:gsub("'s Base", "") -- на случай апострофа другого типа
    end
    return text or "Empty Base"
end

-- Find the actual COLLECT ZONE part (green panel with "COLLECT ZONE" text)
-- ВАЖНО: Collect Zone может быть в модели Cash ИЛИ CashPad внутри plot!
local function getPlotCollectZone(plot)
    if not plot then return nil end
    
    -- Список возможных имён модели с Collect Zone
    local possibleNames = {"Cash", "CashPad"}
    
    -- ПЕРВЫЙ МЕТОД: Ищем в моделях Cash или CashPad
    for _, modelName in ipairs(possibleNames) do
        local cashModel = plot:FindFirstChild(modelName)
        if cashModel then
            for _, part in ipairs(cashModel:GetChildren()) do
                if part:IsA("BasePart") then
                    local surfaceGui = part:FindFirstChild("SurfaceGui")
                    if surfaceGui then
                        local frame = surfaceGui:FindFirstChild("Frame")
                        if frame then
                            local textLabel = frame:FindFirstChild("TextLabel")
                            if textLabel and textLabel:IsA("TextLabel") then
                                if textLabel.Text == "COLLECT ZONE" then
                                    log("[COLLECT_ZONE] Found in " .. modelName .. " model: " .. tostring(part.Position))
                                    return part
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- ВТОРОЙ МЕТОД: Ищем в Decorations (запасной)
    local decorations = plot:FindFirstChild("Decorations")
    if decorations then
        for _, part in ipairs(decorations:GetChildren()) do
            if part:IsA("BasePart") then
                local surfaceGui = part:FindFirstChild("SurfaceGui")
                if surfaceGui then
                    local frame = surfaceGui:FindFirstChild("Frame")
                    if frame then
                        local textLabel = frame:FindFirstChild("TextLabel")
                        if textLabel and textLabel:IsA("TextLabel") then
                            if textLabel.Text == "COLLECT ZONE" then
                                log("[COLLECT_ZONE] Found in Decorations: " .. tostring(part.Position))
                                return part
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- ТРЕТИЙ МЕТОД: Рекурсивный поиск по всему plot
    local function searchRecursive(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("BasePart") then
                local surfaceGui = child:FindFirstChild("SurfaceGui")
                if surfaceGui then
                    local frame = surfaceGui:FindFirstChild("Frame")
                    if frame then
                        local textLabel = frame:FindFirstChild("TextLabel")
                        if textLabel and textLabel:IsA("TextLabel") and textLabel.Text == "COLLECT ZONE" then
                            log("[COLLECT_ZONE] Found recursively: " .. tostring(child.Position))
                            return child
                        end
                    end
                end
            end
            local found = searchRecursive(child)
            if found then return found end
        end
        return nil
    end
    
    local found = searchRecursive(plot)
    if found then return found end
    
    log("[COLLECT_ZONE] Not found for plot: " .. tostring(plot.Name), "WARN")
    return nil
end

local function getPlotDeliveryHitbox(plot)
    if not plot then return nil end
    -- First try to find the actual COLLECT ZONE
    local collectZone = getPlotCollectZone(plot)
    if collectZone then return collectZone end
    -- Fallback to DeliveryHitbox
    local deliveryHitbox = plot:FindFirstChild("DeliveryHitbox")
    if deliveryHitbox and deliveryHitbox:IsA("BasePart") then
        log("[COLLECT_ZONE] Using DeliveryHitbox fallback: " .. tostring(deliveryHitbox.Position))
        return deliveryHitbox
    end
    return nil
end

-- Получить позицию для подхода к Collect Zone (учитывая ориентацию панели)
-- Панель вертикальная, повёрнута - используем LookVector для определения направления подхода
local function getCollectZoneApproachPosition(collectZonePart, offset)
    if not collectZonePart then return nil end
    
    offset = offset or 5 -- Расстояние от центра панели
    
    local partCFrame = collectZonePart.CFrame
    local partPos = partCFrame.Position
    
    -- LookVector указывает куда "смотрит" панель (направление Front)
    local lookVector = partCFrame.LookVector
    
    -- Позиция подхода = центр панели + смещение в направлении куда смотрит панель
    -- Мы хотим подойти СПЕРЕДИ панели
    local approachPos = partPos + lookVector * offset
    
    -- Корректируем Y чтобы быть на уровне земли (не в воздухе и не под землёй)
    -- Используем Y позицию базы (около 3-4 над землёй для персонажа)
    local groundY = 3
    
    -- Пробуем определить уровень земли по соседним объектам
    local plotParent = collectZonePart.Parent and collectZonePart.Parent.Parent -- Cash/CashPad -> Plot
    if plotParent then
        local carpet = plotParent:FindFirstChild("Flying Carpet")
        if carpet then
            groundY = carpet.Position.Y + 3
        else
            -- Fallback: используем Y базы
            groundY = 3
        end
    end
    
    approachPos = Vector3.new(approachPos.X, groundY, approachPos.Z)
    
    log("[COLLECT_ZONE] Approach position calculated: " .. string.format("%.1f, %.1f, %.1f", approachPos.X, approachPos.Y, approachPos.Z) ..
        " (LookVector: " .. string.format("%.2f, %.2f, %.2f", lookVector.X, lookVector.Y, lookVector.Z) .. ")")
    
    return approachPos
end

-- Получить позицию ЦЕНТРА Collect Zone (для финального захода)
local function getCollectZoneCenterPosition(collectZonePart)
    if not collectZonePart then return nil end
    
    local partPos = collectZonePart.CFrame.Position
    
    -- Корректируем Y на уровень земли
    local groundY = 3
    local plotParent = collectZonePart.Parent and collectZonePart.Parent.Parent
    if plotParent then
        local carpet = plotParent:FindFirstChild("Flying Carpet")
        if carpet then
            groundY = carpet.Position.Y + 3
        end
    end
    
    return Vector3.new(partPos.X, groundY, partPos.Z)
end

local function getCarpetPositionForPlot(plot)
    if not plot then return nil end
    local map = workspace:FindFirstChild("Map")
    if not map then return nil end
    local carpet = map:FindFirstChild("Carpet")
    if not carpet or not carpet:IsA("BasePart") then return nil end
    local deliveryHitbox = getPlotDeliveryHitbox(plot)
    local plotZ = deliveryHitbox and deliveryHitbox.Position.Z or plot:GetPivot().Position.Z
    return Vector3.new(carpet.Position.X, carpet.Position.Y + 3, plotZ)
end

-- Get max slots count for any plot (counts AnimalPodiums)
local function getPlotMaxSlots(plot)
    if not plot then return 10 end -- default
    local animalPodiums = plot:FindFirstChild("AnimalPodiums")
    if not animalPodiums then return 10 end
    return #animalPodiums:GetChildren()
end

local function countPlotsOnBase()
    local myPlot = findPlayerPlot()
    if not myPlot then return 0, 0 end
    local animalPodiums = myPlot:FindFirstChild("AnimalPodiums")
    if not animalPodiums then return 0, 0 end
    local totalPodiums, usedPodiums = 0, 0
    
    -- Track which brainrot models have been assigned to podiums (to prevent duplicates)
    local assignedModels = {}
    
    -- First pass: collect all podiums and their spawns
    local podiumData = {}
    for _, podium in ipairs(animalPodiums:GetChildren()) do
        totalPodiums = totalPodiums + 1
        local base = podium:FindFirstChild("Base")
        if not base then continue end
        local spawn = base:FindFirstChild("Spawn")
        if not spawn then continue end
        
        podiumData[podium.Name] = {
            spawn = spawn,
            hasBrainrot = false,
            assignedModel = nil
        }
    end
    
    -- NEW METHOD: Find brainrot models directly (works on own base!)
    -- Look for Models in plot that have attributes like Mutation, or are valid brainrots
    for _, child in ipairs(myPlot:GetChildren()) do
        if child:IsA("Model") and 
           child.Name ~= "AnimalPodiums" and 
           child.Name ~= "PlotSign" and 
           child.Name ~= "Building" and 
           child.Name ~= "Decorations" and
           child.Name ~= "Decoration" and
           child.Name ~= "Model" and
           child.Name ~= "LaserHitbox" and
           child.Name ~= "DeliveryHitbox" then
            -- Skip if being carried
            local rootPart = child:FindFirstChild("RootPart")
            if rootPart and rootPart:FindFirstChild("WeldConstraint") then
                continue
            end
            
            -- Check if this is a valid brainrot model:
            -- 1. Has RootPart (all brainrots have this)
            -- 2. Has AnimationController or Humanoid (brainrots have this)
            -- 3. OR has Mutation attribute
            local isValidBrainrot = false
            
            if rootPart then
                local hasAnimController = child:FindFirstChild("AnimationController") ~= nil
                local hasHumanoid = child:FindFirstChildOfClass("Humanoid") ~= nil
                local hasMutation = child:GetAttribute("Mutation") ~= nil
                local hasAnimalOverhead = child:FindFirstChild("AnimalOverhead", true) ~= nil
                
                if hasAnimController or hasHumanoid or hasMutation or hasAnimalOverhead then
                    isValidBrainrot = true
                end
            end
            
            if isValidBrainrot then
                local modelPrimary = child.PrimaryPart or rootPart or child:FindFirstChildWhichIsA("BasePart")
                if modelPrimary then
                    -- Find CLOSEST podium that doesn't have a brainrot yet
                    local closestPodium = nil
                    local closestDist = 15
                    for podiumName, data in pairs(podiumData) do
                        if not data.hasBrainrot and not data.assignedModel then
                            local dist = (modelPrimary.Position - data.spawn.Position).Magnitude
                            if dist < closestDist then
                                closestDist = dist
                                closestPodium = podiumName
                            end
                        end
                    end
                    -- Assign this model to the closest podium
                    if closestPodium then
                        podiumData[closestPodium].hasBrainrot = true
                        podiumData[closestPodium].assignedModel = child
                        assignedModels[child] = closestPodium
                    end
                end
            end
        end
    end
    
    -- Count total used podiums
    for _, data in pairs(podiumData) do
        if data.hasBrainrot then
            usedPodiums = usedPodiums + 1
        end
    end
    
    return usedPodiums, totalPodiums
end

-- Check if brainrot is on which floor (1, 2, or 3)
local function getBrainrotFloor(plot, podiumPosition)
    if not plot then return 1 end
    
    local laserHitbox = plot:FindFirstChild("LaserHitbox")
    if not laserHitbox then return 1 end
    
    local secondFloor = laserHitbox:FindFirstChild("SecondFloor")
    local thirdFloor = laserHitbox:FindFirstChild("ThirdFloor")
    
    -- Check third floor first (Y > 20 approximately based on ThirdFloor Y ~26)
    if thirdFloor then
        local thirdFloorY = thirdFloor.Position.Y
        -- If podium Y is close to third floor level
        if podiumPosition.Y > (thirdFloorY - 8) then
            return 3
        end
    end
    
    -- Check second floor
    if secondFloor then
        -- If podium Y is above ground floor level (around Y > 10)
        if podiumPosition.Y > 8 then
            return 2
        end
    end
    
    return 1
end

-- Определить на каком этаже сейчас находится персонаж
local function getPlayerCurrentFloor()
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return 1 end
    
    local playerY = hrp.Position.Y
    
    -- Примерные границы этажей
    if playerY > 22 then
        return 3
    elseif playerY > 10 then
        return 2
    else
        return 1
    end
end

-- Переменная для отслеживания текущей базы и этажа при навигации
local currentNavigationState = {
    onPlot = nil,       -- На какой базе сейчас находимся
    onFloor = 1,        -- На каком этаже
    targetPlot = nil,   -- К какой базе идём
    targetFloor = 1,    -- На какой этаж идём
}

-- ============ COORDINATION SYSTEM (must be before findBestBrainrot) ============
local FARM_FOLDER = "farm_data"  -- Папка для данных (НЕ ScriptManager/farm!)
local HttpService = game:GetService("HttpService")
local COORDINATION_FILE = FARM_FOLDER .. "/coordination.json"
local COORDINATION_TIMEOUT = 30 -- секунд до истечения резервации

-- Генерация уникального приоритета для этого аккаунта (на основе имени)
local function getAccountPriority()
    local name = LocalPlayer.Name
    local hash = 0
    for i = 1, #name do
        hash = hash + string.byte(name, i) * i
    end
    return hash % 1000
end

local ACCOUNT_PRIORITY = getAccountPriority()

local function ensureFarmFolder()
    pcall(function()
        if not isfolder(FARM_FOLDER) then makefolder(FARM_FOLDER) end
    end)
end

-- Проверить, является ли владелец базы "своим" (в списке аккаунтов)
-- ownerNameOrDisplay может быть DisplayName или Name с таблички
local function isOwnBase(ownerNameOrDisplay)
    if not ownerNameOrDisplay then return false end
    
    -- Теперь в CONFIG.STORAGE_ACCOUNTS есть и Name и DisplayName всех аккаунтов
    if CONFIG.STORAGE_ACCOUNTS and #CONFIG.STORAGE_ACCOUNTS > 0 then
        local ownerLower = string.lower(ownerNameOrDisplay)
        for _, account in ipairs(CONFIG.STORAGE_ACCOUNTS) do
            if string.lower(account) == ownerLower then
                return true
            end
        end
    end
    return false
end

-- Загрузить данные координации
local function loadCoordination()
    local data = {
        reservations = {},
        accountStatus = {}
    }
    pcall(function()
        ensureFarmFolder()
        if isfile(COORDINATION_FILE) then
            local content = readfile(COORDINATION_FILE)
            local loaded = HttpService:JSONDecode(content)
            if loaded then data = loaded end
        end
    end)
    return data
end

-- Функция для красивого форматирования JSON с отступами
local function prettyJSON(data, indent)
    indent = indent or 0
    local spaces = string.rep("    ", indent)
    local nextSpaces = string.rep("    ", indent + 1)
    
    if type(data) == "table" then
        -- Проверяем, это массив или объект
        local isRealArray = true
        local count = 0
        for k, _ in pairs(data) do
            count = count + 1
            if type(k) ~= "number" then
                isRealArray = false
                break
            end
        end
        
        if count == 0 then
            return "{}"
        end
        
        if isRealArray and #data > 0 then
            -- Массив
            local items = {}
            for i, v in ipairs(data) do
                table.insert(items, nextSpaces .. prettyJSON(v, indent + 1))
            end
            return "[\n" .. table.concat(items, ",\n") .. "\n" .. spaces .. "]"
        else
            -- Объект
            local items = {}
            local keys = {}
            for k in pairs(data) do table.insert(keys, k) end
            table.sort(keys, function(a, b)
                local priority = {playerName = 1, lastUpdate = 2, totalBrainrots = 3, totalIncome = 4, totalIncomeFormatted = 5, brainrots = 6, name = 1, income = 2, incomeText = 3, podiumIndex = 4, floor = 5, account = 1, timestamp = 2, brainrotCount = 3, reservations = 1, accountStatus = 2}
                local pa, pb = priority[a] or 100, priority[b] or 100
                if pa ~= pb then return pa < pb end
                return tostring(a) < tostring(b)
            end)
            
            for _, k in ipairs(keys) do
                local v = data[k]
                local key = '"' .. tostring(k) .. '"'
                table.insert(items, nextSpaces .. key .. ": " .. prettyJSON(v, indent + 1))
            end
            return "{\n" .. table.concat(items, ",\n") .. "\n" .. spaces .. "}"
        end
    elseif type(data) == "string" then
        return '"' .. data:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
    elseif type(data) == "number" then
        return tostring(data)
    elseif type(data) == "boolean" then
        return tostring(data)
    else
        return "null"
    end
end

-- Сохранить данные координации (с красивым форматом)
local function saveCoordination(data)
    pcall(function()
        ensureFarmFolder()
        local content = prettyJSON(data)
        writefile(COORDINATION_FILE, content)
    end)
end

-- Очистить устаревшие резервации
local function cleanExpiredReservations(data)
    local now = os.time()
    for key, reservation in pairs(data.reservations) do
        if now - (reservation.timestamp or 0) > COORDINATION_TIMEOUT then
            data.reservations[key] = nil
        end
    end
end

-- Проверить, можем ли мы взять этот brainrot
local function canTakeBrainrot(brainrotKey)
    local data = loadCoordination()
    cleanExpiredReservations(data)
    
    local reservation = data.reservations[brainrotKey]
    if not reservation then return true end
    if reservation.account == LocalPlayer.Name then return true end
    
    -- Проверяем: у кого меньше brainrot'ов - тот имеет приоритет
    local myCount = countPlotsOnBase()
    local theirCount = reservation.brainrotCount or 999
    
    if myCount < theirCount then
        return true -- У нас меньше - мы можем забрать
    elseif myCount > theirCount then
        return false -- У них меньше - они приоритетнее
    else
        -- Одинаковое количество - используем приоритет аккаунта
        local myPriority = ACCOUNT_PRIORITY or 500
        local theirPriority = reservation.priority or 500
        return myPriority < theirPriority
    end
end

-- Зарезервировать brainrot за собой
local function reserveBrainrot(brainrotKey)
    local data = loadCoordination()
    cleanExpiredReservations(data)
    
    local myCount = countPlotsOnBase()
    local myPriority = ACCOUNT_PRIORITY or 500
    local existing = data.reservations[brainrotKey]
    
    if existing and existing.account ~= LocalPlayer.Name then
        local theirCount = existing.brainrotCount or 999
        local theirPriority = existing.priority or 500
        
        -- Можем перехватить только если у нас меньше brainrot'ов
        -- или при равенстве - если у нас меньший приоритет
        if theirCount < myCount then
            return false
        elseif theirCount == myCount and theirPriority <= myPriority then
            return false
        end
    end
    
    data.reservations[brainrotKey] = {
        account = LocalPlayer.Name,
        timestamp = os.time(),
        brainrotCount = myCount,
        priority = myPriority
    }
    
    saveCoordination(data)
    return true
end

-- Освободить резервацию
local function releaseReservation(brainrotKey)
    local data = loadCoordination()
    if data.reservations[brainrotKey] and data.reservations[brainrotKey].account == LocalPlayer.Name then
        data.reservations[brainrotKey] = nil
        saveCoordination(data)
    end
end

-- Проверить, существует ли brainrot на указанном podium И база не наша
local function isBrainrotStillThere(plot, podiumName)
    if not plot or not plot.Parent then return false end
    
    -- Проверяем что база не принадлежит нашему аккаунту
    local ownerName = getPlotOwnerName(plot)
    if isOwnBase(ownerName) then 
        return false -- Это наша база, brainrot "пропал" (украден нами же)
    end
    
    local animalPodiums = plot:FindFirstChild("AnimalPodiums")
    if not animalPodiums then return false end
    
    local podium = animalPodiums:FindFirstChild(podiumName)
    if not podium then return false end
    
    local base = podium:FindFirstChild("Base")
    if not base then return false end
    local spawn = base:FindFirstChild("Spawn")
    if not spawn then return false end
    
    -- Method 1: Check Attachment in spawn
    local animalOverhead = nil
    local spawnAttachment = spawn:FindFirstChild("Attachment")
    if spawnAttachment then
        animalOverhead = spawnAttachment:FindFirstChild("AnimalOverhead")
    end
    
    -- Method 2: Search all descendants of spawn
    if not animalOverhead then
        for _, desc in ipairs(spawn:GetDescendants()) do
            if desc.Name == "AnimalOverhead" and desc:IsA("BillboardGui") then
                animalOverhead = desc
                break
            end
        end
    end
    
    -- Method 3: Search in nearby brainrot model (for other players' bases!)
    -- AnimalOverhead is CLIENT-SIDE and may be in the brainrot model, not in spawn
    if not animalOverhead then
        local closestDist = 15
        for _, child in ipairs(plot:GetChildren()) do
            if child:IsA("Model") and child.Name ~= "AnimalPodiums" and 
               child.Name ~= "PlotSign" and child.Name ~= "Building" and 
               child.Name ~= "Decorations" then
                -- Check if model has WeldConstraint (being carried)
                local rootPart = child:FindFirstChild("RootPart")
                if rootPart and rootPart:FindFirstChild("WeldConstraint") then
                    continue -- Being carried - skip
                end
                
                local overhead = child:FindFirstChild("AnimalOverhead", true)
                if overhead and overhead:IsA("BillboardGui") then
                    local modelPrimary = child.PrimaryPart or child:FindFirstChild("RootPart") or child:FindFirstChildWhichIsA("BasePart")
                    if modelPrimary then
                        local dist = (modelPrimary.Position - spawn.Position).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            animalOverhead = overhead
                        end
                    end
                end
            end
        end
    end
    
    -- Method 4: Check via ProximityPrompt (server-side, reliable for other players)
    if not animalOverhead then
        local promptAttachment = spawn:FindFirstChild("PromptAttachment")
        if promptAttachment then
            for _, desc in ipairs(promptAttachment:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and desc.ActionText == "Steal" and desc.ObjectText ~= "" then
                    -- Found steal prompt with brainrot name - brainrot exists!
                    return true
                end
            end
        end
    end
    
    if not animalOverhead then return false end
    
    -- Проверяем что есть Generation label с /s (значит есть brainrot)
    local generationLabel = animalOverhead:FindFirstChild("Generation")
    if not generationLabel or not generationLabel:IsA("TextLabel") then return false end
    if not generationLabel.Text:find("/s") then return false end
    
    -- Проверяем что не украден
    local stolenLabel = animalOverhead:FindFirstChild("Stolen")
    if stolenLabel and stolenLabel.Visible then return false end
    
    return true
end

-- Найти альтернативный brainrot на той же базе (только если база не наша)
local function findAlternativeBrainrotOnPlot(plot, minIncome)
    if not plot or not plot.Parent then 
        log("findAlternativeBrainrotOnPlot: plot is nil or destroyed")
        return nil 
    end
    
    -- Проверяем что база не принадлежит нашему аккаунту
    local ownerName = getPlotOwnerName(plot)
    if isOwnBase(ownerName) then 
        log("findAlternativeBrainrotOnPlot: plot belongs to own account")
        return nil -- Это наша база, не ищем здесь
    end
    
    log("findAlternativeBrainrotOnPlot: Searching on plot " .. plot.Name .. " (owner: " .. tostring(ownerName) .. ")")
    
    local bestBrainrot, bestValue = nil, minIncome
    
    -- ========== СПОСОБ 1: Поиск моделей напрямую в plot ==========
    -- НОВЫЙ СПОСОБ: Используем calculateBrainrotGeneration вместо GUI!
    log("findAlternativeBrainrotOnPlot: Method 1 - checking models in plot (NEW: calculateBrainrotGeneration)")
    for _, child in ipairs(plot:GetChildren()) do
        if child.Name == "AnimalPodiums" or child.Name == "PlotSign" or
           child.Name == "Building" or child.Name == "Decorations" or
           child.Name == "Decoration" or child.Name == "LaserHitbox" or
           child.Name == "DeliveryHitbox" or child.Name == "Model" then
            continue
        end
        
        if child:IsA("Model") then
            local rootPart = child:FindFirstChild("RootPart")
            if rootPart and rootPart:FindFirstChild("WeldConstraint") then
                continue
            end
            
            -- Проверяем статус через AnimalOverhead (fusing/stolen)
            local animalOverhead = child:FindFirstChild("AnimalOverhead", true)
            if animalOverhead and animalOverhead:IsA("BillboardGui") then
                if isAnimalFusing(animalOverhead) then continue end
                
                local stolenLabel = animalOverhead:FindFirstChild("Stolen")
                if stolenLabel and stolenLabel.Visible then continue end
            end
            
            -- НОВЫЙ СПОСОБ: Рассчитываем Generation из атрибутов модели!
            local generationValue, brainrotName, mutation, traits = calculateBrainrotGeneration(child)
            
            if generationValue > 0 and generationValue > bestValue then
                local generationText = "$" .. formatPrice(generationValue) .. "/s"
                
                local modelPos = nil
                local modelPrimary = child.PrimaryPart or child:FindFirstChild("RootPart") or child:FindFirstChildWhichIsA("BasePart")
                if modelPrimary then
                    modelPos = modelPrimary.Position
                end
                
                local foundPodium, foundSpawn = nil, nil
                local animalPodiums = plot:FindFirstChild("AnimalPodiums")
                if animalPodiums and modelPos then
                    local closestDist = 15
                    for _, podium in ipairs(animalPodiums:GetChildren()) do
                        local base = podium:FindFirstChild("Base")
                        if base then
                            local spawn = base:FindFirstChild("Spawn")
                            if spawn then
                                local dist = (spawn.Position - modelPos).Magnitude
                                if dist < closestDist then
                                    closestDist = dist
                                    foundPodium = podium
                                    foundSpawn = spawn
                                end
                            end
                        end
                    end
                end
                
                if foundPodium and foundSpawn then
                    local brainrotKey = plot.Name .. "_" .. tostring(foundPodium.Name)
                    if canTakeBrainrot(brainrotKey) then
                        local podiumPos = foundSpawn.Position
                        local brainrotFloor = getBrainrotFloor(plot, podiumPos)
                        
                        bestValue = generationValue
                        bestBrainrot = {
                            name = brainrotName,
                            value = generationValue,
                            text = generationText,
                            plot = plot,
                            podium = foundPodium,
                            spawn = foundSpawn,
                            ownerName = ownerName or "Unknown",
                            podiumIndex = foundPodium.Name,
                            floor = brainrotFloor,
                            key = brainrotKey,
                        }
                    end
                end
            end
        end
    end
    
    log("findAlternativeBrainrotOnPlot: Method 1 complete, best so far: " .. (bestBrainrot and bestBrainrot.name or "none"))
    
    -- ========== СПОСОБ 2: Поиск в AnimalPodiums ==========
    log("findAlternativeBrainrotOnPlot: Method 2 - checking AnimalPodiums")
    local animalPodiums = plot:FindFirstChild("AnimalPodiums")
    if not animalPodiums then 
        log("findAlternativeBrainrotOnPlot: No AnimalPodiums folder")
        if bestBrainrot then reserveBrainrot(bestBrainrot.key) end
        return bestBrainrot 
    end
    
    for _, podium in ipairs(animalPodiums:GetChildren()) do
        local base = podium:FindFirstChild("Base")
        if not base then continue end
        local spawn = base:FindFirstChild("Spawn")
        if not spawn then continue end
        
        -- ========== НОВЫЙ СПОСОБ: ищем модель brainrot и рассчитываем Generation ==========
        local animalOverhead = nil
        local brainrotName = nil
        local generationValue = 0
        local generationText = ""
        local foundBrainrotModel = nil
        
        -- Ищем модель brainrot рядом со spawn
        local closestModelDist = 15
        for _, child in ipairs(plot:GetChildren()) do
            if child.Name == "AnimalPodiums" or child.Name == "PlotSign" or 
               child.Name == "Building" or child.Name == "Decorations" or 
               child.Name == "Decoration" or child.Name == "Model" then
                continue
            end
            
            if child:IsA("Model") then
                local rootPart = child:FindFirstChild("RootPart")
                if rootPart and rootPart:FindFirstChild("WeldConstraint") then
                    continue
                end
                
                local modelPrimary = child.PrimaryPart or child:FindFirstChild("RootPart") or child:FindFirstChildWhichIsA("BasePart")
                if modelPrimary then
                    local dist = (modelPrimary.Position - spawn.Position).Magnitude
                    if dist < closestModelDist then
                        closestModelDist = dist
                        foundBrainrotModel = child
                        local overhead = child:FindFirstChild("AnimalOverhead", true)
                        if overhead and overhead:IsA("BillboardGui") then
                            animalOverhead = overhead
                        end
                    end
                end
            end
        end
        
        -- Если нашли AnimalOverhead - проверяем статус (fusing/stolen)
        if animalOverhead then
            if isAnimalFusing(animalOverhead) then continue end
            
            local stolenLabel = animalOverhead:FindFirstChild("Stolen")
            if stolenLabel and stolenLabel.Visible then continue end
        end
        
        -- НОВЫЙ СПОСОБ: Рассчитываем Generation из атрибутов модели!
        if foundBrainrotModel then
            local calcGen, calcName, calcMutation, calcTraits = calculateBrainrotGeneration(foundBrainrotModel)
            if calcGen > 0 then
                generationValue = calcGen
                generationText = "$" .. formatPrice(calcGen) .. "/s"
                brainrotName = calcName or foundBrainrotModel.Name
            end
        end
        
        -- FALLBACK: ProximityPrompt + base generation
        if generationValue <= 0 then
            for _, desc in ipairs(spawn:GetDescendants()) do
                if desc:IsA("ProximityPrompt") then
                    if desc.ActionText == "Steal" and desc.ObjectText and desc.ObjectText ~= "" then
                        brainrotName = desc.ObjectText
                        break
                    end
                end
            end
            
            if brainrotName and brainrotName ~= "" then
                local dataGeneration = getAnimalGeneration(brainrotName)
                if dataGeneration > 0 then
                    generationValue = dataGeneration
                    generationText = "$" .. formatPrice(dataGeneration) .. "/s"
                elseif FALLBACK_GENERATIONS[brainrotName] then
                    generationValue = FALLBACK_GENERATIONS[brainrotName]
                    generationText = "$" .. formatPrice(generationValue) .. "/s"
                end
            end
        end
        
        -- Skip if no valid data found
        if generationValue <= 0 or generationValue <= bestValue then continue end
        if not brainrotName or brainrotName == "" then brainrotName = "Unknown" end
        
        -- Проверяем, можем ли мы взять этот brainrot (система координации)
        local brainrotKey = plot.Name .. "_" .. tostring(podium.Name)
        if not canTakeBrainrot(brainrotKey) then continue end

        local podiumPos = spawn.Position
        local brainrotFloor = getBrainrotFloor(plot, podiumPos)

        bestValue = generationValue
        bestBrainrot = {
            name = brainrotName,
            value = generationValue,
            text = generationText,
            plot = plot,
            podium = podium,
            spawn = spawn,
            ownerName = ownerName or "Unknown",
            podiumIndex = podium.Name,
            floor = brainrotFloor,
            key = brainrotKey,
        }
        log("findAlternativeBrainrotOnPlot: Found candidate - " .. brainrotName .. " value=" .. tostring(generationValue))
    end
    
    if bestBrainrot then
        log("findAlternativeBrainrotOnPlot: RESULT - Found " .. bestBrainrot.name .. " on podium " .. bestBrainrot.podiumIndex)
        reserveBrainrot(bestBrainrot.key)
    else
        log("findAlternativeBrainrotOnPlot: RESULT - No brainrot found")
    end
    
    return bestBrainrot
end

-- ============ END COORDINATION (part 1) ============

-- Проверяет находится ли brainrot в процессе fusing/crafting (НЕ доступен для кражи)
-- ВАЖНО: статус "stolen" НЕ блокирует полностью - brainrot ещё на подиуме
local function isAnimalFusing(animalOverhead)
    if not animalOverhead then return false end
    local stolenLabel = animalOverhead:FindFirstChild("Stolen")
    if not stolenLabel or not stolenLabel:IsA("TextLabel") then return false end
    local stolenText = string.lower(tostring(stolenLabel.Text or ""))
    -- Блокируем только fusing/crafting когда brainrot в машине
    return stolenLabel.Visible and (stolenText == "fusing" or stolenText == "crafting" or stolenText == "in machine" or stolenText == "in fuse")
end

-- ============ NEW: SYNCHRONIZER-BASED BEST BRAINROT SEARCH ============
-- Uses Synchronizer API to find best brainrot on server (REAL-TIME DATA!)
-- This is much more reliable than GUI-based search!
local function findBestBrainrotViaSynchronizer()
    if not Synchronizer or not AnimalsShared then
        log("[SyncFind] Synchronizer or AnimalsShared not available")
        return nil
    end
    
    log("[SyncFind] === findBestBrainrotViaSynchronizer START ===")
    
    local myPlot = findPlayerPlot()
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    
    local best = {Gen = CONFIG.MIN_INCOME, Plot = nil, Slot = nil, Name = "None", Info = nil}
    
    -- Load targets if available
    local hasTargets = false
    local targets = {}
    if _G.FarmConfig and _G.FarmConfig.getTargets then
        targets = _G.FarmConfig.getTargets() or {}
        hasTargets = #targets > 0
    end
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        -- Skip own plot
        if myPlot and plot.Name == myPlot.Name then continue end
        if plot.Name == LocalPlayer.Name then continue end
        
        -- Check if base is "own" (belongs to our accounts)
        local ownerName = getPlotOwnerName(plot)
        if isOwnBase(ownerName) then
            log("[SyncFind] Skipping own base: " .. ownerName)
            continue
        end
        
        -- Check targets if enabled
        if hasTargets then
            local isTargeted = false
            local ownerLower = string.lower(ownerName)
            
            for _, targetName in ipairs(targets) do
                if string.lower(targetName) == ownerLower then
                    isTargeted = true
                    break
                end
            end
            
            -- Also check by Username -> DisplayName mapping
            if not isTargeted then
                for _, player in ipairs(Players:GetPlayers()) do
                    local playerNameLower = string.lower(player.Name)
                    local playerDisplayLower = string.lower(player.DisplayName)
                    
                    if playerDisplayLower == ownerLower then
                        for _, targetName in ipairs(targets) do
                            if string.lower(targetName) == playerNameLower then
                                isTargeted = true
                                break
                            end
                        end
                        if isTargeted then break end
                    end
                end
            end
            
            if not isTargeted then
                log("[SyncFind] Skipping non-target: " .. ownerName)
                continue
            end
        end
        
        -- Get brainrot data via Synchronizer
        local channel = nil
        pcall(function()
            channel = Synchronizer:Get(plot.Name)
        end)
        
        if not channel then continue end
        
        local animalList = nil
        pcall(function()
            animalList = channel:Get("AnimalList")
        end)
        
        if not animalList then continue end
        
        for slot, info in pairs(animalList) do
            if type(info) == "table" and info.Index then
                local gen = 0
                pcall(function()
                    gen = AnimalsShared:GetGeneration(info.Index, info.Mutation, info.Traits, nil) or 0
                end)
                
                if gen > best.Gen then
                    -- Check coordination (can we take this brainrot?)
                    local brainrotKey = plot.Name .. "_" .. tostring(slot)
                    if canTakeBrainrot(brainrotKey) then
                        -- Get spawn position for floor detection
                        local floor = 1
                        local spawn = nil
                        local podium = nil
                        local animalPodiums = plot:FindFirstChild("AnimalPodiums")
                        if animalPodiums then
                            podium = animalPodiums:FindFirstChild(tostring(slot))
                            if podium then
                                local base = podium:FindFirstChild("Base")
                                if base then
                                    spawn = base:FindFirstChild("Spawn")
                                    if spawn then
                                        floor = getBrainrotFloor(plot, spawn.Position)
                                    end
                                end
                            end
                        end
                        
                        best = {
                            Gen = gen,
                            Plot = plot,
                            Slot = slot,
                            Name = info.Index,
                            Info = info,
                            Floor = floor,
                            Spawn = spawn,
                            Podium = podium,
                            Key = brainrotKey,
                            OwnerName = ownerName
                        }
                        
                        log("[SyncFind] New best: " .. info.Index .. " = $" .. formatPrice(gen) .. "/s on plot " .. plot.Name .. " slot " .. tostring(slot))
                    end
                end
            end
        end
    end
    
    if best.Gen > CONFIG.MIN_INCOME and best.Plot then
        log("[SyncFind] RESULT: " .. best.Name .. " = $" .. formatPrice(best.Gen) .. "/s on " .. best.Plot.Name)
        
        -- Convert to standard brainrot format used by farm.lua
        return {
            name = best.Name,
            value = best.Gen,
            text = "$" .. formatPrice(best.Gen) .. "/s",
            plot = best.Plot,
            podium = best.Podium,
            spawn = best.Spawn,
            ownerName = best.OwnerName,
            podiumIndex = tostring(best.Slot),
            floor = best.Floor,
            key = best.Key,
        }
    end
    
    log("[SyncFind] RESULT: No brainrot found above MIN_INCOME")
    return nil
end
-- ============ END SYNCHRONIZER-BASED SEARCH ============

local function findBestBrainrot()
    log("========== findBestBrainrot() START ==========")
    
    -- TRY SYNCHRONIZER FIRST (MUCH MORE RELIABLE AND FASTER!)
    if SynchronizerReady then
        local syncResult = findBestBrainrotViaSynchronizer()
        if syncResult then
            log("findBestBrainrot: Found via Synchronizer: " .. syncResult.name .. " = " .. syncResult.text)
            reserveBrainrot(syncResult.key)
            return syncResult
        end
        log("findBestBrainrot: Synchronizer returned nil, falling back to old method")
    end
    
    -- FALLBACK: Old GUI-based method
    local myPlot = findPlayerPlot()
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then 
        log("ERROR: Plots folder not found in workspace", "ERROR")
        return nil 
    end
    local bestBrainrot, bestValue = nil, CONFIG.MIN_INCOME
    local myBrainrotCount = countPlotsOnBase()
    local bestKey = nil
    
    log("MIN_INCOME threshold: " .. tostring(CONFIG.MIN_INCOME))
    log("My plot: " .. (myPlot and myPlot.Name or "NOT FOUND"))
    
    -- Count cache entries properly
    local cacheCount = 0
    for _ in pairs(AnimalGenerationCache) do cacheCount = cacheCount + 1 end
    log("AnimalDataLoaded: " .. tostring(AnimalDataLoaded) .. ", cache size: " .. tostring(cacheCount))
    
    -- Загружаем текущий список целей (перезагружается из файла)
    local hasTargets = false
    local targets = {}
    if _G.FarmConfig and _G.FarmConfig.getTargets then
        targets = _G.FarmConfig.getTargets() or {}
        hasTargets = #targets > 0
    end
    
    log("Has targets: " .. tostring(hasTargets) .. ", target count: " .. #targets)
    if hasTargets then
        log("Targets: " .. table.concat(targets, ", "))
    end
    
    -- Log ALL plot owners on server
    local allOwners = {}
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local owner = getPlotOwnerName(plot)
        if owner and owner ~= "" then
            table.insert(allOwners, owner)
        end
    end
    log("ALL plot owners on server: " .. table.concat(allOwners, ", "))
    
    -- Log all players on server for comparison
    local playerNames = {}
    for _, player in ipairs(Players:GetPlayers()) do
        table.insert(playerNames, player.Name .. " (" .. player.DisplayName .. ")")
    end
    log("ALL players on server: " .. table.concat(playerNames, ", "))
    
    local plotCount = 0
    local scannedPlots = 0
    local skippedOwn = 0
    local skippedNotTarget = 0

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        plotCount = plotCount + 1
        if plot == myPlot then continue end
        
        -- Проверяем, не является ли владелец базы "своим"
        local ownerName = getPlotOwnerName(plot)
        local isOwn = isOwnBase(ownerName)
        
        if isOwn then 
            skippedOwn = skippedOwn + 1
            logDetailed("Skipped own base: " .. ownerName .. " (plot: " .. plot.Name .. ")")
            continue -- Пропускаем базы своих аккаунтов
        end
        
        -- Если есть список целей - проверяем, есть ли владелец в нём
        if hasTargets then
            local isTargeted = false
            local ownerLower = string.lower(ownerName)
            
            for _, targetName in ipairs(targets) do
                local targetLower = string.lower(targetName)
                -- Check if target matches owner (DisplayName shown on base)
                if ownerLower == targetLower then
                    isTargeted = true
                    break
                end
            end
            
            -- Also check by player Username -> DisplayName mapping
            -- Because target list contains usernames, but bases show DisplayNames
            if not isTargeted then
                for _, player in ipairs(Players:GetPlayers()) do
                    local playerNameLower = string.lower(player.Name)
                    local playerDisplayLower = string.lower(player.DisplayName)
                    
                    -- If this player's DisplayName matches the base owner
                    if playerDisplayLower == ownerLower then
                        -- Check if this player's Username is in targets
                        for _, targetName in ipairs(targets) do
                            if string.lower(targetName) == playerNameLower then
                                isTargeted = true
                                logDetailed("Target match: " .. targetName .. " (username) = " .. player.DisplayName .. " (displayname) = " .. ownerName .. " (base)")
                                break
                            end
                        end
                        if isTargeted then break end
                    end
                end
            end
            
            if not isTargeted then
                skippedNotTarget = skippedNotTarget + 1
                logDetailed("Skipped non-target base: " .. ownerName .. " (plot: " .. plot.Name .. ")")
                continue -- Пропускаем не-целевые базы
            end
        end
        
        scannedPlots = scannedPlots + 1
        log(">>> Scanning plot: " .. plot.Name .. " (owner: " .. ownerName .. ")")
        
        -- ========== СПОСОБ 1: Поиск моделей напрямую в plot (как в autosteal.lua) ==========
        -- brainrots с AnimalOverhead внутри модели ТАКЖЕ могут быть украдены!
        -- НОВЫЙ СПОСОБ: Используем calculateBrainrotGeneration вместо GUI!
        for _, child in ipairs(plot:GetChildren()) do
            -- Пропускаем служебные папки
            if child.Name == "AnimalPodiums" or child.Name == "PlotSign" or
               child.Name == "Building" or child.Name == "Decorations" or
               child.Name == "Decoration" or child.Name == "LaserHitbox" or
               child.Name == "DeliveryHitbox" or child.Name == "Model" then
                continue
            end
            
            if child:IsA("Model") then
                -- Проверяем есть ли WeldConstraint (признак что brainrot несут)
                local rootPart = child:FindFirstChild("RootPart")
                if rootPart then
                    local weldConstraint = rootPart:FindFirstChild("WeldConstraint")
                    if weldConstraint then
                        continue -- Этот brainrot кто-то несёт - пропускаем
                    end
                end
                
                -- Ищем AnimalOverhead в модели (для проверки статуса)
                local animalOverhead = child:FindFirstChild("AnimalOverhead", true)
                if animalOverhead and animalOverhead:IsA("BillboardGui") then
                    -- Проверяем статус - пропускаем если fusing/crafting
                    if isAnimalFusing(animalOverhead) then
                        continue
                    end
                    
                    -- Проверяем stolen - пропускаем если кто-то уже крадёт
                    local stolenLabel = animalOverhead:FindFirstChild("Stolen")
                    if stolenLabel and stolenLabel.Visible then continue end
                end
                
                -- НОВЫЙ СПОСОБ: Рассчитываем Generation из атрибутов модели!
                local generationValue, brainrotName, mutation, traits = calculateBrainrotGeneration(child)
                
                if generationValue > 0 and generationValue > bestValue then
                    local generationText = "$" .. formatPrice(generationValue) .. "/s"
                    
                    -- Ищем связанный подиум по позиции модели
                    local modelPos = nil
                    local modelPrimary = child.PrimaryPart or child:FindFirstChild("RootPart") or child:FindFirstChildWhichIsA("BasePart")
                    if modelPrimary then
                        modelPos = modelPrimary.Position
                    end
                    
                    local foundPodium = nil
                    local foundSpawn = nil
                    local animalPodiums = plot:FindFirstChild("AnimalPodiums")
                    if animalPodiums and modelPos then
                        -- Ищем ближайший подиум к модели
                        local closestDist = 15 -- Увеличенный радиус поиска
                        for _, podium in ipairs(animalPodiums:GetChildren()) do
                            local base = podium:FindFirstChild("Base")
                            if base then
                                local spawn = base:FindFirstChild("Spawn")
                                if spawn then
                                    local dist = (spawn.Position - modelPos).Magnitude
                                    if dist < closestDist then
                                        closestDist = dist
                                        foundPodium = podium
                                        foundSpawn = spawn
                                    end
                                end
                            end
                        end
                    end
                    
                    -- Если нашли подиум - можем украсть!
                    if foundPodium and foundSpawn then
                        local brainrotKey = plot.Name .. "_" .. tostring(foundPodium.Name)
                        if canTakeBrainrot(brainrotKey) then
                            local podiumPos = foundSpawn.Position
                            local brainrotFloor = getBrainrotFloor(plot, podiumPos)
                            
                            bestValue = generationValue
                            bestKey = brainrotKey
                            bestBrainrot = {
                                name = brainrotName,
                                value = generationValue,
                                text = generationText,
                                plot = plot,
                                podium = foundPodium,
                                spawn = foundSpawn,
                                ownerName = ownerName or "Unknown",
                                podiumIndex = foundPodium.Name,
                                floor = brainrotFloor,
                                key = brainrotKey,
                            }
                            
                            local traitsStr = traits and (#traits > 0) and (" traits=" .. table.concat(traits, ",")) or ""
                            log("  [Method1-NEW] Found: " .. brainrotName .. " = " .. generationText .. (mutation and (" mutation=" .. mutation) or "") .. traitsStr)
                        end
                    end
                end
            end
        end
        
        -- ========== СПОСОБ 2: Поиск в AnimalPodiums ==========
        local animalPodiums = plot:FindFirstChild("AnimalPodiums")
        if not animalPodiums then 
            logDetailed("  No AnimalPodiums folder in plot " .. plot.Name)
            continue 
        end
        
        local podiumCount = #animalPodiums:GetChildren()
        logDetailed("  AnimalPodiums found with " .. podiumCount .. " podiums")

        for _, podium in ipairs(animalPodiums:GetChildren()) do
            local base = podium:FindFirstChild("Base")
            if not base then 
                logDetailed("    Podium " .. podium.Name .. ": No Base")
                continue 
            end
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then 
                logDetailed("    Podium " .. podium.Name .. ": No Spawn in Base")
                continue 
            end
            
            logDetailed("    Podium " .. podium.Name .. ": Scanning spawn...")
            
            -- ========== УЛУЧШЕННЫЙ ПОИСК AnimalOverhead ==========
            local animalOverhead = nil
            local brainrotName = nil
            local generationValue = 0
            local generationText = ""
            local foundViaOverhead = false
            local foundMethod = "none"
            
            -- Method 2a: Ищем во ВСЕХ Attachment в spawn (не только именованном)
            for _, child in ipairs(spawn:GetChildren()) do
                if child:IsA("Attachment") and child.Name ~= "PromptAttachment" then
                    local overhead = child:FindFirstChild("AnimalOverhead")
                    if overhead and overhead:IsA("BillboardGui") then
                        animalOverhead = overhead
                        foundMethod = "2a-Attachment"
                        break
                    end
                end
            end
            
            -- Method 2b: Поиск по всем descendants spawn
            if not animalOverhead then
                for _, desc in ipairs(spawn:GetDescendants()) do
                    if desc.Name == "AnimalOverhead" and desc:IsA("BillboardGui") then
                        animalOverhead = desc
                        foundMethod = "2b-Descendants"
                        break
                    end
                end
            end
            
            -- Method 2c: Ищем в ближайшей модели brainrot И СОХРАНЯЕМ МОДЕЛЬ
            local foundBrainrotModel = nil
            if not animalOverhead then
                local closestModelDist = 15
                for _, child in ipairs(plot:GetChildren()) do
                    if child.Name == "AnimalPodiums" or child.Name == "PlotSign" or 
                       child.Name == "Building" or child.Name == "Decorations" or 
                       child.Name == "Decoration" or child.Name == "Model" then
                        continue
                    end
                    
                    if child:IsA("Model") then
                        local rootPart = child:FindFirstChild("RootPart")
                        if rootPart and rootPart:FindFirstChild("WeldConstraint") then
                            continue
                        end
                        
                        local modelPrimary = child.PrimaryPart or child:FindFirstChild("RootPart") or child:FindFirstChildWhichIsA("BasePart")
                        if modelPrimary then
                            local dist = (modelPrimary.Position - spawn.Position).Magnitude
                            if dist < closestModelDist then
                                closestModelDist = dist
                                foundBrainrotModel = child
                                local overhead = child:FindFirstChild("AnimalOverhead", true)
                                if overhead and overhead:IsA("BillboardGui") then
                                    animalOverhead = overhead
                                    foundMethod = "2c-NearbyModel(" .. child.Name .. ")"
                                end
                            end
                        end
                    end
                end
            else
                -- Если нашли AnimalOverhead через 2a/2b, ищем модель рядом
                local closestModelDist = 15
                for _, child in ipairs(plot:GetChildren()) do
                    if child.Name == "AnimalPodiums" or child.Name == "PlotSign" or 
                       child.Name == "Building" or child.Name == "Decorations" or 
                       child.Name == "Decoration" or child.Name == "Model" then
                        continue
                    end
                    if child:IsA("Model") then
                        local modelPrimary = child.PrimaryPart or child:FindFirstChild("RootPart") or child:FindFirstChildWhichIsA("BasePart")
                        if modelPrimary then
                            local dist = (modelPrimary.Position - spawn.Position).Magnitude
                            if dist < closestModelDist then
                                closestModelDist = dist
                                foundBrainrotModel = child
                            end
                        end
                    end
                end
            end
            
            -- Если нашли AnimalOverhead - проверяем статус (fusing/stolen)
            if animalOverhead then
                logDetailed("      Found AnimalOverhead via " .. foundMethod)
                
                -- Проверяем статус - пропускаем если fusing/crafting
                if isAnimalFusing(animalOverhead) then 
                    logDetailed("      SKIP: is fusing/crafting")
                    continue 
                end
                
                -- Проверяем stolen
                local stolenLabel = animalOverhead:FindFirstChild("Stolen")
                if stolenLabel and stolenLabel.Visible then 
                    logDetailed("      SKIP: Stolen label visible (text: " .. tostring(stolenLabel.Text) .. ")")
                    continue 
                end
            end
            
            -- ========== НОВЫЙ СПОСОБ: Рассчитываем Generation из атрибутов модели! ==========
            if foundBrainrotModel then
                local calcGen, calcName, calcMutation, calcTraits = calculateBrainrotGeneration(foundBrainrotModel)
                if calcGen > 0 then
                    generationValue = calcGen
                    generationText = "$" .. formatPrice(calcGen) .. "/s"
                    brainrotName = calcName or foundBrainrotModel.Name
                    foundViaOverhead = true -- Mark as found
                    
                    local traitsStr = calcTraits and (#calcTraits > 0) and (" traits=" .. table.concat(calcTraits, ",")) or ""
                    logDetailed("      [NEW] calculateBrainrotGeneration: " .. brainrotName .. " = " .. formatPrice(calcGen) .. (calcMutation and (" mutation=" .. calcMutation) or "") .. traitsStr)
                end
            end
            
            -- ========== FALLBACK: ProximityPrompt + base generation (для случаев когда нет модели) ==========
            if not foundViaOverhead or generationValue <= 0 then
                logDetailed("      Trying FALLBACK: ProximityPrompt search...")
                
                -- Look for ProximityPrompt with "Steal" action
                for _, desc in ipairs(spawn:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") then
                        if desc.ActionText == "Steal" and desc.ObjectText and desc.ObjectText ~= "" then
                            brainrotName = desc.ObjectText
                            logDetailed("      Found Steal prompt: brainrotName = " .. brainrotName)
                            break
                        end
                    end
                end
                
                -- Get BASE income from Animals data (without modifiers)
                if brainrotName and brainrotName ~= "" then
                    local dataGeneration = getAnimalGeneration(brainrotName)
                    if dataGeneration > 0 then
                        generationValue = dataGeneration
                        generationText = "$" .. formatPrice(dataGeneration) .. "/s"
                        logDetailed("      FALLBACK: base generation = " .. formatPrice(dataGeneration))
                    elseif FALLBACK_GENERATIONS[brainrotName] then
                        generationValue = FALLBACK_GENERATIONS[brainrotName]
                        generationText = "$" .. formatPrice(generationValue) .. "/s"
                        logDetailed("      FALLBACK: from FALLBACK_GENERATIONS = " .. formatPrice(generationValue))
                    end
                end
            end
            
            -- Skip if no valid data found
            if generationValue <= 0 then
                logDetailed("      SKIP: generationValue = 0")
                continue
            end
            if generationValue <= bestValue then
                logDetailed("      SKIP: generationValue (" .. generationValue .. ") <= bestValue (" .. bestValue .. ")")
                continue
            end
            if not brainrotName or brainrotName == "" then brainrotName = "Unknown" end
            
            -- Проверяем, можем ли мы взять этот brainrot (система координации)
            local brainrotKey = plot.Name .. "_" .. tostring(podium.Name)
            if not canTakeBrainrot(brainrotKey) then
                logDetailed("      SKIP: canTakeBrainrot returned false for " .. brainrotKey)
                continue
            end
            
            -- Determine floor
            local podiumPos = spawn.Position
            local brainrotFloor = getBrainrotFloor(plot, podiumPos)
            
            log("  !!! FOUND CANDIDATE: " .. brainrotName .. " value=" .. generationValue .. " on podium " .. podium.Name)

            bestValue = generationValue
            bestKey = brainrotKey
            bestBrainrot = {
                name = brainrotName,
                value = generationValue,
                text = generationText,
                plot = plot,
                podium = podium,
                spawn = spawn,
                ownerName = ownerName or "Unknown",
                podiumIndex = podium.Name,
                floor = brainrotFloor,
                key = brainrotKey,
            }
        end
    end
    
    -- Log summary
    log("---------- SEARCH SUMMARY ----------")
    log("Total plots: " .. plotCount .. ", Scanned: " .. scannedPlots)
    log("Skipped own: " .. skippedOwn .. ", Skipped non-target: " .. skippedNotTarget)
    
    -- СРАЗУ резервируем найденный brainrot чтобы другие аккаунты не выбрали его
    if bestBrainrot and bestKey then
        reserveBrainrot(bestKey)
        log("RESULT: Found best brainrot '" .. bestBrainrot.name .. "' value=" .. bestBrainrot.value .. " on " .. bestBrainrot.ownerName .. "'s base, podium " .. bestBrainrot.podiumIndex)
    else
        log("RESULT: No brainrot found!")
    end
    
    log("========== findBestBrainrot() END ==========")
    
    return bestBrainrot
end

-- ============ PATHFINDING SYSTEM (PathfindingService) ============
-- Полноценная система навигации с использованием Roblox PathfindingService
-- Автоматически обходит препятствия: Shop, FuseMachine, AdventCalendar, Events и др.

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

-- Конфигурация pathfinding
local PATHFINDING_CONFIG = {
    AgentRadius = 4,          -- Радиус агента (увеличен для обхода крупных объектов)
    AgentHeight = 6,          -- Высота агента
    AgentCanJump = true,      -- Разрешить прыжки
    AgentCanClimb = false,    -- Запретить лазание по TrussParts
    WaypointSpacing = 3,      -- Расстояние между waypoints (уменьшено для точности)
    
    -- Стоимость прохода через разные зоны
    Costs = {
        Water = math.huge,    -- Вода непроходима
        Neon = 20,            -- Neon материал избегаем сильнее
    },
    
    -- Логирование (основное управление через LOG_PATHFINDING_VERBOSE в начале файла)
    LOG_PATHFINDING = false,   -- ОТКЛЮЧЕНО
    
    -- Таймауты (УСКОРЕНО)
    WAYPOINT_TIMEOUT = 6,     -- Секунд на один waypoint (уменьшено для быстрого перестроения)
    PATH_TIMEOUT = 45,        -- Общий таймаут на весь путь
    STUCK_THRESHOLD = 1.0,    -- Секунд без движения = застрял (УСКОРЕНО с 2 до 1)
    REBUILD_DELAY = 0.15,     -- Задержка перед перестроением маршрута (БЫСТРО)
    
    -- Параметры движения
    ARRIVAL_DISTANCE = 5,     -- Считаем что дошли если ближе этого расстояния
    JUMP_ON_STUCK = true,     -- Прыгать при застревании
    
    -- Лазеры (laser gate)
    LASER_WAIT_TIMEOUT = 8,   -- Максимум ждать пропадания лазеров (секунд)
}

-- Статистика pathfinding для логирования
local pathfindingStats = {
    totalPaths = 0,
    successfulPaths = 0,
    failedPaths = 0,
    fallbackPaths = 0,
    lastPathTime = 0,
    lastPathWaypoints = 0,
}

-- Функция для логирования pathfinding
local function logPathfinding(message, level)
    if not PATHFINDING_CONFIG.LOG_PATHFINDING then return end
    log("[PATHFIND] " .. message, level or "INFO")
end

-- Verbose pathfinding logging (для детальной отладки waypoints)
local function logPathfindingVerbose(message)
    if not LOG_PATHFINDING_VERBOSE then return end
    log("[PATHFIND-V] " .. message, "VERBOSE")
end

-- Список известных препятствий которые нужно обходить
local KNOWN_OBSTACLES = {
    "Shop",
    "FuseMachine", 
    "AdventCalendar",
    "Events",
    "Lucky Block",
    "Festive Lucky Block",
    "Tree", -- Ёлка
}

-- Специальные зоны препятствий (для дополнительной защиты)
-- Формат: {center = Vector3, radius = number, name = string}
local OBSTACLE_ZONES = {}

-- Невидимые блокирующие части для pathfinding
local pathfindingBlockerParts = {}

-- Функция создания невидимого блокера для pathfinding
local function createPathfindingBlocker(position, size, name)
    local blocker = Instance.new("Part")
    blocker.Name = "PathBlocker_" .. name
    blocker.Size = size
    blocker.Position = position
    blocker.Anchored = true
    blocker.CanCollide = true -- ВАЖНО: PathfindingService видит только CanCollide = true
    blocker.CanQuery = true
    blocker.Transparency = 0.9 -- Почти невидимый (можно поставить 1 для полной невидимости)
    blocker.Color = Color3.fromRGB(255, 0, 0) -- Красный для отладки
    blocker.Parent = workspace
    
    -- Добавляем PathfindingModifier чтобы pathfinding обходил
    local modifier = Instance.new("PathfindingModifier")
    modifier.PassThrough = false
    modifier.Parent = blocker
    
    table.insert(pathfindingBlockerParts, blocker)
    return blocker
end

-- ============ LASER GATE DETECTION ============
-- Проверяет есть ли активные лазеры между игроком и целью

-- Получить папку Laser для плота
local function getLaserFolder(plot)
    if not plot then return nil end
    return plot:FindFirstChild("Laser")
end

-- Проверить виден ли лазер (не прозрачный)
local function isLaserVisible(laserPart)
    if not laserPart then return false end
    -- Лазер видим если Transparency < 1
    return laserPart.Transparency < 0.9
end

-- Проверить есть ли активные лазеры на плоте
local function hasActiveLasers(plot)
    local laserFolder = getLaserFolder(plot)
    if not laserFolder then return false end
    
    -- Проверяем все модели в папке Laser
    for _, child in ipairs(laserFolder:GetDescendants()) do
        if child:IsA("BasePart") then
            -- Пропускаем структурные части (base)
            if not child.Name:lower():find("base") and not child.Name:lower():find("structure") then
                if isLaserVisible(child) then
                    return true
                end
            end
        end
    end
    
    return false
end

-- Проверить блокирует ли лазер путь к позиции
local function isLaserBlockingPath(plot, targetPos)
    local laserFolder = getLaserFolder(plot)
    if not laserFolder then return false end
    
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local playerPos = hrp.Position
    local direction = (targetPos - playerPos).Unit
    local distance = (targetPos - playerPos).Magnitude
    
    -- Проверяем каждый лазер
    for _, child in ipairs(laserFolder:GetDescendants()) do
        if child:IsA("BasePart") and isLaserVisible(child) then
            -- Проверяем пересекает ли линия (player -> target) лазер
            local laserPos = child.Position
            local laserSize = child.Size
            
            -- Простая проверка: лазер между игроком и целью по горизонтали
            local toPlayer = (playerPos - laserPos) * Vector3.new(1, 0, 1)
            local toTarget = (targetPos - laserPos) * Vector3.new(1, 0, 1)
            
            -- Если лазер между игроком и целью
            if toPlayer.Magnitude < distance and toTarget.Magnitude < distance then
                local distToLaser = (laserPos - playerPos).Magnitude
                if distToLaser < 20 then -- Лазер близко
                    return true
                end
            end
        end
    end
    
    return false
end

-- Ждать пока лазеры исчезнут
local function waitForLasersToDisappear(plot, maxWait)
    maxWait = maxWait or PATHFINDING_CONFIG.LASER_WAIT_TIMEOUT
    local startTime = tick()
    
    while hasActiveLasers(plot) do
        if tick() - startTime > maxWait then
            logPathfinding("Laser wait timeout after " .. maxWait .. "s")
            return false
        end
        task.wait(0.1)
    end
    
    logPathfinding("Lasers disappeared, continuing...")
    return true
end

-- Функция добавления PathfindingModifier к препятствиям
local function setupPathfindingModifiers()
    logPathfinding("Setting up PathfindingModifiers for obstacles...")
    local modifiersAdded = 0
    
    -- Удаляем старые блокеры
    for _, part in ipairs(pathfindingBlockerParts) do
        if part and part.Parent then part:Destroy() end
    end
    pathfindingBlockerParts = {}
    OBSTACLE_ZONES = {}
    
    -- Функция для добавления модификаторов к модели
    local function addModifiersToModel(obstacle, obstacleName, useBoxBlocker)
        -- Получаем размеры и позицию препятствия
        local cf, size = nil, nil
        if obstacle:IsA("Model") then
            local ok, boundsCF, boundsSize = pcall(function()
                return obstacle:GetBoundingBox()
            end)
            if ok then
                cf = boundsCF
                size = boundsSize
            end
        elseif obstacle:IsA("BasePart") then
            cf = obstacle.CFrame
            size = obstacle.Size
        end
        
        if cf and size then
            -- Добавляем зону препятствия с увеличенным радиусом
            local radius = math.max(size.X, size.Z) / 2 + 10 -- +10 studs запас
            table.insert(OBSTACLE_ZONES, {
                center = cf.Position,
                radius = radius,
                name = obstacleName,
                size = size
            })
            
            -- Если useBoxBlocker - создаём ОДИН БОЛЬШОЙ КУБ вместо стен
            if useBoxBlocker then
                local boxPadding = 8  -- Уменьшен - слишком большой мешает pathfinding
                local boxSize = Vector3.new(
                    size.X + boxPadding * 2,
                    size.Y + 5, -- Высота с небольшим запасом
                    size.Z + boxPadding * 2
                )
                createPathfindingBlocker(cf.Position, boxSize, obstacleName .. "_BOX")
                logPathfinding("Created BOX blocker around: " .. obstacleName .. 
                    " (size=" .. string.format("%.1f,%.1f,%.1f", boxSize.X, boxSize.Y, boxSize.Z) .. ")")
                return 1
            end
            
            -- Стандартные стены для других препятствий
            local blockerHeight = 30
            local blockerThickness = 3
            local padding = 5
            
            local halfX = size.X / 2 + padding
            local halfZ = size.Z / 2 + padding
            local centerPos = cf.Position
            
            -- Северная стена
            createPathfindingBlocker(
                Vector3.new(centerPos.X, centerPos.Y, centerPos.Z - halfZ - blockerThickness/2),
                Vector3.new(size.X + padding * 2 + blockerThickness * 2, blockerHeight, blockerThickness),
                obstacleName .. "_N"
            )
            -- Южная стена
            createPathfindingBlocker(
                Vector3.new(centerPos.X, centerPos.Y, centerPos.Z + halfZ + blockerThickness/2),
                Vector3.new(size.X + padding * 2 + blockerThickness * 2, blockerHeight, blockerThickness),
                obstacleName .. "_S"
            )
            -- Западная стена
            createPathfindingBlocker(
                Vector3.new(centerPos.X - halfX - blockerThickness/2, centerPos.Y, centerPos.Z),
                Vector3.new(blockerThickness, blockerHeight, size.Z + padding * 2),
                obstacleName .. "_W"
            )
            -- Восточная стена
            createPathfindingBlocker(
                Vector3.new(centerPos.X + halfX + blockerThickness/2, centerPos.Y, centerPos.Z),
                Vector3.new(blockerThickness, blockerHeight, size.Z + padding * 2),
                obstacleName .. "_E"
            )
            
            logPathfinding("Created blocker walls around: " .. obstacleName .. 
                " (size=" .. string.format("%.1f,%.1f,%.1f", size.X, size.Y, size.Z) .. ")")
            return 4
        end
        
        return 0
    end
    
    for _, obstacleName in ipairs(KNOWN_OBSTACLES) do
        local obstacle = workspace:FindFirstChild(obstacleName)
        if obstacle then
            modifiersAdded = modifiersAdded + addModifiersToModel(obstacle, obstacleName)
            
            -- Также добавляем модификатор к самой модели
            local existingModifier = obstacle:FindFirstChildOfClass("PathfindingModifier")
            if not existingModifier then
                local modifier = Instance.new("PathfindingModifier")
                modifier.Name = "FarmPathModifier"
                modifier.PassThrough = false
                modifier.Parent = obstacle
                modifiersAdded = modifiersAdded + 1
            end
            
            -- Добавляем модификаторы ко всем частям внутри модели
            if obstacle:IsA("Model") then
                for _, part in ipairs(obstacle:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        local partModifier = part:FindFirstChildOfClass("PathfindingModifier")
                        if not partModifier then
                            local modifier = Instance.new("PathfindingModifier")
                            modifier.Name = "FarmPathModifier"
                            modifier.PassThrough = false
                            modifier.Parent = part
                        end
                    end
                end
            end
        end
    end
    
    -- ВАЖНО: Обработка AdventCalendar.Tree отдельно (ёлка внутри календаря)
    -- Используем BOX блокер для ёлки - ОДИН БОЛЬШОЙ КУБ
    local adventCalendar = workspace:FindFirstChild("AdventCalendar")
    if adventCalendar then
        -- Создаём BOX блокер для ВСЕГО AdventCalendar
        logPathfinding("Found AdventCalendar - adding BOX blocker for entire model...")
        modifiersAdded = modifiersAdded + addModifiersToModel(adventCalendar, "AdventCalendar_FULL", true)
        
        local tree = adventCalendar:FindFirstChild("Tree")
        if tree then
            logPathfinding("Found AdventCalendar.Tree - adding extra BOX blocker...")
            modifiersAdded = modifiersAdded + addModifiersToModel(tree, "AdventCalendar_Tree", true) -- true = useBoxBlocker
            
            -- Модификатор к самому дереву
            local existingModifier = tree:FindFirstChildOfClass("PathfindingModifier")
            if not existingModifier then
                local modifier = Instance.new("PathfindingModifier")
                modifier.Name = "FarmPathModifier"
                modifier.PassThrough = false
                modifier.Parent = tree
                modifiersAdded = modifiersAdded + 1
            end
            
            -- Модификаторы ко всем частям дерева
            if tree:IsA("Model") then
                for _, part in ipairs(tree:GetDescendants()) do
                    if part:IsA("BasePart") then
                        local partModifier = part:FindFirstChildOfClass("PathfindingModifier")
                        if not partModifier then
                            local modifier = Instance.new("PathfindingModifier")
                            modifier.Name = "FarmPathModifier"
                            modifier.PassThrough = false
                            modifier.Parent = part
                        end
                    end
                end
            end
        end
    end
    
    -- Также ищем объекты по частичному совпадению имени
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") or obj:IsA("Folder") then
            local name = obj.Name:lower()
            if name:find("tree") or name:find("shop") or name:find("fuse") or 
               name:find("event") or name:find("lucky") or name:find("calendar") then
                local existingModifier = obj:FindFirstChildOfClass("PathfindingModifier")
                if not existingModifier then
                    local modifier = Instance.new("PathfindingModifier")
                    modifier.Name = "FarmPathModifier"
                    modifier.PassThrough = false
                    modifier.Parent = obj
                    modifiersAdded = modifiersAdded + 1
                    logPathfinding("Added PathfindingModifier to: " .. obj.Name)
                end
            end
        end
    end
    
    logPathfinding("PathfindingModifiers setup complete: " .. modifiersAdded .. " modifiers/blockers added")
    logPathfinding("Obstacle zones registered: " .. #OBSTACLE_ZONES)
end

-- Проверка находится ли точка внутри зоны препятствия
local function isInsideObstacleZone(position)
    for _, zone in ipairs(OBSTACLE_ZONES) do
        local horizontalDist = ((position.X - zone.center.X)^2 + (position.Z - zone.center.Z)^2)^0.5
        if horizontalDist < zone.radius then
            return true, zone.name
        end
    end
    return false, nil
end

-- Получить безопасную точку обхода препятствия
local function getObstacleAvoidancePoint(startPos, endPos)
    -- Проверяем пересекает ли прямой путь какую-либо зону
    for _, zone in ipairs(OBSTACLE_ZONES) do
        local centerX, centerZ = zone.center.X, zone.center.Z
        local radius = zone.radius + 5 -- Дополнительный запас
        
        -- Простая проверка: если линия от start к end проходит близко к центру зоны
        local dx = endPos.X - startPos.X
        local dz = endPos.Z - startPos.Z
        local lineLength = (dx^2 + dz^2)^0.5
        
        if lineLength > 0 then
            -- Проекция центра зоны на линию
            local t = math.max(0, math.min(1, 
                ((centerX - startPos.X) * dx + (centerZ - startPos.Z) * dz) / (lineLength^2)))
            
            local closestX = startPos.X + t * dx
            local closestZ = startPos.Z + t * dz
            
            local distToLine = ((closestX - centerX)^2 + (closestZ - centerZ)^2)^0.5
            
            if distToLine < radius then
                -- Путь пересекает зону! Создаём точку обхода
                logPathfinding("Path crosses obstacle zone: " .. zone.name .. ", creating avoidance point")
                
                -- Определяем с какой стороны обходить (выбираем ближайшую)
                local perpX = -dz / lineLength
                local perpZ = dx / lineLength
                
                -- Две возможные точки обхода
                local avoidPoint1 = Vector3.new(
                    centerX + perpX * (radius + 3),
                    startPos.Y,
                    centerZ + perpZ * (radius + 3)
                )
                local avoidPoint2 = Vector3.new(
                    centerX - perpX * (radius + 3),
                    startPos.Y,
                    centerZ - perpZ * (radius + 3)
                )
                
                -- Выбираем точку которая ближе к текущей позиции
                local dist1 = (avoidPoint1 - startPos).Magnitude
                local dist2 = (avoidPoint2 - startPos).Magnitude
                
                return dist1 < dist2 and avoidPoint1 or avoidPoint2, zone.name
            end
        end
    end
    
    return nil, nil
end

-- Вызываем настройку модификаторов при загрузке
-- В SAFE_MODE не создаём никаких блокеров и модификаторов
if not SAFE_MODE then
    task.spawn(function()
        task.wait(2) -- Ждём загрузки мира
        setupPathfindingModifiers()
    end)
end

-- Создание Path объекта с оптимальными параметрами
local function createPath()
    return PathfindingService:CreatePath({
        AgentRadius = PATHFINDING_CONFIG.AgentRadius,
        AgentHeight = PATHFINDING_CONFIG.AgentHeight,
        AgentCanJump = PATHFINDING_CONFIG.AgentCanJump,
        AgentCanClimb = PATHFINDING_CONFIG.AgentCanClimb,
        WaypointSpacing = PATHFINDING_CONFIG.WaypointSpacing,
        Costs = PATHFINDING_CONFIG.Costs,
    })
end

-- Проверка валидности позиции (не NaN, не слишком далеко)
local function isValidPosition(pos)
    if not pos then return false end
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then return false end -- NaN check
    if math.abs(pos.X) > 10000 or math.abs(pos.Y) > 1000 or math.abs(pos.Z) > 10000 then return false end
    return true
end

-- Получение текущей позиции персонажа
local function getPlayerPosition()
    local character = LocalPlayer.Character
    if not character then return nil end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    return hrp.Position
end

-- Получение humanoid
local function getHumanoid()
    local character = LocalPlayer.Character
    if not character then return nil end
    return character:FindFirstChild("Humanoid")
end

-- Простое движение к точке (MoveTo) без pathfinding - для коротких дистанций или fallback
local function moveToSimple(position, timeout)
    local character = LocalPlayer.Character
    if not character then return false end
    local humanoid = character:FindFirstChild("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp then return false end
    
    -- Проверка - уже на месте?
    local initialDist = (hrp.Position - position).Magnitude
    if initialDist < PATHFINDING_CONFIG.ARRIVAL_DISTANCE then 
        return true 
    end
    
    timeout = timeout or PATHFINDING_CONFIG.WAYPOINT_TIMEOUT
    local startTime = tick()
    local lastPos = hrp.Position
    local stuckTime = 0
    local lastJumpTime = 0
    local noProgressTime = 0
    local bestDist = initialDist
    
    humanoid:MoveTo(position)
    logPathfinding("moveToSimple: dist=" .. string.format("%.1f", initialDist) .. ", timeout=" .. timeout)
    
    while tick() - startTime < timeout do
        if not CONFIG.FARM_ENABLED then return false end
        if not hrp or not hrp.Parent then return false end
        
        local currentPos = hrp.Position
        local dist = (currentPos - position).Magnitude
        
        -- Дошли до цели
        if dist < PATHFINDING_CONFIG.ARRIVAL_DISTANCE then 
            logPathfinding("moveToSimple: SUCCESS, dist=" .. string.format("%.1f", dist))
            return true 
        end
        
        -- Отслеживаем лучшую дистанцию
        if dist < bestDist then
            bestDist = dist
            noProgressTime = 0
        else
            noProgressTime = noProgressTime + 0.1
        end
        
        -- Если 5 секунд нет прогресса - пробуем прыжки
        if noProgressTime > 5 then
            if tick() - lastJumpTime > 0.8 then
                humanoid.Jump = true
                lastJumpTime = tick()
            end
        end
        
        -- Проверка застревания (не двигаемся)
        local moved = (currentPos - lastPos).Magnitude
        if moved < 0.3 then
            stuckTime = stuckTime + 0.1
            if stuckTime > PATHFINDING_CONFIG.STUCK_THRESHOLD then
                humanoid.Jump = true
                stuckTime = 0
                logPathfinding("moveToSimple: stuck, jumping")
            end
        else
            stuckTime = 0
            lastPos = currentPos
        end
        
        -- Повторяем MoveTo для обновления направления
        humanoid:MoveTo(position)
        task.wait(0.1)
    end
    
    -- Timeout - проверяем финальную дистанцию
    local finalDist = (hrp.Position - position).Magnitude
    local success = finalDist < PATHFINDING_CONFIG.ARRIVAL_DISTANCE * 2
    logPathfinding("moveToSimple: " .. (success and "SUCCESS" or "TIMEOUT") .. ", finalDist=" .. string.format("%.1f", finalDist))
    return success
end

-- Движение к waypoint с обработкой действий (Jump, Custom)
local function moveToWaypoint(waypoint, timeout)
    local humanoid = getHumanoid()
    if not humanoid then return false end
    
    local position = waypoint.Position
    local action = waypoint.Action
    
    -- Если требуется прыжок - прыгаем
    if action == Enum.PathWaypointAction.Jump then
        humanoid.Jump = true
        task.wait(0.1)
    end
    
    return moveToSimple(position, timeout)
end

-- Вычисление пути через PathfindingService
local function computePath(startPos, endPos)
    if not isValidPosition(startPos) or not isValidPosition(endPos) then
        logPathfinding("Invalid positions: start=" .. tostring(startPos) .. " end=" .. tostring(endPos), "WARN")
        return nil, "Invalid positions"
    end
    
    local distance = (endPos - startPos).Magnitude
    if distance > 3000 then
        logPathfinding("Distance too far: " .. string.format("%.1f", distance) .. " studs (max 3000)", "WARN")
        return nil, "Distance too far"
    end
    
    -- Перед вычислением пути обновляем модификаторы препятствий
    setupPathfindingModifiers()
    
    local path = createPath()
    local success, errorMessage = pcall(function()
        path:ComputeAsync(startPos, endPos)
    end)
    
    if not success then
        logPathfinding("ComputeAsync failed: " .. tostring(errorMessage), "WARN")
        return nil, errorMessage
    end
    
    if path.Status ~= Enum.PathStatus.Success then
        logPathfinding("Path status: " .. tostring(path.Status) .. " (may need manual navigation)", "WARN")
        return nil, tostring(path.Status)
    end
    
    local waypoints = path:GetWaypoints()
    if not waypoints or #waypoints < 2 then
        logPathfinding("No waypoints generated", "WARN")
        return nil, "No waypoints"
    end
    
    -- Проверяем не проходит ли путь через препятствия
    local obstacleHit = false
    for _, waypoint in ipairs(waypoints) do
        for _, obstacleName in ipairs(KNOWN_OBSTACLES) do
            local obstacle = workspace:FindFirstChild(obstacleName)
            if obstacle then
                -- Получаем bounding box препятствия
                local cf, size = nil, nil
                if obstacle:IsA("Model") and obstacle.PrimaryPart then
                    cf = obstacle.PrimaryPart.CFrame
                    size = obstacle:GetExtentsSize()
                elseif obstacle:IsA("BasePart") then
                    cf = obstacle.CFrame
                    size = obstacle.Size
                end
                
                if cf and size then
                    local relPos = cf:PointToObjectSpace(waypoint.Position)
                    local halfSize = size / 2 + Vector3.new(3, 3, 3) -- добавляем отступ
                    if math.abs(relPos.X) < halfSize.X and 
                       math.abs(relPos.Y) < halfSize.Y and 
                       math.abs(relPos.Z) < halfSize.Z then
                        logPathfinding("WARNING: Path goes through obstacle: " .. obstacleName, "WARN")
                        obstacleHit = true
                    end
                end
            end
        end
    end
    
    if obstacleHit then
        logPathfinding("Path may collide with obstacles - navigation might have issues", "WARN")
    end
    
    return waypoints, nil
end

-- Визуализация пути (для отладки) - создаёт маленькие части на waypoints
local DEBUG_VISUALIZE_PATH = false -- ОТКЛЮЧЕНО
local DEBUG_SHOW_OBSTACLES = false -- ОТКЛЮЧЕНО
local pathVisualizationParts = {}
local obstacleVisualizationParts = {}

-- Функция визуализации препятствий (красные полупрозрачные боксы)
local function visualizeObstacles()
    if not DEBUG_SHOW_OBSTACLES then return end
    
    -- Очищаем старую визуализацию
    for _, part in ipairs(obstacleVisualizationParts) do
        if part and part.Parent then part:Destroy() end
    end
    obstacleVisualizationParts = {}
    
    -- Визуализируем зоны препятствий (круги на земле)
    for _, zone in ipairs(OBSTACLE_ZONES) do
        -- Круглый маркер зоны на земле
        local zoneMarker = Instance.new("Part")
        zoneMarker.Name = "ObstacleZone_" .. zone.name
        zoneMarker.Shape = Enum.PartType.Cylinder
        zoneMarker.Size = Vector3.new(1, zone.radius * 2, zone.radius * 2)
        zoneMarker.CFrame = CFrame.new(zone.center.X, zone.center.Y - 5, zone.center.Z) * CFrame.Angles(0, 0, math.rad(90))
        zoneMarker.Anchored = true
        zoneMarker.CanCollide = false
        zoneMarker.Transparency = 0.85
        zoneMarker.Material = Enum.Material.Neon
        zoneMarker.BrickColor = BrickColor.new("Really red")
        zoneMarker.Parent = workspace
        table.insert(obstacleVisualizationParts, zoneMarker)
    end
    
    -- Визуализируем сами препятствия
    for _, obstacleName in ipairs(KNOWN_OBSTACLES) do
        local obstacle = workspace:FindFirstChild(obstacleName)
        if obstacle then
            local cf, size = nil, nil
            if obstacle:IsA("Model") then
                local ok, extents = pcall(function() return obstacle:GetExtentsSize() end)
                if ok then
                    size = extents
                    -- Получаем центр модели
                    local ok2, boundsCF = pcall(function() 
                        return obstacle:GetBoundingBox()
                    end)
                    if ok2 then
                        cf = boundsCF
                    elseif obstacle.PrimaryPart then
                        cf = obstacle.PrimaryPart.CFrame
                    end
                end
            elseif obstacle:IsA("BasePart") then
                cf = obstacle.CFrame
                size = obstacle.Size
            end
            
            if cf and size then
                local marker = Instance.new("Part")
                marker.Name = "ObstacleMarker_" .. obstacleName
                marker.Size = size + Vector3.new(2, 2, 2) -- Немного больше для отступа
                marker.CFrame = cf
                marker.Anchored = true
                marker.CanCollide = false
                marker.Transparency = 0.8
                marker.Material = Enum.Material.ForceField
                marker.BrickColor = BrickColor.new("Really red")
                marker.Parent = workspace
                table.insert(obstacleVisualizationParts, marker)
            end
        end
    end
    
    logPathfinding("Visualized " .. #obstacleVisualizationParts .. " obstacles and zones")
end

-- Очистка визуализации препятствий
local function clearObstacleVisualization()
    for _, part in ipairs(obstacleVisualizationParts) do
        if part and part.Parent then part:Destroy() end
    end
    obstacleVisualizationParts = {}
end

local function clearPathVisualization()
    for _, part in ipairs(pathVisualizationParts) do
        if part and part.Parent then
            part:Destroy()
        end
    end
    pathVisualizationParts = {}
end

local function visualizePath(waypoints, destination)
    if not DEBUG_VISUALIZE_PATH then return end
    clearPathVisualization()
    
    -- Создаём визуальную линию пути
    for i, waypoint in ipairs(waypoints) do
        -- Сфера на waypoint
        local part = Instance.new("Part")
        part.Name = "PathWaypoint_" .. i
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(2, 2, 2)
        part.Position = waypoint.Position
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 0.3
        part.Material = Enum.Material.Neon
        
        -- Цвет в зависимости от действия и позиции
        if i == 1 then
            part.BrickColor = BrickColor.new("Lime green") -- Старт
            part.Size = Vector3.new(3, 3, 3)
        elseif i == #waypoints then
            part.BrickColor = BrickColor.new("Bright red") -- Финиш
            part.Size = Vector3.new(3, 3, 3)
        elseif waypoint.Action == Enum.PathWaypointAction.Jump then
            part.BrickColor = BrickColor.new("Bright yellow") -- Прыжок
        else
            part.BrickColor = BrickColor.new("Cyan") -- Обычный
        end
        
        part.Parent = workspace
        table.insert(pathVisualizationParts, part)
        
        -- Линия к следующему waypoint
        if i < #waypoints then
            local nextWaypoint = waypoints[i + 1]
            local startPos = waypoint.Position
            local endPos = nextWaypoint.Position
            local distance = (endPos - startPos).Magnitude
            
            if distance > 0.5 then
                local line = Instance.new("Part")
                line.Name = "PathLine_" .. i
                line.Size = Vector3.new(0.3, 0.3, distance)
                line.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance/2)
                line.Anchored = true
                line.CanCollide = false
                line.Transparency = 0.5
                line.Material = Enum.Material.Neon
                line.BrickColor = BrickColor.new("Electric blue")
                line.Parent = workspace
                table.insert(pathVisualizationParts, line)
            end
        end
    end
    
    -- Маркер конечной точки (если отличается от последнего waypoint)
    if destination then
        local destMarker = Instance.new("Part")
        destMarker.Name = "PathDestination"
        destMarker.Shape = Enum.PartType.Cylinder
        destMarker.Size = Vector3.new(1, 5, 5)
        destMarker.CFrame = CFrame.new(destination) * CFrame.Angles(0, 0, math.rad(90))
        destMarker.Anchored = true
        destMarker.CanCollide = false
        destMarker.Transparency = 0.5
        destMarker.Material = Enum.Material.Neon
        destMarker.BrickColor = BrickColor.new("Bright red")
        destMarker.Parent = workspace
        table.insert(pathVisualizationParts, destMarker)
    end
    
    logPathfinding("Path visualized: " .. #waypoints .. " waypoints")
end

-- Главная функция навигации с использованием PathfindingService
-- Возвращает: success (bool), reason (string|nil)
local function navigateWithPathfinding(destination, timeout)
    pathfindingStats.totalPaths = pathfindingStats.totalPaths + 1
    local pathStartTime = tick()
    
    local startPos = getPlayerPosition()
    if not startPos then
        logPathfinding("Cannot navigate: no player position", "WARN")
        pathfindingStats.failedPaths = pathfindingStats.failedPaths + 1
        return false, "No player position"
    end
    
    local humanoid = getHumanoid()
    if not humanoid then
        logPathfinding("Cannot navigate: no humanoid", "WARN")
        pathfindingStats.failedPaths = pathfindingStats.failedPaths + 1
        return false, "No humanoid"
    end
    
    -- Уже на месте?
    local initialDist = (startPos - destination).Magnitude
    if initialDist < PATHFINDING_CONFIG.ARRIVAL_DISTANCE then
        logPathfinding("Already at destination (dist=" .. string.format("%.1f", initialDist) .. ")")
        pathfindingStats.successfulPaths = pathfindingStats.successfulPaths + 1
        return true, nil
    end
    
    timeout = timeout or PATHFINDING_CONFIG.PATH_TIMEOUT
    
    logPathfinding(string.format("Computing path: dist=%.1f start=(%.1f,%.1f,%.1f) end=(%.1f,%.1f,%.1f)", 
        initialDist, startPos.X, startPos.Y, startPos.Z, destination.X, destination.Y, destination.Z))
    
    -- Проверяем нужен ли обход препятствия
    local avoidancePoint, obstacleName = getObstacleAvoidancePoint(startPos, destination)
    if avoidancePoint then
        logPathfinding("Need to avoid obstacle: " .. obstacleName .. ", going to avoidance point first")
        -- Сначала идём к точке обхода
        local avoidWaypoints, _ = computePath(startPos, avoidancePoint)
        if avoidWaypoints then
            visualizePath(avoidWaypoints, avoidancePoint)
            -- Проходим точку обхода
            for i = 2, #avoidWaypoints do
                if not CONFIG.FARM_ENABLED then break end
                local wp = avoidWaypoints[i]
                if wp.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                end
                moveToSimple(wp.Position, 5)
            end
            -- Обновляем стартовую позицию
            startPos = getPlayerPosition() or startPos
        end
    end
    
    -- Визуализируем препятствия для отладки
    visualizeObstacles()
    
    -- Вычисляем путь
    local waypoints, pathError = computePath(startPos, destination)
    
    if not waypoints then
        -- Fallback: пробуем простое движение если путь не вычислился
        logPathfinding("Pathfinding failed: " .. tostring(pathError) .. ", trying direct movement", "WARN")
        pathfindingStats.fallbackPaths = pathfindingStats.fallbackPaths + 1
        
        local directSuccess = moveToSimple(destination, timeout)
        if directSuccess then
            pathfindingStats.successfulPaths = pathfindingStats.successfulPaths + 1
        else
            pathfindingStats.failedPaths = pathfindingStats.failedPaths + 1
        end
        return directSuccess, directSuccess and nil or "Direct movement failed"
    end
    
    pathfindingStats.lastPathWaypoints = #waypoints
    logPathfinding("Path computed: " .. #waypoints .. " waypoints")
    visualizePath(waypoints, destination)
    
    -- Движение по waypoints
    -- Пропускаем первый waypoint (это стартовая позиция)
    local currentWaypointIndex = 2
    local pathBlocked = false
    
    local success = false
    local reason = nil
    
    while currentWaypointIndex <= #waypoints do
        -- Проверки
        if not CONFIG.FARM_ENABLED then
            reason = "Farm disabled"
            break
        end
        
        if tick() - pathStartTime > timeout then
            reason = "Path timeout"
            logPathfinding("Path timeout after " .. string.format("%.1f", tick() - pathStartTime) .. "s", "WARN")
            break
        end
        
        -- Текущий waypoint
        local waypoint = waypoints[currentWaypointIndex]
        
        -- Verbose logging для детальной отладки каждого waypoint
        logPathfindingVerbose(string.format("Waypoint %d/%d: (%.1f,%.1f,%.1f) action=%s",
            currentWaypointIndex, #waypoints,
            waypoint.Position.X, waypoint.Position.Y, waypoint.Position.Z,
            tostring(waypoint.Action)))
        
        -- Движение к waypoint с отслеживанием застревания
        local waypointStartTime = tick()
        local waypointSuccess = false
        local stuckAttempts = 0
        local maxStuckAttempts = 3
        local lastPosition = getPlayerPosition()
        
        while tick() - waypointStartTime < PATHFINDING_CONFIG.WAYPOINT_TIMEOUT do
            if not CONFIG.FARM_ENABLED then break end
            
            local currentPos = getPlayerPosition()
            if not currentPos then break end
            
            local distToWaypoint = (currentPos - waypoint.Position).Magnitude
            
            -- Дошли до waypoint
            if distToWaypoint < PATHFINDING_CONFIG.ARRIVAL_DISTANCE then
                waypointSuccess = true
                break
            end
            
            -- Проверка застревания (УСКОРЕНО с 1.5 до 1.0 секунды)
            local moved = lastPosition and (currentPos - lastPosition).Magnitude or 0
            if moved < 0.5 then
                stuckAttempts = stuckAttempts + 1
                
                -- Проверяем не застряли ли мы в зоне препятствия
                local inObstacle, obstacleName = isInsideObstacleZone(currentPos)
                if inObstacle then
                    logPathfinding("STUCK INSIDE OBSTACLE: " .. obstacleName .. "! Emergency escape!", "WARN")
                    
                    -- Экстренный выход из препятствия - идём в противоположную сторону
                    for _, zone in ipairs(OBSTACLE_ZONES) do
                        if zone.name == obstacleName then
                            local escapeDir = (currentPos - zone.center).Unit
                            local escapePos = currentPos + escapeDir * (zone.radius + 10)
                            escapePos = Vector3.new(escapePos.X, currentPos.Y, escapePos.Z)
                            
                            logPathfinding("Escaping to: " .. string.format("%.1f,%.1f,%.1f", escapePos.X, escapePos.Y, escapePos.Z))
                            humanoid.Jump = true
                            humanoid:MoveTo(escapePos)
                            task.wait(1.5)  -- УСКОРЕНО с 2
                            
                            -- Перерасчёт пути после выхода
                            local newPos = getPlayerPosition()
                            if newPos then
                                local newWaypoints, _ = computePath(newPos, destination)
                                if newWaypoints and #newWaypoints >= 2 then
                                    waypoints = newWaypoints
                                    currentWaypointIndex = 2
                                    visualizePath(waypoints, destination)
                                    logPathfinding("Path recomputed after escape: " .. #waypoints .. " waypoints")
                                end
                            end
                            break
                        end
                    end
                    stuckAttempts = 0
                    break
                end
                
                if stuckAttempts > 10 then -- ~1.0 секунды без движения (УСКОРЕНО)
                    logPathfinding("STUCK detected at waypoint " .. currentWaypointIndex .. ", attempting recovery", "WARN")
                    
                    -- Попытка 1: прыжок
                    humanoid.Jump = true
                    task.wait(0.3)
                    
                    -- Попытка 2: перерасчёт пути от текущей позиции
                    if stuckAttempts > 18 then
                        logPathfinding("Recomputing path from current position...")
                        local newWaypoints, newError = computePath(currentPos, destination)
                        if newWaypoints and #newWaypoints >= 2 then
                            waypoints = newWaypoints
                            currentWaypointIndex = 2
                            visualizePath(waypoints, destination)
                            logPathfinding("Path recomputed: " .. #waypoints .. " waypoints")
                            stuckAttempts = 0
                            break
                        end
                    end
                end
            else
                stuckAttempts = 0
                lastPosition = currentPos
            end
            
            -- Движение к waypoint
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            humanoid:MoveTo(waypoint.Position)
            
            task.wait(0.1)
        end
        
        if not waypointSuccess then
            logPathfinding("Failed to reach waypoint " .. currentWaypointIndex .. " after " .. 
                string.format("%.1f", tick() - waypointStartTime) .. "s", "WARN")
            
            -- Пробуем прыжок и перерасчёт пути
            humanoid.Jump = true
            task.wait(0.2)
            
            -- Если осталось много waypoints - перерасчитываем путь
            local remainingWaypoints = #waypoints - currentWaypointIndex
            if remainingWaypoints > 2 then
                local currentPos = getPlayerPosition()
                if currentPos then
                    logPathfinding("Recomputing path due to stuck... (" .. remainingWaypoints .. " waypoints remaining)")
                    local newWaypoints, _ = computePath(currentPos, destination)
                    if newWaypoints and #newWaypoints >= 2 then
                        waypoints = newWaypoints
                        currentWaypointIndex = 1 -- Reset to start of new path
                        visualizePath(waypoints, destination)
                        logPathfinding("Path recomputed: " .. #waypoints .. " new waypoints")
                    else
                        -- Не получилось перерасчитать - пробуем простое движение к цели
                        logPathfinding("Cannot recompute path, trying direct movement to destination")
                        local directSuccess = moveToSimple(destination, 15)
                        if directSuccess then
                            success = true
                            break
                        end
                    end
                end
            end
        end
        
        currentWaypointIndex = currentWaypointIndex + 1
        
        -- Обновляем визуализацию текущего waypoint
        if DEBUG_VISUALIZE_PATH then
            for _, part in ipairs(pathVisualizationParts) do
                if part and part.Parent and part.Name == "PathWaypoint_" .. (currentWaypointIndex - 1) then
                    part.BrickColor = BrickColor.new("Bright green") -- Пройден
                    part.Transparency = 0.7
                end
            end
        end
    end
    
    -- Очищаем визуализацию через 5 секунд (чтобы увидеть путь)
    task.delay(5, function()
        clearPathVisualization()
        clearObstacleVisualization()
    end)
    
    -- Проверяем финальную позицию
    local finalPos = getPlayerPosition()
    if finalPos then
        local finalDist = (finalPos - destination).Magnitude
        success = finalDist < PATHFINDING_CONFIG.ARRIVAL_DISTANCE * 1.5
        
        if success then
            pathfindingStats.successfulPaths = pathfindingStats.successfulPaths + 1
            logPathfinding(string.format("Navigation SUCCESS: final dist=%.1f, time=%.1fs", 
                finalDist, tick() - pathStartTime))
        else
            pathfindingStats.failedPaths = pathfindingStats.failedPaths + 1
            reason = reason or string.format("Final distance too far: %.1f", finalDist)
            logPathfinding("Navigation FAILED: " .. reason, "WARN")
        end
    else
        pathfindingStats.failedPaths = pathfindingStats.failedPaths + 1
        reason = "Lost player position at end"
    end
    
    pathfindingStats.lastPathTime = tick() - pathStartTime
    
    return success, reason
end

-- Обёртка для совместимости со старым кодом
-- walkTo теперь использует PathfindingService!
local function walkTo(position, timeout)
    timeout = timeout or 30
    local maxRetries = 10 -- Увеличено для надёжности
    local retryDelay = 0.5 -- Уменьшено для быстрой перестройки
    
    for attempt = 1, maxRetries do
        local success, reason = navigateWithPathfinding(position, timeout)
        
        if success then
            return true
        end
        
        logPathfinding("walkTo attempt " .. attempt .. "/" .. maxRetries .. " failed: " .. tostring(reason))
        
        -- Если не последняя попытка - пробуем recovery
        if attempt < maxRetries then
            local humanoid = getHumanoid()
            if humanoid then
                -- Прыжок для выхода из застревания
                humanoid.Jump = true
                task.wait(0.5)
                
                -- На последней попытке пробуем простое движение
                if attempt == maxRetries - 1 then
                    logPathfinding("Trying direct simple movement as last resort...")
                    local simpleSuccess = moveToSimple(position, timeout)
                    if simpleSuccess then
                        logPathfinding("Simple movement succeeded!")
                        return true
                    end
                end
            end
            task.wait(retryDelay)
        end
    end
    
    -- Финальный fallback - простое движение с прыжками
    logPathfinding("All pathfinding attempts failed, final fallback to aggressive simple movement", "WARN")
    local humanoid = getHumanoid()
    local hrp = humanoid and humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
    if humanoid and hrp then
        local startTime = tick()
        local lastJumpTime = 0
        while tick() - startTime < timeout do
            if not CONFIG.FARM_ENABLED then return false end
            
            local dist = (hrp.Position - position).Magnitude
            if dist < PATHFINDING_CONFIG.ARRIVAL_DISTANCE * 2 then
                return true
            end
            
            humanoid:MoveTo(position)
            
            -- Прыжок каждые 1.5 секунды
            if tick() - lastJumpTime > 1.5 then
                humanoid.Jump = true
                lastJumpTime = tick()
            end
            
            task.wait(0.1)
        end
    end
    
    return false
end

-- Простая функция для коротких дистанций (без pathfinding)
local function walkToSimple(position, timeout)
    return moveToSimple(position, timeout)
end

-- Функция для получения статистики pathfinding
local function getPathfindingStats()
    local successRate = 0
    if pathfindingStats.totalPaths > 0 then
        successRate = (pathfindingStats.successfulPaths / pathfindingStats.totalPaths) * 100
    end
    
    return string.format(
        "Paths: %d total, %d success (%.1f%%), %d failed, %d fallback\nLast: %.1fs, %d waypoints",
        pathfindingStats.totalPaths,
        pathfindingStats.successfulPaths,
        successRate,
        pathfindingStats.failedPaths,
        pathfindingStats.fallbackPaths,
        pathfindingStats.lastPathTime,
        pathfindingStats.lastPathWaypoints
    )
end

-- Логируем статистику каждые 60 секунд
-- В SAFE_MODE pathfinding не используется
if not SAFE_MODE then
    task.spawn(function()
        while true do
            task.wait(60)
            if CONFIG.FARM_ENABLED and pathfindingStats.totalPaths > 0 then
                logPathfinding("=== PATHFINDING STATS ===\n" .. getPathfindingStats())
            end
        end
    end)
end

log("[PATHFIND] PathfindingService navigation system initialized")
-- ============ END PATHFINDING SYSTEM ============

-- Find stairs and second floor info for a plot
local function getPlotStairsInfo(plot)
    if not plot then return nil end
    
    local decorations = plot:FindFirstChild("Decorations")
    if not decorations then return nil end
    
    local laserHitbox = plot:FindFirstChild("LaserHitbox")
    local secondFloor = laserHitbox and laserHitbox:FindFirstChild("SecondFloor")
    
    if not secondFloor then return nil end
    
    -- Find stairs parts (structure base home with specific sizes)
    -- Ступеньки имеют размер 6x10x2 (или вариации из-за поворота)
    local stairsStart, stairsEnd = nil, nil
    local lowestY, highestY = math.huge, -math.huge
    
    for _, part in ipairs(decorations:GetChildren()) do
        if part:IsA("BasePart") and part.Name == "structure base home" then
            local size = part.Size
            -- Проверяем размеры (могут быть в разном порядке из-за поворота)
            local sizes = {size.X, size.Y, size.Z}
            table.sort(sizes)
            
            -- Ступеньки: размеры содержат примерно 2, 6, 10
            local is6x10x2 = (sizes[1] >= 1.5 and sizes[1] <= 2.5) and 
                            (sizes[2] >= 5 and sizes[2] <= 7) and 
                            (sizes[3] >= 9 and sizes[3] <= 11)
            
            -- Верхняя площадка: размеры содержат примерно 2, 10, 17
            local is17x10x2 = (sizes[1] >= 1.5 and sizes[1] <= 2.5) and 
                             (sizes[2] >= 9 and sizes[2] <= 11) and 
                             (sizes[3] >= 15 and sizes[3] <= 19)
            
            if is6x10x2 then
                -- Ищем самую нижнюю ступеньку (первая)
                if part.Position.Y < lowestY then
                    lowestY = part.Position.Y
                    stairsStart = part
                end
            end
            
            if is17x10x2 then
                -- Ищем самую верхнюю площадку
                if part.Position.Y > highestY then
                    highestY = part.Position.Y
                    stairsEnd = part
                end
            end
        end
    end
    
    if stairsStart then
        log("[STAIRS] Found stairsStart at Y=" .. string.format("%.1f", stairsStart.Position.Y) .. 
            ", size=" .. tostring(stairsStart.Size))
    end
    if stairsEnd then
        log("[STAIRS] Found stairsEnd at Y=" .. string.format("%.1f", stairsEnd.Position.Y) .. 
            ", size=" .. tostring(stairsEnd.Size))
    end
    
    return {
        hasSecondFloor = true,
        secondFloorPart = secondFloor,
        stairsStart = stairsStart,
        stairsEnd = stairsEnd
    }
end

-- Получить позиции низа и верха лестницы для plot
local function getStairsPositions(plot)
    local info = getPlotStairsInfo(plot)
    if not info or not info.stairsStart or not info.stairsEnd then
        return nil, nil
    end
    
    -- Находим carpet для определения уровня земли
    local carpet = plot:FindFirstChild("Flying Carpet")
    local groundY = carpet and (carpet.Position.Y + 3) or info.stairsStart.Position.Y
    
    -- Вычисляем направление лестницы (от первой ступеньки к верхней площадке)
    local dirX = info.stairsEnd.Position.X - info.stairsStart.Position.X
    local dirZ = info.stairsEnd.Position.Z - info.stairsStart.Position.Z
    local len = math.sqrt(dirX * dirX + dirZ * dirZ)
    if len > 0 then
        dirX = dirX / len
        dirZ = dirZ / len
    end
    
    -- Позиция НА ЗЕМЛЕ перед первой ступенькой (сдвинутая назад от лестницы)
    -- ВАЖНО: Y координата должна быть на уровне земли, чтобы персонаж
    -- мог достичь этого вейпоинта при спуске по лестнице
    local bottomPos = Vector3.new(
        info.stairsStart.Position.X - dirX * 5, -- 5 studs назад от первой ступеньки
        groundY,                                 -- На уровне земли (не ступеньки!)
        info.stairsStart.Position.Z - dirZ * 5
    )
    
    -- Позиция ПОСЛЕДНЕЙ площадки (верх лестницы)
    local topPos = info.stairsEnd.Position
    
    log("[STAIRS] Ground level Y: " .. string.format("%.1f", groundY))
    log("[STAIRS] Position BEFORE first step (on ground): " .. string.format("%.1f, %.1f, %.1f", bottomPos.X, bottomPos.Y, bottomPos.Z))
    log("[STAIRS] Last step position: " .. string.format("%.1f, %.1f, %.1f", topPos.X, topPos.Y, topPos.Z))
    
    return bottomPos, topPos
end

-- Простое движение к точке с прыжком при застревании (для лестниц)
local function simpleWalkTo(position, timeout, allowJump)
    timeout = timeout or 15
    allowJump = allowJump ~= false
    
    local character = LocalPlayer.Character
    if not character then return false end
    local humanoid = character:FindFirstChild("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp then return false end
    
    local startTime = tick()
    local lastPos = hrp.Position
    local stuckTime = 0
    local lastJumpTime = 0
    
    humanoid:MoveTo(position)
    
    while tick() - startTime < timeout do
        if not CONFIG.FARM_ENABLED then return false end
        
        local currentPos = hrp.Position
        local dist = (currentPos - position).Magnitude
        local horizontalDist = ((currentPos - position) * Vector3.new(1, 0, 1)).Magnitude
        
        -- Дошли
        if horizontalDist < 3 or dist < 4 then
            return true
        end
        
        -- Проверка застревания
        local moved = (currentPos - lastPos).Magnitude
        if moved < 0.2 then
            stuckTime = stuckTime + 0.1
            if stuckTime > 0.3 and allowJump then
                local now = tick()
                if now - lastJumpTime > 0.4 then
                    humanoid.Jump = true
                    humanoid:MoveTo(position)
                    lastJumpTime = now
                end
            end
        else
            stuckTime = 0
        end
        
        lastPos = currentPos
        humanoid:MoveTo(position)
        task.wait(0.1)
    end
    
    -- Timeout - проверим дошли ли частично
    local finalDist = (hrp.Position - position).Magnitude
    return finalDist < 8
end

-- Walk to second floor via stairs - НЕ НУЖНА при использовании прямого pathfinding
-- Pathfinding сам построит маршрут через лестницу к brainrot
local function walkToSecondFloor(plot)
    -- Больше не нужна - pathfinding сам поднимется по лестнице
    log("[STAIRS] walkToSecondFloor called but not needed - pathfinding handles stairs")
    return true
end

-- Walk down from second floor - НЕ НУЖНА при использовании прямого pathfinding
local function walkDownFromSecondFloor(plot)
    -- Больше не нужна - pathfinding сам спустится по лестнице
    log("[STAIRS] walkDownFromSecondFloor called but not needed - pathfinding handles stairs")
    return true
end

-- ============ ELEVATOR SYSTEM FOR THIRD FLOOR ============
local activeElevator = nil
local disabledLadderParts = {} -- Store ladder parts with disabled collision

-- Get third floor info for a plot
local function getThirdFloorInfo(plot)
    if not plot then return nil end
    
    local laserHitbox = plot:FindFirstChild("LaserHitbox")
    if not laserHitbox then return nil end
    
    local thirdFloor = laserHitbox:FindFirstChild("ThirdFloor")
    if not thirdFloor then return nil end
    
    return {
        hasThirdFloor = true,
        thirdFloorPart = thirdFloor,
        position = thirdFloor.Position,
        size = thirdFloor.Size
    }
end

-- Disable ladder collision so player doesn't get stuck during elevator ride
local function disableLadderCollision(plot)
    if not plot then return end
    
    local model = plot:FindFirstChild("Model")
    if not model then return end
    
    disabledLadderParts = {}
    
    for _, part in ipairs(model:GetChildren()) do
        if part:IsA("BasePart") and part.Name == "structure base home" then
            -- Save original state
            table.insert(disabledLadderParts, {
                part = part,
                canCollide = part.CanCollide,
                transparency = part.Transparency
            })
            -- Disable collision and make semi-transparent
            part.CanCollide = false
            part.Transparency = 0.7
        end
    end
end

-- Restore ladder collision after elevator ride
local function restoreLadderCollision()
    for _, data in ipairs(disabledLadderParts) do
        if data.part and data.part.Parent then
            data.part.CanCollide = data.canCollide
            data.part.Transparency = data.transparency
        end
    end
    disabledLadderParts = {}
end

-- Create elevator platform under player
local function createElevator(position, size)
    -- Remove old elevator if exists
    if activeElevator and activeElevator.Parent then
        activeElevator:Destroy()
    end
    
    local elevator = Instance.new("Part")
    elevator.Name = "FarmElevator"
    -- ThirdFloor is rotated 90 degrees, so its real horizontal dimensions are:
    -- Width = size.Y (10.875), Depth = size.X (11.270)
    -- Make elevator flat horizontal platform matching ThirdFloor's actual footprint
    elevator.Size = Vector3.new(size.Y, 1, size.X)
    elevator.Position = position
    elevator.Anchored = true
    elevator.CanCollide = true
    elevator.BrickColor = BrickColor.new("Bright blue")
    elevator.Material = Enum.Material.SmoothPlastic
    elevator.Transparency = 0.3
    elevator.Parent = workspace
    
    activeElevator = elevator
    return elevator
end

-- Move elevator smoothly to target Y (player stands on elevator naturally)
local function moveElevator(elevator, targetY, speed)
    if not elevator or not elevator.Parent then return false end
    
    speed = speed or 8 -- slower speed for smoother movement
    local currentY = elevator.Position.Y
    local direction = targetY > currentY and 1 or -1
    local distance = math.abs(targetY - currentY)
    
    -- More steps for smoother animation
    local updateInterval = 0.016 -- ~60fps for smooth movement
    local totalTime = distance / speed
    local steps = math.ceil(totalTime / updateInterval)
    if steps < 1 then steps = 1 end
    
    local startY = currentY
    local startTime = tick()
    
    for i = 1, steps do
        if not elevator or not elevator.Parent then return false end
        if not CONFIG.FARM_ENABLED then return false end
        
        -- Calculate smooth position using linear interpolation
        local progress = i / steps
        local newY = startY + (targetY - startY) * progress
        
        -- Update elevator position - player stands on it naturally via collision
        elevator.Position = Vector3.new(elevator.Position.X, newY, elevator.Position.Z)
        
        task.wait(updateInterval)
    end
    
    -- Final position adjustment
    elevator.Position = Vector3.new(elevator.Position.X, targetY, elevator.Position.Z)
    
    return true
end

-- Destroy elevator
local function destroyElevator()
    if activeElevator and activeElevator.Parent then
        activeElevator:Destroy()
        activeElevator = nil
    end
end

-- Walk to center of second floor (preparation for elevator)
-- ИСПОЛЬЗУЕТ PATHFINDING для подъёма на 2 этаж
local function walkToSecondFloorCenter(plot)
    local stairsInfo = getPlotStairsInfo(plot)
    if not stairsInfo or not stairsInfo.secondFloorPart then
        log("[ELEVATOR] No stairs info or second floor part")
        return false
    end
    
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChild("Humanoid")
    if not hrp or not humanoid then return false end
    
    -- Позиция центра 2 этажа (где будет появляться лифт)
    local secondFloorCenter = stairsInfo.secondFloorPart.Position
    
    -- ИСПРАВЛЕНИЕ: Получаем позиции низа и верха лестницы
    local stairsBottom, stairsTop = getStairsPositions(plot)
    
    -- Если есть данные о лестнице - идём поэтапно (земля -> лестница -> 2 этаж)
    if stairsBottom and stairsTop then
        log("[ELEVATOR] Stage 1: Pathfinding to GROUND before stairs")
        log("[ELEVATOR] StairsBottom position: " .. string.format("%.1f, %.1f, %.1f", stairsBottom.X, stairsBottom.Y, stairsBottom.Z))
        log("[ELEVATOR] StairsTop position: " .. string.format("%.1f, %.1f, %.1f", stairsTop.X, stairsTop.Y, stairsTop.Z))
        
        updateStatus("Walking to stairs...", Color3.fromRGB(200, 200, 100))
        
        -- ВАЖНО: Создаём блокеры ДО построения маршрута!
        setupPathfindingModifiers()
        task.wait(0.1)
        
        -- ЭТАП 1: Идём к точке НА ЗЕМЛЕ перед лестницей (локальный pathfinding)
        local pathToGround = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            WaypointSpacing = 3,
            Costs = { Water = 100 }
        })
        
        local successGround, errorGround = pcall(function()
            pathToGround:ComputeAsync(hrp.Position, stairsBottom)
        end)
        
        local reachedGround = false
        if successGround and pathToGround.Status == Enum.PathStatus.Success then
            local waypointsGround = pathToGround:GetWaypoints()
            log("[ELEVATOR] Path to ground: " .. #waypointsGround .. " waypoints")
            
            if DEBUG_VISUALIZE_PATH then
                visualizePath(waypointsGround, stairsBottom)
            end
            
            -- Проходим до земли
            for i, waypoint in ipairs(waypointsGround) do
                if not CONFIG.FARM_ENABLED then return false end
                
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                    task.wait(0.3)
                end
                
                humanoid:MoveTo(waypoint.Position)
                
                local waypointStart = tick()
                while tick() - waypointStart < 8 do
                    if not CONFIG.FARM_ENABLED then return false end
                    
                    local distToWaypoint = (hrp.Position - waypoint.Position).Magnitude
                    if distToWaypoint < 4 then break end
                    
                    task.wait(0.1)
                end
            end
            
            local distToStairsBottom = (hrp.Position - stairsBottom).Magnitude
            log("[ELEVATOR] Distance to stairs bottom after Stage 1: " .. string.format("%.1f", distToStairsBottom))
            reachedGround = distToStairsBottom < 12
        end
        
        if reachedGround then
            -- ЭТАП 2: Поднимаемся по лестнице к stairsTop (простое движение)
            log("[ELEVATOR] Stage 2: Climbing stairs to top")
            updateStatus("Climbing stairs...", Color3.fromRGB(200, 200, 100))
            
            -- Визуализация Stage 2 (простая линия)
            if DEBUG_VISUALIZE_PATH then
                -- Создаём фейковые waypoints для визуализации лестницы
                local stairsWaypoints = {
                    {Position = hrp.Position, Action = Enum.PathWaypointAction.Walk},
                    {Position = stairsTop, Action = Enum.PathWaypointAction.Walk}
                }
                visualizePath(stairsWaypoints, stairsTop)
            end
            
            humanoid:MoveTo(stairsTop)
            local climbStart = tick()
            local lastPos = hrp.Position
            local stuckTime = 0
            
            while tick() - climbStart < 20 do
                if not CONFIG.FARM_ENABLED then return false end
                
                local dist = (hrp.Position - stairsTop).Magnitude
                if dist < 5 then
                    log("[ELEVATOR] Successfully climbed stairs")
                    break
                end
                
                -- Проверка застревания
                local moved = (hrp.Position - lastPos).Magnitude
                if moved < 0.15 then
                    stuckTime = stuckTime + 0.1
                    if stuckTime > 1 then
                        humanoid.Jump = true
                        stuckTime = 0
                    end
                else
                    stuckTime = 0
                end
                
                lastPos = hrp.Position
                task.wait(0.1)
            end
            
            local distToStairsTop = (hrp.Position - stairsTop).Magnitude
            if distToStairsTop < 10 then
                -- ЭТАП 3: Идём к центру 2 этажа
                log("[ELEVATOR] Stage 3: Walking to 2nd floor center")
                updateStatus("Walking to 2nd floor center...", Color3.fromRGB(200, 200, 100))
                
                log("[ELEVATOR] Building pathfinding route to 2nd floor center: " .. string.format("%.1f, %.1f, %.1f", secondFloorCenter.X, secondFloorCenter.Y, secondFloorCenter.Z))
                
                -- На 2 этаже используем обычный pathfinding
                local pathTo2nd = PathfindingService:CreatePath({
                    AgentRadius = 2,
                    AgentHeight = 5,
                    AgentCanJump = true,
                    AgentCanClimb = true,
                    WaypointSpacing = 4,
                    Costs = { Water = 100 }
                })
                
                local success2, errorMsg2 = pcall(function()
                    pathTo2nd:ComputeAsync(hrp.Position, secondFloorCenter)
                end)
                
                if success2 and pathTo2nd.Status == Enum.PathStatus.Success then
                    local waypoints2nd = pathTo2nd:GetWaypoints()
                    log("[ELEVATOR] Path to 2nd floor center: " .. #waypoints2nd .. " waypoints")
                    
                    if DEBUG_VISUALIZE_PATH then
                        visualizePath(waypoints2nd, secondFloorCenter)
                    end
                    
                    -- Проходим по маршруту на 2 этаже
                    for i, waypoint in ipairs(waypoints2nd) do
                        if not CONFIG.FARM_ENABLED then return false end
                        
                        if waypoint.Action == Enum.PathWaypointAction.Jump then
                            humanoid.Jump = true
                            task.wait(0.3)
                        end
                        
                        humanoid:MoveTo(waypoint.Position)
                        
                        local waypointStart = tick()
                        while tick() - waypointStart < 8 do
                            if not CONFIG.FARM_ENABLED then return false end
                            
                            local distToWaypoint = (hrp.Position - waypoint.Position).Magnitude
                            local distToTarget = (hrp.Position - secondFloorCenter).Magnitude
                            
                            if distToWaypoint < 5 then break end
                            if distToTarget < 6 then
                                log("[ELEVATOR] Reached 2nd floor center (via staged path)")
                                return true
                            end
                            
                            task.wait(0.1)
                        end
                    end
                    
                    local finalDist = (hrp.Position - secondFloorCenter).Magnitude
                    log("[ELEVATOR] Staged path complete. Final distance: " .. string.format("%.1f", finalDist))
                    return finalDist < 15
                end
            end
        end
    end
    
    -- FALLBACK: Если поэтапный путь не сработал - пробуем прямой pathfinding
    log("[ELEVATOR] Fallback: Direct pathfinding route to 2nd floor center: " .. string.format("%.1f, %.1f, %.1f", secondFloorCenter.X, secondFloorCenter.Y, secondFloorCenter.Z))
    updateStatus("Pathfinding to 2nd floor...", Color3.fromRGB(200, 200, 100))
    
    -- Строим маршрут PATHFINDER до центра 2 этажа
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 4,
        Costs = { Water = 100 }
    })
    
    local success, errorMsg = pcall(function()
        path:ComputeAsync(hrp.Position, secondFloorCenter)
    end)
    
    if not success or path.Status ~= Enum.PathStatus.Success then
        log("[ELEVATOR] Failed to compute path to 2nd floor: " .. tostring(errorMsg or path.Status))
        return false
    end
    
    local waypoints = path:GetWaypoints()
    log("[ELEVATOR] Path to 2nd floor: " .. #waypoints .. " waypoints")
    
    -- Визуализация
    if DEBUG_VISUALIZE_PATH then
        visualizePath(waypoints, secondFloorCenter)
    end
    
    -- Проходим по маршруту
    local startTime = tick()
    local timeout = 30
    
    for i, waypoint in ipairs(waypoints) do
        if not CONFIG.FARM_ENABLED then return false end
        if tick() - startTime > timeout then return false end
        
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
            task.wait(0.3)
        end
        
        humanoid:MoveTo(waypoint.Position)
        
        local waypointStart = tick()
        local lastPos = hrp.Position
        local stuckTime = 0
        
        while tick() - waypointStart < 10 do
            if not CONFIG.FARM_ENABLED then return false end
            
            local currentPos = hrp.Position
            local distToWaypoint = (currentPos - waypoint.Position).Magnitude
            local distToTarget = (currentPos - secondFloorCenter).Magnitude
            
            if distToWaypoint < 5 then break end
            if distToTarget < 6 then
                log("[ELEVATOR] Reached 2nd floor center")
                return true
            end
            
            local moved = (currentPos - lastPos).Magnitude
            if moved < 0.15 then
                stuckTime = stuckTime + 0.1
                if stuckTime > 1.5 then
                    humanoid.Jump = true
                    stuckTime = 0
                end
            else
                stuckTime = 0
            end
            
            lastPos = currentPos
            task.wait(0.1)
        end
    end
    
    -- Проверяем дошли ли
    local finalDist = (hrp.Position - secondFloorCenter).Magnitude
    log("[ELEVATOR] Path complete to 2nd floor. Final distance: " .. string.format("%.1f", finalDist))
    return finalDist < 15
end

-- Ride elevator to third floor
local function rideElevatorToThirdFloor(plot)
    local thirdFloorInfo = getThirdFloorInfo(plot)
    if not thirdFloorInfo then
        return false
    end
    
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    -- Disable ladder collision so player doesn't get stuck
    disableLadderCollision(plot)
    
    -- Get third floor target position and size
    local thirdFloorPos = thirdFloorInfo.position
    local thirdFloorSize = thirdFloorInfo.size
    
    -- Create elevator at ThirdFloor X,Z position but at player's Y level
    -- This way elevator will rise straight up into ThirdFloor like a puzzle piece
    local elevatorStartY = hrp.Position.Y - 3.5 -- just under player feet
    local elevatorPos = Vector3.new(thirdFloorPos.X, elevatorStartY, thirdFloorPos.Z)
    
    updateStatus("Creating elevator...", Color3.fromRGB(100, 200, 255))
    local elevator = createElevator(elevatorPos, thirdFloorSize)
    
    if not elevator then
        restoreLadderCollision() -- Restore on failure
        return false
    end
    
    -- Wait a moment for player to settle on elevator
    task.wait(0.5)
    
    -- Move elevator up to exact ThirdFloor Y position (fit like a puzzle)
    local targetY = thirdFloorPos.Y
    updateStatus("Rising to 3rd floor...", Color3.fromRGB(100, 255, 200))
    
    if not moveElevator(elevator, targetY, 8) then
        restoreLadderCollision() -- Restore on failure
        return false
    end
    
    task.wait(0.3)
    return true
end

-- Ride elevator down from third floor
local function rideElevatorDownFromThirdFloor(plot)
    if not activeElevator or not activeElevator.Parent then
        restoreLadderCollision() -- Restore anyway
        return false
    end
    
    local stairsInfo = getPlotStairsInfo(plot)
    local secondFloorY = 10 -- default second floor Y
    if stairsInfo and stairsInfo.secondFloorPart then
        secondFloorY = stairsInfo.secondFloorPart.Position.Y
    end
    
    -- Move elevator down to second floor level (slower for smoother descent)
    updateStatus("Descending to 2nd floor...", Color3.fromRGB(100, 200, 255))
    local targetY = secondFloorY - 2
    
    if not moveElevator(activeElevator, targetY, 8) then
        restoreLadderCollision() -- Restore on failure
        return false
    end
    
    task.wait(0.5)
    
    -- Destroy elevator after descent
    destroyElevator()
    
    -- Restore ladder collision after safe descent
    restoreLadderCollision()
    
    return true
end

-- Full route to third floor: stairs -> second floor center -> elevator -> third floor
local function walkToThirdFloor(plot)
    updateStatus("Route to 3rd floor...", Color3.fromRGB(200, 200, 100))
    
    -- Step 1: Walk to second floor via stairs and reach center
    if not walkToSecondFloorCenter(plot) then
        return false
    end
    
    -- Step 2: Walk to position under ThirdFloor (align with third floor center)
    local thirdFloorInfo = getThirdFloorInfo(plot)
    if not thirdFloorInfo then
        return false
    end
    
    -- Walk to position directly under third floor
    -- ВАЖНО: Используем walkToSimple на 2-м этаже чтобы не строить путь внизу!
    local alignPos = Vector3.new(thirdFloorInfo.position.X, LocalPlayer.Character.HumanoidRootPart.Position.Y, thirdFloorInfo.position.Z)
    updateStatus("Aligning under 3rd floor...", Color3.fromRGB(200, 200, 100))
    logPathfinding("Aligning under 3rd floor with SIMPLE movement (no pathfinding on 2nd floor)")
    if not walkToSimple(alignPos, 10) then
        return false
    end
    
    -- Step 3: Create and ride elevator
    if not rideElevatorToThirdFloor(plot) then
        return false
    end
    
    updateStatus("On 3rd floor!", Color3.fromRGB(100, 255, 100))
    return true
end

-- Full route down from third floor
local function walkDownFromThirdFloor(plot)
    updateStatus("Returning from 3rd floor...", Color3.fromRGB(200, 200, 100))
    
    -- First, walk back to elevator center if not there
    -- ВАЖНО: Используем walkToSimple (без PathfindingService) чтобы не строить путь внизу!
    if activeElevator and activeElevator.Parent then
        local elevatorCenter = activeElevator.Position
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local distToElevator = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(elevatorCenter.X, 0, elevatorCenter.Z)).Magnitude
            if distToElevator > 2 then
                updateStatus("Walking to elevator...", Color3.fromRGB(200, 200, 100))
                -- Walk to elevator center position at current Y level
                -- Используем ПРОСТОЕ движение, не PathfindingService!
                local targetPos = Vector3.new(elevatorCenter.X, hrp.Position.Y, elevatorCenter.Z)
                logPathfinding("Walking to elevator with SIMPLE movement (no pathfinding on 3rd floor)")
                walkToSimple(targetPos, 10)
                -- Wait for player to settle on elevator
                task.wait(0.5)
            end
        end
    else
        -- Лифт не существует - нужно создать его
        logPathfinding("No active elevator found, creating one for descent", "WARN")
        local thirdFloorInfo = getThirdFloorInfo(plot)
        if thirdFloorInfo then
            local character = LocalPlayer.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            if hrp then
                -- Сначала идём к позиции над 3-м этажом (простым движением!)
                local targetPos = Vector3.new(thirdFloorInfo.position.X, hrp.Position.Y, thirdFloorInfo.position.Z)
                updateStatus("Walking to elevator position...", Color3.fromRGB(200, 200, 100))
                walkToSimple(targetPos, 10)
                task.wait(0.3)
                
                -- Создаём лифт под игроком
                local elevatorStartY = hrp.Position.Y - 3.5
                local elevatorPos = Vector3.new(thirdFloorInfo.position.X, elevatorStartY, thirdFloorInfo.position.Z)
                createElevator(elevatorPos, thirdFloorInfo.size)
                disableLadderCollision(plot)
                task.wait(0.3)
            end
        end
    end
    
    -- Ride elevator down
    if not rideElevatorDownFromThirdFloor(plot) then
        -- Force destroy elevator as fallback
        destroyElevator()
        -- Make sure ladder collision is restored
        restoreLadderCollision()
    end
    
    -- Then walk down stairs from second floor
    return walkDownFromSecondFloor(plot)
end

-- ============ SMART NAVIGATION SYSTEM ============
-- Умная навигация между этажами с учётом текущего положения

-- Спуститься с текущего этажа на целевой
local function descendToFloor(plot, currentFloor, targetFloor)
    if currentFloor <= targetFloor then return true end
    
    updateStatus("Descending from floor " .. currentFloor .. " to " .. targetFloor .. "...", Color3.fromRGB(200, 200, 100))
    
    -- С 3 этажа
    if currentFloor == 3 then
        if not walkDownFromThirdFloor(plot) then
            return false
        end
        currentFloor = 2
    end
    
    -- С 2 этажа на 1
    if currentFloor == 2 and targetFloor == 1 then
        if not walkDownFromSecondFloor(plot) then
            return false
        end
    end
    
    return true
end

-- Подняться с текущего этажа на целевой
local function ascendToFloor(plot, currentFloor, targetFloor)
    if currentFloor >= targetFloor then return true end
    
    updateStatus("Ascending from floor " .. currentFloor .. " to " .. targetFloor .. "...", Color3.fromRGB(200, 200, 100))
    
    -- С 1 этажа на 2
    if currentFloor == 1 and targetFloor >= 2 then
        if not walkToSecondFloor(plot) then
            return false
        end
        currentFloor = 2
    end
    
    -- С 2 этажа на 3
    if currentFloor == 2 and targetFloor == 3 then
        if not walkToThirdFloor(plot) then
            return false
        end
    end
    
    return true
end

-- Полная навигация с любого этажа на любой другой
local function navigateToFloor(plot, targetFloor, myCarpetPos, targetCarpetPos)
    local currentFloor = getPlayerCurrentFloor()
    -- Если уже на нужном этаже - ничего не делаем
    if currentFloor == targetFloor then
        return true
    end
    
    -- СНАЧАЛА нужно спуститься с текущего этажа до первого (если на верхнем)
    if currentFloor > 1 then
        updateStatus("First descending to ground...", Color3.fromRGB(200, 200, 100))
        
        -- Находим на какой базе мы сейчас находимся по позиции
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local plotsFolder = workspace:FindFirstChild("Plots")
            if plotsFolder then
                local closestPlot = nil
                local closestDist = math.huge
                for _, p in ipairs(plotsFolder:GetChildren()) do
                    local carpet = p:FindFirstChild("Flying Carpet")
                    if carpet then
                        local dist = (hrp.Position - carpet.Position).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestPlot = p
                        end
                    end
                end
                if closestPlot then
                    if not descendToFloor(closestPlot, currentFloor, 1) then
                        return false
                    end
                end
            end
        end
        
        -- После спуска - идём к своему карпету (1 этаж)
        if myCarpetPos then
            walkTo(myCarpetPos, 15)
        end
        
        -- Если целевой carpet далеко - идём к нему
        if targetCarpetPos and myCarpetPos then
            local dist = (myCarpetPos - targetCarpetPos).Magnitude
            if dist > 30 then
                walkTo(targetCarpetPos, 15)
            end
        end
    end
    
    -- Теперь мы на 1 этаже, поднимаемся на целевой
    if targetFloor > 1 then
        if not ascendToFloor(plot, 1, targetFloor) then
            return false
        end
    end
    
    return true
end

-- Безопасное возвращение на 1 этаж с любой позиции
local function safeReturnToGround(plot, myCarpetPos)
    local currentFloor = getPlayerCurrentFloor()
    
    -- Получаем текущую позицию
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local myPos = hrp.Position
    
    if currentFloor <= 1 then
        -- Уже на земле, просто идём к ближайшему карпету, потом к своему
        local plotsFolder = workspace:FindFirstChild("Plots")
        if plotsFolder then
            local closestCarpet = nil
            local closestDist = math.huge
            for _, p in ipairs(plotsFolder:GetChildren()) do
                local carpet = p:FindFirstChild("Flying Carpet")
                if carpet then
                    local dist = (myPos - carpet.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closestCarpet = carpet.Position
                    end
                end
            end
            -- Идём к ближайшему ковру
            if closestCarpet and closestDist < 100 then
                walkTo(closestCarpet, 15)
            end
        end
        -- Потом к своему
        if myCarpetPos then
            walkTo(myCarpetPos, 15)
        end
        return true
    end
    
    -- Мы на верхнем этаже - ищем БЛИЖАЙШУЮ базу для спуска
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return false end
    
    -- Ищем ближайшую базу (по горизонтальному расстоянию)
    local closestPlot = nil
    local closestDist = math.huge
    for _, p in ipairs(plotsFolder:GetChildren()) do
        local carpet = p:FindFirstChild("Flying Carpet")
        if carpet then
            -- Горизонтальное расстояние (игнорируем Y)
            local dx = myPos.X - carpet.Position.X
            local dz = myPos.Z - carpet.Position.Z
            local dist = math.sqrt(dx*dx + dz*dz)
            if dist < closestDist then
                closestDist = dist
                closestPlot = p
            end
        end
    end
    
    if not closestPlot then 
        log("safeReturnToGround: No plot found for descent", "WARN")
        return false 
    end
    
    log("safeReturnToGround: Floor=" .. currentFloor .. ", closest plot: " .. closestPlot.Name .. " dist=" .. string.format("%.1f", closestDist))
    
    -- Пробуем спуститься с ближайшей базы
    local success = false
    
    if currentFloor == 3 then
        -- С 3 этажа - сначала пробуем лифт/лестницу
        success = walkDownFromThirdFloor(closestPlot)
        if success then
            currentFloor = 2
        end
    end
    
    if currentFloor == 2 then
        -- С 2 этажа - спускаемся по лестнице
        success = walkDownFromSecondFloor(closestPlot)
        if success then
            currentFloor = 1
        end
    end
    
    -- Если не получилось спуститься - пробуем просто упасть вниз к ближайшему ковру
    if currentFloor > 1 then
        log("safeReturnToGround: Normal descent failed, trying direct fall", "WARN")
        local carpet = closestPlot:FindFirstChild("Flying Carpet")
        if carpet then
            -- Телепортируемся немного выше ковра и падаем
            local fallPos = Vector3.new(carpet.Position.X, carpet.Position.Y + 5, carpet.Position.Z)
            walkTo(fallPos, 10)
            task.wait(0.5)
        end
    end
    
    -- После спуска идём к своему карпету
    if myCarpetPos then
        walkTo(myCarpetPos, 15)
    end
    
    return getPlayerCurrentFloor() <= 1
end

-- ============ END SMART NAVIGATION ============
-- ============ END ELEVATOR SYSTEM ============

local function isCarryingBrainrot()
    return LocalPlayer:GetAttribute("Stealing") == true
end

-- Простой pathfind к точке (без проверок brainrot)
-- ВАЖНО: Строгая валидация каждого вейпоинта перед переходом к следующему
local function simplePathfindTo(position, timeout, retryCount, lastReachedWaypointIndex)
    retryCount = retryCount or 0
    lastReachedWaypointIndex = lastReachedWaypointIndex or 0
    local maxRetries = 10
    
    local character = LocalPlayer.Character
    if not character then return false end
    local humanoid = character:FindFirstChild("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp then return false end
    
    timeout = timeout or 30
    local startTime = tick()
    
    -- Уже рядом?
    local distToTarget = (hrp.Position - position).Magnitude
    if distToTarget < 5 then
        return true
    end
    
    -- Логируем текущий этаж для отладки
    local playerFloor = getPlayerCurrentFloor()
    log("[PATHFIND-SIMPLE] Computing path (attempt " .. (retryCount + 1) .. "), dist=" .. string.format("%.1f", distToTarget) .. ", floor=" .. playerFloor)
    
    -- Устанавливаем блокеры на первой попытке
    if retryCount == 0 then
        setupPathfindingModifiers()
        task.wait(0.1)
    end
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 3,          -- Увеличен для лучшего обхода препятствий
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 2.5,    -- Уменьшен для более точного пути
        Costs = { 
            Water = math.huge,    -- Вода непроходима
            Neon = 50,            -- Избегаем neon части
        }
    })
    
    local success, errorMsg = pcall(function()
        path:ComputeAsync(hrp.Position, position)
    end)
    
    if not success or path.Status ~= Enum.PathStatus.Success then
        log("[PATHFIND-SIMPLE] Path failed: " .. tostring(errorMsg or path.Status))
        if retryCount < maxRetries then
            task.wait(0.3)
            return simplePathfindTo(position, timeout - 1, retryCount + 1, 0)
        end
        return false
    end
    
    local waypoints = path:GetWaypoints()
    log("[PATHFIND-SIMPLE] Path: " .. #waypoints .. " waypoints")
    
    if DEBUG_VISUALIZE_PATH then
        visualizePath(waypoints, position)
    end
    
    local currentWaypointIndex = 1
    
    while currentWaypointIndex <= #waypoints do
        local waypoint = waypoints[currentWaypointIndex]
        if not CONFIG.FARM_ENABLED then return false end
        if tick() - startTime > timeout then
            log("[PATHFIND-SIMPLE] Timeout at waypoint " .. currentWaypointIndex)
            if retryCount < maxRetries then
                -- Ретрай с последнего достигнутого вейпоинта
                return simplePathfindTo(position, timeout, retryCount + 1, currentWaypointIndex - 1)
            end
            return false
        end
        
        -- ВАЛИДАЦИЯ: Проверяем что вейпоинт достижим (на том же этаже)
        local waypointHeightDiff = math.abs(waypoint.Position.Y - hrp.Position.Y)
        if waypointHeightDiff > 10 then
            log("[PATHFIND-SIMPLE] Waypoint " .. currentWaypointIndex .. " unreachable (height diff=" .. string.format("%.1f", waypointHeightDiff) .. "), skipping")
            currentWaypointIndex = currentWaypointIndex + 1
            continue
        end
        
        humanoid:MoveTo(waypoint.Position)
        
        local waypointStart = tick()
        local lastPos = hrp.Position
        local stuckTime = 0
        local waypointReached = false
        
        while tick() - waypointStart < 5 do
            if not CONFIG.FARM_ENABLED then return false end
            
            local currentPos = hrp.Position
            local distToWaypoint = (currentPos - waypoint.Position).Magnitude
            local horizontalDist = ((currentPos - waypoint.Position) * Vector3.new(1, 0, 1)).Magnitude
            
            -- ВАЛИДАЦИЯ: Дошли до waypoint
            if horizontalDist < 3 or distToWaypoint < 4 then 
                waypointReached = true
                log("[PATHFIND-SIMPLE] Waypoint " .. currentWaypointIndex .. " reached")
                break 
            end
            
            -- Дошли до цели
            if (currentPos - position).Magnitude < 5 then
                log("[PATHFIND-SIMPLE] Target reached early")
                return true
            end
            
            -- Застревание - попытка обхода
            local moved = (currentPos - lastPos).Magnitude
            if moved < 0.2 then
                stuckTime = stuckTime + 0.1
                
                -- Первая попытка - прыжок (УСКОРЕНО)
                if stuckTime > 0.25 and stuckTime < 0.4 then
                    humanoid.Jump = true
                    humanoid:MoveTo(waypoint.Position)
                end
                
                -- Вторая попытка - сдвиг влево для обхода препятствия (УСКОРЕНО)
                if stuckTime > 0.5 and stuckTime < 0.7 then
                    local dirToWaypoint = (waypoint.Position - currentPos).Unit
                    local sideOffset = Vector3.new(-dirToWaypoint.Z, 0, dirToWaypoint.X) * 5 -- Сдвиг влево
                    humanoid:MoveTo(currentPos + sideOffset)
                    task.wait(0.3)
                    humanoid:MoveTo(waypoint.Position)
                end
                
                -- Третья попытка - сдвиг вправо (УСКОРЕНО)
                if stuckTime > 0.9 and stuckTime < 1.1 then
                    local dirToWaypoint = (waypoint.Position - currentPos).Unit
                    local sideOffset = Vector3.new(dirToWaypoint.Z, 0, -dirToWaypoint.X) * 5 -- Сдвиг вправо
                    humanoid:MoveTo(currentPos + sideOffset)
                    task.wait(0.3)
                    humanoid:MoveTo(waypoint.Position)
                end
                
                -- Четвёртая попытка - большой обход (УСКОРЕНО)
                if stuckTime > 1.3 and stuckTime < 1.5 then
                    local dirToWaypoint = (waypoint.Position - currentPos).Unit
                    local sideOffset = Vector3.new(-dirToWaypoint.Z, 0, dirToWaypoint.X) * 10 -- Большой сдвиг влево
                    humanoid:MoveTo(currentPos + sideOffset)
                    task.wait(0.4)
                    humanoid:MoveTo(waypoint.Position)
                end
                
                if stuckTime > 1.8 then  -- УСКОРЕНО с 2.5
                    log("[PATHFIND-SIMPLE] Stuck at waypoint " .. currentWaypointIndex .. ", rebuilding from previous...")
                    if retryCount < maxRetries then
                        -- ВАЖНО: Ретрай с текущего вейпоинта (не сначала!)
                        return simplePathfindTo(position, timeout, retryCount + 1, math.max(0, currentWaypointIndex - 1))
                    end
                    return false
                end
            else
                stuckTime = 0
            end
            
            lastPos = currentPos
            task.wait(0.1)
        end
        
        -- ВАЛИДАЦИЯ: Если вейпоинт не достигнут - ретрай
        if not waypointReached then
            log("[PATHFIND-SIMPLE] Failed to reach waypoint " .. currentWaypointIndex .. ", retrying from previous")
            if retryCount < maxRetries then
                -- Проверяем этаж перед ретраем
                local currentFloor = getPlayerCurrentFloor()
                if currentFloor ~= playerFloor then
                    log("[PATHFIND-SIMPLE] Floor changed during path! Was " .. playerFloor .. ", now " .. currentFloor)
                    return false -- Вернуть false чтобы внешний код обработал смену этажа
                end
                return simplePathfindTo(position, timeout, retryCount + 1, math.max(0, currentWaypointIndex - 1))
            end
            return false
        end
        
        currentWaypointIndex = currentWaypointIndex + 1
    end
    
    local finalDist = (hrp.Position - position).Magnitude
    log("[PATHFIND-SIMPLE] Path complete. Final dist: " .. string.format("%.1f", finalDist))
    return finalDist < 8
end

-- Специальная версия walkTo для движения к brainrot - проверяет подбор
-- С разбиением на этапы: земля -> низ лестницы -> верх лестницы -> brainrot
-- ВАЖНО: Строгая проверка этажа перед каждым действием!
local function walkToBrainrot(position, timeout, retryCount, plot, brainrotFloor)
    retryCount = retryCount or 0
    local maxRetries = 10
    
    local character = LocalPlayer.Character
    if not character then return false, false end
    local humanoid = character:FindFirstChild("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp then return false, false end
    
    timeout = timeout or 45
    local startTime = tick()
    
    -- Уже подобрали?
    if isCarryingBrainrot() then return true, true end
    
    -- Уже рядом?
    local distToTarget = (hrp.Position - position).Magnitude
    if distToTarget < 6 then
        log("[PATHFIND] Already near brainrot")
        return true, false
    end
    
    -- СТРОГАЯ ПРОВЕРКА ЭТАЖА
    local playerFloor = getPlayerCurrentFloor()
    brainrotFloor = brainrotFloor or 1
    
    log("[PATHFIND] Walking to brainrot (attempt " .. (retryCount + 1) .. ")")
    log("[PATHFIND] Player floor: " .. playerFloor .. ", brainrot floor: " .. brainrotFloor)
    
    -- ВАЛИДАЦИЯ: Нельзя идти к brainrot на 3 этаже если мы не на 3 этаже
    if brainrotFloor == 3 and playerFloor ~= 3 then
        log("[PATHFIND] ERROR: Brainrot on floor 3 but player on floor " .. playerFloor .. " - need elevator!")
        return false, false
    end
    
    -- ВАЛИДАЦИЯ: Нельзя идти к brainrot на 2 этаже если мы на 3 (нужен лифт вниз)
    if brainrotFloor == 2 and playerFloor == 3 then
        log("[PATHFIND] ERROR: Brainrot on floor 2 but player on floor 3 - need to descend first!")
        return false, false
    end
    
    -- ЭТАП 1: Если brainrot на 2 этаже и мы на 1 этаже - используем лестницу
    if brainrotFloor >= 2 and playerFloor == 1 and plot then
        local stairsBottom, stairsTop = getStairsPositions(plot)
        
        if stairsBottom and stairsTop then
            log("[PATHFIND] Brainrot on floor " .. brainrotFloor .. ", need to climb stairs")
            log("[PATHFIND] Ground position before stairs: " .. string.format("%.1f, %.1f, %.1f", stairsBottom.X, stairsBottom.Y, stairsBottom.Z))
            log("[PATHFIND] Top of stairs: " .. string.format("%.1f, %.1f, %.1f", stairsTop.X, stairsTop.Y, stairsTop.Z))
            
            -- ЭТАП 1a: Pathfind до точки НА ЗЕМЛЕ перед первой ступенькой
            log("[PATHFIND] Stage 1: Walking to ground BEFORE first step")
            if not simplePathfindTo(stairsBottom, 25) then
                log("[PATHFIND] Failed to reach ground before stairs")
                if retryCount < maxRetries then
                    task.wait(0.3)
                    return walkToBrainrot(position, timeout, retryCount + 1, plot, brainrotFloor)
                end
                return false, false
            end
            if isCarryingBrainrot() then return true, true end
            
            -- ВАЛИДАЦИЯ: Убеждаемся что мы достигли точки перед лестницей
            local distToStairsBottom = (hrp.Position - stairsBottom).Magnitude
            if distToStairsBottom > 8 then
                log("[PATHFIND] Did not reach ground before stairs (dist=" .. string.format("%.1f", distToStairsBottom) .. "), retrying")
                if retryCount < maxRetries then
                    task.wait(0.3)
                    return walkToBrainrot(position, timeout, retryCount + 1, plot, brainrotFloor)
                end
                return false, false
            end
            
            -- ЭТАП 1b: Теперь поднимаемся по лестнице к верху
            log("[PATHFIND] Stage 2: Climbing stairs to top")
            if not simpleWalkTo(stairsTop, 20, true) then
                log("[PATHFIND] Failed to climb stairs")
                if retryCount < maxRetries then
                    task.wait(0.3)
                    return walkToBrainrot(position, timeout, retryCount + 1, plot, brainrotFloor)
                end
                return false, false
            end
            if isCarryingBrainrot() then return true, true end
            
            -- ВАЛИДАЦИЯ: Проверяем что мы теперь на 2 этаже
            local newFloor = getPlayerCurrentFloor()
            if newFloor < 2 then
                log("[PATHFIND] Still on floor " .. newFloor .. " after climbing stairs, retrying")
                if retryCount < maxRetries then
                    task.wait(0.3)
                    return walkToBrainrot(position, timeout, retryCount + 1, plot, brainrotFloor)
                end
                return false, false
            end
            
            log("[PATHFIND] Stage 3: Now on floor " .. newFloor .. ", pathfinding to brainrot")
        else
            log("[PATHFIND] WARNING: No stairs found for plot!")
        end
    end
    
    -- ЭТАП 2: Идём к brainrot (теперь уже на том же этаже или без лестницы)
    -- ВАЛИДАЦИЯ: Ещё раз проверяем этаж
    local currentFloorBeforePath = getPlayerCurrentFloor()
    log("[PATHFIND] Computing path to brainrot (attempt " .. (retryCount + 1) .. "), floor=" .. currentFloorBeforePath)
    
    -- Устанавливаем блокеры на первой попытке
    if retryCount == 0 then
        setupPathfindingModifiers()
        task.wait(0.1)
    end
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 3,          -- Увеличен для лучшего обхода дерева и препятствий
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 2.5,    -- Уменьшен для более точного пути
        Costs = { 
            Water = math.huge,    -- Вода непроходима
            Neon = 50,            -- Избегаем neon части
        }
    })
    
    local success, errorMsg = pcall(function()
        path:ComputeAsync(hrp.Position, position)
    end)
    
    if not success or path.Status ~= Enum.PathStatus.Success then
        log("[PATHFIND] Path failed: " .. tostring(errorMsg or path.Status))
        if retryCount < maxRetries then
            task.wait(0.3)
            return walkToBrainrot(position, timeout - 1, retryCount + 1, plot, brainrotFloor)
        end
        return false, false
    end
    
    local waypoints = path:GetWaypoints()
    log("[PATHFIND] Path: " .. #waypoints .. " waypoints")
    
    if DEBUG_VISUALIZE_PATH then
        visualizePath(waypoints, position)
    end
    
    local currentWaypointIndex = 1
    local lastReachedWaypointIndex = 0
    
    while currentWaypointIndex <= #waypoints do
        local waypoint = waypoints[currentWaypointIndex]
        if not CONFIG.FARM_ENABLED then return false, false end
        if tick() - startTime > timeout then
            log("[PATHFIND] Timeout at waypoint " .. currentWaypointIndex .. ", rebuilding from " .. lastReachedWaypointIndex)
            -- ВАЛИДАЦИЯ: Проверяем этаж перед ретраем
            local floorBeforeRetry = getPlayerCurrentFloor()
            if floorBeforeRetry ~= currentFloorBeforePath then
                log("[PATHFIND] Floor changed! Was " .. currentFloorBeforePath .. ", now " .. floorBeforeRetry)
                return false, false -- Вернуть false чтобы внешний код обработал
            end
            if retryCount < maxRetries then
                return walkToBrainrot(position, 25, retryCount + 1, plot, brainrotFloor)
            end
            return false, false
        end
        
        -- Проверяем подобрали ли brainrot
        if isCarryingBrainrot() then
            log("[PATHFIND] Picked up brainrot!")
            return true, true
        end
        
        -- Проверяем не дошли ли уже
        local distToTarget2 = (hrp.Position - position).Magnitude
        if distToTarget2 < 6 then
            log("[PATHFIND] Reached brainrot early")
            if isCarryingBrainrot() then return true, true end
            return true, false
        end
        
        -- ВАЛИДАЦИЯ: Проверяем что вейпоинт достижим
        local heightDiff = waypoint.Position.Y - hrp.Position.Y
        
        -- Если waypoint СЛИШКОМ высоко (>6 studs) - недостижим
        if heightDiff > 6 then
            log("[PATHFIND] Waypoint " .. currentWaypointIndex .. " unreachable (height=" .. string.format("%.1f", heightDiff) .. "), skipping")
            currentWaypointIndex = currentWaypointIndex + 1
            continue
        end
        
        -- Вычисляем горизонтальное расстояние до waypoint
        local horizontalDistToWp = ((hrp.Position - waypoint.Position) * Vector3.new(1, 0, 1)).Magnitude
        
        -- Прыжок если waypoint выше
        if waypoint.Action == Enum.PathWaypointAction.Jump or (heightDiff > 0.5 and horizontalDistToWp < 4) then
            humanoid.Jump = true
        end
        
        humanoid:MoveTo(waypoint.Position)
        
        local waypointStart = tick()
        local lastPos = hrp.Position
        local stuckTime = 0
        local offPathTime = 0
        local lastJumpTime = 0
        local waypointReached = false
        
        while tick() - waypointStart < 6 do
            if not CONFIG.FARM_ENABLED then return false, false end
            
            if isCarryingBrainrot() then
                log("[PATHFIND] Picked up brainrot!")
                return true, true
            end
            
            local currentPos = hrp.Position
            local distToWaypoint = (currentPos - waypoint.Position).Magnitude
            local distToTarget3 = (currentPos - position).Magnitude
            
            -- Дошли до waypoint (по горизонтали)
            local horizontalDist = ((currentPos - waypoint.Position) * Vector3.new(1, 0, 1)).Magnitude
            
            -- Прыжок на лестницу если нужно
            local currentHeightDiff = waypoint.Position.Y - currentPos.Y
            if currentHeightDiff > 1.5 and horizontalDist < 12 then
                local now = tick()
                if now - lastJumpTime > 0.5 then
                    humanoid.Jump = true
                    humanoid:MoveTo(waypoint.Position)
                    lastJumpTime = now
                end
            end
            
            -- ВАЛИДАЦИЯ: Достигли вейпоинт
            if horizontalDist < 3 or distToWaypoint < 4 then 
                waypointReached = true
                lastReachedWaypointIndex = currentWaypointIndex
                log("[PATHFIND] Waypoint " .. currentWaypointIndex .. " reached")
                break 
            end
            
            if distToTarget3 < 6 then
                log("[PATHFIND] Reached brainrot")
                if isCarryingBrainrot() then return true, true end
                return true, false
            end
            
            -- Проверка отклонения
            if distToWaypoint > 10 then
                offPathTime = offPathTime + 0.1
                if offPathTime > 0.5 then
                    log("[PATHFIND] Off path, rebuilding from waypoint " .. lastReachedWaypointIndex)
                    -- ВАЛИДАЦИЯ: Проверяем этаж
                    local floorNow = getPlayerCurrentFloor()
                    if floorNow ~= currentFloorBeforePath then
                        log("[PATHFIND] Floor changed during off-path! Was " .. currentFloorBeforePath .. ", now " .. floorNow)
                        return false, false
                    end
                    if retryCount < maxRetries then
                        return walkToBrainrot(position, 30, retryCount + 1, plot, brainrotFloor)
                    end
                end
            else
                offPathTime = 0
            end
            
            -- Проверка застревания с попыткой обхода
            local moved = (currentPos - lastPos).Magnitude
            if moved < 0.15 then
                stuckTime = stuckTime + 0.1
                
                -- Первая попытка - прыжок
                if stuckTime > 0.4 and stuckTime < 0.6 then
                    humanoid.Jump = true
                    humanoid:MoveTo(waypoint.Position)
                end
                
                -- Вторая попытка - обход влево (для дерева и препятствий)
                if stuckTime > 0.9 and stuckTime < 1.1 then
                    local dirToWaypoint = (waypoint.Position - currentPos).Unit
                    local sideOffset = Vector3.new(-dirToWaypoint.Z, 0, dirToWaypoint.X) * 6
                    humanoid:MoveTo(currentPos + sideOffset)
                    task.wait(0.4)
                    humanoid:MoveTo(waypoint.Position)
                end
                
                -- Третья попытка - обход вправо
                if stuckTime > 1.4 and stuckTime < 1.6 then
                    local dirToWaypoint = (waypoint.Position - currentPos).Unit
                    local sideOffset = Vector3.new(dirToWaypoint.Z, 0, -dirToWaypoint.X) * 6
                    humanoid:MoveTo(currentPos + sideOffset)
                    task.wait(0.4)
                    humanoid:MoveTo(waypoint.Position)
                end
                
                -- Большой обход
                if stuckTime > 2.0 and stuckTime < 2.2 then
                    local dirToWaypoint = (waypoint.Position - currentPos).Unit
                    local sideOffset = Vector3.new(-dirToWaypoint.Z, 0, dirToWaypoint.X) * 12
                    humanoid:MoveTo(currentPos + sideOffset)
                    task.wait(0.5)
                    humanoid:MoveTo(waypoint.Position)
                end
                
                if stuckTime > 2.5 then
                    log("[PATHFIND] Stuck at waypoint " .. currentWaypointIndex .. ", rebuilding from " .. lastReachedWaypointIndex)
                    -- ВАЛИДАЦИЯ: Проверяем этаж
                    local floorNow = getPlayerCurrentFloor()
                    if floorNow ~= currentFloorBeforePath then
                        log("[PATHFIND] Floor changed while stuck! Was " .. currentFloorBeforePath .. ", now " .. floorNow)
                        return false, false
                    end
                    if retryCount < maxRetries then
                        return walkToBrainrot(position, 25, retryCount + 1, plot, brainrotFloor)
                    end
                end
            else
                stuckTime = 0
            end
            
            lastPos = currentPos
            task.wait(0.1)
        end
        
        -- ВАЛИДАЦИЯ: Если вейпоинт не достигнут - ретрай
        if not waypointReached then
            log("[PATHFIND] Failed to reach waypoint " .. currentWaypointIndex .. ", retrying from " .. lastReachedWaypointIndex)
            -- ВАЛИДАЦИЯ: Проверяем этаж
            local floorNow = getPlayerCurrentFloor()
            if floorNow ~= currentFloorBeforePath then
                log("[PATHFIND] Floor changed! Was " .. currentFloorBeforePath .. ", now " .. floorNow)
                return false, false
            end
            if retryCount < maxRetries then
                return walkToBrainrot(position, 25, retryCount + 1, plot, brainrotFloor)
            end
            return false, false
        end
        
        currentWaypointIndex = currentWaypointIndex + 1
    end
    
    -- Финальная проверка
    local finalDist = (hrp.Position - position).Magnitude
    log("[PATHFIND] Path complete. Final dist: " .. string.format("%.1f", finalDist))
    
    if isCarryingBrainrot() then return true, true end
    if finalDist < 10 then return true, false end
    
    return false, false
end

-- Найти ближайший plot к позиции игрока
local function findClosestPlotToPlayer()
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    
    local closestPlot = nil
    local closestDist = math.huge
    
    for _, p in ipairs(plotsFolder:GetChildren()) do
        local carpet = p:FindFirstChild("Flying Carpet")
        if carpet then
            local dx = hrp.Position.X - carpet.Position.X
            local dz = hrp.Position.Z - carpet.Position.Z
            local dist = math.sqrt(dx*dx + dz*dz)
            if dist < closestDist then
                closestDist = dist
                closestPlot = p
            end
        end
    end
    
    return closestPlot
end

-- Функция для pathfinding возврата к своему collect zone
-- С разбиением на этапы для спуска с лестницы
-- ВАЖНО: Строгая проверка этажа перед каждым действием!
local function pathfindToCollectZone(collectZonePos, timeout, retryCount)
    retryCount = retryCount or 0
    local maxRetries = 10
    
    local character = LocalPlayer.Character
    if not character then return false end
    local humanoid = character:FindFirstChild("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp then return false end
    
    timeout = timeout or 35
    local startTime = tick()
    
    local approachPos = Vector3.new(
        collectZonePos.X + 3,
        collectZonePos.Y + 2,
        collectZonePos.Z
    )
    
    -- Уже на месте?
    local distToCollect = (hrp.Position - approachPos).Magnitude
    if distToCollect <= 12 then
        log("[PATHFIND] Already at collect zone (dist=" .. string.format("%.1f", distToCollect) .. ")")
        return true
    end
    
    -- СТРОГАЯ ПРОВЕРКА ЭТАЖА
    local playerFloor = getPlayerCurrentFloor()
    log("[PATHFIND] pathfindToCollectZone (attempt " .. (retryCount + 1) .. "), player floor: " .. playerFloor)
    
    -- ВАЛИДАЦИЯ: Если на 3+ этаже - сначала спускаемся через лифт!
    if playerFloor >= 3 and retryCount == 0 then
        log("[PATHFIND] On floor " .. playerFloor .. ", need elevator to descend first!")
        local closestPlot = findClosestPlotToPlayer()
        if closestPlot then
            updateStatus("Descending from floor " .. playerFloor .. "...", Color3.fromRGB(255, 200, 100))
            walkDownFromThirdFloor(closestPlot)
            task.wait(0.5)
            
            -- Проверяем новый этаж
            local newFloor = getPlayerCurrentFloor()
            log("[PATHFIND] After elevator descent, now on floor " .. newFloor)
            
            if newFloor >= 3 then
                log("[PATHFIND] Still on floor " .. newFloor .. " after elevator, retrying")
                if retryCount < maxRetries then
                    task.wait(0.5)
                    return pathfindToCollectZone(collectZonePos, timeout, retryCount + 1)
                end
                return false
            end
        else
            log("[PATHFIND] ERROR: Cannot find plot for elevator descent!")
            return false
        end
    end
    
    -- После спуска с лифта - обновляем этаж
    playerFloor = getPlayerCurrentFloor()
    
    -- ЭТАП 0: Если мы на 2 этаже - сначала спускаемся по лестнице
    if playerFloor == 2 and retryCount == 0 then
        local closestPlot = findClosestPlotToPlayer()
        if closestPlot then
            local stairsBottom, stairsTop = getStairsPositions(closestPlot)
            
            if stairsBottom and stairsTop then
                log("[PATHFIND] On floor 2, descending stairs")
                log("[PATHFIND] Top of stairs: " .. string.format("%.1f, %.1f, %.1f", stairsTop.X, stairsTop.Y, stairsTop.Z))
                log("[PATHFIND] Ground before stairs: " .. string.format("%.1f, %.1f, %.1f", stairsBottom.X, stairsBottom.Y, stairsBottom.Z))
                
                -- ЭТАП 1: Идём к верху лестницы (если не там)
                local distToTop = (hrp.Position - stairsTop).Magnitude
                if distToTop > 5 then
                    log("[PATHFIND] Stage 1: Walking to top of stairs")
                    if not simplePathfindTo(stairsTop, 15) then
                        log("[PATHFIND] Failed to reach top of stairs")
                    end
                end
                
                -- ВАЛИДАЦИЯ: Проверяем что мы у верха лестницы
                distToTop = (hrp.Position - stairsTop).Magnitude
                if distToTop > 10 then
                    log("[PATHFIND] Not at top of stairs (dist=" .. string.format("%.1f", distToTop) .. "), retrying")
                    if retryCount < maxRetries then
                        task.wait(0.3)
                        return pathfindToCollectZone(collectZonePos, timeout, retryCount + 1)
                    end
                    return false
                end
                
                -- ЭТАП 2: Спускаемся по лестнице к земле
                log("[PATHFIND] Stage 2: Descending stairs to ground")
                simpleWalkTo(stairsBottom, 20, true)
                
                -- ВАЛИДАЦИЯ: Проверяем что мы теперь на 1 этаже
                local newFloor = getPlayerCurrentFloor()
                if newFloor > 1 then
                    log("[PATHFIND] Still on floor " .. newFloor .. " after descending, retrying")
                    if retryCount < maxRetries then
                        task.wait(0.3)
                        return pathfindToCollectZone(collectZonePos, timeout, retryCount + 1)
                    end
                    return false
                end
                
                log("[PATHFIND] Stage 3: Now on ground (floor " .. newFloor .. "), pathfinding to collect zone")
            else
                log("[PATHFIND] WARNING: No stairs found for descent!")
            end
        end
    end
    
    -- СНАЧАЛА устанавливаем блокеры, ПОТОМ строим маршрут
    if retryCount == 0 then
        setupPathfindingModifiers()
        task.wait(0.1) -- Даём время на создание блокеров
    end
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 3,          -- Увеличен для лучшего обхода препятствий
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 2.5,    -- Уменьшен для более точного пути
        Costs = { 
            Water = math.huge,    -- Вода непроходима
            Neon = 50,            -- Избегаем neon части
        }
    })
    
    local success, errorMsg = pcall(function()
        path:ComputeAsync(hrp.Position, approachPos)
    end)
    
    if not success or path.Status ~= Enum.PathStatus.Success then
        log("[PATHFIND] Failed to compute path: " .. tostring(errorMsg or path.Status))
        if retryCount < maxRetries then
            task.wait(0.5)
            return pathfindToCollectZone(collectZonePos, timeout - 1, retryCount + 1)
        end
        return false
    end
    
    local waypoints = path:GetWaypoints()
    log("[PATHFIND] Path: " .. #waypoints .. " waypoints")
    
    if DEBUG_VISUALIZE_PATH then
        visualizePath(waypoints, approachPos)
    end
    
    local i = 1
    while i <= #waypoints do
        local waypoint = waypoints[i]
        if not CONFIG.FARM_ENABLED then return false end
        if tick() - startTime > timeout then 
            log("[PATHFIND] Timeout, rebuilding...")
            if retryCount < maxRetries then
                return pathfindToCollectZone(collectZonePos, 20, retryCount + 1)
            end
            return false 
        end
        
        -- Проверяем высоту waypoint
        local heightDiff = waypoint.Position.Y - hrp.Position.Y
        
        -- Если waypoint СЛИШКОМ высоко (>4 studs) - пропускаем его
        if heightDiff > 4 then
            log("[PATHFIND] Skipping waypoint too high: " .. string.format("%.1f", heightDiff))
            i = i + 1
            continue
        end
        
        -- Вычисляем горизонтальное расстояние до waypoint
        local horizontalDistToWp = ((hrp.Position - waypoint.Position) * Vector3.new(1, 0, 1)).Magnitude
        
        -- Прыжок только если waypoint ЗНАЧИТЕЛЬНО выше (начало лестницы)
        if waypoint.Action == Enum.PathWaypointAction.Jump or (heightDiff > 1.5 and horizontalDistToWp < 12) then
            humanoid.Jump = true
        end
        
        humanoid:MoveTo(waypoint.Position)
        
        local waypointStart = tick()
        local lastPos = hrp.Position
        local stuckTime = 0
        local offPathTime = 0
        local lastJumpTime = 0
        
        while tick() - waypointStart < 6 do
            if not CONFIG.FARM_ENABLED then return false end
            
            local currentPos = hrp.Position
            local distToWaypoint = (currentPos - waypoint.Position).Magnitude
            local distToTarget2 = (currentPos - approachPos).Magnitude
            
            -- Вычисляем горизонтальное расстояние
            local horizontalDist = ((currentPos - waypoint.Position) * Vector3.new(1, 0, 1)).Magnitude
            
            -- Прыжок только если waypoint ЗНАЧИТЕЛЬНО выше (>1.5 studs) - начало лестницы
            -- На самой лестнице просто бежим без прыжков
            local currentHeightDiff = waypoint.Position.Y - currentPos.Y
            if currentHeightDiff > 1.5 and horizontalDist < 12 then
                local now = tick()
                if now - lastJumpTime > 0.5 then
                    humanoid.Jump = true
                    humanoid:MoveTo(waypoint.Position) -- Продолжаем движение сразу после прыжка
                    lastJumpTime = now
                end
            end
            
            -- Дошли до waypoint (по горизонтали)
            if horizontalDist < 2 or distToWaypoint < 3 then break end
            
            -- Проверка отклонения от маршрута - БЫСТРАЯ перестройка
            if distToWaypoint > 10 then
                offPathTime = offPathTime + 0.1
                if offPathTime > 0.5 then -- Через 0.5 сек отклонения - перестраиваем
                    log("[PATHFIND] Off path (dist=" .. string.format("%.1f", distToWaypoint) .. "), rebuilding...")
                    if retryCount < maxRetries then
                        return pathfindToCollectZone(collectZonePos, 25, retryCount + 1)
                    end
                end
            else
                offPathTime = 0
            end
            
            -- Проверка застревания - БЫСТРАЯ перестройка
            local moved = (currentPos - lastPos).Magnitude
            if moved < 0.15 then
                stuckTime = stuckTime + 0.1
                if stuckTime > 0.5 and stuckTime < 0.7 then
                    humanoid.Jump = true
                end
                if stuckTime > 1.0 then
                    log("[PATHFIND] Stuck, rebuilding...")
                    if retryCount < maxRetries then
                        return pathfindToCollectZone(collectZonePos, 25, retryCount + 1)
                    end
                end
            else
                stuckTime = 0
            end
            
            lastPos = currentPos
            task.wait(0.1)
        end
        i = i + 1
    end
    
    -- Детекция ТОЛЬКО после завершения ВСЕХ waypoints
    local finalDist = (hrp.Position - approachPos).Magnitude
    log("[PATHFIND] All waypoints completed. Final dist: " .. string.format("%.1f", finalDist))
    if finalDist < 12 then 
        log("[PATHFIND] Successfully reached collect zone!")
        return true 
    end
    
    -- Если не дошли - последняя попытка
    if retryCount < maxRetries then
        log("[PATHFIND] Not reached, final retry...")
        return pathfindToCollectZone(collectZonePos, 20, retryCount + 1)
    end
    
    return false
end

-- // COMPLETE STEAL FIX - Based on PlotClient.lua + AnimalPrompt.lua //
-- Two remotes are needed for steal:
-- 1. eb9dee81 - fires on PromptButtonHoldBegan (start holding)
-- 2. fce51e06 - fires on Triggered (steal action after hold completes)
local steal_hold_remote = nil  -- eb9dee81 - HoldBegan
local steal_action_remote = nil  -- fce51e06 - Steal action

-- // FIND STEAL REMOTES //
-- В SAFE_MODE не ищем ремоуты для кражи - они не нужны
if not SAFE_MODE then
    pcall(function()
        local net_folder = ReplicatedStorage:WaitForChild("Packages", 5):WaitForChild("Net", 5)
        
        -- Find HoldBegan remote (eb9dee81)
        steal_hold_remote = net_folder:FindFirstChild("RE/eb9dee81-7718-4020-b6b2-219888488d13")
        if not steal_hold_remote then
            for _, child in pairs(net_folder:GetChildren()) do
                if child.Name:find("eb9dee81") then
                    steal_hold_remote = child
                    break
                end
            end
        end
        
        -- Find Steal action remote (fce51e06)
        steal_action_remote = net_folder:FindFirstChild("RE/fce51e06-a587-4ff0-9e19-869eb1859a01")
        if not steal_action_remote then
            for _, child in pairs(net_folder:GetChildren()) do
                if child.Name:find("fce51e06") then
                    steal_action_remote = child
                    break
                end
            end
        end
        
        log("[STEAL] Remotes found: hold=" .. tostring(steal_hold_remote ~= nil) .. ", action=" .. tostring(steal_action_remote ~= nil))
    end)
end

local function tryStealBrainrot(brainrotData)
    if not brainrotData or not brainrotData.podium then return false end
    local plotUID = brainrotData.plot.Name
    local podiumIndex = tonumber(brainrotData.podiumIndex) or brainrotData.podiumIndex

    pcall(function()
        -- Step 1: Fire HoldBegan (simulates starting to hold the prompt)
        if steal_hold_remote then
            local hold_time = workspace:GetServerTimeNow() + 187
            steal_hold_remote:FireServer(hold_time, "ebc6aca1-afeb-49f3-9bd8-5be09e1bc187")
            steal_hold_remote:FireServer(hold_time, "9aba28d9-6365-4f5b-843c-f4830e87c058")
            log("[STEAL] HoldBegan sent")
        else
            log("[STEAL] HoldBegan remote not found!")
        end
    end)
    
    -- Wait for hold duration (1.5 seconds as per ProximityPrompt.HoldDuration)
    task.wait(1.6)
    
    pcall(function()
        -- Step 2: Fire Steal action (simulates prompt triggered after hold)
        if steal_action_remote then
            local action_time = workspace:GetServerTimeNow() + 56
            steal_action_remote:FireServer(action_time, "37feb1a5-fea5-4abc-8cc3-cb3ea2322c02", plotUID, podiumIndex)
            steal_action_remote:FireServer(action_time, "70646659-e472-4788-a9d8-cfa70e3d378c", plotUID, podiumIndex)
            log("[STEAL] Steal action sent for plot=" .. plotUID .. " slot=" .. tostring(podiumIndex))
        else
            log("[STEAL] Steal action remote not found!")
        end
    end)

    task.wait(0.5)
    return isCarryingBrainrot()
end

-- ============ COORDINATION (part 2 - remaining functions) ============
local function getBrainrotsFileName()
    return FARM_FOLDER .. "/brainrots_" .. LocalPlayer.Name .. ".json"
end

-- Обновить статус текущего аккаунта
local function updateAccountStatus(brainrotCount)
    local data = loadCoordination()
    cleanExpiredReservations(data)
    
    data.accountStatus[LocalPlayer.Name] = {
        brainrotCount = brainrotCount,
        lastUpdate = os.time(),
        isActive = CONFIG.FARM_ENABLED
    }
    
    saveCoordination(data)
end

-- ============ NEW: SYNCHRONIZER-BASED BRAINROT SCANNING ============
-- Uses Synchronizer API to get REAL-TIME SERVER DATA about brainrots
-- This is much more reliable than GUI-based search!
local function scanPlotBrainrotsViaSynchronizer(plot)
    if not plot then return nil, 0 end
    if not Synchronizer or not AnimalsShared then 
        log("[SyncScan] Synchronizer or AnimalsShared not available")
        return nil, 0 
    end
    
    local plotOwner = plot.Name
    log("[SyncScan] Scanning plot: " .. plotOwner .. " via Synchronizer")
    
    local channel = nil
    local success, err = pcall(function()
        channel = Synchronizer:Get(plotOwner)
    end)
    
    if not success or not channel then
        log("[SyncScan] Could not get channel for " .. plotOwner .. ": " .. tostring(err))
        return nil, 0
    end
    
    local animalList = nil
    success, err = pcall(function()
        animalList = channel:Get("AnimalList")
    end)
    
    if not success or not animalList then
        log("[SyncScan] Could not get AnimalList for " .. plotOwner .. ": " .. tostring(err))
        return nil, 0
    end
    
    local brainrots = {}
    local totalIncome = 0
    local animalPodiums = plot:FindFirstChild("AnimalPodiums")
    
    for slot, info in pairs(animalList) do
        if type(info) == "table" and info.Index then
            local gen = 0
            local brainrotName = info.Index
            local mutation = info.Mutation
            local traits = info.Traits
            
            -- Calculate generation using AnimalsShared module (ACCURATE!)
            pcall(function()
                gen = AnimalsShared:GetGeneration(info.Index, info.Mutation, info.Traits, nil) or 0
            end)
            
            -- Get floor info from podium position
            local floor = 1
            if animalPodiums then
                local podium = animalPodiums:FindFirstChild(tostring(slot))
                if podium then
                    local base = podium:FindFirstChild("Base")
                    if base then
                        local spawn = base:FindFirstChild("Spawn")
                        if spawn then
                            floor = getBrainrotFloor(plot, spawn.Position)
                        end
                    end
                end
            end
            
            -- Format traits for storage
            local traitsString = nil
            if traits and type(traits) == "table" and #traits > 0 then
                traitsString = table.concat(traits, ",")
            elseif traits and type(traits) == "string" and traits ~= "" then
                traitsString = traits
            end
            
            totalIncome = totalIncome + gen
            
            table.insert(brainrots, {
                name = brainrotName,
                income = gen,
                incomeText = "$" .. formatPrice(gen) .. "/s",
                podiumIndex = tostring(slot),
                floor = floor,
                mutation = mutation,
                traits = traitsString
            })
            
            log("[SyncScan] Found: " .. brainrotName .. " = $" .. formatPrice(gen) .. "/s" .. 
                (mutation and (" | mutation=" .. mutation) or "") ..
                (traitsString and (" | traits=" .. traitsString) or ""))
        end
    end
    
    -- Sort by income (highest first)
    table.sort(brainrots, function(a, b) return a.income > b.income end)
    
    log("[SyncScan] RESULT: " .. #brainrots .. " brainrots, total income: " .. formatPrice(totalIncome))
    
    return brainrots, totalIncome
end
-- ============ END SYNCHRONIZER-BASED SCANNING ============

-- Сканировать брейнротов на КОНКРЕТНОЙ базе (по plot)
-- Now uses Synchronizer as PRIMARY method, falls back to old method if needed
local function scanPlotBrainrots(plot)
    if not plot then return {}, 0 end
    
    log("=== scanPlotBrainrots START for plot: " .. plot.Name .. " ===")
    
    -- TRY SYNCHRONIZER FIRST (MUCH MORE RELIABLE!)
    if SynchronizerReady then
        local syncBrainrots, syncIncome = scanPlotBrainrotsViaSynchronizer(plot)
        if syncBrainrots and #syncBrainrots > 0 then
            log("=== scanPlotBrainrots RESULT (via Synchronizer): " .. #syncBrainrots .. " brainrots, total income: " .. formatPrice(syncIncome) .. " ===")
            return syncBrainrots, syncIncome
        end
        log("[scanPlotBrainrots] Synchronizer returned no data, falling back to old method")
    end
    
    -- FALLBACK: Old method (GUI-based search)
    local animalPodiums = plot:FindFirstChild("AnimalPodiums")
    if not animalPodiums then 
        log("  ERROR: No AnimalPodiums folder!")
        return {}, 0
    end
    
    local brainrots = {}
    local totalIncome = 0
    local podiumCount = 0
    
    -- Track which brainrot models have been assigned to prevent duplicates
    local assignedModels = {}
    
    -- First, collect all podium spawns
    local podiumSpawns = {}
    for _, podium in ipairs(animalPodiums:GetChildren()) do
        local base = podium:FindFirstChild("Base")
        if not base then continue end
        local spawn = base:FindFirstChild("Spawn")
        if not spawn then continue end
        podiumSpawns[podium.Name] = spawn
    end
    
    for _, podium in ipairs(animalPodiums:GetChildren()) do
        podiumCount = podiumCount + 1
        local base = podium:FindFirstChild("Base")
        if not base then 
            log("  Podium " .. podium.Name .. ": No Base")
            continue 
        end
        local spawn = base:FindFirstChild("Spawn")
        if not spawn then 
            log("  Podium " .. podium.Name .. ": No Spawn")
            continue 
        end
        
        log("  Podium " .. podium.Name .. " - checking spawn children...")
        
        -- Логируем все дочерние элементы spawn
        local spawnChildren = {}
        for _, child in ipairs(spawn:GetChildren()) do
            table.insert(spawnChildren, child.Name .. "(" .. child.ClassName .. ")")
        end
        log("    Spawn children: " .. table.concat(spawnChildren, ", "))
        
        -- Ищем AnimalOverhead разными методами
        local animalOverhead = nil
        local brainrotName = nil
        local incomeValue = 0
        local incomeText = ""
        local foundMethod = "none"
        local foundModel = nil -- Track model for Method 3
        
        -- Method 1: Check ALL Attachments (excluding PromptAttachment)
        for _, child in ipairs(spawn:GetChildren()) do
            if child:IsA("Attachment") and child.Name ~= "PromptAttachment" then
                local overhead = child:FindFirstChild("AnimalOverhead")
                if overhead and overhead:IsA("BillboardGui") then
                    animalOverhead = overhead
                    foundMethod = "1-Attachment(" .. child.Name .. ")"
                    log("    Found AnimalOverhead via Method 1 in Attachment: " .. child.Name)
                    break
                end
            end
        end
        
        -- Method 2: Search spawn descendants
        if not animalOverhead then
            for _, desc in ipairs(spawn:GetDescendants()) do
                if desc.Name == "AnimalOverhead" and desc:IsA("BillboardGui") then
                    animalOverhead = desc
                    foundMethod = "2-SpawnDescendant"
                    log("    Found AnimalOverhead via Method 2 (spawn descendants)")
                    break
                end
            end
        end
        
        -- Method 3: Search in BRAINROT MODEL near spawn (как в autosteal.lua!)
        -- AnimalOverhead может быть внутри модели brainrot, а не в spawn
        -- IMPORTANT: Only assign model to THIS podium if this is the CLOSEST podium to the model
        if not foundModel then
            local closestDist = 15
            for _, child in ipairs(plot:GetChildren()) do
                if child:IsA("Model") and 
                   child.Name ~= "AnimalPodiums" and 
                   child.Name ~= "PlotSign" and 
                   child.Name ~= "Building" and 
                   child.Name ~= "Decorations" and
                   child.Name ~= "Decoration" and
                   child.Name ~= "Model" and
                   child.Name ~= "LaserHitbox" and
                   child.Name ~= "DeliveryHitbox" and
                   not assignedModels[child] then -- Skip already assigned models
                    -- Проверяем WeldConstraint (brainrot несут - пропускаем)
                    local rootPart = child:FindFirstChild("RootPart")
                    if rootPart and rootPart:FindFirstChild("WeldConstraint") then
                        continue
                    end
                    
                    -- Check if this is a valid brainrot model (with or without AnimalOverhead)
                    local isValidBrainrot = false
                    if rootPart then
                        local hasAnimController = child:FindFirstChild("AnimationController") ~= nil
                        local hasHumanoid = child:FindFirstChildOfClass("Humanoid") ~= nil
                        local hasMutation = child:GetAttribute("Mutation") ~= nil
                        local hasAnimalOverhead = child:FindFirstChild("AnimalOverhead", true) ~= nil
                        
                        if hasAnimController or hasHumanoid or hasMutation or hasAnimalOverhead then
                            isValidBrainrot = true
                        end
                    end
                    
                    if isValidBrainrot then
                        -- Проверяем расстояние до spawn
                        local modelPrimary = child.PrimaryPart or rootPart or child:FindFirstChildWhichIsA("BasePart")
                        if modelPrimary then
                            local distToThis = (modelPrimary.Position - spawn.Position).Magnitude
                            
                            -- Check if THIS podium is the closest to this model
                            local isClosestPodium = true
                            for otherPodiumName, otherSpawn in pairs(podiumSpawns) do
                                if otherPodiumName ~= podium.Name then
                                    local distToOther = (modelPrimary.Position - otherSpawn.Position).Magnitude
                                    if distToOther < distToThis then
                                        isClosestPodium = false
                                        break
                                    end
                                end
                            end
                            
                            if isClosestPodium and distToThis < closestDist then
                                closestDist = distToThis
                                foundModel = child
                                local overhead = child:FindFirstChild("AnimalOverhead", true)
                                if overhead and overhead:IsA("BillboardGui") then
                                    animalOverhead = overhead
                                end
                                foundMethod = "3-Model(" .. child.Name .. ",dist=" .. string.format("%.1f", distToThis) .. ")"
                                log("    Found brainrot model via Method 3: " .. child.Name .. " (dist=" .. string.format("%.1f", distToThis) .. ")")
                            elseif not isClosestPodium then
                                log("    Skipping model " .. child.Name .. " - closer to another podium")
                            end
                        end
                    end
                end
            end
        end
        
        -- Если AnimalOverhead найден через Method 1 или 2, ищем модель brainrot рядом со spawn
        if animalOverhead and not foundModel then
            local closestModelDist = 20 -- Увеличил радиус поиска
            for _, child in ipairs(plot:GetChildren()) do
                if child:IsA("Model") and 
                   child.Name ~= "AnimalPodiums" and 
                   child.Name ~= "PlotSign" and 
                   child.Name ~= "Building" and 
                   child.Name ~= "Decorations" then
                    local modelPart = child.PrimaryPart or child:FindFirstChild("RootPart") or child:FindFirstChildWhichIsA("BasePart")
                    if modelPart then
                        local distToSpawn = (modelPart.Position - spawn.Position).Magnitude
                        if distToSpawn < closestModelDist then
                            closestModelDist = distToSpawn
                            foundModel = child
                        end
                    end
                end
            end
            if foundModel then
                log("    Found brainrot model for Method " .. foundMethod .. ": " .. foundModel.Name)
            end
        end
        
        -- Mark model as assigned to prevent duplicates
        if foundModel then
            assignedModels[foundModel] = podium.Name
        end
        
        -- Extract mutation - СНАЧАЛА из атрибута модели (первичный источник!), потом из GUI
        local mutation = nil
        
        -- Method 1: Model attribute (PRIMARY SOURCE - always correct!)
        if foundModel then
            mutation = foundModel:GetAttribute("Mutation")
            if mutation then
                log("    Mutation from model attribute: " .. tostring(mutation))
            end
        end
        
        -- Method 2: AnimalOverhead.Mutation TextLabel (fallback)
        if not mutation and animalOverhead then
            local mutationLabel = animalOverhead:FindFirstChild("Mutation")
            if mutationLabel and mutationLabel:IsA("TextLabel") then
                -- Используем ContentText для чистого текста без RichText разметки
                local mutText = mutationLabel.ContentText or mutationLabel.Text
                -- Очищаем от возможных HTML тегов
                if mutText then
                    mutText = mutText:gsub("<[^>]+>", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
                end
                if mutText and mutText ~= "" and mutationLabel.Visible then
                    mutation = mutText
                    log("    Mutation from AnimalOverhead.Mutation: " .. tostring(mutation))
                end
            end
        end
        
        -- ============ NEW: Calculate Generation from model attributes ============
        -- This is the correct way - no more GUI-based search that fails with duplicate names!
        local traitsFromModel = nil
        
        if foundModel then
            local calculatedGen, calcName, calcMutation, calcTraits = calculateBrainrotGeneration(foundModel)
            
            if calculatedGen and calculatedGen > 0 then
                incomeValue = calculatedGen
                incomeText = "$" .. formatPrice(calculatedGen) .. "/s"
                
                -- Use Index attribute for name if available
                if calcName and calcName ~= "" then
                    brainrotName = calcName
                end
                
                -- Use mutation from calculation if not found before
                if calcMutation and not mutation then
                    mutation = calcMutation
                end
                
                -- Store traits for logging
                traitsFromModel = calcTraits
                
                local traitsStr = ""
                if calcTraits and #calcTraits > 0 then
                    traitsStr = " | traits=" .. table.concat(calcTraits, ",")
                end
                
                log("    [NEW] calculateBrainrotGeneration: " .. brainrotName .. " = " .. formatPrice(calculatedGen) .. traitsStr .. (calcMutation and (" | mutation=" .. calcMutation) or ""))
            end
        end
        
        -- FALLBACK: Get name from AnimalOverhead if still not found
        if (not brainrotName or brainrotName == "") and animalOverhead then
            local displayNameLabel = animalOverhead:FindFirstChild("DisplayName")
            if displayNameLabel then
                brainrotName = displayNameLabel.Text
                log("    DisplayName from GUI: " .. tostring(brainrotName))
            end
        end
        
        -- FALLBACK: Get name from model.Name if still not found
        if (not brainrotName or brainrotName == "") and foundModel then
            brainrotName = foundModel.Name
            log("    Name from model.Name: " .. brainrotName)
        end
        
        -- Method 4: If no AnimalOverhead or no name, try ProximityPrompt
        if not brainrotName or brainrotName == "" then
            local promptAttachment = spawn:FindFirstChild("PromptAttachment")
            if promptAttachment then
                local prompt = promptAttachment:FindFirstChildOfClass("ProximityPrompt")
                if prompt and prompt.ObjectText and prompt.ObjectText ~= "" then
                    brainrotName = prompt.ObjectText
                    foundMethod = foundMethod .. "+4-Prompt"
                    log("    Got name from ProximityPrompt: " .. brainrotName)
                end
            end
        end
        
        -- Skip if still no name
        if not brainrotName or brainrotName == "" then 
            log("    SKIPPED: No brainrot name found")
            continue 
        end
        
        -- FALLBACK: If income is still 0, try cache or fallback table
        if incomeValue == 0 then
            -- Try AnimalGenerationCache (base generation without modifiers)
            local cachedIncome = AnimalGenerationCache[brainrotName]
            if cachedIncome and cachedIncome > 0 then
                incomeValue = cachedIncome
                incomeText = "$" .. formatPrice(cachedIncome) .. "/s"
                log("    FALLBACK: Got base income from cache: " .. formatPrice(cachedIncome))
            elseif FALLBACK_GENERATIONS[brainrotName] then
                -- Try hardcoded fallback
                incomeValue = FALLBACK_GENERATIONS[brainrotName]
                incomeText = "$" .. formatPrice(incomeValue) .. "/s"
                log("    FALLBACK: Got base income from FALLBACK_GENERATIONS: " .. formatPrice(incomeValue))
            else
                log("    WARNING: income=0 and no fallback for: " .. brainrotName)
            end
        end
        
        -- Добавляем brainrot
        totalIncome = totalIncome + incomeValue
        
        -- Format traits for storage
        local traitsString = nil
        if traitsFromModel and #traitsFromModel > 0 then
            traitsString = table.concat(traitsFromModel, ",")
        end
        
        table.insert(brainrots, {
            name = brainrotName,
            income = incomeValue,
            incomeText = incomeText ~= "" and incomeText or "?",
            podiumIndex = podium.Name,
            floor = getBrainrotFloor(plot, spawn.Position),
            mutation = mutation,
            traits = traitsString
        })
        
        local traitsLog = traitsString and (" | traits=" .. traitsString) or ""
        log("    ADDED: " .. brainrotName .. " | " .. incomeText .. " | method=" .. foundMethod .. (mutation and (" | mutation=" .. mutation) or "") .. traitsLog)
    end
    
    -- Сортируем по доходу
    table.sort(brainrots, function(a, b) return a.income > b.income end)
    
    log("=== scanPlotBrainrots RESULT: " .. #brainrots .. " brainrots from " .. podiumCount .. " podiums, total income: " .. formatPrice(totalIncome) .. " ===")
    
    return brainrots, totalIncome
end

-- Сканировать всех brainrots на базе игрока и сохранить в JSON
-- Использует scanPlotBrainrots для правильного поиска
local function scanAndSaveBaseBrainrots()
    local myPlot = findPlayerPlot()
    if not myPlot then return 0 end
    
    local brainrots, totalIncome = scanPlotBrainrots(myPlot)
    local usedSlots, maxSlots = countPlotsOnBase()
    
    local data = {
        playerName = LocalPlayer.Name,
        lastUpdate = os.date("%Y-%m-%d %H:%M:%S"),
        totalBrainrots = #brainrots,
        maxSlots = maxSlots,
        totalIncome = totalIncome,
        totalIncomeFormatted = formatPrice(totalIncome) .. "/s",
        brainrots = brainrots
    }
    
    ensureFarmFolder()
    pcall(function()
        local content = prettyJSON(data)
        writefile(getBrainrotsFileName(), content)
    end)
    
    return #brainrots
end

-- Переменная для отслеживания последнего сканирования всех баз
local lastAllBasesScanTime = 0
local ALL_BASES_SCAN_INTERVAL = 5 -- секунд

-- Сканировать ТОЛЬКО свою базу (текущего аккаунта) и сохранить данные
-- Каждый фермер отвечает только за себя - сервер мержит всех в одну базу
local function scanAllOwnBases()
    local myPlot = findPlayerPlot()
    if not myPlot then 
        lastAllBasesScanTime = os.time()
        return 0 
    end
    
    local brainrots, totalIncome = scanPlotBrainrots(myPlot)
    local maxSlots = getPlotMaxSlots(myPlot)
    
    local data = {
        playerName = LocalPlayer.Name,
        userId = LocalPlayer.UserId,
        lastUpdate = os.date("%Y-%m-%d %H:%M:%S"),
        totalBrainrots = #brainrots,
        maxSlots = maxSlots,
        totalIncome = totalIncome,
        totalIncomeFormatted = formatPrice(totalIncome) .. "/s",
        brainrots = brainrots,
        status = currentStatus or "idle",
        action = currentAction or "",
        farmEnabled = CONFIG.FARM_ENABLED,
        farmRunning = farmRunning
    }
    
    ensureFarmFolder()
    pcall(function()
        local fileName = FARM_FOLDER .. "/brainrots_" .. LocalPlayer.Name .. ".json"
        local content = prettyJSON(data)
        writefile(fileName, content)
    end)
    
    lastAllBasesScanTime = os.time()
    return 1
end

-- Проверить, нужно ли сканировать базу (прошло 5+ секунд)
local function shouldScanAllBases()
    return (os.time() - lastAllBasesScanTime) >= ALL_BASES_SCAN_INTERVAL
end

-- ============ PANEL DATA SYNC SYSTEM ============
local lastPanelSyncTime = 0
local currentStatus = "idle" -- idle, searching, walking, stealing, delivering
local currentAction = ""
local isOnline = true

-- Сохранить данные для веб-панели (ТОЛЬКО текущий аккаунт!)
-- Каждый фермер отправляет только свои данные, сервер мержит всех в одну базу
local function savePanelData()
    -- Сканируем ТОЛЬКО свою базу
    local myPlot = findPlayerPlot()
    local brainrots, totalIncome = {}, 0
    local maxSlots = 10
    if myPlot then
        brainrots, totalIncome = scanPlotBrainrots(myPlot)
        maxSlots = getPlotMaxSlots(myPlot)
    end
    
    -- Сохраняем в локальный файл (для panel_sync.lua)
    local myData = {
        playerName = LocalPlayer.Name,
        userId = LocalPlayer.UserId,
        lastUpdate = os.date("%Y-%m-%d %H:%M:%S"),
        totalBrainrots = #brainrots,
        maxSlots = maxSlots,
        totalIncome = totalIncome,
        totalIncomeFormatted = formatPrice(totalIncome) .. "/s",
        brainrots = brainrots,
        status = currentStatus,
        action = currentAction,
        farmEnabled = CONFIG.FARM_ENABLED,
        farmRunning = farmRunning
    }
    
    ensureFarmFolder()
    pcall(function()
        local fileName = FARM_FOLDER .. "/brainrots_" .. LocalPlayer.Name .. ".json"
        local content = prettyJSON(myData)
        writefile(fileName, content)
    end)
    
    -- Формируем данные для отправки - ТОЛЬКО текущий аккаунт
    local myAccountData = {
        playerName = LocalPlayer.Name,
        userId = LocalPlayer.UserId,
        lastUpdate = os.date("%Y-%m-%d %H:%M:%S"),
        totalBrainrots = #brainrots,
        maxSlots = maxSlots,
        totalIncome = totalIncome,
        totalIncomeFormatted = formatPrice(totalIncome) .. "/s",
        brainrots = brainrots,
        isOnline = true,
        status = currentStatus,
        action = currentAction,
        farmEnabled = CONFIG.FARM_ENABLED,
        farmRunning = farmRunning
    }
    
    local panelData = {
        farmKey = FARM_KEY,
        lastSync = os.date("%Y-%m-%d %H:%M:%S"),
        lastSyncTimestamp = os.time(),
        currentPlayer = LocalPlayer.Name,
        currentUserId = LocalPlayer.UserId,
        totalGlobalIncome = totalIncome, -- Только свой income (сервер посчитает общий)
        totalGlobalIncomeFormatted = formatPrice(totalIncome) .. "/s",
        accounts = { myAccountData } -- Массив с ОДНИМ аккаунтом - сервер мержит
    }
    
    ensureFarmFolder()
    pcall(function()
        local content = prettyJSON(panelData)
        writefile(PANEL_DATA_FILE, content)
    end)
    
    -- Отправляем данные на веб-панель через HTTP
    if PANEL_SYNC_ENABLED and PANEL_API_URL then
        local now = tick()
        if now - lastPanelHttpSync >= PANEL_SYNC_INTERVAL then
            lastPanelHttpSync = now
            task.spawn(function()
                local success, response = httpPost(PANEL_API_URL, panelData)
                if success then
                    log("[PanelSync] Data synced to web panel successfully")
                else
                    log("[PanelSync] Failed to sync to web panel", "WARN")
                end
            end)
        end
    end
    
    return panelData
end

-- Моментальная синхронизация с панелью (без проверки интервала)
local function syncNow()
    lastPanelHttpSync = 0 -- Сбрасываем таймер
    savePanelData()
    log("[PanelSync] Immediate sync triggered")
end

-- Обновить статус для панели
local function updatePanelStatus(status, action)
    currentStatus = status or currentStatus
    currentAction = action or currentAction
    
    -- Синхронизируем если прошло достаточно времени
    if os.time() - lastPanelSyncTime >= PANEL_SYNC_INTERVAL then
        savePanelData()
        lastPanelSyncTime = os.time()
    end
end

-- ============ END PANEL DATA SYNC ============

local farmRunning = false

-- ============ WATCHDOG SYSTEM ============
-- Глобальная защита от застревания
local WATCHDOG_TIMEOUT = 120 -- секунд максимум на одну итерацию (увеличено для дальних маршрутов)
local watchdogStartTime = tick() -- Инициализируем сразу
local watchdogLastPosition = nil
local watchdogStuckTime = 0
local WATCHDOG_STUCK_THRESHOLD = 60 -- 60 секунд без движения = застрял (БЫЛО 30!)
local watchdogActive = false -- Активен только когда фарм работает
local WATCHDOG_MOVEMENT_THRESHOLD = 3 -- минимальное движение (studs) чтобы считаться "двигающимся"

-- Функция для ресета персонажа (через Humanoid:ChangeState или уничтожение)
local function forceResetCharacter()
    log("WATCHDOG: Forcing character reset!", "WARN")
    updateStatus("WATCHDOG: Resetting...", Color3.fromRGB(255, 50, 50))
    
    local character = LocalPlayer.Character
    if character then
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.Health = 0
        end
    end
    
    -- Ждём респавн
    task.wait(4)
end

local function resetWatchdog()
    watchdogStartTime = tick()
    watchdogStuckTime = 0
    watchdogActive = true
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    watchdogLastPosition = hrp and hrp.Position or nil
    log("Watchdog reset, start=" .. tostring(watchdogStartTime))
end

local function checkWatchdog()
    if not watchdogActive then return true, nil end
    
    local elapsed = tick() - watchdogStartTime
    
    -- Проверяем общий таймаут итерации (120 секунд)
    if elapsed > WATCHDOG_TIMEOUT then
        log("WATCHDOG: Iteration timeout! Elapsed=" .. string.format("%.1f", elapsed) .. "s", "WARN")
        return false, "timeout"
    end
    
    -- Проверяем застревание (60 секунд без движения)
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if hrp and watchdogLastPosition then
        local moved = (hrp.Position - watchdogLastPosition).Magnitude
        if moved < WATCHDOG_MOVEMENT_THRESHOLD then
            watchdogStuckTime = watchdogStuckTime + 1
            if watchdogStuckTime >= WATCHDOG_STUCK_THRESHOLD then
                log("WATCHDOG: Stuck! No movement for " .. watchdogStuckTime .. "s (>=" .. WATCHDOG_STUCK_THRESHOLD .. ")", "WARN")
                return false, "stuck"
            end
        else
            -- Движение есть - сбрасываем
            watchdogStuckTime = 0
            watchdogLastPosition = hrp.Position
        end
    elseif hrp then
        watchdogLastPosition = hrp.Position
    end
    
    return true, nil
end

-- Обёртка для удобной проверки с автоматическим выводом статуса
local watchdogFailed = false
local watchdogFailReason = nil

local function doWatchdogCheck()
    local ok, reason = checkWatchdog()
    if not ok then
        watchdogFailed = true
        watchdogFailReason = reason
        updateStatus("WATCHDOG: " .. (reason or "unknown") .. "\nRestarting...", Color3.fromRGB(255, 100, 100))
        
        -- При таймауте (60 сек) - делаем reset персонажа
        if reason == "timeout" then
            forceResetCharacter()
        end
        
        return false
    end
    return true
end

-- Фоновый watchdog - работает независимо от основного цикла
-- В SAFE_MODE watchdog не нужен - нет движения и действий
if not SAFE_MODE then
    task.spawn(function()
        log("Background watchdog started!")
        while true do
            task.wait(1) -- Проверка каждую секунду
            
            if CONFIG.FARM_ENABLED and farmRunning then
            -- Активируем watchdog если ещё не активен
            if not watchdogActive then
                watchdogActive = true
                watchdogStartTime = tick()
                log("Watchdog auto-activated by background task")
            end
            
            local elapsed = tick() - watchdogStartTime
            
            -- НЕ обновляем статус в фоне - это делает основной цикл
            -- (убрали логирование каждые 15 секунд чтобы не перезаписывать реальный статус)
            
            -- Проверяем таймаут (120 секунд)
            if elapsed > WATCHDOG_TIMEOUT then
                log("WATCHDOG TIMEOUT! " .. string.format("%.1f", elapsed) .. "s > " .. WATCHDOG_TIMEOUT .. "s", "WARN")
                updateStatus("WATCHDOG TIMEOUT!\n" .. string.format("%.0f", elapsed) .. "s\nResetting...", Color3.fromRGB(255, 50, 50))
                forceResetCharacter()
                watchdogActive = false
                watchdogStartTime = tick()
                watchdogStuckTime = 0
            end
            
            -- Проверяем застревание (60 секунд БЕЗ движения)
            local character = LocalPlayer.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            if hrp and watchdogLastPosition then
                local moved = (hrp.Position - watchdogLastPosition).Magnitude
                if moved < WATCHDOG_MOVEMENT_THRESHOLD then
                    -- Персонаж НЕ двигается
                    watchdogStuckTime = watchdogStuckTime + 1
                    if watchdogStuckTime >= WATCHDOG_STUCK_THRESHOLD then
                        log("WATCHDOG STUCK! No movement for " .. watchdogStuckTime .. "s (threshold: " .. WATCHDOG_STUCK_THRESHOLD .. ")", "WARN")
                        updateStatus("WATCHDOG STUCK!\n" .. watchdogStuckTime .. "s no move\nResetting...", Color3.fromRGB(255, 50, 50))
                        forceResetCharacter()
                        watchdogActive = false
                        watchdogStartTime = tick()
                        watchdogStuckTime = 0
                    end
                else
                    -- Персонаж ДВИЖЕТСЯ - сбрасываем таймер застревания
                    if watchdogStuckTime > 0 then
                        log("[Watchdog] Movement detected! Reset stuck timer from " .. watchdogStuckTime .. "s")
                    end
                    watchdogStuckTime = 0
                end
                watchdogLastPosition = hrp.Position
            elseif hrp then
                watchdogLastPosition = hrp.Position
            end
        else
            -- Фарм не активен - сбрасываем
            watchdogActive = false
            watchdogStuckTime = 0
        end
    end
    end)
end -- end if not SAFE_MODE for watchdog

-- ============ ANTI-AFK SYSTEM ============
-- Roblox кикает за AFK после 20 минут бездействия
-- Используем VirtualInputManager или VirtualUser для симуляции активности

local ANTI_AFK_INTERVAL = 60 -- Секунды между анти-афк действиями (каждые 60 сек)
local lastAntiAfkTime = tick()
local antiAfkEnabled = true

-- Получаем VirtualUser или VirtualInputManager для симуляции инпута
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = nil
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

local function performAntiAfkAction()
    -- Метод 1: VirtualUser (предпочтительный для exploit)
    if VirtualUser then
        pcall(function()
            -- Симулируем клик мышью в центре экрана
            VirtualUser:CaptureController()
            VirtualUser:ClickButton1(Vector2.new(0, 0))
        end)
    end
    
    -- Метод 2: VirtualInputManager - отправляем нажатие клавиши
    if VirtualInputManager then
        pcall(function()
            -- Отправляем событие нажатия и отпускания Space (прыжок)
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
    end
    
    -- Метод 3: Прямое небольшое движение камеры (работает всегда)
    pcall(function()
        local camera = workspace.CurrentCamera
        if camera then
            local currentCF = camera.CFrame
            -- Очень маленький поворот камеры (незаметный)
            camera.CFrame = currentCF * CFrame.Angles(0, math.rad(0.01), 0)
            task.wait(0.1)
            camera.CFrame = currentCF -- Возвращаем обратно
        end
    end)
    
    log("Anti-AFK action performed")
end

-- Фоновый Anti-AFK loop
task.spawn(function()
    log("Anti-AFK system started! Interval: " .. ANTI_AFK_INTERVAL .. "s")
    while true do
        task.wait(10) -- Проверяем каждые 10 секунд
        
        if antiAfkEnabled then
            local elapsed = tick() - lastAntiAfkTime
            
            if elapsed >= ANTI_AFK_INTERVAL then
                performAntiAfkAction()
                lastAntiAfkTime = tick()
            end
        end
    end
end)

-- Также подписываемся на событие Player.Idled для гарантии
pcall(function()
    LocalPlayer.Idled:Connect(function(idleTime)
        log("Player.Idled triggered! idleTime=" .. tostring(idleTime), "WARN")
        -- Сразу выполняем анти-афк действие
        performAntiAfkAction()
    end)
    log("Connected to Player.Idled event")
end)

-- ============ END ANTI-AFK SYSTEM ============

-- ============ END WATCHDOG SYSTEM ============

local function farmLoop()
    -- SAFE_MODE: Полностью блокируем фарм-цикл
    if SAFE_MODE then
        log("[SAFE_MODE] farmLoop blocked - safe mode is active")
        return
    end
    
    if farmRunning then return end
    farmRunning = true
    -- Случайная задержка при старте для десинхронизации аккаунтов (0.5-2 секунды)
    local startDelay = 0.5 + (ACCOUNT_PRIORITY / 1000) * 1.5
    updateStatus("Syncing accounts...\n" .. string.format("%.1f", startDelay) .. "s", Color3.fromRGB(200, 200, 100))
    updatePanelStatus("farming", "Starting farm")
    -- МОМЕНТАЛЬНАЯ синхронизация при старте фарма!
    syncNow()
    task.wait(startDelay)
    
    -- Первоначальное сканирование всех своих баз при старте
    scanAllOwnBases()
    savePanelData() -- Синхронизация с панелью при старте

    -- Переменные для отслеживания бездействия (idle detection)
    local lastActionTime = tick()
    local lastActionPos = nil
    local IDLE_TIMEOUT = 15 -- Секунд бездействия до forced retry (было 20)
    
    while CONFIG.FARM_ENABLED do
        -- SAFE_MODE check внутри цикла на случай динамического переключения
        if SAFE_MODE then
            log("[SAFE_MODE] farmLoop exiting - safe mode activated")
            break
        end
        
        -- Сбрасываем watchdog в начале каждой итерации
        resetWatchdog()
        watchdogFailed = false
        watchdogFailReason = nil
        
        -- IDLE DETECTION: Проверяем не застрял ли персонаж без действий
        local hrpCheck = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrpCheck then
            local currentPos = hrpCheck.Position
            if lastActionPos then
                local movedSinceLastAction = (currentPos - lastActionPos).Magnitude
                local idleTime = tick() - lastActionTime
                
                -- Если больше IDLE_TIMEOUT секунд не двигаемся - принудительный рестарт итерации
                if movedSinceLastAction < 5 and idleTime > IDLE_TIMEOUT then
                    log("[IDLE] Detected idle state for " .. string.format("%.1f", idleTime) .. "s! Forcing movement restart", "WARN")
                    updateStatus("Idle detected!\nRestarting movement...", Color3.fromRGB(255, 200, 100))
                    
                    -- Прыжок для выхода из застревания
                    local hum = hrpCheck.Parent:FindFirstChild("Humanoid")
                    if hum then
                        hum.Jump = true
                        -- Принудительно идём к своему collect zone как fallback
                        local myPlotCheck = findPlayerPlot()
                        if myPlotCheck then
                            local myCollectZoneCheck = getPlotDeliveryHitbox(myPlotCheck)
                            if myCollectZoneCheck then
                                log("[IDLE] Forcing movement to my collect zone as recovery")
                                local recoveryPos = myCollectZoneCheck.Position + Vector3.new(3, 2, 0)
                                hum:MoveTo(recoveryPos)
                            end
                        end
                    end
                    task.wait(0.5)
                    
                    -- Сбрасываем таймер
                    lastActionTime = tick()
                    lastActionPos = currentPos
                end
            else
                lastActionPos = currentPos
                -- Обновляем таймер при движении
                lastActionTime = tick()
            end
        end
        
        -- Ждём персонажа если его нет
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChild("Humanoid")
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        
        if not character or not humanoid or not hrp or humanoid.Health <= 0 then
            updateStatus("Waiting for respawn...", Color3.fromRGB(255, 200, 100))
            updatePanelStatus("waiting", "Waiting for respawn")
            -- Сбрасываем idle таймер после респавна
            lastActionTime = tick()
            lastActionPos = nil
            task.wait(0.5)
            continue
        end
        
        -- После респавна - МИНИМАЛЬНАЯ задержка для стабилизации
        if lastActionPos == nil then
            log("[RESPAWN] Character respawned, quick stabilization...")
            task.wait(0.3) -- Было 1 сек, теперь 0.3
            lastActionTime = tick()
            lastActionPos = hrp.Position
        end
        
        local myPlot = findPlayerPlot()
        if not myPlot then
            updateStatus("Own plot not found!", Color3.fromRGB(255, 100, 100))
            updatePanelStatus("error", "Own plot not found")
            task.wait(3)
            continue
        end

        local myCollectZone = getPlotDeliveryHitbox(myPlot)
        local myCarpetPos = getCarpetPositionForPlot(myPlot)
        
        if not myCollectZone or not myCarpetPos then
            updateStatus("Route error", Color3.fromRGB(255, 100, 100))
            updatePanelStatus("error", "Route error")
            task.wait(3)
            continue
        end

        -- Проверка: если несём brainrot - сразу идём сдавать
        if isCarryingBrainrot() then
            updateStatus("Carrying brainrot!\nDelivering...", Color3.fromRGB(255, 200, 100))
            
            -- Calculate approach position for collect zone (центр панели)
            local collectZonePos = myCollectZone.Position
            local approachPos = Vector3.new(
                collectZonePos.X + 3,  -- Немного перед панелью
                collectZonePos.Y + 2,  -- На уровне земли
                collectZonePos.Z       -- ЦЕНТР по Z
            )
            
            local deliveryAttempts = 0
            while isCarryingBrainrot() and CONFIG.FARM_ENABLED and deliveryAttempts < 5 do
                deliveryAttempts = deliveryAttempts + 1
                
                -- Watchdog check в delivery loop
                if not doWatchdogCheck() then break end
                
                -- Проверяем расстояние до collect zone
                local character = LocalPlayer.Character
                local hrp = character and character:FindFirstChild("HumanoidRootPart")
                local distToCollect = hrp and (hrp.Position - collectZonePos).Magnitude or 999
                
                if distToCollect < 8 then
                    -- Close to collect zone - walk directly into it
                    walkTo(collectZonePos, 5)
                    -- Уже на месте, ждём пока сбросится
                    local waitTime = 0
                    while isCarryingBrainrot() and waitTime < 1.5 and CONFIG.FARM_ENABLED do
                        task.wait(0.15)
                        waitTime = waitTime + 0.15
                    end
                elseif distToCollect < 20 then
                    -- Medium distance - walk to approach position then into zone
                    walkTo(approachPos, 10)
                    if isCarryingBrainrot() then
                        walkTo(collectZonePos, 10)
                    end
                else
                    -- Far away - go directly to approach position then into zone (no carpet)
                    walkTo(approachPos, 20)
                    if isCarryingBrainrot() then
                        walkTo(collectZonePos, 10)
                    end
                end
                
                if not isCarryingBrainrot() then
                    CONFIG.CollectedThisSession = (CONFIG.CollectedThisSession or 0) + 1
                    local used, total = countPlotsOnBase()
                    setPlotInfo(used, total)
                    local totalOnBase = scanAndSaveBaseBrainrots()
                    updateAccountStatus(totalOnBase)
                    updateStatus("Delivered!\nBase: " .. used .. "/" .. total .. "\nOn base: " .. totalOnBase, Color3.fromRGB(100, 255, 100))
                    -- МОМЕНТАЛЬНАЯ синхронизация с панелью после доставки!
                    syncNow()
                    break
                end
            end
            
            -- Если watchdog сработал - сбрасываем и начинаем заново
            if watchdogFailed then
                log("Watchdog triggered in delivery loop, restarting", "WARN")
                continue
            end
            
            if not CONFIG.FARM_ENABLED then break end
            task.wait(0.3)
            continue
        end

        -- Начинаем со своего collect zone
        -- СНАЧАЛА проверяем, не застряли ли мы на верхнем этаже
        local myCurrentFloor = getPlayerCurrentFloor()
        if myCurrentFloor > 1 then
            updateStatus("Stuck on floor " .. myCurrentFloor .. "\nDescending first...", Color3.fromRGB(255, 200, 100))
            safeReturnToGround(nil, myCarpetPos)
        end
        
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local collectApproach = Vector3.new(myCollectZone.Position.X + 3, myCollectZone.Position.Y + 2, myCollectZone.Position.Z)
            local distToCollect = (hrp.Position - collectApproach).Magnitude
            if distToCollect > 12 then
                updateStatus("Going to collect zone...", Color3.fromRGB(100, 200, 255))
                pathfindToCollectZone(myCollectZone.Position, 25)
                if not CONFIG.FARM_ENABLED then break end
            end
        end

        local used, total = countPlotsOnBase()
        setPlotInfo(used, total)

        if used >= total then
            updateStatus("Base full!\nWaiting for slot...", Color3.fromRGB(255, 100, 100))
            -- Пока ждём - сканируем все свои базы
            if shouldScanAllBases() then
                scanAllOwnBases()
            end
            task.wait(3)
            continue
        end

        updateStatus("Searching brainrot > " .. formatPrice(CONFIG.MIN_INCOME) .. "/s...", Color3.fromRGB(255, 200, 100))
        updatePanelStatus("searching", "Searching brainrot > " .. formatPrice(CONFIG.MIN_INCOME) .. "/s")
        local bestBrainrot = findBestBrainrot()

        if not bestBrainrot then
            updateStatus("No brainrot found\nChecking position...", Color3.fromRGB(150, 150, 150))
            updatePanelStatus("idle", "No brainrot found")
            
            -- ВАЖНО: Проверяем где мы сейчас находимся
            local currentFloor = getPlayerCurrentFloor()
            local character = LocalPlayer.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            
            if hrp and myCollectZone and myCollectZone.Parent then
                local collectApproach = Vector3.new(
                    myCollectZone.Position.X + 3,
                    myCollectZone.Position.Y + 2,
                    myCollectZone.Position.Z
                )
                local distToCollect = (hrp.Position - collectApproach).Magnitude
                
                log("[ROUTE] No brainrot found. Floor=" .. currentFloor .. ", distToCollect=" .. string.format("%.1f", distToCollect))
                
                -- Если на верхнем этаже - сначала спускаемся
                if currentFloor >= 3 then
                    updateStatus("No brainrot found\nDescending from floor " .. currentFloor .. "...", Color3.fromRGB(255, 200, 100))
                    local closestPlot = findClosestPlotToPlayer()
                    if closestPlot then
                        walkDownFromThirdFloor(closestPlot)
                    end
                    task.wait(0.5)
                elseif currentFloor == 2 then
                    updateStatus("No brainrot found\nDescending stairs...", Color3.fromRGB(255, 200, 100))
                    -- Спускаемся по лестнице
                    local closestPlot = findClosestPlotToPlayer()
                    if closestPlot then
                        local stairsBottom, stairsTop = getStairsPositions(closestPlot)
                        if stairsBottom and stairsTop then
                            simplePathfindTo(stairsTop, 10)
                            simpleWalkTo(stairsBottom, 15, true)
                        end
                    end
                    task.wait(0.3)
                end
                
                -- Если далеко от collect zone - возвращаемся
                if distToCollect > 15 then
                    updateStatus("No brainrot found\nReturning to base...", Color3.fromRGB(255, 200, 100))
                    pathfindToCollectZone(myCollectZone.Position, 25)
                end
            end
            
            -- Пока ждём - сканируем все свои базы
            if shouldScanAllBases() then
                scanAllOwnBases()
            end
            
            updateStatus("No brainrot found\nRetrying in 2s...", Color3.fromRGB(150, 150, 150))
            task.wait(2)
            continue
        end
        
        -- ВАЖНО: Задержка для синхронизации резервации между аккаунтами
        task.wait(0.15)
        
        -- Двойная проверка: перечитываем координацию и проверяем резервацию
        if not canTakeBrainrot(bestBrainrot.key) then
            updateStatus("Target reserved by other\nSearching new...", Color3.fromRGB(255, 200, 100))
            releaseReservation(bestBrainrot.key)
            task.wait(0.3)
            continue
        end
        
        -- Обновляем резервацию (перезаписываем timestamp)
        reserveBrainrot(bestBrainrot.key)
        
        -- Дополнительная проверка: убеждаемся что владелец базы НЕ наш аккаунт
        local currentOwner = getPlotOwnerName(bestBrainrot.plot)
        if isOwnBase(currentOwner) then
            updateStatus("Target on own base!\nSkipping...", Color3.fromRGB(255, 200, 100))
            releaseReservation(bestBrainrot.key)
            task.wait(0.3)
            continue
        end

        local targetCarpetPos = getCarpetPositionForPlot(bestBrainrot.plot)
        local targetPos = bestBrainrot.spawn.Position
        local brainrotKey = bestBrainrot.key -- Уже зарезервировано в findBestBrainrot
        local currentPlot = bestBrainrot.plot

        if not targetCarpetPos then
            updateStatus("Target route error", Color3.fromRGB(255, 100, 100))
            releaseReservation(brainrotKey)
            task.wait(1)
            continue
        end

        -- Защита от nil floor
        local brainrotFloor = bestBrainrot.floor or 1
        
        updateStatus("Target: " .. bestBrainrot.name .. "\n" .. bestBrainrot.text .. "\nFrom: " .. bestBrainrot.ownerName .. " (F" .. brainrotFloor .. ")", Color3.fromRGB(100, 255, 100))
        updatePanelStatus("walking", "Walking to " .. bestBrainrot.name .. " on " .. bestBrainrot.ownerName .. "'s base")

        -- Waypoints для маршрута (для возврата при ошибке)
        local waypoints = {}
        local currentWaypointIndex = 0
        
        local function addWaypoint(pos, name)
            currentWaypointIndex = currentWaypointIndex + 1
            waypoints[currentWaypointIndex] = {position = pos, name = name}
        end
        
        local function walkBackToCollectZone()
            -- Проверяем - может мы УЖЕ на collect zone?
            local character = LocalPlayer.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            
            if myCollectZone and myCollectZone.Parent then
                local collectZonePos = myCollectZone.Position
                local approachPos = Vector3.new(
                    collectZonePos.X + 3,
                    collectZonePos.Y + 2,
                    collectZonePos.Z
                )
                
                local distToCollect = hrp and (hrp.Position - approachPos).Magnitude or 999
                
                -- Более агрессивная проверка - 12 вместо 10
                if distToCollect <= 12 then
                    log("[ROUTE] walkBackToCollectZone: Already at collect zone (dist=" .. string.format("%.1f", distToCollect) .. ")")
                    return true
                end
                
                updateStatus("Returning to my base...", Color3.fromRGB(255, 200, 100))
                
                -- ВАЖНО: Проверяем этаж перед возвратом
                local currentFloor = getPlayerCurrentFloor()
                log("[ROUTE] walkBackToCollectZone via pathfinding, floor=" .. currentFloor)
                
                -- Если на 3 этаже - сначала спускаемся через лифт
                if currentFloor >= 3 then
                    log("[ROUTE] On floor 3+, descending via elevator first")
                    local closestPlot = findClosestPlotToPlayer()
                    if closestPlot then
                        walkDownFromThirdFloor(closestPlot)
                    end
                    task.wait(0.5)
                end
                
                -- Теперь pathfinding (он сам спустится по лестнице если на 2 этаже)
                return pathfindToCollectZone(collectZonePos, 30)
            end
            return true
        end
        
        -- Функция проверки и переключения на альтернативу
        -- УПРОЩЁННАЯ версия - просто возвращает false чтобы начать новый поиск
        local function checkAndSwitchTarget()
            if not isBrainrotStillThere(currentPlot, bestBrainrot.podiumIndex) then
                updateStatus("Brainrot gone!\nRestarting search...", Color3.fromRGB(255, 200, 100))
                log("checkAndSwitchTarget: Brainrot gone from podium " .. tostring(bestBrainrot.podiumIndex))
                releaseReservation(brainrotKey)
                task.wait(0.3)
                -- Просто возвращаем false - основной цикл найдёт новую цель
                return false
            end
            return true -- brainrot на месте
        end

        -- ОПТИМИЗИРОВАННЫЙ МАРШРУТ:
        -- Этаж 1-2: Идём СРАЗУ к brainrot (humanoid сам поднимется по лестнице)
        -- Этаж 3: Элеватор -> brainrot -> вниз -> свой collect zone
        
        log("[ROUTE] SIMPLIFIED: Direct route to brainrot at Floor " .. brainrotFloor)
        log("[ROUTE] Target brainrot: " .. bestBrainrot.name .. ", pos: " .. string.format("%.1f, %.1f, %.1f", targetPos.X, targetPos.Y, targetPos.Z))
        
        -- СТРОГАЯ ПРОВЕРКА: Определяем текущий этаж персонажа
        local currentPlayerFloor = getPlayerCurrentFloor()
        log("[ROUTE] Current player floor: " .. currentPlayerFloor .. ", target brainrot floor: " .. brainrotFloor)
        
        -- ВАЛИДАЦИЯ: Если персонаж на неправильном этаже - сначала переместиться
        -- Если на 3 этаже и брейнрот на 1-2 - спуститься
        if currentPlayerFloor >= 3 and brainrotFloor <= 2 then
            updateStatus("Wrong floor!\nDescending from " .. currentPlayerFloor .. "...", Color3.fromRGB(255, 200, 100))
            log("[ROUTE] Need to descend from floor " .. currentPlayerFloor .. " to reach brainrot on floor " .. brainrotFloor)
            local closestPlot = findClosestPlotToPlayer()
            if closestPlot then
                walkDownFromThirdFloor(closestPlot)
                task.wait(0.5)
            end
            currentPlayerFloor = getPlayerCurrentFloor()
            log("[ROUTE] After descent, now on floor " .. currentPlayerFloor)
        end
        
        -- Если на 2 этаже и брейнрот на 1 - спуститься по лестнице
        if currentPlayerFloor == 2 and brainrotFloor == 1 then
            updateStatus("On 2nd floor\nDescending stairs...", Color3.fromRGB(255, 200, 100))
            log("[ROUTE] Need to descend stairs to reach brainrot on floor 1")
            local closestPlot = findClosestPlotToPlayer()
            if closestPlot then
                local stairsBottom, stairsTop = getStairsPositions(closestPlot)
                if stairsBottom and stairsTop then
                    simplePathfindTo(stairsTop, 10)
                    simpleWalkTo(stairsBottom, 15, true)
                end
            end
            currentPlayerFloor = getPlayerCurrentFloor()
            log("[ROUTE] After stairs descent, now on floor " .. currentPlayerFloor)
        end
        
        -- Сбрасываем idle таймер перед движением
        lastActionTime = tick()
        lastActionPos = hrp.Position
        
        local walkSuccess, pickedUp = false, false
        
        if brainrotFloor <= 2 then
            -- ЭТАЖ 1-2: Идём к brainrot с разбиением на этапы (лестница)
            updateStatus("Walking to " .. bestBrainrot.name .. "...\n(Floor " .. brainrotFloor .. ")", Color3.fromRGB(100, 200, 255))
            
            walkSuccess, pickedUp = walkToBrainrot(targetPos, 45, nil, currentPlot, brainrotFloor)
            
        else
            -- ЭТАЖ 3: Используем элеватор
            -- ВАЛИДАЦИЯ: Сначала убедимся что мы на земле (этаж 1)
            currentPlayerFloor = getPlayerCurrentFloor()
            if currentPlayerFloor > 1 then
                updateStatus("Need ground first\nDescending...", Color3.fromRGB(255, 200, 100))
                log("[ROUTE] Before elevator: need to reach ground first, currently on floor " .. currentPlayerFloor)
                
                if currentPlayerFloor >= 3 then
                    local closestPlot = findClosestPlotToPlayer()
                    if closestPlot then
                        walkDownFromThirdFloor(closestPlot)
                        task.wait(0.5)
                    end
                end
                
                currentPlayerFloor = getPlayerCurrentFloor()
                if currentPlayerFloor == 2 then
                    local closestPlot = findClosestPlotToPlayer()
                    if closestPlot then
                        local stairsBottom, stairsTop = getStairsPositions(closestPlot)
                        if stairsBottom and stairsTop then
                            simplePathfindTo(stairsTop, 10)
                            simpleWalkTo(stairsBottom, 15, true)
                        end
                    end
                end
                
                currentPlayerFloor = getPlayerCurrentFloor()
                log("[ROUTE] After descent, now on floor " .. currentPlayerFloor)
            end
            
            updateStatus("Brainrot on 3rd floor\nUsing elevator...", Color3.fromRGB(200, 200, 100))
            log("[ROUTE] >>> Ascending to 3rd floor for brainrot: " .. bestBrainrot.name)
            
            if not walkToThirdFloor(bestBrainrot.plot) then
                updateStatus("Failed to reach 3rd floor\nWaiting for respawn...", Color3.fromRGB(255, 100, 100))
                log("[ROUTE] Failed to reach 3rd floor - waiting for respawn")
                releaseReservation(brainrotKey)
                destroyElevator()
                -- Не возвращаемся на базу - ждём респавн
                task.wait(2)
                continue
            end
            log("[ROUTE] Successfully on 3rd floor!")
            
            -- ВАЖНО: Ждём пока лифт полностью поднимется и игрок стабилизируется
            task.wait(1)
            
            -- СТРОГАЯ ВАЛИДАЦИЯ: Проверяем что мы ДЕЙСТВИТЕЛЬНО на 3 этаже
            currentPlayerFloor = getPlayerCurrentFloor()
            if currentPlayerFloor < 3 then
                log("[ROUTE] ERROR: After elevator, still on floor " .. currentPlayerFloor .. ", expected 3!")
                updateStatus("Elevator failed!\nRetrying...", Color3.fromRGB(255, 100, 100))
                releaseReservation(brainrotKey)
                task.wait(1)
                continue
            end
            log("[ROUTE] Confirmed on floor " .. currentPlayerFloor)
            
            -- Проверяем brainrot ещё на месте
            if not checkAndSwitchTarget() then
                updateStatus("Target gone, returning...", Color3.fromRGB(255, 150, 100))
                walkDownFromThirdFloor(bestBrainrot.plot)
                task.wait(0.2)
                continue
            end
            
            -- На 3 этаже используем ПРОСТОЕ движение (не pathfinding!)
            -- Pathfinding может строить маршрут через пол
            updateStatus("Walking to " .. bestBrainrot.name .. "...\n(Floor 3)", Color3.fromRGB(100, 200, 255))
            log("[ROUTE] Using simple movement on 3rd floor to brainrot")
            
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChild("Humanoid")
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            
            if humanoid and hrp then
                -- Простое движение к brainrot на 3 этаже
                humanoid:MoveTo(targetPos)
                
                local moveStart = tick()
                local lastPos = hrp.Position
                local stuckTime = 0
                
                while tick() - moveStart < 30 do
                    if not CONFIG.FARM_ENABLED then break end
                    
                    -- Проверяем подобрали ли brainrot
                    if isCarryingBrainrot() then
                        walkSuccess = true
                        pickedUp = true
                        log("[ROUTE] Picked up brainrot on 3rd floor!")
                        break
                    end
                    
                    local dist = (hrp.Position - targetPos).Magnitude
                    if dist < 6 then
                        walkSuccess = true
                        log("[ROUTE] Reached brainrot on 3rd floor")
                        break
                    end
                    
                    -- Проверка застревания
                    local moved = (hrp.Position - lastPos).Magnitude
                    if moved < 0.2 then
                        stuckTime = stuckTime + 0.1
                        if stuckTime > 2 then
                            humanoid.Jump = true
                            stuckTime = 0
                        end
                    else
                        stuckTime = 0
                    end
                    
                    lastPos = hrp.Position
                    humanoid:MoveTo(targetPos)
                    task.wait(0.1)
                end
            end
        end
        
        -- Если подобрали brainrot - сразу идём сдавать
        if pickedUp then
            updateStatus("Picked up " .. bestBrainrot.name .. "!\nDelivering...", Color3.fromRGB(100, 255, 200))
            
            -- Только для 3 этажа нужен спуск через элеватор
            -- Для 1-2 этажей pathfinding сам спустится по лестнице
            if brainrotFloor == 3 then
                walkDownFromThirdFloor(bestBrainrot.plot)
            end
        elseif not walkSuccess then
            -- Проверяем: может лазеры мешали?
            local closestPlot = findClosestPlotToPlayer()
            if closestPlot and hasActiveLasers(closestPlot) then
                -- Лазеры активны - ждём их исчезновения и пробуем снова
                updateStatus("Laser gate active\\nWaiting...", Color3.fromRGB(255, 200, 100))
                log("[ROUTE] Laser gate blocking path, waiting for it to disappear...")
                
                if waitForLasersToDisappear(closestPlot, PATHFINDING_CONFIG.LASER_WAIT_TIMEOUT) then
                    -- Лазеры исчезли - пробуем ещё раз
                    log("[ROUTE] Lasers gone, retrying walk to brainrot")
                    continue -- Повторяем цикл с тем же brainrot
                end
            end
            
            -- walkToBrainrot уже сделала 10 попыток перестроить маршрут внутри себя
            -- Если всё ещё не получилось - ждём минимум 45 секунд перед возвратом на базу
            updateStatus("Walk failed (10 retries)\nWaiting 45s before return...", Color3.fromRGB(255, 100, 100))
            log("[ROUTE] Walk to brainrot failed after 10 internal retries - waiting 45s before return")
            releaseReservation(brainrotKey)
            if brainrotFloor == 3 then
                walkDownFromThirdFloor(bestBrainrot.plot)
            end
            task.wait(45)  -- Минимум 45 секунд перед возвратом
            continue
        end
        if not CONFIG.FARM_ENABLED then break end
        if not doWatchdogCheck() then 
            releaseReservation(brainrotKey) 
            if brainrotFloor > 1 then safeReturnToGround(nil, myCarpetPos) end
            continue 
        end
        
        -- Если ещё не подобрали - пробуем украсть
        if not pickedUp then
            -- Последняя проверка перед кражей
            if not isBrainrotStillThere(currentPlot, bestBrainrot.podiumIndex) then
                updateStatus("Brainrot stolen!\nSearching new...", Color3.fromRGB(255, 100, 100))
                releaseReservation(brainrotKey)
                if brainrotFloor == 3 then
                    walkDownFromThirdFloor(bestBrainrot.plot)
                end
                -- Не возвращаемся на базу - просто ищем новый
                task.wait(0.3)
                continue
            end

            updateStatus("Stealing...", Color3.fromRGB(255, 255, 100))
            updatePanelStatus("stealing", "Stealing " .. bestBrainrot.name)
            local stealSuccess = tryStealBrainrot(bestBrainrot)

            if not stealSuccess then
                updateStatus("Steal failed\nWaiting 45s before return...", Color3.fromRGB(255, 100, 100))
                updatePanelStatus("waiting", "Steal failed, waiting 45s")
                releaseReservation(brainrotKey)
                if brainrotFloor == 3 then
                    walkDownFromThirdFloor(bestBrainrot.plot)
                end
                -- Ждём минимум 45 секунд перед возвратом
                task.wait(45)
                continue
            end

            updateStatus("Carrying " .. bestBrainrot.name .. "!", Color3.fromRGB(100, 255, 200))
            updatePanelStatus("delivering", "Carrying " .. bestBrainrot.name)
            
            -- Только для 3 этажа нужен спуск через элеватор
            if brainrotFloor == 3 then
                walkDownFromThirdFloor(bestBrainrot.plot)
            end
            -- Pathfinding сам спустится по лестнице для 1-2 этажей
        end
        
        -- Используем pathfinding для возврата к своему collect zone
        local collectZonePos = myCollectZone.Position
        
        -- Позиция для подхода к ЦЕНТРУ collect zone
        local myCollectApproachPos = Vector3.new(
            collectZonePos.X + 3,
            collectZonePos.Y + 2,
            collectZonePos.Z
        )
        
        -- Проверяем - может мы УЖЕ на collect zone?
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local currentDistToCollect = hrp and (hrp.Position - myCollectApproachPos).Magnitude or 999
        
        if currentDistToCollect > 12 then
            updateStatus("Returning to my collect zone...", Color3.fromRGB(100, 255, 200))
            log("[ROUTE] Returning via pathfinding, dist=" .. string.format("%.1f", currentDistToCollect))
            
            lastActionTime = tick()
            lastActionPos = hrp and hrp.Position
            
            -- ВАЖНО: Проверяем этаж перед возвратом
            local currentFloorBeforeReturn = getPlayerCurrentFloor()
            log("[ROUTE] Current floor before return: " .. currentFloorBeforeReturn)
            
            -- Если на 3 этаже - сначала спускаемся через лифт
            if currentFloorBeforeReturn >= 3 then
                log("[ROUTE] On floor 3+, using elevator to descend first")
                updateStatus("Descending from floor " .. currentFloorBeforeReturn .. "...", Color3.fromRGB(255, 200, 100))
                local closestPlot = findClosestPlotToPlayer()
                if closestPlot then
                    walkDownFromThirdFloor(closestPlot)
                end
                task.wait(0.5)
            end
            
            -- Теперь pathfinding (он сам спустится по лестнице если на 2 этаже)
            pathfindToCollectZone(collectZonePos, 35)
        else
            log("[ROUTE] Already at collect zone (dist=" .. string.format("%.1f", currentDistToCollect) .. ")")
        end
        if not CONFIG.FARM_ENABLED then break end
        if not doWatchdogCheck() then continue end

        -- Доставляем - проверяем сразу, сбросился ли brainrot
        updateStatus("Delivering...", Color3.fromRGB(100, 255, 200))
        
        -- Проверяем расстояние до collect zone
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        
        local distToCollect = hrp and (hrp.Position - collectZonePos).Magnitude or 999
        
        -- Если ещё несёт brainrot - идём прямо в collect zone
        if isCarryingBrainrot() and distToCollect > 5 then
            local humanoid = character and character:FindFirstChild("Humanoid")
            if humanoid then
                humanoid:MoveTo(collectZonePos)
                task.wait(2)
            end
        end
        
        -- Быстрая проверка каждые 0.1 сек, максимум 1 секунду
        local waitTime = 0
        while isCarryingBrainrot() and waitTime < 1 and CONFIG.FARM_ENABLED do
            task.wait(0.1)
            waitTime = waitTime + 0.1
        end
        
        if not CONFIG.FARM_ENABLED then break end

        local usedAfter, totalAfter = countPlotsOnBase()
        setPlotInfo(usedAfter, totalAfter)

        if not isCarryingBrainrot() then
            CONFIG.CollectedThisSession = (CONFIG.CollectedThisSession or 0) + 1
            local totalOnBase = scanAndSaveBaseBrainrots()
            updateStatus(bestBrainrot.name .. " placed!\nBase: " .. usedAfter .. "/" .. totalAfter .. "\nOn base: " .. totalOnBase, Color3.fromRGB(100, 255, 100))
            updatePanelStatus("idle", bestBrainrot.name .. " placed!")
            -- Освобождаем резервацию и обновляем статус аккаунта
            releaseReservation(brainrotKey)
            updateAccountStatus(totalOnBase)
            savePanelData() -- Синхронизация после успешной доставки
            
            if usedAfter >= totalAfter then
                updateStatus("BASE FULL!\n" .. usedAfter .. "/" .. totalAfter .. " plots\nStopping...", Color3.fromRGB(255, 100, 100))
                updatePanelStatus("full", "Base full!")
                CONFIG.FARM_ENABLED = false
                break
            end
        end

        task.wait(0.15)
    end

    farmRunning = false
    updateStatus("Stopped", Color3.fromRGB(150, 150, 150))
    updatePanelStatus("stopped", "Stopped")
    savePanelData() -- Синхронизация при остановке
end

task.spawn(function()
    while true do
        task.wait(0.3)
        -- В SAFE_MODE фарм-цикл НЕ запускается
        if not SAFE_MODE and CONFIG.FARM_ENABLED and not farmRunning then task.spawn(farmLoop) end
    end
end)

task.defer(function()
    task.wait(1) -- Быстрее инициализация
    local used, total = countPlotsOnBase()
    setPlotInfo(used, total)
    CONFIG.CollectedThisSession = 0
    -- Сканируем brainrots на базе при запуске
    local totalOnBase = scanAndSaveBaseBrainrots()
    -- Обновляем статус аккаунта в координации
    updateAccountStatus(totalOnBase)
    -- Сохраняем данные для панели
    updatePanelStatus("ready", "Ready - " .. totalOnBase .. " brainrots")
    
    -- МОМЕНТАЛЬНАЯ синхронизация при заходе в игру!
    log("[PanelSync] Immediate sync on game start...")
    syncNow()
    
    -- Статус зависит от SAFE_MODE
    if SAFE_MODE then
        updateStatus("SAFE MODE\nSync only\nBrainrots: " .. totalOnBase .. "\nKey: " .. FARM_KEY, Color3.fromRGB(255, 200, 100))
        updatePanelStatus("safe_mode", "Safe Mode - " .. totalOnBase .. " brainrots")
    else
        updateStatus("Ready\nPress START\nBrainrots: " .. totalOnBase .. "\nKey: " .. FARM_KEY, Color3.fromRGB(100, 200, 100))
    end
end)

-- ============ SAFE MODE SYNC LOOP ============
-- В безопасном режиме постоянно сканируем и синхронизируем данные
-- без выполнения каких-либо действий (кражи, движения и т.д.)
if SAFE_MODE then
    task.spawn(function()
        log("[SAFE_MODE] Safe mode sync loop started")
        while true do
            task.wait(5) -- Синхронизация каждые 5 секунд
            
            pcall(function()
                -- Обновляем счётчик базы в GUI
                local used, total = countPlotsOnBase()
                setPlotInfo(used, total)
                
                -- Сканируем только свою базу и сохраняем данные для панели
                local totalOnBase = scanAndSaveBaseBrainrots()
                savePanelData()
                
                -- Обновляем статус в GUI
                updateStatus("SAFE MODE\nSync only\nBrainrots: " .. totalOnBase .. "\nKey: " .. FARM_KEY, Color3.fromRGB(255, 200, 100))
                
                -- Обновляем статус для панели
                updatePanelStatus("safe_mode", "Safe Mode - " .. totalOnBase .. " brainrots")
                
                -- Синхронизируем с панелью
                syncNow()
            end)
            
            log("[SAFE_MODE] Sync completed")
        end
    end)
end
-- ============ END SAFE MODE SYNC LOOP ============

-- Фоновый цикл синхронизации с веб-панелью
-- ВАЖНО: Работает ВСЕГДА, независимо от того запущен фарм или нет
-- Каждый фермер синхронизирует ТОЛЬКО свои данные
task.spawn(function()
    task.wait(1) -- Быстрая инициализация
    while true do
        task.wait(3) -- Каждые 3 секунды для быстрого обновления
        
        -- В SAFE_MODE - всегда safe_mode статус
        if SAFE_MODE then
            currentStatus = "safe_mode"
            currentAction = "Sync Only"
        elseif CONFIG.FARM_ENABLED and farmRunning then
            -- Фарм активен - статус устанавливается в farmLoop
        else
            -- Фарм не активен - ставим idle
            currentStatus = "idle"
            currentAction = CONFIG.FARM_ENABLED and "Ready" or "Disabled"
        end
        
        -- Всегда синхронизируем с панелью (только свои данные!)
        if PANEL_SYNC_ENABLED then
            pcall(function()
                savePanelData()
            end)
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function(character)
    -- Ждём пока персонаж полностью загрузится
    local humanoid = character:WaitForChild("Humanoid", 10)
    local hrp = character:WaitForChild("HumanoidRootPart", 10)
    
    if humanoid and hrp then
        -- Ждём пока персонаж сможет двигаться
        task.wait(0.5)
        -- В SAFE_MODE не показываем "Respawned! Continuing..."
        if not SAFE_MODE and CONFIG.FARM_ENABLED then 
            updateStatus("Respawned!\nContinuing...", Color3.fromRGB(100, 255, 100))
        end
    end
end)
