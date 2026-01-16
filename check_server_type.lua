-- [[ КОД ]] --

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- 1. Ожидание инициализации LocalPlayer
if not Players.LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
end
local LocalPlayer = Players.LocalPlayer

print("[Protection] Начинаю проверку типа сервера...")

-- Функция безопасного поиска объектов с ожиданием
local function checkServerType()
    -- Даем время на прогрузку карты, так как скрипт грузится рано
    -- Используем WaitForChild с таймаутом, чтобы не зависнуть навечно
    local map = Workspace:WaitForChild("Map", 60)
    if not map then return warn("Не удалось найти папку Map") end

    local codes = map:WaitForChild("Codes", 60)
    if not codes then return warn("Не удалось найти модель Codes") end

    local mainPart = codes:WaitForChild("Main", 60)
    if not mainPart then return warn("Не удалось найти Main part") end

    local surfaceGui = mainPart:WaitForChild("SurfaceGui", 60)
    local mainFrame = surfaceGui and surfaceGui:WaitForChild("MainFrame", 60)
    
    -- Ищем тот самый индикатор приватки
    local privateMsg = mainFrame and mainFrame:WaitForChild("PrivateServerMessage", 60)

    if not privateMsg then
        warn("Не удалось найти индикатор сервера (PrivateServerMessage).")
        return
    end

    -- [[ ГЛАВНАЯ ПРОВЕРКА ]] --
    -- На публичном сервере это сообщение скрыто (Visible = false)
    -- На приватном сервере оно видно (Visible = true)
    
    if privateMsg.Visible == false then
        warn(">> ОБНАРУЖЕН ПУБЛИЧНЫЙ СЕРВЕР! ВЫХОЖУ... <<")
        game:Shutdown() -- Кикаем игрока
    else
        print(">> Это приватный сервер. Всё в порядке. <<")
    end
end

-- Запускаем проверку в защищенном режиме (pcall), чтобы ошибки не крашили поток,
-- и в отдельном потоке (task.spawn), чтобы не тормозить остальной скрипт.
task.spawn(function()
    local success, err = pcall(checkServerType)
    if not success then
        warn("Ошибка при проверке сервера: " .. tostring(err))
    end
end)