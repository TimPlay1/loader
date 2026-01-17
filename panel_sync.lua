--[[
    Panel Sync Script v1.3
    Читает локальные файлы brainrots_*.json и синхронизирует с веб-панелью
    Запускается отдельно от farm.lua - собирает данные ВСЕХ фермеров
    
    КООРДИНАЦИЯ: Использует lock-файл чтобы несколько инстансов не отправляли
    данные одновременно. Только один инстанс отправляет раз в 3 секунды.
    
    v1.3 FIX: Не синкает пустые данные (0 brainrots, 0 income) чтобы
    не перезаписывать хорошие данные на сервере при раннем старте
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Configuration
local FARM_FOLDER = "farm_data"
local KEY_FILE = FARM_FOLDER .. "/key.txt"
local LOCK_FILE = FARM_FOLDER .. "/sync_lock.json"

-- ============ API URL CONFIGURATION ============
local PANEL_API_URL = "https://ody.farm/api/sync"

local SYNC_INTERVAL = 5 -- секунд между проверками (увеличено для стабильности)
local MIN_SYNC_DELAY = 5 -- минимальная пауза между синхронизациями
local LOCK_TIMEOUT = 15 -- секунд до истечения лока
local HTTP_TIMEOUT = 30 -- timeout для HTTP запросов
local STARTUP_DELAY = 8 -- задержка перед первым sync (прогрев эксплоита)

-- Уникальный ID этого инстанса
local INSTANCE_ID = LocalPlayer.Name .. "_" .. tostring(math.random(100000, 999999))

print("[PanelSync] Instance ID: " .. INSTANCE_ID)

-- Base64 encoding функция
local function base64encode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

-- URL-safe base64 (заменяем + на -, / на _, убираем =)
local function base64urlEncode(data)
    local b64 = base64encode(data)
    b64 = b64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
    return b64
end

-- Определяем HTTP функцию один раз при загрузке
local HTTP_FUNC = nil
local HTTP_NAME = "none"

if request then
    HTTP_FUNC = request
    HTTP_NAME = "request"
elseif http_request then
    HTTP_FUNC = http_request
    HTTP_NAME = "http_request"
elseif syn and syn.request then
    HTTP_FUNC = syn.request
    HTTP_NAME = "syn.request"
elseif fluxus and fluxus.request then
    HTTP_FUNC = fluxus.request
    HTTP_NAME = "fluxus.request"
elseif http and http.request then
    HTTP_FUNC = http.request
    HTTP_NAME = "http.request"
end

print("[PanelSync] HTTP method: " .. HTTP_NAME)

if not HTTP_FUNC then
    warn("[PanelSync] ❌ No HTTP method available! Panel sync will not work.")
end

-- ============ COORDINATION SYSTEM ============
-- Проверить можно ли сейчас синхронизировать (lock не занят)
local function canSync()
    local lock = nil
    pcall(function()
        if isfile(LOCK_FILE) then
            local content = readfile(LOCK_FILE)
            if content and content ~= "" then
                lock = HttpService:JSONDecode(content)
            end
        end
    end)
    
    if not lock then
        return true -- Нет лока - можно синхронизировать
    end
    
    local now = os.time()
    
    -- Проверяем не истёк ли лок (процесс мог умереть)
    if lock.timestamp and (now - lock.timestamp) > LOCK_TIMEOUT then
        return true -- Лок устарел
    end
    
    -- Проверяем прошло ли достаточно времени с последней синхронизации
    if lock.lastSync and (now - lock.lastSync) < MIN_SYNC_DELAY then
        return false -- Слишком рано
    end
    
    return true
end

-- Захватить лок перед синхронизацией
local function acquireLock()
    local now = os.time()
    local lock = {
        instanceId = INSTANCE_ID,
        timestamp = now,
        lastSync = now
    }
    
    pcall(function()
        if not isfolder(FARM_FOLDER) then
            makefolder(FARM_FOLDER)
        end
        writefile(LOCK_FILE, HttpService:JSONEncode(lock))
    end)
    
    return true
end

-- Обновить время последней синхронизации в локе
local function updateLockTime()
    local now = os.time()
    pcall(function()
        local lock = {
            instanceId = INSTANCE_ID,
            timestamp = now,
            lastSync = now
        }
        writefile(LOCK_FILE, HttpService:JSONEncode(lock))
    end)
end

-- ============ END COORDINATION ============

-- Загрузить ключ
local function loadKey()
    local key = nil
    pcall(function()
        if isfile(KEY_FILE) then
            key = readfile(KEY_FILE):gsub("%s+", "")
        end
    end)
    return key
end

-- Безопасное чтение JSON с retry
local function safeReadJSON(filePath, maxRetries)
    maxRetries = maxRetries or 3
    for attempt = 1, maxRetries do
        local success, result = pcall(function()
            if not isfile(filePath) then
                return nil
            end
            local content = readfile(filePath)
            if not content or content == "" then
                return nil
            end
            return HttpService:JSONDecode(content)
        end)
        
        if success and result then
            return result
        end
        
        -- Подождать немного перед retry (файл может быть в процессе записи)
        if attempt < maxRetries then
            task.wait(0.1)
        end
    end
    return nil
end

-- Получить путь к файлу brainrots для ТЕКУЩЕГО игрока
local function getMyBrainrotFile()
    return FARM_FOLDER .. "/brainrots_" .. LocalPlayer.Name .. ".json"
end

-- Собрать данные ТОЛЬКО текущего аккаунта
-- Каждый фермер отправляет только свои данные, сервер мержит всех в базу
local function collectMyAccountData()
    local myFile = getMyBrainrotFile()
    local data = safeReadJSON(myFile)
    
    if not data or not data.playerName then
        print("[PanelSync] No data found for " .. LocalPlayer.Name)
        return nil
    end
    
    -- v1.3: ЗАЩИТА от отправки пустых данных
    -- Не синкаем если brainrots пустой - это может быть до первого сканирования
    local brainrots = data.brainrots or {}
    local totalIncome = data.totalIncome or 0
    
    if #brainrots == 0 and totalIncome == 0 then
        print("[PanelSync] ⚠️ SKIP: brainrots empty and income=0 for " .. LocalPlayer.Name .. " - waiting for first scan")
        return nil
    end
    
    -- Для текущего аккаунта всегда isOnline = true
    local accountData = {
        playerName = data.playerName or LocalPlayer.Name,
        userId = data.userId or LocalPlayer.UserId,
        lastUpdate = data.lastUpdate or os.date("%Y-%m-%d %H:%M:%S"),
        totalBrainrots = data.totalBrainrots or #brainrots,
        maxSlots = data.maxSlots or 10,
        totalIncome = totalIncome,
        totalIncomeFormatted = data.totalIncomeFormatted or "0/s",
        isOnline = true, -- Текущий аккаунт всегда онлайн
        status = data.status or "idle",
        action = data.action or "",
        farmEnabled = data.farmEnabled or false,
        farmRunning = data.farmRunning or false,
        brainrots = brainrots
    }
    
    print("[PanelSync] Account: " .. accountData.playerName .. " | Brainrots: " .. #brainrots .. " | Income: " .. accountData.totalIncomeFormatted)
    print("[PanelSync] Current local time: " .. os.date("%Y-%m-%d %H:%M:%S"))
    
    return accountData
end

-- HTTP Sync запрос с автоматическим fallback
-- Пробует: 1) GET+base64 (обход блокировок), 2) POST (стандарт), 3) PUT (альтернатива)
local function httpSync(url, data)
    if not HTTP_FUNC then
        warn("[PanelSync] No HTTP method available!")
        return false, nil, "No HTTP method"
    end
    
    local jsonData
    local encodeSuccess, encodeErr = pcall(function()
        jsonData = HttpService:JSONEncode(data)
    end)
    
    if not encodeSuccess then
        warn("[PanelSync] JSON encode error: " .. tostring(encodeErr))
        return false, nil, "JSON encode failed"
    end
    
    local dataSize = #jsonData
    
    -- ============ МЕТОД 1: GET с base64 данными (обход блокировки POST) ============
    print("[PanelSync] Trying GET+base64 method (" .. dataSize .. " bytes)...")
    
    local base64Data = base64urlEncode(jsonData)
    local getUrl = url .. "?data=" .. base64Data
    
    -- Проверяем длину URL (максимум ~8000 символов)
    if #getUrl < 8000 then
        local success, response = pcall(function()
            return HTTP_FUNC({
                Url = getUrl,
                Method = "GET",
                Headers = {
                    ["Accept"] = "application/json",
                    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                }
            })
        end)
        
        if success and response then
            local statusCode = response.StatusCode or response.statusCode or response.status or 0
            if statusCode == 200 then
                print("[PanelSync] ✓ GET+base64 success!")
                return true, response, nil
            else
                print("[PanelSync] GET+base64 returned status: " .. tostring(statusCode))
            end
        else
            print("[PanelSync] GET+base64 failed: " .. tostring(response))
        end
    else
        print("[PanelSync] URL too long for GET (" .. #getUrl .. " chars), trying POST...")
    end
    
    -- ============ МЕТОД 2: POST с retry (стандартный) ============
    for attempt = 1, 3 do
        print("[PanelSync] Trying POST method (" .. dataSize .. " bytes), attempt " .. attempt .. "/3...")
        
        local success, response = pcall(function()
            return HTTP_FUNC({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json",
                    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                },
                Body = jsonData
            })
        end)
        
        if success and response then
            local statusCode = response.StatusCode or response.statusCode or response.status or 0
            if statusCode == 200 then
                print("[PanelSync] ✓ POST success!")
                return true, response, nil
            elseif statusCode > 0 then
                print("[PanelSync] POST returned status: " .. tostring(statusCode))
                local body = response.Body or response.body or ""
                if statusCode ~= 200 then
                    warn("[PanelSync] Response: " .. tostring(body):sub(1, 300))
                end
                return statusCode == 200, response, nil
            else
                print("[PanelSync] POST returned status 0")
                if attempt < 3 then
                    print("[PanelSync] Waiting 2s before retry...")
                    task.wait(2)
                end
            end
        else
            print("[PanelSync] POST pcall failed: " .. tostring(response))
            if attempt < 3 then
                task.wait(2)
            end
        end
    end
    
    print("[PanelSync] POST failed after 3 attempts, trying PUT...")
    
    -- ============ МЕТОД 3: PUT (альтернатива POST) ============
    print("[PanelSync] Trying PUT method (" .. dataSize .. " bytes)...")
    
    success, response = pcall(function()
        return HTTP_FUNC({
            Url = url,
            Method = "PUT",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json",
                ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            },
            Body = jsonData
        })
    end)
    
    if success and response then
        local statusCode = response.StatusCode or response.statusCode or response.status or 0
        if statusCode == 200 then
            print("[PanelSync] ✓ PUT success!")
            return true, response, nil
        else
            print("[PanelSync] PUT returned status: " .. tostring(statusCode))
        end
    end
    
    warn("[PanelSync] All methods failed!")
    return false, response, "All methods failed"
end

-- Главная функция синхронизации
-- Отправляет ТОЛЬКО данные текущего аккаунта (сервер мержит всех)
local function syncToPanel()
    local farmKey = loadKey()
    if not farmKey or farmKey == "" then
        warn("[PanelSync] No farm key found in " .. KEY_FILE)
        return false
    end
    
    local myAccount = collectMyAccountData()
    
    if not myAccount then
        warn("[PanelSync] No account data found for " .. LocalPlayer.Name)
        return false
    end
    
    local panelData = {
        farmKey = farmKey,
        timestamp = os.time(),
        accounts = { myAccount }, -- Только ОДИН аккаунт - сервер мержит
        totalGlobalIncome = myAccount.totalIncome or 0 -- Только свой income
    }
    
    local success, response = httpSync(PANEL_API_URL, panelData)
    if success then
        print("[PanelSync] ✓ Synced account " .. myAccount.playerName .. " to panel")
        updateLockTime() -- Обновляем время последней синхронизации
        return true
    else
        warn("[PanelSync] ✗ Failed to sync to panel")
        return false
    end
end

-- Главный цикл
print("[PanelSync] Starting panel sync service...")
print("[PanelSync] API URL: " .. PANEL_API_URL)
print("[PanelSync] Farm folder: " .. FARM_FOLDER)
print("[PanelSync] Sync interval: " .. SYNC_INTERVAL .. " seconds")
print("[PanelSync] Min delay between syncs: " .. MIN_SYNC_DELAY .. " seconds")

-- Минимальная начальная задержка (чтобы инстансы не стартовали одновременно)
task.wait(1 + math.random() * 2)

-- Первая синхронизация - пробуем СРАЗУ
local firstSyncSuccess = false
if canSync() then
    acquireLock()
    print("[PanelSync] Attempting immediate first sync...")
    firstSyncSuccess = syncToPanel()
end

-- Если первый sync не удался - ждём warmup и пробуем ещё раз
if not firstSyncSuccess then
    local warmupDelay = STARTUP_DELAY + math.random() * 3
    print("[PanelSync] First sync failed, waiting " .. string.format("%.1f", warmupDelay) .. "s warmup...")
    task.wait(warmupDelay)
    
    if canSync() then
        acquireLock()
        print("[PanelSync] Retrying after warmup...")
        syncToPanel()
    end
end

-- Бесконечный цикл синхронизации с координацией
local skippedCount = 0
local consecutiveFailures = 0

while true do
    task.wait(SYNC_INTERVAL + math.random() * 2) -- Добавляем jitter
    
    if canSync() then
        acquireLock()
        local success = syncToPanel()
        skippedCount = 0
        
        if success then
            consecutiveFailures = 0
        else
            consecutiveFailures = consecutiveFailures + 1
            -- Если много фейлов подряд, увеличиваем паузу
            if consecutiveFailures >= 3 then
                local extraWait = math.min(consecutiveFailures * 2, 30)
                print("[PanelSync] " .. consecutiveFailures .. " failures, waiting extra " .. extraWait .. "s...")
                task.wait(extraWait)
            end
        end
    else
        skippedCount = skippedCount + 1
        if skippedCount % 10 == 1 then
            print("[PanelSync] Skipping - another instance synced recently")
        end
    end
end
