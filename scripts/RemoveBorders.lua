task.wait(3) -- Group 1: Map modifications

--[[
    RemoveBorders
    Purpose: Remove ONLY invisible borders and add walkable ramps on green edges
    Created: 2025-12-29
    [PROTECTED] - Защита от античита через рандомизацию имён
]]

local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

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
    
    -- Последний fallback - nil (для 3D объектов используем workspace)
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

-- Безопасное изменение свойства с pcall
local function safeSetProperty(instance, property, value)
    pcall(function()
        instance[property] = value
    end)
end

-- ============== КОНФИГУРАЦИЯ ==============

local RAMP_WIDTH = 90 -- Ширина рампы (увеличена ещё в 3 раза)
local RAMP_HEIGHT = 15 -- Высота наклона рампы
local RAMP_COLOR = Color3.fromRGB(100, 200, 255) -- Голубоватый стеклянный цвет
local RAMP_MATERIAL = Enum.Material.Glass -- Стеклянная текстура
local RAMP_TRANSPARENCY = 0.6 -- Полупрозрачность
local RAMP_REFLECTANCE = 0.3 -- Отражение для стекла
local OUTLINE_COLOR = Color3.fromRGB(0, 255, 200) -- Цвет обводки (бирюзовый)
local OUTLINE_TRANSPARENCY = 0.3 -- Прозрачность обводки

local createdRamps = {}

-- Отключить коллизию у части Border
local function disableBorderPart(part)
    if part:IsA("BasePart") then
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
    end
end

-- Удаление коллизий у всех Border частей (через тег и папки)
local function removeInvisibleBorders()
    local map = workspace:FindFirstChild("Map")
    
    -- 1. Через CollectionService тег "Border" (самый надёжный способ)
    for _, part in pairs(CollectionService:GetTagged("Border")) do
        disableBorderPart(part)
    end
    
    -- 2. Мониторим появление новых Border частей
    CollectionService:GetInstanceAddedSignal("Border"):Connect(function(part)
        disableBorderPart(part)
    end)
    
    if not map then return end
    
    -- 3. Также проверяем папку Borders напрямую (на всякий случай)
    local borders = map:FindFirstChild("Borders")
    if borders then
        for _, part in pairs(borders:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency >= 0.9 then
                disableBorderPart(part)
            end
        end
        -- Мониторим новые части в папке Borders
        borders.DescendantAdded:Connect(function(part)
            if part:IsA("BasePart") then
                task.wait(0.1)
                disableBorderPart(part)
            end
        end)
    end
    
    -- 4. Collisions - только невидимые
    local collisions = map:FindFirstChild("Collisions")
    if collisions then
        for _, part in pairs(collisions:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency >= 0.9 then
                disableBorderPart(part)
            end
        end
        collisions.DescendantAdded:Connect(function(part)
            if part:IsA("BasePart") and part.Transparency >= 0.9 then
                task.wait(0.1)
                disableBorderPart(part)
            end
        end)
    end
end

-- Игровые объекты которые НЕ нужно трогать (механики игры)
local GAME_OBJECTS = {
    "FuseMachine", "CraftingMachine", "Merchant", "Santa Merchant", "BrainrotTrader",
    "Shop", "EventBoard", "AdventCalendar", "Present", "Sounds", "MainHighlight",
    "RenderedMovingAnimals", "ShopNPCRobuxIdle", "ShopNPCCash", "Map", "Players",
    "Camera", "Terrain", "SpawnLocation", "Baseplate",
    "CursedSpinWheels" -- Колёса удачи - игровая механика
}

-- Погодные/визуальные события которые появляются напрямую в workspace
local WEATHER_EVENTS = {
    "RadioactiveMap", "RadioactiveWeather", "RainWeather", "CandyWeather",
    "GalaxyMap", "SchoolMap", "FishingMap", "MapVFX",
    "ChristmasMap", "HalloweenMap", "EasterMap", "EventMap",
    "SnowWeather", "BloodmoonWeather", "GraveyardWeather",
    "MoltenWeather", "TrickOrTreatWeather", "YinYangWeather",
    -- Дополнительные события
    "CursedMap", "FireGoblets",
    "NeonMap", "DarkMap", "GlitchMap", "SpaceMap",
    "UnderwaterMap", "LavaMap", "IceMap", "DesertMap",
    "JungleMap", "CaveMap", "SkyMap", "VoidMap"
}

-- Проверить является ли объект погодным событием (workspace)
local function isWeatherEvent(obj)
    if not obj then return false end
    local name = obj.Name
    
    -- Проверяем не является ли это игровым объектом
    for _, gameName in pairs(GAME_OBJECTS) do
        if name == gameName then
            return false
        end
    end
    
    -- Основная карта игры (только если содержит WallModels или Borders)
    if name == "Map" and obj.Parent == workspace then
        if obj:FindFirstChild("WallModels") or obj:FindFirstChild("Borders") then
            return false
        end
    end
    
    -- Проверяем по точному имени
    for _, eventName in pairs(WEATHER_EVENTS) do
        if name == eventName then
            return true
        end
    end
    
    -- Проверяем по суффиксу/паттерну
    if name:find("Weather") or name:find("Radioactive") or name:sub(-3) == "VFX" then
        return true
    end
    
    -- Проверяем папки/модели которые содержат "Map" в названии но НЕ являются основной картой
    -- (основная карта называется просто "Map", а события имеют префикс типа "CursedMap", "GalaxyMap")
    if name ~= "Map" and name:sub(-3) == "Map" then
        -- Дополнительная проверка - это не основная карта (нет WallModels/Borders)
        if not obj:FindFirstChild("WallModels") and not obj:FindFirstChild("Borders") then
            return true
        end
    end
    
    return false
end

-- Проверить является ли часть стеной (не трогать коллизию)
local function isWallPart(part)
    if not part:IsA("BasePart") then return false end
    -- Проверяем тег Wall
    if part:HasTag("Wall") then return true end
    -- Проверяем наличие атрибутов стен (OriginalColor, Side)
    if part:GetAttribute("Side") ~= nil or part:GetAttribute("OriginalColor") ~= nil then return true end
    -- Проверяем находится ли часть в WallModels
    local parent = part.Parent
    while parent and parent ~= workspace do
        if parent.Name == "WallModels" then return true end
        parent = parent.Parent
    end
    return false
end

-- Скрыть и деактивировать событие (не удаляем чтобы не было ошибок)
local function hideEvent(event)
    if not event then return end
    
    for _, part in pairs(event:GetDescendants()) do
        if part:IsA("BasePart") then
            -- НЕ трогаем стены с тегом Wall или в WallModels
            if not isWallPart(part) then
                part.Transparency = 1
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
            end
        elseif part:IsA("Decal") or part:IsA("Texture") then
            part.Transparency = 1
        elseif part:IsA("ParticleEmitter") or part:IsA("Fire") or part:IsA("Smoke") or part:IsA("Sparkles") or part:IsA("Trail") then
            part.Enabled = false
        elseif part:IsA("Light") then
            part.Enabled = false
        elseif part:IsA("Sound") then
            part.Volume = 0
            pcall(function() part:Stop() end)
        elseif part:IsA("BillboardGui") or part:IsA("SurfaceGui") then
            part.Enabled = false
        elseif part:IsA("Beam") then
            part.Enabled = false
        end
    end
    
    -- Также скрываем сам корневой объект если это BasePart
    if event:IsA("BasePart") and not isWallPart(event) then
        event.Transparency = 1
        event.CanCollide = false
        event.CanQuery = false
        event.CanTouch = false
    end
end

-- Скрыть все события (в папке Events и в workspace)
local function hideAllEvents()
    local Lighting = game:GetService("Lighting")
    
    -- 1. ВСЕ содержимое папки Events - скрываем полностью
    local eventsFolder = workspace:FindFirstChild("Events")
    if eventsFolder then
        for _, child in pairs(eventsFolder:GetChildren()) do
            hideEvent(child)
        end
    end
    
    -- 2. Погодные события напрямую в workspace
    for _, child in pairs(workspace:GetChildren()) do
        if isWeatherEvent(child) then
            hideEvent(child)
        end
    end
    
    -- 3. Убираем атмосферу и небо событий из Lighting
    for _, child in pairs(Lighting:GetChildren()) do
        local name = child.Name
        if name:find("Radioactive") or name:find("Rain") or name:find("Snow") or
           name:find("Bloodmoon") or name:find("Galaxy") or name:find("Molten") or
           name:find("Candy") or name:find("Graveyard") or name:find("TrickOrTreat") or
           name:find("YinYang") or name:find("Meowl") or name:find("Christmas") or
           name:find("Halloween") or name:find("Easter") then
            if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("ColorCorrectionEffect") or
               child:IsA("BloomEffect") or child:IsA("BlurEffect") or child:IsA("SunRaysEffect") or
               child:IsA("DepthOfFieldEffect") then
                child:Destroy()
            end
        end
    end
end

-- Скрыть любой объект и все его потомки
local function hideDescendant(descendant)
    if descendant:IsA("BasePart") then
        -- НЕ трогаем стены с тегом Wall или в WallModels
        if isWallPart(descendant) then return end
        descendant.Transparency = 1
        descendant.CanCollide = false
        descendant.CanQuery = false
        descendant.CanTouch = false
    elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
        descendant.Transparency = 1
    elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Fire") or descendant:IsA("Smoke") or descendant:IsA("Sparkles") or descendant:IsA("Trail") then
        descendant.Enabled = false
    elseif descendant:IsA("Light") then
        descendant.Enabled = false
    elseif descendant:IsA("Sound") then
        descendant.Volume = 0
        pcall(function() descendant:Stop() end)
    elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
        descendant.Enabled = false
    elseif descendant:IsA("Beam") then
        descendant.Enabled = false
    end
end

-- Проверить находится ли объект внутри папки Events или погодного события
local function isInsideEvent(obj)
    local parent = obj.Parent
    while parent and parent ~= workspace do
        if parent.Name == "Events" and parent.Parent == workspace then
            return true
        end
        if isWeatherEvent(parent) then
            return true
        end
        parent = parent.Parent
    end
    return false
end

-- Блокировать создание новых событий
local function blockEventCreation()
    -- Функция для настройки мониторинга папки Events (ВСЁ содержимое скрываем)
    local function setupEventsFolderMonitoring(eventsFolder)
        -- Скрываем новые дочерние события
        eventsFolder.ChildAdded:Connect(function(child)
            task.wait(0.1)
            hideEvent(child)
        end)
        
        -- Скрываем ВСЕ новые потомки внутри Events
        eventsFolder.DescendantAdded:Connect(function(descendant)
            task.defer(function()
                hideDescendant(descendant)
            end)
        end)
    end
    
    -- Следим за workspace напрямую
    workspace.ChildAdded:Connect(function(child)
        task.wait(0.1)
        
        if child.Name == "Events" then
            -- Папка Events появилась - скрываем ВСЁ и подключаем мониторинг
            for _, eventChild in pairs(child:GetChildren()) do
                hideEvent(eventChild)
            end
            setupEventsFolderMonitoring(child)
        elseif isWeatherEvent(child) then
            -- Погодное событие (RadioactiveWeather и т.д.)
            task.wait(0.1)
            hideEvent(child)
        end
    end)
    
    -- Следим за папкой Events если она уже существует
    local eventsFolder = workspace:FindFirstChild("Events")
    if eventsFolder then
        setupEventsFolderMonitoring(eventsFolder)
    end
    
    -- Глобальный мониторинг всех новых потомков workspace
    workspace.DescendantAdded:Connect(function(descendant)
        -- Если потомок внутри Events или погодного события - скрываем
        if isInsideEvent(descendant) then
            task.defer(function()
                hideDescendant(descendant)
            end)
        end
    end)
    
    -- Следим за Lighting для удаления атмосферы/неба событий
    local Lighting = game:GetService("Lighting")
    Lighting.ChildAdded:Connect(function(child)
        local name = child.Name
        if name:find("Radioactive") or name:find("Rain") or name:find("Snow") or
           name:find("Bloodmoon") or name:find("Galaxy") or name:find("Molten") or
           name:find("Candy") or name:find("Graveyard") or name:find("TrickOrTreat") or
           name:find("YinYang") or name:find("Meowl") or name:find("Christmas") or
           name:find("Halloween") or name:find("Easter") then
            if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("ColorCorrectionEffect") or
               child:IsA("BloomEffect") or child:IsA("BlurEffect") or child:IsA("SunRaysEffect") or
               child:IsA("DepthOfFieldEffect") then
                task.wait(0.1)
                child:Destroy()
            end
        end
    end)
end

-- Добавить красивую обводку на рампу
local function addRampHighlight(ramp)
    local highlight = Instance.new("Highlight")
    highlight.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
    highlight.Adornee = ramp
    highlight.FillColor = RAMP_COLOR
    highlight.FillTransparency = 0.9 -- Почти невидимая заливка
    highlight.OutlineColor = OUTLINE_COLOR
    highlight.OutlineTransparency = OUTLINE_TRANSPARENCY
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.Parent = ramp
    return highlight
end

-- Включить коллизии на Wall-объектах (видимые стены должны быть непроходимы)
local function enableWallCollisions()
    local map = workspace:FindFirstChild("Map")
    if not map then return end
    
    local count = 0
    
    -- WallModels - все видимые части (Transparency < 0.9)
    local wallModels = map:FindFirstChild("WallModels")
    if wallModels then
        -- Прямые дети
        for _, part in pairs(wallModels:GetChildren()) do
            if part:IsA("BasePart") and part.Transparency < 0.9 then
                -- Проверяем тег через CollectionService или атрибуты Side/OriginalColor
                local hasWallTag = part:HasTag("Wall") or part:GetAttribute("Side") ~= nil or part:GetAttribute("OriginalColor") ~= nil
                if hasWallTag then
                    part.CanCollide = true
                    count = count + 1
                end
            end
        end
        -- Вложенные части
        for _, part in pairs(wallModels:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 0.9 then
                local hasWallTag = part:HasTag("Wall") or part:GetAttribute("Side") ~= nil or part:GetAttribute("OriginalColor") ~= nil
                if hasWallTag then
                    part.CanCollide = true
                    count = count + 1
                end
            end
        end
    end
    
    -- Также включаем коллизии через CollectionService для всех Wall
    for _, part in pairs(CollectionService:GetTagged("Wall")) do
        if part:IsA("BasePart") and part.Transparency < 0.9 then
            part.CanCollide = true
            count = count + 1
        end
    end
end

-- Найти зелёные выступы для позиционирования рамп (ТОЛЬКО краевые с атрибутом Side)
local function findGreenEdges()
    local map = workspace:FindFirstChild("Map")
    if not map then return {} end
    
    local greenParts = {}
    
    -- Ищем ТОЛЬКО в WallModels - там краевые зелёные части с атрибутом Side
    local wallModels = map:FindFirstChild("WallModels")
    if wallModels then
        for _, part in pairs(wallModels:GetDescendants()) do
            -- Краевые зелёные части имеют тег Grass И атрибут Side
            if part:IsA("BasePart") and part:HasTag("Grass") and part:GetAttribute("Side") ~= nil and part.Transparency < 0.5 then
                table.insert(greenParts, part)
            end
        end
    end
    
    return greenParts
end

-- Ожидать загрузку зелёных частей
local function waitForGreenEdges(timeout)
    timeout = timeout or 30
    local startTime = tick()
    
    while tick() - startTime < timeout do
        local parts = findGreenEdges()
        if #parts > 0 then
            return parts
        end
        task.wait(0.5)
    end
    
    return {}
end

-- Создание рамп на основе зелёных выступов
local function createBorderRamps()
    local map = workspace:FindFirstChild("Map")
    if not map then return end
    
    -- Очищаем старые рампы
    for _, ramp in pairs(createdRamps) do
        if ramp and ramp.Parent then
            ramp:Destroy()
        end
    end
    createdRamps = {}
    
    -- Создаём/очищаем контейнер для рамп (ЗАЩИТА: ищем по атрибуту, не по имени)
    local rampsFolder = nil
    for _, child in pairs(map:GetChildren()) do
        if child:IsA("Folder") and child:GetAttribute("_isRampsFolder") == true then
            rampsFolder = child
            break
        end
    end
    
    if rampsFolder then
        rampsFolder:ClearAllChildren()
    else
        rampsFolder = Instance.new("Folder")
        rampsFolder.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
        rampsFolder:SetAttribute("_isRampsFolder", true) -- Помечаем для идентификации
        rampsFolder.Parent = map
    end
    
    local greenParts = waitForGreenEdges(30)
    
    -- Если части не найдены - не создаём рампы
    if #greenParts == 0 then
        return
    end
    
    -- Определяем границы карты по зелёным выступам
    local minX, maxX = math.huge, -math.huge
    local minZ, maxZ = math.huge, -math.huge
    local greenY = 21 -- Стандартная высота зелёных выступов
    
    for _, part in pairs(greenParts) do
        local pos = part.Position
        local size = part.Size
        
        -- Учитываем поворот для определения реальных границ
        local cf = part.CFrame
        local corners = {
            cf * CFrame.new(size.X/2, 0, size.Z/2),
            cf * CFrame.new(-size.X/2, 0, size.Z/2),
            cf * CFrame.new(size.X/2, 0, -size.Z/2),
            cf * CFrame.new(-size.X/2, 0, -size.Z/2),
        }
        
        for _, corner in pairs(corners) do
            minX = math.min(minX, corner.Position.X)
            maxX = math.max(maxX, corner.Position.X)
            minZ = math.min(minZ, corner.Position.Z)
            maxZ = math.max(maxZ, corner.Position.Z)
        end
        
        greenY = pos.Y + size.Y / 2 -- Верх зелёного выступа
    end
    
    -- Параметры рамп
    -- WedgePart: высокая сторона на -Z (back), низкая на +Z (front)
    -- НИЖНИЙ ВНУТРЕННИЙ угол рампы (ближайший к стене) должен быть на уровне верха зелёного выступа
    -- У WedgePart нижняя грань находится на Y - Height/2
    -- Нам нужно чтобы нижняя грань была на topY
    local topY = greenY -- Верх зелёного выступа
    local rampCenterY = topY + RAMP_HEIGHT / 2 -- Центр так чтобы низ рампы был на topY
    
    -- Длины сторон - увеличиваем чтобы перекрывались на углах (воронка без щелей)
    local lengthX = (maxX - minX) + RAMP_WIDTH * 2
    local lengthZ = (maxZ - minZ) + RAMP_WIDTH * 2
    local centerX = (minX + maxX) / 2
    local centerZ = (minZ + maxZ) / 2
    
    -- Левая сторона (минимальный X) - высокая сторона у карты (minX)
    -- -Z локальный → +X мировой при повороте -90°
    local leftRamp = Instance.new("WedgePart")
    leftRamp.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
    leftRamp:SetAttribute("_rampSide", "left") -- Для идентификации
    leftRamp.Anchored = true
    leftRamp.CanCollide = true
    leftRamp.CastShadow = false
    leftRamp.Color = RAMP_COLOR
    leftRamp.Material = RAMP_MATERIAL
    leftRamp.Transparency = RAMP_TRANSPARENCY
    leftRamp.Reflectance = RAMP_REFLECTANCE
    leftRamp.Size = Vector3.new(lengthZ, RAMP_HEIGHT, RAMP_WIDTH)
    leftRamp.CFrame = CFrame.new(minX - RAMP_WIDTH/2, rampCenterY, centerZ) * CFrame.Angles(0, math.rad(-90), 0)
    leftRamp.Parent = rampsFolder
    addRampHighlight(leftRamp)
    table.insert(createdRamps, leftRamp)
    
    -- Правая сторона (максимальный X) - высокая сторона у карты (maxX)
    -- -Z локальный → -X мировой при повороте 90°
    local rightRamp = Instance.new("WedgePart")
    rightRamp.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
    rightRamp:SetAttribute("_rampSide", "right") -- Для идентификации
    rightRamp.Anchored = true
    rightRamp.CanCollide = true
    rightRamp.CastShadow = false
    rightRamp.Color = RAMP_COLOR
    rightRamp.Material = RAMP_MATERIAL
    rightRamp.Transparency = RAMP_TRANSPARENCY
    rightRamp.Reflectance = RAMP_REFLECTANCE
    rightRamp.Size = Vector3.new(lengthZ, RAMP_HEIGHT, RAMP_WIDTH)
    rightRamp.CFrame = CFrame.new(maxX + RAMP_WIDTH/2, rampCenterY, centerZ) * CFrame.Angles(0, math.rad(90), 0)
    rightRamp.Parent = rampsFolder
    addRampHighlight(rightRamp)
    table.insert(createdRamps, rightRamp)
    
    -- Задняя сторона (минимальный Z) - высокая сторона у карты (minZ)
    -- -Z локальный → +Z мировой при повороте 180°
    local backRamp = Instance.new("WedgePart")
    backRamp.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
    backRamp:SetAttribute("_rampSide", "back") -- Для идентификации
    backRamp.Anchored = true
    backRamp.CanCollide = true
    backRamp.CastShadow = false
    backRamp.Color = RAMP_COLOR
    backRamp.Material = RAMP_MATERIAL
    backRamp.Transparency = RAMP_TRANSPARENCY
    backRamp.Reflectance = RAMP_REFLECTANCE
    backRamp.Size = Vector3.new(lengthX, RAMP_HEIGHT, RAMP_WIDTH)
    backRamp.CFrame = CFrame.new(centerX, rampCenterY, minZ - RAMP_WIDTH/2) * CFrame.Angles(0, math.rad(180), 0)
    backRamp.Parent = rampsFolder
    addRampHighlight(backRamp)
    table.insert(createdRamps, backRamp)
    
    -- Передняя сторона (максимальный Z) - высокая сторона у карты (maxZ)
    -- -Z локальный → -Z мировой при повороте 0°
    local frontRamp = Instance.new("WedgePart")
    frontRamp.Name = generateRandomName() -- ЗАЩИТА: рандомное имя
    frontRamp:SetAttribute("_rampSide", "front") -- Для идентификации
    frontRamp.Anchored = true
    frontRamp.CanCollide = true
    frontRamp.CastShadow = false
    frontRamp.Color = RAMP_COLOR
    frontRamp.Material = RAMP_MATERIAL
    frontRamp.Transparency = RAMP_TRANSPARENCY
    frontRamp.Reflectance = RAMP_REFLECTANCE
    frontRamp.Size = Vector3.new(lengthX, RAMP_HEIGHT, RAMP_WIDTH)
    frontRamp.CFrame = CFrame.new(centerX, rampCenterY, maxZ + RAMP_WIDTH/2) * CFrame.Angles(0, math.rad(0), 0)
    frontRamp.Parent = rampsFolder
    addRampHighlight(frontRamp)
    table.insert(createdRamps, frontRamp)
end

-- Основная инициализация
local function init()
    local map = workspace:WaitForChild("Map", 30)
    if not map then
        return
    end
    
    -- Ждём загрузки компонентов карты
    map:WaitForChild("Borders", 10)
    map:WaitForChild("WallModels", 10)
    
    task.wait(1)
    
    removeInvisibleBorders()
    enableWallCollisions() -- Включаем коллизии на видимых стенах
    hideAllEvents() -- Скрываем все события (не удаляем чтобы не было ошибок)
    blockEventCreation() -- Блокируем создание новых событий
    createBorderRamps()
    
    -- Функция проверки - является ли часть стеной
    local function isWall(part)
        if not part:IsA("BasePart") then return false end
        if part.Transparency >= 0.9 then return false end
        return part:HasTag("Wall") or part:GetAttribute("Side") ~= nil or part:GetAttribute("OriginalColor") ~= nil
    end
    
    -- Мониторим изменения коллизий на стенах и восстанавливаем их
    local wallModels = map:FindFirstChild("WallModels")
    if wallModels then
        -- Защищаем коллизию прямых детей WallModels
        for _, part in pairs(wallModels:GetChildren()) do
            if isWall(part) then
                part.CanCollide = true -- Принудительно включаем
                part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                    if not part.CanCollide then
                        part.CanCollide = true
                    end
                end)
            end
        end
        -- Защищаем коллизию вложенных частей
        for _, part in pairs(wallModels:GetDescendants()) do
            if isWall(part) then
                part.CanCollide = true -- Принудительно включаем
                part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                    if not part.CanCollide then
                        part.CanCollide = true
                    end
                end)
            end
        end
        -- Мониторим новые части в WallModels
        wallModels.DescendantAdded:Connect(function(part)
            task.wait(0.1)
            if isWall(part) then
                part.CanCollide = true
                part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                    if not part.CanCollide then
                        part.CanCollide = true
                    end
                end)
            end
        end)
    end
    
    -- Защищаем коллизию через CollectionService для всех Wall
    for _, part in pairs(CollectionService:GetTagged("Wall")) do
        if part:IsA("BasePart") and part.Transparency < 0.9 then
            part.CanCollide = true -- Принудительно включаем
            part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                if not part.CanCollide then
                    part.CanCollide = true
                end
            end)
        end
    end
    
    -- Мониторим новые части с тегом Wall
    CollectionService:GetInstanceAddedSignal("Wall"):Connect(function(part)
        if part:IsA("BasePart") and part.Transparency < 0.9 then
            task.wait(0.1)
            part.CanCollide = true
            part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                if not part.CanCollide then
                    part.CanCollide = true
                end
            end)
        end
    end)
    
    -- Периодическая проверка и принудительное включение коллизий у стен (каждые 2 секунды)
    task.spawn(function()
        while task.wait(2) do
            local currentMap = workspace:FindFirstChild("Map")
            if currentMap then
                local wm = currentMap:FindFirstChild("WallModels")
                if wm then
                    for _, part in pairs(wm:GetDescendants()) do
                        if part:IsA("BasePart") and part.Transparency < 0.9 then
                            if part:HasTag("Wall") or part:GetAttribute("Side") ~= nil or part:GetAttribute("OriginalColor") ~= nil then
                                if not part.CanCollide then
                                    part.CanCollide = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

init()

-- Мониторинг респавна карты
workspace.ChildAdded:Connect(function(child)
    if child.Name == "Map" then
        task.wait(2)
        init()
    end
end)
