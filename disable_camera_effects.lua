task.wait(5) -- Group 2: UI/Effects (5 sec delay)

--[[
    Camera Effects Disabler
    Автоматически отключает все эффекты камеры при инжекте:
    - Camera shake (тряску)
    - FieldOfView изменения (зум)
    - BlurEffect (размытие от пчел/boogie bomb)
    - ColorCorrection (цветокоррекция)
    - Splatter Slap burst эффекты (НО оставляет Paintball Gun!)
    
    Работает через hooking метаметодов и блокировку создания эффектов
    
    ВАЖНО: Paintball Gun и Splatter Slap используют ОДИНАКОВЫЕ эффекты!
    Разница: Paintball Gun = 1-2 краски, Splatter Slap = много (burst)
    Скрипт определяет burst (3+ эффекта за 0.2 сек) и блокирует ТОЛЬКО его
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============== ЗАЩИТА ОТ АНТИЧИТА ==============

-- Получение защищённого GUI контейнера (gethui или CoreGui)
local function getProtectedGui()
    -- gethui() - самый защищённый способ (не детектится)
    if gethui then
        local success, result = pcall(gethui)
        if success and result then
            return result
        end
    end
    
    -- Fallback на CoreGui
    local success, result = pcall(function()
        return CoreGui
    end)
    if success and result then
        return result
    end
    
    -- Последний fallback - nil
    return nil
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

local protectedGuiContainer = getProtectedGui()

-- Настройки
local CONFIG = {
    BLOCK_FOV_CHANGES = true,        -- Блокировать изменения FieldOfView
    BLOCK_BLUR_EFFECTS = true,        -- Блокировать BlurEffect
    BLOCK_COLOR_CORRECTION = true,    -- Блокировать ColorCorrection
    BLOCK_CAMERA_SHAKE = true,        -- Блокировать тряску камеры
    BLOCK_INVERTED_CONTROLS = true,  -- Блокировать инверсию управления
    BLOCK_SCREEN_EFFECTS = true,     -- Блокировать Splatter Slap bursts (оставляет Paintball Gun 1-2 эффекта)
    DEFAULT_FOV = 70,                 -- Стандартный FOV
    ALLOW_MANUAL_FOV = true,          -- Разрешить ручное изменение FOV игроком
    LOG_BLOCKED_EFFECTS = false,      -- Логировать заблокированные эффекты
}

-- Статистика
local stats = {
    blockedFOV = 0,
    blockedBlur = 0,
    blockedColorCorrection = 0,
    blockedShake = 0,
    blockedInversion = 0,
    blockedScreenEffects = 0,
}

-- Оригинальные функции
local originalNewIndex = nil
local originalInstance = Instance.new
local blockedEffectNames = {}

-- ============================================================================
-- ЗАЩИТА FOV (FieldOfView)
-- ============================================================================

-- Хук Camera.FieldOfView через метатаблицу
local function protectFOV()
    if not CONFIG.BLOCK_FOV_CHANGES then return end
    
    local cameraMetatable = getrawmetatable(camera)
    local oldNewIndex = cameraMetatable.__newindex
    originalNewIndex = oldNewIndex
    
    setreadonly(cameraMetatable, false)
    
    cameraMetatable.__newindex = newcclosure(function(self, key, value)
        -- ПОЛНАЯ БЛОКИРОВКА FOV - игнорируем ВСЕ изменения кроме нашего DEFAULT_FOV
        if self == camera and key == "FieldOfView" then
            if value ~= CONFIG.DEFAULT_FOV then
                stats.blockedFOV = stats.blockedFOV + 1
                return -- Блокируем ЛЮБОЕ изменение
            end
        end
        
        return oldNewIndex(self, key, value)
    end)
    
    setreadonly(cameraMetatable, true)
    
    -- АГРЕССИВНЫЙ сброс FOV каждый кадр через RenderStepped (приоритет)
    RunService.RenderStepped:Connect(function()
        if camera.FieldOfView ~= CONFIG.DEFAULT_FOV then
            pcall(function()
                camera.FieldOfView = CONFIG.DEFAULT_FOV
            end)
        end
    end)
    
    -- Дополнительный сброс через Heartbeat для двойной защиты
    RunService.Heartbeat:Connect(function()
        if camera.FieldOfView ~= CONFIG.DEFAULT_FOV then
            pcall(function()
                camera.FieldOfView = CONFIG.DEFAULT_FOV
            end)
        end
    end)
end

-- ============================================================================
-- БЛОКИРОВКА ЭФФЕКТОВ В LIGHTING (BlurEffect, ColorCorrection)
-- ============================================================================

local function blockLightingEffects()
    -- Таблица для хранения скрытых эффектов
    local hiddenEffects = {}
    local dummyFolder = Instance.new("Folder")
    dummyFolder.Name = generateRandomName() -- ЗАЩИТА: рандомное имя вместо "HiddenEffects"
    dummyFolder:SetAttribute("_isHiddenEffectsFolder", true) -- для идентификации
    dummyFolder.Parent = nil -- Держим в памяти, но не в иерархии
    
    -- ПЕРЕХВАТЫВАЕМ Parent - перемещаем эффекты в скрытую папку
    local function interceptEffect(effect, effectType)
        if hiddenEffects[effect] then return end
        hiddenEffects[effect] = true
        
        pcall(function()
            -- Хукаем Parent через метатаблицу
            local effectMt = getrawmetatable(effect)
            setreadonly(effectMt, false)
            local oldNewIndex = effectMt.__newindex
            
            effectMt.__newindex = newcclosure(function(self, key, value)
                if self == effect and key == "Parent" then
                    -- Если пытаются установить Parent в Lighting - перенаправляем в dummy
                    if value == Lighting then
                        if effectType == "BlurEffect" then
                            stats.blockedBlur = stats.blockedBlur + 1
                        else
                            stats.blockedColorCorrection = stats.blockedColorCorrection + 1
                        end
                        return oldNewIndex(self, key, dummyFolder) -- Перенаправляем в dummy
                    end
                end
                return oldNewIndex(self, key, value)
            end)
            
            setreadonly(effectMt, true)
            
            -- Если эффект уже в Lighting - перемещаем в dummy
            if effect.Parent == Lighting then
                effect.Parent = dummyFolder
            end
        end)
    end
    
    -- Обрабатываем существующие эффекты
    for _, effect in ipairs(Lighting:GetChildren()) do
        pcall(function()
            if effect:IsA("BlurEffect") and CONFIG.BLOCK_BLUR_EFFECTS then
                interceptEffect(effect, "BlurEffect")
            elseif effect:IsA("ColorCorrectionEffect") and CONFIG.BLOCK_COLOR_CORRECTION then
                if effect.Name ~= "ColorCCorrection" then
                    interceptEffect(effect, "ColorCorrectionEffect")
                end
            end
        end)
    end
    
    -- МГНОВЕННО перехватываем новые эффекты
    Lighting.ChildAdded:Connect(function(child)
        pcall(function()
            if child:IsA("BlurEffect") and CONFIG.BLOCK_BLUR_EFFECTS then
                -- Немедленно перемещаем в dummy
                child.Parent = dummyFolder
                interceptEffect(child, "BlurEffect")
                stats.blockedBlur = stats.blockedBlur + 1
            elseif child:IsA("ColorCorrectionEffect") and CONFIG.BLOCK_COLOR_CORRECTION then
                if child.Name ~= "ColorCCorrection" then
                    -- Немедленно перемещаем в dummy
                    child.Parent = dummyFolder
                    interceptEffect(child, "ColorCorrectionEffect")
                    stats.blockedColorCorrection = stats.blockedColorCorrection + 1
                end
            end
        end)
    end)
    
    -- АГРЕССИВНАЯ очистка каждый кадр (на случай если эффекты как-то вернулись)
    RunService.RenderStepped:Connect(function()
        pcall(function()
            for _, effect in ipairs(Lighting:GetChildren()) do
                if effect:IsA("BlurEffect") and CONFIG.BLOCK_BLUR_EFFECTS then
                    if not hiddenEffects[effect] then
                        effect.Parent = dummyFolder
                        interceptEffect(effect, "BlurEffect")
                    elseif effect.Parent == Lighting then
                        -- Эффект каким-то образом вернулся в Lighting
                        effect.Parent = dummyFolder
                    end
                elseif effect:IsA("ColorCorrectionEffect") and CONFIG.BLOCK_COLOR_CORRECTION then
                    if effect.Name ~= "ColorCCorrection" then
                        if not hiddenEffects[effect] then
                            effect.Parent = dummyFolder
                            interceptEffect(effect, "ColorCorrectionEffect")
                        elseif effect.Parent == Lighting then
                            -- Эффект каким-то образом вернулся в Lighting
                            effect.Parent = dummyFolder
                        end
                    end
                end
            end
        end)
    end)
end

-- ============================================================================
-- БЛОКИРОВКА CAMERA SHAKE
-- ============================================================================

local function blockCameraShake()
    if not CONFIG.BLOCK_CAMERA_SHAKE then return end
    
    -- БЛОКИРУЕМ CAMERA CFRAME ИЗМЕНЕНИЯ
    local cameraMetatable = getrawmetatable(camera)
    setreadonly(cameraMetatable, false)
    local oldCameraNewIndex = cameraMetatable.__newindex
    
    cameraMetatable.__newindex = newcclosure(function(self, key, value)
        if self == camera and key == "CFrame" then
            -- Разрешаем только изменения от игрока, блокируем shake эффекты
            local trace = debug.traceback()
            if string.find(trace, "Shake") or 
               string.find(trace, "Bump") or
               string.find(trace, "BindShakeToCamera") or
               string.find(trace, "Glitch") then
                stats.blockedShake = stats.blockedShake + 1
                return -- Блокируем shake изменения CFrame
            end
        end
        return oldCameraNewIndex(self, key, value)
    end)
    
    setreadonly(cameraMetatable, true)
    
    -- Находим Shake модули и отключаем их
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    
    -- Попытка найти Shared/ShakePresets
    local success, shared = pcall(function()
        return ReplicatedStorage:WaitForChild("Shared", 2)
    end)
    
    if success and shared then
        local shakePresetsSuccess, shakePresets = pcall(function()
            return shared:FindFirstChild("ShakePresets")
        end)
        
        if shakePresetsSuccess and shakePresets then
            -- Хук require для ShakePresets
            local oldRequire = require
            getgenv().require = function(module)
                if module == shakePresets then
                    stats.blockedShake = stats.blockedShake + 1
                    -- Возвращаем пустую таблицу вместо shake presets
                    local fakeShakePresets = {
                        Bump = {
                            Clone = function() 
                                return {
                                    Start = function() end,
                                    Stop = function() end,
                                    StopSustain = function() end,
                                    Sustain = false,
                                }
                            end
                        },
                        BindShakeToCamera = function() 
                            stats.blockedShake = stats.blockedShake + 1
                            return {
                                Disconnect = function() end
                            }
                        end,
                    }
                    setmetatable(fakeShakePresets, {
                        __index = function(self, key)
                            -- Возвращаем пустые shake presets для любых других ключей
                            return {
                                Clone = function()
                                    return {
                                        Start = function() end,
                                        Stop = function() end,
                                        StopSustain = function() end,
                                        Sustain = false,
                                    }
                                end
                            }
                        end
                    })
                    return fakeShakePresets
                end
                return oldRequire(module)
            end
        end
    end
    
    -- Блокируем Conch AST ObjectShake методы (альтернативная система shake)
    pcall(function()
        local packages = ReplicatedStorage:WaitForChild("Packages", 2)
        if packages then
            local conch = packages:FindFirstChild("Conch")
            if conch then
                -- Хукаем методы AddObjectShake/RemoveObjectShake
                -- Это делается через перехват require выше
            end
        end
    end)
end

-- ============================================================================
-- БЛОКИРОВКА ЭФФЕКТОВ НА ЭКРАНЕ (Splatter Slap ТОЛЬКО)
-- ============================================================================

local function blockScreenEffects()
    if not CONFIG.BLOCK_SCREEN_EFFECTS then return end
    
    local PlayerGui = localPlayer:WaitForChild("PlayerGui")
    local MainGui = PlayerGui:WaitForChild("Main")
    
    -- Трекер для обнаружения burst эффектов (Splatter Slap)
    local paintEffectBurst = {
        count = 0,
        lastTime = 0,
        resetDelay = 0.2 -- Если эффекты появляются чаще чем 0.2 сек = burst
    }
    
    -- Функция проверки - это Splatter Slap burst или обычный Paintball Gun
    local function shouldBlockPaintEffect()
        local currentTime = tick()
        local timeSinceLast = currentTime - paintEffectBurst.lastTime
        
        -- Сброс счетчика если прошло много времени
        if timeSinceLast > paintEffectBurst.resetDelay then
            paintEffectBurst.count = 0
        end
        
        paintEffectBurst.count = paintEffectBurst.count + 1
        paintEffectBurst.lastTime = currentTime
        
        -- Если 3+ эффекта за короткое время = Splatter Slap burst
        if paintEffectBurst.count >= 3 then
            return true
        end
        
        return false
    end
    
    -- Мониторим PlayerGui.Main для paint эффектов
    MainGui.ChildAdded:Connect(function(child)
        pcall(function()
            -- Проверяем что это ImageLabel (paint effect)
            if child:IsA("ImageLabel") then
                -- Проверяем что это paint/splatter эффект по позиции (рандомная)
                -- Paint эффекты имеют рандомную позицию от 0.1 до 0.9
                local pos = child.Position
                if pos.X.Scale > 0.05 and pos.X.Scale < 0.95 and 
                   pos.Y.Scale > 0.05 and pos.Y.Scale < 0.95 then
                    
                    -- Это paint эффект - проверяем burst
                    if shouldBlockPaintEffect() then
                        -- Это Splatter Slap burst - удаляем
                        child:Destroy()
                        stats.blockedScreenEffects = stats.blockedScreenEffects + 1
                    end
                end
            end
        end)
    end)
    
    -- Удаляем существующие paint эффекты при загрузке
    for _, child in ipairs(MainGui:GetChildren()) do
        pcall(function()
            if child:IsA("ImageLabel") then
                local pos = child.Position
                if pos.X.Scale > 0.05 and pos.X.Scale < 0.95 and 
                   pos.Y.Scale > 0.05 and pos.Y.Scale < 0.95 then
                    child:Destroy()
                    stats.blockedScreenEffects = stats.blockedScreenEffects + 1
                end
            end
        end)
    end
    
    -- Очистка paint эффектов каждые 5 секунд (на случай если что-то пропустили)
    task.spawn(function()
        while task.wait(5) do
            pcall(function()
                local cleanedCount = 0
                for _, child in ipairs(MainGui:GetChildren()) do
                    if child:IsA("ImageLabel") then
                        local pos = child.Position
                        if pos.X.Scale > 0.05 and pos.X.Scale < 0.95 and 
                           pos.Y.Scale > 0.05 and pos.Y.Scale < 0.95 then
                            -- Проверяем время существования - если > 5 сек, это явно багнутый эффект
                            if tick() - paintEffectBurst.lastTime > 5 then
                                child:Destroy()
                                cleanedCount = cleanedCount + 1
                            end
                        end
                    end
                end
                if cleanedCount > 0 then
                    -- Очищено
                end
            end)
        end
    end)
end

-- ============================================================================
-- БЛОКИРОВКА ИНВЕРСИИ УПРАВЛЕНИЯ
-- ============================================================================

local function blockInvertedControls()
    if not CONFIG.BLOCK_INVERTED_CONTROLS then return end
    
    -- ГЛАВНАЯ ЗАЩИТА: Мониторим и восстанавливаем moveFunction
    task.spawn(function()
        pcall(function()
            local playerScripts = localPlayer:WaitForChild("PlayerScripts", 10)
            if not playerScripts then return end
            
            local playerModule = playerScripts:WaitForChild("PlayerModule", 10)
            if not playerModule then return end
            
            -- Получаем Controls
            local controls = require(playerModule):GetControls()
            if not controls then return end
            
            -- Сохраняем оригинальную moveFunction
            local originalMoveFunction = controls.moveFunction
            
            -- ПОСТОЯННАЯ проверка - если функция изменилась, возвращаем оригинальную
            RunService.Heartbeat:Connect(function()
                pcall(function()
                    if controls.moveFunction ~= originalMoveFunction then
                        -- Функция изменена (инверсия применена) - восстанавливаем
                        controls.moveFunction = originalMoveFunction
                        stats.blockedInversion = stats.blockedInversion + 1
                    end
                end)
            end)
        end)
    end)
end

-- ============================================================================
-- ДОПОЛНИТЕЛЬНАЯ ЗАЩИТА
-- ============================================================================

local function additionalProtection()
    -- Защита Humanoid.CameraOffset (иногда используется для shake)
    local function protectCharacter(character)
        local humanoid = character:WaitForChild("Humanoid", 5)
        
        if humanoid then
            local humanoidMt = getrawmetatable(humanoid)
            setreadonly(humanoidMt, false)
            local oldHumanoidNewIndex = humanoidMt.__newindex
            
            humanoidMt.__newindex = newcclosure(function(self, key, value)
                if key == "CameraOffset" and CONFIG.BLOCK_CAMERA_SHAKE then
                    -- ПОЛНАЯ БЛОКИРОВКА CameraOffset - разрешаем только Vector3.zero
                    if value ~= Vector3.new(0, 0, 0) then
                        stats.blockedShake = stats.blockedShake + 1
                        return
                    end
                end
                return oldHumanoidNewIndex(self, key, value)
            end)
            
            setreadonly(humanoidMt, true)
            
            -- АГРЕССИВНЫЙ сброс CameraOffset каждый кадр
            RunService.RenderStepped:Connect(function()
                if humanoid and humanoid.Parent and humanoid.CameraOffset ~= Vector3.new(0, 0, 0) then
                    pcall(function()
                        humanoid.CameraOffset = Vector3.new(0, 0, 0)
                    end)
                end
            end)
        end
    end
    
    -- Защищаем текущего персонажа
    if localPlayer.Character then
        protectCharacter(localPlayer.Character)
    end
    
    -- Защищаем будущих персонажей (после респавна)
    localPlayer.CharacterAdded:Connect(function(character)
        protectCharacter(character)
    end)
end

-- ============================================================================
-- GUI ДЛЯ СТАТИСТИКИ (опционально)
-- ============================================================================

local function createStatsGUI()
    -- ЗАЩИТА: Используем gethui() или CoreGui с рандомным именем
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = generateRandomName() -- рандомное имя
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 9999
    screenGui:SetAttribute("_isCameraProtectionGui", true) -- для идентификации
    
    local frame = Instance.new("Frame")
    frame.Name = generateRandomName()
    frame.Size = UDim2.new(0, 220, 0, 130)
    frame.Position = UDim2.new(1, -230, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BorderSizePixel = 0
    frame.BackgroundTransparency = 0.3
    frame.Parent = screenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Name = generateRandomName()
    title.Size = UDim2.new(1, 0, 0, 25)
    title.BackgroundTransparency = 1
    title.Text = "🛡️ Camera Protection"
    title.TextColor3 = Color3.fromRGB(100, 255, 100)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.Parent = frame
    
    local statsLabel = Instance.new("TextLabel")
    statsLabel.Name = generateRandomName()
    statsLabel.Size = UDim2.new(1, -10, 1, -30)
    statsLabel.Position = UDim2.new(0, 5, 0, 25)
    statsLabel.BackgroundTransparency = 1
    statsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    statsLabel.TextSize = 11
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.TextYAlignment = Enum.TextYAlignment.Top
    statsLabel.Parent = frame
    
    -- Обновление статистики каждые 0.5 секунд
    task.spawn(function()
        while task.wait(0.5) do
            local text = string.format(
                "FOV Changes: %d\nBlur Effects: %d\nColor Correction: %d\nCamera Shake: %d\nScreen Effects: %d\nInverted Controls: %d\n\nStatus: Active ✓",
                stats.blockedFOV,
                stats.blockedBlur,
                stats.blockedColorCorrection,
                stats.blockedShake,
                stats.blockedScreenEffects,
                stats.blockedInversion
            )
            statsLabel.Text = text
        end
    end)
    
    -- ЗАЩИТА: Используем gethui() или CoreGui
    if protectedGuiContainer then
        screenGui.Parent = protectedGuiContainer
    else
        screenGui.Parent = CoreGui
    end
    
    return screenGui
end

-- ============================================================================
-- ИНИЦИАЛИЗАЦИЯ
-- ============================================================================

local function initialize()
    print("[Camera Protection] Initializing...")
    
    -- Применяем все защиты
    protectFOV()
    blockLightingEffects()
    blockCameraShake()
    blockScreenEffects()
    blockInvertedControls()
    additionalProtection()
    
    -- Создаем GUI со статистикой (опционально)
    -- createStatsGUI()
    
    -- Финальное сообщение
    task.wait(1)
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Camera Protection",
        Text = "All camera effects disabled ✓",
        Duration = 3,
    })
end

-- Запуск
initialize()

-- Экспорт для внешнего использования
return {
    Stats = stats,
    Config = CONFIG,
    CreateGUI = createStatsGUI,
}
