--[[
    Custom Sound Replacer v2.0
    Заменяет игровые звуки на кастомные из локальной папки
    
    Автоматически создает структуру при первом запуске
]]

-- ============== ЗАЩИТА ОТ АНТИЧИТА ==============

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

-- Безопасный вызов функций
local function safeCall(func, ...)
    local args = {...}
    local success, result = pcall(function()
        return func(unpack(args))
    end)
    return success and result or nil
end

-- ============== КОНЕЦ ЗАЩИТЫ ==============

-- Путь к папке с кастомными звуками (относительный от workspace эксплойта)
local CUSTOM_SOUNDS_PATH = "CustomSounds/"
local MARKER_FILE = CUSTOM_SOUNDS_PATH .. ".initialized"

-- НАСТРОЙКИ
local MUTE_REPLACED_SOUNDS = false -- Если true, заменённые звуки будут полностью отключены (для теста)
local AUTO_REPLACE_NEW_SOUNDS = true -- Автоматически заменять динамически создаваемые звуки
local DEBUG_MODE = false -- Отладочные сообщения в консоль

-- База звуков (будет заполняться автоматически из игры)
local SOUND_DATABASE = {}

local CustomSoundReplacer = {}

-- Сканирует все звуки из игры и заполняет SOUND_DATABASE
function CustomSoundReplacer:ScanGameSounds()
    local workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    
    local soundsFound = 0
    
    -- Функция для обработки звука
    local function processSound(sound, categoryPath)
        if not sound:IsA("Sound") then return end
        
        local soundName = sound.Name
        local category = categoryPath or "Unknown"
        
        -- Определяем длительность звука
        local duration = math.ceil(sound.TimeLength)
        if duration == 0 then duration = 3 end -- По умолчанию 3 секунды
        
        -- Создаем категорию если не существует
        if not SOUND_DATABASE[category] then
            SOUND_DATABASE[category] = {}
        end
        
        -- Проверяем что звук еще не добавлен
        local exists = false
        for _, soundInfo in ipairs(SOUND_DATABASE[category]) do
            if soundInfo.name == soundName then
                exists = true
                break
            end
        end
        
        if not exists then
            table.insert(SOUND_DATABASE[category], {
                name = soundName,
                duration = duration .. "s",
                description = "Автоматически найден: " .. sound:GetFullName()
            })
            soundsFound = soundsFound + 1
        end
    end
    
    -- Сканируем workspace.Sounds
    local soundsFolder = workspace:FindFirstChild("Sounds")
    if soundsFolder then
        for _, child in ipairs(soundsFolder:GetChildren()) do
            if child:IsA("Sound") then
                processSound(child, "Music")
            elseif child:IsA("Folder") then
                for _, sound in ipairs(child:GetDescendants()) do
                    processSound(sound, child.Name)
                end
            end
        end
    end
    
    -- Сканируем ReplicatedStorage.Sounds
    local repSoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if repSoundsFolder then
        for _, child in ipairs(repSoundsFolder:GetChildren()) do
            if child:IsA("Sound") then
                processSound(child, "Other")
            elseif child:IsA("Folder") then
                for _, sound in ipairs(child:GetDescendants()) do
                    processSound(sound, child.Name)
                end
            end
        end
    end
    
    -- Сканируем инструменты в ReplicatedStorage.Items (все звуки инструментов попадут в Tools)
    local itemsFolder = ReplicatedStorage:FindFirstChild("Items")
    if itemsFolder then
        for _, item in ipairs(itemsFolder:GetDescendants()) do
            if item:IsA("Sound") then
                processSound(item, "Tools")
            end
        end
    end
    
    -- КАСТОМНОЕ ОТВЕТВЛЕНИЕ: Добавляем специальные звуки если их нет
    
    -- Day и Night используют специальную папку daynight
    if not SOUND_DATABASE["Music"] then
        SOUND_DATABASE["Music"] = {}
    end
    
    -- Sfx для звуков ударов
    if not SOUND_DATABASE["Sfx"] then
        SOUND_DATABASE["Sfx"] = {}
    end
    
    -- Tools для звуков инструментов
    if not SOUND_DATABASE["Tools"] then
        SOUND_DATABASE["Tools"] = {}
    end
    
    local dayExists = false
    local nightExists = false
    local slashExists = false
    local hitSoundExists = false
    
    for _, soundInfo in ipairs(SOUND_DATABASE["Music"]) do
        if soundInfo.name == "Day" then dayExists = true end
        if soundInfo.name == "Night" then nightExists = true end
    end
    
    for _, soundInfo in ipairs(SOUND_DATABASE["Sfx"]) do
        if soundInfo.name == "Slash" then slashExists = true end
        if soundInfo.name == "HitSound" then hitSoundExists = true end
    end
    
    if not dayExists then
        table.insert(SOUND_DATABASE["Music"], {
            name = "Day",
            duration = "191s",
            description = "Кастомное ответвление: Использует папку Music/daynight/ (workspace.Sounds.Day)"
        })
    end
    
    if not nightExists then
        table.insert(SOUND_DATABASE["Music"], {
            name = "Night",
            duration = "132s",
            description = "Кастомное ответвление: Использует папку Music/daynight/ (workspace.Sounds.Night)"
        })
    end
    
    if not slashExists then
        table.insert(SOUND_DATABASE["Tools"], {
            name = "Slash",
            duration = "1s",
            description = "Звук взмаха (Workspace.*.Slap.Slash)"
        })
    end
    
    if not hitSoundExists then
        table.insert(SOUND_DATABASE["Tools"], {
            name = "HitSound",
            duration = "1s",
            description = "Звук удара (Workspace.*.Slap.HitSound)"
        })
    end
    
end

-- Создает структуру папок и пустые файлы
function CustomSoundReplacer:InitializeStructure()
    -- Проверяем маркер через readfile
    if isfile(MARKER_FILE) then
        local initData = readfile(MARKER_FILE)
        
        -- Даже если структура существует, проверяем наличие папки daynight
        local daynightPath = CUSTOM_SOUNDS_PATH .. "Music/daynight/"
        if not isfolder(daynightPath) then
            makefolder(daynightPath)
            
            -- Создаем заглушки для Day и Night если их нет
            if SOUND_DATABASE["Music"] then
                for _, soundInfo in ipairs(SOUND_DATABASE["Music"]) do
                    if soundInfo.name == "Day" or soundInfo.name == "Night" then
                        local fileName = soundInfo.name .. "_" .. soundInfo.duration .. ".mp3"
                        local filePath = daynightPath .. fileName
                        
                        if not isfile(filePath) then
                            local placeholder = string.format(
                                "PLACEHOLDER: %s\nDuration: %s\nReplace this file with your MP3\n\n=== СПЕЦИАЛЬНОЕ ПРАВИЛО ДЛЯ %s ===\n- Если этот файл существует и не является заглушкой, он будет использоваться\n- Если файл пустой/заглушка или отсутствует, будет выбран СЛУЧАЙНЫЙ звук из папки Music/daynight/\n- Звуки не повторяются до тех пор пока все не будут использованы\n- Положите свои MP3 файлы в эту папку для случайного выбора",
                                soundInfo.description,
                                soundInfo.duration,
                                soundInfo.name
                            )
                            writefile(filePath, placeholder)
                            print("[CustomSoundReplacer] ✓ Создана заглушка: " .. fileName)
                        end
                    end
                end
            end
        end
        
        return false
    end
    
    local success, result = pcall(function()
        -- Создаем корневую папку
        if not isfolder(CUSTOM_SOUNDS_PATH) then
            makefolder(CUSTOM_SOUNDS_PATH)
        end
        
        -- Создаем категории и файлы
        for category, sounds in pairs(SOUND_DATABASE) do
            local categoryPath = CUSTOM_SOUNDS_PATH .. category .. "/"
            
            if not isfolder(categoryPath) then
                makefolder(categoryPath)
            end
            
            -- Создаем файлы-заглушки
            for _, soundInfo in ipairs(sounds) do
                local fileName = soundInfo.name .. "_" .. soundInfo.duration .. ".mp3"
                local filePath = categoryPath .. fileName
                
                -- Для Day и Night создаем заглушки ТОЛЬКО в подпапке daynight
                if category == "Music" and (soundInfo.name == "Day" or soundInfo.name == "Night") then
                    local daynightPath = categoryPath .. "daynight/"
                    
                    -- Создаем папку daynight если не существует
                    if not isfolder(daynightPath) then
                        makefolder(daynightPath)
                    end
                    
                    local daynightFilePath = daynightPath .. fileName
                    if not isfile(daynightFilePath) then
                        local placeholder = string.format(
                            "PLACEHOLDER: %s\nDuration: %s\nReplace this file with your MP3\n\n=== СПЕЦИАЛЬНОЕ ПРАВИЛО ДЛЯ %s ===\n- Если этот файл существует и не является заглушкой, он будет использоваться\n- Если файл пустой/заглушка или отсутствует, будет выбран СЛУЧАЙНЫЙ звук из папки Music/daynight/\n- Звуки не повторяются до тех пор пока все не будут использованы\n- Положите свои MP3 файлы в эту папку для случайного выбора",
                            soundInfo.description,
                            soundInfo.duration,
                            soundInfo.name
                        )
                        writefile(daynightFilePath, placeholder)
                    end
                    -- Пропускаем создание заглушки в основной папке Music
                else
                    -- Для всех остальных звуков создаем заглушки в основной папке
                    if not isfile(filePath) then
                        local placeholder = string.format(
                            "PLACEHOLDER: %s\nDuration: %s\nReplace this file with your MP3",
                            soundInfo.description,
                            soundInfo.duration
                        )
                        writefile(filePath, placeholder)
                    end
                end
            end
        end
        
        -- Создаем маркер
        local markerData = "Initialized: " .. os.date("%Y-%m-%d %H:%M:%S")
        writefile(MARKER_FILE, markerData)
        
        -- Создаем README
        local readmePath = CUSTOM_SOUNDS_PATH .. "README.txt"
        local readme = [[
=== CUSTOM SOUND REPLACER ===

Эта папка содержит структуру для замены звуков в игре.

ИНСТРУКЦИЯ:
1. Найдите нужный звук в соответствующей папке (Music, Events, Ambience, Special)
2. Замените пустой файл .mp3 на ваш звук
3. Имя файла должно остаться прежним (например: Day_180s.mp3)
4. Формат: MP3
5. При следующем запуске скрипта звуки автоматически заменятся

СТРУКТУРА:
- Music/         - Основная музыка (день/ночь)
  - daynight/    - Специальная папка ТОЛЬКО для Day и Night
                   * Если заглушки присутствуют - используются они
                   * Если заглушки пустые/отсутствуют - выбирается случайный звук из этой папки
                   * Звуки не повторяются до тех пор пока все не будут использованы
                   * Другие звуки Music используют стандартную логику
- Events/        - Звуки событий (концерты, праздники)
- Ambience/      - Звуки окружения (дождь, снег)
- Special/       - Специальные звуки (глитч, космос)

ВАЖНО:
- Если звук не найден, игровой звук не будет заменен
- Рекомендуется сохранять оригинальную длительность звука
- Звуки загружаются через getcustomasset()
- Для Music/daynight: положите свои MP3 файлы в папку, скрипт будет выбирать их случайно

Версия: 2.0
]]
        writefile(readmePath, readme)
        
        return true
    end)
    
    if not success then
        warn("[CustomSoundReplacer] Ошибка при создании структуры:", result)
        return false
    end
    
    return result
end

-- Загружает кастомный звук через readfile
function CustomSoundReplacer:LoadCustomSound(category, soundName)
    -- Если категория Unknown, пытаемся найти звук во всех категориях
    if category == "Unknown" or category == nil then
        for cat, sounds in pairs(SOUND_DATABASE) do
            for _, soundInfo in ipairs(sounds) do
                if soundInfo.name == soundName then
                    -- Рекурсивно вызываем с найденной категорией
                    return self:LoadCustomSound(cat, soundName)
                end
            end
        end
        return nil
    end
    
    local categoryPath = CUSTOM_SOUNDS_PATH .. category .. "/"
    
    if not isfolder(categoryPath) then
        return nil
    end
    
    -- Специальная обработка ТОЛЬКО для Day и Night в Music
    if category == "Music" and (soundName == "Day" or soundName == "Night") then
        local daynightPath = categoryPath .. "daynight/"
        
        if isfolder(daynightPath) then
            -- Ищем нужный звук в подпапке daynight
            for _, soundInfo in ipairs(SOUND_DATABASE[category] or {}) do
                if soundInfo.name == soundName then
                    local fileName = soundInfo.name .. "_" .. soundInfo.duration .. ".mp3"
                    local filePath = daynightPath .. fileName
                    
                    if isfile(filePath) then
                        local success, content = pcall(readfile, filePath)
                        
                        -- Если файл существует и не является заглушкой (больше 1000 байт)
                        if success and content and #content > 1000 then
                            local assetSuccess, assetUrl = pcall(function()
                                return getcustomasset(filePath)
                            end)
                            if assetSuccess then
                                return assetUrl
                            end
                        else
                            -- Файл является заглушкой - выбираем случайный звук из папки
                            return self:GetRandomSoundFromFolder(daynightPath, soundName)
                        end
                    else
                        -- Файл не найден - выбираем случайный звук
                        return self:GetRandomSoundFromFolder(daynightPath, soundName)
                    end
                end
            end
        end
    end
    
    -- Обычная обработка для всех остальных звуков
    for _, soundInfo in ipairs(SOUND_DATABASE[category] or {}) do
        if soundInfo.name == soundName then
            local fileName = soundInfo.name .. "_" .. soundInfo.duration .. ".mp3"
            local filePath = categoryPath .. fileName
            
            if isfile(filePath) then
                local success, content = pcall(readfile, filePath)
                
                if success and content and #content > 1000 then
                    local assetSuccess, assetUrl = pcall(function()
                        return getcustomasset(filePath)
                    end)
                    if assetSuccess then
                        return assetUrl
                    end
                end
            end
        end
    end
    
    return nil
end

-- Получает случайный звук из папки (без повторений)
local usedSounds = {} -- Кеш использованных звуков для каждой папки
local initialDayNightSounds = {} -- Кеш для первоначально выбранных звуков

function CustomSoundReplacer:GetRandomSoundFromFolder(folderPath, hookName, isInitialLoad)
    if not isfolder(folderPath) then
        return nil
    end
    
    -- Если это начальная загрузка и звук уже выбран, используем его
    if isInitialLoad and initialDayNightSounds[hookName] then
        if DEBUG_MODE then
            print(string.format("[CustomSoundReplacer] Используем предзагруженный звук для %s", hookName))
        end
        return initialDayNightSounds[hookName]
    end
    
    -- Получаем список всех .mp3 файлов в папке
    local availableSounds = {}
    local files = listfiles(folderPath)
    
    for _, filePath in ipairs(files) do
        if filePath:lower():match("%.mp3$") then
            local success, content = pcall(readfile, filePath)
            
            -- Проверяем что это не заглушка (больше 1000 байт для надежности)
            if success and content and #content > 1000 then
                table.insert(availableSounds, filePath)
            end
        end
    end
    
    if #availableSounds == 0 then
        return nil
    end
    
    -- Инициализируем кеш для этого хука если не существует
    if not usedSounds[hookName] then
        usedSounds[hookName] = {}
    end
    
    -- Фильтруем уже использованные звуки
    local unusedSounds = {}
    for _, soundPath in ipairs(availableSounds) do
        local isUsed = false
        for _, usedPath in ipairs(usedSounds[hookName]) do
            if soundPath == usedPath then
                isUsed = true
                break
            end
        end
        
        if not isUsed then
            table.insert(unusedSounds, soundPath)
        end
    end
    
    -- Если все звуки использованы - сбрасываем кеш
    if #unusedSounds == 0 then
        usedSounds[hookName] = {}
        unusedSounds = availableSounds
    end
    
    -- Выбираем случайный звук
    local randomIndex = math.random(1, #unusedSounds)
    local selectedSound = unusedSounds[randomIndex]
    
    -- Добавляем в кеш использованных
    table.insert(usedSounds[hookName], selectedSound)
    
    -- Безопасная загрузка через pcall
    local success, assetUrl = pcall(function()
        return getcustomasset(selectedSound)
    end)
    
    if not success then
        -- Если ошибка загрузки, пропускаем этот файл и пробуем следующий
        table.remove(usedSounds[hookName])
        return self:GetRandomSoundFromFolder(folderPath, hookName, isInitialLoad)
    end
    
    -- Если это начальная загрузка, сохраняем звук для повторного использования
    if isInitialLoad then
        initialDayNightSounds[hookName] = assetUrl
    end
    
    if DEBUG_MODE then
        print(string.format("[CustomSoundReplacer] ✓ Выбран случайный звук: %s", selectedSound))
    end
    
    return assetUrl
end

-- Предзагружает случайные звуки для Day и Night при старте игры
function CustomSoundReplacer:PreloadDayNightSounds()
    local daynightPath = CUSTOM_SOUNDS_PATH .. "Music/daynight/"
    
    if not isfolder(daynightPath) then
        return
    end
    
    -- Предзагружаем первый случайный звук (используется для обоих Day и Night)
    local firstSound = self:GetRandomSoundFromFolder(daynightPath, "DayNight", true)
    
    -- Если нет звуков, просто выходим без ошибки
    if not firstSound then
        return
    end
    
    -- Применяем звук к текущим объектам в игре
    local workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    
    -- Ищем напрямую в Workspace.Sounds и ReplicatedStorage.Sounds
    local replaced = 0
    local soundsToReplace = {"Day", "Night"}
    local soundObjects = {}
    
    for _, soundName in ipairs(soundsToReplace) do
        -- Ищем в Workspace.Sounds
        local wsSound = workspace:FindFirstChild("Sounds")
        if wsSound then
            local foundSound = wsSound:FindFirstChild(soundName, true) -- recursive search
            if foundSound and foundSound:IsA("Sound") then
                foundSound.SoundId = firstSound
                replaced = replaced + 1
                table.insert(soundObjects, foundSound)
            end
        end
        
        -- Ищем в ReplicatedStorage.Sounds
        local rsSound = ReplicatedStorage:FindFirstChild("Sounds")
        if rsSound then
            local foundSound = rsSound:FindFirstChild(soundName, true) -- recursive search
            if foundSound and foundSound:IsA("Sound") then
                foundSound.SoundId = firstSound
                replaced = replaced + 1
                table.insert(soundObjects, foundSound)
            end
        end
    end
    
    if replaced > 0 then
        -- Устанавливаем автоматическое переключение на следующий случайный звук
        for _, soundObj in ipairs(soundObjects) do
            soundObj.Ended:Connect(function()
                local nextSound = self:GetRandomSoundFromFolder(daynightPath, "DayNight", false)
                if nextSound then
                    soundObj.SoundId = nextSound
                    -- Воспроизводим если звук был активен
                    if soundObj.Parent and soundObj.Parent.Parent then
                        soundObj:Play()
                    end
                end
            end)
        end
    end
end

-- Заменяет звук в workspace.Sounds
function CustomSoundReplacer:ReplaceSound(soundObject, category, soundName)
    if not soundObject or not soundObject:IsA("Sound") then
        return false
    end
    
    -- Если включен режим отключения звуков
    if MUTE_REPLACED_SOUNDS then
        soundObject.Volume = 0
        return true
    end
    
    local customAsset = self:LoadCustomSound(category, soundName)
    
    if customAsset then
        soundObject.SoundId = customAsset
        if DEBUG_MODE then
            print(string.format("[CustomSoundReplacer] ✓ Заменен звук: %s (%s)", soundName, category))
        end
        return true
    end
    
    return false
end

-- Основная функция замены всех звуков
function CustomSoundReplacer:ReplaceAllSounds()
    local workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    
    local replacedCount = 0
    local totalCount = 0
    local skippedCount = 0
    
    -- Заменяем звуки из каждой категории
    for category, sounds in pairs(SOUND_DATABASE) do
        for _, soundInfo in ipairs(sounds) do
            totalCount = totalCount + 1
            
            -- Парсим полный путь звука из description
            local fullPath = soundInfo.description:match("Автоматически найден: (.+)")
            if not fullPath then
                skippedCount = skippedCount + 1
                if DEBUG_MODE then
                    print(string.format("[CustomSoundReplacer] ! Некорректный путь: %s", soundInfo.name))
                end
                continue
            end
            
            -- Получаем объект звука по полному пути
            local soundObject = nil
            local parts = {}
            for part in fullPath:gmatch("[^.]+") do
                table.insert(parts, part)
            end
            
            -- Находим звук
            if parts[1] == "Workspace" then
                soundObject = workspace
            elseif parts[1] == "ReplicatedStorage" then
                soundObject = ReplicatedStorage
            end
            
            if soundObject then
                for i = 2, #parts do
                    soundObject = soundObject:FindFirstChild(parts[i])
                    if not soundObject then break end
                end
            end
            
            if soundObject and soundObject:IsA("Sound") then
                if self:ReplaceSound(soundObject, category, soundInfo.name) then
                    replacedCount = replacedCount + 1
                end
            else
                skippedCount = skippedCount + 1
                if DEBUG_MODE then
                    print(string.format("[CustomSoundReplacer] ! Звук не найден: %s (%s)", soundInfo.name, category))
                end
            end
        end
    end
end

-- Мониторит и автоматически заменяет динамически создаваемые звуки
-- Настраивает автоматическую смену Day/Night музыки
function CustomSoundReplacer:SetupDayNightAutoSwitch()
    local workspace = game:GetService("Workspace")
    local soundsFolder = workspace:FindFirstChild("Sounds")
    if not soundsFolder then return end
    
    local daySound = soundsFolder:FindFirstChild("Day")
    local nightSound = soundsFolder:FindFirstChild("Night")
    
    if daySound and daySound:IsA("Sound") then
        daySound.Ended:Connect(function()
            local daynightPath = CUSTOM_SOUNDS_PATH .. "Music/daynight/"
            local nextSound = self:GetRandomSoundFromFolder(daynightPath, "Day", false)
            if nextSound then
                daySound.SoundId = nextSound
            end
        end)
    end
    
    if nightSound and nightSound:IsA("Sound") then
        nightSound.Ended:Connect(function()
            local daynightPath = CUSTOM_SOUNDS_PATH .. "Music/daynight/"
            local nextSound = self:GetRandomSoundFromFolder(daynightPath, "Night", false)
            if nextSound then
                nightSound.SoundId = nextSound
            end
        end)
    end
end

-- Легкий мониторинг только для инструментов игрока (Slash и HitSound)
function CustomSoundReplacer:SetupSlashHitSoundMonitor()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    
    if not player then return end
    
    local function monitorCharacter(character)
        -- Мониторим только добавление инструментов в персонаж
        character.ChildAdded:Connect(function(tool)
            if tool:IsA("Tool") then
                -- Ищем звуки только в этом инструменте
                for _, descendant in ipairs(tool:GetDescendants()) do
                    if descendant:IsA("Sound") then
                        local soundName = descendant.Name
                        if soundName == "Slash" or soundName == "HitSound" then
                            local customUrl = self:LoadCustomSound("Tools", soundName)
                            if customUrl then
                                descendant.SoundId = customUrl
                            end
                        end
                    end
                end
                
                -- Следим за новыми звуками в инструменте
                tool.DescendantAdded:Connect(function(descendant)
                    if descendant:IsA("Sound") then
                        local soundName = descendant.Name
                        if soundName == "Slash" or soundName == "HitSound" then
                            task.wait(0.05)
                            local customUrl = self:LoadCustomSound("Tools", soundName)
                            if customUrl then
                                descendant.SoundId = customUrl
                            end
                        end
                    end
                end)
            end
        end)
        
        -- Проверяем уже существующие инструменты
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") then
                for _, descendant in ipairs(tool:GetDescendants()) do
                    if descendant:IsA("Sound") then
                        local soundName = descendant.Name
                        if soundName == "Slash" or soundName == "HitSound" then
                            local customUrl = self:LoadCustomSound("Tools", soundName)
                            if customUrl then
                                descendant.SoundId = customUrl
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Мониторим текущего персонажа
    if player.Character then
        monitorCharacter(player.Character)
    end
    
    -- Мониторим следующих персонажей
    player.CharacterAdded:Connect(monitorCharacter)
end

-- Устанавливает hook на PlaySound для замены звуков на лету
-- Главная функция
function CustomSoundReplacer:Start()
    -- Проверка функций эксплойта
    if not isfolder or not makefolder or not isfile or not writefile or not readfile or not getcustomasset then
        return
    end
    
    task.wait(2.7)
    
    local workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    
    -- Ждем папки со звуками
    local soundsFolder = workspace:FindFirstChild("Sounds") or workspace:WaitForChild("Sounds", 5)
    local repSoundsFolder = ReplicatedStorage:FindFirstChild("Sounds") or ReplicatedStorage:WaitForChild("Sounds", 5)
    
    if repSoundsFolder then
        local sfxFolder = repSoundsFolder:FindFirstChild("Sfx")
        if not sfxFolder then
            repSoundsFolder:WaitForChild("Sfx", 3)
        end
    end
    
    task.wait(0.7)
    
    -- Сканируем все звуки из игры
    self:ScanGameSounds()
    
    -- Инициализация структуры (создаст папки только для новых звуков)
    self:InitializeStructure()
    
    -- Дополнительное ожидание для загрузки всех звуков
    task.wait(1)
    
    -- ПЕРВОСТЕПЕННО: Предзагружаем и заменяем Day/Night звуки ОДИН РАЗ при старте
    self:PreloadDayNightSounds()
    
    -- Заменяем все существующие звуки
    self:ReplaceAllSounds()
    
    -- Настраиваем автоматическую смену Day/Night музыки при окончании трека
    self:SetupDayNightAutoSwitch()
    
    -- Мониторинг только инструментов игрока для Slash и HitSound
    self:SetupSlashHitSoundMonitor()
end

-- Автозапуск
local replacer = CustomSoundReplacer
replacer:Start()
