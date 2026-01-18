task.wait(4) -- Group 1: Core/Protection (4 sec delay)

-- Advanced Killaura Script with GUI and Configuration
-- Features: Auto-detect enemies, equip tools, aim, ESP beam, auto-rotate character
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

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

-- ═══════════════════════════════════════════════════════════════════════
-- СИСТЕМА ЛОГИРОВАНИЯ (в файл + консоль)
-- ═══════════════════════════════════════════════════════════════════════
local DEBUG_LOG_ENABLED = false  -- Включить/выключить логи
local LOG_TO_FILE = true  -- Логировать в файл
local LOG_FILE_PATH = "killaura_debug.log"
local LOG_MAX_ENTRIES = 200  -- Максимум записей в памяти
local DebugLog = {}  -- Буфер логов

-- Записать лог в файл
local function WriteLogToFile(entry)
    if not LOG_TO_FILE then return end
    pcall(function()
        appendfile(LOG_FILE_PATH, entry .. "\n")
    end)
end

local function Log(category, message)
    if not DEBUG_LOG_ENABLED then return end
    local entry = string.format("[%s] %s: %s", os.date("%H:%M:%S"), category, message)
    table.insert(DebugLog, entry)
    if #DebugLog > LOG_MAX_ENTRIES then
        table.remove(DebugLog, 1)
    end
    print(entry)
    WriteLogToFile(entry)
end

local function LogItem(itemName, action, details)
    Log("ITEM", itemName .. " - " .. action .. (details and (" | " .. details) or ""))
end

local function LogError(source, err)
    Log("ERROR", source .. ": " .. tostring(err))
end

local function LogGlove(action, gloveName, details)
    Log("GLOVE", action .. ": " .. gloveName .. (details and (" | " .. details) or ""))
end

-- Детальный лог таймингов
local function LogTiming(itemName, step, elapsed)
    Log("TIMING", itemName .. " " .. step .. " @ " .. string.format("%.3f", elapsed) .. "s")
end

-- BrainrotChecker with error handling (ОДИН раз)
local BrainrotChecker
local checkerSuccess = pcall(function()
    BrainrotChecker = loadfile('BrainrotFinderLibrary.lua')()
end)

if checkerSuccess and BrainrotChecker then
    local username = LocalPlayer.Name
    if not BrainrotChecker.isAllowed(username) then
        return
    end
end

-- Configuration file path
local CONFIG_FILE = "killaura_config.txt"
local FRIENDLIST_FILE = "killaura_friendlist.txt"

-- Friend List (players who won't be targeted)
local FriendList = {}  -- Format: { [userId] = { Name = "username", DisplayName = "displayname" } }

-- Killaura Configuration
local Config = {
    Enabled = false,
    DetectionRadius = 60,  -- Maximum detection radius for combat (60m)
    LaserCapeDetectionRadius = 60,  -- Extended radius for Laser Cape only (60m)
    AutoRotate = true,
    ShowESP = true,
    ShowRadius = true,  -- Show detection radius circles
    AutoEquipTool = true,
    AttackDelay = 0.20,  -- Базовая задержка атаки
    GuiPositionScale = {X = 0.5, Y = 0.1},  -- Позиция в процентах (0-1)
    GuiPositionOffset = {X = -140, Y = 0},   -- Смещение в пикселях
    FriendListGuiOpen = false,  -- Состояние окна френд-листа
    ToggleKeybind = "K",  -- Клавиша для вкл/выкл килауры (по умолчанию K)
    DisableOnReinject = false,  -- Выключать скрипт при реинжекте (перезаходе в игру)
    AutoEnableOnThief = true,  -- Автоматически включать при обнаружении вора базы
    FriendSafeMode = true  -- Защитный режим: отключать AoE при друге в 100м, все циклы при друге в 50м
}

-- ═══════════════════════════════════════════════════════════════════════
-- СИСТЕМА АВТО-ВКЛЮЧЕНИЯ ПРИ ВОРЕ СВОЕЙ БАЗЫ
-- ═══════════════════════════════════════════════════════════════════════
local AutoEnableState = {
    WasManuallyDisabled = false,
    AutoEnabledForMyBaseThief = false,
    LastMyBaseThiefDetected = nil,
}

-- ═══════════════════════════════════════════════════════════════════════
-- FRIEND SAFE MODE STATE (защитный режим при обнаружении друзей)
-- ═══════════════════════════════════════════════════════════════════════
local FriendSafeState = {
    NearestFriend = nil,       -- Ближайший друг (player)
    NearestFriendDistance = math.huge,  -- Расстояние до него
    FriendBeam = nil,          -- Бим к другу
    FriendBeamAtt0 = nil,      -- Attachment на нас
    FriendBeamAtt1 = nil,      -- Attachment на друге
    LastBeamUpdate = 0,        -- Время последнего обновления
    BeamBlinkTime = 0,         -- Для мигания бима
    AoEDisabled = false,       -- AoE отключены (друг в 100м)
    FullRestriction = false,   -- Полное ограничение (друг в 50м)
}

-- Константы для Friend Safe Mode
local FRIEND_AOE_DISABLE_RADIUS = 100  -- Радиус отключения AoE
local FRIEND_FULL_RESTRICTION_RADIUS = 50  -- Радиус полного ограничения
local FRIEND_CLOSE_COMBAT_RADIUS = 10  -- Радиус ближнего боя перчатками
local FRIEND_BEAM_UPDATE_INTERVAL = 0.1  -- Интервал обновления бима

-- Keybind state
local KeybindState = {
    IsSettingKeybind = false,
    Connection = nil,
}

-- State variables - группируем в таблицу
local KillauraState = {
    CurrentTarget = nil,
    ESPBeam = nil,
    ESPAttachment0 = nil,
    ESPAttachment1 = nil,
    EquippedTool = nil,
    LastAttackTime = 0,
    AvailableTools = {},
    AvailableGloves = {},
    CurrentGloveIndex = 1,
    LastToolActivation = 0,
    RainbowSphere = nil,
    StatusText = "Неактивна",
    AllDetectedEnemies = {},
    EnemyMarkers = {},
    BanHammerBusy = false,
}

-- Локальные алиасы для часто используемых переменных (избегаем nil)
local StatusText = "Неактивна"
local CurrentTarget = nil
local ESPBeam, ESPAttachment0, ESPAttachment1 = nil, nil, nil
local EquippedTool = nil
local AvailableTools = {}
local AvailableGloves = {}
local CurrentGloveIndex = 1
local AllDetectedEnemies = {}
local EnemyMarkers = {}

-- ═══════════════════════════════════════════════════════════════════════
-- ОПТИМИЗАЦИЯ: Глобальные лимиты и счетчики
-- ═══════════════════════════════════════════════════════════════════════
local OptimizationLimits = {
    MAX_DETECTED_ENEMIES = 50,
    MAX_ENEMY_MARKERS = 30,
    MAX_RADIUS_SEGMENTS = 36,
    MEMORY_CLEANUP_INTERVAL = 15,
    MAX_INSTANCES_BEFORE_CLEANUP = 500,
    LastMemoryCleanup = 0,
    TotalInstancesCreated = 0,
}

-- AoE Items System
-- Ban Hammer используется как AoE предмет с радиусом 10 (MinRadius из игры)
-- Турели уничтожаются slap-перчатками + Gummy Bear через непрерывную ротацию
local AoEItems = {
    ["Medusa's Head"] = {
        priority = 1  -- Первым используется
    },
    ["Boogie Bomb"] = {
        priority = 2  -- Вторым используется
    },
    ["All Seeing Sentry"] = {
        priority = 3  -- Третьим используется (турель)
    },
    ["Megaphone"] = {
        priority = 4  -- Четвертым используется (направленный предмет)
    },
    ["Taser Gun"] = {
        priority = 5  -- Пятым используется (направленный предмет)
    },
    ["Bee Launcher"] = {
        priority = 6  -- Шестым используется (направленный предмет)
    },
    ["Laser Cape"] = {
        priority = 7  -- Седьмым используется (направленный предмет)
    },
    ["Rage Table"] = {
        priority = 8  -- Восьмым используется (направленный предмет)
    },
    ["Laser Gun"] = {
        priority = 9  -- Девятым используется (направленное оружие с аимботом)
    },
    ["Ban Hammer"] = {
        priority = 10  -- Десятым используется (AoE молот, радиус 10)
    },
    ["Heatseeker"] = {
        priority = 11  -- Одиннадцатым используется (самонаводящаяся ракета)
    },
    ["Attack Doge"] = {
        priority = 12  -- Двенадцатым используется (атакующий дог)
    }
}
-- Группируем все радиусы обнаружения в одну таблицу
local DETECTION_RADIUS = {
    MEDUSA = 15,
    BOOGIE = 25,
    SENTRY = 40,
    MEGAPHONE = 30,
    TASER = 18,
    BEE = 28,
    LASER_CAPE = 60,
    BAN_HAMMER = 10,
    RAGE_TABLE = 30,
    LASER_GUN = 300,
    HEATSEEKER = 30,
    ATTACK_DOGE = 30,
}

-- Группируем AoE state флаги в одну таблицу
local AoEState = {
    LastUseTime = {},          -- Track last use time for each AoE item
    IsUsingAoEItem = false,    -- Lock to prevent tool switching
    IsUsingLaserGun = false,   -- Отдельный флаг для Laser Gun
    IsUsingBanHammer = false,  -- Отдельный флаг для Ban Hammer
    AsyncItemLock = false,     -- Общая блокировка async предметов
    IsUsingRageTable = false,
    IsUsingHeatseeker = false,
    IsUsingAttackDoge = false,
    -- Кулдауны
    AOE_USE_COOLDOWN = 0.5,
    LASER_GUN_USE_COOLDOWN = 3.0,
    LASER_CAPE_USE_COOLDOWN = 2.5,
    BAN_HAMMER_USE_COOLDOWN = 2.5,
}

-- Обратная совместимость (alias для кулдаунов и времени)
local LastAoEUseTime = AoEState.LastUseTime
local AOE_USE_COOLDOWN = AoEState.AOE_USE_COOLDOWN
local LASER_GUN_USE_COOLDOWN = AoEState.LASER_GUN_USE_COOLDOWN
local LASER_CAPE_USE_COOLDOWN = AoEState.LASER_CAPE_USE_COOLDOWN
local BAN_HAMMER_USE_COOLDOWN = AoEState.BAN_HAMMER_USE_COOLDOWN
local LastAttackTime = 0

-- Вспомогательная функция: проверяет используется ли любой асинхронный предмет
local function IsAnyAsyncItemInUse()
    return AoEState.AsyncItemLock or AoEState.IsUsingRageTable or AoEState.IsUsingHeatseeker or AoEState.IsUsingAttackDoge or AoEState.IsUsingBanHammer
end

-- ═══════════════════════════════════════════════════════════════════════
-- TIMING CONSTANTS (на основе анализа игровых скриптов)
-- ═══════════════════════════════════════════════════════════════════════
-- Из игровых скриптов:
-- - Rage Table: task.wait(0.1) после FireServer перед анимацией
-- - Heatseeker: мгновенный FireServer с target
-- - Attack Doge: серверный скрипт
-- - Ban Hammer: Charge RemoteFunction → wait → Release RemoteEvent
-- - Все остальные: простой Activated → FireServer()
local TIMING = {
    -- EQUIP/UNEQUIP (критично для предотвращения конфликтов)
    EQUIP_WAIT = 0.2,       -- Ждать после экипировки (игра обрабатывает Tool.Equipped)
    UNEQUIP_WAIT = 0.1,     -- Ждать после снятия
    
    -- АКТИВАЦИЯ
    ACTIVATE_WAIT = 0.15,   -- Ждать после Activate() 
    CD_CHECK_INTERVAL = 0.1, -- Интервал проверки КД
    CD_MAX_WAIT = 0.8,      -- Максимум ждать КД
    MEDIUM = 0.15,          -- Средняя задержка (legacy)
    
    -- ВОССТАНОВЛЕНИЕ
    RESTORE_WAIT = 0.1,     -- Ждать перед восстановлением инструмента
    
    -- Ban Hammer специфичные (требует зарядку через ActionController)
    BAN_HAMMER_CHARGE = 0.6,  -- Время зарядки удара (увеличено)
    BAN_HAMMER_TOTAL = 1.2,   -- Общее время на Ban Hammer (charge + release + buffer)
    BAN_HAMMER_TIMEOUT = 1.5, -- Таймаут для Ban Hammer (НЕ переключать раньше!)
    
    -- Glove rotation
    GLOVE_SWITCH_WAIT = 0.12,  -- Переключение перчаток
    POST_ATTACK_DEFAULT = 0.16,  -- Задержка после атаки обычной перчаткой
    POST_ATTACK_GUMMY_BEAR = 0.20,  -- Задержка после атаки Gummy Bear
    POST_ATTACK_BAN_HAMMER = 0.20,  -- Задержка после атаки Ban Hammer
    -- Джиттер для рандомизации задержек
    JITTER_MIN = 0.9,   -- Минимальный множитель (90%)
    JITTER_MAX = 1.15,   -- Максимальный множитель (115%)
}

-- ═══════════════════════════════════════════════════════════════════════
-- BODY SWAP PROTECTION SYSTEM (ДЕТЕКЦИЯ ЧЕРЕЗ SMOKE ЭФФЕКТ)
-- ═══════════════════════════════════════════════════════════════════════
local ContextActionService = game:GetService("ContextActionService")

-- Группируем все переменные Body Swap в одну таблицу для экономии регистров
local BodySwapState = {
    LastKnownPosition = nil,
    LastPositionUpdateTime = 0,
    IsProtectionActive = false,
    LastSwapTime = 0,
    LastDetectionTime = 0,
    EffectConnections = {},
    PendingSwapBack = false,
    SwapperPlayer = nil,
    InputBlocked = false,
    -- Константы тоже внутри для экономии
    POSITION_UPDATE_INTERVAL = 0.5,
    SWAP_DETECTION_THRESHOLD = 50,
    SWAP_COOLDOWN = 3,
    PROTECTION_ENABLED = true,
    SMOKE_TEXTURE = "rbxassetid://16867365247",
    SMOKE_NAME = "Smoke",
    DETECTION_WINDOW = 2.0,
}

-- Константы BODY_SWAP для совместимости
local BODY_SWAP_PROTECTION_ENABLED = BodySwapState.PROTECTION_ENABLED
local BODY_SWAP_SMOKE_TEXTURE = BodySwapState.SMOKE_TEXTURE
local BODY_SWAP_SMOKE_NAME = BodySwapState.SMOKE_NAME

-- ═══════════════════════════════════════════════════════════════════════
-- LASER GUN SYSTEM (Интегрированный из paintball_auto_fire.lua)
-- ═══════════════════════════════════════════════════════════════════════
local HttpService = game:GetService("HttpService")

-- Группируем все переменные Laser Gun в одну таблицу
local LaserGunState = {
    SharedModule = nil,        -- Кешируем модуль для получения параметров
    Remote = nil,              -- RemoteEvent для Fire
    ImpactRemote = nil,        -- RemoteEvent для Impact (урон)
    Ready = false,             -- Флаг готовности системы
    LastFireTime = 0,          -- Время последнего выстрела
    ShotCounter = 0,           -- Счетчик выстрелов для отладки
    AbsoluteLastFireTime = 0,  -- Абсолютный минимум между выстрелами
    TargetBeam = nil,          -- Визуальный бим к цели
    BeamAttachment0 = nil,     -- Attachment для бима
    BeamAttachment1 = nil,     -- Attachment для бима
    LastBeamCreate = 0,        -- Время последнего создания бима
}
local ABSOLUTE_MIN_FIRE_INTERVAL = 1.0  -- НЕ МЕНЬШЕ 1 СЕКУНДЫ между выстрелами
local LASER_GUN_BEAM_CREATE_INTERVAL = 0.5  -- Минимум 0.5 сек между созданиями бима

-- Загрузка модуля LaserGunsShared (вызывается один раз)
local function LoadLaserGunsSharedModule()
    if LaserGunState.SharedModule then
        return true
    end
    
    local success = pcall(function()
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        if shared then
            local laserGunsShared = shared:FindFirstChild("LaserGunsShared")
            if laserGunsShared and laserGunsShared:IsA("ModuleScript") then
                LaserGunState.SharedModule = require(laserGunsShared)
            end
        end
    end)
    
    return success and LaserGunState.SharedModule ~= nil
end

-- Получение АКТУАЛЬНОГО кулдауна из игры
local function GetLaserGunCooldown()
    LoadLaserGunsSharedModule()
    
    if LaserGunState.SharedModule and LaserGunState.SharedModule.Settings and LaserGunState.SharedModule.Settings.Cooldown then
        local success, result = pcall(function()
            return LaserGunState.SharedModule.Settings.Cooldown:Get()
        end)
        
        if success and result and result > 0 then
            return result + 0.2  -- Добавляем 0.2с к игровому кулдауну
        end
    end
    
    return 2.4  -- Fallback: 2.2 + 0.2
end

-- Получение АКТУАЛЬНОЙ скорости снаряда из игры
local function GetLaserGunSpeed()
    LoadLaserGunsSharedModule()
    
    if LaserGunState.SharedModule and LaserGunState.SharedModule.Settings and LaserGunState.SharedModule.Settings.Speed then
        local success, result = pcall(function()
            return LaserGunState.SharedModule.Settings.Speed:Get()
        end)
        
        if success and result and result > 0 then
            return result
        end
    end
    
    return 100  -- Fallback
end

-- Предиктивный расчет для Laser Gun
local function CalculateLaserAim(targetPosition, targetVelocity, myPosition)
    if not targetPosition or not myPosition then
        return targetPosition
    end
    
    local projectileSpeed = GetLaserGunSpeed()
    local distance = (targetPosition - myPosition).Magnitude
    local flightTime = distance / projectileSpeed
    
    local predictedPosition = targetPosition
    if targetVelocity and targetVelocity.Magnitude > 0 then
        predictedPosition = targetPosition + (targetVelocity * flightTime * 0.7)
    end
    
    return predictedPosition
end

-- Инициализация Laser Gun RemoteEvents
local function InitializeLaserGunRemotes()
    task.spawn(function()
        task.wait(0.5)
        
        local RepStorage = game:GetService("ReplicatedStorage")
        local packagesFolder = RepStorage:FindFirstChild("Packages")
        
        -- Метод 1: Через Net модуль (ПРАВИЛЬНЫЙ способ из LaserGunsShared.luau)
        if packagesFolder then
            local netModule = packagesFolder:FindFirstChild("Net")
            if netModule and netModule:IsA("ModuleScript") then
                local success, net = pcall(require, netModule)
                if success and net then
                    -- Способ из LaserGunsShared.luau: net:RemoteEvent("LaserGun_Fire")
                    if type(net.RemoteEvent) == "function" then
                        local success2, remote = pcall(function()
                            return net:RemoteEvent("LaserGun_Fire")
                        end)
                        if success2 and remote and typeof(remote) == "Instance" and remote:IsA("RemoteEvent") then
                            LaserGunState.Remote = remote
                        end
                    end
                    
                    -- Fallback: прямой доступ через индекс
                    if not LaserGunState.Remote then
                        local attempts = {
                            "LaserGun_Fire",
                            "RE/LaserGun_Fire",
                            "LaserGun.Fire",
                        }
                        for _, key in ipairs(attempts) do
                            local value = net[key]
                            if value and typeof(value) == "Instance" and value:IsA("RemoteEvent") then
                                LaserGunState.Remote = value
                                break
                            end
                        end
                    end
                    
                    -- Ищем LaserGun_Impact
                    if type(net.RemoteEvent) == "function" then
                        local success3, impactRemote = pcall(function()
                            return net:RemoteEvent("LaserGun_Impact")
                        end)
                        if success3 and impactRemote then
                            LaserGunState.ImpactRemote = impactRemote
                        end
                    end
                end
            end
        end
        
        -- Метод 2: Прямой поиск если не нашли через Net
        if not LaserGunState.Remote then
            for _, obj in ipairs(RepStorage:GetDescendants()) do
                if obj:IsA("RemoteEvent") then
                    local name = obj.Name
                    -- Ищем RemoteEvent с LaserGun_Fire в названии
                    if name == "LaserGun_Fire" or (name:find("LaserGun") and name:find("Fire")) then
                        if not name:find("Impact") then
                            LaserGunState.Remote = obj
                            break
                        end
                    end
                end
            end
        end
        
        -- Ищем Impact если еще не нашли
        if not LaserGunState.ImpactRemote then
            for _, obj in ipairs(RepStorage:GetDescendants()) do
                if obj:IsA("RemoteEvent") and obj.Name == "LaserGun_Impact" then
                    LaserGunState.ImpactRemote = obj
                    break
                end
            end
        end
        
        if LaserGunState.Remote and LaserGunState.ImpactRemote then
            LaserGunState.Ready = true
        end
    end)
end

-- Выстрел из Laser Gun (РАБОЧАЯ ВЕРСИЯ из paintball_auto_fire.lua)
local function FireLaserGun(targetEnemy)
    local currentTime = tick()
    
    -- КРИТИЧЕСКАЯ ЗАЩИТА: абсолютный минимум 1 секунда между выстрелами
    if currentTime - LaserGunState.AbsoluteLastFireTime < ABSOLUTE_MIN_FIRE_INTERVAL then
        return false
    end
    
    local cooldown = GetLaserGunCooldown()
    
    if currentTime - LaserGunState.LastFireTime < cooldown then 
        return false 
    end
    
    if not LaserGunState.Remote or not LaserGunState.Ready then 
        return false 
    end
    
    local character = LocalPlayer.Character
    if not character then return false end
    
    -- КРИТИЧНО: Tool ДОЛЖЕН называться "Laser Gun"
    local laserGun = character:FindFirstChild("Laser Gun")
    if not laserGun or not laserGun:IsA("Tool") then 
        return false 
    end
    
    local handle = laserGun:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then
        return false
    end
    
    local muzzle = handle:FindFirstChild("Muzzle")
    if not muzzle or not muzzle:IsA("Attachment") then
        return false
    end
    
    local origin = muzzle.WorldCFrame.Position
    
    -- Получаем данные цели
    local targetChar = targetEnemy.Character
    if not targetChar then return false end
    
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local targetHead = targetChar:FindFirstChild("Head")
    if not targetRoot or not targetHead then return false end
    
    -- Предикт движения
    local targetVelocity = Vector3.new(0, 0, 0)
    pcall(function()
        targetVelocity = targetRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    end)
    
    local predictedPosition = CalculateLaserAim(targetHead.Position, targetVelocity, origin)
    local distance = (predictedPosition - origin).Magnitude
    local direction = (predictedPosition - origin).Unit
    
    LaserGunState.LastFireTime = currentTime
    LaserGunState.AbsoluteLastFireTime = currentTime  -- Обновляем абсолютный таймер
    LaserGunState.ShotCounter = LaserGunState.ShotCounter + 1
    
    local timestamp = workspace:GetServerTimeNow()
    local weaponID = HttpService:GenerateGUID(false):lower():gsub("-", "")
    
    -- Fire
    local fireSuccess = pcall(function()
        LaserGunState.Remote:FireServer(weaponID, origin, direction, timestamp)
    end)
    
    if not fireSuccess then
        return false
    end
    
    -- Impact (моментально)
    task.spawn(function()
        local projectileSpeed = GetLaserGunSpeed()
        local impactTimestamp = workspace:GetServerTimeNow()
        local impactAge = 0.01
        local linearVelocity = direction * projectileSpeed
        
        local impactData = {
            {
                Timestamp = impactTimestamp,
                CFrame = CFrame.lookAt(targetHead.Position, targetHead.Position + direction),
                LinearVelocity = linearVelocity,
                Age = impactAge,
                HitPart = targetRoot,
                HitNormal = -direction,
                HitPosition = targetHead.Position,
                HitEnding = targetHead.Position,
                HitAlpha = 0.95,
                HitSize = targetRoot.Size,
                HitCFrame = targetRoot.CFrame,
                Character = targetChar,
                Attributes = {
                    Bounces = 1
                }
            }
        }
        
        if LaserGunState.ImpactRemote then
            pcall(function()
                LaserGunState.ImpactRemote:FireServer(weaponID, impactData)
            end)
        end
    end)
    
    return true
end

-- ═══════════════════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════════════════


-- Sentry Tracking System - группируем в таблицу
local SentrySystem = {
    OurInstance = nil,             -- Reference to our currently placed sentry
    LastPlacementTime = 0,         -- When we last placed a sentry
    CHECK_INTERVAL = 0.5,          -- Check for sentry every 0.5 seconds
    ADDITIONAL_COOLDOWN = 6,       -- Additional cooldown after item ends
}

-- ═══════════════════════════════════════════════════════════════════════
-- ENEMY SENTRY STEALER SYSTEM - группируем в таблицу
-- ═══════════════════════════════════════════════════════════════════════
local EnemySentrySystem = {
    Tracked = {},                  -- Dictionary: sentry -> data
    VisualCopies = {},             -- Хранилище визуальных копий
    RadiusSpheres = {},            -- Хранилище сфер радиуса
    VignetteGui = nil,             -- GUI для виньетки
    LastMicroMove = 0,             -- Последнее микро-движение
    LastSphereFlash = 0,           -- Для мигания сфер
    -- Константы
    TELEPORT_DELAY = 4,            -- 3 секунды после установки турели
    TELEPORT_OFFSET = Vector3.new(0, 0, 3),
    MICRO_MOVE_INTERVAL = 0.05,
    SIZE_MULTIPLIER = 1.4,
    ATTACK_RADIUS = 24,
    TRANSPARENCY = 0.85,
    DETECTION_RADIUS = 100,
}

-- Обратно совместимые alias для Enemy Sentry
local TrackedEnemySentries = EnemySentrySystem.Tracked
local EnemySentryVisualCopies = EnemySentrySystem.VisualCopies
local SentryRadiusSpheres = EnemySentrySystem.RadiusSpheres
local ENEMY_SENTRY_ATTACK_RADIUS = EnemySentrySystem.ATTACK_RADIUS
local ENEMY_SENTRY_DETECTION_RADIUS = EnemySentrySystem.DETECTION_RADIUS
local ENEMY_SENTRY_TELEPORT_DELAY = EnemySentrySystem.TELEPORT_DELAY
local ENEMY_SENTRY_SIZE_MULTIPLIER = EnemySentrySystem.SIZE_MULTIPLIER
local ENEMY_SENTRY_TRANSPARENCY = EnemySentrySystem.TRANSPARENCY
local ENEMY_SENTRY_TELEPORT_OFFSET = EnemySentrySystem.TELEPORT_OFFSET
local ENEMY_SENTRY_MICRO_MOVE_INTERVAL = EnemySentrySystem.MICRO_MOVE_INTERVAL
-- Alias для констант нашей турели
local SENTRY_CHECK_INTERVAL = SentrySystem.CHECK_INTERVAL
local SENTRY_ADDITIONAL_COOLDOWN = SentrySystem.ADDITIONAL_COOLDOWN
-- OurSentryInstance остаётся как отдельная переменная для совместимости
local OurSentryInstance = nil

-- Quantum Cloner Pause System
local QuantumClonerPauseUntil = 0
local QUANTUM_CLONER_PAUSE_DURATION = 1
local QuantumClonerEquipped = false

-- Load configuration from file
local function LoadConfig()
    local success, result = pcall(function()
        if not isfolder("killaura_data") then
            return
        end
        
        if not isfile("killaura_data/" .. CONFIG_FILE) then
            return
        end
        
        local data = readfile("killaura_data/" .. CONFIG_FILE)
        local decoded = game:GetService("HttpService"):JSONDecode(data)
        
        for key, value in pairs(decoded) do
            -- НЕ перезаписываем AttackDelay из старого конфига (используем новое значение)
            if Config[key] ~= nil and key ~= "AttackDelay" then
                Config[key] = value
            end
        end
    end)
    
    -- Force radius to 50 (max detection)
    Config.DetectionRadius = 60
    
    -- Принудительно устанавливаем новое значение AttackDelay
    Config.AttackDelay = 0.20
    
    -- Если включена опция "Выключать при реинжекте" - выключаем скрипт
    if Config.DisableOnReinject then
        Config.Enabled = false
    end
end

-- Load friend list from file
local function LoadFriendList()
    local success, result = pcall(function()
        if not isfolder("killaura_data") then
            return
        end
        
        if not isfile("killaura_data/" .. FRIENDLIST_FILE) then
            return
        end
        
        local data = readfile("killaura_data/" .. FRIENDLIST_FILE)
        local decoded = game:GetService("HttpService"):JSONDecode(data)
        
        if type(decoded) == "table" then
            FriendList = decoded
        end
    end)
end

-- Save friend list to file
local function SaveFriendList()
    local success, result = pcall(function()
        if not isfolder("killaura_data") then
            makefolder("killaura_data")
        end
        
        local data = game:GetService("HttpService"):JSONEncode(FriendList)
        writefile("killaura_data/" .. FRIENDLIST_FILE, data)
    end)
end

-- Add player to friend list
local function AddToFriendList(player)
    if not player or not player:IsA("Player") then
        return false
    end
    
    local userId = tostring(player.UserId)
    
    FriendList[userId] = {
        Name = player.Name,
        DisplayName = player.DisplayName
    }
    
    SaveFriendList()
    return true
end

-- Remove player from friend list by userId
local function RemoveFromFriendList(userId)
    local userIdStr = tostring(userId)
    
    if FriendList[userIdStr] then
        FriendList[userIdStr] = nil
        SaveFriendList()
        return true
    end
    
    return false
end

-- Check if player is in friend list
local function IsInFriendList(player)
    if not player then
        return false
    end
    
    local userId = tostring(player.UserId)
    return FriendList[userId] ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════
-- FRIEND SAFE MODE FUNCTIONS (поиск друзей и управление бимом)
-- ═══════════════════════════════════════════════════════════════════════

-- Найти ближайшего друга из FriendList
-- ВАЖНО: При нескольких друзьях выбирается БЛИЖАЙШИЙ для определения режима
-- Если хоть один друг в радиусе 100м - AoE блокируются
-- Если хоть один друг в радиусе 50м - полное ограничение (только перчатки 10м)
-- Бим рисуется ТОЛЬКО к ближайшему другу
local function FindNearestFriend()
    local character = LocalPlayer.Character
    if not character then
        return nil, math.huge
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return nil, math.huge
    end
    
    local nearestFriend = nil
    local nearestDistance = math.huge
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsInFriendList(player) then
            local friendChar = player.Character
            if friendChar then
                local friendRoot = friendChar:FindFirstChild("HumanoidRootPart")
                local friendHumanoid = friendChar:FindFirstChildOfClass("Humanoid")
                
                if friendRoot and friendHumanoid and friendHumanoid.Health > 0 then
                    local distance = (rootPart.Position - friendRoot.Position).Magnitude
                    if distance < nearestDistance then
                        nearestDistance = distance
                        nearestFriend = player
                    end
                end
            end
        end
    end
    
    return nearestFriend, nearestDistance
end

-- Удалить бим к другу
local function RemoveFriendBeam()
    if FriendSafeState.FriendBeam then
        pcall(function() FriendSafeState.FriendBeam:Destroy() end)
        FriendSafeState.FriendBeam = nil
    end
    if FriendSafeState.FriendBeamAtt0 then
        pcall(function() FriendSafeState.FriendBeamAtt0:Destroy() end)
        FriendSafeState.FriendBeamAtt0 = nil
    end
    if FriendSafeState.FriendBeamAtt1 then
        pcall(function() FriendSafeState.FriendBeamAtt1:Destroy() end)
        FriendSafeState.FriendBeamAtt1 = nil
    end
end

-- Создать бим к другу (зеленый, тонкий, мигающий)
local function CreateFriendBeam(friendPlayer)
    if not Config.FriendSafeMode then return end
    if not friendPlayer then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    
    local friendChar = friendPlayer.Character
    if not friendChar then return end
    
    local friendRoot = friendChar:FindFirstChild("HumanoidRootPart")
    if not friendRoot then return end
    
    -- Удаляем старый бим если есть
    RemoveFriendBeam()
    
    -- Создаем attachments
    local att0 = Instance.new("Attachment")
    att0.Name = "FriendBeamAttachment0"
    att0.Position = Vector3.new(0, 2, 0)
    att0.Parent = rootPart
    
    local att1 = Instance.new("Attachment")
    att1.Name = "FriendBeamAttachment1"
    att1.Position = Vector3.new(0, 2, 0)
    att1.Parent = friendRoot
    
    -- Создаем яркий зеленый бим (более заметный)
    local beam = Instance.new("Beam")
    beam.Name = "FriendSafeBeam"
    beam.Color = ColorSequence.new(Color3.fromRGB(50, 255, 100))  -- Ярко-зеленый
    beam.Width0 = 0.35  -- Увеличенная толщина
    beam.Width1 = 0.35
    beam.FaceCamera = true
    beam.Transparency = NumberSequence.new(0)  -- Полностью непрозрачный
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Brightness = 2  -- Дополнительная яркость
    beam.Attachment0 = att0
    beam.Attachment1 = att1
    beam.Parent = rootPart
    
    FriendSafeState.FriendBeam = beam
    FriendSafeState.FriendBeamAtt0 = att0
    FriendSafeState.FriendBeamAtt1 = att1
end

-- Обновить бим к другу (мигание)
local function UpdateFriendBeam()
    if not Config.FriendSafeMode then
        RemoveFriendBeam()
        return
    end
    
    local currentTime = tick()
    
    -- Throttle обновления
    if currentTime - FriendSafeState.LastBeamUpdate < FRIEND_BEAM_UPDATE_INTERVAL then
        return
    end
    FriendSafeState.LastBeamUpdate = currentTime
    
    -- Ищем ближайшего друга
    local friend, distance = FindNearestFriend()
    FriendSafeState.NearestFriend = friend
    FriendSafeState.NearestFriendDistance = distance
    
    -- Определяем режимы ограничений
    FriendSafeState.AoEDisabled = (friend ~= nil and distance <= FRIEND_AOE_DISABLE_RADIUS)
    FriendSafeState.FullRestriction = (friend ~= nil and distance <= FRIEND_FULL_RESTRICTION_RADIUS)
    
    -- Показываем бим только если друг в радиусе 100м
    if friend and distance <= FRIEND_AOE_DISABLE_RADIUS then
        -- Проверяем нужно ли пересоздать бим (новый друг)
        if FriendSafeState.FriendBeam then
            -- Проверяем что attachments на правильных объектах
            local friendRoot = friend.Character and friend.Character:FindFirstChild("HumanoidRootPart")
            if friendRoot and FriendSafeState.FriendBeamAtt1 and FriendSafeState.FriendBeamAtt1.Parent ~= friendRoot then
                CreateFriendBeam(friend)
            end
        else
            CreateFriendBeam(friend)
        end
        
        -- Мигание бима (яркое)
        if FriendSafeState.FriendBeam then
            FriendSafeState.BeamBlinkTime = FriendSafeState.BeamBlinkTime + FRIEND_BEAM_UPDATE_INTERVAL
            local blinkPhase = math.sin(FriendSafeState.BeamBlinkTime * 8)  -- Быстрее мигание
            local transparency = 0 + (blinkPhase + 1) * 0.15  -- 0 - 0.3 прозрачность (ярче)
            local widthPulse = 0.35 + (blinkPhase + 1) * 0.1  -- Пульсация толщины
            FriendSafeState.FriendBeam.Transparency = NumberSequence.new(transparency)
            FriendSafeState.FriendBeam.Width0 = widthPulse
            FriendSafeState.FriendBeam.Width1 = widthPulse
            
            -- Меняем цвет в зависимости от режима
            if FriendSafeState.FullRestriction then
                -- Ярко-желтый/оранжевый при полном ограничении (50м)
                local greenValue = math.floor(180 + blinkPhase * 75)
                FriendSafeState.FriendBeam.Color = ColorSequence.new(Color3.fromRGB(255, greenValue, 0))
            else
                -- Ярко-зеленый при частичном ограничении (100м)
                local greenValue = math.floor(220 + blinkPhase * 35)
                FriendSafeState.FriendBeam.Color = ColorSequence.new(Color3.fromRGB(50, greenValue, 80))
            end
        end
    else
        -- Друг вне зоны - удаляем бим
        RemoveFriendBeam()
        FriendSafeState.BeamBlinkTime = 0
    end
end

-- Save configuration to file
local function SaveConfig()
    local success, result = pcall(function()
        if not isfolder("killaura_data") then
            makefolder("killaura_data")
        end
        
        local data = game:GetService("HttpService"):JSONEncode(Config)
        writefile("killaura_data/" .. CONFIG_FILE, data)
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- GLOVE PRIORITY SYSTEM (приоритет по стоимости в игре)
-- ═══════════════════════════════════════════════════════════════════════
-- Чем выше приоритет, тем лучше перчатка (дороже в игре)
local GlovePriorities = {
    -- Топ-тир перчатки (самые дорогие/редкие)
    ["dual wield slap"] = 100,
    ["dual slap"] = 100,
    ["diamond slap"] = 95,
    ["godly slap"] = 90,
    ["celestial slap"] = 88,
    ["rainbow slap"] = 85,
    ["titanium slap"] = 83,
    ["platinum slap"] = 80,
    ["emerald slap"] = 78,
    ["sapphire slap"] = 76,
    ["ruby slap"] = 74,
    ["amethyst slap"] = 72,
    
    -- Высокий тир
    ["golden slap"] = 70,
    ["gold slap"] = 70,
    ["crystal slap"] = 68,
    ["neon slap"] = 66,
    ["electric slap"] = 64,
    ["fire slap"] = 62,
    ["ice slap"] = 60,
    ["plasma slap"] = 58,
    ["laser slap"] = 56,
    ["cosmic slap"] = 54,
    ["galaxy slap"] = 52,
    
    -- Средний тир
    ["silver slap"] = 50,
    ["steel slap"] = 48,
    ["iron slap"] = 46,
    ["bronze slap"] = 44,
    ["copper slap"] = 42,
    ["stone slap"] = 40,
    ["wooden slap"] = 38,
    ["wood slap"] = 38,
    
    -- Базовые перчатки (низкий приоритет)
    ["slap"] = 10,
    ["default slap"] = 5,
    ["basic slap"] = 5,
}

-- ═══════════════════════════════════════════════════════════════════════
-- BRAINROT THIEF DETECTION SYSTEM (1 в 1 из adminabuse.lua)
-- Определяет вора лучшего brainrot для приоритетной атаки
-- ═══════════════════════════════════════════════════════════════════════

-- ============== DEBUG LOGGING ДЛЯ ДЕТЕКЦИИ ВОРА ==============
local THIEF_DEBUG_LOG_FILE = "killaura_thief_debug.log"
local THIEF_DEBUG_ENABLED = false  -- Отключено

-- Очистить лог при старте
local function ClearThiefDebugLog()
    if not THIEF_DEBUG_ENABLED then return end
    pcall(function()
        writefile(THIEF_DEBUG_LOG_FILE, "=== Killaura Thief Detection Debug ===\n" .. "Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    end)
end

-- Записать в лог
local function LogThiefDebug(message)
    if not THIEF_DEBUG_ENABLED then return end
    pcall(function()
        local timestamp = os.date("%H:%M:%S")
        local content = ""
        if isfile and isfile(THIEF_DEBUG_LOG_FILE) then
            content = readfile(THIEF_DEBUG_LOG_FILE)
            -- Ограничиваем размер файла
            if #content > 100000 then
                content = string.sub(content, -50000)
            end
        end
        writefile(THIEF_DEBUG_LOG_FILE, content .. "[" .. timestamp .. "] " .. message .. "\n")
    end)
end

-- Очищаем лог при старте скрипта
ClearThiefDebugLog()
LogThiefDebug("=== Script started ===")

-- Кэш и состояние детекции вора
local CachedBrainrotThief = nil  -- Текущий вор { player, brainrotName, value }
local CachedMyBaseThief = nil  -- Вор моей базы (приоритет выше!)
local LastThiefDetectionTime = 0  -- Время последней детекции
local LastMyBaseThiefDetectionTime = 0  -- Время последней детекции вора моей базы
local THIEF_DETECTION_INTERVAL = 0.15  -- Интервал проверки вора (150мс как в adminabuse)
local ThiefPriorityEnabled = true  -- Включен ли приоритет вора
local CachedPlotsFolder = nil  -- Кэш папки Plots

-- Множители цен для парсинга (из adminabuse.lua - ПОЛНЫЙ список)
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

-- Парсинг цены из строки (из adminabuse.lua)
local function ParseBrainrotPrice(priceString)
    local cleanString = tostring(priceString or ""):gsub("[$,]", ""):gsub("/s", "")
    local numericPart, unitPart = cleanString:match("([%d%.]+)%s*([A-Za-z]*)")
    if not numericPart then return 0 end
    local basePrice = tonumber(numericPart) or 0
    local upperUnit = string.upper(unitPart or "")
    local multiplier = PRICE_MULTIPLIERS[upperUnit] or 1
    return basePrice * multiplier
end

-- Форматирование числа в строку с суффиксом (k, M, B и т.д.)
local SUFFIXES = {"k", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No"}

local function FormatGenerationNumber(n)
    if not n then return "0" end
    n = tonumber(n)
    if not n then return "0" end
    
    if n < 1000 then 
        return tostring(math.floor(n)) 
    end
    
    -- Логарифмический поиск суффикса
    local i = math.floor(math.log(n, 1000))
    local v = math.pow(1000, i)
    local suffix = SUFFIXES[i] or "?"
    
    -- Оставляем 1 или 2 знака после запятой
    return string.format("%.1f%s", n/v, suffix)
end

-- Найти плот текущего игрока
local function FindMyPlot()
    local playerName = LocalPlayer.Name
    local playerDisplayName = LocalPlayer.DisplayName
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    CachedPlotsFolder = plotsFolder

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

-- Получить ценность brainrot по имени с подиума (когда brainrot несут, но overhead остался на подиуме)
-- 1 в 1 как getBrainrotIncomeFromPodiumByName в adminabuse.lua
local function GetBrainrotValueByName(brainrotName)
    if not brainrotName then return 0, "" end
    
    local plotsFolder = CachedPlotsFolder or workspace:FindFirstChild("Plots")
    if not plotsFolder then return 0, "" end
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local animalPodiums = plot:FindFirstChild("AnimalPodiums")
        if not animalPodiums then continue end
        
        for _, podium in ipairs(animalPodiums:GetChildren()) do
            local base = podium:FindFirstChild("Base")
            if not base then continue end
            
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            
            -- Проверяем имя через ProximityPrompt (как в adminabuse.lua)
            local promptAttachment = spawn:FindFirstChild("PromptAttachment")
            if promptAttachment then
                for _, desc in ipairs(promptAttachment:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") then
                        local objectText = desc.ObjectText
                        if objectText and objectText == brainrotName then
                            -- Нашли! Получаем Generation
                            local spawnAttachment = spawn:FindFirstChild("Attachment")
                            if spawnAttachment then
                                local animalOverhead = spawnAttachment:FindFirstChild("AnimalOverhead")
                                if animalOverhead then
                                    local generationLabel = animalOverhead:FindFirstChild("Generation")
                                    if generationLabel and generationLabel:IsA("TextLabel") then
                                        local genText = generationLabel.Text
                                        if genText and genText:find("/s") then
                                            return ParseBrainrotPrice(genText), genText
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
    
    return 0, ""
end

-- ============== ПОИСК ЛУЧШЕГО УКРАДЕННОГО BRAINROT (статус Stolen на подиуме) ==============
-- НОВОЕ: Ищем самый ценный brainrot в статусе "Stolen" - его кто-то крадёт/несёт прямо сейчас
-- Это даёт ТОЧНУЮ ценность украденного brainrot (а не первый попавшийся с таким именем)
-- 1 в 1 из adminabuse.lua

local function FindBestStolenBrainrot()
    local myPlot = FindMyPlot()
    local plotsFolder = CachedPlotsFolder or workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    
    local bestStolen = nil
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
            if not stolenLabel then continue end
            if not stolenLabel.Visible then continue end
            
            local stolenText = ""
            if stolenLabel:IsA("TextLabel") then
                stolenText = string.lower(tostring(stolenLabel.Text or ""))
            elseif stolenLabel:IsA("Frame") or stolenLabel:IsA("TextButton") then
                stolenText = "stolen" -- Если видим - считаем что статус активен
            end
            
            if stolenText ~= "stolen" and stolenText ~= "" then continue end
            
            -- Это brainrot в статусе Stolen! Получаем его ценность
            local generationLabel = animalOverhead:FindFirstChild("Generation")
            if not generationLabel or not generationLabel:IsA("TextLabel") then continue end
            
            local generationText = generationLabel.Text
            if not generationText then continue end
            
            -- Пробуем парсить ценность
            local generationValue = ParseBrainrotPrice(generationText)
            if generationValue <= 0 then continue end
            if generationValue <= bestValue then continue end
            
            -- Получаем имя brainrot из ProximityPrompt
            local promptAttachment = spawn:FindFirstChild("PromptAttachment")
            local brainrotName = "Unknown"
            if promptAttachment then
                for _, desc in ipairs(promptAttachment:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") then
                        local objectText = desc.ObjectText
                        if objectText and objectText ~= "" then
                            brainrotName = objectText
                            break
                        end
                    end
                end
            end
            
            bestValue = generationValue
            bestStolen = {
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
    
    return bestStolen
end

-- ============== НОВАЯ ЛОГИКА: Поиск через Synchronizer ==============

-- Получить часть слота (подиума) для отображения ESP
local function GetPartOfSlot(plot, slotIdx)
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

-- Основная функция поиска лучшего brainrot через Synchronizer
local function FindBestTargetViaSync()
    if not AnimalsShared or not Synchronizer or not PlotsFolder then
        return nil
    end
    
    local myPlot = FindMyPlot()
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

-- ============== ФУНКЦИЯ ПОИСКА ВОРА ЛУЧШЕГО BRAINROT ЧЕРЕЗ SYNCHRONIZER ==============
-- Ищет вора который несёт лучший brainrot определённый через Synchronizer
-- Возвращает данные о воре или nil
local function FindBestBrainrotThiefViaSync()
    -- Получаем лучший brainrot через Synchronizer
    local syncTarget = FindBestTargetViaSync()
    if not syncTarget or not syncTarget.Name then
        return nil
    end
    
    local targetName = syncTarget.Name
    local targetPlot = syncTarget.Plot
    local targetSlot = syncTarget.Slot
    local targetGen = syncTarget.Gen
    
    LogThiefDebug("FindBestBrainrotThiefViaSync: looking for " .. targetName .. " (Gen=" .. tostring(targetGen) .. ")")
    
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
        local generationText = FormatGenerationNumber(targetGen) .. "/s"
        
        LogThiefDebug("  FOUND in workspace: " .. obj.Name .. " carried by " .. carrierPlayer.Name)
        
        return {
            player = carrierPlayer,
            character = carrierCharacter,
            hrp = carrierHRP,
            brainrotModel = obj,
            rootPart = rootPart,
            brainrotName = targetName,
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
                                local generationText = FormatGenerationNumber(targetGen) .. "/s"
                                
                                LogThiefDebug("  FOUND in Plot (Stolen): " .. targetName .. " by " .. carrierPlayer.Name)
                                
                                return {
                                    player = carrierPlayer,
                                    character = carrierCharacter,
                                    hrp = carrierHRP,
                                    brainrotModel = brainrotModel,
                                    rootPart = rootPart,
                                    brainrotName = targetName,
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
    
    LogThiefDebug("  NOT FOUND - no one carrying " .. targetName)
    return nil
end

-- Найти лучший brainrot на ВСЕХ подиумах (кроме своего)
-- Использует новую логику через Synchronizer + AnimalsShared:GetGeneration()
local function FindBestBrainrotOnPodiums()
    local myPlot = FindMyPlot()
    local plotsFolder = CachedPlotsFolder or workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    
    local bestBrainrot = nil
    local bestValue = 0
    
    -- ============== НОВАЯ ЛОГИКА: Поиск через Synchronizer ==============
    local syncTarget = FindBestTargetViaSync()
    if syncTarget and syncTarget.Gen > bestValue then
        local spawn, podium = GetPartOfSlot(syncTarget.Plot, syncTarget.Slot)
        
        if spawn then
            local generationText = FormatGenerationNumber(syncTarget.Gen) .. "/s"
            
            bestValue = syncTarget.Gen
            bestBrainrot = {
                name = syncTarget.Name,
                value = syncTarget.Gen,
                text = generationText,
                plot = syncTarget.Plot,
                podium = podium,
                spawn = spawn
            }
        end
    end
    
    -- Если Synchronizer нашёл brainrot - используем его
    if bestBrainrot then
        return bestBrainrot
    end
    
    -- ============== FALLBACK: Старая логика поиска ==============
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        -- Пропускаем свой плот
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
            
            local generationLabel = animalOverhead:FindFirstChild("Generation")
            if not generationLabel or not generationLabel:IsA("TextLabel") then continue end
            
            local generationText = generationLabel.Text
            if not generationText then continue end
            
            -- Пропускаем таймеры и READY
            local lowerText = string.lower(generationText)
            if lowerText == "ready!" or lowerText:match("^%d+[smp]$") or lowerText:match("^%d+:%d+") then
                continue
            end
            
            -- Должен содержать /s
            if not generationText:find("/s") and not generationText:find("/S") then
                continue
            end
            
            local value = ParseBrainrotPrice(generationText)
            if value <= 0 then continue end
            if value <= bestValue then continue end
            
            -- Получаем имя brainrot
            local displayNameLabel = animalOverhead:FindFirstChild("DisplayName")
            local brainrotName = "Unknown"
            if displayNameLabel and displayNameLabel:IsA("TextLabel") then
                brainrotName = displayNameLabel.Text or "Unknown"
            end
            
            bestValue = value
            bestBrainrot = {
                name = brainrotName,
                value = value,
                text = generationText,
                plot = plot,
                podium = podium,
                spawn = spawn
            }
        end
    end
    
    return bestBrainrot
end

-- Найти вора лучшего brainrot (используя Synchronizer как основной метод)
-- Возвращает player если кто-то несёт ЛУЧШИЙ brainrot на сервере
local function FindBrainrotThief()
    local now = tick()
    
    -- Используем кэш если не истёк
    if now - LastThiefDetectionTime < THIEF_DETECTION_INTERVAL then
        if CachedBrainrotThief and CachedBrainrotThief.player and CachedBrainrotThief.player.Character then
            return CachedBrainrotThief
        end
        return nil
    end
    LastThiefDetectionTime = now
    
    LogThiefDebug("========== FindBrainrotThief START ==========")
    
    -- ОСНОВНОЙ МЕТОД: Через Synchronizer находим лучший brainrot и ищем вора
    local syncThief = FindBestBrainrotThiefViaSync()
    if syncThief then
        LogThiefDebug("SYNC METHOD SUCCESS: " .. syncThief.player.Name .. " carrying " .. syncThief.brainrotName)
        CachedBrainrotThief = syncThief
        return syncThief
    end
    
    LogThiefDebug("SYNC METHOD: No thief found, falling back to old logic")
    
    -- FALLBACK: Старая логика
    
    local bestThief = nil
    local bestCarriedValue = 0
    local carriedList = {}  -- Для логирования всех найденных
    
    -- Находим мой плот
    local myPlot = FindMyPlot()
    LogThiefDebug("MyPlot: " .. (myPlot and myPlot.Name or "NOT FOUND"))
    
    -- Находим лучший brainrot на МОЁМ подиуме (1 в 1 из adminabuse.lua)
    local myBestBrainrot = nil
    local myBestValue = 0
    if myPlot then
        local animalPodiums = myPlot:FindFirstChild("AnimalPodiums")
        if animalPodiums then
            for _, podium in ipairs(animalPodiums:GetChildren()) do
                local base = podium:FindFirstChild("Base")
                if not base then continue end
                local spawn = base:FindFirstChild("Spawn")
                if not spawn then continue end
                
                local animalOverhead = spawn:FindFirstChild("AnimalOverhead", true)
                if animalOverhead then
                    local generationLabel = animalOverhead:FindFirstChild("Generation")
                    if generationLabel and generationLabel:IsA("TextLabel") then
                        local genText = generationLabel.Text
                        if genText and genText:find("/s") then
                            local value = ParseBrainrotPrice(genText)
                            if value > myBestValue then
                                myBestValue = value
                                local promptAttach = spawn:FindFirstChild("PromptAttachment")
                                if promptAttach then
                                    for _, desc in ipairs(promptAttach:GetDescendants()) do
                                        if desc:IsA("ProximityPrompt") and desc.ObjectText then
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
    LogThiefDebug("MyBestBrainrot: " .. (myBestBrainrot and (myBestBrainrot.name .. " = " .. tostring(myBestBrainrot.value)) or "none"))
    
    -- ВАЖНО: Сначала находим ценность лучшего brainrot на ВСЕХ подиумах (кроме своего)
    local bestOnPodium = FindBestBrainrotOnPodiums()
    local bestPodiumValue = bestOnPodium and bestOnPodium.value or 0
    local bestPodiumName = bestOnPodium and bestOnPodium.name or "none"
    LogThiefDebug("BestOnPodiums: " .. bestPodiumName .. " = " .. tostring(bestPodiumValue))
    
    -- НОВОЕ: Ищем лучший УКРАДЕННЫЙ brainrot (со статусом "Stolen" на подиуме)
    -- Это даёт точную ценность того brainrot который прямо сейчас несут!
    local bestStolenBrainrot = FindBestStolenBrainrot()
    local bestStolenValue = bestStolenBrainrot and bestStolenBrainrot.value or 0
    local bestStolenName = bestStolenBrainrot and bestStolenBrainrot.name or "none"
    LogThiefDebug("BestStolenBrainrot: " .. bestStolenName .. " = " .. tostring(bestStolenValue))
    
    -- Счётчики для отладки
    local modelsChecked = 0
    local modelsWithFakeRoot = 0
    local modelsWithOverhead = 0
    local carriersFound = 0
    
    -- Ищем brainrot модели в workspace (не в Plots!)
    -- КРИТИЧЕСКИ ВАЖНО: Только модели с FakeRootPart являются carried brainrot!
    -- Модели БЕЗ FakeRootPart (только с AnimalOverhead) - это brainrot на подиумах (не несут)
    LogThiefDebug("--- Scanning workspace for CARRIED brainrot models (must have FakeRootPart) ---")
    for _, obj in ipairs(workspace:GetChildren()) do
        if not obj:IsA("Model") then continue end
        modelsChecked = modelsChecked + 1
        
        -- СТРОГАЯ ПРОВЕРКА (1 в 1 как adminabuse.lua строка 1165):
        -- FakeRootPart - ОБЯЗАТЕЛЬНЫЙ признак того что brainrot НЕСУТ!
        local fakeRootPart = obj:FindFirstChild("FakeRootPart")
        if not fakeRootPart then continue end  -- ПРОПУСКАЕМ если нет FakeRootPart!
        
        modelsWithFakeRoot = modelsWithFakeRoot + 1
        
        -- AnimalOverhead для получения информации о brainrot
        local animalOverheadCheck = obj:FindFirstChild("AnimalOverhead", true)
        if animalOverheadCheck then modelsWithOverhead = modelsWithOverhead + 1 end
        
        LogThiefDebug("  CARRIED Model: " .. obj.Name .. " (FakeRoot:true, Overhead:" .. tostring(animalOverheadCheck ~= nil) .. ")")
        
        -- Ищем кто несёт этот brainrot
        local carrierHRP = nil
        local carrierCharacter = nil
        local carrierPlayer = nil
        local detectionMethod = "none"
        
        -- МЕТОД 1: WeldConstraint в RootPart (основной метод)
        local rootPart = obj:FindFirstChild("RootPart")
        if rootPart then
            local weldConstraint = rootPart:FindFirstChild("WeldConstraint")
            if weldConstraint then
                LogThiefDebug("    Found WeldConstraint in RootPart")
                if weldConstraint.Part0 and weldConstraint.Part0:IsA("BasePart") and weldConstraint.Part0.Name == "HumanoidRootPart" then
                    carrierHRP = weldConstraint.Part0
                    carrierCharacter = carrierHRP.Parent
                    if carrierCharacter then
                        carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
                        detectionMethod = "WeldConstraint.Part0"
                    end
                elseif weldConstraint.Part1 and weldConstraint.Part1:IsA("BasePart") and weldConstraint.Part1.Name == "HumanoidRootPart" then
                    carrierHRP = weldConstraint.Part1
                    carrierCharacter = carrierHRP.Parent
                    if carrierCharacter then
                        carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
                        detectionMethod = "WeldConstraint.Part1"
                    end
                end
            end
        end
        
        -- МЕТОД 2: AssemblyRootPart (резервный метод через физику)
        if not carrierPlayer then
            local partToCheck = fakeRootPart or rootPart
            if partToCheck and partToCheck:IsA("BasePart") then
                local assemblyRoot = partToCheck.AssemblyRootPart
                if assemblyRoot and assemblyRoot ~= partToCheck and assemblyRoot.Name == "HumanoidRootPart" then
                    carrierHRP = assemblyRoot
                    carrierCharacter = carrierHRP.Parent
                    if carrierCharacter then
                        carrierPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
                        detectionMethod = "AssemblyRootPart"
                    end
                end
            end
        end
        
        -- МЕТОД 3: Рекурсивный поиск WeldConstraint/Weld/Motor6D через GetDescendants
        if not carrierPlayer then
            for _, desc in ipairs(obj:GetDescendants()) do
                if desc:IsA("WeldConstraint") or desc:IsA("Weld") or desc:IsA("Motor6D") then
                    if desc.Part0 and desc.Part0.Name == "HumanoidRootPart" then
                        local char = desc.Part0.Parent
                        if char then
                            local player = Players:GetPlayerFromCharacter(char)
                            if player and player ~= LocalPlayer then
                                carrierPlayer = player
                                carrierCharacter = char
                                carrierHRP = desc.Part0
                                detectionMethod = "GetDescendants." .. desc.ClassName .. ".Part0"
                                break
                            end
                        end
                    end
                    if not carrierPlayer and desc.Part1 and desc.Part1.Name == "HumanoidRootPart" then
                        local char = desc.Part1.Parent
                        if char then
                            local player = Players:GetPlayerFromCharacter(char)
                            if player and player ~= LocalPlayer then
                                carrierPlayer = player
                                carrierCharacter = char
                                carrierHRP = desc.Part1
                                detectionMethod = "GetDescendants." .. desc.ClassName .. ".Part1"
                                break
                            end
                        end
                    end
                end
            end
        end
        
        -- Логируем результат поиска carrier
        if carrierPlayer then
            LogThiefDebug("    CARRIER FOUND: " .. carrierPlayer.Name .. " (method: " .. detectionMethod .. ")")
            carriersFound = carriersFound + 1
        else
            LogThiefDebug("    No carrier found")
            continue
        end
        
        -- Проверяем что это не мы
        if carrierPlayer == LocalPlayer then
            LogThiefDebug("    SKIP: carrier is LocalPlayer")
            continue
        end
        
        -- Пропускаем друзей
        if IsInFriendList(carrierPlayer) then
            LogThiefDebug("    SKIP: carrier is in FriendList")
            continue
        end
        
        -- Пытаемся определить ценность brainrot
        local brainrotValue = 0
        local generationText = ""
        
        -- Ищем AnimalOverhead в carried модели
        local animalOverhead = obj:FindFirstChild("AnimalOverhead", true)
        if animalOverhead then
            local generationLabel = animalOverhead:FindFirstChild("Generation")
            if generationLabel and generationLabel:IsA("TextLabel") then
                local genText = generationLabel.Text
                LogThiefDebug("    Generation text: '" .. tostring(genText) .. "'")
                if genText and genText:find("/s") then
                    brainrotValue = ParseBrainrotPrice(genText)
                    generationText = genText
                    LogThiefDebug("    Parsed value from Generation: " .. tostring(brainrotValue))
                end
            end
        end
        
        -- Пробуем получить реальное имя через DisplayName
        local realBrainrotName = obj.Name
        if animalOverhead then
            local displayNameLabel = animalOverhead:FindFirstChild("DisplayName")
            if displayNameLabel and displayNameLabel:IsA("TextLabel") then
                local displayName = displayNameLabel.Text
                if displayName and displayName ~= "" and displayName ~= "{DisplayName}" then
                    realBrainrotName = displayName
                    LogThiefDebug("    Real name from DisplayName: '" .. realBrainrotName .. "'")
                end
            end
        end
        
        -- НОВАЯ ЛОГИКА: Если ценность 0 или низкая - ищем через статус "Stolen" на подиуме!
        -- Это КРИТИЧЕСКИ важно! Когда brainrot несут, его Generation показывает $0/s,
        -- но на подиуме откуда украли есть статус "Stolen" с РЕАЛЬНОЙ ценностью!
        if brainrotValue == 0 then
            LogThiefDebug("    Value is 0, trying FindBestStolenBrainrot()...")
            local stolenBrainrot = FindBestStolenBrainrot()
            if stolenBrainrot then
                LogThiefDebug("    Found STOLEN brainrot: " .. stolenBrainrot.name .. " = " .. tostring(stolenBrainrot.value))
                -- Проверяем совпадает ли имя (модель может называться по-другому)
                if stolenBrainrot.name == obj.Name or stolenBrainrot.name == realBrainrotName then
                    brainrotValue = stolenBrainrot.value
                    generationText = stolenBrainrot.text
                    realBrainrotName = stolenBrainrot.name
                    LogThiefDebug("    Names match! Using stolen value: " .. tostring(brainrotValue))
                else
                    -- Имена не совпадают, но если это единственный carried brainrot - возможно это он
                    -- Используем ценность stolen если она выше
                    LogThiefDebug("    Names don't match (model=" .. obj.Name .. ", stolen=" .. stolenBrainrot.name .. "), trying by model name...")
                    brainrotValue, generationText = GetBrainrotValueByName(obj.Name)
                    LogThiefDebug("    GetBrainrotValueByName result: " .. tostring(brainrotValue))
                    
                    -- Если всё ещё 0 и stolen значительно ценнее - возможно это он (имена могут отличаться)
                    if brainrotValue == 0 and stolenBrainrot.value > 0 then
                        brainrotValue = stolenBrainrot.value
                        generationText = stolenBrainrot.text
                        realBrainrotName = stolenBrainrot.name
                        LogThiefDebug("    Using stolen value as fallback: " .. tostring(brainrotValue))
                    end
                end
            else
                LogThiefDebug("    No STOLEN brainrot found, trying GetBrainrotValueByName('" .. obj.Name .. "')")
                brainrotValue, generationText = GetBrainrotValueByName(obj.Name)
                LogThiefDebug("    Result: " .. tostring(brainrotValue) .. " (" .. generationText .. ")")
                
                -- Если всё ещё 0, пробуем по реальному имени
                if brainrotValue == 0 and realBrainrotName ~= obj.Name then
                    LogThiefDebug("    Value still 0, trying GetBrainrotValueByName('" .. realBrainrotName .. "')")
                    brainrotValue, generationText = GetBrainrotValueByName(realBrainrotName)
                    LogThiefDebug("    Result: " .. tostring(brainrotValue) .. " (" .. generationText .. ")")
                end
            end
        end
        
        -- Добавляем в лог
        table.insert(carriedList, {
            name = realBrainrotName,
            modelName = obj.Name,
            carrier = carrierPlayer.Name,
            value = brainrotValue,
            method = detectionMethod
        })
        
        LogThiefDebug("    FINAL: " .. realBrainrotName .. " carried by " .. carrierPlayer.Name .. " value=" .. tostring(brainrotValue))
        
        -- Собираем информацию о ВСЕХ несомых brainrot
        -- ВАЖНО: brainrotValue должен быть > 0!
        if brainrotValue > 0 and brainrotValue > bestCarriedValue then
            LogThiefDebug("    >> NEW BEST CARRIED: " .. tostring(brainrotValue) .. " > " .. tostring(bestCarriedValue))
            bestCarriedValue = brainrotValue
            bestThief = {
                player = carrierPlayer,
                character = carrierCharacter,
                hrp = carrierHRP,
                brainrotModel = obj,
                brainrotName = realBrainrotName,
                value = brainrotValue,
                text = generationText ~= "" and generationText or "???"
            }
        elseif brainrotValue == 0 then
            LogThiefDebug("    SKIP: brainrotValue is 0")
        else
            LogThiefDebug("    SKIP: " .. tostring(brainrotValue) .. " <= " .. tostring(bestCarriedValue))
        end
    end
    
    LogThiefDebug("--- Scan complete ---")
    LogThiefDebug("ModelsChecked: " .. modelsChecked .. ", WithFakeRoot: " .. modelsWithFakeRoot .. ", WithOverhead: " .. modelsWithOverhead .. ", CarriersFound: " .. carriersFound)
    LogThiefDebug("CarriedList (" .. #carriedList .. "):")
    for i, c in ipairs(carriedList) do
        LogThiefDebug("  " .. i .. ". " .. c.name .. " (" .. c.modelName .. ") by " .. c.carrier .. " value=" .. tostring(c.value) .. " method=" .. c.method)
    end
    
    -- КРИТИЧЕСКАЯ ПРОВЕРКА
    LogThiefDebug("--- Final check ---")
    if bestThief then
        LogThiefDebug("BestThief: " .. bestThief.player.Name .. " carrying " .. bestThief.brainrotName .. " value=" .. tostring(bestThief.value))
        
        local isMyBrainrot = myBestBrainrot and bestThief.brainrotName == myBestBrainrot.name
        
        -- ИСПРАВЛЕННАЯ ЛОГИКА:
        -- 1. Если есть STOLEN brainrot на подиуме - проверяем совпадает ли с тем что несут
        -- 2. Если имя совпадает с stolen - ЭТО ТОЧНО ЛУЧШИЙ (используем stolen value)
        -- 3. Если stolen value выше podium value - значит несут лучший
        local isBestOnServer = false
        local checkReason = ""
        
        if bestStolenBrainrot then
            -- Есть stolen brainrot на подиуме
            local stolenMatches = (bestThief.brainrotName == bestStolenName) or (bestThief.brainrotModel.Name == bestStolenName)
            if stolenMatches then
                -- Имя совпадает со stolen - это ТОЧНО тот brainrot который крадут!
                -- Обновляем ценность на правильную (со stolen подиума)
                if bestThief.value < bestStolenValue then
                    LogThiefDebug("  Updating thief value from " .. tostring(bestThief.value) .. " to stolen value " .. tostring(bestStolenValue))
                    bestThief.value = bestStolenValue
                    bestThief.text = bestStolenBrainrot.text
                end
                isBestOnServer = bestStolenValue >= bestPodiumValue
                checkReason = "stolen_match (stolen=" .. tostring(bestStolenValue) .. " >= podium=" .. tostring(bestPodiumValue) .. ")"
            else
                -- Имя не совпадает - проверяем обычным способом
                isBestOnServer = bestThief.value >= bestPodiumValue
                checkReason = "value_check (value=" .. tostring(bestThief.value) .. " >= podium=" .. tostring(bestPodiumValue) .. ")"
            end
        else
            -- Нет stolen на подиуме - обычная проверка
            isBestOnServer = bestThief.value >= bestPodiumValue
            checkReason = "no_stolen (value=" .. tostring(bestThief.value) .. " >= podium=" .. tostring(bestPodiumValue) .. ")"
        end
        
        LogThiefDebug("isMyBrainrot: " .. tostring(isMyBrainrot) .. " (myBest=" .. (myBestBrainrot and myBestBrainrot.name or "nil") .. ", thief=" .. bestThief.brainrotName .. ")")
        LogThiefDebug("isBestOnServer: " .. tostring(isBestOnServer) .. " (" .. checkReason .. ")")
        
        if isMyBrainrot then
            LogThiefDebug("RESULT: Stealing MY brainrot - KEEP")
        elseif isBestOnServer then
            LogThiefDebug("RESULT: Stealing BEST on server - KEEP")
        else
            LogThiefDebug("RESULT: NOT best - IGNORE (set to nil)")
            bestThief = nil
        end
    else
        LogThiefDebug("BestThief: nil (no valid carrier found)")
    end
    
    LogThiefDebug("========== FindBrainrotThief END (result: " .. (bestThief and bestThief.player.Name or "nil") .. ") ==========")
    
    CachedBrainrotThief = bestThief
    return bestThief
end

-- ============== ПОИСК ВОРА МОЕЙ БАЗЫ (ЛЮБОЙ BRAINROT) ==============
-- Находит игрока который ворует ЛЮБОЙ brainrot с МОЕГО плота
-- Этот вор имеет ПРИОРИТЕТ над вором лучшего brainrot
local function FindMyBaseThief()
    local now = tick()
    
    -- Используем кэш если не истёк
    if now - LastMyBaseThiefDetectionTime < THIEF_DETECTION_INTERVAL then
        if CachedMyBaseThief and CachedMyBaseThief.player and CachedMyBaseThief.player.Character then
            return CachedMyBaseThief
        end
        return nil
    end
    LastMyBaseThiefDetectionTime = now
    
    local myPlot = FindMyPlot()
    if not myPlot then 
        CachedMyBaseThief = nil
        return nil 
    end
    
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
        
        -- Через AnimalsShared если есть данные
        if AnimalsShared and brainrotInfo.mutation then
            pcall(function()
                brainrotValue = AnimalsShared:GetGeneration(brainrotName, brainrotInfo.mutation, brainrotInfo.traits, nil) or 0
            end)
        end
        
        -- Fallback: AnimalOverhead
        if brainrotValue == 0 then
            local animalOverhead = obj:FindFirstChild("AnimalOverhead", true)
            if animalOverhead then
                local generationLabel = animalOverhead:FindFirstChild("Generation")
                if generationLabel and generationLabel:IsA("TextLabel") then
                    local genText = generationLabel.Text
                    if genText and genText:find("/s") then
                        brainrotValue = ParseBrainrotPrice(genText)
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
                brainrotName = brainrotName,
                value = brainrotValue,
                isMyBaseThief = true
            }
        end
    end
    
    CachedMyBaseThief = bestThief
    return bestThief
end

-- Проверить является ли игрок вором лучшего brainrot
local function IsBrainrotThief(player)
    if not ThiefPriorityEnabled then return false end
    if not player then return false end
    
    local thief = FindBrainrotThief()
    return thief and thief.player == player
end

-- Проверить является ли игрок вором моей базы
local function IsMyBaseThief(player)
    if not ThiefPriorityEnabled then return false end
    if not player then return false end
    
    local thief = FindMyBaseThief()
    return thief and thief.player == player
end

-- Получить приоритет перчатки по имени
local function GetGlovePriority(tool)
    if not tool or not tool:IsA("Tool") then
        return 0
    end
    
    local name = tool.Name:lower()
    
    -- Сначала пробуем точное совпадение
    if GlovePriorities[name] then
        return GlovePriorities[name]
    end
    
    -- Затем ищем частичное совпадение (от самых дорогих к дешёвым)
    local bestPriority = 1  -- Минимальный приоритет для неизвестных перчаток
    
    for pattern, priority in pairs(GlovePriorities) do
        if name:find(pattern) and priority > bestPriority then
            bestPriority = priority
        end
    end
    
    return bestPriority
end

-- Check if tool is a slap glove (contains "Slap" in name)
local function IsGlove(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end
    
    local name = tool.Name:lower()
    -- Check for common glove patterns (только slap-перчатки)
    if name:find("slap") or name:find("glove") or name:find("hand") then
        return true
    end
    
    -- Check tool's remote events/functions for "Slap"
    for _, child in ipairs(tool:GetDescendants()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            if child.Name:lower():find("slap") then
                return true
            end
        end
    end
    
    return false
end

-- Check if tool is Ban Hammer
local function IsBanHammer(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end
    local name = tool.Name:lower()
    return name:find("ban hammer") or name:find("banhammer") or name == "ban hammer"
end

-- Check if tool is Gummy Bear
local function IsGummyBear(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end
    local name = tool.Name:lower()
    return name:find("gummy bear") or name:find("gummybear") or name == "gummy bear"
end

-- Check if tool is part of rotation (slap glove, Ban Hammer, or Gummy Bear)
local function IsRotationTool(tool)
    return IsGlove(tool) or IsBanHammer(tool) or IsGummyBear(tool)
end

-- Check if tool is on cooldown (универсальная проверка для любого инструмента)
local function IsToolOnCooldown(tool)
    if not tool then
        return true  -- Нет инструмента = считаем на КД
    end
    
    local cooldownTime = tool:GetAttribute("CooldownTime")
    if cooldownTime and cooldownTime > 0 then
        return true
    end
    
    -- Альтернативные атрибуты КД
    local cd = tool:GetAttribute("Cooldown")
    if cd and cd > 0 then
        return true
    end
    
    local onCooldown = tool:GetAttribute("OnCooldown")
    if onCooldown == true then
        return true
    end
    
    return false
end
-- Scan inventory for available tools and gloves
-- ИЗМЕНЕНО: slap-перчатки + Gummy Bear (если есть) в ротации
-- Ban Hammer используется ОТДЕЛЬНО через AoE систему (радиус 10)
local MAX_SLAP_GLOVES_IN_ROTATION = 7  -- 7 slap-перчаток + Gummy Bear = 8 макс

-- Глобальная переменная для Ban Hammer (для AoE системы)
local CachedBanHammer = nil

local function ScanInventory()
    AvailableTools = {}
    AvailableGloves = {}
    local allSlapGloves = {}  -- Временный список slap-перчаток для сортировки
    local gummyBear = nil  -- Gummy Bear добавляется в конец ротации (обязательно)
    CachedBanHammer = nil  -- Сбрасываем кеш
    
    -- Wait for backpack to load
    local backpack = LocalPlayer:WaitForChild("Backpack", 5)
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(AvailableTools, item)
                
                -- Проверяем тип инструмента
                if IsBanHammer(item) then
                    CachedBanHammer = item  -- Кешируем для AoE системы
                elseif IsGummyBear(item) then
                    gummyBear = item  -- Сохраняем для добавления в ротацию
                elseif IsGlove(item) and item.Name ~= "Blackhole Slap" then
                    table.insert(allSlapGloves, item)
                end
            end
        end
    end
    
    -- Check currently equipped tool
    local character = LocalPlayer.Character
    if character then
        local equippedTool = character:FindFirstChildOfClass("Tool")
        if equippedTool then
            if not table.find(AvailableTools, equippedTool) then
                table.insert(AvailableTools, equippedTool)
            end
            
            -- Проверяем тип экипированного инструмента
            if IsBanHammer(equippedTool) and not CachedBanHammer then
                CachedBanHammer = equippedTool  -- Кешируем для AoE системы
            elseif IsGummyBear(equippedTool) and not gummyBear then
                gummyBear = equippedTool  -- Сохраняем для добавления в ротацию
            elseif IsGlove(equippedTool) and equippedTool.Name ~= "Blackhole Slap" and not table.find(allSlapGloves, equippedTool) then
                table.insert(allSlapGloves, equippedTool)
            end
        end
    end
    
    -- Сортируем slap-перчатки по приоритету (от лучших к худшим)
    table.sort(allSlapGloves, function(a, b)
        return GetGlovePriority(a) > GetGlovePriority(b)
    end)
    
    -- Берём только MAX_SLAP_GLOVES_IN_ROTATION лучших slap-перчаток
    for i = 1, math.min(#allSlapGloves, MAX_SLAP_GLOVES_IN_ROTATION) do
        table.insert(AvailableGloves, allSlapGloves[i])
    end
    
    -- ОБЯЗАТЕЛЬНО добавляем Gummy Bear в конец ротации (если есть)
    -- Gummy Bear работает как slap-перчатка с Cooldown 0.7s
    if gummyBear then
        table.insert(AvailableGloves, gummyBear)
    end
    
    -- Ban Hammer доступен через CachedBanHammer для AoE системы
    -- НЕ добавляется в ротацию перчаток
    
    return AvailableTools, AvailableGloves
end

-- Find AoE item in inventory
local function FindAoEItem(itemName)
    -- First try exact match in backpack
    local backpack = LocalPlayer:WaitForChild("Backpack", 5)
    if backpack then
        local item = backpack:FindFirstChild(itemName)
        if item and item:IsA("Tool") then
            return item
        end
        
        -- Try partial match - check if item name contains key words
        -- ВАЖНО: Laser Gun проверяется ДО Laser Cape!
        local keywords = {}
        if itemName == "Laser Gun" or itemName:find("Laser Gun") then
            keywords = {"Laser Gun"}
        elseif itemName:find("Medusa") then
            keywords = {"Medusa", "medusa"}
        elseif itemName:find("Boogie") then
            keywords = {"Boogie", "boogie", "Bomb", "bomb"}
        elseif itemName:find("Sentry") then
            keywords = {"Sentry", "sentry", "All Seeing", "AllSeeing"}
        elseif itemName:find("Megaphone") then
            keywords = {"Megaphone", "megaphone"}
        elseif itemName:find("Taser") then
            keywords = {"Taser", "taser"}
        elseif itemName:find("Bee") then
            keywords = {"Bee", "bee", "Launcher", "launcher"}
        elseif itemName:find("Laser Cape") then
            keywords = {"Laser Cape", "Cape", "cape"}
        elseif itemName:find("Rage") or itemName:find("Table") then
            keywords = {"Rage", "rage", "Table", "table"}
        elseif itemName:find("Ban") or itemName:find("Hammer") then
            keywords = {"Ban Hammer", "BanHammer", "Ban", "Hammer"}
        elseif itemName:find("Heatseeker") or itemName:find("Heat") then
            keywords = {"Heatseeker", "heatseeker", "Heat Seeker", "heat seeker"}
        elseif itemName:find("Attack") or itemName:find("Doge") then
            keywords = {"Attack Doge", "AttackDoge", "Attack", "Doge", "attack doge"}
        end
        
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                for _, keyword in ipairs(keywords) do
                    if child.Name:find(keyword) then
                        return child
                    end
                end
            end
        end
    end
    
    -- Check if currently equipped
    local character = LocalPlayer.Character
    if character then
        local item = character:FindFirstChild(itemName)
        if item and item:IsA("Tool") then
            return item
        end
        
        -- Try partial match in equipped items
        -- ВАЖНО: Laser Gun проверяется ДО Laser Cape!
        local keywords = {}
        if itemName == "Laser Gun" or itemName:find("Laser Gun") then
            keywords = {"Laser Gun"}
        elseif itemName:find("Medusa") then
            keywords = {"Medusa", "medusa"}
        elseif itemName:find("Boogie") then
            keywords = {"Boogie", "boogie", "Bomb", "bomb"}
        elseif itemName:find("Sentry") then
            keywords = {"Sentry", "sentry", "All Seeing", "AllSeeing"}
        elseif itemName:find("Megaphone") then
            keywords = {"Megaphone", "megaphone"}
        elseif itemName:find("Taser") then
            keywords = {"Taser", "taser"}
        elseif itemName:find("Bee") then
            keywords = {"Bee", "bee", "Launcher", "launcher"}
        elseif itemName:find("Laser Cape") then
            keywords = {"Laser Cape", "Cape", "cape"}
        elseif itemName:find("Rage") or itemName:find("Table") then
            keywords = {"Rage", "rage", "Table", "table"}
        elseif itemName:find("Ban") or itemName:find("Hammer") then
            keywords = {"Ban Hammer", "BanHammer", "Ban", "Hammer"}
        elseif itemName:find("Heatseeker") or itemName:find("Heat") then
            keywords = {"Heatseeker", "heatseeker", "Heat Seeker", "heat seeker"}
        elseif itemName:find("Attack") or itemName:find("Doge") then
            keywords = {"Attack Doge", "AttackDoge", "Attack", "Doge", "attack doge"}
        end
        
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                for _, keyword in ipairs(keywords) do
                    if child.Name:find(keyword) then
                        return child
                    end
                end
            end
        end
    end
    
    return nil
end



-- Get real cooldown from game Tool attribute
local function GetItemCooldown(itemName)
    local item = FindAoEItem(itemName)
    if not item then
        return 999  -- Item not found = infinite cooldown
    end
    
    -- Проверяем разные варианты атрибутов КД
    local cooldownTime = item:GetAttribute("CooldownTime")
    if cooldownTime and cooldownTime > 0 then
        return cooldownTime
    end
    
    local cd = item:GetAttribute("Cooldown")
    if cd and cd > 0 then
        return cd
    end
    
    local onCooldown = item:GetAttribute("OnCooldown")
    if onCooldown == true then
        return 1  -- На КД но время неизвестно
    end
    
    return 0  -- 0 = ready to use
end

-- Count enemies in specific radius
local function CountEnemiesInRadius(radius)
    if not Players then
        return 0
    end
    
    local character = LocalPlayer.Character
    if not character then
        return 0
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return 0
    end
    
    local count = 0
    
    local success, result = pcall(function()
        for _, player in ipairs(Players:GetPlayers()) do
            if IsEnemy(player) then
                local targetChar = player.Character
                if targetChar then
                    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
                    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
                    
                    if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
                        local distance = (rootPart.Position - targetRoot.Position).Magnitude
                        
                        if distance <= radius then
                            count = count + 1
                        end
                    end
                end
            end
        end
    end)
    
    if not success then
        return 0
    end
    
    return count
end

-- Use AoE item
-- asyncMode = true: НЕ блокирует основной цикл (для Rage Table, Heatseeker, Attack Doge)
-- ОПТИМИЗАЦИЯ: Проверяем КД ДО экипировки, быстрая активация для мгновенных предметов
local function UseAoEItem(itemName, asyncMode)
    local startTime = tick()
    
    local item = FindAoEItem(itemName)
    if not item then
        return false
    end
    
    -- ПРОВЕРКА КД ДО ЭКИПИРОВКИ - не тратим время если предмет на КД
    local currentCooldown = item:GetAttribute("CooldownTime")
    if currentCooldown and currentCooldown > 0 then
        LogItem(itemName, "SKIP", "on cooldown " .. tostring(currentCooldown) .. "s")
        return false
    end
    
    LogItem(itemName, "START", asyncMode and "async" or "sync")
    
    local character = LocalPlayer.Character
    if not character then
        LogItem(itemName, "ABORT", "no character")
        return false
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        LogItem(itemName, "ABORT", "no humanoid")
        return false
    end
    
    -- Remember current GLOVE before switching
    local previousTool = nil
    local currentEquipped = character:FindFirstChildOfClass("Tool")
    if currentEquipped and IsRotationTool(currentEquipped) then
        previousTool = currentEquipped
    end
    
    -- Set category lock СРАЗУ
    if asyncMode then
        AoEState.AsyncItemLock = true
    else
        AoEState.IsUsingAoEItem = true
    end
    
    -- Определяем тип предмета для оптимизации
    local isInstantItem = itemName:find("Boogie") or itemName:find("Megaphone") or 
                          itemName:find("Sentry") or 
                          itemName:find("Attack Doge") or itemName:find("Rage Table")
    local isHeatseeker = itemName == "Heatseeker" or itemName:find("Heatseeker")
    local isAttackDoge = itemName == "Attack Doge" or itemName:find("Attack Doge")
    local isRageTable = itemName == "Rage Table" or itemName:find("Rage Table")
    local isLaserCape = itemName == "Laser Cape" or itemName:find("Laser Cape")
    local isTaserGun = itemName == "Taser Gun" or itemName:find("Taser")
    local isLaserGun = itemName == "Laser Gun" or itemName:find("Laser Gun")
    local isBeeLauncher = itemName == "Bee Launcher" or itemName:find("Bee")
    
    local success, err = pcall(function()
        -- ШАГ 1: Снимаем текущий инструмент (быстро)
        LogTiming(itemName, "STEP1_unequip", tick() - startTime)
        humanoid:UnequipTools()
        task.wait(0.05)  -- Минимальная задержка
        
        -- ШАГ 2: Экипируем предмет
        LogTiming(itemName, "STEP2_equip", tick() - startTime)
        humanoid:EquipTool(item)
        
        -- Ждём экипировки (короткое ожидание для быстрых предметов)
        local maxWait = isInstantItem and 0.25 or 0.4
        local waitTime = 0
        while item.Parent ~= character and waitTime < maxWait do
            task.wait(0.03)
            waitTime = waitTime + 0.03
        end
        
        if item.Parent ~= character then
            LogItem(itemName, "ABORT", "equip failed")
            return
        end
        
        LogTiming(itemName, "STEP3_equipped", tick() - startTime)
        LogItem(itemName, "STEP4", "activate | enemies=" .. #AllDetectedEnemies)
        
        -- ШАГ 3: БЫСТРАЯ АКТИВАЦИЯ
        local Net = nil
        pcall(function()
            local Packages = ReplicatedStorage:FindFirstChild("Packages")
            if Packages then
                Net = require(Packages:FindFirstChild("Net"))
            end
        end)
        
        if isLaserGun then
            -- Laser Gun - через FireLaserGun или обычную активацию
            local laserTarget = CurrentTarget
            
            -- Если CurrentTarget не установлен - берём ближайшего врага в радиусе
            if not laserTarget then
                local closestDist = math.huge
                for _, enemyData in ipairs(AllDetectedEnemies) do
                    if enemyData.distance <= DETECTION_RADIUS.LASER_GUN and enemyData.distance < closestDist then
                        laserTarget = enemyData.player
                        closestDist = enemyData.distance
                    end
                end
            end
            
            if laserTarget then
                -- Пробуем через remote (быстрее)
                local fireSuccess = FireLaserGun(laserTarget)
                
                -- Если remote не сработал - используем обычную активацию
                if not fireSuccess then
                    LogItem(itemName, "FALLBACK", "FireLaserGun failed, using Activate()")
                    pcall(function()
                        tool:Activate()
                    end)
                    task.wait(0.1)
                end
            else
                -- Нет цели - просто активируем (выстрел в направлении камеры)
                pcall(function()
                    tool:Activate()
                end)
                task.wait(0.1)
            end
            
        elseif isHeatseeker then
            -- Heatseeker - требует Player как параметр
            -- ИСПРАВЛЕНО: Используем CurrentTarget
            if Net then
                local targetPlayer = CurrentTarget
                -- Fallback на ближайшего в радиусе если нет CurrentTarget
                if not targetPlayer then
                    local closestDist = math.huge
                    for _, enemyData in ipairs(AllDetectedEnemies) do
                        if enemyData.distance <= 40 and enemyData.distance < closestDist then
                            targetPlayer = enemyData.player
                            closestDist = enemyData.distance
                        end
                    end
                end
                if targetPlayer then
                    LogItem("Heatseeker", "FIRE", "target=" .. targetPlayer.Name)
                    Net:RemoteEvent("UseItem"):FireServer(targetPlayer)
                else
                    LogItem("Heatseeker", "NO_TARGET", "no enemy within 40 studs")
                end
            end
            
        elseif isRageTable then
            -- Rage Table - мгновенный FireServer без параметров
            if Net then
                LogItem("Rage Table", "FIRE", "instant")
                Net:RemoteEvent("UseItem"):FireServer()
            end
            
        elseif isAttackDoge then
            -- Attack Doge - серверный скрипт, просто Activate
            LogItem("Attack Doge", "FIRE", "Activate()")
            item:Activate()
            
        elseif isBeeLauncher then
            -- Bee Launcher - требует Player как параметр (как Heatseeker)
            -- ИСПРАВЛЕНО: Используем CurrentTarget
            if Net then
                local targetPlayer = CurrentTarget
                -- Fallback на ближайшего в радиусе если нет CurrentTarget
                if not targetPlayer then
                    local closestDist = math.huge
                    for _, enemyData in ipairs(AllDetectedEnemies) do
                        if enemyData.distance <= 30 and enemyData.distance < closestDist then
                            targetPlayer = enemyData.player
                            closestDist = enemyData.distance
                        end
                    end
                end
                if targetPlayer then
                    LogItem("Bee Launcher", "FIRE", "target=" .. targetPlayer.Name)
                    Net:RemoteEvent("UseItem"):FireServer(targetPlayer)
                else
                    LogItem("Bee Launcher", "NO_TARGET", "no enemy within 30 studs")
                end
            end
            
        elseif isTaserGun then
            -- Taser Gun - требует цель
            -- ИСПРАВЛЕНО: Используем CurrentTarget
            local targetPart = nil
            local targetPlayer = CurrentTarget
            if targetPlayer and targetPlayer.Character then
                local targetChar = targetPlayer.Character
                targetPart = targetChar:FindFirstChild("UpperTorso") or targetChar:FindFirstChild("HumanoidRootPart")
            end
            -- Fallback на ближайшего в радиусе если нет CurrentTarget
            if not targetPart then
                local closestDist = math.huge
                for _, enemyData in ipairs(AllDetectedEnemies) do
                    if enemyData.distance <= DETECTION_RADIUS.TASER and enemyData.distance < closestDist then
                        local targetChar = enemyData.player and enemyData.player.Character
                        if targetChar then
                            targetPart = targetChar:FindFirstChild("UpperTorso") or targetChar:FindFirstChild("HumanoidRootPart")
                            if targetPart then
                                closestDist = enemyData.distance
                            end
                        end
                    end
                end
            end
            if targetPart and Net then
                Net:RemoteEvent("UseItem"):FireServer(targetPart)
            end
            item:Activate()
            
        elseif isLaserCape then
            -- Laser Cape - требует позицию и цель
            -- ИСПРАВЛЕНО: Используем CurrentTarget
            local targetPosition, targetPart = nil, nil
            local targetPlayer = CurrentTarget
            if targetPlayer and targetPlayer.Character then
                local targetChar = targetPlayer.Character
                local rootPart = targetChar:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    targetPosition = rootPart.Position
                    targetPart = rootPart
                end
            end
            -- Fallback на ближайшего в радиусе если нет CurrentTarget
            if not targetPosition then
                local closestDist = math.huge
                for _, enemyData in ipairs(AllDetectedEnemies) do
                    if enemyData.distance <= 60 and enemyData.distance < closestDist then
                        local targetChar = enemyData.player and enemyData.player.Character
                        if targetChar then
                            local rootPart = targetChar:FindFirstChild("HumanoidRootPart")
                            if rootPart then
                                targetPosition = rootPart.Position
                                targetPart = rootPart
                                closestDist = enemyData.distance
                            end
                        end
                    end
                end
            end
            if targetPosition and targetPart and Net then
                Net:RemoteEvent("UseItem"):FireServer(targetPosition, targetPart)
            end
            item:Activate()
            
        else
            -- Стандартные предметы (Boogie, Medusa, Megaphone, Sentry, Bee) - просто Activate
            item:Activate()
            if Net then
                pcall(function() Net:RemoteEvent("UseItem"):FireServer() end)
            end
        end
        
        -- ШАГ 4: Ждём КД (очень короткое ожидание для мгновенных)
        LogTiming(itemName, "STEP5_waitCD", tick() - startTime)
        local cdWaitTime = isInstantItem and 0.15 or 0.3
        task.wait(cdWaitTime)
        
        -- Проверяем что КД установился
        local newCooldown = item:GetAttribute("CooldownTime")
        if newCooldown and newCooldown > 0 then
            LogItem(itemName, "CD_SET", tostring(math.floor(newCooldown)))
        end
        
        -- ШАГ 5: Снимаем предмет и возвращаем перчатку
        LogTiming(itemName, "STEP6_restore", tick() - startTime)
        humanoid:UnequipTools()
        task.wait(0.05)
        
        if previousTool and previousTool.Parent == LocalPlayer.Backpack then
            humanoid:EquipTool(previousTool)
        end
        
        LogTiming(itemName, "COMPLETE", tick() - startTime)
    end)
    
    if not success and err then
        LogError("UseAoEItem " .. itemName, tostring(err))
    end
    
    local totalTime = tick() - startTime
    LogItem(itemName, "END", (success and "success" or "failed") .. " in " .. string.format("%.2f", totalTime) .. "s")
    
    -- Release locks
    if asyncMode then
        AoEState.AsyncItemLock = false
    else
        AoEState.IsUsingAoEItem = false
    end
    
    return success
end

-- ═══════════════════════════════════════════════════════════════════════
-- BAN HAMMER AoE ФУНКЦИЯ (отдельная от ротации перчаток)
-- Использует ActionController.Pressed/Released как в оригинальной игре
-- Тайминги из brainrot: ChargeMaxDuration=2.5s, Cooldown=2s, MinRadius=10, MaxRadius=20
-- ═══════════════════════════════════════════════════════════════════════
local function UseBanHammerAoE(banHammerItem)
    local startTime = tick()
    LogItem("Ban Hammer AoE", "START", "")
    
    local character = LocalPlayer.Character
    if not character then
        LogItem("Ban Hammer AoE", "ABORT", "no character")
        return false
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        LogItem("Ban Hammer AoE", "ABORT", "no humanoid")
        return false
    end
    
    -- Запоминаем текущий инструмент для восстановления
    local previousTool = nil
    local currentEquipped = character:FindFirstChildOfClass("Tool")
    if currentEquipped and IsRotationTool(currentEquipped) then
        previousTool = currentEquipped
    end
    
    local success = false
    
    pcall(function()
        -- ШАГ 1: Снимаем текущий инструмент
        humanoid:UnequipTools()
        task.wait(0.1)
        
        -- ШАГ 2: Экипируем Ban Hammer
        humanoid:EquipTool(banHammerItem)
        
        -- Ждём экипировки
        local waitTime = 0
        while banHammerItem.Parent ~= character and waitTime < 0.5 do
            task.wait(0.05)
            waitTime = waitTime + 0.05
        end
        
        if banHammerItem.Parent ~= character then
            LogItem("Ban Hammer AoE", "ABORT", "equip failed")
            return
        end
        
        LogTiming("Ban Hammer AoE", "equipped", tick() - startTime)
        
        -- ШАГ 3: Ждём инициализации (Equipped event должен отработать)
        task.wait(0.25)
        
        -- ШАГ 4: Используем ActionController для Charge + Release
        local RepStorage = game:GetService("ReplicatedStorage")
        local Controllers = RepStorage:FindFirstChild("Controllers")
        if not Controllers then
            LogItem("Ban Hammer AoE", "ABORT", "Controllers not found")
            return
        end
        
        local ActionController = require(Controllers:FindFirstChild("ActionController"))
        if not ActionController then
            LogItem("Ban Hammer AoE", "ABORT", "ActionController not found")
            return
        end
        
        -- Симулируем нажатие кнопки мыши - запускает зарядку
        LogItem("Ban Hammer AoE", "CHARGE", "firing Pressed")
        ActionController.Pressed:Fire()
        
        -- Ждём зарядки (из игры: ChargeMaxDuration = 2.5s, но можно отпустить раньше)
        -- Минимальная зарядка для MinRadius = 10 studs примерно 0.6-0.8 сек
        task.wait(TIMING.BAN_HAMMER_CHARGE)
        
        -- Симулируем отпускание кнопки - триггерит Release
        LogItem("Ban Hammer AoE", "RELEASE", "firing Released")
        ActionController.Released:Fire()
        
        LogTiming("Ban Hammer AoE", "attack_complete", tick() - startTime)
        
        -- Ждём анимации удара
        task.wait(0.3)
        
        success = true
    end)
    
    -- ШАГ 5: Восстанавливаем предыдущий инструмент
    task.wait(0.1)
    humanoid:UnequipTools()
    task.wait(0.05)
    
    if previousTool and previousTool.Parent == LocalPlayer.Backpack then
        humanoid:EquipTool(previousTool)
    end
    
    local totalTime = tick() - startTime
    LogItem("Ban Hammer AoE", "END", (success and "success" or "failed") .. " in " .. string.format("%.2f", totalTime) .. "s")
    
    return success
end

-- Check if our sentry still exists in workspace
local function IsSentryStillPlaced()
    if not OurSentryInstance then
        return false
    end
    
    -- Check if sentry still exists in workspace and belongs to us
    if not OurSentryInstance.Parent or OurSentryInstance.Parent ~= Workspace then
        OurSentryInstance = nil
        return false
    end
    
    -- Additional check: verify sentry has not been destroyed
    local success = pcall(function()
        local _ = OurSentryInstance.Name
    end)
    
    if not success then
        OurSentryInstance = nil
        return false
    end
    
    return true
end

-- Find our sentry in workspace (to re-track after respawn or loss of reference)
local function FindOurSentryInWorkspace()
    -- Look for sentry models in workspace that belong to us
    local playerName = LocalPlayer.Name
    
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") and (child.Name:find("Sentry") or child.Name:find("sentry")) then
            -- Check if this sentry has our name in it or is owned by us
            local ownerValue = child:FindFirstChild("Owner") or child:FindFirstChild("Player")
            if ownerValue and ownerValue:IsA("ObjectValue") and ownerValue.Value == LocalPlayer then
                return child
            end
            
            -- Alternative: check by name pattern (some sentries might have player name)
            if child.Name:find(playerName) then
                return child
            end
        end
    end
    
    return nil
end


-- Check and use AoE items if conditions are met
local LastAoECheckTime = 0
local AOE_CHECK_INTERVAL = 0.25  -- Интервал проверки AoE

-- НОВОЕ: Интервал для AoE когда есть телепортированная турель (менее агрессивно)
local AOE_CHECK_INTERVAL_SENTRY_PRIORITY = 0.75  -- Увеличенный интервал при атаке турели

local function CheckAndUseAoEItems()
    -- СТРОГИЙ THROTTLE: не проверяем AoE слишком часто
    local currentTime = tick()
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- FRIEND SAFE MODE: Блокировка AoE при друге в радиусе 100м
    -- ═══════════════════════════════════════════════════════════════════════
    -- FRIEND SAFE MODE: Блокировка AoE при друге в радиусе 100м
    -- НАПРАВЛЕННЫЕ предметы (Bee Launcher, Laser Cape, Taser Gun) РАЗРЕШЕНЫ!
    -- ═══════════════════════════════════════════════════════════════════════
    local friendSafeBlockAoE = Config.FriendSafeMode and FriendSafeState.AoEDisabled
    -- При friendSafeBlockAoE = true блокируем все кроме направленных (Bee, Laser Cape, Taser)
    
    -- НОВОЕ: Проверяем есть ли телепортированная вражеская турель
    local hasTeleportedSentry = false
    for sentry, data in pairs(TrackedEnemySentries) do
        if sentry and sentry.Parent and data.teleported then
            hasTeleportedSentry = true
            break
        end
    end
    
    -- КРИТИЧНО: Если есть телепортированная турель - ПОЛНОСТЬЮ блокируем AoE предметы
    -- Используем ТОЛЬКО цикл перчаток пока турель не будет уничтожена
    if hasTeleportedSentry then
        return  -- Выходим сразу, никакие AoE не используем
    end
    
    -- НОВОЕ: Если есть телепортированная турель - реже используем AoE (приоритет перчаткам)
    local checkInterval = hasTeleportedSentry and AOE_CHECK_INTERVAL_SENTRY_PRIORITY or AOE_CHECK_INTERVAL
    
    if currentTime - LastAoECheckTime < checkInterval then
        return
    end
    LastAoECheckTime = currentTime
    
    if not Config.Enabled then
        return
    end
    
    -- Don't check for SYNCHRONOUS AoE items if one is already being used
    -- Также блокируем если работает асинхронный предмет (AoEState.AsyncItemLock)
    local blockSyncItems = AoEState.IsUsingAoEItem or AoEState.AsyncItemLock
    
    -- Don't use AoE items if Quantum Cloner pause is active (используем уже объявленный currentTime)
    if currentTime < QuantumClonerPauseUntil then
        return
    end
    
    -- Use already detected enemies from FindClosestEnemy
    local enemiesInAoERange = 0
    local enemiesForMedusa = 0
    local enemiesForBoogie = 0
    local enemiesForSentry = 0
    local enemiesForMegaphone = 0
    local enemiesForTaser = 0
    local enemiesForBee = 0
    local enemiesForLaser = 0
    local enemiesForRageTable = 0
    local enemiesForLaserGun = 0
    local enemiesForHeatseeker = 0
    local enemiesForAttackDoge = 0
    local enemiesForBanHammer = 0  -- НОВОЕ: для Ban Hammer (радиус 10)
    local character = LocalPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    
    if rootPart then
        for _, enemyData in ipairs(AllDetectedEnemies) do
            if enemyData.distance <= DETECTION_RADIUS.MEDUSA then
                enemiesForMedusa = enemiesForMedusa + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.BOOGIE then
                enemiesForBoogie = enemiesForBoogie + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.SENTRY then
                enemiesForSentry = enemiesForSentry + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.MEGAPHONE then
                enemiesForMegaphone = enemiesForMegaphone + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.TASER then
                enemiesForTaser = enemiesForTaser + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.BEE then
                enemiesForBee = enemiesForBee + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.LASER_CAPE then
                enemiesForLaser = enemiesForLaser + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.RAGE_TABLE then
                enemiesForRageTable = enemiesForRageTable + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.LASER_GUN then
                enemiesForLaserGun = enemiesForLaserGun + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.HEATSEEKER then
                enemiesForHeatseeker = enemiesForHeatseeker + 1
            end
            if enemyData.distance <= DETECTION_RADIUS.ATTACK_DOGE then
                enemiesForAttackDoge = enemiesForAttackDoge + 1
            end
            -- НОВОЕ: Ban Hammer (радиус 10)
            if enemyData.distance <= DETECTION_RADIUS.BAN_HAMMER then
                enemiesForBanHammer = enemiesForBanHammer + 1
            end
        end
        
        enemiesInAoERange = math.max(enemiesForMedusa, enemiesForBoogie, enemiesForSentry, enemiesForMegaphone, enemiesForTaser, enemiesForBee, enemiesForLaser, enemiesForRageTable, enemiesForLaserGun, enemiesForHeatseeker, enemiesForAttackDoge, enemiesForBanHammer)
    end
    
    -- currentTime уже объявлен выше, не дублируем
    
    -- СИНХРОННЫЕ ПРЕДМЕТЫ: блокируются если используется любой AoE или асинхронный предмет
    -- Асинхронные предметы (Rage Table, Heatseeker, Attack Doge) проверяются отдельно ниже
    
    -- Try Medusa's Head first (priority 1) - need 1+ enemies within 15 studs
    -- AoE ПРЕДМЕТ - ЗАБЛОКИРОВАН в Friend Safe Mode!
    if not blockSyncItems and not friendSafeBlockAoE and enemiesForMedusa >= 1 then
        local medusaCooldown = GetItemCooldown("Medusa's Head")
        local medusaLastUse = LastAoEUseTime["Medusa's Head"] or 0
        local timeSinceLastMedusaUse = currentTime - medusaLastUse
        
        if medusaCooldown == 0 and timeSinceLastMedusaUse >= AOE_USE_COOLDOWN then
            local medusaItem = FindAoEItem("Medusa's Head")
            if medusaItem then
                StatusText = "AoE: Medusa's Head (" .. enemiesInAoERange .. " целей)"
                if UseAoEItem("Medusa's Head") then
                    LastAoEUseTime["Medusa's Head"] = currentTime
                    -- Don't block - return and continue main loop
                    return
                end
            end
        end
    end
    
    -- Try Boogie Bomb (priority 2, independent cooldown) - need 1+ enemies within 25 studs
    -- AoE ПРЕДМЕТ - ЗАБЛОКИРОВАН в Friend Safe Mode!
    if not blockSyncItems and not friendSafeBlockAoE and enemiesForBoogie >= 1 then
        local boogieCooldown = GetItemCooldown("Boogie Bomb")
        local boogieLastUse = LastAoEUseTime["Boogie Bomb"] or 0
        local timeSinceLastBoogieUse = currentTime - boogieLastUse
        
        if boogieCooldown == 0 and timeSinceLastBoogieUse >= AOE_USE_COOLDOWN then
            local boogieItem = FindAoEItem("Boogie Bomb")
            if boogieItem then
                StatusText = "AoE: Boogie Bomb (" .. enemiesInAoERange .. " целей)"
                if UseAoEItem("Boogie Bomb") then
                    LastAoEUseTime["Boogie Bomb"] = currentTime
                    -- Don't block - return and continue main loop
                    return
                end
            end
        end
    end
    
    -- All Seeing Sentry Logic (priority 3)
    -- Use sentry if:
    -- 1. Less than 2 enemies (1 enemy): Check if sentry is destroyed AND check cooldown
    -- 2. 2+ enemies: Only check cooldown (ignore if sentry exists or not)
    -- AoE ПРЕДМЕТ - ЗАБЛОКИРОВАН в Friend Safe Mode!
    
    local sentryStillExists = IsSentryStillPlaced()
    local shouldPlaceSentry = false
    
    if enemiesForSentry >= 2 then
        -- Case 1: 2+ enemies - always try to use (don't check if sentry exists)
        shouldPlaceSentry = true
    elseif enemiesForSentry >= 1 then
        -- Case 2: 1 enemy - only use if sentry is destroyed/not placed
        if not sentryStillExists then
            shouldPlaceSentry = true
        end
    end
    
    if not blockSyncItems and not friendSafeBlockAoE and shouldPlaceSentry then
        local sentryItem = FindAoEItem("All Seeing Sentry")
        if not sentryItem then
            return  -- No sentry item in inventory
        end
        
        local sentryLastUse = LastAoEUseTime["All Seeing Sentry"] or 0
        local timeSinceLastSentryUse = currentTime - sentryLastUse
        
        -- For sentry, we use ONLY our custom timer, ignore game cooldown
        -- Wait: 2 sec (AOE_USE_COOLDOWN) + 3 sec (SENTRY_ADDITIONAL_COOLDOWN) = 5 seconds total
        if timeSinceLastSentryUse >= (AOE_USE_COOLDOWN + SENTRY_ADDITIONAL_COOLDOWN) then
            local reasonText = ""
            if enemiesForSentry >= 2 then
                reasonText = "Sentry: 2+ целей (" .. enemiesForSentry .. ")"
            else
                reasonText = "Sentry: Размещение (" .. enemiesForSentry .. " цель)"
            end
            
            StatusText = reasonText
            if UseAoEItem("All Seeing Sentry") then
                LastAoEUseTime["All Seeing Sentry"] = currentTime
                SentrySystem.LastPlacementTime = currentTime
                
                -- Try to find our newly placed sentry after a short delay
                task.delay(1, function()
                    if not OurSentryInstance then
                        OurSentryInstance = FindOurSentryInWorkspace()
                    end
                end)
                
                return
            end
        end
    end
    
    -- Try Megaphone (priority 4, independent cooldown) - need 1+ enemies within 30 studs
    if not blockSyncItems and enemiesForMegaphone >= 1 then
        local megaphoneCooldown = GetItemCooldown("Megaphone")
        local megaphoneLastUse = LastAoEUseTime["Megaphone"] or 0
        local timeSinceLastMegaphoneUse = currentTime - megaphoneLastUse
        
        if megaphoneCooldown == 0 and timeSinceLastMegaphoneUse >= AOE_USE_COOLDOWN then
            local megaphoneItem = FindAoEItem("Megaphone")
            if megaphoneItem then
                StatusText = "Направленный: Megaphone (" .. enemiesForMegaphone .. " целей)"
                if UseAoEItem("Megaphone") then
                    LastAoEUseTime["Megaphone"] = currentTime
                    -- Don't block - return and continue main loop
                    return
                end
            end
        end
    end
    
    -- Try Taser Gun (priority 5, independent cooldown) - need 1+ enemies within 18 studs
    -- НАПРАВЛЕННЫЙ предмет - РАЗРЕШЕН в Friend Safe Mode!
    if not blockSyncItems and enemiesForTaser >= 1 then
        local taserCooldown = GetItemCooldown("Taser Gun")
        local taserLastUse = LastAoEUseTime["Taser Gun"] or 0
        local timeSinceLastTaserUse = currentTime - taserLastUse
        
        if taserCooldown == 0 and timeSinceLastTaserUse >= AOE_USE_COOLDOWN then
        local taserItem = FindAoEItem("Taser Gun")
        if taserItem then
            StatusText = "Направленный: Taser Gun (" .. enemiesForTaser .. " целей)"
            if UseAoEItem("Taser Gun") then
                LastAoEUseTime["Taser Gun"] = currentTime
                -- Don't block - return and continue main loop
                return
            end
        end
        end
    end
    
    -- Try Bee Launcher (priority 6, independent cooldown) - need 1+ enemies within 28 studs
    -- НАПРАВЛЕННЫЙ предмет - РАЗРЕШЕН в Friend Safe Mode!
    if not blockSyncItems and enemiesForBee >= 1 then
        local beeCooldown = GetItemCooldown("Bee Launcher")
        local beeLastUse = LastAoEUseTime["Bee Launcher"] or 0
        local timeSinceLastBeeUse = currentTime - beeLastUse
        
        if beeCooldown == 0 and timeSinceLastBeeUse >= AOE_USE_COOLDOWN then
        local beeItem = FindAoEItem("Bee Launcher")
        if beeItem then
            StatusText = "Направленный: Bee Launcher (" .. enemiesForBee .. " целей)"
            if UseAoEItem("Bee Launcher") then
                LastAoEUseTime["Bee Launcher"] = currentTime
                -- Don't block - return and continue main loop
                return
            end
        end
        end
    end
    
    -- Try Laser Cape (priority 7, independent cooldown) - need 1+ enemies within 60 studs
    -- Works independently beyond 40m, works with other items within 40m
    -- НАПРАВЛЕННЫЙ предмет - РАЗРЕШЕН в Friend Safe Mode!
    if not blockSyncItems and enemiesForLaser >= 1 then
        local laserItem = FindAoEItem("Laser Cape")
        if laserItem and not IsToolOnCooldown(laserItem) then
            local laserLastUse = LastAoEUseTime["Laser Cape"] or 0
            local timeSinceLastLaserUse = currentTime - laserLastUse
            
            -- Check if there are enemies beyond 40m but within 60m (independent range)
            local hasEnemiesBeyond40m = false
            for _, enemyData in ipairs(AllDetectedEnemies) do
                if enemyData.distance > 40 and enemyData.distance <= DETECTION_RADIUS.LASER_CAPE then
                    hasEnemiesBeyond40m = true
                    break
                end
            end
            
            -- Use Laser Cape if:
            -- 1. Enemies beyond 40m (independent operation)
            -- 2. Enemies within 40m (works with priority system like other items)
            if timeSinceLastLaserUse >= LASER_CAPE_USE_COOLDOWN then
                if hasEnemiesBeyond40m then
                    StatusText = "Laser Cape: Дальняя цель (" .. enemiesForLaser .. ")"
                else
                    StatusText = "Направленный: Laser Cape (" .. enemiesForLaser .. " целей)"
                end
                
                if UseAoEItem("Laser Cape") then
                    LastAoEUseTime["Laser Cape"] = currentTime
                    return
                end
            end
        end
    end
    
    -- Try Rage Table (priority 8, independent cooldown) - need 1+ enemies within 25 studs
    -- АСИНХРОННЫЙ: запускается когда нет других асинхронных предметов
    -- AoE ПРЕДМЕТ - ЗАБЛОКИРОВАН в Friend Safe Mode!
    -- DEBUG: проверяем почему не используется
    local rageTableItem = FindAoEItem("Rage Table")
    if rageTableItem and not friendSafeBlockAoE then
        if enemiesForRageTable < 1 then
            -- LogItem("Rage Table", "SKIP", "no enemies in range")
        elseif AoEState.AsyncItemLock then
            LogItem("Rage Table", "SKIP", "AoEState.AsyncItemLock active")
        else
            local onCD = IsToolOnCooldown(rageTableItem)
            local rageTableLastUse = LastAoEUseTime["Rage Table"] or 0
            local timeSinceLastRageTableUse = currentTime - rageTableLastUse
            
            if onCD then
                LogItem("Rage Table", "SKIP", "on cooldown")
            elseif timeSinceLastRageTableUse < AOE_USE_COOLDOWN then
                LogItem("Rage Table", "SKIP", "throttle " .. string.format("%.1f", timeSinceLastRageTableUse) .. "s")
            else
                LogItem("Rage Table", "USE", enemiesForRageTable .. " targets")
                StatusText = "Rage Table (" .. enemiesForRageTable .. ")"
                AoEState.IsUsingRageTable = true
                LastAoEUseTime["Rage Table"] = currentTime
                task.spawn(function()
                    local success = UseAoEItem("Rage Table", true)
                    LogItem("Rage Table", success and "DONE" or "FAIL")
                    AoEState.IsUsingRageTable = false
                end)
                return  -- Выходим - только один асинхронный за раз
            end
        end
    end
    
    -- Try Ban Hammer (priority 10) - need 1+ enemies within 10 studs
    -- АСИНХРОННЫЙ: требует Charge + Release через ActionController
    -- НЕ используется для турелей - только против игроков
    -- AoE ПРЕДМЕТ - ЗАБЛОКИРОВАН в Friend Safe Mode!
    if not hasTeleportedSentry and not friendSafeBlockAoE and enemiesForBanHammer >= 1 then
        local banHammerItem = CachedBanHammer or FindAoEItem("Ban Hammer")
        if banHammerItem then
            if AoEState.AsyncItemLock then
                LogItem("Ban Hammer", "SKIP", "AoEState.AsyncItemLock active")
            elseif AoEState.IsUsingBanHammer then
                LogItem("Ban Hammer", "SKIP", "already in use")
            else
                local onCD = IsToolOnCooldown(banHammerItem)
                local banHammerLastUse = LastAoEUseTime["Ban Hammer"] or 0
                local timeSinceLastBanHammerUse = currentTime - banHammerLastUse
                
                if onCD then
                    LogItem("Ban Hammer", "SKIP", "on cooldown")
                elseif timeSinceLastBanHammerUse < BAN_HAMMER_USE_COOLDOWN then
                    LogItem("Ban Hammer", "SKIP", "throttle " .. string.format("%.1f", timeSinceLastBanHammerUse) .. "s")
                else
                    LogItem("Ban Hammer", "USE", enemiesForBanHammer .. " targets within 10 studs")
                    StatusText = "Ban Hammer AoE (" .. enemiesForBanHammer .. ")"
                    AoEState.IsUsingBanHammer = true
                    AoEState.AsyncItemLock = true
                    LastAoEUseTime["Ban Hammer"] = currentTime
                    task.spawn(function()
                        local success = UseBanHammerAoE(banHammerItem)
                        LogItem("Ban Hammer", success and "DONE" or "FAIL")
                        AoEState.IsUsingBanHammer = false
                        AoEState.AsyncItemLock = false
                    end)
                    return  -- Выходим - только один асинхронный за раз
                end
            end
        end
    end
    
    -- Try Heatseeker (priority 11) - только если нет других асинхронных
    -- AoE ПРЕДМЕТ - ЗАБЛОКИРОВАН в Friend Safe Mode!
    -- DEBUG: проверяем почему не используется
    local heatseekerItem = FindAoEItem("Heatseeker")
    if heatseekerItem and not friendSafeBlockAoE then
        if enemiesForHeatseeker < 1 then
            -- LogItem("Heatseeker", "SKIP", "no enemies in range")
        elseif AoEState.AsyncItemLock then
            LogItem("Heatseeker", "SKIP", "AoEState.AsyncItemLock active")
        else
            local onCD = IsToolOnCooldown(heatseekerItem)
            local heatseekerLastUse = LastAoEUseTime["Heatseeker"] or 0
            local timeSinceLastHeatseekerUse = currentTime - heatseekerLastUse
            
            if onCD then
                LogItem("Heatseeker", "SKIP", "on cooldown")
            elseif timeSinceLastHeatseekerUse < AOE_USE_COOLDOWN then
                LogItem("Heatseeker", "SKIP", "throttle " .. string.format("%.1f", timeSinceLastHeatseekerUse) .. "s")
            else
                LogItem("Heatseeker", "USE", enemiesForHeatseeker .. " targets")
                StatusText = "Heatseeker (" .. enemiesForHeatseeker .. ")"
                AoEState.IsUsingHeatseeker = true
                LastAoEUseTime["Heatseeker"] = currentTime
                task.spawn(function()
                    local success = UseAoEItem("Heatseeker", true)
                    LogItem("Heatseeker", success and "DONE" or "FAIL")
                    AoEState.IsUsingHeatseeker = false
                end)
                return  -- Выходим - только один асинхронный за раз
            end
        end
    end
    
    -- Try Attack Doge (priority 12) - только если нет других асинхронных
    -- DEBUG: проверяем почему не используется
    -- Try Attack Doge (priority 12) - только если нет других асинхронных
    -- AoE ПРЕДМЕТ - ЗАБЛОКИРОВАН в Friend Safe Mode!
    -- DEBUG: проверяем почему не используется
    local attackDogeItem = FindAoEItem("Attack Doge")
    if attackDogeItem and not friendSafeBlockAoE then
        if enemiesForAttackDoge < 1 then
            -- LogItem("Attack Doge", "SKIP", "no enemies in range")
        elseif AoEState.AsyncItemLock then
            LogItem("Attack Doge", "SKIP", "AoEState.AsyncItemLock active")
        else
            local onCD = IsToolOnCooldown(attackDogeItem)
            local attackDogeLastUse = LastAoEUseTime["Attack Doge"] or 0
            local timeSinceLastAttackDogeUse = currentTime - attackDogeLastUse
            
            if onCD then
                LogItem("Attack Doge", "SKIP", "on cooldown")
            elseif timeSinceLastAttackDogeUse < AOE_USE_COOLDOWN then
                LogItem("Attack Doge", "SKIP", "throttle " .. string.format("%.1f", timeSinceLastAttackDogeUse) .. "s")
            else
                LogItem("Attack Doge", "USE", enemiesForAttackDoge .. " targets")
                StatusText = "Attack Doge (" .. enemiesForAttackDoge .. ")"
                AoEState.IsUsingAttackDoge = true
                LastAoEUseTime["Attack Doge"] = currentTime
                task.spawn(function()
                    local success = UseAoEItem("Attack Doge", true)
                    LogItem("Attack Doge", success and "DONE" or "FAIL")
                    AoEState.IsUsingAttackDoge = false
                end)
                return  -- Выходим - только один асинхронный за раз
            end
        end
    end
    
    -- DEBUG: Периодически логируем статус асинхронных предметов (раз в 5 сек)
    if not _G.LastAsyncStatusLog or currentTime - _G.LastAsyncStatusLog > 5 then
        _G.LastAsyncStatusLog = currentTime
        local hasHeatseeker = FindAoEItem("Heatseeker") ~= nil
        local hasAttackDoge = FindAoEItem("Attack Doge") ~= nil
        local hasRageTable = FindAoEItem("Rage Table") ~= nil
        Log("ASYNC_STATUS", "Heatseeker=" .. tostring(hasHeatseeker) .. " AttackDoge=" .. tostring(hasAttackDoge) .. " RageTable=" .. tostring(hasRageTable) .. " Lock=" .. tostring(AoEState.AsyncItemLock))
    end
end

-- ═══════════════════════════════════════════════════════════════════════
-- LASER GUN AUTO-EQUIP/FIRE/UNEQUIP СИСТЕМА (КАК LASER CAPE)
-- ═══════════════════════════════════════════════════════════════════════
local LastLaserGunCheckTime = 0
local LASER_GUN_CHECK_INTERVAL = 0.3  -- Минимум 0.3 сек между проверками

local function CheckAndUseLaserGun()
    -- СТРОГИЙ THROTTLE: не чаще раза в 0.3 секунды
    local currentTime = tick()
    if currentTime - LastLaserGunCheckTime < LASER_GUN_CHECK_INTERVAL then
        return
    end
    LastLaserGunCheckTime = currentTime
    
    if not Config.Enabled then
        return
    end
    
    -- Не запускаем если уже используется AoE или асинхронный предмет
    if AoEState.IsUsingLaserGun or AoEState.IsUsingAoEItem or IsAnyAsyncItemInUse() then
        return
    end
    
    -- Проверяем паузу Quantum Cloner (используем уже объявленный currentTime)
    if currentTime < QuantumClonerPauseUntil then
        return
    end
    
    -- НЕ проверяем LaserGunState.Ready - это может быть false если remote не найдены
    -- Laser Gun всё равно работает через UseAoEItem → обычная активация
    
    -- Находим врагов в радиусе 300м
    local enemiesForLaserGun = 0
    local closestEnemy = nil
    local closestDist = math.huge
    
    for _, enemyData in ipairs(AllDetectedEnemies) do
        if enemyData.distance <= DETECTION_RADIUS.LASER_GUN then
            enemiesForLaserGun = enemiesForLaserGun + 1
            if enemyData.distance < closestDist then
                closestEnemy = enemyData.player
                closestDist = enemyData.distance
            end
        end
    end
    
    -- Если нет врагов - выходим
    if enemiesForLaserGun < 1 or not closestEnemy then
        return
    end
    
    -- Проверяем кулдаун (используем константу из AoEState)
    local laserGunLastUse = LastAoEUseTime["Laser Gun"] or 0
    local timeSinceLastLaserGunUse = currentTime - laserGunLastUse
    
    -- НЕ экипируем пока не прошла перезарядка
    if timeSinceLastLaserGunUse < AoEState.LASER_GUN_USE_COOLDOWN then
        return
    end
    
    -- Ищем Laser Gun в инвентаре
    local laserGunItem = FindAoEItem("Laser Gun")
    if not laserGunItem then
        return
    end
    
    -- Используем (экипируем, стреляем, снимаем)
    UseAoEItem("Laser Gun")
    LastAoEUseTime["Laser Gun"] = currentTime
end



-- Equip tool remotely (without using hotkeys)
local function EquipTool(tool)
    -- Don't equip any tool if SYNC AoE item is being used
    -- AoEState.AsyncItemLock НЕ блокирует - async предметы работают параллельно с перчатками
    if AoEState.IsUsingAoEItem then
        return false
    end
    
    -- Don't equip any tool if Quantum Cloner pause is active
    local currentTime = tick()
    if currentTime < QuantumClonerPauseUntil then
        return false
    end
    
    if not tool or not tool:IsA("Tool") then
        return false
    end
    
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end
    
    -- Try to equip the tool
    local success = pcall(function()
        -- If tool is in backpack, move it to character
        if tool.Parent == LocalPlayer.Backpack then
            humanoid:EquipTool(tool)
        elseif tool.Parent ~= character then
            -- Tool might be somewhere else, try to parent it first
            tool.Parent = character
        end
    end)
    
    if success then
        EquippedTool = tool
        return true
    end
    
    return false
end

-- Find best tool for combat
local function FindBestTool()
    local tools, gloves = ScanInventory()
    
    -- Check if we have 4+ gloves
    if #gloves >= 4 then
        -- Check if there's a teleported enemy sentry (always use gloves for sentries)
        local hasTeleportedSentry = false
        for sentry, data in pairs(TrackedEnemySentries) do
            if sentry and sentry.Parent and data.teleported then
                hasTeleportedSentry = true
                break
            end
        end
        
        -- If there's a teleported sentry, always use gloves (sentry is always close)
        if hasTeleportedSentry then
            if CurrentGloveIndex > #gloves then
                CurrentGloveIndex = 1
            end
            return gloves[CurrentGloveIndex]
        end
        
        -- Check distance to current target
        local distanceToTarget = math.huge
        
        if CurrentTarget then
            local character = LocalPlayer.Character
            local targetChar = CurrentTarget.Character
            
            if character and targetChar then
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
                
                if rootPart and targetRoot then
                    distanceToTarget = (rootPart.Position - targetRoot.Position).Magnitude
                end
            end
        end
        
        -- Only use glove rotation if target is within 45m
        if distanceToTarget <= 45 then
            -- Return current glove from rotation
            if CurrentGloveIndex > #gloves then
                CurrentGloveIndex = 1
            end
            return gloves[CurrentGloveIndex]
        end
        -- If target is beyond 45m, fall through to look for bat
    end
    
    -- If less than 4 gloves OR target beyond 45m, look for "bat" tool only
    for _, tool in ipairs(tools) do
        if tool.Name:lower():find("bat") then
            return tool
        end
    end
    
    -- No bat found, return nil
    return nil
end

-- Switch to next glove in rotation
-- ИЗМЕНЕНО: Ротация slap-перчаток + Gummy Bear (если есть)
-- Ban Hammer используется ОТДЕЛЬНО через AoE систему
local function SwitchToNextGlove()
    -- Don't switch gloves if Quantum Cloner pause is active
    local currentTime = tick()
    if currentTime < QuantumClonerPauseUntil then
        return false
    end
    
    -- Don't switch gloves during SYNC AoE usage only
    -- AoEState.AsyncItemLock НЕ блокирует - перчатки работают параллельно с async предметами
    if AoEState.IsUsingAoEItem then
        return false
    end
    
    local tools, gloves = ScanInventory()
    
    if #gloves < 4 then
        return false  -- Don't switch if less than 4 gloves
    end
    
    -- Непрерывный цикл - переходим к следующей перчатке
    -- Gummy Bear в конце списка - используется обязательно если есть
    CurrentGloveIndex = CurrentGloveIndex + 1
    if CurrentGloveIndex > #gloves then
        CurrentGloveIndex = 1
    end
    
    local nextGlove = gloves[CurrentGloveIndex]
    if nextGlove then
        -- Для Gummy Bear ждём немного дольше после атаки (Cooldown 0.7s)
        local equipped = EquipTool(nextGlove)
        
        -- Минимальная задержка после экипировки
        if equipped then
            task.wait(TIMING.GLOVE_SWITCH_WAIT)
            LogGlove("SWITCH", nextGlove.Name, "idx=" .. CurrentGloveIndex .. "/" .. #gloves)
            return true
        end
    end
    
    -- Если текущая перчатка не экипировалась - пробуем первую доступную
    for i, glove in ipairs(gloves) do
        if glove then
            CurrentGloveIndex = i
            local equipped = EquipTool(glove)
            if equipped then
                return true
            end
        end
    end
    
    return false
end

-- Check if player is an enemy (not yourself, not in same team, not in friend list)
local function IsEnemy(player)
    if player == LocalPlayer then
        return false
    end
    
    -- Check if player is in friend list
    if IsInFriendList(player) then
        return false
    end
    
    -- Check if same team
    if player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
        return false
    end
    
    return true
end

-- Create/Update markers for all detected enemies
local LastMarkerUpdate = 0
local MARKER_UPDATE_INTERVAL = 1.5  -- Увеличено с 1.0 до 1.5 сек
local LastForcedMarkerCleanup = 0
local FORCED_MARKER_CLEANUP_INTERVAL = 20  -- Уменьшено с 30 до 20 сек для частой очистки

-- Безопасное удаление Instance
local function SafeDestroy(instance)
    if instance then
        local success = pcall(function()
            if instance.Parent then
                instance.Parent = nil
            end
            instance:Destroy()
        end)
        return success
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════════════
-- ENEMY SENTRY STEALER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════

-- Проверка, является ли объект турелью All Seeing Sentry
local function IsEnemySentryObject(object)
    if not object then
        return false
    end
    
    if not (object:IsA("BasePart") or object:IsA("Model")) then
        return false
    end
    
    local name = object.Name
    
    if name:match("^Sentry_%d+$") then
        return true
    end
    
    local nameLower = name:lower()
    if nameLower:find("sentry") or nameLower:find("all seeing") or nameLower:find("allseeing") then
        return true
    end
    
    return false
end

-- Получить владельца турели
local function GetEnemySentryOwner(sentry)
    if not sentry then
        return nil, nil
    end
    
    local sentryName = sentry.Name
    local userIdFromName = sentryName:match("^Sentry_(%d+)$")
    if userIdFromName then
        local userId = tonumber(userIdFromName)
        if userId then
            local player = Players:GetPlayerByUserId(userId)
            return player, userId
        end
    end
    
    local tags = CollectionService:GetTags(sentry)
    for _, tag in ipairs(tags) do
        local userIdFromTag = tag:match("^Player_(%d+)$")
        if userIdFromTag then
            local userId = tonumber(userIdFromTag)
            if userId then
                local player = Players:GetPlayerByUserId(userId)
                return player, userId
            end
        end
    end
    
    local ownerUserId = sentry:GetAttribute("OwnerUserId")
    if ownerUserId then
        local player = Players:GetPlayerByUserId(ownerUserId)
        return player, ownerUserId
    end
    
    local ownerValue = sentry:FindFirstChild("Owner") or sentry:FindFirstChild("Player")
    if ownerValue and ownerValue:IsA("ObjectValue") and ownerValue.Value then
        if ownerValue.Value:IsA("Player") then
            return ownerValue.Value, ownerValue.Value.UserId
        end
    end
    
    local creatorId = sentry:GetAttribute("CreatorId") or sentry:GetAttribute("Creator")
    if creatorId and type(creatorId) == "number" then
        local player = Players:GetPlayerByUserId(creatorId)
        return player, creatorId
    end
    
    return nil, nil
end

-- Проверка, является ли турель вражеской
local function IsEnemySentryCheck(sentry)
    if not sentry then
        return false
    end
    
    local ownerPlayer, ownerUserId = GetEnemySentryOwner(sentry)
    
    if not ownerPlayer and not ownerUserId then
        if sentry.Name:find(LocalPlayer.Name) then
            return false
        end
        return false
    end
    
    if ownerUserId == LocalPlayer.UserId then
        return false
    end
    
    if ownerPlayer then
        if ownerPlayer.Team and LocalPlayer.Team and ownerPlayer.Team == LocalPlayer.Team then
            return false
        end
    end
    
    return true
end

-- Получить позицию турели
local function GetEnemySentryPosition(sentry)
    if sentry:IsA("BasePart") then
        return sentry.Position
    elseif sentry:IsA("Model") then
        return sentry:GetPivot().Position
    end
    return nil
end

-- Проверка, активирована ли турель (не в состоянии "Ready")
local function IsSentryActivated(sentry)
    if not sentry or not sentry.Parent then
        return false
    end
    
    -- Проверяем BillboardGui с текстом "Ready"
    for _, descendant in ipairs(sentry:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
            local text = descendant.Text:lower()
            if text:find("ready") or text:find("sentry ready") then
                return false  -- Турель ещё не активирована
            end
        end
    end
    
    -- Проверяем атрибуты
    local isReady = sentry:GetAttribute("Ready") or sentry:GetAttribute("SentryReady") or sentry:GetAttribute("IsReady")
    if isReady == true then
        return false  -- Турель в состоянии Ready - не активирована
    end
    
    -- Проверяем атрибут Activated
    local isActivated = sentry:GetAttribute("Activated") or sentry:GetAttribute("IsActivated") or sentry:GetAttribute("Active")
    if isActivated == false then
        return false  -- Турель не активирована
    end
    
    -- Проверяем наличие активных частей (лазер, свечение)
    local hasActiveBeam = false
    for _, descendant in ipairs(sentry:GetDescendants()) do
        if descendant:IsA("Beam") or descendant:IsA("PointLight") or descendant:IsA("SpotLight") then
            if descendant.Enabled then
                hasActiveBeam = true
                break
            end
        end
    end
    
    -- Если есть активный луч/свет - турель активирована
    if hasActiveBeam then
        return true
    end
    
    -- По умолчанию считаем активированной если прошло достаточно времени (спаун задержка)
    return true
end

-- Получить время до активации турели (для телепортации заранее)
local function GetTimeToSentryActivation(sentry)
    if not sentry or not sentry.Parent then
        return 0
    end
    
    -- Ищем таймер или индикатор времени на турели
    for _, descendant in ipairs(sentry:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
            local text = descendant.Text
            -- Пытаемся найти число секунд (например "5s", "3", "Ready in 2")
            local timeMatch = text:match("(%d+%.?%d*)%s*s") or text:match("(%d+%.?%d*)")
            if timeMatch then
                local timeValue = tonumber(timeMatch)
                if timeValue and timeValue > 0 and timeValue <= 30 then
                    return timeValue
                end
            end
        end
    end
    
    -- Проверяем атрибуты с временем
    local activateTime = sentry:GetAttribute("ActivateTime") or sentry:GetAttribute("TimeToActivate")
    if activateTime and type(activateTime) == "number" then
        return activateTime
    end
    
    return 0  -- Неизвестно
end

-- Проверить, готова ли турель к телепортации (1 секунда до активации или уже активна)
local function IsSentryReadyForTeleport(sentry)
    if not sentry or not sentry.Parent then
        return false
    end
    
    -- Если уже активирована - телепортируем
    if IsSentryActivated(sentry) then
        return true
    end
    
    -- Проверяем время до активации
    local timeToActivation = GetTimeToSentryActivation(sentry)
    if timeToActivation > 0 and timeToActivation <= 1.5 then
        return true  -- Менее 1.5 секунды до активации - телепортируем
    end
    
    -- Проверяем признаки скорой активации (изменение цвета, эффекты)
    for _, descendant in ipairs(sentry:GetDescendants()) do
        -- Проверяем мигание или изменение свечения
        if descendant:IsA("PointLight") or descendant:IsA("SpotLight") then
            if descendant.Enabled and descendant.Brightness > 0.5 then
                return true  -- Свет включается - скоро активация
            end
        end
        -- Проверяем появление красного/желтого цвета (предупреждение)
        if descendant:IsA("BasePart") and descendant.Color then
            local color = descendant.Color
            if color.R > 0.8 and color.G < 0.5 then
                -- Красноватый цвет - возможно предупреждение об активации
                return true
            end
        end
    end
    
    return false
end

-- Создать/обновить сферу радиуса для турели (независимо от телепортации)
local function CreateOrUpdateSentrySphere(sentry, position)
    if not sentry or not position then return nil end
    
    local existingSphere = SentryRadiusSpheres[sentry]
    
    if existingSphere and existingSphere.Parent then
        -- Обновляем позицию существующей сферы
        existingSphere.Position = position
        return existingSphere
    end
    
    -- Создаём новую сферу
    local radiusSphere = Instance.new("Part")
    radiusSphere.Name = "SentryRadiusSphere_" .. (sentry.Name or "Unknown")
    radiusSphere.Shape = Enum.PartType.Ball
    radiusSphere.Size = Vector3.new(ENEMY_SENTRY_ATTACK_RADIUS * 2, ENEMY_SENTRY_ATTACK_RADIUS * 2, ENEMY_SENTRY_ATTACK_RADIUS * 2)
    radiusSphere.Anchored = true
    radiusSphere.CanCollide = false
    radiusSphere.CanTouch = false
    radiusSphere.CanQuery = false
    radiusSphere.Position = position
    radiusSphere.Color = Color3.fromRGB(255, 30, 30)
    radiusSphere.Material = Enum.Material.ForceField
    radiusSphere.Transparency = 0.8  -- Базовая прозрачность
    radiusSphere.CastShadow = false
    radiusSphere.Parent = Workspace
    
    SentryRadiusSpheres[sentry] = radiusSphere
    return radiusSphere
end

-- Удалить сферу радиуса для турели
local function RemoveSentrySphere(sentry)
    local sphere = SentryRadiusSpheres[sentry]
    if sphere then
        pcall(function()
            sphere:Destroy()
        end)
        SentryRadiusSpheres[sentry] = nil
    end
end

-- Обновить все сферы (мигание при приближении игрока)
local function UpdateAllSentrySpheres()
    local character = LocalPlayer.Character
    if not character then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    
    local playerPos = rootPart.Position
    local currentTime = tick()
    
    -- Частота мигания ОЧЕНЬ ВЫСОКАЯ (20 Hz) для интенсивного эффекта
    local flashPhase = math.sin(currentTime * 20) * 0.5 + 0.5
    -- Дополнительная быстрая пульсация для "тревожного" эффекта
    local fastPulse = math.sin(currentTime * 40) * 0.5 + 0.5
    
    for sentry, sphere in pairs(SentryRadiusSpheres) do
        if sphere and sphere.Parent and sentry and sentry.Parent then
            local sentryPos = sphere.Position
            local distance = (playerPos - sentryPos).Magnitude
            
            -- Расстояние до ЦЕНТРА турели (не до края сферы)
            if distance <= ENEMY_SENTRY_ATTACK_RADIUS then
                -- ВНУТРИ сферы - ОЧЕНЬ ИНТЕНСИВНОЕ мигание красным/жёлтым (ОПАСНОСТЬ!)
                local combinedFlash = flashPhase * 0.6 + fastPulse * 0.4
                local baseTransparency = 0.15  -- Очень видимая
                local flashAmount = combinedFlash * 0.35
                sphere.Transparency = baseTransparency + flashAmount
                -- Мигание между красным и жёлтым для тревоги
                local r = 255
                local g = math.floor(50 + 180 * combinedFlash)  -- От красного к жёлтому
                local b = math.floor(30 * combinedFlash)
                sphere.Color = Color3.fromRGB(r, g, b)
            elseif distance <= ENEMY_SENTRY_ATTACK_RADIUS + 10 then
                -- ОЧЕНЬ БЛИЗКО (10 studs от края) - интенсивное мигание
                local proximityFactor = 1 - (distance - ENEMY_SENTRY_ATTACK_RADIUS) / 10
                local combinedFlash = flashPhase * 0.7 + fastPulse * 0.3 * proximityFactor
                local baseTransparency = 0.25 - proximityFactor * 0.1
                local flashAmount = combinedFlash * 0.3 * (0.5 + proximityFactor * 0.5)
                sphere.Transparency = baseTransparency + flashAmount
                -- Мигание между красным и оранжевым
                local r = 255
                local g = math.floor(30 + 100 * combinedFlash * proximityFactor)
                sphere.Color = Color3.fromRGB(r, g, 0)
            elseif distance <= ENEMY_SENTRY_ATTACK_RADIUS + 25 then
                -- Близко (25 studs от края) - заметное мигание
                local proximityFactor = 1 - (distance - ENEMY_SENTRY_ATTACK_RADIUS - 10) / 15
                local baseTransparency = 0.45 - proximityFactor * 0.15
                local flashAmount = flashPhase * 0.25 * proximityFactor
                sphere.Transparency = baseTransparency + flashAmount
                sphere.Color = Color3.fromRGB(255, math.floor(30 + 30 * (1 - proximityFactor)), 30)
            elseif distance <= ENEMY_SENTRY_ATTACK_RADIUS + 45 then
                -- Приближаемся (45 studs от края) - лёгкое мигание
                local proximityFactor = 1 - (distance - ENEMY_SENTRY_ATTACK_RADIUS - 25) / 20
                local baseTransparency = 0.65 - proximityFactor * 0.15
                local flashAmount = flashPhase * 0.15 * proximityFactor
                sphere.Transparency = baseTransparency + flashAmount
                sphere.Color = Color3.fromRGB(255, 30, 30)
            else
                -- Далеко - базовая видимость без мигания
                sphere.Transparency = 0.75
                sphere.Color = Color3.fromRGB(255, 30, 30)
            end
        else
            -- Очистка невалидных сфер
            if sphere and not sphere.Parent then
                SentryRadiusSpheres[sentry] = nil
            end
        end
    end
end

-- Микро-движение турели чтобы она разрушилась
local function MicroMoveEnemySentry(sentry, data)
    if not sentry or not sentry.Parent then
        return false
    end
    
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return false
    end
    
    local currentTime = tick()
    if currentTime - EnemySentrySystem.LastMicroMove < ENEMY_SENTRY_MICRO_MOVE_INTERVAL then
        return true
    end
    EnemySentrySystem.LastMicroMove = currentTime
    
    data.microMovePhase = (data.microMovePhase or 0) + 1
    local phase = data.microMovePhase % 4
    
    local microOffsets = {
        Vector3.new(0.3, 0, 0),
        Vector3.new(0, 0, 0.3),
        Vector3.new(-0.3, 0, 0),
        Vector3.new(0, 0, -0.3),
    }
    
    local microOffset = microOffsets[phase + 1] or Vector3.new(0, 0, 0)
    
    -- Используем LookVector чтобы турель всегда была СПЕРЕДИ игрока
    local lookVector = rootPart.CFrame.LookVector
    local basePosition = rootPart.Position + lookVector * ENEMY_SENTRY_TELEPORT_OFFSET.Z
    local targetPosition = basePosition + microOffset
    local targetCFrame = CFrame.new(targetPosition)
    
    pcall(function()
        if sentry:IsA("BasePart") then
            sentry.CFrame = targetCFrame
        elseif sentry:IsA("Model") then
            sentry:PivotTo(targetCFrame)
        end
    end)
    
    return true
end

-- Телепортация вражеской турели
-- Создать визуальную копию турели на исходной позиции с красным очертанием и красной сферой
local function CreateSentryVisualCopy(sentry, originalPosition, originalCFrame)
    if not sentry then return nil end
    
    local visualData = {}
    
    -- Создаём Model для копии турели
    local copyModel = Instance.new("Model")
    copyModel.Name = "SentryVisualCopy_" .. (sentry.Name or "Unknown")
    
    -- Создаём копию Part - ЯРКО-КРАСНАЯ СВЕТЯЩАЯСЯ
    local copyPart = Instance.new("Part")
    copyPart.Name = "SentryBody"
    copyPart.Size = Vector3.new(4, 4, 4)  -- Размер оригинальной турели
    copyPart.Anchored = true
    copyPart.CanCollide = false
    copyPart.CanTouch = false
    copyPart.CanQuery = false
    copyPart.Transparency = 0.4  -- Немного прозрачная
    copyPart.Color = Color3.fromRGB(255, 50, 50)  -- ЯРКО-КРАСНЫЙ
    copyPart.Material = Enum.Material.Neon  -- Светящийся материал
    copyPart.CFrame = originalCFrame or CFrame.new(originalPosition)
    copyPart.Parent = copyModel
    
    -- Копируем Mesh с турели (из sentryturret: MeshId=68388933, TextureId=68237809, Scale=2,2,2)
    pcall(function()
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.FileMesh
        mesh.MeshId = "http://www.roblox.com/asset/?id=68388933"
        mesh.TextureId = ""  -- Без текстуры для красного цвета
        mesh.Scale = Vector3.new(2, 2, 2)
        mesh.Parent = copyPart
    end)
    
    -- Добавляем PointLight для СВЕЧЕНИЯ (glow эффект)
    local pointLight = Instance.new("PointLight")
    pointLight.Name = "SentryGlow"
    pointLight.Color = Color3.fromRGB(255, 50, 50)  -- Красный свет
    pointLight.Brightness = 3  -- Яркость
    pointLight.Range = 15  -- Радиус свечения
    pointLight.Shadows = false
    pointLight.Parent = copyPart
    
    copyModel.PrimaryPart = copyPart
    copyModel.Parent = Workspace
    
    -- КРАСНЫЙ Highlight для очертания (применяем к Model) - ЯРКИЙ КОНТУР + ЗАЛИВКА
    local highlight = Instance.new("Highlight")
    highlight.Name = "SentryRedHighlight"
    highlight.Adornee = copyModel
    highlight.FillColor = Color3.fromRGB(255, 30, 30)  -- Ярко-красная заливка
    highlight.FillTransparency = 0.7  -- Полупрозрачная заливка (glow эффект)
    highlight.OutlineColor = Color3.fromRGB(255, 100, 100)  -- Яркая обводка
    highlight.OutlineTransparency = 0  -- Полностью видимый контур
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = copyModel
    
    visualData.copyModel = copyModel
    visualData.copyPart = copyPart
    visualData.highlight = highlight
    visualData.pointLight = pointLight
    
    -- НЕ создаём отдельную сферу - используем уже существующую из SentryRadiusSpheres
    -- Это предотвращает дублирование сфер
    visualData.radiusSphere = nil  -- Сфера управляется через SentryRadiusSpheres
    
    return visualData
end

-- Удалить визуальную копию турели
local function RemoveSentryVisualCopy(visualData)
    if not visualData then return end
    
    pcall(function()
        if visualData.radiusSphere then visualData.radiusSphere:Destroy() end
        if visualData.pointLight then visualData.pointLight:Destroy() end
        if visualData.highlight then visualData.highlight:Destroy() end
        if visualData.copyModel then visualData.copyModel:Destroy() end
        if visualData.copyPart then visualData.copyPart:Destroy() end
    end)
end

-- Показать красный крест на месте уничтоженной турели
local function ShowDestructionCross(position)
    local crossPart = Instance.new("Part")
    crossPart.Name = "SentryDestructionCross"
    crossPart.Size = Vector3.new(1, 1, 1)
    crossPart.Anchored = true
    crossPart.CanCollide = false
    crossPart.CanTouch = false
    crossPart.CanQuery = false
    crossPart.Transparency = 1
    crossPart.Position = position
    crossPart.Parent = Workspace
    
    -- Создаём BillboardGui с красным крестом
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "CrossBillboard"
    billboard.Adornee = crossPart
    billboard.Size = UDim2.new(6, 0, 6, 0)
    billboard.StudsOffset = Vector3.new(0, 2, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = crossPart
    
    -- Фрейм для креста (две пересекающиеся линии)
    local crossFrame = Instance.new("Frame")
    crossFrame.Name = "CrossFrame"
    crossFrame.Size = UDim2.new(1, 0, 1, 0)
    crossFrame.BackgroundTransparency = 1
    crossFrame.Parent = billboard
    
    -- Линия 1 (диагональ \)
    local line1 = Instance.new("Frame")
    line1.Name = "Line1"
    line1.Size = UDim2.new(1.2, 0, 0, 8)
    line1.Position = UDim2.new(-0.1, 0, 0.5, -4)
    line1.AnchorPoint = Vector2.new(0, 0)
    line1.Rotation = 45
    line1.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    line1.BorderSizePixel = 0
    line1.Parent = crossFrame
    
    local line1Corner = Instance.new("UICorner")
    line1Corner.CornerRadius = UDim.new(0, 4)
    line1Corner.Parent = line1
    
    -- Линия 2 (диагональ /)
    local line2 = Instance.new("Frame")
    line2.Name = "Line2"
    line2.Size = UDim2.new(1.2, 0, 0, 8)
    line2.Position = UDim2.new(-0.1, 0, 0.5, -4)
    line2.AnchorPoint = Vector2.new(0, 0)
    line2.Rotation = -45
    line2.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    line2.BorderSizePixel = 0
    line2.Parent = crossFrame
    
    local line2Corner = Instance.new("UICorner")
    line2Corner.CornerRadius = UDim.new(0, 4)
    line2Corner.Parent = line2
    
    -- Анимация исчезновения через 2 секунды
    task.spawn(function()
        task.wait(1.5)
        for i = 1, 10 do
            local transparency = i * 0.1
            line1.BackgroundTransparency = transparency
            line2.BackgroundTransparency = transparency
            task.wait(0.05)
        end
        pcall(function()
            crossPart:Destroy()
        end)
    end)
    
    return crossPart
end

-- Показать виньетку экрана при уничтожении турели
local function ShowSentryDestructionVignette()
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return end
        
        -- Создаём временный ScreenGui для виньетки
        local vignetteGui = Instance.new("ScreenGui")
        vignetteGui.Name = "SentryDestructionVignette"
        vignetteGui.ResetOnSpawn = false
        vignetteGui.DisplayOrder = 999
        vignetteGui.IgnoreGuiInset = true
        vignetteGui.Parent = playerGui
        
        -- Голубая-бриллиантовая виньетка по краям экрана
        local vignetteFrame = Instance.new("Frame")
        vignetteFrame.Name = "VignetteFrame"
        vignetteFrame.Size = UDim2.new(1, 0, 1, 0)
        vignetteFrame.Position = UDim2.new(0, 0, 0, 0)
        vignetteFrame.BackgroundColor3 = Color3.fromRGB(0, 200, 255)  -- Голубой-бриллиантовый
        vignetteFrame.BackgroundTransparency = 0.85
        vignetteFrame.BorderSizePixel = 0
        vignetteFrame.Parent = vignetteGui
        
        -- UIGradient для эффекта виньетки (темнее по краям)
        local gradient = Instance.new("UIGradient")
        gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 180, 255)),
            ColorSequenceKeypoint.new(0.3, Color3.fromRGB(100, 220, 255)),
            ColorSequenceKeypoint.new(0.7, Color3.fromRGB(100, 220, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 180, 255))
        })
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.4, 0.95),
            NumberSequenceKeypoint.new(0.6, 0.95),
            NumberSequenceKeypoint.new(1, 0)
        })
        gradient.Parent = vignetteFrame
        
        -- Текст уведомления
        local notifyLabel = Instance.new("TextLabel")
        notifyLabel.Name = "NotifyText"
        notifyLabel.Size = UDim2.new(0.5, 0, 0.1, 0)
        notifyLabel.Position = UDim2.new(0.25, 0, 0.1, 0)
        notifyLabel.BackgroundTransparency = 1
        notifyLabel.Text = "✨ SENTRY DESTROYED ✨"
        notifyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        notifyLabel.TextScaled = true
        notifyLabel.Font = Enum.Font.GothamBold
        notifyLabel.Parent = vignetteGui
        
        local notifyStroke = Instance.new("UIStroke")
        notifyStroke.Color = Color3.fromRGB(0, 200, 255)  -- Голубой-бриллиантовый
        notifyStroke.Thickness = 2
        notifyStroke.Parent = notifyLabel
        
        -- Анимация исчезновения
        task.spawn(function()
            task.wait(0.5)
            for i = 1, 20 do
                vignetteFrame.BackgroundTransparency = 0.85 + (i * 0.0075)
                notifyLabel.TextTransparency = i * 0.05
                notifyStroke.Transparency = i * 0.05
                task.wait(0.03)
            end
            pcall(function()
                vignetteGui:Destroy()
            end)
        end)
    end)
end

-- Телепортация вражеской турели (с созданием визуальной копии и увеличением размера)
local function TeleportEnemySentry(sentry, data)
    if not sentry or not sentry.Parent then
        return false
    end
    
    local character = LocalPlayer.Character
    if not character then
        return false
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return false
    end
    
    -- Сохраняем оригинальную позицию и CFrame
    local originalPosition = nil
    local originalCFrame = nil
    pcall(function()
        if sentry:IsA("BasePart") then
            originalPosition = sentry.Position
            originalCFrame = sentry.CFrame
        elseif sentry:IsA("Model") then
            originalPosition = sentry:GetPivot().Position
            originalCFrame = sentry:GetPivot()
        end
    end)
    
    -- Визуальная копия уже создана в ProcessEnemySentryVisuals
    -- Просто обновляем originalPosition если ещё не сохранена
    if originalPosition and data then
        data.originalPosition = originalPosition
        -- Если копия уже есть - не создаём новую
        if not data.visualCopy then
            data.visualCopy = CreateSentryVisualCopy(sentry, originalPosition, originalCFrame)
            EnemySentryVisualCopies[sentry] = data.visualCopy
        end
    end
    
    -- Настраиваем физику и УВЕЛИЧИВАЕМ РАЗМЕР в 2 раза, делаем полупрозрачной
    pcall(function()
        if sentry:IsA("BasePart") then
            sentry.CanCollide = false
            sentry.CanTouch = true
            sentry.CanQuery = false
            sentry.Massless = true
            sentry.Anchored = true
            sentry.Size = sentry.Size * ENEMY_SENTRY_SIZE_MULTIPLIER  -- 2x размер (8x8x8)
            sentry.Transparency = ENEMY_SENTRY_TRANSPARENCY  -- Полупрозрачная
        end
        
        for _, part in ipairs(sentry:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
                part.CanTouch = true
                part.CanQuery = false
                part.Massless = true
                part.Anchored = true
                part.Size = part.Size * ENEMY_SENTRY_SIZE_MULTIPLIER  -- 2x размер
                part.Transparency = ENEMY_SENTRY_TRANSPARENCY  -- Полупрозрачная
            end
            -- Увеличиваем масштаб mesh если есть
            if part:IsA("SpecialMesh") or part:IsA("FileMesh") then
                part.Scale = part.Scale * ENEMY_SENTRY_SIZE_MULTIPLIER
            end
        end
    end)
    
    local targetPosition = rootPart.Position + rootPart.CFrame.LookVector * ENEMY_SENTRY_TELEPORT_OFFSET.Z
    local targetCFrame = CFrame.new(targetPosition)
    
    pcall(function()
        if sentry:IsA("BasePart") then
            sentry.CFrame = targetCFrame
        elseif sentry:IsA("Model") then
            sentry:PivotTo(targetCFrame)
        end
    end)
    
    return true
end

-- Обработка ТОЛЬКО визуальной части турели (сферы, копии) - работает независимо от Config.Enabled
local function ProcessEnemySentryVisuals(sentry)
    if not TrackedEnemySentries[sentry] then
        return
    end
    
    local data = TrackedEnemySentries[sentry]
    
    if not sentry or not sentry.Parent then
        return  -- Очистка происходит в ProcessEnemySentry
    end
    
    -- Получаем позицию турели
    local sentryPos = GetEnemySentryPosition(sentry)
    
    -- Создаём/обновляем сферу радиуса:
    -- - Для нетелепортированных: на текущей позиции турели
    -- - Для телепортированных: на originalPosition (место спавна)
    if not data.teleported then
        if sentryPos then
            CreateOrUpdateSentrySphere(sentry, sentryPos)
        end
    else
        -- Турель телепортирована - сфера должна оставаться на месте спавна!
        if data.originalPosition then
            CreateOrUpdateSentrySphere(sentry, data.originalPosition)
        end
    end
    
    -- Создаём визуальную копию СРАЗУ при обнаружении (до телепортации)
    -- Копия показывает где турель и светится красным
    if sentryPos and not data.visualCopy and not data.teleported then
        local originalCFrame = nil
        pcall(function()
            if sentry:IsA("BasePart") then
                originalCFrame = sentry.CFrame
            elseif sentry:IsA("Model") then
                originalCFrame = sentry:GetPivot()
            end
        end)
        
        data.originalPosition = sentryPos
        data.visualCopy = CreateSentryVisualCopy(sentry, sentryPos, originalCFrame)
        EnemySentryVisualCopies[sentry] = data.visualCopy
    end
    
    -- Обновляем позицию визуальной копии (пока турель не телепортирована, следуем за ней)
    if data.visualCopy and not data.teleported and sentryPos then
        pcall(function()
            if data.visualCopy.copyPart then
                data.visualCopy.copyPart.Position = sentryPos
            end
            -- Сфера обновляется через SentryRadiusSpheres, не через visualCopy
        end)
    end
end

-- Обработка одной вражеской турели (БОЕВАЯ ЛОГИКА - телепортация и микро-движение)
local function ProcessEnemySentry(sentry)
    if not TrackedEnemySentries[sentry] then
        return
    end
    
    local data = TrackedEnemySentries[sentry]
    local currentTime = tick()
    
    if not sentry or not sentry.Parent then
        -- Турель уничтожена - показываем эффекты ЕСЛИ была телепортирована
        if data and data.teleported and not data.destroyed then
            data.destroyed = true
            
            -- Показываем виньетку
            ShowSentryDestructionVignette()
            
            -- Показываем красный крест на месте оригинальной позиции
            if data.originalPosition then
                ShowDestructionCross(data.originalPosition)
            end
        end
        
        -- ВСЕГДА удаляем визуальную копию при уничтожении (даже если не была телепортирована)
        if data and data.visualCopy then
            RemoveSentryVisualCopy(data.visualCopy)
            data.visualCopy = nil
        end
        if EnemySentryVisualCopies[sentry] then
            RemoveSentryVisualCopy(EnemySentryVisualCopies[sentry])
            EnemySentryVisualCopies[sentry] = nil
        end
        
        -- Удаляем сферу при уничтожении турели
        RemoveSentrySphere(sentry)
        
        TrackedEnemySentries[sentry] = nil
        return
    end
    
    -- Получаем позицию турели
    local sentryPos = GetEnemySentryPosition(sentry)
    
    -- Сферы создаются/обновляются в ProcessEnemySentryVisuals
    
    -- Проверяем радиус обнаружения для телепортации
    local character = LocalPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    local withinDetectionRadius = true
    
    if rootPart and sentryPos then
        local distance = (rootPart.Position - sentryPos).Magnitude
        withinDetectionRadius = distance <= ENEMY_SENTRY_DETECTION_RADIUS
    end
    
    if not data.teleported and withinDetectionRadius and (currentTime - data.spawnTime) >= ENEMY_SENTRY_TELEPORT_DELAY then
        -- Проверяем, готова ли турель к телепортации (1 сек до активации или уже активна)
        if not IsSentryReadyForTeleport(sentry) then
            return  -- Турель ещё не готова к телепортации
        end
        
        -- Сохраняем originalPosition ДО телепортации для сферы
        local originalPosForSphere = data.originalPosition or sentryPos
        
        local success = TeleportEnemySentry(sentry, data)
        if success then
            data.teleported = true
            data.microMovePhase = 0
            
            -- ВАЖНО: Обновляем позицию сферы на originalPosition (место спавна турели)
            -- Сфера должна остаться там где турель была изначально!
            if originalPosForSphere then
                CreateOrUpdateSentrySphere(sentry, originalPosForSphere)
            end
        end
    end
    
    -- Микро-движение для разрушения турели (атака идёт через основной KillauraLoop)
    if data.teleported then
        MicroMoveEnemySentry(sentry, data)
    end
end

-- Получить телепортированную вражескую турель (для основного цикла killaura)
local function GetTeleportedEnemySentry()
    for sentry, data in pairs(TrackedEnemySentries) do
        if sentry and sentry.Parent and data.teleported then
            return sentry
        end
    end
    return nil
end

-- Атака телепортированной турели (без проверки Humanoid)
local function AttackTeleportedSentry(sentry)
    local currentTime = tick()
    -- Применяем джиттер для рандомизации задержки
    local jitter = TIMING.JITTER_MIN + math.random() * (TIMING.JITTER_MAX - TIMING.JITTER_MIN)
    local attackDelay = Config.AttackDelay * jitter
    if currentTime - LastAttackTime < attackDelay then
        return
    end
    
    if not sentry or not sentry.Parent then
        return
    end
    
    local character = LocalPlayer.Character
    if not character then
        return
    end
    
    local currentTool = character:FindFirstChildOfClass("Tool")
    if not currentTool then
        return
    end
    
    -- ИЗМЕНЕНО: При атаке турели используем ТОЛЬКО slap-перчатки
    -- Ban Hammer НЕ используется для уничтожения турелей
    if IsBanHammer(currentTool) then
        -- Если экипирован Ban Hammer - немедленно переключаемся на slap-перчатку
        SwitchToNextGlove()
        return
    end
    
    EquippedTool = currentTool
    
    -- Проверяем что это перчатка из ротации (slap + Gummy Bear, но без Ban Hammer)
    -- Gummy Bear работает как slap-перчатка с Cooldown 0.7s (из Items.lua)
    local isGummy = IsGummyBear(currentTool)
    local isRotationGlove = (IsGlove(currentTool) or isGummy) and not IsBanHammer(currentTool)
    local _, gloves = ScanInventory()
    
    -- Используем ротацию для всех перчаток из цикла (slap + Gummy Bear)
    if isRotationGlove and #gloves >= 4 then
        local activatedConnection = nil
        local switchScheduled = false
        
        activatedConnection = currentTool.Activated:Connect(function()
            LastToolActivation = tick()
            switchScheduled = true
            if activatedConnection then
                activatedConnection:Disconnect()
                activatedConnection = nil
            end
            -- Задержка зависит от типа перчатки (Gummy Bear = 0.7s cooldown)
            local postDelay = isGummy and TIMING.POST_ATTACK_GUMMY_BEAR or TIMING.POST_ATTACK_DEFAULT
            -- Применяем джиттер для рандомизации
            local jitterMult = TIMING.JITTER_MIN + math.random() * (TIMING.JITTER_MAX - TIMING.JITTER_MIN)
            postDelay = postDelay * jitterMult
            task.wait(postDelay)
            SwitchToNextGlove()
        end)
        
        -- Таймаут для перчаток
        task.spawn(function()
            task.wait(0.5)
            if not switchScheduled then
                if activatedConnection then
                    activatedConnection:Disconnect()
                    activatedConnection = nil
                end
                SwitchToNextGlove()
            end
        end)
    end
    
    -- Активируем перчатки из ротации (slap + Gummy Bear)
    if currentTool and currentTool.Parent == character and not IsBanHammer(currentTool) then
        pcall(function()
            currentTool:Activate()
        end)
    end
    
    LastAttackTime = currentTime
end

-- Обработчик добавления турели
local function OnEnemySentryAdded(child)
    if not IsEnemySentryObject(child) then
        return
    end
    
    task.wait(0.2)
    
    if not IsEnemySentryCheck(child) then
        return
    end
    
    TrackedEnemySentries[child] = {
        spawnTime = tick(),
        teleported = false,
        microMovePhase = 0,
        originalPosition = nil,
        visualCopy = nil,
        destroyed = false
    }
    
    -- Сразу создаём сферу радиуса для турели
    local sentryPos = GetEnemySentryPosition(child)
    if sentryPos then
        CreateOrUpdateSentrySphere(child, sentryPos)
    end
    
    child.Destroying:Once(function()
        local data = TrackedEnemySentries[child]
        if data then
            -- Показываем эффекты уничтожения если турель была телепортирована
            if data.teleported and not data.destroyed then
                data.destroyed = true
                
                -- Показываем виньетку
                ShowSentryDestructionVignette()
                
                -- Показываем красный крест на месте оригинальной позиции
                if data.originalPosition then
                    ShowDestructionCross(data.originalPosition)
                end
                
                -- Удаляем визуальную копию
                if data.visualCopy then
                    RemoveSentryVisualCopy(data.visualCopy)
                    data.visualCopy = nil
                end
            end
        end
        
        -- Очищаем из словарей
        if EnemySentryVisualCopies[child] then
            RemoveSentryVisualCopy(EnemySentryVisualCopies[child])
            EnemySentryVisualCopies[child] = nil
        end
        
        -- Удаляем сферу радиуса
        RemoveSentrySphere(child)
        
        TrackedEnemySentries[child] = nil
    end)
end

-- Обработчик удаления турели
local function OnEnemySentryRemoved(child)
    local data = TrackedEnemySentries[child]
    if data then
        -- Очистка визуальных элементов
        if data.visualCopy then
            RemoveSentryVisualCopy(data.visualCopy)
            data.visualCopy = nil
        end
        TrackedEnemySentries[child] = nil
    end
    
    -- Очистка из кэша копий
    if EnemySentryVisualCopies[child] then
        RemoveSentryVisualCopy(EnemySentryVisualCopies[child])
        EnemySentryVisualCopies[child] = nil
    end
    
    -- Удаляем сферу радиуса
    RemoveSentrySphere(child)
end

-- Сканирование существующих вражеских турелей (полное сканирование всего Workspace)
local function ScanExistingEnemySentries()
    -- Сканируем ВСЕ объекты в Workspace включая вложенные (GetDescendants)
    -- Это находит турели которые были до захода на сервер
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if IsEnemySentryObject(descendant) and IsEnemySentryCheck(descendant) then
            if not TrackedEnemySentries[descendant] then
                TrackedEnemySentries[descendant] = {
                    spawnTime = tick() - ENEMY_SENTRY_TELEPORT_DELAY - 1,  -- Сразу готова к телепорту
                    teleported = false,
                    microMovePhase = 0,
                    originalPosition = nil,
                    visualCopy = nil,
                    destroyed = false
                }
                
                -- Сразу создаём сферу радиуса для турели
                local sentryPos = GetEnemySentryPosition(descendant)
                if sentryPos then
                    CreateOrUpdateSentrySphere(descendant, sentryPos)
                end
                
                -- Подключаем событие удаления
                pcall(function()
                    descendant.Destroying:Once(function()
                        local data = TrackedEnemySentries[descendant]
                        if data then
                            if data.teleported and not data.destroyed then
                                data.destroyed = true
                                ShowSentryDestructionVignette()
                                if data.originalPosition then
                                    ShowDestructionCross(data.originalPosition)
                                end
                                if data.visualCopy then
                                    RemoveSentryVisualCopy(data.visualCopy)
                                    data.visualCopy = nil
                                end
                            end
                        end
                        if EnemySentryVisualCopies[descendant] then
                            RemoveSentryVisualCopy(EnemySentryVisualCopies[descendant])
                            EnemySentryVisualCopies[descendant] = nil
                        end
                        -- Удаляем сферу радиуса
                        RemoveSentrySphere(descendant)
                        TrackedEnemySentries[descendant] = nil
                    end)
                end)
            end
        end
    end
end

local function UpdateEnemyMarkers()
    -- СТРОГИЙ THROTTLE: не обновляем маркеры слишком часто
    local currentTime = tick()
    if currentTime - LastMarkerUpdate < MARKER_UPDATE_INTERVAL then
        return
    end
    LastMarkerUpdate = currentTime
    
    -- ПРИНУДИТЕЛЬНАЯ ОЧИСТКА: удаляем ВСЕ маркеры раз в 20 секунд для предотвращения утечек
    if currentTime - LastForcedMarkerCleanup >= FORCED_MARKER_CLEANUP_INTERVAL then
        for playerName, marker in pairs(EnemyMarkers) do
            SafeDestroy(marker)
        end
        EnemyMarkers = {}
        LastForcedMarkerCleanup = currentTime
        OptimizationLimits.TotalInstancesCreated = math.max(0, OptimizationLimits.TotalInstancesCreated - 50)  -- Сбрасываем счетчик
    end
    
    if not Config.ShowESP then
        -- Remove all markers if ESP is disabled
        for playerName, marker in pairs(EnemyMarkers) do
            if marker then
                pcall(function() marker:Destroy() end)
            end
        end
        EnemyMarkers = {}
        return
    end
    
    -- Create/update markers for currently detected enemies
    local activeMarkers = {}
    local markerCount = 0
    
    for _, enemyData in ipairs(AllDetectedEnemies) do
        -- ЗАЩИТА: не создаем больше MAX_ENEMY_MARKERS маркеров
        if markerCount >= OptimizationLimits.MAX_ENEMY_MARKERS then
            break
        end
        markerCount = markerCount + 1
        local player = enemyData.player
        local playerName = player.Name
        local isTarget = (CurrentTarget == player)
        
        activeMarkers[playerName] = true
        
        local character = player.Character
        if character then
            local head = character:FindFirstChild("Head")
            if head then
                -- Reuse existing marker or create new one
                local marker = EnemyMarkers[playerName]
                
                if not marker or not marker.Parent or marker.Parent ~= Workspace then
                    -- ЗАЩИТА: не создаем если слишком много объектов
                    if OptimizationLimits.TotalInstancesCreated >= OptimizationLimits.MAX_INSTANCES_BEFORE_CLEANUP then
                        break
                    end
                    
                    -- Create new marker (3D part above head) только если нужно
                    marker = Instance.new("Part")
                    marker.Name = "EnemyMarker_" .. playerName
                    marker.Size = Vector3.new(0.6, 0.6, 0.6)
                    marker.Shape = Enum.PartType.Ball
                    marker.Anchored = true
                    marker.CanCollide = false
                    marker.Material = Enum.Material.Neon
                    marker.TopSurface = Enum.SurfaceType.Smooth
                    marker.BottomSurface = Enum.SurfaceType.Smooth
                    marker.CastShadow = false
                    marker.Parent = Workspace
                    
                    EnemyMarkers[playerName] = marker
                    OptimizationLimits.TotalInstancesCreated = OptimizationLimits.TotalInstancesCreated + 1
                end
                
                -- Update position (above head)
                marker.Position = head.Position + Vector3.new(0, 2, 0)
                
                -- Color based on whether it's the current target
                if isTarget then
                    marker.Color = Color3.fromRGB(255, 255, 0)  -- Желтый для цели
                    marker.Transparency = 0.1
                    marker.Size = Vector3.new(0.8, 0.8, 0.8)
                else
                    marker.Color = Color3.fromRGB(255, 100, 100)  -- Красный для остальных
                    marker.Transparency = 0.3
                    marker.Size = Vector3.new(0.5, 0.5, 0.5)
                end
            end
        end
    end
    
    -- Remove markers for enemies no longer detected
    local toRemove = {}  -- Собираем ключи для удаления (безопасный способ)
    for playerName, marker in pairs(EnemyMarkers) do
        if not activeMarkers[playerName] then
            table.insert(toRemove, playerName)
            SafeDestroy(marker)
            OptimizationLimits.TotalInstancesCreated = math.max(0, OptimizationLimits.TotalInstancesCreated - 1)
        end
    end
    
    -- Удаляем из таблицы
    for _, playerName in ipairs(toRemove) do
        EnemyMarkers[playerName] = nil
    end
    
    -- Принудительная очистка nil значений и "мертвых" объектов
    local cleanedMarkers = {}
    local validCount = 0
    for name, marker in pairs(EnemyMarkers) do
        if marker and validCount < OptimizationLimits.MAX_ENEMY_MARKERS then
            local isValid = pcall(function()
                return marker.Parent ~= nil
            end)
            if isValid and marker.Parent then
                cleanedMarkers[name] = marker
                validCount = validCount + 1
            else
                SafeDestroy(marker)
                OptimizationLimits.TotalInstancesCreated = math.max(0, OptimizationLimits.TotalInstancesCreated - 1)
            end
        elseif marker then
            -- Лишние маркеры удаляем
            SafeDestroy(marker)
            OptimizationLimits.TotalInstancesCreated = math.max(0, OptimizationLimits.TotalInstancesCreated - 1)
        end
    end
    EnemyMarkers = cleanedMarkers
end

-- ═══════════════════════════════════════════════════════════════════════
-- BODY SWAP PROTECTION FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════

-- Найти Body Swap Potion в инвентаре
local function FindBodySwapPotion()
    local backpack = LocalPlayer:WaitForChild("Backpack", 2)
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                local name = item.Name:lower()
                if name:find("body") and name:find("swap") then
                    return item
                end
            end
        end
    end
    
    -- Проверяем экипированный инструмент
    local character = LocalPlayer.Character
    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") then
                local name = item.Name:lower()
                if name:find("body") and name:find("swap") then
                    return item
                end
            end
        end
    end
    
    return nil
end

-- Найти ближайшего врага для свапа обратно
local function FindNearestEnemyForSwap()
    local character = LocalPlayer.Character
    if not character then return nil end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end
    
    local closestEnemy = nil
    local closestDist = 50  -- Body Swap работает в радиусе 50 studs
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsEnemy(player) then
            local enemyChar = player.Character
            if enemyChar then
                local enemyRoot = enemyChar:FindFirstChild("HumanoidRootPart")
                local enemyHumanoid = enemyChar:FindFirstChildOfClass("Humanoid")
                if enemyRoot and enemyHumanoid and enemyHumanoid.Health > 0 then
                    local dist = (rootPart.Position - enemyRoot.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closestEnemy = player
                    end
                end
            end
        end
    end
    
    return closestEnemy
end

-- ═══════════════════════════════════════════════════════════════════════
-- BODY SWAP INPUT BLOCKING SYSTEM
-- ═══════════════════════════════════════════════════════════════════════

-- Функция для полной блокировки ввода игрока
local function BlockPlayerInput()
    if BodySwapInputBlocked then return end
    BodySwapInputBlocked = true
    
    Log("SWAP", "🔒 Блокируем ввод игрока")
    
    -- Блокируем ВСЕ клавиши движения через ContextActionService
    local function sinkInput(actionName, inputState, inputObject)
        return Enum.ContextActionResult.Sink  -- "Поглощаем" ввод
    end
    
    -- Блокируем WASD, стрелки, пробел, и другие клавиши управления
    ContextActionService:BindAction("BodySwap_BlockW", sinkInput, false, Enum.KeyCode.W)
    ContextActionService:BindAction("BodySwap_BlockA", sinkInput, false, Enum.KeyCode.A)
    ContextActionService:BindAction("BodySwap_BlockS", sinkInput, false, Enum.KeyCode.S)
    ContextActionService:BindAction("BodySwap_BlockD", sinkInput, false, Enum.KeyCode.D)
    ContextActionService:BindAction("BodySwap_BlockUp", sinkInput, false, Enum.KeyCode.Up)
    ContextActionService:BindAction("BodySwap_BlockDown", sinkInput, false, Enum.KeyCode.Down)
    ContextActionService:BindAction("BodySwap_BlockLeft", sinkInput, false, Enum.KeyCode.Left)
    ContextActionService:BindAction("BodySwap_BlockRight", sinkInput, false, Enum.KeyCode.Right)
    ContextActionService:BindAction("BodySwap_BlockSpace", sinkInput, false, Enum.KeyCode.Space)
    ContextActionService:BindAction("BodySwap_BlockShift", sinkInput, false, Enum.KeyCode.LeftShift)
    
    -- Высокий приоритет чтобы перехватить ввод до игры
    ContextActionService:SetPosition("BodySwap_BlockW", UDim2.new(0, -1000, 0, -1000))
    ContextActionService:SetPosition("BodySwap_BlockA", UDim2.new(0, -1000, 0, -1000))
    ContextActionService:SetPosition("BodySwap_BlockS", UDim2.new(0, -1000, 0, -1000))
    ContextActionService:SetPosition("BodySwap_BlockD", UDim2.new(0, -1000, 0, -1000))
end

-- Функция для разблокировки ввода игрока
local function UnblockPlayerInput()
    if not BodySwapInputBlocked then return end
    BodySwapInputBlocked = false
    
    Log("SWAP", "🔓 Разблокируем ввод игрока")
    
    -- Убираем все блокировки
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockW") end)
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockA") end)
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockS") end)
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockD") end)
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockUp") end)
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockDown") end)
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockLeft") end)
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockRight") end)
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockSpace") end)
    pcall(function() ContextActionService:UnbindAction("BodySwap_BlockShift") end)
end

-- Проверка и использование Body Swap Potion для свапа обратно (С ПОЛНОЙ БЛОКИРОВКОЙ ВВОДА)
local function UseBodySwapToSwapBack(targetPlayer)
    local bodySwapPotion = FindBodySwapPotion()
    if not bodySwapPotion then
        return false
    end
    
    -- Проверяем кулдаун предмета
    local cooldown = bodySwapPotion:GetAttribute("CooldownTime")
    if cooldown and cooldown > 0 then
        return false
    end
    
    local character = LocalPlayer.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- КРИТИЧНО: ОСТАНАВЛИВАЕМ ВСЕ ФУНКЦИИ KILLAURA ПЕРЕД СВАПОМ
    -- ═══════════════════════════════════════════════════════════════════════
    
    Log("SWAP", "🛑 ОСТАНАВЛИВАЕМ ВСЕ ФУНКЦИИ KILLAURA!")
    
    -- Устанавливаем ВСЕ блокирующие флаги
    BodySwapState.IsProtectionActive = true
    AoEState.IsUsingAoEItem = true
    AoEState.AsyncItemLock = true  -- Блокируем async предметы
    KillauraState.BanHammerBusy = true  -- Блокируем Ban Hammer
    AoEState.IsUsingLaserGun = true  -- Блокируем Laser Gun
    AoEState.IsUsingRageTable = true  -- Блокируем Rage Table
    AoEState.IsUsingHeatseeker = true  -- Блокируем Heatseeker
    AoEState.IsUsingAttackDoge = true  -- Блокируем Attack Doge
    
    -- МОМЕНТАЛЬНО блокируем ввод игрока
    BlockPlayerInput()
    
    -- Ждём чтобы текущие операции успели остановиться
    Log("SWAP", "⏳ Ждём остановки всех операций...")
    task.wait(0.15)  -- Даём время на остановку текущих циклов
    
    -- Снимаем текущий инструмент СРАЗУ (прерываем любые действия с ним)
    pcall(function()
        humanoid:UnequipTools()
    end)
    task.wait(0.05)
    
    -- ПЕРЕПРОВЕРЯЕМ ВСЁ после ожидания (character мог измениться после свапа!)
    character = LocalPlayer.Character
    if not character then
        Log("SWAP", "❌ Character не найден после ожидания")
        UnblockPlayerInput()
        BodySwapState.IsProtectionActive = false
        AoEState.IsUsingAoEItem = false
        AoEState.AsyncItemLock = false
        KillauraState.BanHammerBusy = false
        AoEState.IsUsingLaserGun = false
        AoEState.IsUsingRageTable = false
        AoEState.IsUsingHeatseeker = false
        AoEState.IsUsingAttackDoge = false
        BodySwapState.PendingSwapBack = false
        BodySwapState.SwapperPlayer = nil
        return false
    end
    
    humanoid = character:FindFirstChildOfClass("Humanoid")
    rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then
        Log("SWAP", "❌ Humanoid или RootPart не найден после ожидания")
        UnblockPlayerInput()
        BodySwapState.IsProtectionActive = false
        AoEState.IsUsingAoEItem = false
        AoEState.AsyncItemLock = false
        KillauraState.BanHammerBusy = false
        AoEState.IsUsingLaserGun = false
        AoEState.IsUsingRageTable = false
        AoEState.IsUsingHeatseeker = false
        AoEState.IsUsingAttackDoge = false
        BodySwapState.PendingSwapBack = false
        BodySwapState.SwapperPlayer = nil
        return false
    end
    
    -- Перепроверяем Body Swap Potion
    bodySwapPotion = FindBodySwapPotion()
    if not bodySwapPotion then
        Log("SWAP", "❌ Body Swap Potion не найден после ожидания")
        UnblockPlayerInput()
        BodySwapState.IsProtectionActive = false
        AoEState.IsUsingAoEItem = false
        AoEState.AsyncItemLock = false
        KillauraState.BanHammerBusy = false
        AoEState.IsUsingLaserGun = false
        AoEState.IsUsingRageTable = false
        AoEState.IsUsingHeatseeker = false
        AoEState.IsUsingAttackDoge = false
        BodySwapState.PendingSwapBack = false
        BodySwapState.SwapperPlayer = nil
        return false
    end
    
    Log("SWAP", "✅ Все функции остановлены, начинаем свап")
    
    -- Сохраняем оригинальные значения
    local originalJumpPower = humanoid.JumpPower
    local originalJumpHeight = humanoid.JumpHeight
    
    -- Блокируем прыжки
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0
    
    StatusText = "BODY SWAP: 🔒 Блокировка, бежим к цели!"
    Log("SWAP", "🏃 Начинаем бежать к цели: " .. (targetPlayer and targetPlayer.Name or "unknown"))
    
    task.spawn(function()
        local swapSuccess = false
        
        pcall(function()
            -- СРАЗУ начинаем движение к цели
            local targetChar = targetPlayer and targetPlayer.Character
            if targetChar then
                local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
                if targetRoot and rootPart then
                    local targetPosition = targetRoot.Position
                    local groundTarget = Vector3.new(targetPosition.X, rootPart.Position.Y, targetPosition.Z)
                    humanoid:MoveTo(groundTarget)
                    Log("SWAP", "🎯 Направляемся к цели")
                end
            end
            
            -- Экипируем Body Swap Potion
            if bodySwapPotion and bodySwapPotion.Parent == LocalPlayer.Backpack then
                humanoid:EquipTool(bodySwapPotion)
                task.wait(0.05)
            elseif bodySwapPotion and bodySwapPotion.Parent == character then
                -- Уже экипирован
                Log("SWAP", "Body Swap Potion уже экипирован")
            end
            
            -- Проверяем что экипировано (перепроверяем character)
            local currentChar = LocalPlayer.Character
            if not bodySwapPotion or (bodySwapPotion.Parent ~= currentChar and bodySwapPotion.Parent ~= LocalPlayer.Backpack) then
                Log("SWAP", "❌ Не удалось экипировать Body Swap Potion")
                return
            end
            
            -- Если ещё в рюкзаке - пробуем ещё раз
            if bodySwapPotion.Parent == LocalPlayer.Backpack then
                local currentHumanoid = currentChar and currentChar:FindFirstChildOfClass("Humanoid")
                if currentHumanoid then
                    currentHumanoid:EquipTool(bodySwapPotion)
                    task.wait(0.05)
                end
            end
            
            -- ═══════════════════════════════════════════════════════════════════════
            -- Цикл движения к цели (0.5 секунды)
            -- ═══════════════════════════════════════════════════════════════════════
            local walkDuration = 0.5
            local walkStartTime = tick()
            
            while tick() - walkStartTime < walkDuration do
                local currentChar = LocalPlayer.Character
                if not currentChar then break end
                
                local currentHumanoid = currentChar:FindFirstChildOfClass("Humanoid")
                local currentRoot = currentChar:FindFirstChild("HumanoidRootPart")
                if not currentHumanoid or not currentRoot then break end
                
                local tgtChar = targetPlayer and targetPlayer.Character
                if tgtChar then
                    local tgtRoot = tgtChar:FindFirstChild("HumanoidRootPart")
                    if tgtRoot then
                        local targetPosition = tgtRoot.Position
                        local myPosition = currentRoot.Position
                        local distance = (targetPosition - myPosition).Magnitude
                        
                        -- Если близко достаточно (< 12 studs) - можно юзать свап
                        if distance < 12 then
                            Log("SWAP", "✅ Достигли цели! Дистанция: " .. string.format("%.1f", distance))
                            break
                        end
                        
                        -- Продолжаем двигаться к цели
                        local groundTarget = Vector3.new(targetPosition.X, myPosition.Y, targetPosition.Z)
                        currentHumanoid:MoveTo(groundTarget)
                        
                        StatusText = "BODY SWAP: 🏃 " .. string.format("%.1f", distance) .. "m до цели"
                    end
                end
                
                task.wait(0.03)  -- ~33 обновлений в секунду для плавности
            end
            
            -- Останавливаем движение
            pcall(function()
                local currentChar = LocalPlayer.Character
                if currentChar then
                    local currentHumanoid = currentChar:FindFirstChildOfClass("Humanoid")
                    local currentRoot = currentChar:FindFirstChild("HumanoidRootPart")
                    if currentHumanoid and currentRoot then
                        currentHumanoid:MoveTo(currentRoot.Position)
                    end
                end
            end)
            
            Log("SWAP", "⚡ Активируем Body Swap Potion!")
            StatusText = "BODY SWAP: ⚡ Свап обратно!"
            
            -- Активируем Body Swap Potion через UseItem RemoteEvent
            local RepStorage = game:GetService("ReplicatedStorage")
            local packagesFolder = RepStorage:FindFirstChild("Packages")
            if packagesFolder then
                local netModule = packagesFolder:FindFirstChild("Net")
                if netModule and netModule:IsA("ModuleScript") then
                    local success, net = pcall(require, netModule)
                    if success and net and type(net.RemoteEvent) == "function" then
                        local useItemRemote = net:RemoteEvent("UseItem")
                        if useItemRemote then
                            useItemRemote:FireServer(targetPlayer)
                            swapSuccess = true
                        end
                    end
                end
            end
            
            -- Также пробуем Activate
            pcall(function()
                bodySwapPotion:Activate()
            end)
            
            task.wait(0.1)  -- Короткая задержка для активации
            
            -- Снимаем Body Swap и возвращаем предыдущий инструмент
            pcall(function()
                local currentChar = LocalPlayer.Character
                if currentChar then
                    local currentHumanoid = currentChar:FindFirstChildOfClass("Humanoid")
                    if currentHumanoid then
                        currentHumanoid:UnequipTools()
                        task.wait(0.05)
                        
                        local bestTool = FindBestTool()
                        if bestTool and bestTool.Parent == LocalPlayer.Backpack then
                            currentHumanoid:EquipTool(bestTool)
                        end
                    end
                end
            end)
        end)
        
        -- ВОССТАНАВЛИВАЕМ ВСЁ
        pcall(function()
            local currentChar = LocalPlayer.Character
            if currentChar then
                local currentHumanoid = currentChar:FindFirstChildOfClass("Humanoid")
                if currentHumanoid then
                    currentHumanoid.JumpPower = originalJumpPower
                    currentHumanoid.JumpHeight = originalJumpHeight
                end
            end
        end)
        
        -- Разблокируем ввод
        UnblockPlayerInput()
        
        -- Сбрасываем ВСЕ флаги блокировки
        BodySwapState.IsProtectionActive = false
        AoEState.IsUsingAoEItem = false
        AoEState.AsyncItemLock = false  -- Разблокируем async предметы
        KillauraState.BanHammerBusy = false  -- Разблокируем Ban Hammer
        AoEState.IsUsingLaserGun = false  -- Разблокируем Laser Gun
        AoEState.IsUsingRageTable = false  -- Разблокируем Rage Table
        AoEState.IsUsingHeatseeker = false  -- Разблокируем Heatseeker
        AoEState.IsUsingAttackDoge = false  -- Разблокируем Attack Doge
        BodySwapState.PendingSwapBack = false  -- Сбрасываем флаг ожидания свапа
        BodySwapState.SwapperPlayer = nil  -- Сбрасываем ссылку на свапера
        BodySwapState.LastSwapTime = tick()
        
        Log("SWAP", "🔓 Все функции killaura разблокированы")
        
        if swapSuccess then
            Log("SWAP", "✅ Body Swap успешно выполнен!")
        end
    end)
    
    return true
end

-- ═══════════════════════════════════════════════════════════════════════
-- BODY SWAP SMOKE EFFECT DETECTION (Новая система детекции)
-- ═══════════════════════════════════════════════════════════════════════

-- Проверка, является ли эффект Body Swap Smoke
local function IsBodySwapSmokeEffect(particleEmitter)
    if not particleEmitter or not particleEmitter:IsA("ParticleEmitter") then
        return false
    end
    
    -- Проверяем имя
    if particleEmitter.Name ~= BODY_SWAP_SMOKE_NAME then
        return false
    end
    
    -- Проверяем текстуру
    local texture = particleEmitter.Texture
    if texture and (texture == BODY_SWAP_SMOKE_TEXTURE or texture:find("16867365247")) then
        return true
    end
    
    return false
end

-- Найти игрока который нас свапнул (ТОЛЬКО через Smoke эффект на его персонаже)
local function FindSwapper()
    local character = LocalPlayer.Character
    if not character then return nil end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end
    
    local closestSwapper = nil
    local closestDist = 60  -- Body Swap Potion имеет радиус действия
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsEnemy(player) then
            local enemyChar = player.Character
            if enemyChar then
                local enemyRoot = enemyChar:FindFirstChild("HumanoidRootPart")
                local enemyHumanoid = enemyChar:FindFirstChildOfClass("Humanoid")
                if enemyRoot and enemyHumanoid and enemyHumanoid.Health > 0 then
                    local dist = (rootPart.Position - enemyRoot.Position).Magnitude
                    
                    -- ТОЛЬКО проверяем наличие Smoke эффекта на враге (он тоже получает эффект при свапе)
                    local hasSmokeEffect = false
                    
                    for _, part in ipairs(enemyChar:GetChildren()) do
                        if part:IsA("BasePart") then
                            for _, child in ipairs(part:GetChildren()) do
                                if IsBodySwapSmokeEffect(child) then
                                    hasSmokeEffect = true
                                    break
                                end
                            end
                        end
                        if hasSmokeEffect then break end
                    end
                    
                    -- ТОЛЬКО враги со Smoke эффектом
                    if hasSmokeEffect and dist < closestDist then
                        closestDist = dist
                        closestSwapper = player
                    end
                end
            end
        end
    end
    
    return closestSwapper
end

-- Обработчик обнаружения Body Swap Smoke эффекта на нашем персонаже
local function OnBodySwapSmokeDetected(particleEmitter, bodyPart)
    local currentTime = tick()
    
    -- Проверяем кулдаун
    if currentTime - BodySwapState.LastSwapTime < BodySwapState.SWAP_COOLDOWN then
        Log("SWAP", "Обнаружен Smoke эффект, но кулдаун активен")
        return
    end
    
    -- Проверяем не обрабатываем ли уже свап
    if BodySwapState.IsProtectionActive or BodySwapState.PendingSwapBack then
        Log("SWAP", "Обнаружен Smoke эффект, но уже обрабатываем свап")
        return
    end
    
    Log("SWAP", "🔥 BODY SWAP DETECTED! Smoke эффект на: " .. tostring(bodyPart.Name))
    
    -- Сохраняем время детекции
    LastBodySwapDetectionTime = currentTime
    BodySwapState.PendingSwapBack = true
    
    -- Ищем кто нас свапнул
    local swapper = FindSwapper()
    
    if swapper then
        BodySwapState.SwapperPlayer = swapper
        Log("SWAP", "🎯 Нашли свапера: " .. swapper.Name)
        KillauraState.StatusText = "BODY SWAP: Обнаружен свап от " .. swapper.Name .. "!"
        
        -- МОМЕНТАЛЬНО запускаем ответный свап (БЕЗ ЗАДЕРЖКИ!)
        Log("SWAP", "⚡ МОМЕНТАЛЬНО запускаем ответный свап на: " .. BodySwapState.SwapperPlayer.Name)
        local success = UseBodySwapToSwapBack(BodySwapState.SwapperPlayer)
        
        if success then
            Log("SWAP", "✅ Ответный свап успешно инициирован!")
        else
            Log("SWAP", "❌ Не удалось выполнить ответный свап")
            BodySwapState.PendingSwapBack = false
            BodySwapState.SwapperPlayer = nil
        end
    else
        Log("SWAP", "⚠️ Не удалось найти свапера со Smoke эффектом - отмена")
        -- НЕ используем fallback на ближайшего врага - только точное определение по Smoke
        BodySwapState.PendingSwapBack = false
    end
end

-- Мониторинг добавления эффектов на части тела персонажа
local function SetupBodyPartMonitoring(bodyPart)
    if not bodyPart:IsA("BasePart") then return end
    
    -- Проверяем существующие эффекты
    for _, child in ipairs(bodyPart:GetChildren()) do
        if IsBodySwapSmokeEffect(child) then
            OnBodySwapSmokeDetected(child, bodyPart)
        end
    end
    
    -- Подключаем мониторинг новых эффектов
    local connection = bodyPart.ChildAdded:Connect(function(child)
        task.wait(0.01)  -- Небольшая задержка чтобы свойства загрузились
        if IsBodySwapSmokeEffect(child) then
            OnBodySwapSmokeDetected(child, bodyPart)
        end
    end)
    
    table.insert(BodySwapState.EffectConnections, connection)
end

-- Настройка мониторинга Body Swap эффектов для персонажа
local function SetupBodySwapMonitoring(character)
    if not character then return end
    if not BODY_SWAP_PROTECTION_ENABLED then return end
    
    -- Очищаем старые подключения
    for _, conn in ipairs(BodySwapState.EffectConnections) do
        if conn and conn.Connected then
            conn:Disconnect()
        end
    end
    BodySwapState.EffectConnections = {}
    
    Log("SWAP", "Настраиваем мониторинг Body Swap эффектов...")
    
    -- Мониторим все части тела
    for _, bodyPart in ipairs(character:GetChildren()) do
        SetupBodyPartMonitoring(bodyPart)
    end
    
    -- Мониторим добавление новых частей тела
    local charConnection = character.ChildAdded:Connect(function(child)
        SetupBodyPartMonitoring(child)
    end)
    table.insert(BodySwapState.EffectConnections, charConnection)
    
    Log("SWAP", "✅ Мониторинг Body Swap эффектов настроен для " .. #BodySwapState.EffectConnections .. " подключений")
end

-- Проверка на Body Swap (старая версия через телепортацию - оставлена как backup)
local function CheckForBodySwap()
    local currentTime = tick()
    
    -- Не проверяем слишком часто
    if currentTime - BodySwapState.LastPositionUpdateTime < BodySwapState.POSITION_UPDATE_INTERVAL then
        return
    end
    
    -- Не реагируем если уже свапаемся или недавно свапнулись
    if BodySwapState.IsProtectionActive or currentTime - BodySwapState.LastSwapTime < BodySwapState.SWAP_COOLDOWN then
        return
    end
    
    local character = LocalPlayer.Character
    if not character then
        BodySwapState.LastKnownPosition = nil
        return
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        BodySwapState.LastKnownPosition = nil
        return
    end
    
    local currentPosition = rootPart.Position
    
    -- Если первая проверка - запоминаем позицию
    if not BodySwapState.LastKnownPosition then
        BodySwapState.LastKnownPosition = currentPosition
        BodySwapState.LastPositionUpdateTime = currentTime
        return
    end
    
    -- Проверяем расстояние телепортации
    local teleportDistance = (currentPosition - BodySwapState.LastKnownPosition).Magnitude
    
    -- Если телепортировались далеко - возможно нас свапнули
    if teleportDistance > BodySwapState.SWAP_DETECTION_THRESHOLD then
        -- Проверяем есть ли враг рядом (тот кто мог нас свапнуть)
        local nearestEnemy = FindNearestEnemyForSwap()
        
        if nearestEnemy then
            -- Пытаемся свапнуть обратно
            local swapped = UseBodySwapToSwapBack(nearestEnemy)
            if swapped then
                KillauraState.StatusText = "BODY SWAP: Защита активирована!"
            end
        end
    end
    
    -- Обновляем позицию
    BodySwapState.LastKnownPosition = currentPosition
    BodySwapState.LastPositionUpdateTime = currentTime
end

-- Find closest enemy within radius (detects ALL enemies but targets CLOSEST)
local function FindClosestEnemy()
    local character = LocalPlayer.Character
    if not character then
        AllDetectedEnemies = {}
        return nil
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        AllDetectedEnemies = {}
        return nil
    end
    
    local closestPlayer = nil
    local closestDistance = math.huge
    local closestPlayerForESP = nil  -- Ближайший среди ВСЕХ обнаруженных (для ESP луча)
    local closestDistanceForESP = math.huge
    local detectedEnemies = {}
    
    -- Сканируем всех игроков
    for _, player in ipairs(Players:GetPlayers()) do
        if IsEnemy(player) then
            local targetChar = player.Character
            if targetChar then
                local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
                local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
                
                if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
                    local distance = (rootPart.Position - targetRoot.Position).Magnitude
                    
                    -- Добавляем в список обнаруженных до 300м (для Laser Gun)
                    if distance <= DETECTION_RADIUS.LASER_GUN then
                        table.insert(detectedEnemies, {
                            player = player,
                            distance = distance,
                            position = targetRoot.Position
                        })
                        
                        -- Ищем ближайшего среди ВСЕХ обнаруженных (для ESP луча до 300м)
                        if distance < closestDistanceForESP then
                            closestDistanceForESP = distance
                            closestPlayerForESP = player
                        end
                        
                        -- Ищем ближайшего только в обычном радиусе (60м для боя)
                        if distance <= Config.DetectionRadius and distance < closestDistance then
                            closestDistance = distance
                            closestPlayer = player
                        end
                    end
                end
            end
        end
    end
    
    -- Обновляем глобальный список обнаруженных врагов (С ЛИМИТОМ)
    -- Ограничиваем размер таблицы для предотвращения утечек памяти
    if #detectedEnemies > OptimizationLimits.MAX_DETECTED_ENEMIES then
        -- Сортируем по расстоянию и оставляем только ближайших
        table.sort(detectedEnemies, function(a, b)
            return a.distance < b.distance
        end)
        local trimmed = {}
        for i = 1, OptimizationLimits.MAX_DETECTED_ENEMIES do
            trimmed[i] = detectedEnemies[i]
        end
        detectedEnemies = trimmed
    end
    AllDetectedEnemies = detectedEnemies
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- ПРИОРИТЕТ 1: Вор МОЕЙ базы - АБСОЛЮТНЫЙ приоритет!
    -- Независимо от расстояния! (любой brainrot с моего плота)
    -- ═══════════════════════════════════════════════════════════════════════
    if ThiefPriorityEnabled then
        local myBaseThief = FindMyBaseThief()
        LogThiefDebug("[FindClosestEnemy] MyBaseThief=" .. (myBaseThief and myBaseThief.player and myBaseThief.player.Name or "nil"))
        
        if myBaseThief and myBaseThief.player then
            local thiefCharacter = myBaseThief.character or myBaseThief.player.Character
            local thiefRoot = myBaseThief.hrp or (thiefCharacter and thiefCharacter:FindFirstChild("HumanoidRootPart"))
            local thiefHumanoid = thiefCharacter and thiefCharacter:FindFirstChildOfClass("Humanoid")
            
            if thiefRoot and thiefHumanoid and thiefHumanoid.Health > 0 then
                local thiefDistance = (rootPart.Position - thiefRoot.Position).Magnitude
                LogThiefDebug("[FindClosestEnemy] MyBaseThief distance: " .. tostring(math.floor(thiefDistance)) .. "m")
                
                -- Проверяем IsEnemy чтобы не атаковать друзей
                local isThiefEnemy = IsEnemy(myBaseThief.player)
                
                if isThiefEnemy then
                    -- Вор моей базы - АБСОЛЮТНЫЙ приоритет!
                    LogThiefDebug("[FindClosestEnemy] >>> RETURNING MY BASE THIEF AS TARGET: " .. myBaseThief.player.Name)
                    return myBaseThief.player
                end
            end
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- ПРИОРИТЕТ 2: Вор лучшего brainrot - приоритетная цель (если нет вора моей базы)
    -- Независимо от расстояния! (как в adminabuse.lua)
    -- ═══════════════════════════════════════════════════════════════════════
    if ThiefPriorityEnabled then
        local thief = FindBrainrotThief()
        LogThiefDebug("[FindClosestEnemy] ThiefPriorityEnabled=true, thief=" .. (thief and thief.player and thief.player.Name or "nil"))
        
        if thief and thief.player then
            -- ИСПРАВЛЕНО: Используем закэшированные hrp и character из объекта thief,
            -- или получаем актуальные если кэш устарел
            local thiefCharacter = thief.character or thief.player.Character
            local thiefRoot = thief.hrp or (thiefCharacter and thiefCharacter:FindFirstChild("HumanoidRootPart"))
            local thiefHumanoid = thiefCharacter and thiefCharacter:FindFirstChildOfClass("Humanoid")
            
            LogThiefDebug("[FindClosestEnemy] thiefCharacter=" .. tostring(thiefCharacter ~= nil) .. ", thiefRoot=" .. tostring(thiefRoot ~= nil) .. ", thiefHumanoid=" .. tostring(thiefHumanoid ~= nil))
            
            if thiefRoot and thiefHumanoid and thiefHumanoid.Health > 0 then
                local thiefDistance = (rootPart.Position - thiefRoot.Position).Magnitude
                LogThiefDebug("[FindClosestEnemy] Thief distance: " .. tostring(math.floor(thiefDistance)) .. "m, DetectionRadius: " .. tostring(Config.DetectionRadius))
                
                -- ВАЖНО: Проверяем IsEnemy чтобы не атаковать друзей
                local isThiefEnemy = IsEnemy(thief.player)
                LogThiefDebug("[FindClosestEnemy] IsEnemy(thief): " .. tostring(isThiefEnemy))
                
                if isThiefEnemy then
                    -- ИСПРАВЛЕНО: Вор ВСЕГДА приоритетная цель, независимо от расстояния!
                    -- Атака будет ограничена радиусом в боевом цикле, но цель - вор
                    LogThiefDebug("[FindClosestEnemy] >>> RETURNING THIEF AS TARGET: " .. thief.player.Name .. " (distance: " .. tostring(math.floor(thiefDistance)) .. "m)")
                    return thief.player
                else
                    LogThiefDebug("[FindClosestEnemy] Thief is NOT enemy (in FriendList?), skipping")
                end
            else
                LogThiefDebug("[FindClosestEnemy] Thief has no HRP/Humanoid or dead (char=" .. tostring(thiefCharacter ~= nil) .. ", hrp=" .. tostring(thiefRoot ~= nil) .. ", hum=" .. tostring(thiefHumanoid ~= nil) .. ")")
            end
        end
    end
    
    -- Если вора нет или он вне радиуса - возвращаем ближайшего врага в боевом радиусе
    -- ИСПРАВЛЕНО: Возвращаем closestPlayer (в радиусе 60м), а не closestPlayerForESP (300м)
    if closestPlayer then
        LogThiefDebug("[FindClosestEnemy] No thief priority, returning closestPlayer: " .. closestPlayer.Name)
        return closestPlayer
    end
    
    -- Fallback на ближайшего в расширенном радиусе (для ESP/Laser Gun)
    if closestPlayerForESP then
        LogThiefDebug("[FindClosestEnemy] No combat target, returning closestPlayerForESP: " .. closestPlayerForESP.Name)
        return closestPlayerForESP
    end
    
    LogThiefDebug("[FindClosestEnemy] No targets found")
    return nil
end

-- Create ESP beam to target
local LastESPBeamCreate = 0
local ESP_BEAM_CREATE_INTERVAL = 0.3  -- Интервал между созданиями бима

local function CreateESPBeam(target)
    -- СТРОГИЙ THROTTLE: не создаём бим слишком часто
    local currentTime = tick()
    if currentTime - LastESPBeamCreate < ESP_BEAM_CREATE_INTERVAL then
        return
    end
    LastESPBeamCreate = currentTime
    
    -- ЗАЩИТА: не создаём если слишком много объектов
    if OptimizationLimits.TotalInstancesCreated >= OptimizationLimits.MAX_INSTANCES_BEFORE_CLEANUP then
        return
    end
    
    if not Config.ShowESP then
        return
    end
    
    if not target then
        return
    end
    
    local character = LocalPlayer.Character
    if not character then
        return
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return
    end
    
    local targetChar = target.Character
    if not targetChar then
        return
    end
    
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return
    end
    
    -- Calculate distance to determine color
    local distance = (rootPart.Position - targetRoot.Position).Magnitude
    local beamColor
    
    if distance <= 15 then
        beamColor = Color3.fromRGB(255, 0, 0)  -- Red - close range (0-15m)
    elseif distance <= 30 then
        beamColor = Color3.fromRGB(255, 255, 0)  -- Yellow - medium range (15-30m)
    elseif distance <= 45 then
        beamColor = Color3.fromRGB(0, 255, 0)  -- Green - medium-far range (30-45m)
    elseif distance <= 60 then
        beamColor = Color3.fromRGB(128, 0, 255)  -- Purple - far range (45-60m)
    else
        beamColor = Color3.fromRGB(0, 191, 255)  -- Cyan/Blue - beyond combat range (>60m)
    end
    
    -- Create new attachments
    local att0 = Instance.new("Attachment")
    att0.Name = "KillauraBeamAttachment0"
    att0.Position = Vector3.new(0, 2, 0)
    att0.Parent = rootPart
    
    local att1 = Instance.new("Attachment")
    att1.Name = "KillauraBeamAttachment1"
    att1.Position = Vector3.new(0, 2, 0)
    att1.Parent = targetRoot
    
    -- Create beam with thin width and glow effect
    local beam = Instance.new("Beam")
    beam.Name = "KillauraESP"
    beam.Color = ColorSequence.new(beamColor)
    beam.Width0 = 0.2
    beam.Width1 = 0.2
    beam.FaceCamera = true
    beam.Transparency = NumberSequence.new(0.2)
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Attachment0 = att0
    beam.Attachment1 = att1
    beam.Parent = rootPart
    
    -- Store references
    ESPBeam = beam
    ESPAttachment0 = att0
    ESPAttachment1 = att1
    OptimizationLimits.TotalInstancesCreated = OptimizationLimits.TotalInstancesCreated + 3  -- Учитываем созданные объекты
end

-- Remove ESP beam (оптимизировано с SafeDestroy)
local function RemoveESPBeam()
    SafeDestroy(ESPBeam)
    SafeDestroy(ESPAttachment0)
    SafeDestroy(ESPAttachment1)
    
    ESPBeam = nil
    ESPAttachment0 = nil
    ESPAttachment1 = nil
    OptimizationLimits.TotalInstancesCreated = math.max(0, OptimizationLimits.TotalInstancesCreated - 3)  -- Учитываем удаление
    LastESPBeamCreate = 0  -- Сбрасываем таймер чтобы можно было сразу создать новый бим
end

-- Update ESP beam color based on distance (с throttle)
local LastESPColorUpdate = 0
local ESP_COLOR_UPDATE_INTERVAL = 0.1  -- Обновление цвета раз в 0.1 сек (чаще проверяем валидность)

local function UpdateESPBeamColor()
    local currentTime = tick()
    if currentTime - LastESPColorUpdate < ESP_COLOR_UPDATE_INTERVAL then
        return  -- Слишком рано для обновления
    end
    LastESPColorUpdate = currentTime
    
    -- Если нет цели - ничего не делаем
    if not CurrentTarget then
        return
    end
    
    -- Если бима нет но цель есть - пытаемся создать
    if not ESPBeam then
        CreateESPBeam(CurrentTarget)
        return
    end
    
    -- Проверяем валидность бима и аттачментов (могли быть удалены при респавне)
    local beamValid = ESPBeam and ESPBeam.Parent
    local att0Valid = ESPAttachment0 and ESPAttachment0.Parent
    local att1Valid = ESPAttachment1 and ESPAttachment1.Parent
    
    if not beamValid or not att0Valid or not att1Valid then
        -- Бим сломан - удаляем и пересоздаём
        RemoveESPBeam()
        CreateESPBeam(CurrentTarget)
        return
    end
    
    local character = LocalPlayer.Character
    if not character then
        return
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return
    end
    
    local targetChar = CurrentTarget.Character
    if not targetChar then
        return
    end
    
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return
    end
    
    local distance = (rootPart.Position - targetRoot.Position).Magnitude
    local beamColor
    
    if distance <= 15 then
        beamColor = Color3.fromRGB(255, 0, 0)  -- Red - close range (0-15m)
    elseif distance <= 30 then
        beamColor = Color3.fromRGB(255, 255, 0)  -- Yellow - medium range (15-30m)
    elseif distance <= 45 then
        beamColor = Color3.fromRGB(0, 255, 0)  -- Green - medium-far range (30-45m)
    elseif distance <= 60 then
        beamColor = Color3.fromRGB(128, 0, 255)  -- Purple - far range (45-60m)
    else
        beamColor = Color3.fromRGB(0, 191, 255)  -- Cyan/Blue - beyond combat range (>60m)
    end
    
    ESPBeam.Color = ColorSequence.new(beamColor)
end

-- Create 3D Part ring circles on ground to show detection radius (25, 35, 50 studs)
local RadiusCircles = {}
local CircleUpdateConnection = nil
local ColorAnimationTime = 0

-- ВАЖНО: RemoveRadiusCircles должна быть объявлена ДО CreateRadiusCircles
local function RemoveRadiusCircles()
    if CircleUpdateConnection then
        CircleUpdateConnection:Disconnect()
        CircleUpdateConnection = nil
    end
    
    local partsRemoved = 0
    for i = 1, #RadiusCircles do
        local ringData = RadiusCircles[i]
        if ringData then
            -- Удаляем части если есть (СНАЧАЛА части, потом модель)
            if ringData.parts then
                for _, part in ipairs(ringData.parts) do
                    if SafeDestroy(part) then
                        partsRemoved = partsRemoved + 1
                    end
                end
                ringData.parts = nil  -- Очищаем ссылку
            end
            -- Удаляем модель если есть
            if ringData.model then
                if SafeDestroy(ringData.model) then
                    partsRemoved = partsRemoved + 1
                end
                ringData.model = nil
            end
        end
    end
    
    -- Обновляем счетчик
    OptimizationLimits.TotalInstancesCreated = math.max(0, OptimizationLimits.TotalInstancesCreated - partsRemoved)
    
    RadiusCircles = {}
    ColorAnimationTime = 0
end

local function CreateRadiusCircles()
    if not Config.ShowRadius then
        RemoveRadiusCircles()
        return
    end
    
    if #RadiusCircles > 0 then
        return  -- Already created
    end
    
    local character = LocalPlayer.Character
    if not character then
        return
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return
    end
    
    -- Create FOUR rings with different radii
    local radii = {15, 30, 45, 60}
    local baseColors = {
        Color3.fromRGB(255, 0, 0),    -- Red for 15
        Color3.fromRGB(255, 255, 0),  -- Yellow for 30
        Color3.fromRGB(0, 255, 0),    -- Green for 45
        Color3.fromRGB(128, 0, 255)   -- Purple for 60
    }
    
    for ringIdx = 1, #radii do
        local radius = radii[ringIdx]
        local baseColor = baseColors[ringIdx]
        
        -- Create container model for this ring
        local ringModel = Instance.new("Model")
        ringModel.Name = "KillauraRing_" .. radius
        
        -- Number of segments to create smooth circle (ОПТИМИЗИРОВАНО)
        local segments = OptimizationLimits.MAX_RADIUS_SEGMENTS  -- Уменьшено с 48 до 36
        local segmentAngle = (2 * math.pi) / segments
        
        local ringParts = {}
        
        for i = 0, segments - 1 do
            local angle = i * segmentAngle
            
            -- Calculate position on circle
            local x = math.cos(angle) * radius
            local z = math.sin(angle) * radius
            
            -- Create small cube for this segment
            local segment = Instance.new("Part")
            segment.Name = "RingSegment_" .. i
            segment.Size = Vector3.new(0.4, 0.4, 0.4)
            segment.Anchored = true
            segment.CanCollide = false
            segment.Material = Enum.Material.Neon
            segment.Color = baseColor
            segment.Transparency = 0.5
            segment.TopSurface = Enum.SurfaceType.Smooth
            segment.BottomSurface = Enum.SurfaceType.Smooth
            segment.CastShadow = false
            
            -- Position on ground
            local groundPos = rootPart.Position - Vector3.new(0, 3, 0)
            segment.Position = groundPos + Vector3.new(x, 0, z)
            
            segment.Parent = ringModel
            table.insert(ringParts, segment)
            OptimizationLimits.TotalInstancesCreated = OptimizationLimits.TotalInstancesCreated + 1
        end
        
        ringModel.Parent = Workspace
        OptimizationLimits.TotalInstancesCreated = OptimizationLimits.TotalInstancesCreated + 1  -- +1 за модель
        
        table.insert(RadiusCircles, {
            model = ringModel,
            parts = ringParts,
            baseColor = baseColor,
            radius = radius,
            baseTransparency = 0.5
        })
    end
    
    -- Update circles every frame (с throttle для оптимизации)
    if CircleUpdateConnection then
        CircleUpdateConnection:Disconnect()
    end
    
    local lastCircleUpdate = 0
    local CIRCLE_UPDATE_INTERVAL = 0.4  -- Увеличено с 0.3 до 0.4 сек
    
    CircleUpdateConnection = RunService.RenderStepped:Connect(function(deltaTime)
        -- Throttle: обновляем только раз в CIRCLE_UPDATE_INTERVAL
        local currentTime = tick()
        if currentTime - lastCircleUpdate < CIRCLE_UPDATE_INTERVAL then
            return
        end
        lastCircleUpdate = currentTime
        
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not hrp then
            return
        end
        
        if not Config.Enabled or not Config.ShowRadius then
            -- Hide rings when disabled or ShowRadius is off
            for i = 1, #RadiusCircles do
                local ringData = RadiusCircles[i]
                if ringData and ringData.parts then
                    for _, part in ipairs(ringData.parts) do
                        if part then
                            part.Transparency = 1
                        end
                    end
                end
            end
            return
        end
        
        -- Update color animation (pulsing glow effect)
        ColorAnimationTime = ColorAnimationTime + (deltaTime or 0.016)
        local pulseValue = (math.sin(ColorAnimationTime * 4) + 1) / 2  -- 0 to 1, x2 faster pulse
        
        -- Update ring positions and colors
        local groundPos = hrp.Position - Vector3.new(0, 3, 0)
        
        for ringIdx = 1, #RadiusCircles do
            local ringData = RadiusCircles[ringIdx]
            if ringData and ringData.parts then
                local radius = ringData.radius
                local baseColor = ringData.baseColor
                local baseTransparency = ringData.baseTransparency or 0.5
                local parts = ringData.parts
                
                local segments = #parts
                local segmentAngle = (2 * math.pi) / segments
                
                for i = 1, segments do
                    local part = parts[i]
                    if part then
                        local angle = (i - 1) * segmentAngle
                        
                        -- Calculate position on circle
                        local x = math.cos(angle) * radius
                        local z = math.sin(angle) * radius
                        
                        -- Update position to follow player
                        part.Position = groundPos + Vector3.new(x, 0, z)
                        
                        -- Пульсирующий эффект
                        local white = Color3.fromRGB(255, 255, 255)
                        part.Color = baseColor:Lerp(white, pulseValue * 0.7)
                        part.Transparency = baseTransparency + (pulseValue * 0.3)
                    end
                end
            end
        end
    end)
end

-- Remove old rainbow sphere function (replaced by Drawing circles)
local RainbowConnection = nil
local HueValue = 0

local function CreateRainbowSphere()
    -- Deprecated - now using 3D radius circles
    CreateRadiusCircles()
end

local function RemoveRainbowSphere()
    -- Deprecated - now using 3D radius circles
    RemoveRadiusCircles()
end

-- Rotate character to face target using AutoRotate disable + manual orientation
-- This simulates Shift Lock behavior - character looks at target while you move freely
local RotationConnection = nil
local OriginalAutoRotate = nil
local LastCFrameUpdate = 0
local CFRAME_UPDATE_INTERVAL = 0.070

local function RotateToTarget(target)
    if not Config.AutoRotate then
        return
    end
    
    if not target then
        return
    end
    
    local character = LocalPlayer.Character
    if not character then
        return
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then
        return
    end
    
    local targetChar = target.Character
    if not targetChar then
        return
    end
    
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return
    end
    
    -- Save original AutoRotate state and disable it
    if OriginalAutoRotate == nil then
        OriginalAutoRotate = humanoid.AutoRotate
        humanoid.AutoRotate = false
    end
    
    -- Create rotation update connection if it doesn't exist
    if not RotationConnection then
        RotationConnection = RunService.RenderStepped:Connect(function()
            local char = LocalPlayer.Character
            if not char then return end
            
            local hum = char:FindFirstChildOfClass("Humanoid")
            local root = char:FindFirstChild("HumanoidRootPart")
            if not hum or not root then return end
            
            if not CurrentTarget or not CurrentTarget.Character then
                -- Нет цели - восстанавливаем AutoRotate и сбрасываем состояние
                hum.AutoRotate = true
                OriginalAutoRotate = nil
                return
            end
            
            local targetRoot = CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
            if not targetRoot then
                -- Нет корня цели - восстанавливаем AutoRotate и сбрасываем состояние
                hum.AutoRotate = true
                OriginalAutoRotate = nil
                return
            end
            
            -- Не поворачиваемся к дальним целям (>60м) - они только для ESP
            local distance = (root.Position - targetRoot.Position).Magnitude
            if distance > Config.DetectionRadius then
                -- Цель за пределами радиуса - восстанавливаем AutoRotate и сбрасываем состояние
                hum.AutoRotate = true
                OriginalAutoRotate = nil
                return
            end
            
            -- Сохраняем оригинальное состояние если ещё не сохранили
            if OriginalAutoRotate == nil then
                OriginalAutoRotate = hum.AutoRotate
            end
            
            -- Disable AutoRotate to prevent automatic rotation
            hum.AutoRotate = false
            
            -- Check if enough time has passed since last update
            local currentTime = tick()
            if currentTime - LastCFrameUpdate < CFRAME_UPDATE_INTERVAL then
                return
            end
            
            LastCFrameUpdate = currentTime
            
            -- Calculate direction to target (horizontal only)
            local direction = (targetRoot.Position - root.Position)
            local lookVector = Vector3.new(direction.X, 0, direction.Z)
            
            if lookVector.Magnitude > 0.001 then
                -- Create target orientation
                local targetCFrame = CFrame.lookAt(root.Position, root.Position + lookVector)
                
                -- Apply only rotation, preserve position
                root.CFrame = CFrame.new(root.Position) * (targetCFrame - targetCFrame.Position)
            end
        end)
    end
end

-- Stop rotation
local function StopRotation()
    if RotationConnection then
        RotationConnection:Disconnect()
        RotationConnection = nil
    end
    
    -- Reset last update time
    LastCFrameUpdate = 0
    
    -- Restore original AutoRotate state
    if OriginalAutoRotate ~= nil then
        local character = LocalPlayer.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.AutoRotate = OriginalAutoRotate
            end
        end
        OriginalAutoRotate = nil
    end
end

-- Attack target with equipped tool
-- ИЗМЕНЕНО: Ротация теперь только slap-перчатки
local function AttackTarget(target)
    local currentTime = tick()
    -- Применяем джиттер для рандомизации задержки
    local jitter = TIMING.JITTER_MIN + math.random() * (TIMING.JITTER_MAX - TIMING.JITTER_MIN)
    local attackDelay = Config.AttackDelay * jitter
    if currentTime - LastAttackTime < attackDelay then
        return
    end
    
    if not target then
        return
    end
    
    local character = LocalPlayer.Character
    if not character then
        return
    end
    
    local currentTool = character:FindFirstChildOfClass("Tool")
    if not currentTool then
        EquippedTool = nil
        return
    end
    
    EquippedTool = currentTool
    
    local targetChar = target.Character
    if not targetChar then
        return
    end
    
    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid or targetHumanoid.Health <= 0 then
        return
    end
    
    -- ИЗМЕНЕНО: Проверяем перчатки из ротации (slap + Gummy Bear, без Ban Hammer)
    -- Все slap-перчатки и Gummy Bear имеют Cooldown = 0.7s (из Items.lua brainrot)
    local isGummy = IsGummyBear(currentTool)
    local isRotationGlove = (IsGlove(currentTool) or isGummy) and not IsBanHammer(currentTool)
    local _, gloves = ScanInventory()
    
    -- Check distance to target (only rotate gloves if target within 45m)
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local distanceToTarget = math.huge
    
    if rootPart and targetRoot then
        distanceToTarget = (rootPart.Position - targetRoot.Position).Magnitude
    end
    
    local shouldRotate = isRotationGlove and #gloves >= 4 and distanceToTarget <= 45
    
    -- Setup tool activation detector for rotation gloves (slap + Gummy Bear)
    if shouldRotate and currentTool then
        -- Перчатки из ротации - слушаем Activated
        local activatedConnection = nil
        local switchScheduled = false
        
        activatedConnection = currentTool.Activated:Connect(function()
            -- Attack detected! Switch to next glove
            LastToolActivation = tick()
            switchScheduled = true
            
            -- Disconnect to avoid multiple triggers
            if activatedConnection then
                activatedConnection:Disconnect()
                activatedConnection = nil
            end
            
            -- Задержка зависит от типа перчатки (Gummy Bear = 0.7s cooldown из игры)
            local postDelay = isGummy and TIMING.POST_ATTACK_GUMMY_BEAR or TIMING.GLOVE_SWITCH_WAIT
            -- Применяем джиттер для рандомизации
            local jitterMult = TIMING.JITTER_MIN + math.random() * (TIMING.JITTER_MAX - TIMING.JITTER_MIN)
            postDelay = postDelay * jitterMult
            task.wait(postDelay)
            SwitchToNextGlove()
        end)
        
        -- Таймаут для перчаток
        task.spawn(function()
            task.wait(0.25)
            if not switchScheduled then
                if activatedConnection then
                    activatedConnection:Disconnect()
                    activatedConnection = nil
                end
                LogGlove("TIMEOUT", currentTool.Name, "no Activated event")
                SwitchToNextGlove()
            end
        end)
    end
    
    -- Активируем инструмент (только slap-перчатки в ротации)
    if currentTool and currentTool.Parent == character then
        pcall(function()
            currentTool:Activate()
        end)
    else
        if currentTool then
            LogGlove("SKIP_ATTACK", currentTool.Name, "tool not in character (Parent=" .. tostring(currentTool.Parent) .. ")")
        end
    end
    
    LastAttackTime = currentTime
end

-- Remove Laser Gun beam (оптимизировано с SafeDestroy)
local function RemoveLaserGunBeam()
    SafeDestroy(LaserGunState.TargetBeam)
    SafeDestroy(LaserGunState.BeamAttachment0)
    SafeDestroy(LaserGunState.BeamAttachment1)
    
    LaserGunState.TargetBeam = nil
    LaserGunState.BeamAttachment0 = nil
    LaserGunState.BeamAttachment1 = nil
    OptimizationLimits.TotalInstancesCreated = math.max(0, OptimizationLimits.TotalInstancesCreated - 3)
end

-- Main killaura loop
local function CreateLaserGunBeam(target)
    -- СТРОГИЙ THROTTLE: не создаём бим слишком часто
    local currentTime = tick()
    if currentTime - LaserGunState.LastBeamCreate < LASER_GUN_BEAM_CREATE_INTERVAL then
        return
    end
    LaserGunState.LastBeamCreate = currentTime
    
    -- ЗАЩИТА: не создаём если слишком много объектов
    if OptimizationLimits.TotalInstancesCreated >= OptimizationLimits.MAX_INSTANCES_BEFORE_CLEANUP then
        return
    end
    
    if not Config.ShowESP then
        return
    end
    
    if not target then
        return
    end
    
    local character = LocalPlayer.Character
    if not character then
        return
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return
    end
    
    local targetChar = target.Character
    if not targetChar then
        return
    end
    
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        return
    end
    
    -- Переиспользуем существующий бим вместо пересоздания
    if LaserGunState.TargetBeam and LaserGunState.BeamAttachment0 and LaserGunState.BeamAttachment1 then
        -- Обновляем только позиции attachments
        if LaserGunState.BeamAttachment0.Parent == rootPart and LaserGunState.BeamAttachment1.Parent == targetRoot then
            return  -- Бим уже правильный, не трогаем
        end
    end
    
    -- Удаляем старый только если нужно пересоздать
    RemoveLaserGunBeam()
    
    -- Создаем attachments
    local att0 = Instance.new("Attachment")
    att0.Name = "LaserGunBeamAttachment0"
    att0.Position = Vector3.new(0, 2, 0)
    att0.Parent = rootPart
    
    local att1 = Instance.new("Attachment")
    att1.Name = "LaserGunBeamAttachment1"
    att1.Position = Vector3.new(0, 2, 0)
    att1.Parent = targetRoot
    
    -- Создаем синий бим для Laser Gun
    local beam = Instance.new("Beam")
    beam.Name = "LaserGunTargetBeam"
    beam.Color = ColorSequence.new(Color3.fromRGB(0, 150, 255))  -- Синий цвет
    beam.Width0 = 0.3
    beam.Width1 = 0.3
    beam.FaceCamera = true
    beam.Transparency = NumberSequence.new(0.3)
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Attachment0 = att0
    beam.Attachment1 = att1
    beam.Parent = rootPart
    
    LaserGunState.TargetBeam = beam
    LaserGunState.BeamAttachment0 = att0
    LaserGunState.BeamAttachment1 = att1
    OptimizationLimits.TotalInstancesCreated = OptimizationLimits.TotalInstancesCreated + 3  -- Учитываем созданные объекты
end

-- Main killaura loop
local function KillauraLoop()
    -- ПРИОРИТЕТ: Body Swap Protection
    -- Детекция ТОЛЬКО через мониторинг Smoke эффектов (SetupBodySwapMonitoring)
    -- Телепортационная детекция отключена - триггерим свап только по Smoke эффекту
    
    -- Если защита от свапа активна или ожидаем ответного свапа - прерываем все остальные действия
    if BodySwapState.IsProtectionActive or BodySwapState.PendingSwapBack then
        KillauraState.StatusText = "BODY SWAP: Защита..."
        return
    end
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- FRIEND SAFE MODE: Обновляем состояние и бим к другу
    -- ═══════════════════════════════════════════════════════════════════════
    UpdateFriendBeam()
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- АВТО-ВКЛЮЧЕНИЕ ПРИ ВОРЕ СВОЕЙ БАЗЫ (не друга)
    -- ═══════════════════════════════════════════════════════════════════════
    if ThiefPriorityEnabled and Config.AutoEnableOnThief then
        local myBaseThief = FindMyBaseThief()
        
        if myBaseThief and myBaseThief.player and not IsInFriendList(myBaseThief.player) then
            -- Вор моей базы обнаружен и он не друг!
            if not Config.Enabled then
                -- Скрипт выключен - включаем автоматически
                WasManuallyDisabled = true  -- Запоминаем что был выключен
                AutoEnabledForMyBaseThief = true
                Config.Enabled = true
                LastMyBaseThiefDetected = myBaseThief.player
                -- Обновляем GUI
                if _G.KillauraUpdateToggleGUI then
                    _G.KillauraUpdateToggleGUI()
                end
            end
        else
            -- Вора моей базы нет (или он друг)
            if AutoEnabledForMyBaseThief and WasManuallyDisabled then
                -- Мы включили автоматически - выключаем обратно
                Config.Enabled = false
                AutoEnabledForMyBaseThief = false
                WasManuallyDisabled = false
                LastMyBaseThiefDetected = nil
                -- Обновляем GUI
                if _G.KillauraUpdateToggleGUI then
                    _G.KillauraUpdateToggleGUI()
                end
            end
        end
    end
    
    -- ВСЕГДА обрабатываем турели и сферы (независимо от Config.Enabled)
    -- Обрабатываем все турели (телепортация и микро-движение) - НО телепортация только если включен
    for sentry, data in pairs(TrackedEnemySentries) do
        if sentry and sentry.Parent then
            ProcessEnemySentryVisuals(sentry)  -- Только визуальная часть (сферы, копии)
        end
    end
    
    -- Обновляем все сферы радиуса турелей (мигание при приближении) - ВСЕГДА
    UpdateAllSentrySpheres()
    
    if not Config.Enabled then
        CurrentTarget = nil
        RemoveESPBeam()
        RemoveLaserGunBeam()  -- Также удаляем Laser Gun beam
        AllDetectedEnemies = {}
        UpdateEnemyMarkers()  -- Убираем все маркеры
        StopRotation()  -- ВАЖНО: восстанавливаем AutoRotate
        -- Сбрасываем все блокировки при выключении
        AoEState.IsUsingAoEItem = false
        AoEState.AsyncItemLock = false
        EquipLock = false
        EquipLockOwner = nil
        StatusText = "Неактивна (сферы турелей активны)"
        
        -- НЕ удаляем сферы - они работают независимо от killaura
        
        return
    end
    
    -- Check if we have a character - if not, reset all locks
    local character = LocalPlayer.Character
    if not character then
        AoEState.IsUsingAoEItem = false
        AoEState.AsyncItemLock = false
        EquipLock = false
        EquipLockOwner = nil
        return
    end
    
    -- Check if Grapple Hook or Flying Carpet is equipped - if yes, disable all killaura functions
    if character then
        local equippedTool = character:FindFirstChildOfClass("Tool")
        if equippedTool then
            local toolName = equippedTool.Name:lower()
            if toolName:find("grapple") or toolName:find("flying") or toolName:find("carpet") then
                -- Grapple Hook or Flying Carpet detected - disable everything immediately
                CurrentTarget = nil
                RemoveESPBeam()
                AllDetectedEnemies = {}
                UpdateEnemyMarkers()
                StopRotation()
                if toolName:find("grapple") then
                    StatusText = "Приостановлено (Grapple Hook)"
                else
                    StatusText = "Приостановлено (Flying Carpet)"
                end
                return
            end
        end
        
        -- Check if Quantum Cloner is equipped - if yes, start 1 second pause and schedule unequip
        if equippedTool and equippedTool.Name == "Quantum Cloner" then
            local currentTime = tick()
            -- Set pause timer when Quantum Cloner is first detected
            if QuantumClonerPauseUntil < currentTime then
                QuantumClonerPauseUntil = currentTime + QUANTUM_CLONER_PAUSE_DURATION
                QuantumClonerEquipped = true
                
                -- Schedule unequip after 1 second (async)
                task.delay(QUANTUM_CLONER_PAUSE_DURATION, function()
                    local character = LocalPlayer.Character
                    if character then
                        local currentEquipped = character:FindFirstChildOfClass("Tool")
                        -- Only unequip if Quantum Cloner is still equipped
                        if currentEquipped and currentEquipped.Name == "Quantum Cloner" then
                            local humanoid = character:FindFirstChildOfClass("Humanoid")
                            if humanoid then
                                humanoid:UnequipTools()
                            end
                        end
                    end
                    QuantumClonerEquipped = false
                end)
            end
        end
    end
    
    -- Check if we're in Quantum Cloner pause period
    local currentTime = tick()
    if currentTime < QuantumClonerPauseUntil then
        -- Pause all actions during Quantum Cloner usage
        CurrentTarget = nil
        RemoveESPBeam()
        AllDetectedEnemies = {}
        UpdateEnemyMarkers()
        StopRotation()
        local remainingTime = math.ceil((QuantumClonerPauseUntil - currentTime) * 10) / 10
        StatusText = "Пауза (Quantum Cloner): " .. remainingTime .. "с"
        return
    end
    
    -- Find closest enemy (also detects all enemies) - FIRST!
    local target = FindClosestEnemy()
    
    -- Update enemy markers for all detected enemies
    UpdateEnemyMarkers()
    
    -- Проверяем есть ли телепортированная вражеская турель (приоритет над дальними врагами)
    local teleportedSentry = GetTeleportedEnemySentry()
    
    -- КРИТИЧНО: Если есть телепортированная турель - НЕ используем AoE и Laser Gun
    -- Используем ТОЛЬКО цикл перчаток пока турель не будет уничтожена
    if not teleportedSentry then
        -- AFTER FindClosestEnemy filled AllDetectedEnemies, check AoE
        CheckAndUseAoEItems()
        
        -- LASER GUN: Проверяем и используем отдельно (ПОСЛЕ AoE проверки)
        CheckAndUseLaserGun()
    end
    
    -- Обрабатываем все турели (телепортация и микро-движение) - БОЕВАЯ ЛОГИКА
    for sentry, data in pairs(TrackedEnemySentries) do
        if sentry and sentry.Parent then
            ProcessEnemySentry(sentry)  -- Полная обработка включая телепортацию
        else
            TrackedEnemySentries[sentry] = nil
        end
    end
    
    -- Сферы уже обновлены выше (до проверки Config.Enabled)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- FRIEND SAFE MODE: Определяем эффективный радиус для боя
    -- При друге в 50м - атакуем перчатками только в радиусе 10м
    -- ═══════════════════════════════════════════════════════════════════════
    local effectiveCombatRadius = 45  -- Стандартный радиус
    if Config.FriendSafeMode and FriendSafeState.FullRestriction then
        effectiveCombatRadius = FRIEND_CLOSE_COMBAT_RADIUS  -- 10м при друге в 50м
    end
    
    -- Определяем есть ли враг в БОЕВОМ радиусе
    local hasCombatTarget = false
    local character = LocalPlayer.Character
    if target and character then
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart and target.Character then
            local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local dist = (rootPart.Position - targetRoot.Position).Magnitude
                hasCombatTarget = (dist <= effectiveCombatRadius)
            end
        end
    end
    
    -- Если есть телепортированная турель и НЕТ врага в боевом радиусе - атакуем турель
    if teleportedSentry and not hasCombatTarget then
        -- Показываем ESP beam к ближайшему врагу
        local beamTarget = target
        if beamTarget and Config.ShowESP then
            -- Для ESP используем отдельную переменную, не CurrentTarget
            if CurrentTarget ~= beamTarget then
                RemoveESPBeam()
                CurrentTarget = beamTarget
                CreateESPBeam(beamTarget)
            else
                UpdateESPBeamColor()
            end
        elseif not beamTarget then
            -- Нет врагов вообще - удаляем бим
            if CurrentTarget then
                RemoveESPBeam()
                CurrentTarget = nil
            end
        end
        
        -- Телепортированная турель есть - атакуем её
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local sentryPosition = GetEnemySentryPosition(teleportedSentry)
            
            if rootPart and sentryPosition then
                -- Проверяем реально экипированный инструмент
                local currentTool = character:FindFirstChildOfClass("Tool")
                
                -- ИЗМЕНЕНО: Если экипирован Ban Hammer - переключаемся на slap-перчатку
                if currentTool and IsBanHammer(currentTool) then
                    SwitchToNextGlove()
                    task.wait(0.05)
                    currentTool = character:FindFirstChildOfClass("Tool")
                end
                
                -- Экипируем slap-перчатку если нужно (Ban Hammer и Gummy Bear НЕ используются для турелей)
                if Config.AutoEquipTool and not currentTool then
                    local tool = FindBestTool()
                    if tool then
                        EquipTool(tool)
                        task.wait(0.05)
                        currentTool = character:FindFirstChildOfClass("Tool")
                    end
                end
                
                EquippedTool = currentTool
                
                StatusText = "Атака турели (перчатками)"
                
                -- Атакуем турель ТОЛЬКО slap-перчатками
                if not AoEState.IsUsingAoEItem and currentTool and not IsBanHammer(currentTool) then
                    AttackTeleportedSentry(teleportedSentry)
                end
            end
        end
        return  -- Выходим - турель в приоритете
    end

    if target then
        -- New target detected
        if CurrentTarget ~= target then
            RemoveESPBeam()
            CurrentTarget = target
            
            -- Create ESP beam for new target
            if Config.ShowESP then
                CreateESPBeam(target)
            end
        else
            -- Update beam color based on current distance
            if Config.ShowESP then
                UpdateESPBeamColor()
            end
        end
        
        -- Показываем количество обнаруженных врагов и статус вора
        local enemyCount = #AllDetectedEnemies
        local isMyBaseThiefTarget = IsMyBaseThief(target)
        local isThief = IsBrainrotThief(target)
        
        -- FRIEND SAFE MODE: Добавляем индикатор режима
        local friendSafePrefix = ""
        if Config.FriendSafeMode and FriendSafeState.FullRestriction then
            friendSafePrefix = "[SAFE-50] "  -- Полное ограничение
        elseif Config.FriendSafeMode and FriendSafeState.AoEDisabled then
            friendSafePrefix = "[SAFE-100] "  -- Только AoE выключены
        end
        
        if isMyBaseThiefTarget then
            -- Вор моей базы - АБСОЛЮТНЫЙ приоритет!
            local myBaseThief = FindMyBaseThief()
            local brainrotInfo = myBaseThief and myBaseThief.brainrotName or "???"
            StatusText = friendSafePrefix .. "🏠 МОЯ БАЗА: " .. target.Name .. " [" .. brainrotInfo .. "]"
        elseif isThief then
            -- Вор лучшего brainrot - приоритетная цель!
            local thief = FindBrainrotThief()
            local brainrotInfo = thief and thief.brainrotName or "???"
            StatusText = friendSafePrefix .. "🚨 ВОР: " .. target.Name .. " [" .. brainrotInfo .. "]"
        elseif enemyCount > 1 then
            StatusText = friendSafePrefix .. "Цель: " .. target.Name .. " (" .. enemyCount .. " врагов)"
        else
            StatusText = friendSafePrefix .. "Цель: " .. target.Name
        end
        
        -- Check if we have a tool equipped
        local character = LocalPlayer.Character
        if character then
            local currentTool = character:FindFirstChildOfClass("Tool")
            EquippedTool = currentTool
        end
        
        -- Skip tool equipping if SYNCHRONOUS AoE item is being used
        -- AoEState.AsyncItemLock НЕ блокирует - асинхронные предметы работают параллельно с атакой
        if AoEState.IsUsingAoEItem then
            return
        end
        
        -- Skip tool equipping if Quantum Cloner pause is active
        if currentTime < QuantumClonerPauseUntil then
            return
        end
        
        -- Calculate distance to target for equip logic
        local distanceToTarget = math.huge
        if character and target.Character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
            
            if rootPart and targetRoot then
                distanceToTarget = (rootPart.Position - targetRoot.Position).Magnitude
            end
        end
        
        -- ═══════════════════════════════════════════════════════════════════════
        -- FRIEND SAFE MODE: При полном ограничении (друг в 50м) - атакуем только в радиусе 10м
        -- ═══════════════════════════════════════════════════════════════════════
        local effectiveGloveRange = 45  -- Стандартный радиус перчаток
        if Config.FriendSafeMode and FriendSafeState.FullRestriction then
            effectiveGloveRange = FRIEND_CLOSE_COMBAT_RADIUS  -- Только 10м при друге в 50м
        end
        
        -- Only equip tool if target is within effective range (glove range)
        -- НЕ переключаем инструменты только если используется SYNC AoE
        -- AoEState.AsyncItemLock НЕ блокирует - async предметы работают параллельно
        if not AoEState.IsUsingAoEItem and Config.AutoEquipTool and not EquippedTool and distanceToTarget <= effectiveGloveRange then
            local tool = FindBestTool()
            if tool then
                local equipped = EquipTool(tool)
                if equipped then
                    StatusText = "Экипировка: " .. tool.Name
                    task.wait(0.05) -- Small delay after equipping
                end
            end
        elseif not AoEState.IsUsingAoEItem and distanceToTarget > effectiveGloveRange then
            -- Unequip if target is beyond effective range (ТОЛЬКО если не используем sync AoE)
            if character and EquippedTool then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid:UnequipTools()
                    EquippedTool = nil
                end
            end
        end
        
        -- Rotate to target (locked-in) - но только если враг в радиусе атаки
        if distanceToTarget <= effectiveGloveRange then
            RotateToTarget(target)
        else
            StopRotation()
        end
        
        -- Skip attacking ONLY if SYNCHRONOUS AoE item is being used
        -- Асинхронные предметы (Rage Table, Heatseeker, Attack Doge) НЕ блокируют атаку
        if AoEState.IsUsingAoEItem then
            return
        end
        
        -- FRIEND SAFE MODE: Атакуем только если враг в эффективном радиусе
        if distanceToTarget <= effectiveGloveRange then
            -- Attack target
            AttackTarget(target)
        end
    else
        -- Нет врагов в боевом радиусе и нет турелей - стандартное поведение
        -- НЕ снимаем инструмент только если используется sync AoE
        -- AoEState.AsyncItemLock НЕ блокирует снятие - async работают параллельно
        if not AoEState.IsUsingAoEItem then
            local character = LocalPlayer.Character
            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid and EquippedTool then
                    humanoid:UnequipTools()
                    EquippedTool = nil
                end
            end
        end
        
        if CurrentTarget then
            StatusText = "Поиск целей..."
        else
            StatusText = "Активна (нет целей)"
        end
        CurrentTarget = nil
        RemoveESPBeam()
        StopRotation()
    end
end

-- ═══════════════════════════════════════════════════════════════════════
-- МИНИМАЛИСТИЧНЫЙ GUI (без эмодзи, современный дизайн)
-- ═══════════════════════════════════════════════════════════════════════
local function CreateGUI()
    -- Clean up existing GUI
    local existingGui = LocalPlayer.PlayerGui:FindFirstChild("KillauraGUI")
    if existingGui then
        existingGui:Destroy()
        task.wait(0.1)
    end
    
    -- Create ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "KillauraGUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = true
    screenGui.DisplayOrder = 100
    
    -- Цветовая схема (темная тема с акцентами)
    local Colors = {
        Background = Color3.fromRGB(18, 18, 22),
        BackgroundLight = Color3.fromRGB(28, 28, 35),
        Accent = Color3.fromRGB(220, 60, 60),
        AccentGreen = Color3.fromRGB(60, 200, 100),
        AccentBlue = Color3.fromRGB(60, 140, 220),
        Text = Color3.fromRGB(240, 240, 245),
        TextDim = Color3.fromRGB(140, 140, 155),
        TextMuted = Color3.fromRGB(90, 90, 105),
        Border = Color3.fromRGB(50, 50, 60),
        Divider = Color3.fromRGB(40, 40, 50)
    }
    
    -- Main Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 260, 0, 230)
    mainFrame.Position = UDim2.new(
        Config.GuiPositionScale.X, 
        Config.GuiPositionOffset.X,
        Config.GuiPositionScale.Y, 
        Config.GuiPositionOffset.Y
    )
    mainFrame.BackgroundColor3 = Colors.Background
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Visible = true
    mainFrame.Parent = screenGui
    
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame
    
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Colors.Border
    mainStroke.Thickness = 1
    mainStroke.Parent = mainFrame
    
    -- Тень (эффект глубины)
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 30, 1, 30)
    shadow.Position = UDim2.new(0, -15, 0, -15)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://5554236805"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.6
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(23, 23, 277, 277)
    shadow.ZIndex = 0
    shadow.Parent = mainFrame
    
    -- Header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Colors.BackgroundLight
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = header
    
    -- Исправление углов header (только верхние)
    local headerFix = Instance.new("Frame")
    headerFix.Size = UDim2.new(1, 0, 0, 12)
    headerFix.Position = UDim2.new(0, 0, 1, -12)
    headerFix.BackgroundColor3 = Colors.BackgroundLight
    headerFix.BorderSizePixel = 0
    headerFix.Parent = header
    
    -- Индикатор статуса (точка)
    local statusDot = Instance.new("Frame")
    statusDot.Name = "StatusDot"
    statusDot.Size = UDim2.new(0, 8, 0, 8)
    statusDot.Position = UDim2.new(0, 14, 0.5, -4)
    statusDot.BackgroundColor3 = Colors.Accent
    statusDot.BorderSizePixel = 0
    statusDot.Parent = header
    
    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = statusDot
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -60, 1, 0)
    title.Position = UDim2.new(0, 30, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "KILLAURA"
    title.TextColor3 = Colors.Text
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
    
    -- Version badge
    local versionBadge = Instance.new("TextLabel")
    versionBadge.Size = UDim2.new(0, 30, 0, 16)
    versionBadge.Position = UDim2.new(1, -42, 0.5, -8)
    versionBadge.BackgroundColor3 = Colors.Accent
    versionBadge.BackgroundTransparency = 0.8
    versionBadge.Font = Enum.Font.GothamBold
    versionBadge.Text = "v2"
    versionBadge.TextColor3 = Colors.Accent
    versionBadge.TextSize = 10
    versionBadge.Parent = header
    
    local versionCorner = Instance.new("UICorner")
    versionCorner.CornerRadius = UDim.new(0, 4)
    versionCorner.Parent = versionBadge
    
    -- Content container
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -20, 1, -46)
    content.Position = UDim2.new(0, 10, 0, 40)
    content.BackgroundTransparency = 1
    content.Parent = mainFrame
    
    -- Toggle Button
    local toggleButton = Instance.new("TextButton")
    toggleButton.Name = "ToggleButton"
    toggleButton.Size = UDim2.new(1, -90, 0, 32)  -- Уменьшаем ширину для кнопки кейбинда
    toggleButton.Position = UDim2.new(0, 0, 0, 0)
    toggleButton.BackgroundColor3 = Colors.Accent
    toggleButton.BorderSizePixel = 0
    toggleButton.Font = Enum.Font.GothamBold
    toggleButton.Text = "ВЫКЛЮЧЕНО"
    toggleButton.TextColor3 = Colors.Text
    toggleButton.TextSize = 12
    toggleButton.AutoButtonColor = false
    toggleButton.Parent = content
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 8)
    toggleCorner.Parent = toggleButton
    
    -- Keybind Button (кнопка для установки клавиши)
    local keybindButton = Instance.new("TextButton")
    keybindButton.Name = "KeybindButton"
    keybindButton.Size = UDim2.new(0, 80, 0, 32)
    keybindButton.Position = UDim2.new(1, -80, 0, 0)
    keybindButton.BackgroundColor3 = Colors.BackgroundLight
    keybindButton.BorderSizePixel = 0
    keybindButton.Font = Enum.Font.GothamBold
    keybindButton.Text = "[" .. Config.ToggleKeybind .. "]"
    keybindButton.TextColor3 = Colors.TextDim
    keybindButton.TextSize = 12
    keybindButton.AutoButtonColor = false
    keybindButton.Parent = content
    
    local keybindCorner = Instance.new("UICorner")
    keybindCorner.CornerRadius = UDim.new(0, 8)
    keybindCorner.Parent = keybindButton
    
    local keybindStroke = Instance.new("UIStroke")
    keybindStroke.Color = Colors.Border
    keybindStroke.Thickness = 1
    keybindStroke.Parent = keybindButton
    
    -- Radius Toggle (маленькая кнопка справа)
    local radiusButton = Instance.new("TextButton")
    radiusButton.Name = "RadiusButton"
    radiusButton.Size = UDim2.new(0, 80, 0, 24)
    radiusButton.Position = UDim2.new(1, -80, 0, 38)
    radiusButton.BackgroundColor3 = Colors.AccentBlue
    radiusButton.BorderSizePixel = 0
    radiusButton.Font = Enum.Font.GothamSemibold
    radiusButton.Text = "RADIUS"
    radiusButton.TextColor3 = Colors.Text
    radiusButton.TextSize = 10
    radiusButton.AutoButtonColor = false
    radiusButton.Parent = content
    
    local radiusCorner = Instance.new("UICorner")
    radiusCorner.CornerRadius = UDim.new(0, 6)
    radiusCorner.Parent = radiusButton
    
    -- Auto Enable On Thief чекбокс (между status и RADIUS)
    local autoEnableCheckbox = Instance.new("TextButton")
    autoEnableCheckbox.Name = "AutoEnableCheckbox"
    autoEnableCheckbox.Size = UDim2.new(0, 12, 0, 12)
    autoEnableCheckbox.Position = UDim2.new(0, 0, 0, 58)
    autoEnableCheckbox.BackgroundColor3 = Config.AutoEnableOnThief and Colors.AccentGreen or Colors.BackgroundLight
    autoEnableCheckbox.BorderSizePixel = 0
    autoEnableCheckbox.Text = Config.AutoEnableOnThief and "✓" or ""
    autoEnableCheckbox.TextColor3 = Colors.Text
    autoEnableCheckbox.TextSize = 9
    autoEnableCheckbox.Font = Enum.Font.GothamBold
    autoEnableCheckbox.AutoButtonColor = false
    autoEnableCheckbox.Parent = content
    
    local autoEnableCheckboxCorner = Instance.new("UICorner")
    autoEnableCheckboxCorner.CornerRadius = UDim.new(0, 3)
    autoEnableCheckboxCorner.Parent = autoEnableCheckbox
    
    local autoEnableLabel = Instance.new("TextLabel")
    autoEnableLabel.Name = "AutoEnableLabel"
    autoEnableLabel.Size = UDim2.new(0, 30, 0, 12)
    autoEnableLabel.Position = UDim2.new(0, 14, 0, 58)
    autoEnableLabel.BackgroundTransparency = 1
    autoEnableLabel.Text = "AUTO"
    autoEnableLabel.TextColor3 = Colors.TextDim
    autoEnableLabel.TextSize = 8
    autoEnableLabel.Font = Enum.Font.Gotham
    autoEnableLabel.TextXAlignment = Enum.TextXAlignment.Left
    autoEnableLabel.Parent = content
    
    -- Disable On Reinject чекбокс (правее AUTO)
    local reinjectCheckbox = Instance.new("TextButton")
    reinjectCheckbox.Name = "ReinjectCheckbox"
    reinjectCheckbox.Size = UDim2.new(0, 12, 0, 12)
    reinjectCheckbox.Position = UDim2.new(0, 48, 0, 58)
    reinjectCheckbox.BackgroundColor3 = Config.DisableOnReinject and Colors.AccentGreen or Colors.BackgroundLight
    reinjectCheckbox.BorderSizePixel = 0
    reinjectCheckbox.Text = Config.DisableOnReinject and "✓" or ""
    reinjectCheckbox.TextColor3 = Colors.Text
    reinjectCheckbox.TextSize = 9
    reinjectCheckbox.Font = Enum.Font.GothamBold
    reinjectCheckbox.AutoButtonColor = false
    reinjectCheckbox.Parent = content
    
    local reinjectCheckboxCorner = Instance.new("UICorner")
    reinjectCheckboxCorner.CornerRadius = UDim.new(0, 3)
    reinjectCheckboxCorner.Parent = reinjectCheckbox
    
    local reinjectLabel = Instance.new("TextLabel")
    reinjectLabel.Name = "ReinjectLabel"
    reinjectLabel.Size = UDim2.new(0, 35, 0, 12)
    reinjectLabel.Position = UDim2.new(0, 62, 0, 58)
    reinjectLabel.BackgroundTransparency = 1
    reinjectLabel.Text = "START"
    reinjectLabel.TextColor3 = Colors.TextDim
    reinjectLabel.TextSize = 8
    reinjectLabel.Font = Enum.Font.Gotham
    reinjectLabel.TextXAlignment = Enum.TextXAlignment.Left
    reinjectLabel.Parent = content
    
    -- Status Label
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(0.65, -5, 0, 24)
    statusLabel.Position = UDim2.new(0, 0, 0, 38)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.GothamMedium
    statusLabel.Text = StatusText
    statusLabel.TextColor3 = Colors.TextDim
    statusLabel.TextSize = 10
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
    statusLabel.Parent = content
    
    -- Divider 1
    local divider1 = Instance.new("Frame")
    divider1.Size = UDim2.new(1, 0, 0, 1)
    divider1.Position = UDim2.new(0, 0, 0, 78)
    divider1.BackgroundColor3 = Colors.Divider
    divider1.BorderSizePixel = 0
    divider1.Parent = content
    
    -- Tools section
    local toolsLabel = Instance.new("TextLabel")
    toolsLabel.Name = "ToolsLabel"
    toolsLabel.Size = UDim2.new(1, 0, 0, 20)
    toolsLabel.Position = UDim2.new(0, 0, 0, 84)
    toolsLabel.BackgroundTransparency = 1
    toolsLabel.Font = Enum.Font.GothamMedium
    toolsLabel.Text = "Загрузка..."
    toolsLabel.TextColor3 = Colors.TextDim
    toolsLabel.TextSize = 10
    toolsLabel.TextXAlignment = Enum.TextXAlignment.Left
    toolsLabel.TextTruncate = Enum.TextTruncate.AtEnd
    toolsLabel.Parent = content
    
    -- Divider 2
    local divider2 = Instance.new("Frame")
    divider2.Size = UDim2.new(1, 0, 0, 1)
    divider2.Position = UDim2.new(0, 0, 0, 108)
    divider2.BackgroundColor3 = Colors.Divider
    divider2.BorderSizePixel = 0
    divider2.Parent = content
    
    -- AoE Status (компактный)
    local aoeContainer = Instance.new("Frame")
    aoeContainer.Name = "AoEContainer"
    aoeContainer.Size = UDim2.new(1, 0, 0, 55)
    aoeContainer.Position = UDim2.new(0, 0, 0, 114)
    aoeContainer.BackgroundTransparency = 1
    aoeContainer.Parent = content
    
    local aoeTitle = Instance.new("TextLabel")
    aoeTitle.Size = UDim2.new(1, 0, 0, 14)
    aoeTitle.BackgroundTransparency = 1
    aoeTitle.Font = Enum.Font.GothamBold
    aoeTitle.Text = "ITEMS"
    aoeTitle.TextColor3 = Colors.TextMuted
    aoeTitle.TextSize = 9
    aoeTitle.TextXAlignment = Enum.TextXAlignment.Left
    aoeTitle.Parent = aoeContainer
    
    local aoeLabel = Instance.new("TextLabel")
    aoeLabel.Name = "AoELabel"
    aoeLabel.Size = UDim2.new(1, 0, 0, 38)
    aoeLabel.Position = UDim2.new(0, 0, 0, 14)
    aoeLabel.BackgroundTransparency = 1
    aoeLabel.Font = Enum.Font.GothamMedium
    aoeLabel.Text = "Нет"
    aoeLabel.TextColor3 = Colors.TextDim
    aoeLabel.TextSize = 9
    aoeLabel.TextXAlignment = Enum.TextXAlignment.Left
    aoeLabel.TextYAlignment = Enum.TextYAlignment.Top
    aoeLabel.TextWrapped = true
    aoeLabel.Parent = aoeContainer
    
    -- Enemies counter (нижняя часть)
    local enemyCounter = Instance.new("TextLabel")
    enemyCounter.Name = "EnemyCounter"
    enemyCounter.Size = UDim2.new(0.3, -5, 0, 16)  -- Уменьшаем для переключателя
    enemyCounter.Position = UDim2.new(0, 0, 1, -20)
    enemyCounter.BackgroundTransparency = 1
    enemyCounter.Font = Enum.Font.GothamBold
    enemyCounter.Text = "0 TARGETS"
    enemyCounter.TextColor3 = Colors.TextMuted
    enemyCounter.TextSize = 10
    enemyCounter.TextXAlignment = Enum.TextXAlignment.Left
    enemyCounter.Parent = content
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- FRIEND SAFE MODE TOGGLE (слева от кнопки Friends)
    -- ═══════════════════════════════════════════════════════════════════════
    local friendSafeToggle = Instance.new("TextButton")
    friendSafeToggle.Name = "FriendSafeToggle"
    friendSafeToggle.Size = UDim2.new(0, 20, 0, 16)
    friendSafeToggle.Position = UDim2.new(0.3, 0, 1, -20)
    friendSafeToggle.BackgroundColor3 = Config.FriendSafeMode and Colors.AccentGreen or Colors.BackgroundLight
    friendSafeToggle.BorderSizePixel = 0
    friendSafeToggle.Font = Enum.Font.GothamBold
    friendSafeToggle.Text = Config.FriendSafeMode and "S" or "-"
    friendSafeToggle.TextColor3 = Colors.Text
    friendSafeToggle.TextSize = 9
    friendSafeToggle.AutoButtonColor = false
    friendSafeToggle.Parent = content
    
    local friendSafeCorner = Instance.new("UICorner")
    friendSafeCorner.CornerRadius = UDim.new(0, 4)
    friendSafeCorner.Parent = friendSafeToggle
    
    -- Friends button (открывает окно френд-листа)
    local friendsButton = Instance.new("TextButton")
    friendsButton.Name = "FriendsButton"
    friendsButton.Size = UDim2.new(0.5, -30, 0, 16)  -- Уменьшаем для переключателя
    friendsButton.Position = UDim2.new(0.3, 25, 1, -20)
    friendsButton.BackgroundColor3 = Colors.AccentBlue
    friendsButton.BackgroundTransparency = 0.3
    friendsButton.BorderSizePixel = 0
    friendsButton.Font = Enum.Font.GothamBold
    friendsButton.Text = "FRIENDS"
    friendsButton.TextColor3 = Colors.Text
    friendsButton.TextSize = 9
    friendsButton.AutoButtonColor = false
    friendsButton.Parent = content
    
    local friendsCorner = Instance.new("UICorner")
    friendsCorner.CornerRadius = UDim.new(0, 4)
    friendsCorner.Parent = friendsButton
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- FRIEND LIST GUI (отдельное окно)
    -- ═══════════════════════════════════════════════════════════════════════
    
    local friendListFrame = Instance.new("Frame")
    friendListFrame.Name = "FriendListFrame"
    friendListFrame.Size = UDim2.new(0, 280, 0, 350)
    friendListFrame.Position = UDim2.new(0.5, 140, 0.1, 0)
    friendListFrame.BackgroundColor3 = Colors.Background
    friendListFrame.BorderSizePixel = 0
    friendListFrame.Active = true
    friendListFrame.Draggable = true
    friendListFrame.Visible = false
    friendListFrame.Parent = screenGui
    
    local flCorner = Instance.new("UICorner")
    flCorner.CornerRadius = UDim.new(0, 12)
    flCorner.Parent = friendListFrame
    
    local flStroke = Instance.new("UIStroke")
    flStroke.Color = Colors.Border
    flStroke.Thickness = 1
    flStroke.Parent = friendListFrame
    
    -- Friend List Header
    local flHeader = Instance.new("Frame")
    flHeader.Name = "Header"
    flHeader.Size = UDim2.new(1, 0, 0, 36)
    flHeader.BackgroundColor3 = Colors.BackgroundLight
    flHeader.BorderSizePixel = 0
    flHeader.Parent = friendListFrame
    
    local flHeaderCorner = Instance.new("UICorner")
    flHeaderCorner.CornerRadius = UDim.new(0, 12)
    flHeaderCorner.Parent = flHeader
    
    local flHeaderFix = Instance.new("Frame")
    flHeaderFix.Size = UDim2.new(1, 0, 0, 12)
    flHeaderFix.Position = UDim2.new(0, 0, 1, -12)
    flHeaderFix.BackgroundColor3 = Colors.BackgroundLight
    flHeaderFix.BorderSizePixel = 0
    flHeaderFix.Parent = flHeader
    
    local flTitle = Instance.new("TextLabel")
    flTitle.Size = UDim2.new(1, -50, 1, 0)
    flTitle.Position = UDim2.new(0, 14, 0, 0)
    flTitle.BackgroundTransparency = 1
    flTitle.Font = Enum.Font.GothamBold
    flTitle.Text = "FRIEND LIST"
    flTitle.TextColor3 = Colors.Text
    flTitle.TextSize = 14
    flTitle.TextXAlignment = Enum.TextXAlignment.Left
    flTitle.Parent = flHeader
    
    -- Close button
    local flCloseButton = Instance.new("TextButton")
    flCloseButton.Size = UDim2.new(0, 24, 0, 24)
    flCloseButton.Position = UDim2.new(1, -32, 0.5, -12)
    flCloseButton.BackgroundColor3 = Colors.Accent
    flCloseButton.BorderSizePixel = 0
    flCloseButton.Font = Enum.Font.GothamBold
    flCloseButton.Text = "X"
    flCloseButton.TextColor3 = Colors.Text
    flCloseButton.TextSize = 12
    flCloseButton.AutoButtonColor = false
    flCloseButton.Parent = flHeader
    
    local flCloseCorner = Instance.new("UICorner")
    flCloseCorner.CornerRadius = UDim.new(0, 6)
    flCloseCorner.Parent = flCloseButton
    
    -- Tab buttons (Server Players / Friend List)
    local tabContainer = Instance.new("Frame")
    tabContainer.Size = UDim2.new(1, -20, 0, 28)
    tabContainer.Position = UDim2.new(0, 10, 0, 42)
    tabContainer.BackgroundTransparency = 1
    tabContainer.Parent = friendListFrame
    
    local serverTab = Instance.new("TextButton")
    serverTab.Size = UDim2.new(0.5, -2, 1, 0)
    serverTab.BackgroundColor3 = Colors.AccentBlue
    serverTab.BorderSizePixel = 0
    serverTab.Font = Enum.Font.GothamSemibold
    serverTab.Text = "SERVER"
    serverTab.TextColor3 = Colors.Text
    serverTab.TextSize = 10
    serverTab.AutoButtonColor = false
    serverTab.Parent = tabContainer
    
    local serverTabCorner = Instance.new("UICorner")
    serverTabCorner.CornerRadius = UDim.new(0, 6)
    serverTabCorner.Parent = serverTab
    
    local friendTab = Instance.new("TextButton")
    friendTab.Size = UDim2.new(0.5, -2, 1, 0)
    friendTab.Position = UDim2.new(0.5, 2, 0, 0)
    friendTab.BackgroundColor3 = Colors.BackgroundLight
    friendTab.BorderSizePixel = 0
    friendTab.Font = Enum.Font.GothamSemibold
    friendTab.Text = "FRIENDS"
    friendTab.TextColor3 = Colors.TextDim
    friendTab.TextSize = 10
    friendTab.AutoButtonColor = false
    friendTab.Parent = tabContainer
    
    local friendTabCorner = Instance.new("UICorner")
    friendTabCorner.CornerRadius = UDim.new(0, 6)
    friendTabCorner.Parent = friendTab
    
    -- Scrolling frame for player list
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "PlayerList"
    scrollFrame.Size = UDim2.new(1, -20, 1, -120)
    scrollFrame.Position = UDim2.new(0, 10, 0, 76)
    scrollFrame.BackgroundColor3 = Colors.BackgroundLight
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = Colors.TextMuted
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = friendListFrame
    
    local scrollCorner = Instance.new("UICorner")
    scrollCorner.CornerRadius = UDim.new(0, 8)
    scrollCorner.Parent = scrollFrame
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 4)
    listLayout.SortOrder = Enum.SortOrder.Name
    listLayout.Parent = scrollFrame
    
    local listPadding = Instance.new("UIPadding")
    listPadding.PaddingTop = UDim.new(0, 4)
    listPadding.PaddingBottom = UDim.new(0, 4)
    listPadding.PaddingLeft = UDim.new(0, 4)
    listPadding.PaddingRight = UDim.new(0, 4)
    listPadding.Parent = scrollFrame
    
    -- Info label
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Name = "InfoLabel"
    infoLabel.Size = UDim2.new(1, -20, 0, 30)
    infoLabel.Position = UDim2.new(0, 10, 1, -40)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Font = Enum.Font.GothamMedium
    infoLabel.Text = "Click player to add/remove from friends"
    infoLabel.TextColor3 = Colors.TextMuted
    infoLabel.TextSize = 9
    infoLabel.TextWrapped = true
    infoLabel.Parent = friendListFrame
    
    local currentTab = "server"  -- "server" or "friends"
    
    -- Forward declarations для функций обновления списков
    local UpdateServerPlayerList
    local UpdateFriendList
    
    -- Функция создания элемента игрока
    local function CreatePlayerEntry(player, isFriend, userId)
        local entry = Instance.new("Frame")
        entry.Name = player and player.Name or ("Friend_" .. userId)
        entry.Size = UDim2.new(1, -8, 0, 36)
        entry.BackgroundColor3 = isFriend and Color3.fromRGB(40, 60, 40) or Colors.Background
        entry.BorderSizePixel = 0
        
        local entryCorner = Instance.new("UICorner")
        entryCorner.CornerRadius = UDim.new(0, 6)
        entryCorner.Parent = entry
        
        -- Player name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -70, 0.5, 0)
        nameLabel.Position = UDim2.new(0, 8, 0, 2)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextColor3 = Colors.Text
        nameLabel.TextSize = 11
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = entry
        
        -- Display name
        local displayLabel = Instance.new("TextLabel")
        displayLabel.Size = UDim2.new(1, -70, 0.5, 0)
        displayLabel.Position = UDim2.new(0, 8, 0.5, -2)
        displayLabel.BackgroundTransparency = 1
        displayLabel.Font = Enum.Font.GothamMedium
        displayLabel.TextColor3 = Colors.TextDim
        displayLabel.TextSize = 9
        displayLabel.TextXAlignment = Enum.TextXAlignment.Left
        displayLabel.TextTruncate = Enum.TextTruncate.AtEnd
        displayLabel.Parent = entry
        
        if player then
            nameLabel.Text = player.Name
            displayLabel.Text = player.DisplayName ~= player.Name and ("@" .. player.DisplayName) or ""
        else
            -- Offline friend from saved list
            local friendData = FriendList[userId]
            if friendData then
                nameLabel.Text = friendData.Name
                displayLabel.Text = friendData.DisplayName ~= friendData.Name and ("@" .. friendData.DisplayName) or "(offline)"
            end
        end
        
        -- Action button
        local actionButton = Instance.new("TextButton")
        actionButton.Size = UDim2.new(0, 50, 0, 24)
        actionButton.Position = UDim2.new(1, -58, 0.5, -12)
        actionButton.BorderSizePixel = 0
        actionButton.Font = Enum.Font.GothamBold
        actionButton.TextSize = 9
        actionButton.AutoButtonColor = false
        actionButton.Parent = entry
        
        local actionCorner = Instance.new("UICorner")
        actionCorner.CornerRadius = UDim.new(0, 4)
        actionCorner.Parent = actionButton
        
        if isFriend then
            actionButton.Text = "REMOVE"
            actionButton.BackgroundColor3 = Colors.Accent
            actionButton.TextColor3 = Colors.Text
        else
            actionButton.Text = "ADD"
            actionButton.BackgroundColor3 = Colors.AccentGreen
            actionButton.TextColor3 = Colors.Text
        end
        
        actionButton.MouseButton1Click:Connect(function()
            if player then
                if isFriend then
                    RemoveFromFriendList(player.UserId)
                else
                    AddToFriendList(player)
                end
            else
                -- Remove offline friend by userId
                RemoveFromFriendList(userId)
            end
            
            -- Refresh list
            if currentTab == "server" then
                -- Trigger server list refresh
                UpdateServerPlayerList()
            else
                -- Trigger friends list refresh
                UpdateFriendList()
            end
        end)
        
        return entry
    end
    
    -- Функция обновления списка серверных игроков
    UpdateServerPlayerList = function()
        -- Clear existing entries
        for _, child in ipairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        
        -- Add all players from server
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local isFriend = IsInFriendList(player)
                local entry = CreatePlayerEntry(player, isFriend, tostring(player.UserId))
                entry.Parent = scrollFrame
            end
        end
        
        -- Update canvas size
        task.wait()
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
    end
    
    -- Функция обновления списка друзей
    UpdateFriendList = function()
        -- Clear existing entries
        for _, child in ipairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        
        -- Add friends from saved list
        for userId, friendData in pairs(FriendList) do
            -- Check if player is online
            local onlinePlayer = nil
            for _, player in ipairs(Players:GetPlayers()) do
                if tostring(player.UserId) == userId then
                    onlinePlayer = player
                    break
                end
            end
            
            local entry = CreatePlayerEntry(onlinePlayer, true, userId)
            entry.Parent = scrollFrame
        end
        
        -- Update canvas size
        task.wait()
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
    end
    
    -- Tab switching
    serverTab.MouseButton1Click:Connect(function()
        currentTab = "server"
        serverTab.BackgroundColor3 = Colors.AccentBlue
        serverTab.TextColor3 = Colors.Text
        friendTab.BackgroundColor3 = Colors.BackgroundLight
        friendTab.TextColor3 = Colors.TextDim
        infoLabel.Text = "Click ADD to protect player from killaura"
        UpdateServerPlayerList()
    end)
    
    friendTab.MouseButton1Click:Connect(function()
        currentTab = "friends"
        friendTab.BackgroundColor3 = Colors.AccentBlue
        friendTab.TextColor3 = Colors.Text
        serverTab.BackgroundColor3 = Colors.BackgroundLight
        serverTab.TextColor3 = Colors.TextDim
        infoLabel.Text = "Click REMOVE to allow targeting player again"
        UpdateFriendList()
    end)
    
    -- Close button
    flCloseButton.MouseButton1Click:Connect(function()
        friendListFrame.Visible = false
        Config.FriendListGuiOpen = false
    end)
    
    -- Friends button opens friend list
    friendsButton.MouseButton1Click:Connect(function()
        friendListFrame.Visible = not friendListFrame.Visible
        Config.FriendListGuiOpen = friendListFrame.Visible
        
        if friendListFrame.Visible then
            if currentTab == "server" then
                UpdateServerPlayerList()
            else
                UpdateFriendList()
            end
        end
    end)
    
    -- Update friend count on button
    local function UpdateFriendButtonText()
        local count = 0
        for _ in pairs(FriendList) do
            count = count + 1
        end
        friendsButton.Text = "FRIENDS (" .. count .. ")"
    end
    
    -- Initial update
    UpdateFriendButtonText()
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- FRIEND SAFE MODE TOGGLE HANDLER
    -- ═══════════════════════════════════════════════════════════════════════
    friendSafeToggle.MouseButton1Click:Connect(function()
        Config.FriendSafeMode = not Config.FriendSafeMode
        
        if Config.FriendSafeMode then
            friendSafeToggle.BackgroundColor3 = Colors.AccentGreen
            friendSafeToggle.Text = "S"
        else
            friendSafeToggle.BackgroundColor3 = Colors.BackgroundLight
            friendSafeToggle.Text = "-"
            -- Удаляем бим к другу если режим выключен
            RemoveFriendBeam()
        end
        
        SaveConfig()
    end)
    
    -- Hover эффект для Friend Safe Toggle
    friendSafeToggle.MouseEnter:Connect(function()
        if not Config.FriendSafeMode then
            friendSafeToggle.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
        end
    end)
    
    friendSafeToggle.MouseLeave:Connect(function()
        if not Config.FriendSafeMode then
            friendSafeToggle.BackgroundColor3 = Colors.BackgroundLight
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- ФУНКЦИОНАЛЬНОСТЬ
    -- ═══════════════════════════════════════════════════════════════════════
    
    -- Toggle button
    toggleButton.MouseButton1Click:Connect(function()
        Config.Enabled = not Config.Enabled
        
        if Config.Enabled then
            toggleButton.Text = "ВКЛЮЧЕНО"
            toggleButton.BackgroundColor3 = Colors.AccentGreen
            statusDot.BackgroundColor3 = Colors.AccentGreen
        else
            toggleButton.Text = "ВЫКЛЮЧЕНО"
            toggleButton.BackgroundColor3 = Colors.Accent
            statusDot.BackgroundColor3 = Colors.Accent
            StopRotation()
            RemoveESPBeam()
            CurrentTarget = nil
        end
        
        SaveConfig()
    end)
    
    -- Keybind button - нажмите чтобы установить новую клавишу
    keybindButton.MouseButton1Click:Connect(function()
        if IsSettingKeybind then return end
        
        IsSettingKeybind = true
        keybindButton.Text = "[...]"
        keybindButton.BackgroundColor3 = Colors.Accent
        
        -- Ждём нажатия клавиши
        local inputConnection
        inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                local keyName = input.KeyCode.Name
                
                -- Игнорируем Escape - отмена
                if input.KeyCode == Enum.KeyCode.Escape then
                    keybindButton.Text = "[" .. Config.ToggleKeybind .. "]"
                    keybindButton.BackgroundColor3 = Colors.BackgroundLight
                    IsSettingKeybind = false
                    inputConnection:Disconnect()
                    return
                end
                
                -- Устанавливаем новый кейбинд
                Config.ToggleKeybind = keyName
                keybindButton.Text = "[" .. keyName .. "]"
                keybindButton.BackgroundColor3 = Colors.BackgroundLight
                IsSettingKeybind = false
                inputConnection:Disconnect()
                SaveConfig()
            end
        end)
    end)
    
    -- Глобальный обработчик клавиши для вкл/выкл килауры
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if IsSettingKeybind then return end
        
        if input.UserInputType == Enum.UserInputType.Keyboard then
            -- Сравниваем имя клавиши напрямую
            local pressedKeyName = input.KeyCode.Name
            if pressedKeyName == Config.ToggleKeybind then
                -- Переключаем килауру
                Config.Enabled = not Config.Enabled
                
                if Config.Enabled then
                    toggleButton.Text = "ВКЛЮЧЕНО"
                    toggleButton.BackgroundColor3 = Colors.AccentGreen
                    statusDot.BackgroundColor3 = Colors.AccentGreen
                else
                    toggleButton.Text = "ВЫКЛЮЧЕНО"
                    toggleButton.BackgroundColor3 = Colors.Accent
                    statusDot.BackgroundColor3 = Colors.Accent
                    StopRotation()
                    RemoveESPBeam()
                    CurrentTarget = nil
                end
                
                SaveConfig()
            end
        end
    end)
    
    -- Hover эффект для keybind кнопки
    keybindButton.MouseEnter:Connect(function()
        if not IsSettingKeybind then
            keybindButton.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
        end
    end)
    
    keybindButton.MouseLeave:Connect(function()
        if not IsSettingKeybind then
            keybindButton.BackgroundColor3 = Colors.BackgroundLight
        end
    end)
    
    -- Radius button
    radiusButton.MouseButton1Click:Connect(function()
        Config.ShowRadius = not Config.ShowRadius
        
        if Config.ShowRadius then
            radiusButton.BackgroundColor3 = Colors.AccentBlue
            radiusButton.Text = "RADIUS"
            CreateRadiusCircles()
        else
            radiusButton.BackgroundColor3 = Colors.BackgroundLight
            radiusButton.Text = "RADIUS"
            RemoveRadiusCircles()
        end
        
        SaveConfig()
    end)
    
    -- Auto Enable On Thief checkbox handler
    autoEnableCheckbox.MouseButton1Click:Connect(function()
        Config.AutoEnableOnThief = not Config.AutoEnableOnThief
        autoEnableCheckbox.BackgroundColor3 = Config.AutoEnableOnThief and Colors.AccentGreen or Colors.BackgroundLight
        autoEnableCheckbox.Text = Config.AutoEnableOnThief and "✓" or ""
        SaveConfig()
    end)
    
    -- Disable On Reinject checkbox handler
    reinjectCheckbox.MouseButton1Click:Connect(function()
        Config.DisableOnReinject = not Config.DisableOnReinject
        reinjectCheckbox.BackgroundColor3 = Config.DisableOnReinject and Colors.AccentGreen or Colors.BackgroundLight
        reinjectCheckbox.Text = Config.DisableOnReinject and "✓" or ""
        SaveConfig()
    end)
    
    -- Функция для программного обновления toggle (для авто-включения)
    local function UpdateToggleGUI()
        if Config.Enabled then
            toggleButton.Text = "ВКЛЮЧЕНО"
            toggleButton.BackgroundColor3 = Colors.AccentGreen
            statusDot.BackgroundColor3 = Colors.AccentGreen
        else
            toggleButton.Text = "ВЫКЛЮЧЕНО"
            toggleButton.BackgroundColor3 = Colors.Accent
            statusDot.BackgroundColor3 = Colors.Accent
        end
    end
    
    -- Экспортируем функцию обновления GUI глобально
    _G.KillauraUpdateToggleGUI = UpdateToggleGUI
    
    -- Hover эффекты
    toggleButton.MouseEnter:Connect(function()
        if Config.Enabled then
            toggleButton.BackgroundColor3 = Color3.fromRGB(80, 220, 120)
        else
            toggleButton.BackgroundColor3 = Color3.fromRGB(240, 80, 80)
        end
    end)
    
    toggleButton.MouseLeave:Connect(function()
        if Config.Enabled then
            toggleButton.BackgroundColor3 = Colors.AccentGreen
        else
            toggleButton.BackgroundColor3 = Colors.Accent
        end
    end)
    
    radiusButton.MouseEnter:Connect(function()
        if Config.ShowRadius then
            radiusButton.BackgroundColor3 = Color3.fromRGB(80, 160, 240)
        else
            radiusButton.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
        end
    end)
    
    radiusButton.MouseLeave:Connect(function()
        if Config.ShowRadius then
            radiusButton.BackgroundColor3 = Colors.AccentBlue
        else
            radiusButton.BackgroundColor3 = Colors.BackgroundLight
        end
    end)
    
    -- Update loop (с throttle)
    local lastStatusUpdate = 0
    local STATUS_UPDATE_INTERVAL = 0.15
    
    RunService.RenderStepped:Connect(function()
        local currentTime = tick()
        if currentTime - lastStatusUpdate < STATUS_UPDATE_INTERVAL then
            return
        end
        lastStatusUpdate = currentTime
        
        -- Update status
        statusLabel.Text = StatusText
        
        -- Update enemy counter
        local enemyCount = #AllDetectedEnemies
        if enemyCount > 0 then
            enemyCounter.Text = enemyCount .. " TARGET" .. (enemyCount > 1 and "S" or "")
            enemyCounter.TextColor3 = Colors.AccentGreen
        else
            enemyCounter.Text = "NO TARGETS"
            enemyCounter.TextColor3 = Colors.TextMuted
        end
        
        -- Update friends button count
        UpdateFriendButtonText()
        
        -- Update tools
        local tools, gloves = ScanInventory()
        
        if #gloves >= 6 then
            local currentGlove = gloves[CurrentGloveIndex] and gloves[CurrentGloveIndex].Name or "?"
            toolsLabel.Text = "Gloves: " .. #gloves .. " | Active: " .. currentGlove
            toolsLabel.TextColor3 = Colors.AccentGreen
        elseif #tools > 0 then
            local batFound = false
            for _, tool in ipairs(tools) do
                if tool.Name:lower():find("bat") then
                    toolsLabel.Text = "Weapon: Bat | Gloves: " .. #gloves .. "/6"
                    toolsLabel.TextColor3 = Colors.TextDim
                    batFound = true
                    break
                end
            end
            if not batFound then
                toolsLabel.Text = "No bat | Need 6+ gloves"
                toolsLabel.TextColor3 = Colors.Accent
            end
        else
            toolsLabel.Text = "No items"
            toolsLabel.TextColor3 = Colors.TextMuted
        end
        
        -- Update AoE status
        local aoeStatus = {}
        
        local items = {
            {"M", "Medusa's Head"},
            {"B", "Boogie Bomb"},
            {"S", "All Seeing Sentry"},
            {"MG", "Megaphone"},
            {"T", "Taser Gun"},
            {"BL", "Bee Launcher"},
            {"LC", "Laser Cape"},
            {"RT", "Rage Table"},
            {"LG", "Laser Gun"}
        }
        
        for _, itemData in ipairs(items) do
            local shortName, fullName = itemData[1], itemData[2]
            local item = FindAoEItem(fullName)
            if item then
                local cdRemaining
                if fullName == "Laser Gun" then
                    local lastUse = LastAoEUseTime["Laser Gun"] or 0
                    local cooldown = GetLaserGunCooldown()
                    cdRemaining = math.max(0, cooldown - (currentTime - lastUse))
                    if not LaserGunState.Ready then
                        table.insert(aoeStatus, shortName .. "!")
                    elseif cdRemaining > 0 then
                        table.insert(aoeStatus, shortName .. ":" .. math.ceil(cdRemaining))
                    else
                        table.insert(aoeStatus, shortName .. "+")
                    end
                else
                    cdRemaining = GetItemCooldown(fullName)
                    if fullName == "All Seeing Sentry" and IsSentryStillPlaced() then
                        table.insert(aoeStatus, shortName .. "*")
                    elseif cdRemaining > 0 then
                        table.insert(aoeStatus, shortName .. ":" .. math.ceil(cdRemaining))
                    else
                        table.insert(aoeStatus, shortName .. "+")
                    end
                end
            end
        end
        
        if #aoeStatus > 0 then
            aoeLabel.Text = table.concat(aoeStatus, "  ")
            aoeLabel.TextColor3 = Colors.AccentGreen
        else
            aoeLabel.Text = "No AoE items"
            aoeLabel.TextColor3 = Colors.TextMuted
        end
    end)
    
    -- Save position
    mainFrame:GetPropertyChangedSignal("Position"):Connect(function()
        local newPos = mainFrame.Position
        Config.GuiPositionScale = { X = newPos.X.Scale, Y = newPos.Y.Scale }
        Config.GuiPositionOffset = { X = newPos.X.Offset, Y = newPos.Y.Offset }
        SaveConfig()
    end)
    
    -- Apply initial state
    if Config.Enabled then
        toggleButton.Text = "ВКЛЮЧЕНО"
        toggleButton.BackgroundColor3 = Colors.AccentGreen
        statusDot.BackgroundColor3 = Colors.AccentGreen
    end
    
    if not Config.ShowRadius then
        radiusButton.BackgroundColor3 = Colors.BackgroundLight
    end
    
    screenGui.Parent = LocalPlayer.PlayerGui
    mainFrame.Visible = true
    screenGui.Enabled = true
    
    return screenGui
end

-- Initialize
local function Initialize()
    -- Load config
    LoadConfig()
    
    -- Load friend list
    LoadFriendList()
    
    -- Initialize Laser Gun system
    InitializeLaserGunRemotes()
    
    -- Wait for PlayerGui to be ready
    local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    if not playerGui then
        return
    end
    
    -- Create GUI
    local gui = CreateGUI()
    if not gui then
        return
    end
    
    -- Create 3D radius circles once at startup (wait for character first)
    task.spawn(function()
        -- Wait for character to load
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = character:WaitForChild("HumanoidRootPart", 10)
        
        if hrp then
            task.wait(0.5)  -- Small delay to ensure everything is loaded
            CreateRadiusCircles()
            
            -- Setup Body Swap effect monitoring
            if BODY_SWAP_PROTECTION_ENABLED then
                SetupBodySwapMonitoring(character)
            end
        end
    end)
    
    -- Connect main loop
    RunService.Heartbeat:Connect(KillauraLoop)
    
    -- Connect enemy sentry detection (обработка турелей происходит в KillauraLoop)
    -- Используем DescendantAdded/Removing чтобы находить турели в любом месте Workspace
    Workspace.DescendantAdded:Connect(OnEnemySentryAdded)
    Workspace.DescendantRemoving:Connect(OnEnemySentryRemoved)
    
    -- Scan for existing enemy sentries
    ScanExistingEnemySentries()
    
    -- Periodic sentry check (every 0.5 seconds, check if our sentry still exists)
    task.spawn(function()
        while true do
            task.wait(SENTRY_CHECK_INTERVAL)
            
            if Config.Enabled then
                -- Verify our sentry reference is still valid
                if OurSentryInstance and not IsSentryStillPlaced() then
                    -- Sentry was destroyed, clear reference
                    OurSentryInstance = nil
                end
                
                -- Try to find our sentry if we lost track of it
                if not OurSentryInstance then
                    local foundSentry = FindOurSentryInWorkspace()
                    if foundSentry then
                        OurSentryInstance = foundSentry
                    end
                end
            end
        end
    end)
    
    -- Cleanup on character death
    LocalPlayer.CharacterAdded:Connect(function(newCharacter)
        RemoveESPBeam()
        RemoveLaserGunBeam()  -- Также удаляем Laser Gun beam
        EquippedTool = nil
        CurrentTarget = nil
        CurrentGloveIndex = 1
        AllDetectedEnemies = {}
        OurSentryInstance = nil  -- Reset sentry reference on death
        AoEState.IsUsingLaserGun = false  -- Сбрасываем флаг Laser Gun
        AoEState.IsUsingAoEItem = false  -- Сбрасываем флаг AoE
        AoEState.AsyncItemLock = false  -- Сбрасываем общую блокировку
        AoEState.IsUsingRageTable = false  -- Сбрасываем флаг Rage Table
        AoEState.IsUsingHeatseeker = false  -- Сбрасываем флаг Heatseeker
        AoEState.IsUsingAttackDoge = false  -- Сбрасываем флаг Attack Doge
        EnemySentrySystem.Tracked = {}  -- Сбрасываем отслеживаемые вражеские турели
        
        -- Сбрасываем флаги Body Swap Protection
        BodySwapState.IsProtectionActive = false
        BodySwapState.PendingSwapBack = false
        BodySwapState.SwapperPlayer = nil
        BodySwapState.LastKnownPosition = nil
        
        -- Убираем все маркеры врагов (используем SafeDestroy)
        for playerName, marker in pairs(EnemyMarkers) do
            SafeDestroy(marker)
        end
        EnemyMarkers = {}
        OptimizationLimits.TotalInstancesCreated = 0  -- Сбрасываем счетчик при респавне
        
        -- Recreate circles after respawn
        task.wait(1)
        RemoveRadiusCircles()
        task.wait(0.5)
        CreateRadiusCircles()
        
        -- Re-setup Body Swap effect monitoring for new character
        if BODY_SWAP_PROTECTION_ENABLED then
            task.wait(0.2)
            SetupBodySwapMonitoring(newCharacter)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- КРИТИЧЕСКАЯ СИСТЕМА: Периодическая очистка памяти для предотвращения крашей
-- ═══════════════════════════════════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(OptimizationLimits.MEMORY_CLEANUP_INTERVAL)  -- Каждые 15 секунд
        
        local currentTime = tick()
        
        -- ПРИНУДИТЕЛЬНАЯ ОЧИСТКА если создано слишком много объектов
        if OptimizationLimits.TotalInstancesCreated >= OptimizationLimits.MAX_INSTANCES_BEFORE_CLEANUP then
            -- Удаляем все маркеры
            for playerName, marker in pairs(EnemyMarkers) do
                SafeDestroy(marker)
            end
            EnemyMarkers = {}
            
            -- Удаляем ESP beam
            RemoveESPBeam()
            
            -- Сбрасываем счетчик
            OptimizationLimits.TotalInstancesCreated = 0
            LastForcedMarkerCleanup = currentTime
        end
        
        -- Очистка старых записей LastAoEUseTime (старше 60 сек)
        local cleanedAoETime = {}
        for itemName, useTime in pairs(LastAoEUseTime) do
            if currentTime - useTime < 60 then
                cleanedAoETime[itemName] = useTime
            end
        end
        LastAoEUseTime = cleanedAoETime
        
        -- Дополнительная очистка "мертвых" объектов
        if not Config.Enabled then
            -- Если killaura выключена, очищаем все визуальные объекты
            RemoveESPBeam()
            for playerName, marker in pairs(EnemyMarkers) do
                SafeDestroy(marker)
            end
            EnemyMarkers = {}
            AllDetectedEnemies = {}
            OptimizationLimits.TotalInstancesCreated = 0
        end
        
        -- Очистка nil значений из AllDetectedEnemies
        local validEnemies = {}
        for i, enemyData in ipairs(AllDetectedEnemies) do
            if enemyData and enemyData.player and enemyData.player.Parent then
                table.insert(validEnemies, enemyData)
            end
        end
        AllDetectedEnemies = validEnemies
        
        -- Garbage collection hint (Roblox будет собирать мусор)
        -- Явный вызов не нужен, но очистка nil ссылок помогает
    end
end)

-- Start the script
Initialize()
