--[[
    Farm Config v2.4
    With account management, player list, and target list
]]
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ВАЖНО: Используем farm_data (НЕ farm в ScriptManager) чтобы Wave не пытался загрузить .txt/.json как Lua
local FARM_FOLDER = "farm_data"
local ACCOUNTS_FILE = FARM_FOLDER .. "/accounts.txt"
local GUI_POSITION_FILE = FARM_FOLDER .. "/gui_position.json" -- Общая позиция GUI для всех
local DISABLED_ACCOUNTS_FILE = FARM_FOLDER .. "/disabled_autoload.txt"
local TARGETS_FILE = FARM_FOLDER .. "/targets.json" -- Синхронизированный список целей

-- Проверяем, отключён ли автозапуск для этого аккаунта
local function isAutoloadDisabled(username)
    local disabled = false
    pcall(function()
        if isfolder(FARM_FOLDER) and isfile(DISABLED_ACCOUNTS_FILE) then
            local content = readfile(DISABLED_ACCOUNTS_FILE)
            for line in content:gmatch("[^\r\n]+") do
                local trimmed = line:match("^%s*(.-)%s*$")
                if trimmed and string.lower(trimmed) == string.lower(username) then
                    disabled = true
                    break
                end
            end
        end
    end)
    return disabled
end

-- Если аккаунт в списке отключённых - прерываем загрузку
if isAutoloadDisabled(LocalPlayer.Name) then
    return
end

-- Функции для управления disabled autoload
local function disableAutoload(username)
    pcall(function()
        if not isfolder(FARM_FOLDER) then makefolder(FARM_FOLDER) end
        local content = ""
        if isfile(DISABLED_ACCOUNTS_FILE) then
            content = readfile(DISABLED_ACCOUNTS_FILE)
        end
        -- Проверяем, не добавлен ли уже
        for line in content:gmatch("[^\r\n]+") do
            if string.lower(line:match("^%s*(.-)%s*$") or "") == string.lower(username) then
                return -- Уже есть
            end
        end
        content = content .. username .. "\n"
        writefile(DISABLED_ACCOUNTS_FILE, content)
    end)
end

local function enableAutoload(username)
    pcall(function()
        if not isfile(DISABLED_ACCOUNTS_FILE) then return end
        local content = readfile(DISABLED_ACCOUNTS_FILE)
        local newContent = ""
        for line in content:gmatch("[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed and string.lower(trimmed) ~= string.lower(username) then
                newContent = newContent .. trimmed .. "\n"
            end
        end
        writefile(DISABLED_ACCOUNTS_FILE, newContent)
    end)
end

-- Уникальные файлы для каждого игрока
local function getPlayerSettingsFile(playerName)
    return FARM_FOLDER .. "/settings_" .. playerName .. ".json"
end

local function getPlayerBrainrotsFile(playerName)
    return FARM_FOLDER .. "/brainrots_" .. playerName .. ".json"
end

local function ensureFarmFolder()
    pcall(function()
        -- workspace folder not needed
        if not isfolder(FARM_FOLDER) then makefolder(FARM_FOLDER) end
    end)
end

-- ============ TARGET LIST MANAGEMENT (synchronized across all accounts) ============
local SELECTED_TARGETS = {} -- List of selected target player names

local function loadTargets()
    local targets = {}
    pcall(function()
        ensureFarmFolder()
        if isfile(TARGETS_FILE) then
            local content = readfile(TARGETS_FILE)
            local loaded = HttpService:JSONDecode(content)
            if loaded and loaded.targets then
                targets = loaded.targets
            end
        end
    end)
    SELECTED_TARGETS = targets
    return targets
end

local function saveTargets(targets)
    pcall(function()
        ensureFarmFolder()
        local data = {
            targets = targets,
            lastUpdate = os.time(),
            updatedBy = LocalPlayer.Name
        }
        local content = HttpService:JSONEncode(data)
        writefile(TARGETS_FILE, content)
    end)
    SELECTED_TARGETS = targets
end

local function addTarget(playerName)
    for _, t in ipairs(SELECTED_TARGETS) do
        if string.lower(t) == string.lower(playerName) then
            return false -- Already in list
        end
    end
    table.insert(SELECTED_TARGETS, playerName)
    saveTargets(SELECTED_TARGETS)
    return true
end

local function removeTarget(playerName)
    for i, t in ipairs(SELECTED_TARGETS) do
        if string.lower(t) == string.lower(playerName) then
            table.remove(SELECTED_TARGETS, i)
            saveTargets(SELECTED_TARGETS)
            return true
        end
    end
    return false
end

local function isTarget(playerName)
    for _, t in ipairs(SELECTED_TARGETS) do
        if string.lower(t) == string.lower(playerName) then
            return true
        end
    end
    return false
end

local function clearAllTargets()
    SELECTED_TARGETS = {}
    saveTargets(SELECTED_TARGETS)
end

-- Load targets on startup
loadTargets()
-- ============ END TARGET LIST MANAGEMENT ============

-- Базовый список аккаунтов (только username из файла)
local BASE_ACCOUNTS = {}

local function loadBaseAccounts()
    local accounts = {}
    local fileExists = false
    pcall(function()
        ensureFarmFolder()
        fileExists = isfile(ACCOUNTS_FILE)
        if fileExists then
            local content = readfile(ACCOUNTS_FILE)
            for line in content:gmatch("[^\r\n]+") do
                local trimmed = line:match("^%s*(.-)%s*$")
                if trimmed and trimmed ~= "" and not trimmed:match("^#") then
                    table.insert(accounts, trimmed)
                end
            end
        end
    end)
    
    -- Если файла нет или список пустой - добавляем текущего игрока как первого
    if not fileExists or #accounts == 0 then
        accounts = {LocalPlayer.Name}
        local content = "# Farm Accounts List\n# Add one account per line\n# Lines starting with # are comments\n# Only accounts in this list can use the farm system\n\n" .. LocalPlayer.Name .. "\n"
        pcall(function()
            ensureFarmFolder()
            writefile(ACCOUNTS_FILE, content)
        end)
    end
    
    BASE_ACCOUNTS = accounts
    return accounts
end

-- Функция обновления списка с DisplayName-ами (вызывается при инжекте и при заходе игроков)
local function updateAccountsWithDisplayNames()
    local Players = game:GetService("Players")
    local accountsWithDisplayNames = {}
    local seen = {} -- чтобы не дублировать
    
    for _, accName in ipairs(BASE_ACCOUNTS) do
        local accLower = string.lower(accName)
        if not seen[accLower] then
            seen[accLower] = true
            table.insert(accountsWithDisplayNames, accName)
        end
        
        -- Ищем игрока онлайн и добавляем его DisplayName
        for _, player in ipairs(Players:GetPlayers()) do
            if string.lower(player.Name) == accLower then
                local displayLower = string.lower(player.DisplayName)
                if displayLower ~= accLower and not seen[displayLower] then
                    seen[displayLower] = true
                    table.insert(accountsWithDisplayNames, player.DisplayName)
                end
                break
            end
        end
    end
    
    return accountsWithDisplayNames
end

-- Загружаем базовые аккаунты
loadBaseAccounts()

local function saveAccounts(accounts)
    pcall(function()
        ensureFarmFolder()
        local content = "# Farm Accounts List\n# Add one account per line\n# Lines starting with # are comments\n\n"
        for _, acc in ipairs(accounts) do
            content = content .. acc .. "\n"
        end
        writefile(ACCOUNTS_FILE, content)
    end)
end

-- Функция для красивого форматирования JSON
local function prettyJSON(data)
    local function serialize(val, indent)
        indent = indent or 0
        local spaces = string.rep("    ", indent)
        local nextSpaces = string.rep("    ", indent + 1)
        
        if type(val) == "table" then
            local isArray = #val > 0
            local items = {}
            
            if isArray then
                for _, v in ipairs(val) do
                    table.insert(items, nextSpaces .. serialize(v, indent + 1))
                end
                if #items == 0 then return "[]" end
                return "[\n" .. table.concat(items, ",\n") .. "\n" .. spaces .. "]"
            else
                local keys = {}
                for k in pairs(val) do table.insert(keys, k) end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    local key = '"' .. tostring(k) .. '"'
                    table.insert(items, nextSpaces .. key .. ": " .. serialize(val[k], indent + 1))
                end
                if #items == 0 then return "{}" end
                return "{\n" .. table.concat(items, ",\n") .. "\n" .. spaces .. "}"
            end
        elseif type(val) == "string" then
            return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
        elseif type(val) == "number" or type(val) == "boolean" then
            return tostring(val)
        else
            return "null"
        end
    end
    return serialize(data)
end

-- Загрузка общей позиции GUI (для всех игроков)
local function loadGUIPosition()
    local position = {
        GUI_POSITION_X = 400,
        GUI_POSITION_Y = 100,
    }
    pcall(function()
        ensureFarmFolder()
        if isfile(GUI_POSITION_FILE) then
            local content = readfile(GUI_POSITION_FILE)
            local loaded = HttpService:JSONDecode(content)
            for k, v in pairs(loaded) do position[k] = v end
        end
    end)
    return position
end

local function saveGUIPosition(posX, posY)
    pcall(function()
        ensureFarmFolder()
        local content = prettyJSON({GUI_POSITION_X = posX, GUI_POSITION_Y = posY})
        writefile(GUI_POSITION_FILE, content)
    end)
end

-- Загрузка настроек для конкретного игрока
local function loadPlayerSettings(playerName)
    local settings = {
        GUI_MINIMIZED = false,
        FARM_ENABLED = false,
        MIN_INCOME = 5000000,
    }
    pcall(function()
        ensureFarmFolder()
        local settingsFile = getPlayerSettingsFile(playerName)
        if isfile(settingsFile) then
            local content = readfile(settingsFile)
            local loaded = HttpService:JSONDecode(content)
            for k, v in pairs(loaded) do settings[k] = v end
        end
    end)
    return settings
end

local function savePlayerSettings(playerName, settings)
    pcall(function()
        ensureFarmFolder()
        local settingsFile = getPlayerSettingsFile(playerName)
        local content = prettyJSON(settings)
        writefile(settingsFile, content)
    end)
end

-- Первоначальная загрузка списка с DisplayNames
local STORAGE_ACCOUNTS = updateAccountsWithDisplayNames()
local GUI_POSITION = loadGUIPosition()
local PLAYER_SETTINGS = loadPlayerSettings(LocalPlayer.Name)

-- Функция для обновления списка аккаунтов (вызывается при заходе игроков)
local function refreshAccountsList()
    STORAGE_ACCOUNTS = updateAccountsWithDisplayNames()
    -- Обновляем в глобальном конфиге
    if _G.FarmConfig then
        _G.FarmConfig.STORAGE_ACCOUNTS = STORAGE_ACCOUNTS
    end
end

-- Подписываемся на заход новых игроков
local Players = game:GetService("Players")
Players.PlayerAdded:Connect(function(player)
    -- Проверяем, есть ли этот игрок в базовом списке
    for _, accName in ipairs(BASE_ACCOUNTS) do
        if string.lower(player.Name) == string.lower(accName) then
            refreshAccountsList()
            break
        end
    end
end)

local currentUsername = LocalPlayer.Name
local isInAccountList = false
for _, account in ipairs(STORAGE_ACCOUNTS) do
    if string.lower(account) == string.lower(currentUsername) then
        isInAccountList = true
        break
    end
end

-- Если аккаунт НЕ в списке - не загружаем систему фарма
if not isInAccountList then
    -- Создаём минимальный конфиг без GUI
    _G.FarmConfig = _G.FarmConfig or {}
    _G.FarmConfig.isAllowed = false
    _G.FarmConfig.currentUsername = currentUsername
    _G.FarmConfig.FARM_ENABLED = false
    return -- Прерываем загрузку
end

local DEFAULT_CONFIG = {
    MIN_INCOME = PLAYER_SETTINGS.MIN_INCOME or 5000000,
    TELEPORT_DELAY = 0.7,
    COLLECT_WAIT = 0.5,
    PLACEMENT_CHECK_DELAY = 1,
    GUI_POSITION_X = GUI_POSITION.GUI_POSITION_X or 400,
    GUI_POSITION_Y = GUI_POSITION.GUI_POSITION_Y or 100,
    GUI_MINIMIZED = PLAYER_SETTINGS.GUI_MINIMIZED or false,
    FARM_ENABLED = PLAYER_SETTINGS.FARM_ENABLED or false,
}

_G.FarmConfig = _G.FarmConfig or {}
local CONFIG = _G.FarmConfig
CONFIG.STORAGE_ACCOUNTS = STORAGE_ACCOUNTS
CONFIG.BASE_ACCOUNTS = BASE_ACCOUNTS
CONFIG.refreshAccountsList = refreshAccountsList

for key, value in pairs(DEFAULT_CONFIG) do
    CONFIG[key] = value
end

local function isStorageAccount(username)
    for _, account in ipairs(CONFIG.STORAGE_ACCOUNTS) do
        if string.lower(account) == string.lower(username) then return true end
    end
    return false
end

local function isBaseAccount(username)
    for _, account in ipairs(BASE_ACCOUNTS) do
        if string.lower(account) == string.lower(username) then return true end
    end
    return false
end

local function addAccount(username)
    if not isBaseAccount(username) then
        table.insert(BASE_ACCOUNTS, username)
        saveAccounts(BASE_ACCOUNTS) -- Сохраняем только базовые аккаунты
        refreshAccountsList() -- Обновляем список с DisplayNames
        enableAutoload(username) -- Включаем автозагрузку для нового аккаунта
        return true
    end
    return false
end

local function removeAccount(username)
    for i, account in ipairs(BASE_ACCOUNTS) do
        if string.lower(account) == string.lower(username) then
            table.remove(BASE_ACCOUNTS, i)
            saveAccounts(BASE_ACCOUNTS) -- Сохраняем только базовые аккаунты
            refreshAccountsList() -- Обновляем список с DisplayNames
            disableAutoload(username) -- Отключаем автозагрузку для удалённого аккаунта
            return true
        end
    end
    return false
end

local isAllowed = isStorageAccount(currentUsername)

_G.FarmConfig.isAllowed = isAllowed
_G.FarmConfig.currentUsername = currentUsername
_G.FarmConfig.addAccount = addAccount
_G.FarmConfig.removeAccount = removeAccount
_G.FarmConfig.disableAutoload = disableAutoload
_G.FarmConfig.enableAutoload = enableAutoload
_G.FarmConfig.isStorageAccount = isStorageAccount
-- Target list functions (synchronized across all accounts)
_G.FarmConfig.isTarget = function(playerName) 
    loadTargets() -- Перезагружаем из файла для синхронизации
    return isTarget(playerName) 
end
_G.FarmConfig.loadTargets = loadTargets
_G.FarmConfig.addTarget = addTarget
_G.FarmConfig.removeTarget = removeTarget
_G.FarmConfig.getTargets = function() 
    loadTargets() -- Перезагружаем из файла для синхронизации
    return SELECTED_TARGETS 
end

local screenGui, mainFrame, guiElements = nil, nil, {}
local playerListVisible = false
local playerListFrame = nil
local targetListVisible = false
local targetListFrame = nil

_G.FarmConfig.Status = {text = "Waiting...", color = Color3.fromRGB(150, 150, 150), plotsUsed = 0, plotsMax = 0}
_G.FarmConfig.CollectedThisSession = 0

local function saveCurrentSettings()
    -- Сохраняем позицию GUI отдельно (общая для всех)
    saveGUIPosition(CONFIG.GUI_POSITION_X, CONFIG.GUI_POSITION_Y)
    -- Сохраняем настройки игрока отдельно
    local playerSettings = {
        GUI_MINIMIZED = CONFIG.GUI_MINIMIZED,
        FARM_ENABLED = CONFIG.FARM_ENABLED,
        MIN_INCOME = CONFIG.MIN_INCOME,
    }
    savePlayerSettings(LocalPlayer.Name, playerSettings)
end

local function updatePlayerList()
    if not playerListFrame then return end
    for _, child in ipairs(playerListFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    local yOffset = 5
    for _, player in ipairs(Players:GetPlayers()) do
        local playerName = player.Name
        local isInList = isStorageAccount(playerName)
        
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -10, 0, 28)
        btn.Position = UDim2.new(0, 5, 0, yOffset)
        btn.BackgroundColor3 = isInList and Color3.fromRGB(50, 120, 50) or Color3.fromRGB(50, 55, 65)
        btn.Text = (isInList and "[+] " or "    ") .. playerName
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.AutoButtonColor = true
        btn.Parent = playerListFrame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        
        btn.MouseButton1Click:Connect(function()
            if isStorageAccount(playerName) then
                removeAccount(playerName)
                btn.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
                btn.Text = "    " .. playerName
            else
                addAccount(playerName)
                btn.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
                btn.Text = "[+] " .. playerName
            end
            if guiElements.accountStatusLabel then
                guiElements.accountStatusLabel.Text = isStorageAccount(currentUsername) and "In autoload" or "Not in autoload"
                guiElements.accountStatusLabel.TextColor3 = isStorageAccount(currentUsername) and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(200, 100, 100)
            end
        end)
        
        yOffset = yOffset + 32
    end
    
    playerListFrame.CanvasSize = UDim2.new(0, 0, 0, yOffset + 5)
end

-- Обновление списка целей (только игроки НЕ в списке farm-аккаунтов)
local function updateTargetList()
    if not targetListFrame then return end
    for _, child in ipairs(targetListFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    -- Перезагружаем targets.json для синхронизации
    loadTargets()
    
    local yOffset = 5
    for _, player in ipairs(Players:GetPlayers()) do
        local playerName = player.Name
        -- Показываем только игроков НЕ в farm списке
        if not isStorageAccount(playerName) then
            local isTargeted = isTarget(playerName)
            
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -10, 0, 28)
            btn.Position = UDim2.new(0, 5, 0, yOffset)
            btn.BackgroundColor3 = isTargeted and Color3.fromRGB(180, 80, 50) or Color3.fromRGB(50, 55, 65)
            btn.Text = (isTargeted and "[T] " or "    ") .. playerName
            btn.TextColor3 = Color3.new(1, 1, 1)
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 11
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.AutoButtonColor = true
            btn.Parent = targetListFrame
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
            
            btn.MouseButton1Click:Connect(function()
                if isTarget(playerName) then
                    removeTarget(playerName)
                    btn.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
                    btn.Text = "    " .. playerName
                else
                    addTarget(playerName)
                    btn.BackgroundColor3 = Color3.fromRGB(180, 80, 50)
                    btn.Text = "[T] " .. playerName
                end
            end)
            
            yOffset = yOffset + 32
        end
    end
    
    if yOffset == 5 then
        -- Нет игроков для таргета
        local noPlayersLabel = Instance.new("TextLabel")
        noPlayersLabel.Size = UDim2.new(1, -10, 0, 28)
        noPlayersLabel.Position = UDim2.new(0, 5, 0, yOffset)
        noPlayersLabel.BackgroundTransparency = 1
        noPlayersLabel.Text = "No players to target"
        noPlayersLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        noPlayersLabel.Font = Enum.Font.Gotham
        noPlayersLabel.TextSize = 11
        noPlayersLabel.Parent = targetListFrame
        yOffset = yOffset + 32
    end
    
    targetListFrame.CanvasSize = UDim2.new(0, 0, 0, yOffset + 5)
end

local function createGUI()
    local oldGui = CoreGui:FindFirstChild("FarmConfigGUI")
    if oldGui then oldGui:Destroy() end

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FarmConfigGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = CoreGui

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 280, 0, CONFIG.GUI_MINIMIZED and 40 or 400)
    mainFrame.Position = UDim2.new(0, CONFIG.GUI_POSITION_X, 0, CONFIG.GUI_POSITION_Y)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Parent = screenGui

    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", mainFrame)
    stroke.Color = Color3.fromRGB(80, 120, 200)
    stroke.Thickness = 2

    local titleBar = Instance.new("Frame", mainFrame)
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = Color3.fromRGB(40, 60, 100)
    titleBar.BorderSizePixel = 0
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

    local titleLabel = Instance.new("TextLabel", titleBar)
    titleLabel.Size = UDim2.new(1, -80, 1, 0)
    titleLabel.Position = UDim2.new(0, 12, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Brainrot Farm"
    titleLabel.TextColor3 = Color3.new(1, 1, 1)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 16

    local minimizeBtn = Instance.new("TextButton", titleBar)
    minimizeBtn.Size = UDim2.new(0, 28, 0, 28)
    minimizeBtn.Position = UDim2.new(1, -68, 0.5, -14)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    minimizeBtn.Text = CONFIG.GUI_MINIMIZED and "+" or "-"
    minimizeBtn.TextColor3 = Color3.new(1, 1, 1)
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.TextSize = 18
    Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 6)

    local closeBtn = Instance.new("TextButton", titleBar)
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -34, 0.5, -14)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 16
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    local contentFrame = Instance.new("Frame", mainFrame)
    contentFrame.Name = "Content"
    contentFrame.Size = UDim2.new(1, 0, 1, -40)
    contentFrame.Position = UDim2.new(0, 0, 0, 40)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Visible = not CONFIG.GUI_MINIMIZED
    contentFrame.ClipsDescendants = true

    local toggleBtn = Instance.new("TextButton", contentFrame)
    toggleBtn.Size = UDim2.new(1, -24, 0, 40)
    toggleBtn.Position = UDim2.new(0, 12, 0, 8)
    toggleBtn.BackgroundColor3 = CONFIG.FARM_ENABLED and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(50, 150, 50)
    toggleBtn.Text = CONFIG.FARM_ENABLED and "STOP" or "START"
    toggleBtn.TextColor3 = Color3.new(1, 1, 1)
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 16
    Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)
    guiElements.toggleBtn = toggleBtn

    local statusFrame = Instance.new("Frame", contentFrame)
    statusFrame.Size = UDim2.new(1, -24, 0, 60)
    statusFrame.Position = UDim2.new(0, 12, 0, 117)
    statusFrame.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
    Instance.new("UICorner", statusFrame).CornerRadius = UDim.new(0, 8)

    local statusLabel = Instance.new("TextLabel", statusFrame)
    statusLabel.Size = UDim2.new(1, -10, 1, -5)
    statusLabel.Position = UDim2.new(0, 5, 0, 5)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Waiting..."
    statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    statusLabel.TextWrapped = true
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 11
    guiElements.statusLabel = statusLabel

    local baseFrame = Instance.new("Frame", contentFrame)
    baseFrame.Size = UDim2.new(1, -24, 0, 35)
    baseFrame.Position = UDim2.new(0, 12, 0, 184)
    baseFrame.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
    Instance.new("UICorner", baseFrame).CornerRadius = UDim.new(0, 8)

    local baseLabel = Instance.new("TextLabel", baseFrame)
    baseLabel.Size = UDim2.new(1, -10, 1, 0)
    baseLabel.Position = UDim2.new(0, 5, 0, 0)
    baseLabel.BackgroundTransparency = 1
    baseLabel.Text = "Base: 0/0 | Collected: 0"
    baseLabel.TextColor3 = Color3.new(1, 1, 1)
    baseLabel.TextXAlignment = Enum.TextXAlignment.Left
    baseLabel.Font = Enum.Font.Gotham
    baseLabel.TextSize = 12
    guiElements.baseLabel = baseLabel

    local accountFrame = Instance.new("Frame", contentFrame)
    accountFrame.Size = UDim2.new(1, -24, 0, 50)
    accountFrame.Position = UDim2.new(0, 12, 0, 226)
    accountFrame.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
    Instance.new("UICorner", accountFrame).CornerRadius = UDim.new(0, 8)

    local accountLabel = Instance.new("TextLabel", accountFrame)
    accountLabel.Size = UDim2.new(0.6, 0, 0, 20)
    accountLabel.Position = UDim2.new(0, 8, 0, 5)
    accountLabel.BackgroundTransparency = 1
    accountLabel.Text = "Account: " .. currentUsername
    accountLabel.TextColor3 = Color3.new(1, 1, 1)
    accountLabel.TextXAlignment = Enum.TextXAlignment.Left
    accountLabel.Font = Enum.Font.Gotham
    accountLabel.TextSize = 11

    local accountStatusLabel = Instance.new("TextLabel", accountFrame)
    accountStatusLabel.Size = UDim2.new(1, -16, 0, 18)
    accountStatusLabel.Position = UDim2.new(0, 8, 0, 27)
    accountStatusLabel.BackgroundTransparency = 1
    accountStatusLabel.Text = isAllowed and "In autoload" or "Not in autoload"
    accountStatusLabel.TextColor3 = isAllowed and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(200, 100, 100)
    accountStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    accountStatusLabel.Font = Enum.Font.Gotham
    accountStatusLabel.TextSize = 10
    guiElements.accountStatusLabel = accountStatusLabel

    local addRemoveBtn = Instance.new("TextButton", accountFrame)
    addRemoveBtn.Size = UDim2.new(0, 60, 0, 22)
    addRemoveBtn.Position = UDim2.new(1, -68, 0, 5)
    addRemoveBtn.BackgroundColor3 = isAllowed and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(50, 150, 50)
    addRemoveBtn.Text = isAllowed and "Remove" or "Add"
    addRemoveBtn.TextColor3 = Color3.new(1, 1, 1)
    addRemoveBtn.Font = Enum.Font.GothamBold
    addRemoveBtn.TextSize = 10
    Instance.new("UICorner", addRemoveBtn).CornerRadius = UDim.new(0, 4)
    guiElements.addRemoveBtn = addRemoveBtn

    local playerListBtn = Instance.new("TextButton", contentFrame)
    playerListBtn.Size = UDim2.new(1, -24, 0, 28)
    playerListBtn.Position = UDim2.new(0, 12, 0, 284)
    playerListBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 120)
    playerListBtn.Text = "▶ Farmers"
    playerListBtn.TextColor3 = Color3.new(1, 1, 1)
    playerListBtn.Font = Enum.Font.GothamBold
    playerListBtn.TextSize = 12
    Instance.new("UICorner", playerListBtn).CornerRadius = UDim.new(0, 6)

    playerListFrame = Instance.new("ScrollingFrame", contentFrame)
    playerListFrame.Size = UDim2.new(1, -24, 0, 112)
    playerListFrame.Position = UDim2.new(0, 12, 0, 316)
    playerListFrame.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
    playerListFrame.BorderSizePixel = 0
    playerListFrame.ScrollBarThickness = 5
    playerListFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
    playerListFrame.Visible = false
    playerListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    Instance.new("UICorner", playerListFrame).CornerRadius = UDim.new(0, 6)

    -- Target List Button (для выбора целей, синхронизирован между аккаунтами)
    local targetListBtn = Instance.new("TextButton", contentFrame)
    targetListBtn.Size = UDim2.new(1, -24, 0, 28)
    targetListBtn.Position = UDim2.new(0, 12, 0, 316) -- Начальная позиция = после playerListBtn
    targetListBtn.BackgroundColor3 = Color3.fromRGB(150, 80, 50)
    targetListBtn.Text = "▶ Targets"
    targetListBtn.TextColor3 = Color3.new(1, 1, 1)
    targetListBtn.Font = Enum.Font.GothamBold
    targetListBtn.TextSize = 12
    Instance.new("UICorner", targetListBtn).CornerRadius = UDim.new(0, 6)

    targetListFrame = Instance.new("ScrollingFrame", contentFrame)
    targetListFrame.Size = UDim2.new(1, -24, 0, 112)
    targetListFrame.Position = UDim2.new(0, 12, 0, 348)
    targetListFrame.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
    targetListFrame.BorderSizePixel = 0
    targetListFrame.ScrollBarThickness = 5
    targetListFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
    targetListFrame.Visible = false
    targetListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    Instance.new("UICorner", targetListFrame).CornerRadius = UDim.new(0, 6)

    -- Функция обновления позиций элементов
    local function updateElementPositions()
        -- playerListBtn на 284, высота 28
        -- playerListFrame на 316 (284 + 28 + 4), высота 112
        local currentY = 316 -- После playerListBtn
        
        if playerListVisible then
            currentY = 316 + 112 + 4 -- 432
        end
        
        -- targetListBtn идёт после playerList
        targetListBtn.Position = UDim2.new(0, 12, 0, currentY)
        currentY = currentY + 28 + 4 -- После кнопки target (28 + 4 margin)
        
        -- targetListFrame идёт после targetListBtn
        targetListFrame.Position = UDim2.new(0, 12, 0, currentY)
    end

    -- Функция расчёта высоты GUI
    local function calculateGUIHeight()
        -- playerListBtn на 284, высота 28
        -- targetListBtn начинается на 316 (если playerList закрыт), высота 28
        -- Итого закрытые: 316 + 28 = 344 + отступ = ~400
        local height = 370 -- Базовая высота с двумя закрытыми кнопками
        if playerListVisible then 
            height = height + 116 -- playerListFrame (112 + 4)
        end
        if targetListVisible then 
            height = height + 116 -- targetListFrame (112 + 4)
        end
        return height + 30 -- Дополнительный отступ снизу
    end

    -- Функция обновления размера GUI
    local function updateGUISize()
        if not CONFIG.GUI_MINIMIZED then
            mainFrame.Size = UDim2.new(0, 280, 0, calculateGUIHeight())
        end
    end

    local dragging, dragStart, startPos = false, nil, nil
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, dragStart, startPos = true, input.Position, mainFrame.Position
        end
    end)
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            CONFIG.GUI_POSITION_X = mainFrame.Position.X.Offset
            CONFIG.GUI_POSITION_Y = mainFrame.Position.Y.Offset
            saveCurrentSettings()
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    minimizeBtn.MouseButton1Click:Connect(function()
        CONFIG.GUI_MINIMIZED = not CONFIG.GUI_MINIMIZED
        minimizeBtn.Text = CONFIG.GUI_MINIMIZED and "+" or "-"
        contentFrame.Visible = not CONFIG.GUI_MINIMIZED
        local targetHeight = CONFIG.GUI_MINIMIZED and 40 or calculateGUIHeight()
        mainFrame.Size = UDim2.new(0, 280, 0, targetHeight)
        saveCurrentSettings()
    end)

    closeBtn.MouseButton1Click:Connect(function()
        CONFIG.FARM_ENABLED = false
        saveCurrentSettings()
        screenGui:Destroy()
    end)

    toggleBtn.MouseButton1Click:Connect(function()
        CONFIG.FARM_ENABLED = not CONFIG.FARM_ENABLED
        toggleBtn.Text = CONFIG.FARM_ENABLED and "STOP" or "START"
        toggleBtn.BackgroundColor3 = CONFIG.FARM_ENABLED and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(50, 150, 50)
        saveCurrentSettings()
    end)

    addRemoveBtn.MouseButton1Click:Connect(function()
        if isStorageAccount(currentUsername) then
            removeAccount(currentUsername)
            addRemoveBtn.Text = "Add"
            addRemoveBtn.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
            accountStatusLabel.Text = "Not in autoload"
            accountStatusLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
        else
            addAccount(currentUsername)
            addRemoveBtn.Text = "Remove"
            addRemoveBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
            accountStatusLabel.Text = "In autoload"
            accountStatusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
        end
        _G.FarmConfig.isAllowed = isStorageAccount(currentUsername)
        updatePlayerList()
    end)

    playerListBtn.MouseButton1Click:Connect(function()
        playerListVisible = not playerListVisible
        playerListFrame.Visible = playerListVisible
        playerListBtn.Text = playerListVisible and "▼ Players on Server" or "▶ Players on Server"
        -- Обновить позиции элементов
        updateElementPositions()
        -- Обновляем высоту GUI
        updateGUISize()
        if playerListVisible then updatePlayerList() end
    end)

    targetListBtn.MouseButton1Click:Connect(function()
        targetListVisible = not targetListVisible
        targetListFrame.Visible = targetListVisible
        targetListBtn.Text = targetListVisible and "▼ Targets (Shared)" or "▶ Targets (Shared)"
        -- Обновить позиции элементов
        updateElementPositions()
        -- Обновляем высоту GUI
        updateGUISize()
        if targetListVisible then updateTargetList() end
    end)

    Players.PlayerAdded:Connect(function()
        if playerListVisible then updatePlayerList() end
        if targetListVisible then updateTargetList() end
    end)
    Players.PlayerRemoving:Connect(function()
        if playerListVisible then task.wait(0.1) updatePlayerList() end
        if targetListVisible then task.wait(0.1) updateTargetList() end
    end)

    -- Синхронизация целей каждые 3 секунды
    task.spawn(function()
        while screenGui and screenGui.Parent do
            task.wait(3)
            if targetListVisible then
                updateTargetList()
            end
        end
    end)
end

createGUI()

task.spawn(function()
    while screenGui and screenGui.Parent do
        local status = _G.FarmConfig.Status
        if guiElements.statusLabel then
            guiElements.statusLabel.Text = status.text
            guiElements.statusLabel.TextColor3 = status.color
        end
        if guiElements.baseLabel then
            guiElements.baseLabel.Text = string.format("Base: %d/%d | Collected: %d", status.plotsUsed, status.plotsMax, _G.FarmConfig.CollectedThisSession or 0)
        end
        task.wait(0.5)
    end
end)

_G.FarmConfig.updateStatus = function(text, color)
    _G.FarmConfig.Status.text = text
    _G.FarmConfig.Status.color = color or Color3.fromRGB(150, 150, 150)
end

_G.FarmConfig.setPlotInfo = function(used, max)
    _G.FarmConfig.Status.plotsUsed = used
    _G.FarmConfig.Status.plotsMax = max
end
