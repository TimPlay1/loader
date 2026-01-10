task.wait(4) -- Group 1: Core/Protection (4 sec delay)

--[[
    Admin Abuse v1.0 - Автоматическое использование админ команд на воре
    + Отслеживает игрока который несёт лучший brainrot
    + Автоматически применяет команды по очереди с учётом кулдаунов
    + GUI с сохранением позиции и настроек
    [PROTECTED] - Использует gethui() для обхода античита
]]


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

-- ============== ЗАЩИТА ОТ АНТИЧИТА ==============

-- Защищённый контейнер для GUI (ленивая инициализация)
local ProtectedGuiContainer = nil

-- Получение защищённого GUI контейнера (gethui или CoreGui)
local function getProtectedGui()
    -- Если уже инициализирован - возвращаем
    if ProtectedGuiContainer then
        return ProtectedGuiContainer
    end
    
    -- gethui() - самый защищённый способ (не детектится)
    if gethui then
        local success, result = pcall(gethui)
        if success and result then
            ProtectedGuiContainer = result
            return result
        end
    end
    
    -- Fallback на CoreGui
    local success, result = pcall(function()
        return CoreGui
    end)
    if success and result then
        ProtectedGuiContainer = result
        return result
    end
    
    -- Последний fallback - PlayerGui
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if PlayerGui then
        ProtectedGuiContainer = PlayerGui
        return PlayerGui
    end
    
    -- Ждём PlayerGui если ничего не доступно
    PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    ProtectedGuiContainer = PlayerGui
    return PlayerGui
end

-- Генерация случайного имени для объектов (избегаем детекта по именам)
local function generateRandomName()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local name = ""
    for i = 1, math.random(8, 16) do
        local idx = math.random(1, #chars)
        name = name .. chars:sub(idx, idx)
    end
    return name
end

-- ============== SYNCHRONIZER ANTI-CHEAT PATCH ==============
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
        end
    end)
end

-- ============== ЗАГРУЗКА ЗАВИСИМОСТЕЙ ДЛЯ НОВОЙ ЛОГИКИ ПОИСКА BRAINROT ==============
local Shared = ReplicatedStorage:WaitForChild("Shared", 30)
local Packages = ReplicatedStorage:WaitForChild("Packages", 30)
local PlotsFolder = Workspace:WaitForChild("Plots", 30)

local AnimalsShared = nil
local Synchronizer = nil

if Shared and Packages then
    pcall(function()
        AnimalsShared = require(Shared:WaitForChild("Animals"))
    end)
    pcall(function()
        Synchronizer = require(Packages:WaitForChild("Synchronizer"))
    end)
end

-- ЗАЩИТА: Используем getProtectedGui() для получения контейнера
local function getGuiParent()
    return getProtectedGui()
end

-- ============== КОНФИГУРАЦИЯ КОМАНД ==============

-- Все доступные админ команды с их кулдаунами
-- Порядок: balloon -> rocket (после rocket не использовать другие команды ~10 сек) -> ragdoll -> остальные
local ADMIN_COMMANDS = {
    { id = "balloon", name = "balloon", cooldown = 30, enabled = true, priority = 1 },
    { id = "rocket", name = "rocket", cooldown = 120, enabled = true, priority = 2 }, -- После rocket ждём, ракета сама скинет brainrot
    { id = "ragdoll", name = "ragdoll", cooldown = 30, enabled = true, priority = 3 },
    { id = "tiny", name = "tiny", cooldown = 60, enabled = true, priority = 4 },
    { id = "jail", name = "jail", cooldown = 60, enabled = true, priority = 5 },
    { id = "jumpscare", name = "jumpscare", cooldown = 60, enabled = true, priority = 6 },
    { id = "inverse", name = "inverse", cooldown = 60, enabled = true, priority = 7 },
    { id = "control", name = "control", cooldown = 60, enabled = true, priority = 8 },
    { id = "morph", name = "morph", cooldown = 60, enabled = true, priority = 9 },
    { id = "nightvision", name = "nightvision", cooldown = 60, enabled = false, priority = 10 }, -- По умолчанию выключено (не мешает)
}

-- Время ожидания после rocket (ракете нужно время долететь)
local ROCKET_PAUSE_TIME = 10 -- секунд после использования rocket не применять команды
local lastRocketTime = 0 -- когда последний раз использовали rocket

-- ============== СИСТЕМА СОХРАНЕНИЯ КОНФИГА ==============

local CONFIG_FILE = "adminabuse_config.json"
local FRIENDLIST_FILE = "killaura_friendlist.txt" -- Используем тот же файл что и killaura

-- Friend List (players who won't be targeted) - синхронизирован с killaura.lua
local FriendList = {} -- Format: { [userId] = { Name = "username", DisplayName = "displayname" } }

local DEFAULT_CONFIG = {
    AUTO_ABUSE_ENABLED = false,
    ESP_ENABLED = true,
    CHECK_INTERVAL = 0.15, -- Очень быстрая проверка
    MIN_BRAINROT_VALUE = 0,
    GUI_POSITION_X = 300,
    GUI_POSITION_Y = 100,
    GUI_MINIMIZED = false,
    COMMAND_SETTINGS = {}, -- Сохраняется enabled/disabled для каждой команды
    THIEF_CARRY_DELAY = 3, -- Задержка в секундах перед применением команд
    DISABLE_ON_REINJECT = false, -- Выключать скрипт при реинжекте
    AUTO_ENABLE_ON_THIEF = true, -- Автоматически включать при обнаружении вора базы
}

local CONFIG = {}

-- ═══════════════════════════════════════════════════════════════════════
-- СИСТЕМА АВТО-ВКЛЮЧЕНИЯ ПРИ ВОРЕ СВОЕЙ БАЗЫ
-- ═══════════════════════════════════════════════════════════════════════
local WasManuallyDisabled_Admin = false  -- Был ли скрипт выключен до авто-включения
local AutoEnabledForMyBaseThief_Admin = false  -- Включили ли мы автоматически из-за вора базы
local LastMyBaseThiefDetected_Admin = nil  -- Последний обнаруженный вор базы

local function deepCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            copy[k] = deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

local function saveConfig()
    local success, err = pcall(function()
        -- Собираем настройки команд
        local cmdSettings = {}
        for _, cmd in ipairs(ADMIN_COMMANDS) do
            cmdSettings[cmd.id] = cmd.enabled
        end
        
        local jsonData = HttpService:JSONEncode({
            AUTO_ABUSE_ENABLED = CONFIG.AUTO_ABUSE_ENABLED,
            ESP_ENABLED = CONFIG.ESP_ENABLED,
            MIN_BRAINROT_VALUE = CONFIG.MIN_BRAINROT_VALUE,
            GUI_POSITION_X = CONFIG.GUI_POSITION_X,
            GUI_POSITION_Y = CONFIG.GUI_POSITION_Y,
            GUI_MINIMIZED = CONFIG.GUI_MINIMIZED,
            COMMAND_SETTINGS = cmdSettings,
            DISABLE_ON_REINJECT = CONFIG.DISABLE_ON_REINJECT,
            AUTO_ENABLE_ON_THIEF = CONFIG.AUTO_ENABLE_ON_THIEF,
        })
        writefile(CONFIG_FILE, jsonData)
    end)
end

local function loadConfig()
    CONFIG = deepCopy(DEFAULT_CONFIG)
    
    local success, result = pcall(function()
        if isfile and isfile(CONFIG_FILE) then
            local jsonData = readfile(CONFIG_FILE)
            local savedConfig = HttpService:JSONDecode(jsonData)
            
            for key, value in pairs(savedConfig) do
                if CONFIG[key] ~= nil then
                    CONFIG[key] = value
                end
            end
            
            -- Применяем сохранённые настройки команд
            if savedConfig.COMMAND_SETTINGS then
                for _, cmd in ipairs(ADMIN_COMMANDS) do
                    if savedConfig.COMMAND_SETTINGS[cmd.id] ~= nil then
                        cmd.enabled = savedConfig.COMMAND_SETTINGS[cmd.id]
                    end
                end
            end
        end
    end)
    
    if not success then
        CONFIG = deepCopy(DEFAULT_CONFIG)
    end
    
    -- Если включена опция "Выключать при реинжекте" - выключаем скрипт
    if CONFIG.DISABLE_ON_REINJECT then
        CONFIG.AUTO_ABUSE_ENABLED = false
    end
end

loadConfig()

-- ============== FRIEND LIST СИСТЕМА (синхронизирована с killaura.lua) ==============

-- Загрузка Friend List из файла
local function LoadFriendList()
    local success, result = pcall(function()
        if not isfolder or not isfolder("killaura_data") then
            return
        end
        
        if not isfile or not isfile("killaura_data/" .. FRIENDLIST_FILE) then
            return
        end
        
        local data = readfile("killaura_data/" .. FRIENDLIST_FILE)
        local decoded = HttpService:JSONDecode(data)
        
        if type(decoded) == "table" then
            FriendList = decoded
        end
    end)
end

-- Проверить в Friend List ли игрок
local function IsInFriendList(player)
    if not player then
        return false
    end
    
    local userId = tostring(player.UserId)
    return FriendList[userId] ~= nil
end

-- Получить имя друга по userId (для отображения)
local function GetFriendName(userId)
    local userIdStr = tostring(userId)
    if FriendList[userIdStr] then
        return FriendList[userIdStr].Name
    end
    return nil
end

-- Загружаем Friend List при старте
LoadFriendList()

-- Подписываемся на изменения файла Friend List (синхронизация с killaura)
local lastFriendListCheck = 0
local FRIENDLIST_CHECK_INTERVAL = 2 -- Проверять каждые 2 секунды

local function RefreshFriendList()
    local now = tick()
    if now - lastFriendListCheck < FRIENDLIST_CHECK_INTERVAL then
        return
    end
    lastFriendListCheck = now
    LoadFriendList()
end

-- ============== DEBUG FILE LOGGING ==============
local DEBUG_LOG_FILE = "adminabuse_debug.log"
local debugLogEnabled = false -- ОТКЛЮЧЕНО
local lastLogTime = 0
local LOG_INTERVAL = 1 -- Логировать не чаще чем раз в секунду

local function clearDebugLog()
    pcall(function()
        writefile(DEBUG_LOG_FILE, "=== AdminAbuse Debug Log Started at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
    end)
end

local function logToFile(message)
    if not debugLogEnabled then return end
    pcall(function()
        local timestamp = os.date("%H:%M:%S")
        local existingContent = ""
        if isfile and isfile(DEBUG_LOG_FILE) then
            existingContent = readfile(DEBUG_LOG_FILE)
        end
        writefile(DEBUG_LOG_FILE, existingContent .. "[" .. timestamp .. "] " .. message .. "\n")
    end)
end

local function logDetectionState(data)
    if not debugLogEnabled then return end
    local now = tick()
    if now - lastLogTime < LOG_INTERVAL then return end
    lastLogTime = now
    
    pcall(function()
        local lines = {
            "",
            "========== DETECTION STATE ==========",
            "Time: " .. os.date("%H:%M:%S"),
            "",
            "-- MY PLOT INFO --",
            "MyPlot: " .. tostring(data.myPlot),
            "MyBestBrainrot: " .. tostring(data.myBestName) .. " = " .. tostring(data.myBestValue),
            "",
            "-- ALL PODIUMS BEST --",
            "BestOnAllPodiums: " .. tostring(data.bestPodiumName) .. " = " .. tostring(data.bestPodiumValue),
            "",
            "-- SCAN STATS --",
            "ScanStats: " .. tostring(data.scanStats),
            "",
            "-- WORKSPACE MODELS (potential brainrots) --",
        }
        
        -- Логируем все модели в workspace с AnimalOverhead
        local workspaceModels = logWorkspaceModels and logWorkspaceModels() or {}
        if #workspaceModels > 0 then
            for i, m in ipairs(workspaceModels) do
                local weldsStr = #m.welds > 0 and table.concat(m.welds, ", ") or "none"
                local assemblyStr = m.assemblyRoot or "self"
                table.insert(lines, string.format("  [%d] %s | Overhead:%s FakeRoot:%s Root:%s | AssemblyRoot: %s | Welds: %s",
                    i, m.name, tostring(m.hasOverhead), tostring(m.hasFakeRoot), tostring(m.hasRoot), assemblyStr, weldsStr))
            end
        else
            table.insert(lines, "  (no brainrot models in workspace)")
        end
        
        table.insert(lines, "")
        table.insert(lines, "-- CARRIED BRAINROTS --")
        
        if data.carriedList and #data.carriedList > 0 then
            for i, c in ipairs(data.carriedList) do
                table.insert(lines, string.format("  [%d] %s carried by %s | Value: %s | Text: %s | Friend: %s", 
                    i, c.brainrotName, c.carrierName, tostring(c.value), tostring(c.text), tostring(c.isFriend or false)))
            end
        else
            table.insert(lines, "  (none found)")
        end
        
        table.insert(lines, "")
        table.insert(lines, "-- DETECTION RESULT --")
        table.insert(lines, "SearchMethod: " .. tostring(data.searchMethod or "unknown"))
        table.insert(lines, "DetectedThief: " .. tostring(data.thiefName))
        table.insert(lines, "ThiefCarrying: " .. tostring(data.thiefBrainrot))
        table.insert(lines, "ThiefValue: " .. tostring(data.thiefValue))
        table.insert(lines, "IsFriend: " .. tostring(data.isFriend))
        table.insert(lines, "CarryTime: " .. tostring(data.carryTime))
        table.insert(lines, "")
        table.insert(lines, "-- WHY THIS DECISION --")
        table.insert(lines, "Reason: " .. tostring(data.reason))
        table.insert(lines, "=====================================")
        
        local content = table.concat(lines, "\n")
        
        local existingContent = ""
        if isfile and isfile(DEBUG_LOG_FILE) then
            existingContent = readfile(DEBUG_LOG_FILE)
            -- Ограничиваем размер файла - оставляем последние 50KB
            if #existingContent > 50000 then
                existingContent = string.sub(existingContent, -30000)
            end
        end
        writefile(DEBUG_LOG_FILE, existingContent .. content .. "\n")
    end)
end

-- Очищаем лог при старте (только если debugLogEnabled)
if debugLogEnabled then
    clearDebugLog()
end

-- ============== МНОЖИТЕЛИ ЦЕН ==============

local PRICE_MULTIPLIERS = {
    [""] = 1,
    ["K"] = 1000,
    ["M"] = 1000000,
    ["B"] = 1000000000,
    ["T"] = 1000000000000,
    ["QA"] = 1000000000000000,
    ["QI"] = 1000000000000000000,
    ["SX"] = 1e21,
    ["SP"] = 1e24,
    ["OC"] = 1e27,
    ["NO"] = 1e30,
    ["DC"] = 1e33,
    ["UD"] = 1e36,
    ["DD"] = 1e39,
    ["TD"] = 1e42,
    ["QAD"] = 1e45,
    ["QID"] = 1e48,
    ["SXD"] = 1e51,
    ["SPD"] = 1e54,
    ["OCD"] = 1e57,
    ["NOD"] = 1e60,
    ["VG"] = 1e63,
    ["UVG"] = 1e66,
    ["DVG"] = 1e69,
    ["TVG"] = 1e72
}

local function parsePrice(priceString)
    local cleanString = tostring(priceString or ""):gsub("[$,]", ""):gsub("/s", "")
    local numericPart, unitPart = cleanString:match("([%d%.]+)%s*([A-Za-z]*)")
    if not numericPart then return 0 end
    local basePrice = tonumber(numericPart) or 0
    local upperUnit = string.upper(unitPart or "")
    local multiplier = PRICE_MULTIPLIERS[upperUnit] or 1
    return basePrice * multiplier
end

-- ============== ТАБЛИЦЫ МОДИФИКАТОРОВ (для расчёта Generation) ==============

local MUTATION_MODIFIERS = {
    ["Gold"] = 0.25,
    ["Diamond"] = 0.5,
    ["Bloodrot"] = 1,
    ["Candy"] = 3,
    ["Lava"] = 5,
    ["Galaxy"] = 6,
    ["YinYang"] = 6.5,
    ["Radioactive"] = 7.5,
    ["Rainbow"] = 9,
}

local TRAIT_MODIFIERS = {
    ["Taco"] = 2,
    ["Nyan"] = 5,
    ["Claws"] = 4,
    ["Bubblegum"] = 3,
    ["Festive"] = 1,
    ["Shiny"] = 0.5,
    ["Indonesia"] = 0.5,
    -- Sleepy обрабатывается отдельно (множитель 0.5)
}

-- ============== ФУНКЦИЯ РАСЧЁТА GENERATION ИЗ АТРИБУТОВ ==============
-- Формула: result = baseGeneration * (1 + mutationMod + sum(traitsMod))
-- Sleepy trait: result *= 0.5

local function calculateBrainrotGeneration(serverModel)
    if not serverModel then return 0, nil end
    
    -- Проверяем что это brainrot модель (должен быть Mutation или Traits или Index)
    local mutation = serverModel:GetAttribute("Mutation")
    local traitsJson = serverModel:GetAttribute("Traits")
    local indexAttr = serverModel:GetAttribute("Index")
    
    -- Если нет ни одного атрибута brainrot - это не brainrot
    if not mutation and not traitsJson and not indexAttr then
        return 0, nil
    end
    
    -- Index может быть атрибутом ИЛИ просто имя модели
    local index = indexAttr or serverModel.Name
    if not index or index == "" then return 0, nil end
    
    -- Парсим трейты (могут быть JSON или CSV строка)
    local traits = nil
    if traitsJson then
        if type(traitsJson) == "string" then
            local success, decoded = pcall(function()
                return HttpService:JSONDecode(traitsJson)
            end)
            if success and type(decoded) == "table" then
                traits = decoded
            else
                -- Разбиваем по запятой (CSV формат: "Taco,Claws,Nyan,Bubblegum")
                traits = {}
                for trait in string.gmatch(traitsJson, "[^,]+") do
                    table.insert(traits, trait)
                end
            end
        elseif type(traitsJson) == "table" then
            traits = traitsJson
        end
    end
    
    -- Получаем базовое Generation из игровых данных
    local baseGeneration = 0
    
    -- Пробуем получить из Animals модуля
    local animalsModule = nil
    pcall(function()
        local datas = ReplicatedStorage:FindFirstChild("Datas")
        if datas then
            animalsModule = datas:FindFirstChild("Animals")
        end
    end)
    
    if animalsModule then
        local success, animalData = pcall(function()
            return require(animalsModule)
        end)
        if success and animalData and animalData[index] then
            local data = animalData[index]
            if data.Generation then
                baseGeneration = data.Generation
            end
        end
    end
    
    -- Если не нашли в модуле - используем FALLBACK таблицу
    if baseGeneration == 0 then
        local FALLBACK_GENERATIONS = {
            ["Dragon Cannelloni"] = 250000000, ["Burguro And Fryuro"] = 150000000,
            ["La Secret Combinasion"] = 125000000, ["La Casa Boo"] = 100000000,
            ["Spooky and Pumpky"] = 80000000, ["Spaghetti Tualetti"] = 60000000,
            ["Garama and Madundung"] = 50000000, ["Ketchuru and Musturu"] = 42500000,
            ["La Supreme Combinasion"] = 40000000, ["Tictac Sahur"] = 37500000,
            ["Ketupat Kepat"] = 35000000, ["Tang Tang Keletang"] = 33500000,
            ["Los Tacoritas"] = 32000000, ["Eviledon"] = 31500000,
            ["Los Primos"] = 31000000, ["Esok Sekolah"] = 30000000,
            ["Tralaledon"] = 27500000, ["Mieteteira Bicicleteira"] = 26000000,
            ["Chipso and Queso"] = 25000000, ["Chillin Chili"] = 25000000,
            ["La Spooky Grande"] = 24500000, ["Los Bros"] = 24000000,
            ["La Extinct Grande"] = 23500000, ["Celularcini Viciosini"] = 22500000,
            ["Los 67"] = 22500000, ["Los Mobilis"] = 22000000,
            ["Money Money Puggy"] = 21000000, ["Los Hotspotsitos"] = 20000000,
            ["Los Spooky Combinasionas"] = 20000000, ["Las Sis"] = 17500000,
            ["Tacorita Bicicleta"] = 16500000, ["Nuclearo Dinossauro"] = 15000000,
            ["Los Combinasionas"] = 15000000, ["Mariachi Corazoni"] = 12500000,
            ["La Grande Combinasion"] = 10000000, ["67"] = 7500000,
            ["Los Chicleteiras"] = 7000000, ["Rang Ring Bus"] = 6000000,
            ["Tralalero Tralala"] = 50000, ["Matteo"] = 50000,
        }
        baseGeneration = FALLBACK_GENERATIONS[index] or 10
    end
    
    -- Применяем модификаторы
    local totalModifier = 1.0
    local hasSleepy = false
    
    -- Добавляем модификатор мутации
    if mutation and MUTATION_MODIFIERS[mutation] then
        totalModifier = totalModifier + MUTATION_MODIFIERS[mutation]
    end
    
    -- Добавляем модификаторы трейтов
    if traits and type(traits) == "table" then
        for _, trait in ipairs(traits) do
            if trait == "Sleepy" then
                hasSleepy = true
            elseif TRAIT_MODIFIERS[trait] then
                totalModifier = totalModifier + TRAIT_MODIFIERS[trait]
            end
        end
    end
    
    -- Вычисляем финальное значение
    local finalGeneration = baseGeneration * totalModifier
    
    -- Sleepy trait умножает результат на 0.5
    if hasSleepy then
        finalGeneration = finalGeneration * 0.5
    end
    
    return math.round(finalGeneration), index
end

-- Форматирование числа с суффиксами
local function formatGenerationNumber(num)
    if num >= 1e15 then return string.format("%.1fQa", num / 1e15)
    elseif num >= 1e12 then return string.format("%.1fT", num / 1e12)
    elseif num >= 1e9 then return string.format("%.1fB", num / 1e9)
    elseif num >= 1e6 then return string.format("%.1fM", num / 1e6)
    elseif num >= 1e3 then return string.format("%.1fK", num / 1e3)
    else return tostring(math.floor(num))
    end
end

-- ============== REMOTE EVENTS ==============

local Net = nil
local ExecuteCommandRemote = nil

-- ======== НОВЫЕ UUID ДЛЯ АДМИН ПАНЕЛИ (обновлено 2025-01-05) ========
-- Разработчик изменил RemoteEvent с "AdminPanelService/ExecuteCommand" на UUID
local ADMIN_REMOTE_UUID = "352aad58-c786-4998-886b-3e4fa390721e"
local ADMIN_EXECUTE_TOKEN = "78a772b6-9e1c-4827-ab8b-04a07838f298"

local function initializeRemotes()
    local success, result = pcall(function()
        local Packages = ReplicatedStorage:WaitForChild("Packages", 5)
        if Packages then
            Net = require(Packages:WaitForChild("Net"))
            -- НОВЫЙ RemoteEvent с UUID вместо старого "AdminPanelService/ExecuteCommand"
            ExecuteCommandRemote = Net:RemoteEvent(ADMIN_REMOTE_UUID)
            return true
        end
        return false
    end)
    return success and result
end

-- Выполнить команду на игроке
local function executeCommand(targetPlayer, commandId)
    if not ExecuteCommandRemote then
        if not initializeRemotes() then
            return false
        end
    end
    
    local success, err = pcall(function()
        -- НОВЫЙ ФОРМАТ: добавлен токен как первый параметр
        ExecuteCommandRemote:FireServer(ADMIN_EXECUTE_TOKEN, targetPlayer, commandId)
    end)
    
    -- Убираем зелёные нотификации об успешном выполнении команды (многократно чтобы точно поймать)
    local function hideAdminNotifications()
        local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            local notifContainer = playerGui:FindFirstChild("Notification")
            if notifContainer then
                local notification = notifContainer:FindFirstChild("Notification")
                if notification then
                    for _, child in ipairs(notification:GetChildren()) do
                        -- Удаляем нотификации содержащие "Successfully executed"
                        if child:IsA("TextLabel") and child.Name ~= "Template" then
                            local text = child.Text or ""
                            if text:find("Successfully") or text:find("executed") or text:find("92FF67") then
                                child.Visible = false
                                child:Destroy()
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Удаляем нотификации несколько раз чтобы точно поймать
    for i = 1, 5 do
        task.delay(0.1 * i, hideAdminNotifications)
    end
    
    -- Если это rocket - запоминаем время
    if commandId == "rocket" then
        lastRocketTime = tick()
    end
    
    return success
end

-- ============== СИСТЕМА КУЛДАУНОВ ==============

local commandCooldowns = {} -- { [commandId] = endTime }

local function isCommandOnCooldown(commandId)
    local endTime = commandCooldowns[commandId]
    if not endTime then return false end
    return tick() < endTime
end

local function getCommandCooldownRemaining(commandId)
    local endTime = commandCooldowns[commandId]
    if not endTime then return 0 end
    return math.max(0, endTime - tick())
end

local function putCommandOnCooldown(commandId, cooldownTime)
    commandCooldowns[commandId] = tick() + cooldownTime
end

local function getNextAvailableCommand()
    -- Сортируем по приоритету (меньше = выше приоритет)
    local sortedCommands = {}
    for _, cmd in ipairs(ADMIN_COMMANDS) do
        if cmd.enabled then
            table.insert(sortedCommands, cmd)
        end
    end
    table.sort(sortedCommands, function(a, b) return a.priority < b.priority end)
    
    for _, cmd in ipairs(sortedCommands) do
        if not isCommandOnCooldown(cmd.id) then
            return cmd
        end
    end
    return nil
end

-- ============== ПОИСК ВОРА (скопировано 1 в 1 из autosteal.lua) ==============

local cachedPlotsFolder = nil
local currentThief = nil -- { player, brainrotModel, name, value, text, isMyBaseThief }
local currentMyBaseThief = nil -- Вор моей базы (приоритет выше чем вор лучшего)

-- Система отслеживания времени переноски
local thiefCarryStartTime = 0 -- Когда вор начал нести brainrot
local lastThiefPlayer = nil -- Последний известный вор (для отслеживания смены)
local thiefCarryDuration = 0 -- Сколько секунд вор несёт brainrot

-- Отдельная система отслеживания времени для вора моей базы
local myBaseThiefCarryStartTime = 0
local lastMyBaseThiefPlayer = nil
local myBaseThiefCarryDuration = 0

-- Кэш для оптимизации поиска вора
local cachedThief = nil
local cachedMyBaseThief = nil
local lastThiefSearch = 0
local lastMyBaseThiefSearch = 0
local THIEF_CACHE_TIME = 0.15 -- Обновлять кэш каждые 0.15 сек (быстрее для лучшей детекции)

-- Кэш для findBestBrainrot
local cachedBestBrainrot = nil
local lastBrainrotSearch = 0
local BRAINROT_CACHE_TIME = 0.5 -- Кэшировать результат на 0.5 сек

-- Имя последнего лучшего brainrot (для отслеживания вора)
local lastBestBrainrotName = nil

local function findPlayerPlot()
    local playerName = LocalPlayer.Name
    local playerDisplayName = LocalPlayer.DisplayName
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    cachedPlotsFolder = plotsFolder

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local plotSign = plot:FindFirstChild("PlotSign")
        if not plotSign then continue end
        local surfaceGui = plotSign:FindFirstChild("SurfaceGui")
        if not surfaceGui then continue end
        local frame = surfaceGui:FindFirstChild("Frame")
        if not frame then continue end
        local nameLabel = frame:FindFirstChildOfClass("TextLabel")
        if not nameLabel or type(nameLabel.Text) ~= "string" then continue end

        local nameText = nameLabel.Text
        if string.find(nameText, playerDisplayName, 1, true) or
           string.find(nameText, playerName, 1, true) then
            return plot
        end
    end
    return nil
end

-- СТАРЫЕ ФУНКЦИИ getBrainrotIncomeFromModel и getBrainrotIncomeFromPodiumByName УДАЛЕНЫ
-- Вместо них используется calculateBrainrotGeneration (ищет реальное значение из GUI по имени)

-- ============== НОВАЯ ЛОГИКА: Поиск через Synchronizer (как в best brainrot logic.txt) ==============

-- Получить часть слота (подиума) для отображения ESP
local function getPartOfSlot(plot, slotIdx)
    if not plot or not slotIdx then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local slot = podiums:FindFirstChild(tostring(slotIdx))
    if not slot then return nil end
    
    local base = slot:FindFirstChild("Base")
    if base then
        if base:IsA("BasePart") then return base, slot end
        if base:IsA("Model") then
            local spawn = base:FindFirstChild("Spawn")
            if spawn and spawn:IsA("BasePart") then return spawn, slot end
            local part = base:FindFirstChildWhichIsA("BasePart", true)
            if part then return part, slot end
        end
    end
    
    local part = slot:FindFirstChildWhichIsA("BasePart", true)
    return part, slot
end

-- Найти модель brainrot на подиуме
local function findBrainrotModelOnPodium(plot, slotIdx, brainrotName)
    if not plot then return nil end
    
    if brainrotName then
        local model = plot:FindFirstChild(brainrotName)
        if model and model:IsA("Model") then
            return model
        end
    end
    
    local spawn = getPartOfSlot(plot, slotIdx)
    if spawn then
        local closestDist = 15
        local closestModel = nil
        for _, child in ipairs(plot:GetChildren()) do
            if child:IsA("Model") and child.Name ~= "AnimalPodiums" and 
               child.Name ~= "PlotSign" and child.Name ~= "Building" and 
               child.Name ~= "Decorations" then
                local hasMutation = child:GetAttribute("Mutation")
                local hasTraits = child:GetAttribute("Traits")
                local hasIndex = child:GetAttribute("Index")
                if hasMutation or hasTraits or hasIndex then
                    local modelPrimary = child.PrimaryPart or child:FindFirstChild("RootPart") or child:FindFirstChildWhichIsA("BasePart")
                    if modelPrimary then
                        local dist = (modelPrimary.Position - spawn.Position).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestModel = child
                        end
                    end
                end
            end
        end
        return closestModel
    end
    
    return nil
end

-- Основная функция поиска лучшего brainrot через Synchronizer
local function findBestTargetViaSync()
    if not AnimalsShared or not Synchronizer or not PlotsFolder then
        return nil
    end
    
    local myPlot = findPlayerPlot()
    local best = {Gen = -1, Plot = nil, Slot = nil, Name = "None", Info = nil}
    
    for _, plot in ipairs(PlotsFolder:GetChildren()) do
        if myPlot and plot.Name == myPlot.Name then continue end
        if plot.Name == LocalPlayer.Name then continue end
        
        local channel = nil
        pcall(function()
            channel = Synchronizer:Get(plot.Name)
        end)
        
        if channel then
            local owner = nil
            local animalList = nil
            pcall(function()
                owner = channel:Get("Owner")
                animalList = channel:Get("AnimalList")
            end)
            
            if owner and animalList then
                for slot, info in pairs(animalList) do
                    if type(info) == "table" then
                        local gen = 0
                        pcall(function()
                            gen = AnimalsShared:GetGeneration(info.Index, info.Mutation, info.Traits, nil) or 0
                        end)
                        
                        if gen > best.Gen then
                            best = {
                                Gen = gen,
                                Plot = plot,
                                Slot = slot,
                                Name = info.Index or "Unknown",
                                Info = info
                            }
                        end
                    end
                end
            end
        end
    end
    
    if best.Gen > 0 and best.Plot then
        return best
    end
    
    return nil
end

-- ============== ПОИСК ЛУЧШЕГО BRAINROT НА ПОДИУМАХ ==============

local function findBestBrainrot(forceRefresh)
    -- Используем кэш если не истёк
    local now = tick()
    if not forceRefresh and cachedBestBrainrot and (now - lastBrainrotSearch) < BRAINROT_CACHE_TIME then
        -- Быстрая проверка что кэш ещё валиден
        if cachedBestBrainrot.spawn and cachedBestBrainrot.spawn.Parent and
           cachedBestBrainrot.podium and cachedBestBrainrot.podium.Parent then
            return cachedBestBrainrot
        end
    end
    
    local myPlot = findPlayerPlot()
    local plotsFolder = cachedPlotsFolder or workspace:FindFirstChild("Plots")
    if not plotsFolder then
        cachedBestBrainrot = nil
        return nil
    end
    
    local bestBrainrot = nil
    local bestValue = CONFIG.MIN_BRAINROT_VALUE
    
    -- ============== НОВАЯ ЛОГИКА: Поиск через Synchronizer ==============
    local syncTarget = findBestTargetViaSync()
    if syncTarget and syncTarget.Gen > bestValue then
        local spawn, podium = getPartOfSlot(syncTarget.Plot, syncTarget.Slot)
        local brainrotModel = findBrainrotModelOnPodium(syncTarget.Plot, syncTarget.Slot, syncTarget.Name)
        
        if spawn then
            local generationText = formatGenerationNumber(syncTarget.Gen) .. "/s"
            
            bestValue = syncTarget.Gen
            bestBrainrot = {
                name = syncTarget.Name,
                value = syncTarget.Gen,
                text = generationText,
                plot = syncTarget.Plot,
                podium = podium,
                spawn = spawn,
                overhead = nil,
                model = brainrotModel
            }
        end
    end
    
    -- Если Synchronizer нашёл brainrot - используем его
    if bestBrainrot then
        cachedBestBrainrot = bestBrainrot
        lastBrainrotSearch = now
        return bestBrainrot
    end
    
    -- ============== FALLBACK: Старая логика поиска ==============
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        -- Пропускаем свой плот
        if plot == myPlot then continue end
        
        -- Ищем AnimalPodiums
        local animalPodiums = plot:FindFirstChild("AnimalPodiums")
        if not animalPodiums then continue end
        
        for _, podium in ipairs(animalPodiums:GetChildren()) do
            local base = podium:FindFirstChild("Base")
            if not base then continue end
            
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            
            -- Ищем AnimalOverhead в Spawn -> Attachment
            local animalOverhead = nil
            local spawnAttachment = spawn:FindFirstChild("Attachment")
            if spawnAttachment then
                animalOverhead = spawnAttachment:FindFirstChild("AnimalOverhead")
            end
            
            if not animalOverhead then continue end
            
            -- Получаем Generation label
            local generationLabel = animalOverhead:FindFirstChild("Generation")
            if not generationLabel or not generationLabel:IsA("TextLabel") then continue end
            
            local generationText = generationLabel.Text
            if not generationText then continue end
            
            -- Пропускаем если это таймер или READY
            local lowerText = string.lower(generationText)
            if lowerText == "ready!" or lowerText:match("^%d+[smp]$") or lowerText:match("^%d+:%d+") then
                continue
            end
            
            -- Должен содержать /s
            if not generationText:find("/s") and not generationText:find("/S") then
                continue
            end
            
            local generationValue = parsePrice(generationText)
            if generationValue <= 0 then continue end
            if generationValue <= bestValue then continue end
            
            -- Получаем имя brainrot
            local displayNameLabel = animalOverhead:FindFirstChild("DisplayName")
            local brainrotName = "Unknown"
            if displayNameLabel and displayNameLabel:IsA("TextLabel") then
                brainrotName = displayNameLabel.Text or "Unknown"
            end
            
            bestValue = generationValue
            bestBrainrot = {
                name = brainrotName,
                value = generationValue,
                text = generationText,
                plot = plot,
                podium = podium,
                spawn = spawn,
                overhead = animalOverhead
            }
        end
    end
    
    cachedBestBrainrot = bestBrainrot
    lastBrainrotSearch = now
    return bestBrainrot
end

-- ============== ПОИСК ЛУЧШЕГО УКРАДЕННОГО BRAINROT (статус Stolen на подиуме) ==============
-- Ищем самый ценный brainrot в статусе "Stolen" - его кто-то крадёт/несёт прямо сейчас

local function findBestStolenBrainrotName()
    local myPlot = findPlayerPlot()
    local plotsFolder = cachedPlotsFolder or workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    
    local bestName = nil
    local bestValue = 0
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot == myPlot then continue end
        
        local animalPodiums = plot:FindFirstChild("AnimalPodiums")
        if not animalPodiums then continue end
        
        for _, podium in ipairs(animalPodiums:GetChildren()) do
            local base = podium:FindFirstChild("Base")
            if not base then continue end
            
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            
            local spawnAttachment = spawn:FindFirstChild("Attachment")
            if not spawnAttachment then continue end
            
            local animalOverhead = spawnAttachment:FindFirstChild("AnimalOverhead")
            if not animalOverhead then continue end
            
            -- Проверяем статус "Stolen"
            local stolenLabel = animalOverhead:FindFirstChild("Stolen")
            if not stolenLabel or not stolenLabel:IsA("TextLabel") then continue end
            if not stolenLabel.Visible then continue end
            
            local stolenText = string.lower(tostring(stolenLabel.Text or ""))
            if stolenText ~= "stolen" then continue end
            
            -- Это brainrot в статусе Stolen! Получаем его ценность
            local generationLabel = animalOverhead:FindFirstChild("Generation")
            if not generationLabel or not generationLabel:IsA("TextLabel") then continue end
            
            local generationText = generationLabel.Text
            if not generationText or not generationText:find("/s") then continue end
            
            local generationValue = parsePrice(generationText)
            if generationValue <= bestValue then continue end
            
            -- Получаем имя brainrot из ProximityPrompt
            local promptAttachment = spawn:FindFirstChild("PromptAttachment")
            if promptAttachment then
                for _, desc in ipairs(promptAttachment:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") then
                        local objectText = desc.ObjectText
                        if objectText and objectText ~= "" then
                            bestValue = generationValue
                            bestName = objectText
                            break
                        end
                    end
                end
            end
        end
    end
    
    return bestName, bestValue
end

-- ============== ПОИСК ВОРА МОЕЙ БАЗЫ (ЛЮБОЙ BRAINROT) ==============
-- Находит игрока который ворует ЛЮБОЙ brainrot с МОЕГО плота
-- Этот вор имеет ПРИОРИТЕТ над вором лучшего brainrot и команды применяются СРАЗУ (без задержки)
local function findMyBaseThief()
    local myPlot = findPlayerPlot()
    if not myPlot then return nil end
    
    local myPlotName = myPlot.Name
    local bestThief = nil
    local bestCarriedValue = 0
    
    -- МЕТОД 1: Через Synchronizer - получаем AnimalList моего plot
    local myBrainrotNames = {}
    if Synchronizer then
        local channel = nil
        pcall(function()
            channel = Synchronizer:Get(myPlotName)
        end)
        
        if channel then
            local animalList = nil
            pcall(function()
                animalList = channel:Get("AnimalList")
            end)
            
            if animalList then
                for slot, info in pairs(animalList) do
                    if type(info) == "table" and info.Index then
                        myBrainrotNames[info.Index] = {
                            slot = slot,
                            mutation = info.Mutation,
                            traits = info.Traits
                        }
                    end
                end
            end
        end
    end
    
    -- FALLBACK: Получаем имена через ProximityPrompt на подиумах
    local animalPodiums = myPlot:FindFirstChild("AnimalPodiums")
    if animalPodiums then
        for _, podium in ipairs(animalPodiums:GetChildren()) do
            local base = podium:FindFirstChild("Base")
            if not base then continue end
            local spawn = nil
            if base:IsA("Model") then
                spawn = base:FindFirstChild("Spawn")
            elseif base:IsA("BasePart") then
                spawn = base
            end
            if not spawn then continue end
            
            local promptAttachment = spawn:FindFirstChild("PromptAttachment")
            if promptAttachment then
                for _, desc in ipairs(promptAttachment:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") and desc.ObjectText and desc.ObjectText ~= "" then
                        if not myBrainrotNames[desc.ObjectText] then
                            myBrainrotNames[desc.ObjectText] = { slot = podium.Name }
                        end
                        break
                    end
                end
            end
        end
    end
    
    -- Ищем brainrot модели в workspace которые кто-то несёт
    for _, obj in ipairs(workspace:GetChildren()) do
        if not obj:IsA("Model") then continue end
        if obj.Name == "RenderedMovingAnimals" or obj.Name == "Plots" or obj.Name == "Terrain" then continue end
        
        -- Проверяем принадлежит ли этот brainrot моей базе
        local brainrotName = obj:GetAttribute("Index") or obj.Name
        local brainrotInfo = myBrainrotNames[brainrotName] or myBrainrotNames[obj.Name]
        if not brainrotInfo then continue end
        
        -- Проверяем есть ли WeldConstraint (признак несения)
        local rootPart = obj:FindFirstChild("RootPart") or obj:FindFirstChild("FakeRootPart")
        if not rootPart then continue end
        
        local weldConstraint = rootPart:FindFirstChild("WeldConstraint")
        if not weldConstraint then continue end
        
        -- Ищем кто несёт
        local carrierHRP = nil
        if weldConstraint.Part0 and weldConstraint.Part0.Name == "HumanoidRootPart" then
            carrierHRP = weldConstraint.Part0
        elseif weldConstraint.Part1 and weldConstraint.Part1.Name == "HumanoidRootPart" then
            carrierHRP = weldConstraint.Part1
        end
        
        if not carrierHRP or not carrierHRP:IsA("BasePart") then continue end
        
        local carrierCharacter = carrierHRP.Parent
        if not carrierCharacter then continue end
        
        local carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
        if not carrierPlayer then continue end
        if carrierPlayer == LocalPlayer then continue end
        
        -- Проверяем Friend List
        if IsInFriendList(carrierPlayer) then continue end
        
        -- Получаем ценность brainrot
        local brainrotValue = 0
        local generationText = ""
        
        -- Через AnimalsShared если есть данные
        if AnimalsShared and brainrotInfo.mutation then
            pcall(function()
                brainrotValue = AnimalsShared:GetGeneration(brainrotName, brainrotInfo.mutation, brainrotInfo.traits, nil) or 0
                generationText = formatGenerationNumber(brainrotValue) .. "/s"
            end)
        end
        
        -- Fallback: Расчёт из атрибутов
        if brainrotValue == 0 then
            local calcGeneration, _ = calculateBrainrotGeneration(obj)
            if calcGeneration > 0 then
                brainrotValue = calcGeneration
                generationText = formatGenerationNumber(calcGeneration) .. "/s"
            end
        end
        
        -- Fallback: AnimalOverhead
        if brainrotValue == 0 then
            local animalOverhead = obj:FindFirstChild("AnimalOverhead", true)
            if animalOverhead then
                local generationLabel = animalOverhead:FindFirstChild("Generation")
                if generationLabel and generationLabel:IsA("TextLabel") then
                    local genText = generationLabel.Text
                    if genText and genText:find("/s") then
                        brainrotValue = parsePrice(genText)
                        generationText = genText
                    end
                end
            end
        end
        
        -- Выбираем самого ценного вора моей базы
        if brainrotValue >= bestCarriedValue then
            bestCarriedValue = brainrotValue
            bestThief = {
                player = carrierPlayer,
                character = carrierCharacter,
                hrp = carrierHRP,
                brainrotModel = obj,
                rootPart = rootPart,
                name = brainrotName,
                value = brainrotValue,
                text = generationText,
                isMyBaseThief = true
            }
        end
    end
    
    return bestThief
end

-- ============== ПОИСК ВОРА С ЛУЧШИМ BRAINROT ЧЕРЕЗ SYNCHRONIZER ==============
-- Находит вора который несёт ЛУЧШИЙ brainrot на сервере используя Synchronizer
local function findBestBrainrotThiefViaSync()
    -- Получаем лучший brainrot через Synchronizer
    local syncTarget = findBestTargetViaSync()
    if not syncTarget or not syncTarget.Name then
        return nil
    end
    
    local targetName = syncTarget.Name
    local targetPlot = syncTarget.Plot
    local targetSlot = syncTarget.Slot
    local targetGen = syncTarget.Gen
    
    -- Сохраняем имя лучшего brainrot для отслеживания
    lastBestBrainrotName = targetName
    
    -- МЕТОД 1: Ищем модель brainrot в workspace (кто-то несёт)
    for _, obj in ipairs(workspace:GetChildren()) do
        if not obj:IsA("Model") then continue end
        if obj.Name ~= targetName then continue end
        
        -- Проверяем RootPart.WeldConstraint (указывает на вора)
        local rootPart = obj:FindFirstChild("RootPart") or obj.PrimaryPart
        if not rootPart then continue end
        
        local weldConstraint = rootPart:FindFirstChild("WeldConstraint")
        if not weldConstraint then continue end
        
        local carrierHRP = nil
        if weldConstraint.Part0 and weldConstraint.Part0:IsA("BasePart") and weldConstraint.Part0.Name == "HumanoidRootPart" then
            carrierHRP = weldConstraint.Part0
        elseif weldConstraint.Part1 and weldConstraint.Part1:IsA("BasePart") and weldConstraint.Part1.Name == "HumanoidRootPart" then
            carrierHRP = weldConstraint.Part1
        end
        
        if not carrierHRP then continue end
        
        local carrierCharacter = carrierHRP.Parent
        if not carrierCharacter then continue end
        
        local carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
        if not carrierPlayer then continue end
        if carrierPlayer == LocalPlayer then continue end
        
        -- Получаем текст генерации
        local generationText = formatGenerationNumber(targetGen) .. "/s"
        
        return {
            player = carrierPlayer,
            character = carrierCharacter,
            hrp = carrierHRP,
            brainrotModel = obj,
            rootPart = rootPart,
            name = targetName,
            value = targetGen,
            text = generationText
        }
    end
    
    -- МЕТОД 2: Brainrot в Plots но в статусе Stolen (кто-то подбирает)
    -- Ищем модель на нужном подиуме и проверяем WeldConstraint
    if targetPlot then
        local brainrotModel = targetPlot:FindFirstChild(targetName)
        if brainrotModel and brainrotModel:IsA("Model") then
            -- Проверяем FakeRootPart или RootPart на наличие WeldConstraint к игроку
            local rootPart = brainrotModel:FindFirstChild("RootPart") or brainrotModel:FindFirstChild("FakeRootPart")
            if rootPart then
                local weldConstraint = rootPart:FindFirstChild("WeldConstraint")
                if weldConstraint then
                    local carrierHRP = nil
                    -- Проверяем Part0 и Part1
                    if weldConstraint.Part0 and weldConstraint.Part0:IsA("BasePart") and weldConstraint.Part0.Name == "HumanoidRootPart" then
                        carrierHRP = weldConstraint.Part0
                    elseif weldConstraint.Part1 and weldConstraint.Part1:IsA("BasePart") and weldConstraint.Part1.Name == "HumanoidRootPart" then
                        carrierHRP = weldConstraint.Part1
                    end
                    
                    if carrierHRP then
                        local carrierCharacter = carrierHRP.Parent
                        if carrierCharacter then
                            local carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
                            if carrierPlayer and carrierPlayer ~= LocalPlayer then
                                local generationText = formatGenerationNumber(targetGen) .. "/s"
                                
                                return {
                                    player = carrierPlayer,
                                    character = carrierCharacter,
                                    hrp = carrierHRP,
                                    brainrotModel = brainrotModel,
                                    rootPart = rootPart,
                                    name = targetName,
                                    value = targetGen,
                                    text = generationText
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

-- ============== ПОИСК ВОРА С ЛУЧШИМ BRAINROT (FALLBACK) ==============
-- Ищем brainrot который УЖЕ несёт другой игрок (модель в workspace с WeldConstraint)
-- Возвращает данные о воре ТОЛЬКО если он несёт ЛУЧШИЙ brainrot (самый ценный на сервере!)

-- DEBUG: Счётчик для периодического вывода
local debugCounter = 0
local DEBUG_INTERVAL = 2 -- Выводить каждые 2 вызова (чаще для отладки)

-- Детальное логирование всех моделей в workspace для отладки
local function logWorkspaceModels()
    local models = {}
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") then
            local hasAnimalOverhead = obj:FindFirstChild("AnimalOverhead", true) ~= nil
            local hasFakeRootPart = obj:FindFirstChild("FakeRootPart") ~= nil
            local hasRootPart = obj:FindFirstChild("RootPart") ~= nil
            
            -- Ищем любые Weld/WeldConstraint/Motor6D
            local welds = {}
            for _, desc in ipairs(obj:GetDescendants()) do
                if desc:IsA("WeldConstraint") or desc:IsA("Weld") or desc:IsA("Motor6D") then
                    local p0Name = desc.Part0 and desc.Part0.Name or "nil"
                    local p1Name = desc.Part1 and desc.Part1.Name or "nil"
                    local p0Parent = desc.Part0 and desc.Part0.Parent and desc.Part0.Parent.Name or "nil"
                    local p1Parent = desc.Part1 and desc.Part1.Parent and desc.Part1.Parent.Name or "nil"
                    table.insert(welds, desc.ClassName .. "(" .. p0Name .. "[" .. p0Parent .. "]->" .. p1Name .. "[" .. p1Parent .. "])")
                end
            end
            
            -- Проверяем AssemblyRootPart (альтернативный способ детекции носителя)
            local assemblyRoot = nil
            local fakeRoot = obj:FindFirstChild("FakeRootPart")
            local rootPart = obj:FindFirstChild("RootPart")
            
            if fakeRoot and fakeRoot:IsA("BasePart") then
                local ar = fakeRoot.AssemblyRootPart
                if ar and ar ~= fakeRoot and ar ~= rootPart then
                    local arParent = ar.Parent and ar.Parent.Name or "nil"
                    assemblyRoot = ar.Name .. "[" .. arParent .. "]"
                end
            end
            
            if hasAnimalOverhead or hasFakeRootPart then
                table.insert(models, {
                    name = obj.Name,
                    hasOverhead = hasAnimalOverhead,
                    hasFakeRoot = hasFakeRootPart,
                    hasRoot = hasRootPart,
                    welds = welds,
                    assemblyRoot = assemblyRoot
                })
            end
        end
    end
    return models
end

local function findAnyCarriedBrainrotThief()
    local bestThief = nil
    local bestCarriedValue = 0
    
    debugCounter = debugCounter + 1
    local shouldLog = (debugCounter % DEBUG_INTERVAL == 1)
    
    -- Собираем данные для логирования
    local logData = {
        myPlot = "unknown",
        myBestName = "none",
        myBestValue = 0,
        bestPodiumName = "none",
        bestPodiumValue = 0,
        carriedList = {},
        thiefName = "none",
        thiefBrainrot = "none",
        thiefValue = 0,
        isFriend = false,
        carryTime = 0,
        reason = "No thief detected"
    }
    
    -- Находим мой плот
    local myPlot = findPlayerPlot()
    logData.myPlot = myPlot and myPlot.Name or "NOT FOUND"
    
    -- Находим лучший brainrot на МОЁМ подиуме
    local myBestBrainrot = nil
    if myPlot then
        local animalPodiums = myPlot:FindFirstChild("AnimalPodiums")
        if animalPodiums then
            for _, podium in ipairs(animalPodiums:GetChildren()) do
                local base = podium:FindFirstChild("Base")
                if not base then continue end
                local spawn = base:FindFirstChild("Spawn")
                if not spawn then continue end
                
                -- Ищем AnimalOverhead рекурсивно
                local animalOverhead = spawn:FindFirstChild("AnimalOverhead", true)
                if animalOverhead then
                    local generationLabel = animalOverhead:FindFirstChild("Generation")
                    if generationLabel and generationLabel:IsA("TextLabel") then
                        local genText = generationLabel.Text
                        if genText and genText:find("/s") then
                            local value = parsePrice(genText)
                            if value > logData.myBestValue then
                                logData.myBestValue = value
                                -- Пытаемся получить имя через ProximityPrompt
                                local promptAttach = spawn:FindFirstChild("PromptAttachment")
                                if promptAttach then
                                    for _, desc in ipairs(promptAttach:GetDescendants()) do
                                        if desc:IsA("ProximityPrompt") and desc.ObjectText then
                                            logData.myBestName = desc.ObjectText
                                            myBestBrainrot = {name = desc.ObjectText, value = value}
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- ВАЖНО: Сначала находим ценность лучшего brainrot на ВСЕХ подиумах
    local bestOnPodium = findBestBrainrot(true)
    local bestPodiumValue = bestOnPodium and bestOnPodium.value or 0
    logData.bestPodiumName = bestOnPodium and bestOnPodium.name or "none"
    logData.bestPodiumValue = bestPodiumValue
    
    -- Ищем brainrot модели в workspace (не в Plots!)
    for _, obj in ipairs(workspace:GetChildren()) do
        -- Пропускаем если это не Model
        if not obj:IsA("Model") then continue end
        
        -- КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: WeldConstraint находится в RootPart, НЕ в FakeRootPart!
        -- Проверяем наличие FakeRootPart как признак brainrot модели
        local fakeRootPart = obj:FindFirstChild("FakeRootPart")
        if not fakeRootPart then continue end
        
        -- Ищем кто несёт этот brainrot
        local carrierHRP = nil
        local carrierCharacter = nil
        local carrierPlayer = nil
        
        -- МЕТОД 1: WeldConstraint в RootPart (основной метод)
        local rootPart = obj:FindFirstChild("RootPart")
        if rootPart then
            local weldConstraint = rootPart:FindFirstChild("WeldConstraint")
            if weldConstraint then
                -- Part0 = HumanoidRootPart игрока который несёт
                if weldConstraint.Part0 and weldConstraint.Part0:IsA("BasePart") and weldConstraint.Part0.Name == "HumanoidRootPart" then
                    carrierHRP = weldConstraint.Part0
                    carrierCharacter = carrierHRP.Parent
                    if carrierCharacter then
                        carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
                    end
                elseif weldConstraint.Part1 and weldConstraint.Part1:IsA("BasePart") and weldConstraint.Part1.Name == "HumanoidRootPart" then
                    carrierHRP = weldConstraint.Part1
                    carrierCharacter = carrierHRP.Parent
                    if carrierCharacter then
                        carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
                    end
                end
            end
        end
        
        -- МЕТОД 2: AssemblyRootPart (резервный метод через физику)
        if not carrierPlayer and fakeRootPart:IsA("BasePart") then
            local assemblyRoot = fakeRootPart.AssemblyRootPart
            if assemblyRoot and assemblyRoot ~= fakeRootPart and assemblyRoot.Name == "HumanoidRootPart" then
                carrierHRP = assemblyRoot
                carrierCharacter = carrierHRP.Parent
                if carrierCharacter then
                    carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
                end
            end
        end
        
        -- Проверяем что нашли игрока и это не мы
        if not carrierPlayer then continue end
        if carrierPlayer == LocalPlayer then continue end
        
        -- Пытаемся определить ценность brainrot используя новую функцию
        local brainrotValue, brainrotName = calculateBrainrotGeneration(obj)
        local generationText = ""
        
        if brainrotValue > 0 then
            generationText = formatGenerationNumber(brainrotValue) .. "/s"
        else
            -- Fallback на AnimalOverhead в carried модели
            local animalOverhead = obj:FindFirstChild("AnimalOverhead", true)
            if animalOverhead then
                local generationLabel = animalOverhead:FindFirstChild("Generation")
                if generationLabel and generationLabel:IsA("TextLabel") then
                    local genText = generationLabel.Text
                    if genText and genText:find("/s") then
                        brainrotValue = parsePrice(genText)
                        generationText = genText
                    end
                end
            end
        end
        
        -- Добавляем в лог список всех carried
        table.insert(logData.carriedList, {
            brainrotName = obj.Name,
            carrierName = carrierPlayer.Name,
            value = brainrotValue,
            text = generationText,
            isFriend = IsInFriendList(carrierPlayer)
        })
        
        -- Собираем информацию о ВСЕХ несомых brainrot
        -- Выбираем самый ценный из тех что несут (потом проверим лучший ли он на сервере)
        if brainrotValue > bestCarriedValue then
            bestCarriedValue = brainrotValue
            bestThief = {
                player = carrierPlayer,
                character = carrierCharacter,
                hrp = carrierHRP,
                brainrotModel = obj,
                rootPart = fakeRootPart,
                name = obj.Name,
                value = brainrotValue,
                text = generationText ~= "" and generationText or "???"
            }
        end
    end
    
    -- КРИТИЧЕСКАЯ ПРОВЕРКА: Детектим только если несут ЛУЧШИЙ brainrot на сервере!
    -- Сравниваем с лучшим на подиумах - если несомый brainrot >= лучшего на подиуме, то это вор лучшего
    if bestThief then
        local isMyBrainrot = myBestBrainrot and bestThief.name == myBestBrainrot.name
        local isBestOnServer = bestThief.value >= bestPodiumValue -- Несомый brainrot самый ценный на сервере
        
        if isMyBrainrot then
            logData.reason = "Stealing MY brainrot: " .. bestThief.name .. " (value " .. tostring(bestThief.value) .. ")"
        elseif isBestOnServer then
            logData.reason = "Stealing BEST brainrot on server: " .. bestThief.name .. " (value " .. tostring(bestThief.value) .. " >= podium best " .. tostring(bestPodiumValue) .. ")"
        else
            -- Это НЕ лучший brainrot на сервере - игнорируем
            logData.reason = "Ignoring: " .. bestThief.name .. " (value " .. tostring(bestThief.value) .. ") is NOT the best. Best on podium: " .. tostring(bestPodiumValue)
            bestThief = nil -- Сбрасываем - это не вор лучшего!
        end
    end
    
    -- Заполняем данные о найденном воре
    if bestThief then
        logData.thiefName = bestThief.player.Name
        logData.thiefBrainrot = bestThief.name
        logData.thiefValue = bestThief.value
        logData.isFriend = IsInFriendList(bestThief.player)
        logData.carryTime = thiefCarryDuration or 0
    end
    
    -- Логируем состояние
    if shouldLog then
        logDetectionState(logData)
    end
    
    return bestThief
end

-- Главная функция поиска вора (с кэшированием)
-- Ищет игрока который несёт ЛУЧШИЙ brainrot на сервере
local function findBrainrotThief(forceRefresh)
    local now = tick()
    
    -- Используем кэш если не истёк и вор ещё валиден
    if not forceRefresh and cachedThief and (now - lastThiefSearch) < THIEF_CACHE_TIME then
        -- Быстрая проверка валидности кэша
        if cachedThief.brainrotModel and cachedThief.brainrotModel.Parent and
           cachedThief.player and cachedThief.player.Character then
            return cachedThief
        end
    end
    
    local foundThief = nil
    
    -- ОСНОВНОЙ МЕТОД: Через Synchronizer находим лучший brainrot и ищем вора
    local syncThief = findBestBrainrotThiefViaSync()
    if syncThief then
        cachedThief = syncThief
        lastThiefSearch = now
        return syncThief
    end
    
    -- FALLBACK: Старая логика поиска
    -- Собираем данные для логирования
    local logData = {
        myPlot = "unknown",
        myBestName = "none",
        myBestValue = 0,
        bestPodiumName = "none",
        bestPodiumValue = 0,
        targetName = lastBestBrainrotName or "none",
        carriedList = {},
        thiefName = "none",
        thiefBrainrot = "none", 
        thiefValue = 0,
        isFriend = false,
        carryTime = thiefCarryDuration or 0,
        reason = "No thief detected",
        searchMethod = "none"
    }
    
    -- Находим мой плот
    local myPlot = findPlayerPlot()
    logData.myPlot = myPlot and myPlot.Name or "NOT FOUND"
    
    -- Находим лучший brainrot на ВСЕХ подиумах
    local bestOnPodium = findBestBrainrot(true)
    local bestPodiumValue = bestOnPodium and bestOnPodium.value or 0
    local bestPodiumName = bestOnPodium and bestOnPodium.name or "none"
    logData.bestPodiumName = bestPodiumName
    logData.bestPodiumValue = bestPodiumValue
    
    local foundThief = nil
    
    -- СПОСОБ 1: Ищем brainrot со статусом "Stolen" в Plot и в workspace
    -- Структура: Plots/[GUID]/[BrainrotName]/FakeRootPart/Bone/.../AnimalOverhead/Stolen
    -- Когда кто-то несёт brainrot, на модели появляется label "Stolen" с Visible=true
    local stolenBrainrots = {}
    local plotsFolder = workspace:FindFirstChild("Plots")
    local plotsScanned = 0
    local modelsScanned = 0
    local animalOverheadsFound = 0
    local stolenLabelsFound = 0
    
    -- Функция для проверки модели на статус Stolen
    local function checkModelForStolen(child, parentLocation)
        if not child:IsA("Model") then return nil end
        modelsScanned = modelsScanned + 1
        
        -- Ищем AnimalOverhead рекурсивно внутри модели
        local animalOverhead = child:FindFirstChild("AnimalOverhead", true)
        if not animalOverhead then return nil end
        animalOverheadsFound = animalOverheadsFound + 1
        
        -- Проверяем статус "Stolen"
        local stolenLabel = animalOverhead:FindFirstChild("Stolen")
        if not stolenLabel then return nil end
        
        -- Считаем найденные Stolen labels
        stolenLabelsFound = stolenLabelsFound + 1
        
        local isVisible = stolenLabel.Visible
        local stolenText = ""
        
        if stolenLabel:IsA("TextLabel") then
            stolenText = string.lower(tostring(stolenLabel.Text or ""))
        elseif stolenLabel:IsA("Frame") or stolenLabel:IsA("TextButton") then
            -- Иногда Stolen может быть другим типом элемента
            isVisible = stolenLabel.Visible
            stolenText = "stolen" -- Если элемент видим, считаем что статус активен
        end
        
        if not isVisible then return nil end
        if stolenText ~= "stolen" and stolenText ~= "" then return nil end
        
        -- Это brainrot в статусе Stolen! Получаем его ценность
        local generationLabel = animalOverhead:FindFirstChild("Generation")
        if not generationLabel or not generationLabel:IsA("TextLabel") then return nil end
        
        local generationText = generationLabel.Text
        if not generationText then return nil end
        
        -- Пробуем парсить ценность даже если нет /s (иногда формат отличается)
        local brainrotValue = parsePrice(generationText)
        if brainrotValue <= 0 then return nil end
        
        -- Позиция для поиска вора
        local fakeRootPart = child:FindFirstChild("FakeRootPart") or child:FindFirstChild("RootPart")
        local position = fakeRootPart and fakeRootPart.Position or child:GetPivot().Position
        
        return {
            name = child.Name,
            value = brainrotValue,
            text = generationText,
            model = child,
            position = position,
            location = parentLocation
        }
    end
    
    -- Ищем в Plots
    if plotsFolder then
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            plotsScanned = plotsScanned + 1
            
            -- Brainrot модели находятся прямо в Plot (не в AnimalPodiums!)
            for _, child in ipairs(plot:GetChildren()) do
                local stolen = checkModelForStolen(child, "Plots/" .. plot.Name)
                if stolen then
                    table.insert(stolenBrainrots, stolen)
                end
            end
        end
    end
    
    -- Также ищем в корне workspace (модели могут быть и там)
    for _, child in ipairs(workspace:GetChildren()) do
        local stolen = checkModelForStolen(child, "workspace")
        if stolen then
            table.insert(stolenBrainrots, stolen)
        end
    end
    
    -- Статистика сканирования
    logData.scanStats = "Plots:" .. plotsScanned .. " Models:" .. modelsScanned .. " Overheads:" .. animalOverheadsFound .. " StolenLabels:" .. stolenLabelsFound .. " Stolen:" .. #stolenBrainrots
    
    -- Находим лучший украденный brainrot (со статусом STOLEN на подиуме)
    -- Выбираем самый ценный - потом проверим лучший ли он на сервере
    local bestStolen = nil
    for _, stolen in ipairs(stolenBrainrots) do
        -- Выбираем самый ценный украденный brainrot
        if not bestStolen or stolen.value > bestStolen.value then
            bestStolen = stolen
        end
        
        table.insert(logData.carriedList, {
            brainrotName = stolen.name,
            carrierName = "BEING STOLEN (on podium)",
            value = stolen.value,
            text = stolen.text,
            isFriend = false
        })
    end
    
    -- ВАЖНО: Проверяем что украденный brainrot - это ЛУЧШИЙ на сервере!
    if bestStolen then
        local isBestOnServer = bestStolen.value >= bestPodiumValue
        if not isBestOnServer then
            -- Это не лучший на сервере - игнорируем
            logData.reason = "Ignoring stolen: " .. bestStolen.name .. " (value " .. tostring(bestStolen.value) .. ") is NOT the best. Best on podium: " .. tostring(bestPodiumValue)
            bestStolen = nil
        end
    end
    
    -- НОВЫЙ МЕТОД: Напрямую ищем ВСЕ модели в workspace которые кто-то несёт
    -- Это работает даже если на подиуме нет статуса "Stolen"
    local carriedModelsInWorkspace = {}
    
    for _, obj in ipairs(workspace:GetChildren()) do
        if not obj:IsA("Model") then continue end
        
        -- Проверяем есть ли FakeRootPart (признак brainrot модели)
        local fakeRootPart = obj:FindFirstChild("FakeRootPart")
        if not fakeRootPart then continue end
        
        -- Проверяем есть ли AnimalOverhead (признак brainrot)
        local animalOverhead = obj:FindFirstChild("AnimalOverhead", true)
        if not animalOverhead then continue end
        
        -- Ищем кто несёт этот brainrot
        local carrierPlayer = nil
        local carrierCharacter = nil
        local carrierHRP = nil
        
        -- МЕТОД 1: WeldConstraint в RootPart (основной метод)
        local rootPart = obj:FindFirstChild("RootPart")
        if rootPart then
            local weldConstraint = rootPart:FindFirstChild("WeldConstraint")
            if weldConstraint then
                -- Проверяем Part0 (обычно это HumanoidRootPart игрока)
                if weldConstraint.Part0 and weldConstraint.Part0.Name == "HumanoidRootPart" then
                    local char = weldConstraint.Part0.Parent
                    if char then
                        local player = Players:GetPlayerFromCharacter(char)
                        if player and player ~= LocalPlayer then
                            carrierPlayer = player
                            carrierCharacter = char
                            carrierHRP = weldConstraint.Part0
                        end
                    end
                end
                -- Проверяем Part1 (на всякий случай)
                if not carrierPlayer and weldConstraint.Part1 and weldConstraint.Part1.Name == "HumanoidRootPart" then
                    local char = weldConstraint.Part1.Parent
                    if char then
                        local player = Players:GetPlayerFromCharacter(char)
                        if player and player ~= LocalPlayer then
                            carrierPlayer = player
                            carrierCharacter = char
                            carrierHRP = weldConstraint.Part1
                        end
                    end
                end
            end
        end
        
        -- МЕТОД 2: AssemblyRootPart (резервный метод через физику)
        if not carrierPlayer and fakeRootPart:IsA("BasePart") then
            local assemblyRoot = fakeRootPart.AssemblyRootPart
            if assemblyRoot and assemblyRoot ~= fakeRootPart and assemblyRoot.Name == "HumanoidRootPart" then
                local char = assemblyRoot.Parent
                if char then
                    local player = Players:GetPlayerFromCharacter(char)
                    if player and player ~= LocalPlayer then
                        carrierPlayer = player
                        carrierCharacter = char
                        carrierHRP = assemblyRoot
                    end
                end
            end
        end
        
        -- МЕТОД 3: Рекурсивный поиск WeldConstraint/Weld/Motor6D (запасной)
        if not carrierPlayer then
            for _, desc in ipairs(obj:GetDescendants()) do
                if desc:IsA("WeldConstraint") or desc:IsA("Weld") or desc:IsA("Motor6D") then
                    -- Проверяем Part0
                    if desc.Part0 and desc.Part0.Name == "HumanoidRootPart" then
                        local char = desc.Part0.Parent
                        if char then
                            local player = Players:GetPlayerFromCharacter(char)
                            if player and player ~= LocalPlayer then
                                carrierPlayer = player
                                carrierCharacter = char
                                carrierHRP = desc.Part0
                                break
                            end
                        end
                    end
                    -- Проверяем Part1
                    if desc.Part1 and desc.Part1.Name == "HumanoidRootPart" then
                        local char = desc.Part1.Parent
                        if char then
                            local player = Players:GetPlayerFromCharacter(char)
                            if player and player ~= LocalPlayer then
                                carrierPlayer = player
                                carrierCharacter = char
                                carrierHRP = desc.Part1
                                break
                            end
                        end
                    end
                end
            end
        end
        
        if carrierPlayer then
            -- Получаем ценность brainrot используя новую функцию (ищет реальное значение из GUI)
            local brainrotValue, brainrotName = calculateBrainrotGeneration(obj)
            local generationText = ""
            
            -- Если calculateBrainrotGeneration вернул значение, форматируем текст
            if brainrotValue > 0 then
                generationText = formatGenerationNumber(brainrotValue) .. "/s"
            else
                -- Fallback на AnimalOverhead в модели (старый метод)
                local generationLabel = animalOverhead:FindFirstChild("Generation")
                if generationLabel and generationLabel:IsA("TextLabel") then
                    generationText = generationLabel.Text or ""
                    if generationText:find("/s") then
                        brainrotValue = parsePrice(generationText)
                    end
                end
            end
            
            table.insert(carriedModelsInWorkspace, {
                model = obj,
                name = obj.Name,
                value = brainrotValue,
                text = generationText,
                player = carrierPlayer,
                character = carrierCharacter,
                hrp = carrierHRP
            })
            
            table.insert(logData.carriedList, {
                brainrotName = obj.Name,
                carrierName = carrierPlayer.Name .. " (CARRYING)",
                value = brainrotValue,
                text = generationText,
                isFriend = IsInFriendList(carrierPlayer)
            })
        end
    end
    
    -- Выбираем лучший НЕСОМЫЙ brainrot из workspace
    local bestCarried = nil
    for _, carried in ipairs(carriedModelsInWorkspace) do
        if not bestCarried or carried.value > bestCarried.value then
            bestCarried = carried
        end
    end
    
    -- КРИТИЧЕСКАЯ ПРОВЕРКА: Детектим ТОЛЬКО если несут ЛУЧШИЙ brainrot на сервере!
    -- Сравниваем несомый brainrot с лучшим на подиумах
    if bestCarried then
        local isBestOnServer = bestCarried.value >= bestPodiumValue
        
        if isBestOnServer then
            foundThief = {
                player = bestCarried.player,
                character = bestCarried.character,
                hrp = bestCarried.hrp,
                brainrotModel = bestCarried.model,
                rootPart = bestCarried.model:FindFirstChild("FakeRootPart") or bestCarried.model:FindFirstChild("RootPart"),
                name = bestCarried.name,
                value = bestCarried.value,
                text = bestCarried.text
            }
            logData.searchMethod = "workspace_carried"
            logData.reason = "Found player CARRYING BEST brainrot: " .. bestCarried.name .. " (value " .. tostring(bestCarried.value) .. " >= podium best " .. tostring(bestPodiumValue) .. ") by " .. bestCarried.player.Name
        else
            logData.searchMethod = "workspace_carried_ignored"
            logData.reason = "Ignoring carried: " .. bestCarried.name .. " (value " .. tostring(bestCarried.value) .. ") is NOT the best. Best on podium: " .. logData.bestPodiumName .. " = " .. tostring(bestPodiumValue)
        end
    end
    
    -- Если НЕ нашли вора через workspace И нашли украденный на подиуме - ищем кто его несёт
    if not foundThief and bestStolen then
        local thiefPlayer = nil
        local thiefCharacter = nil
        local thiefHRP = nil
        local carriedModel = nil
        
        -- УЛУЧШЕННЫЙ ПОИСК: Ищем во всех местах где может быть модель
        local searchLocations = {workspace}
        if plotsFolder then
            for _, plot in ipairs(plotsFolder:GetChildren()) do
                table.insert(searchLocations, plot)
            end
        end
        
        for _, location in ipairs(searchLocations) do
            if thiefPlayer then break end -- Уже нашли
            
            for _, obj in ipairs(location:GetChildren()) do
                if not obj:IsA("Model") then continue end
                if obj.Name ~= bestStolen.name then continue end
                
                -- Проверяем ВСЕ варианты Part с WeldConstraint
                local possibleRoots = {
                    obj:FindFirstChild("RootPart"),
                    obj:FindFirstChild("FakeRootPart"),
                    obj:FindFirstChild("HumanoidRootPart")
                }
                
                local weldConstraint = nil
                local rootPart = nil
                
                for _, part in ipairs(possibleRoots) do
                    if part then
                        local weld = part:FindFirstChild("WeldConstraint")
                        if weld then
                            weldConstraint = weld
                            rootPart = part
                            break
                        end
                    end
                end
                
                -- Альтернативный поиск: ищем WeldConstraint рекурсивно
                if not weldConstraint then
                    for _, desc in ipairs(obj:GetDescendants()) do
                        if desc:IsA("WeldConstraint") then
                            weldConstraint = desc
                            rootPart = desc.Parent
                            break
                        end
                    end
                end
                
                -- АЛЬТЕРНАТИВА: Если WeldConstraint не найден - пробуем AssemblyRootPart
                local carrierHRP = nil
                
                if weldConstraint then
                    -- Part0 или Part1 = HumanoidRootPart игрока который несёт
                    if weldConstraint.Part0 and weldConstraint.Part0.Name == "HumanoidRootPart" then
                        carrierHRP = weldConstraint.Part0
                    elseif weldConstraint.Part1 and weldConstraint.Part1.Name == "HumanoidRootPart" then
                        carrierHRP = weldConstraint.Part1
                    end
                end
                
                -- Пробуем через AssemblyRootPart если WeldConstraint не помог
                if not carrierHRP then
                    local fakeRoot = obj:FindFirstChild("FakeRootPart")
                    if fakeRoot and fakeRoot:IsA("BasePart") then
                        local assemblyRoot = fakeRoot.AssemblyRootPart
                        if assemblyRoot and assemblyRoot ~= fakeRoot and assemblyRoot.Name == "HumanoidRootPart" then
                            carrierHRP = assemblyRoot
                        end
                    end
                end
                
                if not carrierHRP or not carrierHRP:IsA("BasePart") then continue end
                
                -- Находим персонаж и игрока
                local carrierCharacter = carrierHRP.Parent
                if not carrierCharacter then continue end
                
                local carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
                if not carrierPlayer then continue end
                
                -- Пропускаем себя
                if carrierPlayer == LocalPlayer then continue end
                
                -- Нашли вора!
                thiefPlayer = carrierPlayer
                thiefCharacter = carrierCharacter
                thiefHRP = carrierHRP
                carriedModel = obj
                break
            end
        end
        
        -- РЕЗЕРВНЫЙ МЕТОД: Если не нашли через WeldConstraint, ищем ближайшего игрока к украденной модели
        if not thiefPlayer and bestStolen.position then
            local closestPlayer = nil
            local closestDistance = 15 -- Максимальная дистанция для детекции
            
            for _, player in ipairs(Players:GetPlayers()) do
                if player == LocalPlayer then continue end
                
                local character = player.Character
                if not character then continue end
                
                local hrp = character:FindFirstChild("HumanoidRootPart")
                if not hrp then continue end
                
                local distance = (hrp.Position - bestStolen.position).Magnitude
                if distance < closestDistance then
                    closestDistance = distance
                    closestPlayer = player
                end
            end
            
            if closestPlayer then
                thiefPlayer = closestPlayer
                thiefCharacter = closestPlayer.Character
                thiefHRP = thiefCharacter:FindFirstChild("HumanoidRootPart")
                carriedModel = bestStolen.model
                logData.searchMethod = "proximity"
            end
        end
        
        if thiefPlayer then
            foundThief = {
                player = thiefPlayer,
                character = thiefCharacter,
                hrp = thiefHRP,
                brainrotModel = carriedModel,
                rootPart = carriedModel and (carriedModel:FindFirstChild("RootPart") or carriedModel:FindFirstChild("FakeRootPart")),
                name = bestStolen.name,
                value = bestStolen.value,
                text = bestStolen.text
            }
            logData.searchMethod = logData.searchMethod or "weldconstraint"
            logData.reason = "Found CARRIER of BEST brainrot: " .. bestStolen.name .. " (value " .. tostring(bestStolen.value) .. "), carried by: " .. thiefPlayer.Name .. " (method: " .. logData.searchMethod .. ")"
        else
            logData.reason = "BEST brainrot " .. bestStolen.name .. " is being stolen but carrier not found via WeldConstraint or proximity"
        end
    else
        logData.reason = "No stolen brainrot >= best podium value (" .. tostring(bestPodiumValue) .. ")"
    end
    
    -- Заполняем данные о найденном воре
    if foundThief then
        logData.thiefName = foundThief.player.Name
        logData.thiefBrainrot = foundThief.name
        logData.thiefValue = foundThief.value
        logData.isFriend = IsInFriendList(foundThief.player)
        lastBestBrainrotName = foundThief.name
    end
    
    -- Логируем состояние
    logDetectionState(logData)
    
    cachedThief = foundThief
    lastThiefSearch = now
    return foundThief
end

-- Обновить время переноски (вызывается из главного цикла)
local function updateThiefCarryTime(thief)
    if not thief or not thief.player then
        -- Нет вора - сбрасываем таймер
        thiefCarryStartTime = 0
        lastThiefPlayer = nil
        thiefCarryDuration = 0
        return 0
    end
    
    local now = tick()
    
    -- Проверяем это тот же вор или новый
    if lastThiefPlayer ~= thief.player then
        -- Новый вор - сбрасываем таймер
        thiefCarryStartTime = now
        lastThiefPlayer = thief.player
        thiefCarryDuration = 0
    else
        -- Тот же вор - обновляем время
        thiefCarryDuration = now - thiefCarryStartTime
    end
    
    return thiefCarryDuration
end

-- Обновить время переноски для вора моей базы (отдельная система)
local function updateMyBaseThiefCarryTime(thief)
    if not thief or not thief.player then
        -- Нет вора моей базы - сбрасываем таймер
        myBaseThiefCarryStartTime = 0
        lastMyBaseThiefPlayer = nil
        myBaseThiefCarryDuration = 0
        return 0
    end
    
    local now = tick()
    
    -- Проверяем это тот же вор или новый
    if lastMyBaseThiefPlayer ~= thief.player then
        -- Новый вор - сбрасываем таймер
        myBaseThiefCarryStartTime = now
        lastMyBaseThiefPlayer = thief.player
        myBaseThiefCarryDuration = 0
    else
        -- Тот же вор - обновляем время
        myBaseThiefCarryDuration = now - myBaseThiefCarryStartTime
    end
    
    return myBaseThiefCarryDuration
end

-- Проверить можно ли применять команды к вору (прошло достаточно времени)
-- Для вора моей базы - ВСЕГДА можно (без задержки)
local function canApplyCommandsToThief(isMyBaseThief)
    if isMyBaseThief then
        return true -- Вор моей базы - применяем команды СРАЗУ!
    end
    return thiefCarryDuration >= CONFIG.THIEF_CARRY_DELAY
end

-- ============== ESP СИСТЕМА (компактный индикатор - не конфликтует с autosteal) ==============

local thiefHighlight = nil
local thiefBillboard = nil
local myBaseThiefHighlight = nil -- Отдельный highlight для вора моей базы
local myBaseThiefBillboard = nil -- Отдельный billboard для вора моей базы
local rainbowHue = 0
local RAINBOW_SPEED = 0.15

local function clearThiefESP()
    if thiefHighlight then
        pcall(function() thiefHighlight:Destroy() end)
        thiefHighlight = nil
    end
    if thiefBillboard then
        pcall(function() thiefBillboard:Destroy() end)
        thiefBillboard = nil
    end
end

local function clearMyBaseThiefESP()
    if myBaseThiefHighlight then
        pcall(function() myBaseThiefHighlight:Destroy() end)
        myBaseThiefHighlight = nil
    end
    if myBaseThiefBillboard then
        pcall(function() myBaseThiefBillboard:Destroy() end)
        myBaseThiefBillboard = nil
    end
end

-- Обновляет компактный ESP - только Highlight + маленький таймер сверху
-- Табличка с именем/brainrot уже отображается в autosteal
local function updateThiefESP()
    if not CONFIG.ESP_ENABLED then
        clearThiefESP()
        return
    end
    
    local thief = currentThief
    
    if not thief or not thief.character or not thief.hrp then
        clearThiefESP()
        return
    end
    
    local isFriend = IsInFriendList(thief.player)
    
    -- Цвета: оранжевый для вора, зелёный для друга
    local highlightFillColor = isFriend and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 0)
    local highlightOutlineColor = isFriend and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 0, 0)
    
    -- Highlight на персонаже (ЗАЩИТА: рандомное имя + gethui + pcall)
    if not thiefHighlight or not thiefHighlight.Parent then
        clearThiefESP()
        
        thiefHighlight = Instance.new("Highlight")
        thiefHighlight.Name = generateRandomName() -- ЗАЩИТА
        thiefHighlight.Adornee = thief.character
        thiefHighlight.FillColor = highlightFillColor
        thiefHighlight.FillTransparency = 0.5
        thiefHighlight.OutlineColor = highlightOutlineColor
        thiefHighlight.OutlineTransparency = 0
        pcall(function() thiefHighlight.Parent = getProtectedGui() end) -- ЗАЩИТА: gethui + pcall
    else
        pcall(function()
            thiefHighlight.FillColor = highlightFillColor
            thiefHighlight.OutlineColor = highlightOutlineColor
            thiefHighlight.Adornee = thief.character
        end)
    end
    
    -- Компактный индикатор таймера (маленький, выше таблички autosteal)
    -- ЗАЩИТА: рандомное имя + gethui
    if not thiefBillboard or not thiefBillboard.Parent then
        if thiefBillboard then
            pcall(function() thiefBillboard:Destroy() end)
        end
        
        thiefBillboard = Instance.new("BillboardGui")
        thiefBillboard.Name = generateRandomName() -- ЗАЩИТА
        thiefBillboard.Adornee = thief.hrp
        thiefBillboard.Size = UDim2.new(0, 80, 0, 24)
        thiefBillboard.StudsOffset = Vector3.new(0, 18, 0) -- Выше таблички autosteal (autosteal на 5)
        thiefBillboard.AlwaysOnTop = true
        pcall(function()
            thiefBillboard:SetAttribute("_isAdminAbuseBillboard", true) -- ЗАЩИТА: атрибут для идентификации
            thiefBillboard.Parent = getProtectedGui() -- ЗАЩИТА: gethui + pcall
        end)
        
        local timerLabel = Instance.new("TextLabel")
        timerLabel.Name = generateRandomName() -- ЗАЩИТА
        timerLabel.Size = UDim2.new(1, 0, 1, 0)
        timerLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        timerLabel.BackgroundTransparency = 0.3
        timerLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
        timerLabel.TextScaled = true
        timerLabel.Font = Enum.Font.GothamBold
        timerLabel.Text = "⏱️ 0.0s"
        pcall(function() timerLabel.Parent = thiefBillboard end)
        
        local corner = Instance.new("UICorner")
        corner.Name = generateRandomName() -- ЗАЩИТА
        corner.CornerRadius = UDim.new(0, 6)
        pcall(function() corner.Parent = timerLabel end)
        
        local stroke = Instance.new("UIStroke")
        stroke.Name = generateRandomName() -- ЗАЩИТА
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(255, 100, 0)
        pcall(function()
            stroke:SetAttribute("_isTimerStroke", true) -- ЗАЩИТА: атрибут для поиска
            stroke.Parent = timerLabel
        end)
    else
        pcall(function() thiefBillboard.Adornee = thief.hrp end)
    end
    
    -- Обновляем таймер (ищем по первому TextLabel дочернему элементу) ЗАЩИТА: pcall
    local timerLabel = nil
    pcall(function() timerLabel = thiefBillboard:FindFirstChildWhichIsA("TextLabel") end)
    if timerLabel then
        pcall(function()
            if isFriend then
                timerLabel.Text = "🛡️ ДРУГ"
                timerLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
                -- Ищем stroke по атрибуту
                for _, child in pairs(timerLabel:GetChildren()) do
                    if child:IsA("UIStroke") and child:GetAttribute("_isTimerStroke") then
                        child.Color = Color3.fromRGB(0, 200, 0)
                        break
                    end
                end
            else
                local timeLeft = CONFIG.THIEF_CARRY_DELAY - thiefCarryDuration
                if timeLeft <= 0 then
                    timerLabel.Text = "⚡ GO!"
                    timerLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                else
                    timerLabel.Text = "⏱️ " .. string.format("%.1f", timeLeft) .. "s"
                    timerLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
                end
                -- Радужная рамка (обновляется в цикле)
            end
        end)
    end
end

-- ============== GUI ==============

local screenGui = nil
local mainFrame = nil
local isMinimized = false
local isDragging = false
local dragStart = nil
local startPos = nil

local function createGUI()
    -- ЗАЩИТА: Получаем родительский контейнер для GUI (gethui)
    local guiParent = getGuiParent()
    
    -- Ждём пока guiParent станет доступен
    local attempts = 0
    while not guiParent and attempts < 50 do
        task.wait(0.1)
        guiParent = getGuiParent()
        attempts = attempts + 1
    end
    
    if not guiParent then
        warn("[AdminAbuse] Не удалось получить GUI контейнер!")
        return nil
    end
    
    -- ЗАЩИТА: Удаляем старый GUI по атрибуту вместо имени
    pcall(function()
        for _, child in pairs(guiParent:GetChildren()) do
            if child:IsA("ScreenGui") and child:GetAttribute("_isAdminAbuseGui") then
                child:Destroy()
            end
        end
    end)
    
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Устанавливаем Parent с retry
    local parentSuccess = false
    for i = 1, 5 do
        local ok = pcall(function()
            screenGui:SetAttribute("_isAdminAbuseGui", true) -- ЗАЩИТА: атрибут для идентификации
            screenGui.Parent = guiParent
        end)
        if ok and screenGui.Parent then
            parentSuccess = true
            break
        end
        task.wait(0.1)
    end
    
    if not parentSuccess then
        warn("[AdminAbuse] Не удалось установить Parent для ScreenGui!")
    end
    
    -- Компактные размеры
    local HEADER_HEIGHT = 22
    local ROW_HEIGHT = 18
    local PADDING = 3
    local WIDTH = 160
    
    mainFrame = Instance.new("Frame")
    mainFrame.Name = generateRandomName() -- ЗАЩИТА
    mainFrame.Size = UDim2.new(0, WIDTH, 0, 180)
    mainFrame.Position = UDim2.new(0, CONFIG.GUI_POSITION_X, 0, CONFIG.GUI_POSITION_Y)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    mainFrame.BorderSizePixel = 0
    pcall(function()
        mainFrame:SetAttribute("_isMainFrame", true) -- ЗАЩИТА: атрибут для поиска
        mainFrame.Parent = screenGui
    end)
    
    local mainCorner = Instance.new("UICorner")
    mainCorner.Name = generateRandomName() -- ЗАЩИТА
    mainCorner.CornerRadius = UDim.new(0, 6)
    pcall(function() mainCorner.Parent = mainFrame end)
    
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Name = generateRandomName() -- ЗАЩИТА
    mainStroke.Color = Color3.fromRGB(255, 100, 0)
    mainStroke.Thickness = 1
    pcall(function() mainStroke.Parent = mainFrame end)
    
    -- Заголовок
    local header = Instance.new("Frame")
    header.Name = generateRandomName() -- ЗАЩИТА
    header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
    header.BackgroundColor3 = Color3.fromRGB(255, 100, 0)
    header.BorderSizePixel = 0
    pcall(function()
        header:SetAttribute("_isHeader", true) -- ЗАЩИТА: атрибут для поиска
        header.Parent = mainFrame
    end)
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.Name = generateRandomName() -- ЗАЩИТА
    headerCorner.CornerRadius = UDim.new(0, 6)
    pcall(function() headerCorner.Parent = header end)
    
    local headerCover = Instance.new("Frame")
    headerCover.Name = generateRandomName() -- ЗАЩИТА
    headerCover.Size = UDim2.new(1, 0, 0.5, 0)
    headerCover.Position = UDim2.new(0, 0, 0.5, 0)
    headerCover.BackgroundColor3 = Color3.fromRGB(255, 100, 0)
    headerCover.BorderSizePixel = 0
    pcall(function() headerCover.Parent = header end)
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = generateRandomName() -- ЗАЩИТА
    titleLabel.Size = UDim2.new(1, -40, 1, 0)
    titleLabel.Position = UDim2.new(0, 5, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "⚡ AdminAbuse"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 11
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    pcall(function() titleLabel.Parent = header end)
    
    -- Кнопка минимизации
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = generateRandomName() -- ЗАЩИТА
    minimizeBtn.Size = UDim2.new(0, 16, 0, 16)
    minimizeBtn.Position = UDim2.new(1, -36, 0.5, -8)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    minimizeBtn.BackgroundTransparency = 0.8
    minimizeBtn.Text = "−"
    minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimizeBtn.TextSize = 14
    minimizeBtn.Font = Enum.Font.GothamBold
    pcall(function() minimizeBtn.Parent = header end)
    
    local minimizeBtnCorner = Instance.new("UICorner")
    minimizeBtnCorner.Name = generateRandomName() -- ЗАЩИТА
    minimizeBtnCorner.CornerRadius = UDim.new(0, 4)
    pcall(function() minimizeBtnCorner.Parent = minimizeBtn end)
    
    -- Кнопка закрытия
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = generateRandomName() -- ЗАЩИТА
    closeBtn.Size = UDim2.new(0, 16, 0, 16)
    closeBtn.Position = UDim2.new(1, -18, 0.5, -8)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.BackgroundTransparency = 0.3
    closeBtn.Text = "×"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 12
    closeBtn.Font = Enum.Font.GothamBold
    pcall(function() closeBtn.Parent = header end)
    
    local closeBtnCorner = Instance.new("UICorner")
    closeBtnCorner.Name = generateRandomName() -- ЗАЩИТА
    closeBtnCorner.CornerRadius = UDim.new(0, 4)
    pcall(function() closeBtnCorner.Parent = closeBtn end)
    
    -- Контейнер контента
    local content = Instance.new("ScrollingFrame")
    content.Name = generateRandomName() -- ЗАЩИТА
    content.Size = UDim2.new(1, -6, 1, -HEADER_HEIGHT - 3)
    content.Position = UDim2.new(0, 3, 0, HEADER_HEIGHT + 2)
    content.BackgroundTransparency = 1
    content.ScrollBarThickness = 2
    content.ScrollBarImageColor3 = Color3.fromRGB(255, 100, 0)
    content.CanvasSize = UDim2.new(0, 0, 0, 300)
    pcall(function()
        content:SetAttribute("_isContent", true) -- ЗАЩИТА: атрибут для поиска
        content.Parent = mainFrame
    end)
    
    local contentLayout = Instance.new("UIListLayout")
    contentLayout.Name = generateRandomName() -- ЗАЩИТА
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Padding = UDim.new(0, 2)
    pcall(function() contentLayout.Parent = content end)
    
    -- Статус вора (компактный)
    local thiefStatus = Instance.new("Frame")
    thiefStatus.Name = generateRandomName() -- ЗАЩИТА
    thiefStatus.Size = UDim2.new(1, 0, 0, 28)
    thiefStatus.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    thiefStatus.LayoutOrder = 1
    pcall(function()
        thiefStatus:SetAttribute("_isThiefStatus", true) -- ЗАЩИТА: атрибут для поиска
        thiefStatus.Parent = content
    end)
    
    local thiefStatusCorner = Instance.new("UICorner")
    thiefStatusCorner.Name = generateRandomName() -- ЗАЩИТА
    thiefStatusCorner.CornerRadius = UDim.new(0, 4)
    pcall(function() thiefStatusCorner.Parent = thiefStatus end)
    
    local thiefLabel = Instance.new("TextLabel")
    thiefLabel.Name = generateRandomName() -- ЗАЩИТА
    thiefLabel.Size = UDim2.new(1, -4, 0.5, 0)
    thiefLabel.Position = UDim2.new(0, 2, 0, 1)
    thiefLabel.BackgroundTransparency = 1
    thiefLabel.Text = "🎯 Нет цели"
    thiefLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
    thiefLabel.TextSize = 9
    thiefLabel.Font = Enum.Font.GothamBold
    thiefLabel.TextXAlignment = Enum.TextXAlignment.Left
    thiefLabel.TextTruncate = Enum.TextTruncate.AtEnd
    pcall(function()
        thiefLabel:SetAttribute("_isThiefLabel", true) -- ЗАЩИТА: атрибут для поиска
        thiefLabel.Parent = thiefStatus
    end)
    
    local brainrotLabel = Instance.new("TextLabel")
    brainrotLabel.Name = generateRandomName() -- ЗАЩИТА
    brainrotLabel.Size = UDim2.new(1, -4, 0.5, 0)
    brainrotLabel.Position = UDim2.new(0, 2, 0.5, 0)
    brainrotLabel.BackgroundTransparency = 1
    brainrotLabel.Text = "🧠 ---"
    brainrotLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    brainrotLabel.TextSize = 8
    brainrotLabel.Font = Enum.Font.Gotham
    brainrotLabel.TextXAlignment = Enum.TextXAlignment.Left
    brainrotLabel.TextTruncate = Enum.TextTruncate.AtEnd
    pcall(function()
        brainrotLabel:SetAttribute("_isBrainrotLabel", true) -- ЗАЩИТА: атрибут для поиска
        brainrotLabel.Parent = thiefStatus
    end)
    
    -- Функция создания компактного переключателя (ЗАЩИТА: рандомные имена + pcall)
    local function createCompactToggle(name, text, layoutOrder, initialState, onToggle)
        local toggleFrame = Instance.new("Frame")
        toggleFrame.Name = generateRandomName() -- ЗАЩИТА
        toggleFrame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
        toggleFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        toggleFrame.LayoutOrder = layoutOrder
        pcall(function()
            toggleFrame:SetAttribute("_toggleName", name) -- ЗАЩИТА: атрибут для идентификации
            toggleFrame.Parent = content
        end)
        
        local toggleCorner = Instance.new("UICorner")
        toggleCorner.Name = generateRandomName() -- ЗАЩИТА
        toggleCorner.CornerRadius = UDim.new(0, 3)
        pcall(function() toggleCorner.Parent = toggleFrame end)
        
        local toggleLabel = Instance.new("TextLabel")
        toggleLabel.Name = generateRandomName() -- ЗАЩИТА
        toggleLabel.Size = UDim2.new(1, -35, 1, 0)
        toggleLabel.Position = UDim2.new(0, 4, 0, 0)
        toggleLabel.BackgroundTransparency = 1
        toggleLabel.Text = text
        toggleLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        toggleLabel.TextSize = 9
        toggleLabel.Font = Enum.Font.Gotham
        toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
        pcall(function() toggleLabel.Parent = toggleFrame end)
        
        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Name = generateRandomName() -- ЗАЩИТА
        toggleBtn.Size = UDim2.new(0, 28, 0, 12)
        toggleBtn.Position = UDim2.new(1, -32, 0.5, -6)
        toggleBtn.BackgroundColor3 = initialState and Color3.fromRGB(0, 180, 80) or Color3.fromRGB(80, 80, 80)
        toggleBtn.Text = initialState and "ON" or "OFF"
        toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        toggleBtn.TextSize = 8
        toggleBtn.Font = Enum.Font.GothamBold
        pcall(function()
            toggleBtn:SetAttribute("_isToggleBtn", true) -- ЗАЩИТА: атрибут для поиска
            toggleBtn.Parent = toggleFrame
        end)
        
        local toggleBtnCorner = Instance.new("UICorner")
        toggleBtnCorner.Name = generateRandomName() -- ЗАЩИТА
        toggleBtnCorner.CornerRadius = UDim.new(0, 3)
        pcall(function() toggleBtnCorner.Parent = toggleBtn end)
        
        toggleBtn.MouseButton1Click:Connect(function()
            local newState = onToggle()
            toggleBtn.BackgroundColor3 = newState and Color3.fromRGB(0, 180, 80) or Color3.fromRGB(80, 80, 80)
            toggleBtn.Text = newState and "ON" or "OFF"
        end)
        
        return toggleFrame, toggleBtn
    end
    
    -- Auto Abuse переключатель
    local _, mainToggleBtn = createCompactToggle("MainToggle", "⚡ Auto", 2, CONFIG.AUTO_ABUSE_ENABLED, function()
        CONFIG.AUTO_ABUSE_ENABLED = not CONFIG.AUTO_ABUSE_ENABLED
        saveConfig()
        return CONFIG.AUTO_ABUSE_ENABLED
    end)
    
    -- ESP переключатель
    createCompactToggle("ESPToggle", "👁 ESP", 3, CONFIG.ESP_ENABLED, function()
        CONFIG.ESP_ENABLED = not CONFIG.ESP_ENABLED
        if not CONFIG.ESP_ENABLED then clearThiefESP() end
        saveConfig()
        return CONFIG.ESP_ENABLED
    end)
    
    -- OFF@start чекбокс (выключать при реинжекте)
    local _, reinjectToggleBtn = createCompactToggle("ReinjectToggle", "🔄 OFF@start", 3.5, CONFIG.DISABLE_ON_REINJECT, function()
        CONFIG.DISABLE_ON_REINJECT = not CONFIG.DISABLE_ON_REINJECT
        saveConfig()
        return CONFIG.DISABLE_ON_REINJECT
    end)
    
    -- AUTO чекбокс (авто-включение при воре базы)
    local _, autoEnableToggleBtn = createCompactToggle("AutoEnableToggle", "🏠 AUTO", 3.7, CONFIG.AUTO_ENABLE_ON_THIEF, function()
        CONFIG.AUTO_ENABLE_ON_THIEF = not CONFIG.AUTO_ENABLE_ON_THIEF
        saveConfig()
        return CONFIG.AUTO_ENABLE_ON_THIEF
    end)
    
    -- Функция для программного обновления toggle GUI (для авто-включения) ЗАЩИТА: pcall
    local function UpdateAdminToggleGUI()
        pcall(function()
            if mainToggleBtn then
                mainToggleBtn.BackgroundColor3 = CONFIG.AUTO_ABUSE_ENABLED and Color3.fromRGB(0, 180, 80) or Color3.fromRGB(80, 80, 80)
                mainToggleBtn.Text = CONFIG.AUTO_ABUSE_ENABLED and "ON" or "OFF"
            end
        end)
    end
    
    -- Экспортируем функцию обновления GUI глобально
    _G.AdminAbuseUpdateToggleGUI = UpdateAdminToggleGUI
    
    -- Разделитель
    local separator = Instance.new("Frame")
    separator.Name = generateRandomName() -- ЗАЩИТА
    separator.Size = UDim2.new(1, -8, 0, 1)
    separator.Position = UDim2.new(0, 4, 0, 0)
    separator.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    separator.BorderSizePixel = 0
    separator.LayoutOrder = 4
    pcall(function() separator.Parent = content end)
    
    -- Создаём компактные команды (ЗАЩИТА: рандомные имена + pcall)
    for i, cmd in ipairs(ADMIN_COMMANDS) do
        local cmdFrame = Instance.new("Frame")
        cmdFrame.Name = generateRandomName() -- ЗАЩИТА
        cmdFrame.Size = UDim2.new(1, 0, 0, 14)
        cmdFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
        cmdFrame.LayoutOrder = 4 + i
        pcall(function()
            cmdFrame:SetAttribute("_cmdId", cmd.id) -- ЗАЩИТА: атрибут для идентификации
            cmdFrame.Parent = content
        end)
        
        local cmdCorner = Instance.new("UICorner")
        cmdCorner.Name = generateRandomName() -- ЗАЩИТА
        cmdCorner.CornerRadius = UDim.new(0, 2)
        pcall(function() cmdCorner.Parent = cmdFrame end)
        
        local cmdLabel = Instance.new("TextLabel")
        cmdLabel.Name = generateRandomName() -- ЗАЩИТА
        cmdLabel.Size = UDim2.new(0.45, 0, 1, 0)
        cmdLabel.Position = UDim2.new(0, 3, 0, 0)
        cmdLabel.BackgroundTransparency = 1
        cmdLabel.Text = cmd.name
        cmdLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
        cmdLabel.TextSize = 8
        cmdLabel.Font = Enum.Font.Gotham
        cmdLabel.TextXAlignment = Enum.TextXAlignment.Left
        pcall(function() cmdLabel.Parent = cmdFrame end)
        
        local cooldownLabel = Instance.new("TextLabel")
        cooldownLabel.Name = generateRandomName() -- ЗАЩИТА
        cooldownLabel.Size = UDim2.new(0.25, 0, 1, 0)
        cooldownLabel.Position = UDim2.new(0.45, 0, 0, 0)
        cooldownLabel.BackgroundTransparency = 1
        cooldownLabel.Text = cmd.cooldown .. "s"
        cooldownLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        cooldownLabel.TextSize = 7
        cooldownLabel.Font = Enum.Font.Gotham
        pcall(function()
            cooldownLabel:SetAttribute("_isCooldownLabel", true) -- ЗАЩИТА: атрибут для поиска
            cooldownLabel.Parent = cmdFrame
        end)
        
        local cmdToggleBtn = Instance.new("TextButton")
        cmdToggleBtn.Name = generateRandomName() -- ЗАЩИТА
        cmdToggleBtn.Size = UDim2.new(0, 22, 0, 10)
        cmdToggleBtn.Position = UDim2.new(1, -26, 0.5, -5)
        cmdToggleBtn.BackgroundColor3 = cmd.enabled and Color3.fromRGB(0, 160, 70) or Color3.fromRGB(70, 70, 70)
        cmdToggleBtn.Text = cmd.enabled and "ON" or "OFF"
        cmdToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        cmdToggleBtn.TextSize = 7
        cmdToggleBtn.Font = Enum.Font.GothamBold
        pcall(function()
            cmdToggleBtn:SetAttribute("_isCmdToggleBtn", true) -- ЗАЩИТА: атрибут для поиска
            cmdToggleBtn.Parent = cmdFrame
        end)
        
        local cmdToggleBtnCorner = Instance.new("UICorner")
        cmdToggleBtnCorner.Name = generateRandomName() -- ЗАЩИТА
        cmdToggleBtnCorner.CornerRadius = UDim.new(0, 2)
        pcall(function() cmdToggleBtnCorner.Parent = cmdToggleBtn end)
        
        cmdToggleBtn.MouseButton1Click:Connect(function()
            pcall(function()
                cmd.enabled = not cmd.enabled
                cmdToggleBtn.BackgroundColor3 = cmd.enabled and Color3.fromRGB(0, 160, 70) or Color3.fromRGB(70, 70, 70)
                cmdToggleBtn.Text = cmd.enabled and "ON" or "OFF"
                saveConfig()
            end)
        end)
    end
    
    -- Обновляем размер Canvas (ЗАЩИТА: pcall)
    task.defer(function()
        pcall(function() content.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 5) end)
    end)
    contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        pcall(function() content.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 5) end)
    end)
    
    -- Drag функционал (ЗАЩИТА: pcall)
    header.InputBegan:Connect(function(input)
        pcall(function()
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDragging = true
                dragStart = input.Position
                startPos = mainFrame.Position
            end
        end)
    end)
    
    header.InputEnded:Connect(function(input)
        pcall(function()
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDragging = false
                CONFIG.GUI_POSITION_X = mainFrame.Position.X.Offset
                CONFIG.GUI_POSITION_Y = mainFrame.Position.Y.Offset
                saveConfig()
            end
        end)
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        pcall(function()
            if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)
    end)
    
    minimizeBtn.MouseButton1Click:Connect(function()
        pcall(function()
            isMinimized = not isMinimized
            CONFIG.GUI_MINIMIZED = isMinimized
            
            if isMinimized then
                mainFrame.Size = UDim2.new(0, WIDTH, 0, HEADER_HEIGHT)
                content.Visible = false
                minimizeBtn.Text = "+"
            else
                mainFrame.Size = UDim2.new(0, WIDTH, 0, 180)
                content.Visible = true
                minimizeBtn.Text = "−"
            end
            saveConfig()
        end)
    end)
    
    closeBtn.MouseButton1Click:Connect(function()
        clearThiefESP()
        pcall(function() screenGui:Destroy() end)
        screenGui = nil
    end)
    
    -- Применяем сохранённое состояние минимизации (ЗАЩИТА: pcall)
    pcall(function()
        if CONFIG.GUI_MINIMIZED then
            isMinimized = true
            mainFrame.Size = UDim2.new(0, WIDTH, 0, HEADER_HEIGHT)
            content.Visible = false
            minimizeBtn.Text = "+"
        end
    end)
    
    return screenGui
end

-- ЗАЩИТА: Функция поиска элементов по атрибутам (с pcall для gethui)
local function findChildByAttribute(parent, attributeName, attributeValue)
    if not parent then return nil end
    local result = nil
    pcall(function()
        for _, child in pairs(parent:GetChildren()) do
            if attributeValue then
                if child:GetAttribute(attributeName) == attributeValue then
                    result = child
                    return
                end
            else
                if child:GetAttribute(attributeName) then
                    result = child
                    return
                end
            end
        end
    end)
    return result
end

-- Обновление GUI статуса (ЗАЩИТА: поиск по атрибутам + pcall)
local function updateGUIStatus()
    if not screenGui or not mainFrame then return end
    
    -- ЗАЩИТА: Ищем content по атрибуту
    local content = findChildByAttribute(mainFrame, "_isContent")
    if not content then return end
    
    -- ЗАЩИТА: Ищем thiefStatus по атрибуту
    local thiefStatus = findChildByAttribute(content, "_isThiefStatus")
    if not thiefStatus then return end
    
    -- ЗАЩИТА: Ищем labels по атрибутам
    local thiefLabel = findChildByAttribute(thiefStatus, "_isThiefLabel")
    local brainrotLabel = findChildByAttribute(thiefStatus, "_isBrainrotLabel")
    
    -- ПРИОРИТЕТ: сначала показываем вора моей базы, потом вора лучшего
    local displayThief = currentMyBaseThief or currentThief
    local isMyBaseThiefDisplay = currentMyBaseThief ~= nil
    local displayCarryDuration = isMyBaseThiefDisplay and myBaseThiefCarryDuration or thiefCarryDuration
    
    -- ЗАЩИТА: Обновляем GUI элементы через pcall
    pcall(function()
        if displayThief and displayThief.player then
            -- Проверяем в Friend List ли вор
            local isFriend = IsInFriendList(displayThief.player)
            local carryTimeText = string.format("%.1f", displayCarryDuration) .. "s"
            
            -- Для вора моей базы - нет задержки
            local waitTimeRemaining = 0
            if not isMyBaseThiefDisplay then
                waitTimeRemaining = math.max(0, CONFIG.THIEF_CARRY_DELAY - displayCarryDuration)
            end
            
            if thiefLabel then
                if isFriend then
                    thiefLabel.Text = "👤 ДРУГ: " .. displayThief.player.Name
                    thiefLabel.TextColor3 = Color3.fromRGB(100, 255, 100) -- Зелёный для друга
                elseif isMyBaseThiefDisplay then
                    -- Вор моей базы - всегда красный (атакуем сразу)
                    thiefLabel.Text = "🏠 МОЯ БАЗА: " .. displayThief.player.Name
                    thiefLabel.TextColor3 = Color3.fromRGB(255, 50, 50) -- Ярко-красный
                else
                    if waitTimeRemaining > 0 then
                        thiefLabel.Text = "🎯 " .. displayThief.player.Name .. " (" .. string.format("%.1f", waitTimeRemaining) .. "s)"
                        thiefLabel.TextColor3 = Color3.fromRGB(255, 200, 100) -- Оранжевый - ждём
                    else
                        thiefLabel.Text = "🎯 ЦЕЛЬ: " .. displayThief.player.Name
                        thiefLabel.TextColor3 = Color3.fromRGB(255, 100, 100) -- Красный - атакуем
                    end
                end
            end
            if brainrotLabel then
                local statusText
                if isFriend then
                    statusText = "🛡️ ЗАЩИЩЁН"
                elseif isMyBaseThiefDisplay then
                    statusText = "⚡ АТАКА!" -- Вор моей базы - без задержки
                else
                    statusText = "⏱️ " .. carryTimeText
                end
                brainrotLabel.Text = "🧠 " .. (displayThief.name or "???") .. " | " .. (displayThief.text or "???") .. " | " .. statusText
            end
        else
            if thiefLabel then
                thiefLabel.Text = "🎯 Цель: Нет вора"
                thiefLabel.TextColor3 = Color3.fromRGB(255, 200, 100) -- Стандартный
            end
            if brainrotLabel then
                brainrotLabel.Text = "🧠 Brainrot: ---"
            end
        end
    end)
    
    -- Обновляем кулдауны команд (ЗАЩИТА: ищем по атрибутам + pcall)
    pcall(function()
        for _, cmd in ipairs(ADMIN_COMMANDS) do
            -- ЗАЩИТА: Ищем cmdFrame по атрибуту _cmdId
            local cmdFrame = nil
            for _, child in pairs(content:GetChildren()) do
                if child:GetAttribute("_cmdId") == cmd.id then
                    cmdFrame = child
                    break
                end
            end
            
            if cmdFrame then
                -- ЗАЩИТА: Ищем cooldownLabel по атрибуту
                local cooldownLabel = findChildByAttribute(cmdFrame, "_isCooldownLabel")
                if cooldownLabel then
                    local remaining = getCommandCooldownRemaining(cmd.id)
                    if remaining > 0 then
                        cooldownLabel.Text = string.format("%.0fs", remaining)
                        cooldownLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                    else
                        cooldownLabel.Text = cmd.cooldown .. "s"
                        cooldownLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
                    end
                end
            end
        end
    end)
end

-- ============== ГЛАВНЫЙ ЦИКЛ ==============

local lastCommandTime = 0
local COMMAND_DELAY = 0.2 -- Минимальная задержка между командами (быстрее)

local function mainLoop()
    while true do
        task.wait(CONFIG.CHECK_INTERVAL)
        
        -- Обновляем Friend List из файла (синхронизация с killaura)
        RefreshFriendList()
        
        -- ВАЖНО: Сначала находим лучший brainrot на подиумах и обновляем lastBestBrainrotName
        -- Это нужно чтобы когда кто-то начнёт его красть, мы знали его имя
        local bestBrainrot = findBestBrainrot()
        if bestBrainrot then
            -- Обновляем lastBestBrainrotName только если:
            -- 1. Ещё не было имени (первый запуск)
            -- 2. Изменился brainrot И нет активного вора
            if not lastBestBrainrotName then
                lastBestBrainrotName = bestBrainrot.name
            elseif lastBestBrainrotName ~= bestBrainrot.name then
                -- Появился новый лучший brainrot
                -- Меняем имя ТОЛЬКО если нет вора (иначе продолжаем отслеживать старого вора)
                if not currentThief then
                    lastBestBrainrotName = bestBrainrot.name
                end
            end
        end
        
        -- ВСЕГДА ищем вора (независимо от ESP) - это основная логика
        local thief = findBrainrotThief()
        currentThief = thief -- Обновляем глобальную переменную для GUI и ESP
        
        -- Обновляем время переноски вора
        local carryTime = updateThiefCarryTime(thief)
        
        -- ПРИОРИТЕТ: Сначала ищем вора МОЕЙ базы (любой brainrot с моего плота)
        local myBaseThief = findMyBaseThief()
        currentMyBaseThief = myBaseThief
        
        -- ═══════════════════════════════════════════════════════════════════════
        -- АВТО-ВКЛЮЧЕНИЕ ПРИ ВОРЕ СВОЕЙ БАЗЫ (не друга)
        -- ═══════════════════════════════════════════════════════════════════════
        if CONFIG.AUTO_ENABLE_ON_THIEF and myBaseThief and myBaseThief.player and not IsInFriendList(myBaseThief.player) then
            -- Вор моей базы обнаружен и он не друг!
            if not CONFIG.AUTO_ABUSE_ENABLED then
                -- Скрипт выключен - включаем автоматически
                WasManuallyDisabled_Admin = true  -- Запоминаем что был выключен
                AutoEnabledForMyBaseThief_Admin = true
                CONFIG.AUTO_ABUSE_ENABLED = true
                LastMyBaseThiefDetected_Admin = myBaseThief.player
                -- Обновляем GUI
                if _G.AdminAbuseUpdateToggleGUI then
                    _G.AdminAbuseUpdateToggleGUI()
                end
            end
        else
            -- Вора моей базы нет (или он друг) или AUTO выключен
            if AutoEnabledForMyBaseThief_Admin and WasManuallyDisabled_Admin then
                -- Мы включили автоматически - выключаем обратно
                CONFIG.AUTO_ABUSE_ENABLED = false
                AutoEnabledForMyBaseThief_Admin = false
                WasManuallyDisabled_Admin = false
                LastMyBaseThiefDetected_Admin = nil
                -- Обновляем GUI
                if _G.AdminAbuseUpdateToggleGUI then
                    _G.AdminAbuseUpdateToggleGUI()
                end
            end
        end
        
        -- Обновляем время переноски для вора моей базы
        local myBaseCarryTime = updateMyBaseThiefCarryTime(myBaseThief)
        
        -- Обновляем ESP (только визуал, использует currentThief)
        updateThiefESP()
        
        -- Обновляем GUI
        updateGUIStatus()
        
        -- ПРИОРИТЕТНАЯ ЛОГИКА АТАКИ:
        -- 1. Вор моей базы (любой brainrot) - ПРИОРИТЕТ, команды СРАЗУ
        -- 2. Вор лучшего brainrot на сервере - задержка 5 сек
        
        if CONFIG.AUTO_ABUSE_ENABLED then
            local now = tick()
            local targetThief = nil
            local isMyBaseThiefTarget = false
            
            -- Приоритет 1: Вор моей базы
            if myBaseThief and myBaseThief.player and not IsInFriendList(myBaseThief.player) then
                targetThief = myBaseThief
                isMyBaseThiefTarget = true
            -- Приоритет 2: Вор лучшего brainrot
            elseif thief and thief.player and not IsInFriendList(thief.player) then
                targetThief = thief
                isMyBaseThiefTarget = false
            end
            
            -- Применяем команды к выбранной цели
            if targetThief then
                -- Проверяем можно ли применять команды
                -- Для вора моей базы - СРАЗУ (canApplyCommandsToThief возвращает true для isMyBaseThief)
                if canApplyCommandsToThief(isMyBaseThiefTarget) then
                    -- Проверяем не использовали ли мы недавно rocket (нужно ждать пока долетит)
                    local rocketPauseActive = (now - lastRocketTime) < ROCKET_PAUSE_TIME
                    
                    if not rocketPauseActive then
                        -- Проверяем что прошло достаточно времени с последней команды
                        if now - lastCommandTime >= COMMAND_DELAY then
                            local nextCmd = getNextAvailableCommand()
                            
                            if nextCmd then
                                -- Ещё раз проверяем что вор валиден и не друг
                                if targetThief.player and targetThief.player.Character and not IsInFriendList(targetThief.player) then
                                    local success = executeCommand(targetThief.player, nextCmd.id)
                                    if success then
                                        putCommandOnCooldown(nextCmd.id, nextCmd.cooldown)
                                        lastCommandTime = now
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Радужный эффект для рамки (ЗАЩИТА: pcall для gethui элементов)
local function rainbowLoop()
    while true do
        task.wait(0.05)
        rainbowHue = (rainbowHue + RAINBOW_SPEED * 0.05) % 1
        
        pcall(function()
            if thiefBillboard then
                local frame = thiefBillboard:FindFirstChild("Container")
                if frame then
                    local stroke = frame:FindFirstChild("RainbowStroke")
                    if stroke then
                        stroke.Color = Color3.fromHSV(rainbowHue, 1, 1)
                    end
                end
            end
            
            -- Также обновляем для вора моей базы
            if myBaseThiefBillboard then
                local frame = myBaseThiefBillboard:FindFirstChild("Container")
                if frame then
                    local stroke = frame:FindFirstChild("RainbowStroke")
                    if stroke then
                        stroke.Color = Color3.fromHSV(rainbowHue, 1, 1)
                    end
                end
            end
            
            if mainFrame then
                local mainStroke = mainFrame:FindFirstChildOfClass("UIStroke")
                if mainStroke then
                    mainStroke.Color = Color3.fromHSV(rainbowHue, 0.8, 1)
                end
            end
        end)
    end
end

-- ============== ЗАПУСК ==============

-- Проверяем есть ли админ команды у игрока
local function checkAdminAccess()
    -- Даём время на загрузку атрибутов
    task.wait(2)
    
    local hasAdmin = Players.LocalPlayer:GetAttribute("AdminCommands")
    
    return hasAdmin
end

-- ============== ПЕРЕХВАТ НОТИФИКАЦИЙ ==============

local notificationHookInstalled = false

-- Хук через require - перехватываем функцию Success в NotificationController
local function installNotificationHook()
    if notificationHookInstalled then return end
    
    local success = pcall(function()
        local Controllers = ReplicatedStorage:WaitForChild("Controllers", 5)
        if not Controllers then return end
        
        local NotificationControllerModule = Controllers:FindFirstChild("NotificationController")
        if not NotificationControllerModule then return end
        
        -- Получаем модуль через require
        local NotificationController = require(NotificationControllerModule)
        
        if NotificationController and NotificationController.Success then
            -- Сохраняем оригинальную функцию
            local originalSuccess = NotificationController.Success
            local originalNotify = NotificationController.Notify
            
            -- Заменяем функцию Success на пустую (для сообщений "Successfully executed")
            NotificationController.Success = function(self, text)
                -- Блокируем только сообщения об успешном выполнении команд
                if text and (text:find("Successfully") or text:find("executed")) then
                    return -- Не показываем нотификацию
                end
                -- Остальные Success нотификации показываем
                return originalSuccess(self, text)
            end
            
            -- Также хукаем Notify для перехвата зелёных сообщений
            NotificationController.Notify = function(self, text, duration, sound, position, ...)
                -- Блокируем зелёные нотификации с "Successfully executed"
                if text and (text:find("Successfully") or text:find("executed") or text:find("#92FF67")) then
                    return -- Не показываем
                end
                return originalNotify(self, text, duration, sound, position, ...)
            end
            
            notificationHookInstalled = true
        end
    end)
end

-- Фоновое скрытие нотификаций "Successfully executed" (резервный метод)
local function notificationHiderLoop()
    -- Пробуем установить хук
    task.delay(1, installNotificationHook)
    task.delay(3, installNotificationHook) -- Повторная попытка
    task.delay(5, installNotificationHook) -- Ещё одна попытка
    
    while true do
        task.wait(0.05) -- Быстрее проверяем
        pcall(function()
            local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
            if playerGui then
                local notifContainer = playerGui:FindFirstChild("Notification")
                if notifContainer then
                    local notification = notifContainer:FindFirstChild("Notification")
                    if notification then
                        for _, child in ipairs(notification:GetChildren()) do
                            if child:IsA("TextLabel") and child.Name ~= "Template" then
                                local text = child.Text or ""
                                -- Скрываем зелёные нотификации об успешном выполнении команд
                                if text:find("Successfully") or text:find("executed") or text:find("92FF67") then
                                    child.Visible = false
                                    task.defer(function()
                                        if child and child.Parent then
                                            child:Destroy()
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end

-- Подключение к ChildAdded для мгновенного удаления нотификаций
local notificationConnectionSetup = false
local function setupNotificationConnection()
    if notificationConnectionSetup then return end
    
    pcall(function()
        local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
        if not playerGui then return end
        
        local notifContainer = playerGui:WaitForChild("Notification", 10)
        if not notifContainer then return end
        
        local notification = notifContainer:WaitForChild("Notification", 10)
        if not notification then return end
        
        notification.ChildAdded:Connect(function(child)
            if child:IsA("TextLabel") and child.Name ~= "Template" then
                -- Проверяем текст сразу и через небольшую задержку (текст может установиться позже)
                local function checkAndHide()
                    if not child or not child.Parent then return end
                    local text = child.Text or ""
                    if text:find("Successfully") or text:find("executed") or text:find("92FF67") then
                        child.Visible = false
                        task.defer(function()
                            if child and child.Parent then
                                child:Destroy()
                            end
                        end)
                    end
                end
                
                checkAndHide()
                task.delay(0.01, checkAndHide)
                task.delay(0.05, checkAndHide)
                task.delay(0.1, checkAndHide)
            end
        end)
        
        notificationConnectionSetup = true
    end)
end

-- Инициализация
local function initialize()
    
    -- ПЕРВЫМ ДЕЛОМ устанавливаем хук на нотификации
    task.spawn(installNotificationHook)
    
    -- Инициализируем remote events
    initializeRemotes()
    
    -- Создаём GUI
    createGUI()
    
    -- Проверяем доступ (не блокируем)
    checkAdminAccess()
    
    -- Устанавливаем подключение для мгновенного скрытия нотификаций (резервный метод)
    task.spawn(setupNotificationConnection)
    
    -- Запускаем циклы
    task.spawn(mainLoop)
    task.spawn(rainbowLoop)
    task.spawn(notificationHiderLoop) -- Скрываем нотификации в фоне (резервный метод)
end

initialize()
