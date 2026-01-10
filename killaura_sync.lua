--[[
    Meowl Greeting - Meowl идёт к игроку, делает Snap и приветствует
    Использует настоящие игровые контроллеры для эффектов
    [PROTECTED] - Использует CoreGui для обхода античита
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

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
    
    -- Последний fallback - PlayerGui
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

-- Безопасный доступ к CoreGui
local SecureContainer = nil
local function getSecureContainer()
    if SecureContainer and SecureContainer.Parent then
        return SecureContainer
    end
    
    -- Пытаемся создать контейнер в CoreGui
    local success, result = pcall(function()
        -- Используем рандомное имя чтобы избежать детекта
        local containerName = generateRandomName()
        local container = Instance.new("Folder")
        container.Name = containerName
        container.Parent = CoreGui
        return container
    end)
    
    if success then
        SecureContainer = result
        return SecureContainer
    end
    
    -- Fallback - используем nil (объекты будут в workspace но с защитой)
    warn("[Protection] CoreGui недоступен, используем альтернативный метод")
    return nil
end

-- Безопасный доступ к GUI в CoreGui
local SecureGuiContainer = nil
local function getSecureGuiContainer()
    if SecureGuiContainer and SecureGuiContainer.Parent then
        return SecureGuiContainer
    end
    
    local success, result = pcall(function()
        local guiName = generateRandomName()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = guiName
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.DisplayOrder = 99999
        screenGui.IgnoreGuiInset = true
        screenGui.Parent = CoreGui
        return screenGui
    end)
    
    if success then
        SecureGuiContainer = result
        return SecureGuiContainer
    end
    
    -- Fallback - используем PlayerGui
    warn("[Protection] CoreGui GUI недоступен, используем PlayerGui")
    return PlayerGui
end

-- Защищённое создание Instance с рандомным именем
local function createSecureInstance(className, properties)
    local success, instance = pcall(function()
        local inst = Instance.new(className)
        -- Устанавливаем рандомное имя если не указано специальное
        if not properties or not properties.Name then
            inst.Name = generateRandomName()
        end
        if properties then
            for prop, value in pairs(properties) do
                pcall(function()
                    inst[prop] = value
                end)
            end
        end
        return inst
    end)
    
    if success then
        return instance
    end
    return nil
end

-- Скрытый контейнер для 3D объектов в workspace (с защитой)
local HiddenWorldContainer = nil
local function getHiddenWorldContainer()
    if HiddenWorldContainer and HiddenWorldContainer.Parent then
        return HiddenWorldContainer
    end
    
    local success, result = pcall(function()
        local container = Instance.new("Folder")
        container.Name = generateRandomName() -- Рандомное имя
        -- Помещаем в Camera чтобы было сложнее найти
        local camera = workspace.CurrentCamera
        if camera then
            container.Parent = camera
        else
            container.Parent = workspace
        end
        return container
    end)
    
    if success then
        HiddenWorldContainer = result
        return HiddenWorldContainer
    end
    
    return workspace
end

-- ============== КОНФИГУРАЦИЯ ==============
local CONFIG = {
    -- Рандомные фразы приветствия (напиши свои!)
    GREETING_PHRASES = {
        "Здарова Пидарас!",
        "Че ты хуй?",
        "Попиздовал!",
        "Еби сучар!",
        "Блядина вернулась!",
        "Ку-ку, хуесос!",
        "Ну и нахуя ты?",
        "Давай ебашь пидор!",
        "Мяу, сука!",
        "Иди воруй нахуй!",
        "Ну хоть так поймал меня?",
        "Кто кого еще поймал хуйлан?",
        "Сосал?",
        "Зарейджбайтил тебя да?",
        "Я кот, а ты просто хуесос!",
        "Ебать я умею да?",
        "Никогда не верил в тебя",
        "Пошел нахуй!",
        "Сутулый хуесос",
        "Ты нахуй видел мою цену?",
        "Мяу-мяу, еблан!",
        "А меня Кайнел напастил!",
        "А кто Берлин то взял?",
        "67 раз сосал",
        "ZOV!! SVO!! GOIDA!!",
    },
    MEOWL_SPEED = 50, -- Скорость Meowl (studs/sec)
    MEOWL_SCALE = 1, -- Масштаб Meowl (1 = как игрок)
    SNAP_DISTANCE = 5, -- На какой дистанции делать Snap
    DIALOG_COLOR = "#ffffff", -- Цвет текста диалога
    TEXT_SCALE_ANIMATION = true, -- Анимация масштаба текста
    
    -- OG ЭФФЕКТЫ
    ENABLE_GLOW = true, -- Свечение
    GLOW_COLOR = Color3.fromRGB(255, 100, 0), -- Оранжевое свечение
    ENABLE_PARTICLES = true, -- Частицы
    ENABLE_TRAIL = true, -- Trail за Meowl
    ENABLE_FIRE = true, -- Огненный эффект
    ENABLE_SPARKLES = true, -- Искры
    
    -- ПОЗЫ И ВРАЩЕНИЕ
    POSE_MODES = {"normal", "spin"}, -- Возможные позы
    SPIN_SPEED = 360, -- Скорость вращения (градусов/сек)
    HEAD_FIRST_FLYING = true, -- Лететь головой вперёд
    
    -- ЛЕВИТАЦИЯ ПОСЛЕ ОСТАНОВКИ
    LEVITATION_ENABLED = true, -- Включить левитацию
    LEVITATION_HEIGHT = 1.5, -- Высота покачивания (студы)
    LEVITATION_SPEED = 2, -- Скорость покачивания (циклов/сек)
}

-- ============== КОНТРОЛЛЕРЫ (загрузятся позже) ==============

local SkullEmojiEffectController
local EffectController
local VFX

-- Функция для безопасной загрузки модуля с retry
local function safeRequire(path, maxRetries, delay)
    maxRetries = maxRetries or 3
    delay = delay or 1
    
    for attempt = 1, maxRetries do
        local success, result = pcall(function()
            return require(path)
        end)
        
        if success then
            return result
        end
        
        if attempt < maxRetries then
            task.wait(delay)
        end
    end
    
    return nil
end

-- Загрузка контроллеров (вызывается после загрузки игры)
local function loadControllers()
    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    if not controllers then return end
    
    -- SkullEmojiEffectController
    local skullController = controllers:FindFirstChild("SkullEmojiEffectController")
    if skullController then
        SkullEmojiEffectController = safeRequire(skullController, 3, 0.5)
    end
    
    -- EffectController
    local effectController = controllers:FindFirstChild("EffectController")
    if effectController then
        EffectController = safeRequire(effectController, 3, 0.5)
    end
    
    -- VFX
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared then
        local vfx = shared:FindFirstChild("VFX")
        if vfx then
            VFX = safeRequire(vfx, 3, 0.5)
        end
    end
end

-- ============== СОЗДАНИЕ МОДЕЛИ MEOWL ==============

local function createMeowlModel()
    local meowlModel = nil
    
    -- Ищем Meowl в Events
    pcall(function()
        local events = workspace:FindFirstChild("Events")
        if events then
            for _, child in events:GetDescendants() do
                if child:IsA("Model") and (child.Name == "Meowl" or child.Name:lower():find("meowl")) then
                    meowlModel = child:Clone()
                    break
                end
            end
        end
    end)
    
    -- Ищем в ReplicatedStorage
    if not meowlModel then
        pcall(function()
            for _, child in ReplicatedStorage:GetDescendants() do
                if child:IsA("Model") and (child.Name == "Meowl" or child.Name:lower():find("meowl")) then
                    meowlModel = child:Clone()
                    break
                end
            end
        end)
    end
    
    -- Ищем в workspace напрямую
    if not meowlModel then
        pcall(function()
            for _, child in workspace:GetDescendants() do
                if child:IsA("Model") and (child.Name == "Meowl" or child.Name:lower():find("meowl")) then
                    meowlModel = child:Clone()
                    break
                end
            end
        end)
    end
    
    -- Если не нашли модель - создаём заглушку кота
    if not meowlModel then
        warn("[MeowlGreeting] Модель Meowl не найдена, создаём заглушку")
        meowlModel = Instance.new("Model")
        meowlModel.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
        
        -- Тело
        local root = Instance.new("Part")
        root.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
        root.Size = Vector3.new(2, 2, 3)
        root.Transparency = 0
        root.BrickColor = BrickColor.new("Dark orange")
        root.Material = Enum.Material.SmoothPlastic
        root.CanCollide = false
        root.Anchored = true
        root.Parent = meowlModel
        
        -- Голова
        local head = Instance.new("Part")
        head.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
        head.Size = Vector3.new(1.5, 1.5, 1.5)
        head.Shape = Enum.PartType.Ball
        head.Position = root.Position + Vector3.new(0, 1.5, 1)
        head.Transparency = 0
        head.BrickColor = BrickColor.new("Dark orange")
        head.Material = Enum.Material.SmoothPlastic
        head.CanCollide = false
        head.Anchored = true
        head.Parent = meowlModel
        
        -- Текст Meowl (BillboardGui с рандомным именем)
        local billboard = Instance.new("BillboardGui")
        billboard.Name = generateRandomName()
        billboard.Size = UDim2.new(4, 0, 2, 0)
        billboard.StudsOffset = Vector3.new(0, 2, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = head
        
        local label = Instance.new("TextLabel")
        label.Name = generateRandomName()
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Text = "🐱 MEOWL"
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard
        
        meowlModel.PrimaryPart = root
    else
        -- ЗАЩИТА: меняем имя клонированной модели на рандомное
        meowlModel.Name = generateRandomName()
        
        -- Меняем имена всех частей на рандомные для защиты
        for _, child in meowlModel:GetDescendants() do
            if child:IsA("BasePart") or child:IsA("Model") then
                local oldName = child.Name
                -- Сохраняем ссылку на PrimaryPart
                if child == meowlModel.PrimaryPart then
                    child.Name = generateRandomName()
                elseif oldName == "HumanoidRootPart" then
                    -- Сохраняем HumanoidRootPart для совместимости
                    -- но меняем другие части
                else
                    child.Name = generateRandomName()
                end
            end
        end
        
        if not meowlModel.PrimaryPart then
            local hrp = meowlModel:FindFirstChild("HumanoidRootPart")
            if hrp then
                meowlModel.PrimaryPart = hrp
            else
                for _, part in meowlModel:GetDescendants() do
                    if part:IsA("BasePart") then
                        meowlModel.PrimaryPart = part
                        break
                    end
                end
            end
        end
    end
    
    return meowlModel
end

-- ============== ДОБАВЛЕНИЕ OG ЭФФЕКТОВ ==============

local function addOGEffects(meowlModel)
    local primaryPart = meowlModel.PrimaryPart
    if not primaryPart then return end
    
    -- 1. СВЕЧЕНИЕ (PointLight)
    if CONFIG.ENABLE_GLOW then
        local light = Instance.new("PointLight")
        light.Name = generateRandomName() -- ЗАЩИТА
        light.Color = CONFIG.GLOW_COLOR
        light.Brightness = 3
        light.Range = 20
        light.Shadows = true
        light.Parent = primaryPart
        
        -- Пульсирующее свечение
        task.spawn(function()
            while meowlModel.Parent do
                for i = 1, 10 do
                    pcall(function()
                        light.Brightness = 2 + math.sin(i * 0.3) * 1.5
                    end)
                    task.wait(0.05)
                end
            end
        end)
    end
    
    -- 2. ОГНЕННЫЕ ЧАСТИЦЫ
    if CONFIG.ENABLE_FIRE then
        local fire = Instance.new("Fire")
        fire.Name = generateRandomName() -- ЗАЩИТА
        fire.Color = Color3.fromRGB(255, 100, 0)
        fire.SecondaryColor = Color3.fromRGB(255, 50, 0)
        fire.Size = 5
        fire.Heat = 10
        fire.Parent = primaryPart
    end
    
    -- 3. ИСКРЫ
    if CONFIG.ENABLE_SPARKLES then
        local sparkles = Instance.new("Sparkles")
        sparkles.Name = generateRandomName() -- ЗАЩИТА
        sparkles.SparkleColor = Color3.fromRGB(255, 200, 100)
        sparkles.Parent = primaryPart
    end
    
    -- 4. ЧАСТИЦЫ (ParticleEmitter)
    if CONFIG.ENABLE_PARTICLES then
        local particles = Instance.new("ParticleEmitter")
        particles.Name = generateRandomName() -- ЗАЩИТА
        particles.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 50)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 0))
        })
        particles.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(0.5, 1),
            NumberSequenceKeypoint.new(1, 0)
        })
        particles.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.8, 0.5),
            NumberSequenceKeypoint.new(1, 1)
        })
        particles.Lifetime = NumberRange.new(0.5, 1.5)
        particles.Rate = 50
        particles.Speed = NumberRange.new(3, 8)
        particles.SpreadAngle = Vector2.new(180, 180)
        particles.RotSpeed = NumberRange.new(-180, 180)
        particles.LightEmission = 1
        particles.LightInfluence = 0
        particles.Parent = primaryPart
        
        -- Дополнительные магические частицы
        local magicParticles = Instance.new("ParticleEmitter")
        magicParticles.Name = generateRandomName() -- ЗАЩИТА
        magicParticles.Texture = "rbxassetid://243660364" -- Звёздочки
        magicParticles.Color = ColorSequence.new(Color3.fromRGB(255, 255, 100))
        magicParticles.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(0.5, 0.5),
            NumberSequenceKeypoint.new(1, 0)
        })
        magicParticles.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1)
        })
        magicParticles.Lifetime = NumberRange.new(1, 2)
        magicParticles.Rate = 20
        magicParticles.Speed = NumberRange.new(1, 3)
        magicParticles.SpreadAngle = Vector2.new(360, 360)
        magicParticles.LightEmission = 1
        magicParticles.Parent = primaryPart
    end
    
    -- 5. TRAIL ЭФФЕКТ
    if CONFIG.ENABLE_TRAIL then
        -- Создаём Attachment для Trail
        local attachment0 = Instance.new("Attachment")
        attachment0.Name = generateRandomName() -- ЗАЩИТА
        attachment0.Position = Vector3.new(0, 2, 0)
        attachment0.Parent = primaryPart
        
        local attachment1 = Instance.new("Attachment")
        attachment1.Name = generateRandomName() -- ЗАЩИТА
        attachment1.Position = Vector3.new(0, -2, 0)
        attachment1.Parent = primaryPart
        
        local trail = Instance.new("Trail")
        trail.Name = generateRandomName() -- ЗАЩИТА
        trail.Attachment0 = attachment0
        trail.Attachment1 = attachment1
        trail.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 50, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 0, 0))
        })
        trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1, 1)
        })
        trail.Lifetime = 0.8
        trail.MinLength = 0.1
        trail.FaceCamera = true
        trail.LightEmission = 0.8
        trail.Parent = primaryPart
    end
    
    -- 6. AURA/BEAM эффект вокруг
    local auraAttachment = Instance.new("Attachment")
    auraAttachment.Name = generateRandomName() -- ЗАЩИТА
    auraAttachment.Parent = primaryPart
    
    local beam = Instance.new("ParticleEmitter")
    beam.Name = generateRandomName() -- ЗАЩИТА
    beam.Texture = "rbxassetid://241876428" -- Круглая текстура
    beam.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 100))
    })
    beam.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 3),
        NumberSequenceKeypoint.new(0.5, 4),
        NumberSequenceKeypoint.new(1, 3)
    })
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.7),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 0.7)
    })
    beam.Lifetime = NumberRange.new(0.3, 0.5)
    beam.Rate = 30
    beam.Speed = NumberRange.new(0, 0)
    beam.RotSpeed = NumberRange.new(100, 200)
    beam.LightEmission = 1
    beam.Parent = primaryPart
end

-- ============== ЗАГРУЗКА АНИМАЦИЙ ==============

local function loadAnimations(meowlModel)
    local animations = { walk = nil, snap = nil }
    local animator = nil
    
    -- Создаём Humanoid если нет
    local humanoid = meowlModel:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = Instance.new("Humanoid")
        humanoid.Name = generateRandomName() -- ЗАЩИТА
        humanoid.Parent = meowlModel
    end
    
    -- Создаём Animator
    animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Name = generateRandomName() -- ЗАЩИТА
        animator.Parent = humanoid
    end
    
    -- Загружаем анимации из Phase_5_Sammy_Snap
    pcall(function()
        local controllers = ReplicatedStorage:FindFirstChild("Controllers")
        if controllers then
            local eventController = controllers:FindFirstChild("EventController")
            if eventController then
                local events = eventController:FindFirstChild("Events")
                if events then
                    local sammySnap = events:FindFirstChild("Phase_5_Sammy_Snap")
                    if sammySnap then
                        local walkAnim = sammySnap:FindFirstChild("WalkAnimation")
                        local snapAnim = sammySnap:FindFirstChild("SnapAnimation")
                        
                        if walkAnim then
                            animations.walk = animator:LoadAnimation(walkAnim)
                            animations.walk.Looped = true
                        end
                        
                        if snapAnim then
                            animations.snap = animator:LoadAnimation(snapAnim)
                            animations.snap.Looped = false
                        end
                    end
                end
            end
        end
    end)
    
    return animations
end

-- ============== СОЗДАНИЕ ДИАЛОГА ==============

local function createDialogGui()
    -- ЗАЩИТА: Используем gethui() или CoreGui для максимальной защиты
    local protectedContainer = getProtectedGui()
    
    local dialogGui = Instance.new("ScreenGui")
    dialogGui.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
    dialogGui.ResetOnSpawn = false
    dialogGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    dialogGui.DisplayOrder = 99
    dialogGui.Parent = protectedContainer
    
    local dialogLabel = Instance.new("TextLabel")
    dialogLabel.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
    dialogLabel.Size = UDim2.new(0.8, 0, 0.1, 0)
    dialogLabel.Position = UDim2.fromScale(0.5, 0.25)
    dialogLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    dialogLabel.BackgroundTransparency = 1
    dialogLabel.Font = Enum.Font.GothamBold
    dialogLabel.TextSize = 48
    dialogLabel.TextColor3 = Color3.fromHex(CONFIG.DIALOG_COLOR)
    dialogLabel.TextStrokeTransparency = 0.3
    dialogLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    dialogLabel.Text = ""
    dialogLabel.TextTransparency = 1
    dialogLabel.RichText = false -- Отключаем чтобы не было проблем с русским текстом
    dialogLabel.Parent = dialogGui
    
    local stroke = Instance.new("UIStroke")
    stroke.Name = generateRandomName() -- ЗАЩИТА
    stroke.Color = Color3.new(0, 0, 0)
    stroke.Thickness = 3
    stroke.Transparency = 1
    stroke.Parent = dialogLabel
    
    if CONFIG.TEXT_SCALE_ANIMATION then
        local scale = Instance.new("UIScale")
        scale.Name = generateRandomName() -- ЗАЩИТА
        scale.Scale = 0
        scale.Parent = dialogLabel
    end
    
    return dialogGui, dialogLabel
end

-- ============== ВОСПРОИЗВЕДЕНИЕ ДИАЛОГА ==============

-- UTF-8 безопасная функция для получения подстроки
local function utf8sub(str, startChar, endChar)
    local startByte = 1
    local endByte = #str
    
    local charCount = 0
    local bytePos = 1
    
    while bytePos <= #str do
        charCount = charCount + 1
        
        if charCount == startChar then
            startByte = bytePos
        end
        
        -- Определяем длину UTF-8 символа
        local byte = string.byte(str, bytePos)
        local charLen = 1
        if byte >= 0xC0 and byte < 0xE0 then
            charLen = 2
        elseif byte >= 0xE0 and byte < 0xF0 then
            charLen = 3
        elseif byte >= 0xF0 then
            charLen = 4
        end
        
        if charCount == endChar then
            endByte = bytePos + charLen - 1
            break
        end
        
        bytePos = bytePos + charLen
    end
    
    return string.sub(str, startByte, endByte)
end

-- Подсчёт UTF-8 символов в строке
local function utf8len(str)
    local len = 0
    local bytePos = 1
    
    while bytePos <= #str do
        len = len + 1
        local byte = string.byte(str, bytePos)
        
        if byte >= 0xC0 and byte < 0xE0 then
            bytePos = bytePos + 2
        elseif byte >= 0xE0 and byte < 0xF0 then
            bytePos = bytePos + 3
        elseif byte >= 0xF0 then
            bytePos = bytePos + 4
        else
            bytePos = bytePos + 1
        end
    end
    
    return len
end

local function playDialogEffect(dialogLabel)
    -- ЗАЩИТА: Вся функция обёрнута в pcall
    pcall(function()
        -- Выбираем случайную фразу
        local phrases = CONFIG.GREETING_PHRASES
        local fullText = phrases[math.random(1, #phrases)]
        local textLength = utf8len(fullText) -- Используем UTF-8 длину
        
        -- Показываем текст
        pcall(function()
            if dialogLabel and dialogLabel.Parent then
                dialogLabel.TextTransparency = 0
            end
        end)
        
        pcall(function()
            local stroke = dialogLabel:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Transparency = 0.2 end
        end)
        
        -- Анимация масштаба (РУЧНАЯ - без TweenService)
        if CONFIG.TEXT_SCALE_ANIMATION then
            pcall(function()
                local scale = dialogLabel:FindFirstChildOfClass("UIScale")
                if scale then
                    -- Анимация увеличения
                    task.spawn(function()
                        for i = 1, 8 do
                            pcall(function()
                                if scale and scale.Parent then
                                    scale.Scale = 1 + (i * 0.025) -- до 1.2
                                end
                            end)
                            task.wait(0.05)
                        end
                        -- Возврат к 1
                        task.wait(0.1)
                        for i = 8, 0, -1 do
                            pcall(function()
                                if scale and scale.Parent then
                                    scale.Scale = 1 + (i * 0.025)
                                end
                            end)
                            task.wait(0.025)
                        end
                    end)
                end
            end)
        end
        
        -- Звук печати
        pcall(function()
            local sfx = ReplicatedStorage.Sounds.Sfx
            local typeSound = sfx and sfx:FindFirstChild("Type")
            if typeSound then
                for i = 1, textLength do
                    task.delay(i * 0.05, function()
                        pcall(function()
                            local clone = typeSound:Clone()
                            clone.Parent = sfx
                            clone:Play()
                            Debris:AddItem(clone, 1)
                        end)
                    end)
                end
            end
        end)
        
        -- Эффект печати текста (UTF-8 безопасный)
        for i = 1, textLength do
            pcall(function()
                if dialogLabel and dialogLabel.Parent then
                    dialogLabel.Text = utf8sub(fullText, 1, i)
                end
            end)
            task.wait(0.05)
        end
    end)
end

-- ============== ИСЧЕЗНОВЕНИЕ ДИАЛОГА ==============

local function fadeOutDialog(dialogLabel)
    -- ЗАЩИТА: Вся функция обёрнута в pcall для избежания ошибок с gethui/CoreGui
    pcall(function()
        -- Анимация текста
        task.spawn(function()
            for i = 1, 10 do
                pcall(function()
                    if dialogLabel and dialogLabel.Parent then
                        dialogLabel.TextTransparency = i / 10
                    end
                end)
                task.wait(0.05)
            end
        end)
        
        -- Анимация stroke
        pcall(function()
            local stroke = dialogLabel:FindFirstChildOfClass("UIStroke")
            if stroke then
                task.spawn(function()
                    for i = 1, 10 do
                        pcall(function()
                            if stroke and stroke.Parent then
                                stroke.Transparency = i / 10
                            end
                        end)
                        task.wait(0.05)
                    end
                end)
            end
        end)
        
        -- Анимация scale
        pcall(function()
            local scale = dialogLabel:FindFirstChildOfClass("UIScale")
            if scale then
                task.spawn(function()
                    for i = 10, 0, -1 do
                        pcall(function()
                            if scale and scale.Parent then
                                scale.Scale = i / 10
                            end
                        end)
                        task.wait(0.05)
                    end
                end)
            end
        end)
    end)
end

-- ============== ГЛАВНАЯ ФУНКЦИЯ ==============

local function playMeowlGreeting()
    local character = LocalPlayer.Character
    if not character then return end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end
    
    -- Создаём модель Meowl
    local meowlModel = createMeowlModel()
    if not meowlModel then
        warn("[MeowlGreeting] Не удалось создать модель Meowl")
        return
    end
    
    local playerPos = humanoidRootPart.Position
    local playerLook = humanoidRootPart.CFrame.LookVector
    local playerY = playerPos.Y -- Запоминаем высоту игрока
    
    -- Meowl спавнится СЗАДИ игрока на расстоянии 50 студов (на той же высоте!)
    local spawnDistance = 100
    -- Используем ПРОТИВОПОЛОЖНОЕ горизонтальное направление взгляда (спина игрока)
    local horizontalLook = Vector3.new(-playerLook.X, 0, -playerLook.Z).Unit
    local startPos = Vector3.new(
        playerPos.X + (horizontalLook.X * spawnDistance),
        playerY, -- Точно та же высота что и игрок
        playerPos.Z + (horizontalLook.Z * spawnDistance)
    )
    
    -- Размещаем Meowl
    meowlModel.Name = generateRandomName() -- ЗАЩИТА: рандомное имя вместо "MeowlGreeting_Visual"
    
    -- ЗАЩИТА: Помещаем модель в скрытый контейнер (Camera) вместо workspace напрямую
    local hiddenContainer = getHiddenWorldContainer()
    meowlModel.Parent = hiddenContainer
    
    -- Делаем все части Anchored, проходим сквозь всё, НО сохраняем оригинальную прозрачность
    local partCount = 0
    for _, part in meowlModel:GetDescendants() do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
        end
    end
    
    if meowlModel.PrimaryPart then
        local lookAtPlayer = CFrame.lookAt(startPos, Vector3.new(playerPos.X, startPos.Y, playerPos.Z))
        meowlModel:PivotTo(lookAtPlayer)
    else
        for _, part in meowlModel:GetDescendants() do
            if part:IsA("BasePart") then
                meowlModel.PrimaryPart = part
                part.CFrame = CFrame.lookAt(startPos, Vector3.new(playerPos.X, startPos.Y, playerPos.Z))
                break
            end
        end
    end
    
    -- Масштабируем если нужно
    if CONFIG.MEOWL_SCALE ~= 1 then
        pcall(function()
            meowlModel:ScaleTo(CONFIG.MEOWL_SCALE)
        end)
    end
    
    -- ДОБАВЛЯЕМ OG ЭФФЕКТЫ!
    addOGEffects(meowlModel)
    
    -- Загружаем анимации
    local animations = loadAnimations(meowlModel)
    
    if animations.walk then
        animations.walk:Play()
    end
    
    -- Звук ходьбы
    local walkSound = nil
    pcall(function()
        local sounds = ReplicatedStorage:FindFirstChild("Sounds")
        if sounds then
            local events = sounds:FindFirstChild("Events")
            if events then
                local sammySnap = events:FindFirstChild("Phase 5: Sammy Snap")
                if sammySnap then
                    local walk = sammySnap:FindFirstChild("Walk")
                    if walk then
                        walkSound = walk:Clone()
                        walkSound.Looped = true
                        if meowlModel.PrimaryPart then
                            walkSound.Parent = meowlModel.PrimaryPart
                            walkSound:Play()
                        end
                    end
                end
            end
        end
    end)
    
    local dialogGui, dialogLabel = createDialogGui()
    local currentPos = startPos
    local reachedPlayer = false
    local walkConnection
    
    -- Выбираем случайную позу для полёта и после остановки
    local flyingPose = CONFIG.POSE_MODES[math.random(1, #CONFIG.POSE_MODES)]
    local finalPose = CONFIG.POSE_MODES[math.random(1, #CONFIG.POSE_MODES)]
    local spinAngle = 0 -- Угол для спина
    local flyTime = 0 -- Время полёта для анимаций
    
    -- Meowl преследует игрока пока не достигнет SNAP_DISTANCE
    walkConnection = RunService.RenderStepped:Connect(function(deltaTime)
        if reachedPlayer then return end
        
        flyTime = flyTime + deltaTime
        
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        
        local targetPos = hrp.Position
        local targetY = targetPos.Y -- Высота игрока
        
        -- Вычисляем только ГОРИЗОНТАЛЬНОЕ расстояние и направление
        local horizontalTarget = Vector3.new(targetPos.X, 0, targetPos.Z)
        local horizontalCurrent = Vector3.new(currentPos.X, 0, currentPos.Z)
        local direction = (horizontalTarget - horizontalCurrent)
        local distance = direction.Magnitude -- Только горизонтальная дистанция
        
        -- Проверяем достигли ли игрока (по горизонтали)
        if distance <= CONFIG.SNAP_DISTANCE then
            reachedPlayer = true
            walkConnection:Disconnect()
            
            -- Останавливаем ходьбу
            if animations.walk then animations.walk:Stop() end
            if walkSound then walkSound:Stop() end
            
            -- Проверяем двигается ли игрок
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            local isPlayerMoving = humanoid and humanoid.MoveDirection.Magnitude > 0.1
            
            -- Определяем финальную позицию
            local finalStopPos = currentPos
            
            -- Если игрок стоит - становимся ПЕРЕД ним
            if not isPlayerMoving then
                local playerLookDir = hrp.CFrame.LookVector
                local horizontalLookDir = Vector3.new(playerLookDir.X, 0, playerLookDir.Z).Unit
                -- Позиция перед игроком на расстоянии SNAP_DISTANCE
                finalStopPos = Vector3.new(
                    targetPos.X + (horizontalLookDir.X * CONFIG.SNAP_DISTANCE),
                    targetY,
                    targetPos.Z + (horizontalLookDir.Z * CONFIG.SNAP_DISTANCE)
                )
                -- Мгновенно перемещаемся в позицию перед игроком
                currentPos = finalStopPos
            end
            
            -- Запоминаем базовую позицию для левитации
            local baseStopPos = finalStopPos
            local levitationConnection
            
            -- Запускаем левитацию и слежение за игроком
            if CONFIG.LEVITATION_ENABLED and meowlModel.PrimaryPart then
                local levitationTime = 0
                levitationConnection = RunService.RenderStepped:Connect(function(dt)
                    if not meowlModel.Parent then
                        levitationConnection:Disconnect()
                        return
                    end
                    
                    levitationTime = levitationTime + dt
                    
                    -- Получаем актуальную позицию игрока
                    local char = LocalPlayer.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local playerPosition = hrp and hrp.Position or targetPos
                    
                    -- Вычисляем смещение левитации (синусоида)
                    local levitationOffset = math.sin(levitationTime * CONFIG.LEVITATION_SPEED * math.pi * 2) * CONFIG.LEVITATION_HEIGHT
                    
                    -- Новая позиция с левитацией
                    local newY = baseStopPos.Y + levitationOffset
                    local levitatingPos = Vector3.new(baseStopPos.X, newY, baseStopPos.Z)
                    
                    -- Всегда смотрим на игрока
                    local lookAtCFrame = CFrame.lookAt(levitatingPos, Vector3.new(playerPosition.X, newY, playerPosition.Z))
                    
                    -- Применяем спин если выбран
                    if finalPose == "spin" then
                        local rotation = CFrame.Angles(0, math.rad(levitationTime * CONFIG.SPIN_SPEED), 0)
                        lookAtCFrame = lookAtCFrame * rotation
                    end
                    
                    meowlModel:PivotTo(lookAtCFrame)
                end)
            elseif meowlModel.PrimaryPart then
                -- Если левитация выключена, просто смотрим на игрока
                local lookAt = CFrame.lookAt(currentPos, Vector3.new(targetPos.X, targetY, targetPos.Z))
                meowlModel:PivotTo(lookAt)
            end
            
            -- Делаем SNAP!
            task.spawn(function()
                if animations.snap then
                    animations.snap:Play()
                end
                
                task.wait(0.3)
                
                pcall(function()
                    ReplicatedStorage.Sounds.Events["Phase 5: Sammy Snap"].Snap:Play()
                end)
                
                if SkullEmojiEffectController then
                    pcall(function()
                        SkullEmojiEffectController:Play(2.5, "Lower")
                    end)
                end
                
                pcall(function()
                    local leftHand = meowlModel:FindFirstChild("LeftHand", true) or meowlModel:FindFirstChild("Left Arm", true)
                    if VFX and leftHand then
                        local eventScript = ReplicatedStorage.Controllers.EventController.Events["Phase_5_Sammy_Snap"]
                        local snapVFX = eventScript and eventScript:FindFirstChild("Snap")
                        if snapVFX then
                            local vfxClone = snapVFX:Clone()
                            vfxClone.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
                            vfxClone.CFrame = leftHand.CFrame
                            -- ЗАЩИТА: Помещаем VFX в скрытый контейнер
                            local hiddenContainer = getHiddenWorldContainer()
                            vfxClone.Parent = hiddenContainer
                            VFX.emit(vfxClone)
                            Debris:AddItem(vfxClone, 3)
                        end
                    end
                end)
                
                task.spawn(function()
                    playDialogEffect(dialogLabel)
                end)
                
                task.wait(2.5)
                
                if SkullEmojiEffectController then
                    pcall(function() SkullEmojiEffectController:Stop() end)
                end
                
                if EffectController then
                    pcall(function() EffectController:Activate("Blink") end)
                end
                
                fadeOutDialog(dialogLabel)
                
                -- Исчезновение Meowl (РУЧНАЯ анимация - TweenService вызывает ошибки с Camera/CoreGui)
                task.spawn(function()
                    for step = 1, 6 do
                        local transparency = step / 6
                        pcall(function()
                            for _, part in meowlModel:GetDescendants() do
                                if part:IsA("BasePart") then
                                    pcall(function() part.Transparency = transparency end)
                                elseif part:IsA("Decal") or part:IsA("Texture") then
                                    pcall(function() part.Transparency = transparency end)
                                elseif part:IsA("Fire") or part:IsA("Sparkles") then
                                    pcall(function() part.Enabled = false end)
                                elseif part:IsA("ParticleEmitter") then
                                    pcall(function() part.Enabled = false end)
                                elseif part:IsA("Trail") then
                                    pcall(function() part.Enabled = false end)
                                elseif part:IsA("PointLight") then
                                    pcall(function() part.Brightness = part.Brightness * (1 - transparency) end)
                                end
                            end
                        end)
                        task.wait(0.05)
                    end
                end)
                
                -- Исчезновение GUI элементов на Meowl
                task.spawn(function()
                    for step = 1, 6 do
                        local transparency = step / 6
                        pcall(function()
                            for _, gui in meowlModel:GetDescendants() do
                                if gui:IsA("BillboardGui") then
                                    for _, child in gui:GetDescendants() do
                                        if child:IsA("ImageLabel") then
                                            pcall(function() child.ImageTransparency = transparency end)
                                        elseif child:IsA("TextLabel") then
                                            pcall(function() child.TextTransparency = transparency end)
                                        end
                                    end
                                end
                            end
                        end)
                        task.wait(0.05)
                    end
                end)
                
                task.delay(1, function()
                    -- Останавливаем левитацию перед уничтожением
                    pcall(function()
                        if levitationConnection then
                            levitationConnection:Disconnect()
                        end
                    end)
                    pcall(function() meowlModel:Destroy() end)
                    pcall(function() dialogGui:Destroy() end)
                end)
            end)
            
            return
        end
        
        -- Движение к игроку с ускорением (чем дальше - тем быстрее)
        local speed = CONFIG.MEOWL_SPEED
        if distance > 20 then
            speed = speed * (distance / 20) -- Ускоряется пропорционально расстоянию
        end
        
        local moveDistance = speed * deltaTime
        
        -- Двигаемся только по горизонтали
        if distance > 0.01 then -- Избегаем деления на ноль
            local normalizedDir = direction.Unit
            local newX = currentPos.X + (normalizedDir.X * moveDistance)
            local newZ = currentPos.Z + (normalizedDir.Z * moveDistance)
            
            -- Устанавливаем позицию: горизонтально двигаемся, Y ВСЕГДА как у игрока
            currentPos = Vector3.new(newX, targetY, newZ)
        else
            -- Если горизонтально уже близко, просто обновляем высоту
            currentPos = Vector3.new(currentPos.X, targetY, currentPos.Z)
        end
        
        -- Поворот к игроку и применение позы полёта
        if meowlModel.PrimaryPart then
            -- Базовый CFrame - смотрим на игрока
            local lookAt = CFrame.lookAt(currentPos, Vector3.new(targetPos.X, targetY, targetPos.Z))
            
            -- HEAD FIRST - летим головой вперёд (наклон вперёд на 90 градусов)
            if CONFIG.HEAD_FIRST_FLYING then
                lookAt = lookAt * CFrame.Angles(math.rad(-90), 0, 0)
            end
            
            -- Применяем позу полёта
            if flyingPose == "spin" then
                -- Вращаемся во время полёта
                spinAngle = spinAngle + (CONFIG.SPIN_SPEED * deltaTime)
                lookAt = lookAt * CFrame.Angles(0, 0, math.rad(spinAngle))
            end
            -- normal - ничего дополнительного
            
            meowlModel:PivotTo(lookAt)
        end
    end)
end

-- ============== ОЖИДАНИЕ ЗАГРУЗКИ ==============

local function waitForGameLoaded()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    character:WaitForChild("HumanoidRootPart", 10)
    
    -- Ждём загрузки карты
    pcall(function()
        workspace:WaitForChild("Map", 30)
        workspace:WaitForChild("Plots", 30)
        workspace:WaitForChild("Events", 30)
    end)
    
    -- Ждём пока исчезнет экран загрузки
    pcall(function()
        local loadingScreen = PlayerGui:FindFirstChild("LoadingScreen") or PlayerGui:FindFirstChild("Loading")
        if loadingScreen then
            local startWait = tick()
            while loadingScreen and loadingScreen.Parent and loadingScreen.Enabled ~= false do
                if tick() - startWait > 30 then break end
                task.wait(0.2)
                loadingScreen = PlayerGui:FindFirstChild("LoadingScreen") or PlayerGui:FindFirstChild("Loading")
            end
        end
    end)
    
    -- Ждём пока камера станет нормальной
    pcall(function()
        local camera = workspace.CurrentCamera
        if camera then
            local startWait = tick()
            while camera.CameraType == Enum.CameraType.Scriptable and tick() - startWait < 10 do
                task.wait(0.1)
            end
        end
    end)
    
    -- Дополнительная пауза чтобы модули успели инициализироваться
    task.wait(2)
end

-- ============== ОЧИСТКА ПРИ ВЫХОДЕ ==============

local function cleanup()
    pcall(function()
        if SecureContainer and SecureContainer.Parent then
            SecureContainer:Destroy()
        end
    end)
    pcall(function()
        if SecureGuiContainer and SecureGuiContainer.Parent then
            SecureGuiContainer:Destroy()
        end
    end)
    pcall(function()
        if HiddenWorldContainer and HiddenWorldContainer.Parent then
            HiddenWorldContainer:Destroy()
        end
    end)
end

-- Очистка при смерти/респавне персонажа
LocalPlayer.CharacterRemoving:Connect(function()
    -- Небольшая задержка перед очисткой
    task.delay(0.5, cleanup)
end)

-- ============== ЗАПУСК ==============

waitForGameLoaded()
loadControllers() -- Загружаем контроллеры после загрузки игры
playMeowlGreeting()
