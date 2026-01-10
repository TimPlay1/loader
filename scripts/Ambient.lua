task.wait(5) -- Group 2: UI/Effects (5 sec delay)

--[[
    Ambient Controller (Optimized)
    Purpose: Custom skybox, lighting control, color picker GUI
    Created: 2025-12-29
]]

-- Services
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local RF = game:GetService("ReplicatedFirst")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

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
    return player:WaitForChild("PlayerGui")
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

-- Constants
local CONFIG_FILE = "skybox_config.json"
local SKYBOX_FOLDER = "skyboxes"
local BLACK_TEX = "rbxasset://textures/blackBkg_square.png"
local ENFORCE_INTERVAL = 0.5

-- State
local customSky, currentSkyboxAsset, savedLaserColor, savedGroundColor
local currentHue, currentSat, currentVal = 0, 0.8, 0.7
local isDragging = { brightness = false, canvas = false, hue = false, panel = false }
local dragStart, startPos

-- Wait for game load
local function waitForLoad()
    local timeout = tick() + 30
    while RF:GetAttribute("ClientLoaded") ~= true and tick() < timeout do task.wait(0.1) end
    timeout = tick() + 30
    while RF:GetAttribute("DataLoaded") ~= true and tick() < timeout do task.wait(0.1) end
    task.wait(0.5)
end
waitForLoad()

-- Utility functions
local function HSVtoRGB(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local r, g, b
    i = i % 6
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return Color3.new(r, g, b)
end

local function clamp(v, min, max) return math.max(min, math.min(max, v)) end

local function createInstance(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end

-- Config system
local function loadConfig()
    local ok, result = pcall(function()
        if isfile(CONFIG_FILE) then
            local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
            local screen = workspace.CurrentCamera.ViewportSize
            return {
                brightness = data.brightness or 1,
                skyboxColor = Color3.new(data.skyboxColor.R, data.skyboxColor.G, data.skyboxColor.B),
                guiPosition = UDim2.new(0, clamp(data.guiPosition.X, 0, screen.X - 320), 0, clamp(data.guiPosition.Y, 0, screen.Y - 480)),
                hue = data.hue or 0, saturation = data.saturation or 0.8, value = data.value or 0.7,
                customSkybox = data.customSkybox
            }
        end
    end)
    return ok and result or {
        brightness = 1, skyboxColor = Color3.fromRGB(50, 20, 70),
        guiPosition = UDim2.new(1, -370, 0, 60), hue = 0, saturation = 0.8, value = 0.7
    }
end

local function saveConfig(brightness, color, pos, skybox)
    pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode({
            brightness = brightness,
            skyboxColor = { R = color.R, G = color.G, B = color.B },
            guiPosition = { X = pos.X.Offset, Y = pos.Y.Offset },
            hue = currentHue, saturation = currentSat, value = currentVal,
            customSkybox = skybox
        }))
    end)
end

local config = loadConfig()
currentHue, currentSat, currentVal = config.hue, config.saturation, config.value

-- Lighting system
local lightingValues = {
    Ambient = config.skyboxColor,
    OutdoorAmbient = Color3.new(config.skyboxColor.R * 0.5, config.skyboxColor.G * 0.5, config.skyboxColor.B * 0.5),
    Brightness = config.brightness, ClockTime = 12, GeographicLatitude = 0,
    ColorShift_Top = config.skyboxColor,
    ColorShift_Bottom = Color3.new(config.skyboxColor.R * 0.3, config.skyboxColor.G * 0.3, config.skyboxColor.B * 0.3),
    ExposureCompensation = -0.5, FogColor = Color3.new(config.skyboxColor.R * 0.3, config.skyboxColor.G * 0.3, config.skyboxColor.B * 0.3),
    FogEnd = 10000, FogStart = 0
}

local function applyLighting()
    for prop, val in pairs(lightingValues) do pcall(function() Lighting[prop] = val end) end
end
applyLighting()

-- Skybox system
local function createSky()
    for _, sky in ipairs(Lighting:GetChildren()) do if sky:IsA("Sky") then sky:Destroy() end end
    customSky = createInstance("Sky", {
        Name = "CustomAmbientSky", SkyboxBk = BLACK_TEX, SkyboxDn = BLACK_TEX,
        SkyboxFt = BLACK_TEX, SkyboxLf = BLACK_TEX, SkyboxRt = BLACK_TEX,
        SkyboxUp = BLACK_TEX, StarCount = 0, CelestialBodiesShown = false
    }, Lighting)
end
createSky()

-- Atmosphere for tinting
local atm = createInstance("Atmosphere", { Name = "AmbientAtmosphere", Density = 0.3, Offset = 0, Glare = 0, Haze = 0, Color = config.skyboxColor, Decay = config.skyboxColor }, Lighting)

local function enforceSkybox()
    local sky = Lighting:FindFirstChild("CustomAmbientSky")
    if not sky then createSky() return end
    local tex = currentSkyboxAsset or BLACK_TEX
    sky.SkyboxBk, sky.SkyboxDn, sky.SkyboxFt = tex, tex, tex
    sky.SkyboxLf, sky.SkyboxRt, sky.SkyboxUp = tex, tex, tex
    for _, c in ipairs(Lighting:GetChildren()) do if c:IsA("Sky") and c ~= customSky then c:Destroy() end end
end

-- Custom skybox files
local function ensureSkyboxFolder() pcall(function() if not isfolder(SKYBOX_FOLDER) then makefolder(SKYBOX_FOLDER) end end) end

local function getSkyboxList()
    local list = {"Default (Black)"}
    pcall(function()
        ensureSkyboxFolder()
        for _, f in ipairs(listfiles(SKYBOX_FOLDER)) do
            local name = f:match("([^/\\]+)$")
            if name and name:lower():match("%.([^%.]+)$") and ({png=1,jpg=1,jpeg=1,webp=1,bmp=1})[name:lower():match("%.([^%.]+)$")] then
                table.insert(list, name)
            end
        end
    end)
    return list
end

local currentCustomSkybox
local function applyCustomSkybox(name)
    if name == "Default (Black)" or not name then
        currentSkyboxAsset, currentCustomSkybox = nil, nil
        if customSky then for _, side in ipairs({"Bk","Dn","Ft","Lf","Rt","Up"}) do customSky["Skybox"..side] = BLACK_TEX end end
        return
    end
    pcall(function()
        local path = SKYBOX_FOLDER .. "/" .. name
        if isfile(path) then
            local asset = (getsynasset or getcustomasset)(path)
            if asset and customSky then
                currentSkyboxAsset, currentCustomSkybox = asset, name
                for _, side in ipairs({"Bk","Dn","Ft","Lf","Rt","Up"}) do customSky["Skybox"..side] = asset end
            end
        end
    end)
end

-- Color update functions
local function updateLasers(color)
    savedLaserColor = color
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end
    for _, plot in pairs(plots:GetChildren()) do
        local laser = plot:FindFirstChild("Laser")
        if laser then for _, p in pairs(laser:GetDescendants()) do if p:IsA("BasePart") then p.Color = color end end end
    end
end

local function updateGround(color)
    savedGroundColor = color
    local map = workspace:FindFirstChild("Map")
    if not map then return end
    for _, name in ipairs({"Ground_Left", "Ground_Right"}) do
        local g = map:FindFirstChild(name)
        if g and g:IsA("BasePart") then g.Color = color end
    end
end

local function updateAllColors()
    local color = HSVtoRGB(currentHue, currentSat, currentVal)
    lightingValues.Ambient = color
    lightingValues.OutdoorAmbient = Color3.new(color.R * 0.5, color.G * 0.5, color.B * 0.5)
    lightingValues.ColorShift_Top = color
    lightingValues.ColorShift_Bottom = Color3.new(color.R * 0.3, color.G * 0.3, color.B * 0.3)
    applyLighting()
    if atm then atm.Color, atm.Decay = color, color end
    if not currentCustomSkybox then currentSkyboxAsset = BLACK_TEX end
    updateLasers(color)
    updateGround(color)
    return color
end

-- GUI Creation
-- ЗАЩИТА: Используем gethui() или CoreGui с рандомным именем
local gui = createInstance("ScreenGui", { Name = generateRandomName(), ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, protectedGuiContainer)
gui:SetAttribute("_isAmbientGui", true) -- для идентификации

-- Moon button
local moonBtn = createInstance("ImageButton", {
    Name = generateRandomName(), Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -50, 0, 10),
    BackgroundColor3 = Color3.fromRGB(30, 30, 40), Image = "rbxassetid://6031094678", ImageColor3 = Color3.fromRGB(200, 200, 255)
}, gui)
createInstance("UICorner", { CornerRadius = UDim.new(0.5, 0) }, moonBtn)

-- Main panel
local panel = createInstance("Frame", {
    Name = generateRandomName(), Size = UDim2.new(0, 320, 0, 480), Position = config.guiPosition,
    BackgroundColor3 = Color3.fromRGB(25, 25, 35), Visible = false, Active = true
}, gui)
createInstance("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
createInstance("UIStroke", { Color = Color3.fromRGB(100, 80, 150), Thickness = 2 }, panel)

-- Title bar
local titleBar = createInstance("Frame", { Name = "TitleBar", Size = UDim2.new(1, 0, 0, 35), BackgroundColor3 = Color3.fromRGB(40, 35, 60) }, panel)
createInstance("UICorner", { CornerRadius = UDim.new(0, 8) }, titleBar)
createInstance("TextLabel", { Size = UDim2.new(1, -40, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1, Text = "🌙 Skybox Settings", TextColor3 = Color3.fromRGB(220, 220, 255), TextSize = 16, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, titleBar)

local closeBtn = createInstance("TextButton", { Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(1, -35, 0, 2.5), BackgroundColor3 = Color3.fromRGB(60, 50, 80), Text = "×", TextColor3 = Color3.new(1,1,1), TextSize = 20, Font = Enum.Font.GothamBold }, titleBar)
createInstance("UICorner", { CornerRadius = UDim.new(0.3, 0) }, closeBtn)

-- Content area
local content = createInstance("Frame", { Size = UDim2.new(1, -20, 1, -45), Position = UDim2.new(0, 10, 0, 40), BackgroundTransparency = 1 }, panel)

-- Brightness
local initPct = math.sqrt(clamp((config.brightness - 0.01) / 4.99, 0, 1))
local brightnessLbl = createInstance("TextLabel", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = "Brightness: " .. math.floor(initPct * 100) .. "%", TextColor3 = Color3.fromRGB(200, 200, 220), TextSize = 14, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, content)

local brightnessSlider = createInstance("Frame", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0, 25), BackgroundColor3 = Color3.fromRGB(50, 50, 70) }, content)
createInstance("UICorner", { CornerRadius = UDim.new(0.5, 0) }, brightnessSlider)
local brightnessHandle = createInstance("Frame", { Size = UDim2.new(0, 16, 0, 20), Position = UDim2.new(initPct, -8, 0.5, -10), BackgroundColor3 = Color3.fromRGB(150, 120, 200) }, brightnessSlider)
createInstance("UICorner", { CornerRadius = UDim.new(0.3, 0) }, brightnessHandle)

-- Color picker label
createInstance("TextLabel", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 50), BackgroundTransparency = 1, Text = "Color Picker", TextColor3 = Color3.fromRGB(200, 200, 220), TextSize = 14, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, content)

-- Color canvas
local colorCanvas = createInstance("ImageButton", { Size = UDim2.new(1, -30, 0, 180), Position = UDim2.new(0, 0, 0, 75), BackgroundColor3 = HSVtoRGB(currentHue, 1, 1), AutoButtonColor = false }, content)
createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, colorCanvas)

local whiteGrad = createInstance("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1) }, colorCanvas)
createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, whiteGrad)
createInstance("UIGradient", { Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)}) }, whiteGrad)

local blackGrad = createInstance("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0) }, colorCanvas)
createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, blackGrad)
createInstance("UIGradient", { Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)}), Rotation = 90 }, blackGrad)

local canvasCursor = createInstance("Frame", { Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(currentSat, -6, 1 - currentVal, -6), BackgroundTransparency = 1, ZIndex = 10 }, colorCanvas)
local cursorCircle = createInstance("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 3, BorderColor3 = Color3.new(1,1,1) }, canvasCursor)
createInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, cursorCircle)
createInstance("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1 }, cursorCircle)

-- Hue slider
local hueSlider = createInstance("ImageButton", { Size = UDim2.new(0, 20, 0, 180), Position = UDim2.new(1, -20, 0, 75), BackgroundColor3 = Color3.new(1,1,1), AutoButtonColor = false }, content)
createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, hueSlider)
createInstance("UIGradient", { Rotation = 90, Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)), ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
    ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)), ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
}) }, hueSlider)

local hueCursor = createInstance("Frame", { Size = UDim2.new(1, 4, 0, 4), Position = UDim2.new(0, -2, currentHue, -2), BackgroundColor3 = Color3.new(1,1,1), ZIndex = 10 }, hueSlider)
createInstance("UICorner", { CornerRadius = UDim.new(0.5, 0) }, hueCursor)
createInstance("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, hueCursor)

-- Color preview
local colorPreview = createInstance("Frame", { Size = UDim2.new(1, 0, 0, 35), Position = UDim2.new(0, 0, 0, 265), BackgroundColor3 = config.skyboxColor }, content)
createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, colorPreview)
createInstance("UIStroke", { Color = Color3.fromRGB(100, 100, 120), Thickness = 1 }, colorPreview)
local rgbLabel = createInstance("TextLabel", { Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 5, 0, 0), BackgroundTransparency = 1, Text = string.format("RGB(%d, %d, %d)", config.skyboxColor.R * 255, config.skyboxColor.G * 255, config.skyboxColor.B * 255), TextColor3 = Color3.new(1,1,1), TextSize = 13, Font = Enum.Font.GothamMedium }, colorPreview)

-- Skybox dropdown
createInstance("TextLabel", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 310), BackgroundTransparency = 1, Text = "Custom Skybox", TextColor3 = Color3.fromRGB(200, 200, 220), TextSize = 14, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, content)

local dropdown = createInstance("Frame", { Size = UDim2.new(1, -40, 0, 35), Position = UDim2.new(0, 0, 0, 335), BackgroundColor3 = Color3.fromRGB(40, 40, 55) }, content)
createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, dropdown)
createInstance("UIStroke", { Color = Color3.fromRGB(80, 80, 100), Thickness = 1 }, dropdown)

local selectedLbl = createInstance("TextLabel", { Size = UDim2.new(1, -35, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1, Text = config.customSkybox or "Default (Black)", TextColor3 = Color3.fromRGB(220, 220, 240), TextSize = 13, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, dropdown)
local dropArrow = createInstance("TextLabel", { Size = UDim2.new(0, 25, 1, 0), Position = UDim2.new(1, -30, 0, 0), BackgroundTransparency = 1, Text = "▼", TextColor3 = Color3.fromRGB(180, 180, 200), TextSize = 12, Font = Enum.Font.GothamBold }, dropdown)
local dropBtn = createInstance("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "" }, dropdown)

local refreshBtn = createInstance("TextButton", { Size = UDim2.new(0, 35, 0, 35), Position = UDim2.new(1, -35, 0, 335), BackgroundColor3 = Color3.fromRGB(60, 50, 90), Text = "🔄", TextColor3 = Color3.fromRGB(220, 220, 240), TextSize = 16, Font = Enum.Font.GothamBold }, content)
createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, refreshBtn)

local dropMenu = createInstance("Frame", { Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 1, 5), BackgroundColor3 = Color3.fromRGB(35, 35, 50), ClipsDescendants = true, Visible = false, ZIndex = 100 }, dropdown)
createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, dropMenu)
createInstance("UIStroke", { Color = Color3.fromRGB(80, 80, 100), Thickness = 1 }, dropMenu)
createInstance("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, dropMenu)
createInstance("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, dropMenu)

local isDropOpen = false

local function refreshDropdown()
    for _, c in pairs(dropMenu:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
    local list = getSkyboxList()
    for i, name in ipairs(list) do
        local item = createInstance("TextButton", { Size = UDim2.new(1, -10, 0, 28), BackgroundColor3 = Color3.fromRGB(50, 50, 70), Text = name, TextColor3 = Color3.fromRGB(220, 220, 240), TextSize = 12, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = i, ZIndex = 101 }, dropMenu)
        createInstance("UICorner", { CornerRadius = UDim.new(0, 4) }, item)
        createInstance("UIPadding", { PaddingLeft = UDim.new(0, 8) }, item)
        item.MouseEnter:Connect(function() item.BackgroundColor3 = Color3.fromRGB(70, 60, 100) end)
        item.MouseLeave:Connect(function() item.BackgroundColor3 = Color3.fromRGB(50, 50, 70) end)
        item.MouseButton1Click:Connect(function()
            selectedLbl.Text = name
            applyCustomSkybox(name)
            currentCustomSkybox = name ~= "Default (Black)" and name or nil
            isDropOpen = false
            dropMenu.Visible = false
            dropArrow.Text = "▼"
            saveConfig(lightingValues.Brightness, colorPreview.BackgroundColor3, panel.Position, currentCustomSkybox)
        end)
    end
    dropMenu.Size = UDim2.new(1, 0, 0, math.min(#list * 30 + 10, 150))
end

dropBtn.MouseButton1Click:Connect(function()
    isDropOpen = not isDropOpen
    if isDropOpen then refreshDropdown() end
    dropMenu.Visible = isDropOpen
    dropArrow.Text = isDropOpen and "▲" or "▼"
end)
refreshBtn.MouseButton1Click:Connect(refreshDropdown)

-- GUI logic
local function togglePanel()
    panel.Visible = not panel.Visible
    moonBtn.Visible = not panel.Visible
    if not panel.Visible then saveConfig(lightingValues.Brightness, colorPreview.BackgroundColor3, panel.Position, currentCustomSkybox) end
end
moonBtn.MouseButton1Click:Connect(togglePanel)
closeBtn.MouseButton1Click:Connect(togglePanel)

-- Dragging
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isDragging.panel = true
        dragStart, startPos = input.Position, panel.Position
    end
end)

local function updateBrightness(input)
    local pct = clamp((input.Position.X - brightnessSlider.AbsolutePosition.X) / brightnessSlider.AbsoluteSize.X, 0, 1)
    local brightness = 0.01 + pct * pct * 4.99
    brightnessHandle.Position = UDim2.new(pct, -8, 0.5, -10)
    brightnessLbl.Text = "Brightness: " .. math.floor(pct * 100) .. "%"
    lightingValues.Brightness = brightness
    Lighting.Brightness = brightness
    saveConfig(brightness, colorPreview.BackgroundColor3, panel.Position, currentCustomSkybox)
end

local function updateHue(input)
    local pct = clamp((input.Position.Y - hueSlider.AbsolutePosition.Y) / hueSlider.AbsoluteSize.Y, 0, 1)
    currentHue = pct
    hueCursor.Position = UDim2.new(0, -2, pct, -2)
    colorCanvas.BackgroundColor3 = HSVtoRGB(currentHue, 1, 1)
    local color = updateAllColors()
    colorPreview.BackgroundColor3 = color
    rgbLabel.Text = string.format("RGB(%d, %d, %d)", color.R * 255, color.G * 255, color.B * 255)
    saveConfig(lightingValues.Brightness, color, panel.Position, currentCustomSkybox)
end

local function updateCanvas(input)
    local sx, sy = colorCanvas.AbsoluteSize.X, colorCanvas.AbsoluteSize.Y
    currentSat = clamp((input.Position.X - colorCanvas.AbsolutePosition.X) / sx, 0, 1)
    currentVal = 1 - clamp((input.Position.Y - colorCanvas.AbsolutePosition.Y) / sy, 0, 1)
    canvasCursor.Position = UDim2.new(currentSat, -6, 1 - currentVal, -6)
    local color = updateAllColors()
    colorPreview.BackgroundColor3 = color
    rgbLabel.Text = string.format("RGB(%d, %d, %d)", color.R * 255, color.G * 255, color.B * 255)
    saveConfig(lightingValues.Brightness, color, panel.Position, currentCustomSkybox)
end

brightnessSlider.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then isDragging.brightness = true updateBrightness(input) end end)
hueSlider.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then isDragging.hue = true updateHue(input) end end)
colorCanvas.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then isDragging.canvas = true updateCanvas(input) end end)

UIS.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if isDragging.brightness then updateBrightness(input)
        elseif isDragging.hue then updateHue(input)
        elseif isDragging.canvas then updateCanvas(input)
        elseif isDragging.panel and dragStart then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if isDragging.panel then saveConfig(lightingValues.Brightness, colorPreview.BackgroundColor3, panel.Position, currentCustomSkybox) end
        isDragging.brightness, isDragging.hue, isDragging.canvas, isDragging.panel = false, false, false, false
    end
end)

-- Monitoring & enforcement
Lighting.ChildAdded:Connect(function(c) if c:IsA("Sky") and c ~= customSky then task.defer(function() if c.Parent then c:Destroy() end enforceSkybox() end) end end)
Lighting.ChildRemoved:Connect(function(c) if c == customSky then task.defer(enforceSkybox) end end)
Lighting.Changed:Connect(function(prop) if lightingValues[prop] ~= nil then task.defer(function() Lighting[prop] = lightingValues[prop] end) end end)

-- Event attribute blocking
for _, attr in ipairs({"BloodmoonEvent","CandyEvent","GalaxyEvent","YinYangEvent","RadioactiveEvent","UFOEvent","StrawberryEvent","WitchingHourEvent","TrickOrTreatEvent","GraveyardEvent","Effect_Space","NyanCatsEvent","4thOfJulyEvent","10BVisitsEvent","GlitchEvent","MoltenEvent","BombardiroCrocodiloEvent","Starfall","LosMatteosEventNightTime","SammyniSpyderiniEvent","MeowlEvent","ChicleteiraBicicleteiraEvent","WaterEvent","CrabRave","ConcertEvent","RapConcertEvent","BrazilEvent"}) do
    pcall(function() RS:GetAttributeChangedSignal(attr):Connect(function() task.defer(enforceSkybox) task.defer(applyLighting) end) end)
end

-- Heartbeat enforcement (throttled)
local lastEnforce = 0
RunService.Heartbeat:Connect(function()
    local now = tick()
    if Lighting.ClockTime ~= 12 then Lighting.ClockTime = 12 end
    if Lighting.GeographicLatitude ~= 0 then Lighting.GeographicLatitude = 0 end
    if now - lastEnforce >= ENFORCE_INTERVAL then
        lastEnforce = now
        applyLighting()
        enforceSkybox()
        if savedLaserColor then updateLasers(savedLaserColor) end
        if savedGroundColor then updateGround(savedGroundColor) end
    end
end)

-- Monitor new plots
local plots = workspace:FindFirstChild("Plots")
if plots then
    plots.ChildAdded:Connect(function() task.wait(0.5) if savedLaserColor then updateLasers(savedLaserColor) end if savedGroundColor then updateGround(savedGroundColor) end end)
end

-- Initial apply
task.spawn(function()
    task.wait(1)
    if config.customSkybox then applyCustomSkybox(config.customSkybox) end
    updateLasers(config.skyboxColor)
    updateGround(config.skyboxColor)
end)

player.CharacterAdded:Connect(function() task.wait(0.5) enforceSkybox() applyLighting() end)
