--[[
    AUTOSTEAL OPTIMIZED v3.0
    Компактная оптимизированная версия с встроенной защитой
    Полный функционал: ESP, Auto Steal, Thief Tracking, Base Highlights
    [PROTECTED] - Использует gethui() для обхода античита
]]

-- ============== SERVICES ==============
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do task.wait(0.1); LocalPlayer = Players.LocalPlayer end

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
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
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

-- Защищённый контейнер для GUI
local ProtectedGuiContainer = getProtectedGui()

-- ============== CONFIG ==============
local CONFIG_FILE = "autosteal_config.json"
local FRIEND_LIST_FILE = "killaura_friendlist.txt"

local DEFAULT_CONFIG = {
    -- Core settings
    AUTO_STEAL_ENABLED = true,
    ESP_ENABLED = true,
    THIEF_ESP_ENABLED = true,
    MY_BASE_THIEF_ESP = true,
    STOLEN_PODIUM_ESP = true,
    BASE_HIGHLIGHTS = true,
    SKIP_FRIENDS = true,
    -- Values
    MIN_VALUE = 0,
    MAX_STEAL_DISTANCE = 10,
    UPDATE_INTERVAL = 0.1,
    STEAL_COOLDOWN = 0.5,
    THIEF_SEARCH_INTERVAL = 0.3,
    MY_BASE_THIEF_INTERVAL = 0.15,
    BASE_TRANSPARENCY = 0.7,
    -- GUI
    GUI_POSITION_X = 100,
    GUI_POSITION_Y = 100,
    GUI_MINIMIZED = false,
    TOGGLE_KEY = Enum.KeyCode.RightShift,
    -- Colors
    MY_BASE_COLOR = Color3.fromRGB(0, 150, 255),
    FRIEND_BASE_COLOR = Color3.fromRGB(0, 200, 100),
    OTHER_BASE_COLOR = Color3.fromRGB(200, 100, 100),
}

local CONFIG = {}
for k, v in pairs(DEFAULT_CONFIG) do CONFIG[k] = v end

local function saveConfig()
    pcall(function()
        local data = {}
        for k, v in pairs(CONFIG) do
            if type(v) ~= "function" and type(v) ~= "userdata" then
                if typeof(v) == "UDim2" then
                    data[k] = {X = v.X.Offset, Y = v.Y.Offset, type = "UDim2"}
                elseif typeof(v) == "Color3" then
                    data[k] = {R = v.R, G = v.G, B = v.B, type = "Color3"}
                elseif typeof(v) == "EnumItem" then
                    data[k] = {Name = v.Name, type = "KeyCode"}
                else
                    data[k] = v
                end
            end
        end
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadConfig()
    pcall(function()
        if isfile and readfile and isfile(CONFIG_FILE) then
            local saved = HttpService:JSONDecode(readfile(CONFIG_FILE))
            for k, v in pairs(saved) do
                if CONFIG[k] ~= nil then
                    if type(v) == "table" and v.type then
                        if v.type == "UDim2" then
                            CONFIG[k] = UDim2.new(0, v.X, 0, v.Y)
                        elseif v.type == "Color3" then
                            CONFIG[k] = Color3.new(v.R, v.G, v.B)
                        elseif v.type == "KeyCode" then
                            CONFIG[k] = Enum.KeyCode[v.Name]
                        end
                    else
                        CONFIG[k] = v
                    end
                end
            end
        end
    end)
    CONFIG.ESP_COLOR = Color3.fromRGB(255, 0, 0)
    CONFIG.ESP_COLOR_IN_RANGE = Color3.fromRGB(0, 255, 0)
end
loadConfig()

-- ============== FRIEND LIST ==============
local friendList = {}

local function loadFriends()
    pcall(function()
        if isfile and readfile and isfile(FRIEND_LIST_FILE) then
            local loaded = HttpService:JSONDecode(readfile(FRIEND_LIST_FILE))
            if type(loaded) == "table" then friendList = loaded end
        end
    end)
end
loadFriends()

local function IsInFriendList(player)
    if not player then return false end
    return friendList[tostring(player.UserId)] ~= nil or friendList[player.Name] ~= nil
end

-- ============== SYNCHRONIZER PATCH ==============
pcall(function()
    local SyncModule = ReplicatedStorage:WaitForChild("Packages", 10):WaitForChild("Synchronizer", 10)
    if SyncModule then
        local Sync = require(SyncModule)
        local empty = function() end
        for _, fn in ipairs({Sync.Get, Sync.Wait}) do
            for i, v in pairs(debug.getupvalues(fn)) do
                if type(v) == "function" then debug.setupvalue(fn, i, empty) end
            end
        end
    end
end)

-- ============== DEPENDENCIES ==============
local Shared = ReplicatedStorage:WaitForChild("Shared", 30)
local Packages = ReplicatedStorage:WaitForChild("Packages", 30)
local PlotsFolder = Workspace:WaitForChild("Plots", 30)

local AnimalsShared = nil
pcall(function() AnimalsShared = require(Shared:WaitForChild("Animals")) end)

-- ============== ИНТЕГРАЦИЯ С ЗАЩИТОЙ ==============
_G.AutoStealEnabled = CONFIG.AUTO_STEAL_ENABLED
local protectionWaitStart = tick()
while not _G.ProtectionReady and tick() - protectionWaitStart < 5 do task.wait(0.1) end

-- Protection functions (inline to save local slots)
local setProtectionTarget = function(bd) if _G.Protection and _G.Protection.setTarget then _G.Protection.setTarget(bd.name) end end
local clearProtectionTarget = function() if _G.Protection and _G.Protection.clearTarget then _G.Protection.clearTarget() end end
local canStealBrainrot = function(n) if _G.Protection and _G.Protection.canSteal then return _G.Protection.canSteal(n) end; return true end

-- ============== PRICE MULTIPLIERS ==============
local PRICE_MULTIPLIERS = {
    [""] = 1, ["K"] = 1e3, ["M"] = 1e6, ["B"] = 1e9, ["T"] = 1e12,
    ["QA"] = 1e15, ["QI"] = 1e18, ["SX"] = 1e21, ["SP"] = 1e24, ["OC"] = 1e27,
    ["NO"] = 1e30, ["DC"] = 1e33, ["UD"] = 1e36, ["DD"] = 1e39, ["TD"] = 1e42,
    ["QAD"] = 1e45, ["QID"] = 1e48, ["SXD"] = 1e51, ["SPD"] = 1e54, ["OCD"] = 1e57,
    ["NOD"] = 1e60, ["VG"] = 1e63, ["UVG"] = 1e66, ["DVG"] = 1e69, ["TVG"] = 1e72
}

local function parsePrice(str)
    local clean = tostring(str or ""):gsub("[$,]", ""):gsub("/s", "")
    local num, unit = clean:match("([%d%.]+)%s*([A-Za-z]*)")
    if not num then return 0 end
    return (tonumber(num) or 0) * (PRICE_MULTIPLIERS[string.upper(unit or "")] or 1)
end

local function formatNumber(n)
    if n >= 1e15 then return string.format("%.1fQa", n/1e15)
    elseif n >= 1e12 then return string.format("%.1fT", n/1e12)
    elseif n >= 1e9 then return string.format("%.1fB", n/1e9)
    elseif n >= 1e6 then return string.format("%.1fM", n/1e6)
    elseif n >= 1e3 then return string.format("%.1fK", n/1e3)
    else return tostring(math.floor(n)) end
end

-- ============== MUTATION & TRAIT MODIFIERS ==============
local MUTATION_MODS = {
    ["Gold"] = 0.25, ["Diamond"] = 0.5, ["Bloodrot"] = 1, ["Rainbow"] = 9,
    ["Candy"] = 3, ["Lava"] = 5, ["Galaxy"] = 6, ["Yin Yang"] = 6.5,
    ["YinYang"] = 6.5, ["Radioactive"] = 7.5,
}

local TRAIT_MODS = {
    ["Taco"] = 2, ["Nyan"] = 5, ["Galactic"] = 3, ["Fireworks"] = 5, ["Zombie"] = 4,
    ["Claws"] = 4, ["Glitched"] = 4, ["Bubblegum"] = 3, ["Fire"] = 5, ["Wet"] = 1.5,
    ["Snowy"] = 2, ["Cometstruck"] = 2.5, ["Comet-struck"] = 2.5, ["Explosive"] = 3,
    ["Disco"] = 4, ["10B"] = 3, ["Shark Fin"] = 3, ["Matteo Hat"] = 3.5, ["Brazil"] = 5,
    ["Sleepy"] = 0, ["Lightning"] = 5, ["UFO"] = 2, ["Spider"] = 3.5, ["Strawberry"] = 7,
    ["Paint"] = 5, ["Skeleton"] = 3, ["Sombrero"] = 4, ["Tie"] = 3.75, ["Witch Hat"] = 3,
    ["Indonesia"] = 4, ["Meowl"] = 6, ["RIP Gravestone"] = 3.5, ["Jackolantern Pet"] = 4.5,
    ["Santa Hat"] = 4, ["Reindeer Pet"] = 5,
}

-- ============== CALCULATE GENERATION ==============
local function calculateGeneration(model)
    if not model then return 0, nil end
    local mutation = model:GetAttribute("Mutation")
    local traitsJson = model:GetAttribute("Traits")
    local indexAttr = model:GetAttribute("Index")
    if not mutation and not traitsJson and not indexAttr then return 0, nil end
    
    local index = indexAttr or model.Name
    if not index or index == "" then return 0, nil end
    
    -- Parse traits
    local traits = nil
    if traitsJson then
        if type(traitsJson) == "string" then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(traitsJson) end)
            if ok and type(decoded) == "table" then traits = decoded
            else traits = {}; for t in traitsJson:gmatch("[^,]+") do table.insert(traits, t) end end
        elseif type(traitsJson) == "table" then traits = traitsJson end
    end
    
    -- Get base generation
    local baseGen = 10
    pcall(function()
        local datas = ReplicatedStorage:FindFirstChild("Datas")
        if datas then
            local animData = require(datas:FindFirstChild("Animals"))
            if animData and animData[index] then
                baseGen = animData[index].Generation or (animData[index].Price or 0) * 0.01
            end
        end
    end)
    
    -- Apply modifiers
    local totalMod, hasSleepy = 1.0, false
    if mutation and MUTATION_MODS[mutation] then totalMod = totalMod + MUTATION_MODS[mutation] end
    if traits then
        for _, t in ipairs(traits) do
            if t == "Sleepy" then hasSleepy = true
            elseif TRAIT_MODS[t] then totalMod = totalMod + TRAIT_MODS[t] end
        end
    end
    
    local final = baseGen * totalMod
    if hasSleepy then final = final * 0.5 end
    return math.round(final), index
end

-- ============== REMOTE EVENT UUIDs ==============
-- ВАЖНО: Эти ID должны совпадать с оригинальными из autosteal.lua!
local STEAL_REMOTE_ID = "5aa39ea1-0c65-4fcf-aff9-b18a7ef277c3"
local PROMPT_REMOTE_ID = "b096e1ca-9c3a-453b-8b60-268b235083b9"
local HOLD_BEGAN_UUID_1 = "5c0bd012-dfb2-4bac-8f1a-e41f136e4744"
local HOLD_BEGAN_UUID_2 = "6be28b5b-dbc3-4aab-aa0c-6ebcfa191f22"
local STEAL_TRIGGER_UUID_1 = "c262398d-68e3-4499-8bea-99766bf11686"
local STEAL_TRIGGER_UUID_2 = "579e6c26-5a80-407d-9488-0f84752e8f1f"

-- ============== CONSTANTS ==============
local C = {
    CACHE_DURATION = 2, RAINBOW_SPEED = 0.15, BASE_BEAM_BLINK_SPEED = 3,
    THIEF_BEAM_COLOR = Color3.fromRGB(255, 140, 0),
    MY_BASE_THIEF_COLOR = Color3.fromRGB(255, 50, 50),
    MY_BASE_THIEF_OUTLINE = Color3.fromRGB(200, 0, 0),
    MY_BASE_THIEF_BEAM_COLOR = Color3.fromRGB(255, 0, 0),
    STEAL_STATE = { IDLE = "idle", CARRYING = "carrying", DELIVERED = "delivered" },
    HIGHLIGHT_COOLDOWN = 0.3,
    ESP_RANGE_CHECK_INTERVAL = 0.03, ESP_SEARCH_INTERVAL = 0.75,
}

-- State table
local S = { myPlot = nil, plotsFolder = nil, netModule = nil, time = 0, stealRemote = nil, promptRemote = nil, target = nil, lastBestName = nil, hue = 0, phase = 0, espHL = nil, espBB = nil, espBeam = nil, espA0 = nil, espA1 = nil, baseBeam = nil, baseA0 = nil, baseA1 = nil, baseVisible = false, thiefTgt = nil, thiefHL = nil, thiefBB = nil, thiefBeam = nil, thiefA0 = nil, thiefA1 = nil, myThiefTgt = nil, myThiefHL = nil, myThiefBB = nil, myThiefBeam = nil, myThiefA0 = nil, myThiefA1 = nil, stolenHL = nil, stolenBB = nil, stolenBeam = nil, stolenA0 = nil, stolenA1 = nil, stolenData = nil, distLbl = nil, nameLbl = nil, thiefNameLbl = nil, thiefStroke = nil, myThiefNameLbl = nil, myThiefStroke = nil, stolenStroke = nil, espDist = 0, espInRange = false, myHL = {}, transParts = {}, hlEnabled = true, hlTime = 0, carryState = false, procPlots = {}, connCont = {}, otherTrans = false, plotTrack = false, plotConns = {}, running = false, stealing = false, stealTime = 0, cooldown = 0.5, espCounter = 0, rainbowCounter = 0, espSearch = 0, stealState = "idle", gui = {}, screen = nil, frame = nil }

-- State aliases (consolidated)
local currentTarget, lastBestBrainrotName, rainbowHue, baseBeamPhase = nil, nil, 0, 0
local myBaseHighlights, transparentParts, basesHighlightEnabled, lastHighlightCreateTime = S.myHL, S.transParts, true, 0
local lastCarryingCheckState, processedPlots, connectedContainers, guiElements = false, S.procPlots, S.connCont, S.gui
local screenGui, mainFrame, loopRunning, isCurrentlyStealing, lastStealTime = nil, nil, false, false, 0
local espLoopCounter, rainbowLoopCounter, currentStealState, plotsTrackingConnected = 0, 0, C.STEAL_STATE.IDLE, false
local plotChildAddedConnections, otherBasesTransparencyApplied = S.plotConns, false
local ESP_RANGE_CHECK_INTERVAL = C.ESP_RANGE_CHECK_INTERVAL -- Local copy for espLoop

-- ESP objects table (consolidated to save local slots)
local ESP = { hl = nil, bb = nil, beam = nil, a0 = nil, a1 = nil, baseBeam = nil, baseA0 = nil, baseA1 = nil, baseVisible = false }
local THIEF_ESP = { target = nil, hl = nil, bb = nil, beam = nil, a0 = nil, a1 = nil }
local MY_THIEF_ESP = { target = nil, hl = nil, bb = nil, beam = nil, a0 = nil, a1 = nil }
local STOLEN_ESP = { hl = nil, bb = nil, beam = nil, a0 = nil, a1 = nil, data = nil }

-- Cached objects
local CACHE = { distLabel = nil, nameLabel = nil, myPlot = nil, plotsFolder = nil, netModule = nil, stealRemote = nil, promptRemote = nil }

-- Brainrot search cache variables  
local cachedBestBrainrot, lastBrainrotSearch = nil, 0
local cachedThief, lastThiefSearch, cachedMyBaseThief, lastMyBaseThiefSearch = nil, 0, nil, 0
local cachedEspInRange = false -- ESP in range state cache
local cachedThiefNameLabel, cachedThiefStroke = nil, nil -- Thief ESP cache

-- print("[AutoSteal] Core initialized")

-- ============== NET REMOTE FUNCTIONS ==============
local function getNetRemote(remoteName)
    if not CACHE.netModule then
        local packages = ReplicatedStorage:FindFirstChild("Packages")
        if packages then CACHE.netModule = packages:FindFirstChild("Net") end
    end
    if not CACHE.netModule then return nil end
    return CACHE.netModule:FindFirstChild("RE/" .. remoteName)
end

task.defer(function() CACHE.stealRemote = getNetRemote(STEAL_REMOTE_ID); CACHE.promptRemote = getNetRemote(PROMPT_REMOTE_ID) end)

-- ============== UTILITY FUNCTIONS TABLE ==============
local U = {}
U.getCharPos = function() local c = LocalPlayer.Character; local h = c and c:FindFirstChild("HumanoidRootPart"); return h and h.Position end
U.getDist = function(spawn) local p = U.getCharPos(); if not p or not spawn then return math.huge end; local s = spawn.Position; if spawn:IsA("Model") then local pp = spawn.PrimaryPart or spawn:FindFirstChildWhichIsA("BasePart"); if pp then s = pp.Position end end; return (p - s).Magnitude end
U.isLucky = function(obj) return obj and string.lower(obj.Name or "") == "lucky block" end
U.isFusing = function(oh) if not oh then return false end; local l = oh:FindFirstChild("Stolen"); if not l or not l:IsA("TextLabel") then return false end; local t = string.lower(l.Text or ""); return l.Visible and (t == "fusing" or t == "crafting" or t == "in machine" or t == "in fuse") end
U.isCarrying = function()
    if LocalPlayer:GetAttribute("Stealing") == true then return true end
    local char, hrp = LocalPlayer.Character, nil
    if char then hrp = char:FindFirstChild("HumanoidRootPart") end
    if not hrp then return false end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= char then
            local ccw = obj:FindFirstChild("CreateClientWeld")
            if ccw and ccw:IsA("ObjectValue") and ccw.Value == hrp then return true end
            local rp = obj:FindFirstChild("RootPart")
            if rp then local w = rp:FindFirstChild("WeldConstraint"); if w and w.Part0 == hrp then return true end end
        end
    end
    return false
end
U.isCarryingAdv = function()
    if LocalPlayer:GetAttribute("Stealing") == true then return true end
    local char = LocalPlayer.Character; if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return false end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= char then
            local ccw = obj:FindFirstChild("CreateClientWeld")
            if ccw and ccw:IsA("ObjectValue") and ccw.Value == hrp then return true end
        end
    end
    local rma = workspace:FindFirstChild("RenderedMovingAnimals")
    if rma then for _, obj in ipairs(rma:GetChildren()) do if obj:IsA("Model") then local pp = obj.PrimaryPart; if pp then local wc = pp:FindFirstChild("WeldConstraint"); if wc and wc.Part1 == hrp then return true end end end end end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= char then local rp = obj:FindFirstChild("RootPart"); if rp then local wc = rp:FindFirstChild("WeldConstraint"); if wc and (wc.Part0 == hrp or wc.Part1 == hrp) then return true end end end
    end
    return false
end
U.getStealStatus = function() if U.isCarryingAdv() then return C.STEAL_STATE.CARRYING end; return C.STEAL_STATE.IDLE end

-- Aliases for backward compatibility
local getCharacterPosition, getDistanceToSpawn, isLuckyBlock, isAnimalFusing = U.getCharPos, U.getDist, U.isLucky, U.isFusing
local isCarryingBrainrot, isCarryingBrainrotAdvanced, getStealStatus = U.isCarrying, U.isCarryingAdv, U.getStealStatus
local BRAINROT_CACHE_TIME = 0.5 -- Cache brainrot search for 0.5 sec (like original)
local THIEF_CACHE_TIME, MY_BASE_THIEF_CACHE_TIME = C.CACHE_DURATION, C.CACHE_DURATION
local cacheTime, CACHE_DURATION = 0, C.CACHE_DURATION

-- ============== FIND PLAYER PLOT ==============
local function findPlayerPlot()
    if CACHE.myPlot and (tick() - cacheTime) < CACHE_DURATION then return CACHE.myPlot end
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    CACHE.plotsFolder = plotsFolder
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local sign = plot:FindFirstChild("PlotSign")
        if not sign then continue end
        local gui = sign:FindFirstChild("SurfaceGui")
        if not gui then continue end
        local frame = gui:FindFirstChild("Frame")
        if not frame then continue end
        local lbl = frame:FindFirstChildOfClass("TextLabel")
        if not lbl or type(lbl.Text) ~= "string" then continue end
        if lbl.Text:find(LocalPlayer.DisplayName, 1, true) or lbl.Text:find(LocalPlayer.Name, 1, true) then
            CACHE.myPlot, cacheTime = plot, tick()
            return plot
        end
    end
    return nil
end

local function getMyDeliveryHitbox()
    local plot = findPlayerPlot()
    if not plot then return nil end
    local dh = plot:FindFirstChild("DeliveryHitbox")
    if dh then return dh end
    for _, c in ipairs(plot:GetChildren()) do
        if c.Name == "DeliveryHitbox" and c:IsA("BasePart") then return c end
    end
    return nil
end

-- ============== PART OF SLOT ==============
local function getPartOfSlot(plot, slotIdx)
    if not plot or not slotIdx then return nil, nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil, nil end
    local slot = podiums:FindFirstChild(tostring(slotIdx))
    if not slot then return nil, nil end
    local base = slot:FindFirstChild("Base")
    if base then
        if base:IsA("BasePart") then return base, slot end
        if base:IsA("Model") then
            local spawn = base:FindFirstChild("Spawn")
            if spawn and spawn:IsA("BasePart") then return spawn, slot end
            local p = base:FindFirstChildWhichIsA("BasePart", true)
            if p then return p, slot end
        end
    end
    return slot:FindFirstChildWhichIsA("BasePart", true), slot
end

-- ============== FIND BRAINROT MODEL ON PODIUM ==============
local function findBrainrotModelOnPodium(plot, slotIdx, brainrotName)
    if not plot then return nil end
    local spawn, _ = getPartOfSlot(plot, slotIdx)
    if spawn then
        local closest, closestDist = nil, 15
        for _, c in ipairs(plot:GetChildren()) do
            if c:IsA("Model") and c.Name ~= "AnimalPodiums" and c.Name ~= "PlotSign" and 
               c.Name ~= "Building" and c.Name ~= "Decorations" and c.Name ~= "Decoration" then
                if c:GetAttribute("Mutation") or c:GetAttribute("Traits") or c:GetAttribute("Index") then
                    local mp = c.PrimaryPart or c:FindFirstChild("RootPart") or c:FindFirstChildWhichIsA("BasePart")
                    if mp then
                        local d = (mp.Position - spawn.Position).Magnitude
                        if d < closestDist then
                            if brainrotName then
                                local idx = c:GetAttribute("Index") or c.Name
                                if idx == brainrotName then closest, closestDist = c, d end
                            else closest, closestDist = c, d end
                        end
                    end
                end
            end
        end
        if closest then return closest end
    end
    if brainrotName then
        local m = plot:FindFirstChild(brainrotName)
        if m and m:IsA("Model") then return m end
    end
    return nil
end

-- ============== FIND BEST BRAINROT (MAIN FUNCTION) ==============
local function findBestBrainrot(forceRefresh)
    local now = tick()
    if not forceRefresh and cachedBestBrainrot and (now - lastBrainrotSearch) < BRAINROT_CACHE_TIME then
        if (cachedBestBrainrot.model and cachedBestBrainrot.model.Parent) or
           (cachedBestBrainrot.spawn and cachedBestBrainrot.spawn.Parent and 
            cachedBestBrainrot.podium and cachedBestBrainrot.podium.Parent) then
            return cachedBestBrainrot
        end
    end
    
    local myPlot = findPlayerPlot()
    local plotsFolder = CACHE.plotsFolder or workspace:FindFirstChild("Plots")
    if not plotsFolder then cachedBestBrainrot = nil; return nil end
    
    local bestBrainrot, bestValue = nil, CONFIG.MIN_VALUE
    
    -- Manual search
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot == myPlot then continue end
        
        -- Search models in plot
        for _, child in ipairs(plot:GetChildren()) do
            if child.Name == "AnimalPodiums" or child.Name == "PlotSign" or 
               child.Name == "Building" or child.Name == "Decorations" then continue end
            if not child:IsA("Model") then continue end
            
            local ccw = child:FindFirstChild("CreateClientWeld")
            if ccw then continue end
            local rp = child:FindFirstChild("RootPart")
            if rp then
                local wc = rp:FindFirstChild("WeldConstraint")
                if wc and wc.Part0 and wc.Part0.Name == "HumanoidRootPart" then continue end
            end
            
            if child:GetAttribute("Mutation") or child:GetAttribute("Traits") or child:GetAttribute("Index") then
                local gen, name = calculateGeneration(child)
                if gen > bestValue then
                    local mp = child.PrimaryPart or child:FindFirstChild("RootPart") or child:FindFirstChildWhichIsA("BasePart")
                    local foundPodium, foundSpawn = nil, nil
                    local ap = plot:FindFirstChild("AnimalPodiums")
                    if ap and mp then
                        local cd = 15
                        for _, pod in ipairs(ap:GetChildren()) do
                            local base = pod:FindFirstChild("Base")
                            if base then
                                local sp = base:FindFirstChild("Spawn")
                                if sp then
                                    local d = (sp.Position - mp.Position).Magnitude
                                    if d < cd then cd, foundPodium, foundSpawn = d, pod, sp end
                                end
                            end
                        end
                    end
                    bestValue = gen
                    bestBrainrot = {
                        name = name or child.Name, value = gen, text = formatNumber(gen) .. "/s",
                        plot = plot, podium = foundPodium, spawn = foundSpawn, prompt = nil,
                        podiumIndex = foundPodium and foundPodium.Name, model = child, overhead = nil,
                        promptAttachment = foundSpawn and foundSpawn:FindFirstChild("PromptAttachment"),
                        isLuckyBlock = isLuckyBlock(foundPodium)
                    }
                end
            end
        end
        
        -- Search in AnimalPodiums
        local ap = plot:FindFirstChild("AnimalPodiums")
        if not ap then continue end
        for _, podium in ipairs(ap:GetChildren()) do
            local base = podium:FindFirstChild("Base")
            if not base then continue end
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            
            -- Find server model on this podium
            local serverModel = nil
            local cd = 15
            for _, c in ipairs(plot:GetChildren()) do
                if c:IsA("Model") and c.Name ~= "AnimalPodiums" and c.Name ~= "PlotSign" then
                    if c:GetAttribute("Mutation") or c:GetAttribute("Traits") or c:GetAttribute("Index") then
                        local sp = c.PrimaryPart or c:FindFirstChild("RootPart")
                        if sp then
                            local d = (sp.Position - spawn.Position).Magnitude
                            if d < cd then cd, serverModel = d, c end
                        end
                    end
                end
            end
            
            if serverModel then
                local ccw = serverModel:FindFirstChild("CreateClientWeld")
                if ccw and ccw:IsA("ObjectValue") and ccw.Value then continue end
                
                local gen, name = calculateGeneration(serverModel)
                if gen > bestValue then
                    bestValue = gen
                    bestBrainrot = {
                        name = name or serverModel.Name, value = gen, text = formatNumber(gen) .. "/s",
                        plot = plot, podium = podium, spawn = spawn, prompt = nil,
                        podiumIndex = podium.Name, model = serverModel, overhead = nil,
                        promptAttachment = spawn:FindFirstChild("PromptAttachment"),
                        isLuckyBlock = isLuckyBlock(podium)
                    }
                end
            end
        end
    end
    
    cachedBestBrainrot, lastBrainrotSearch = bestBrainrot, now
    return bestBrainrot
end

-- print("[AutoSteal] Search functions loaded")

-- ============== FIND BEST STOLEN BRAINROT NAME ==============
local function findBestStolenBrainrotName()
    local myPlot = findPlayerPlot()
    local plotsFolder = CACHE.plotsFolder or workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil, 0 end
    
    local bestName, bestValue = nil, 0
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot == myPlot then continue end
        local ap = plot:FindFirstChild("AnimalPodiums")
        if not ap then continue end
        
        for _, podium in ipairs(ap:GetChildren()) do
            local base = podium:FindFirstChild("Base")
            if not base then continue end
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            local pa = spawn:FindFirstChild("PromptAttachment")
            if not pa then continue end
            
            for _, desc in ipairs(pa:GetDescendants()) do
                if desc:IsA("ProximityPrompt") then
                    local state = desc:GetAttribute("State")
                    if state == "Stolen" then
                        local brainrotName = desc.ObjectText
                        if brainrotName and brainrotName ~= "" then
                            -- Try to find model and calculate generation
                            local gen = 0
                            local brainrotModel = plot:FindFirstChild(brainrotName)
                            if brainrotModel then
                                gen = calculateGeneration(brainrotModel) or 0
                            end
                            if gen > bestValue then
                                bestValue = gen
                                bestName = brainrotName
                            end
                        end
                    end
                end
            end
        end
    end
    return bestName, bestValue
end

-- ============== THIEF TRACKING FUNCTIONS ==============
local function findVisualModelForServer(serverModel)
    if not serverModel then return nil end
    local ra = workspace:FindFirstChild("RenderedMovingAnimals")
    if not ra then return nil end
    local sp = serverModel.PrimaryPart or serverModel:FindFirstChild("RootPart")
    if not sp then return nil end
    for _, r in ipairs(ra:GetChildren()) do
        if r:IsA("Model") and r.PrimaryPart then
            local w = r.PrimaryPart:FindFirstChild("WeldConstraint")
            if w and w.Part1 == sp then return r end
        end
    end
    return nil
end

local function getBrainrotIncomeFromModel(model)
    if not model then return 0, "" end
    -- Try visual model
    local vm = findVisualModelForServer(model)
    if vm then
        local oh = vm:FindFirstChild("AnimalOverhead", true)
        if oh then
            local gl = oh:FindFirstChild("Generation")
            if gl and gl:IsA("TextLabel") and gl.Text:find("/s") then
                return parsePrice(gl.Text), gl.Text
            end
        end
    end
    -- Try RootPart attachment
    local rp = model:FindFirstChild("RootPart") or model.PrimaryPart
    if rp then
        local att = rp:FindFirstChild("Attachment")
        if att then
            local oh = att:FindFirstChild("AnimalOverhead")
            if oh then
                local gl = oh:FindFirstChild("Generation")
                if gl and gl:IsA("TextLabel") and gl.Text:find("/s") then
                    return parsePrice(gl.Text), gl.Text
                end
            end
        end
    end
    -- Fallback: calculate
    local gen, _ = calculateGeneration(model)
    if gen > 0 then return gen, formatNumber(gen) .. "/s" end
    return 0, ""
end

local function findStolenBrainrotThief(forceRefresh)
    local now = tick()
    if not forceRefresh and cachedThief and (now - lastThiefSearch) < THIEF_CACHE_TIME then
        if cachedThief.brainrotModel and cachedThief.brainrotModel.Parent and
           cachedThief.player and cachedThief.player.Character then
            return cachedThief
        end
    end
    
    -- Find any carried brainrot
    local bestThief, bestVal = nil, 0
    local bestOnPodium = findBestBrainrot(true)
    local podiumVal = bestOnPodium and bestOnPodium.value or 0
    
    for _, obj in ipairs(workspace:GetChildren()) do
        if not obj:IsA("Model") or obj.Name == "RenderedMovingAnimals" or obj.Name == "Plots" then continue end
        local rp = obj:FindFirstChild("RootPart")
        if not rp then continue end
        
        local carrierHRP = nil
        local ccw = obj:FindFirstChild("CreateClientWeld")
        if ccw and ccw:IsA("ObjectValue") and ccw.Value and ccw.Value:IsA("BasePart") then
            local char = ccw.Value.Parent
            if char then carrierHRP = char:FindFirstChild("HumanoidRootPart") or (ccw.Value.Name == "HumanoidRootPart" and ccw.Value) end
        end
        if not carrierHRP then
            local wc = rp:FindFirstChild("WeldConstraint")
            if wc and wc.Part0 then carrierHRP = wc.Part0 end
        end
        
        if not carrierHRP or carrierHRP.Name ~= "HumanoidRootPart" then continue end
        local carrierChar = carrierHRP.Parent
        if not carrierChar then continue end
        local carrierPlayer = Players:GetPlayerFromCharacter(carrierChar)
        if not carrierPlayer or carrierPlayer == LocalPlayer then continue end
        
        local val, txt = getBrainrotIncomeFromModel(obj)
        local idx = obj:GetAttribute("Index") or obj.Name
        if val > 0 and val >= podiumVal and val > bestVal then
            bestVal = val
            bestThief = {
                player = carrierPlayer, character = carrierChar, hrp = carrierHRP,
                brainrotModel = obj, rootPart = rp, name = idx, value = val, text = txt
            }
        end
    end
    
    if bestThief then lastBestBrainrotName = bestThief.name end
    cachedThief, lastThiefSearch = bestThief, now
    return bestThief
end

local function findMyBaseThief(forceRefresh)
    local now = tick()
    if not forceRefresh and cachedMyBaseThief and (now - lastMyBaseThiefSearch) < MY_BASE_THIEF_CACHE_TIME then
        if cachedMyBaseThief.brainrotModel and cachedMyBaseThief.brainrotModel.Parent and
           cachedMyBaseThief.player and cachedMyBaseThief.player.Character then
            return cachedMyBaseThief
        end
    end
    
    local myPlot = findPlayerPlot()
    if not myPlot then cachedMyBaseThief = nil; lastMyBaseThiefSearch = now; return nil end
    local myPlotName = myPlot.Name
    
    for _, obj in ipairs(workspace:GetChildren()) do
        if not obj:IsA("Model") or obj.Name == "Plots" then continue end
        local rp = obj:FindFirstChild("RootPart") or obj.PrimaryPart
        if not rp then continue end
        
        local wc = rp:FindFirstChild("WeldConstraint")
        if not wc then continue end
        
        local carrierHRP = nil
        if wc.Part0 and wc.Part0.Name == "HumanoidRootPart" then carrierHRP = wc.Part0
        elseif wc.Part1 and wc.Part1.Name == "HumanoidRootPart" then carrierHRP = wc.Part1 end
        if not carrierHRP then continue end
        
        local carrierChar = carrierHRP.Parent
        if not carrierChar then continue end
        local carrierPlayer = Players:GetPlayerFromCharacter(carrierChar)
        if not carrierPlayer or carrierPlayer == LocalPlayer then continue end
        if IsInFriendList(carrierPlayer) then continue end
        
        -- Check if from my base
        local isFromMyBase = false
        local ap = myPlot:FindFirstChild("AnimalPodiums")
        if ap then
            for _, pod in ipairs(ap:GetChildren()) do
                local base = pod:FindFirstChild("Base")
                local spawn = base and (base:IsA("Model") and base:FindFirstChild("Spawn") or base)
                if spawn then
                    local pa = spawn:FindFirstChild("PromptAttachment")
                    if pa then
                        for _, desc in ipairs(pa:GetDescendants()) do
                            if desc:IsA("ProximityPrompt") and desc.ObjectText == obj.Name then
                                isFromMyBase = true; break
                            end
                        end
                    end
                end
                if isFromMyBase then break end
            end
        end
        
        if not isFromMyBase then continue end
        
        local val, txt = getBrainrotIncomeFromModel(obj)
        cachedMyBaseThief = {
            player = carrierPlayer, character = carrierChar, hrp = carrierHRP,
            brainrotModel = obj, rootPart = rp, name = obj.Name,
            value = val, text = txt, isMyBase = true
        }
        lastMyBaseThiefSearch = now
        return cachedMyBaseThief
    end
    
    cachedMyBaseThief = nil
    lastMyBaseThiefSearch = now
    return nil
end

local function findStolenPodiumByName(brainrotName)
    if not brainrotName then return nil end
    local myPlot = findPlayerPlot()
    local pf = CACHE.plotsFolder or workspace:FindFirstChild("Plots")
    if not pf then return nil end
    
    for _, plot in ipairs(pf:GetChildren()) do
        if plot == myPlot then continue end
        local ap = plot:FindFirstChild("AnimalPodiums")
        if not ap then continue end
        for _, pod in ipairs(ap:GetChildren()) do
            local base = pod:FindFirstChild("Base")
            if not base then continue end
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            local pa = spawn:FindFirstChild("PromptAttachment")
            if pa then
                for _, desc in ipairs(pa:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") and desc.ObjectText == brainrotName then
                        return {spawn = spawn, podium = pod, plot = plot, name = brainrotName}
                    end
                end
            end
        end
    end
    return nil
end

-- print("[AutoSteal] Thief tracking loaded")

-- ============== ESP CLEAR FUNCTIONS ==============
local function clearESP()
    if ESP.hl then pcall(function() ESP.hl:Destroy() end); ESP.hl = nil end
    if ESP.bb then pcall(function() ESP.bb:Destroy() end); ESP.bb = nil end
    if ESP.beam then pcall(function() ESP.beam:Destroy() end); ESP.beam = nil end
    if ESP.a0 then pcall(function() ESP.a0:Destroy() end); ESP.a0 = nil end
    if ESP.a1 then pcall(function() ESP.a1:Destroy() end); ESP.a1 = nil end
    CACHE.distLabel, CACHE.nameLabel, cachedEspInRange = nil, nil, false
end

local function clearThiefESP()
    if THIEF_ESP.hl then pcall(function() THIEF_ESP.hl:Destroy() end); THIEF_ESP.hl = nil end
    if THIEF_ESP.bb then pcall(function() THIEF_ESP.bb:Destroy() end); THIEF_ESP.bb = nil end
    if THIEF_ESP.beam then pcall(function() THIEF_ESP.beam:Destroy() end); THIEF_ESP.beam = nil end
    if THIEF_ESP.a0 then pcall(function() THIEF_ESP.a0:Destroy() end); THIEF_ESP.a0 = nil end
    if THIEF_ESP.a1 then pcall(function() THIEF_ESP.a1:Destroy() end); THIEF_ESP.a1 = nil end
    cachedThiefNameLabel, cachedThiefStroke, THIEF_ESP.target, lastBestBrainrotName = nil, nil, nil, nil
end

local function clearMyBaseThiefESP()
    if MY_THIEF_ESP.hl then pcall(function() MY_THIEF_ESP.hl:Destroy() end); MY_THIEF_ESP.hl = nil end
    if MY_THIEF_ESP.bb then pcall(function() MY_THIEF_ESP.bb:Destroy() end); MY_THIEF_ESP.bb = nil end
    if MY_THIEF_ESP.beam then pcall(function() MY_THIEF_ESP.beam:Destroy() end); MY_THIEF_ESP.beam = nil end
    if MY_THIEF_ESP.a0 then pcall(function() MY_THIEF_ESP.a0:Destroy() end); MY_THIEF_ESP.a0 = nil end
    if MY_THIEF_ESP.a1 then pcall(function() MY_THIEF_ESP.a1:Destroy() end); MY_THIEF_ESP.a1 = nil end
    cachedMyBaseThiefNameLabel, cachedMyBaseThiefStroke, MY_THIEF_ESP.target = nil, nil, nil
end

local function clearStolenPodiumESP()
    if STOLEN_ESP.hl then pcall(function() STOLEN_ESP.hl:Destroy() end); STOLEN_ESP.hl = nil end
    if STOLEN_ESP.bb then pcall(function() STOLEN_ESP.bb:Destroy() end); STOLEN_ESP.bb = nil end
    if STOLEN_ESP.beam then pcall(function() STOLEN_ESP.beam:Destroy() end); STOLEN_ESP.beam = nil end
    if STOLEN_ESP.a0 then pcall(function() STOLEN_ESP.a0:Destroy() end); STOLEN_ESP.a0 = nil end
    if STOLEN_ESP.a1 then pcall(function() STOLEN_ESP.a1:Destroy() end); STOLEN_ESP.a1 = nil end
    cachedStolenStroke, STOLEN_ESP.data = nil, nil
end

local function clearBaseBeam()
    if ESP.baseBeam then pcall(function() ESP.baseBeam:Destroy() end); ESP.baseBeam = nil end
    if ESP.baseA0 then pcall(function() ESP.baseA0:Destroy() end); ESP.baseA0 = nil end
    if ESP.baseA1 then pcall(function() ESP.baseA1:Destroy() end); ESP.baseA1 = nil end
    ESP.baseVisible = false
end

-- ============== CREATE ESP ==============
local function createESP(brainrotData)
    clearESP()
    if not brainrotData or not CONFIG.ESP_ENABLED then return end
    
    local targetPart = brainrotData.spawn
    if not targetPart and brainrotData.model then
        targetPart = brainrotData.model:FindFirstChild("RootPart") or brainrotData.model.PrimaryPart or brainrotData.model:FindFirstChildWhichIsA("BasePart")
    end
    if not targetPart then return end
    
    local distance = getDistanceToSpawn(targetPart)
    local inRange = distance <= CONFIG.MAX_STEAL_DISTANCE
    local color = inRange and CONFIG.ESP_COLOR_IN_RANGE or CONFIG.ESP_COLOR
    
    -- Highlight (ЗАЩИТА: рандомное имя + gethui)
    local highlightTarget = brainrotData.model or brainrotData.podium
    if highlightTarget then
        ESP.hl = Instance.new("Highlight")
        ESP.hl.Name = generateRandomName() -- ЗАЩИТА
        ESP.hl.Adornee = highlightTarget
        ESP.hl.FillColor, ESP.hl.OutlineColor = color, Color3.new(1,1,1)
        ESP.hl.FillTransparency, ESP.hl.OutlineTransparency = 0.5, 0
        ESP.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        ESP.hl.Parent = ProtectedGuiContainer -- ЗАЩИТА: gethui
    end
    
    -- Billboard (ЗАЩИТА: рандомное имя + gethui)
    ESP.bb = Instance.new("BillboardGui")
    ESP.bb.Name = generateRandomName() -- ЗАЩИТА
    ESP.bb.Adornee = targetPart
    ESP.bb.Size, ESP.bb.StudsOffset = UDim2.new(0, 220, 0, 90), Vector3.new(0, 8, 0)
    ESP.bb.AlwaysOnTop = true
    ESP.bb.Parent = ProtectedGuiContainer -- ЗАЩИТА: gethui
    
    local frame = Instance.new("Frame")
    frame.Name = generateRandomName() -- ЗАЩИТА
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel = Color3.new(0,0,0), 0.4, 0
    frame.Parent = ESP.bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color, stroke.Thickness, stroke.Transparency = Color3.new(1,1,1), 2, 0.5
    
    local nameLabel = Instance.new("TextLabel", frame)
    nameLabel.Name = generateRandomName() -- ЗАЩИТА
    nameLabel.Size, nameLabel.Position = UDim2.new(1, -10, 0, 30), UDim2.new(0, 5, 0, 5)
    nameLabel.BackgroundTransparency, nameLabel.Text = 1, "🎯 " .. brainrotData.name
    nameLabel.TextColor3, nameLabel.TextScaled, nameLabel.Font = Color3.fromHSV(rainbowHue, 1, 1), true, Enum.Font.GothamBold
    CACHE.nameLabel = nameLabel
    
    local valueLabel = Instance.new("TextLabel", frame)
    valueLabel.Name = generateRandomName() -- ЗАЩИТА
    valueLabel.Size, valueLabel.Position = UDim2.new(1, -10, 0, 25), UDim2.new(0, 5, 0, 35)
    valueLabel.BackgroundTransparency, valueLabel.Text = 1, "💰 " .. brainrotData.text:gsub("%$", "")
    valueLabel.TextColor3, valueLabel.TextScaled, valueLabel.Font = Color3.fromRGB(0, 255, 100), true, Enum.Font.GothamBold
    
    local distLabel = Instance.new("TextLabel", frame)
    distLabel.Name = generateRandomName() -- ЗАЩИТА
    distLabel.Size, distLabel.Position = UDim2.new(1, -10, 0, 22), UDim2.new(0, 5, 0, 62)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = string.format("📍 %.0f studs %s", distance, inRange and "[✓ В РАДИУСЕ!]" or "")
    distLabel.TextColor3, distLabel.TextScaled, distLabel.Font = inRange and Color3.new(0,1,0) or Color3.new(1,1,1), true, Enum.Font.GothamMedium
    CACHE.distLabel, cachedEspInRange = distLabel, inRange
    
    -- Beam (ЗАЩИТА: рандомные имена)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and targetPart then
        ESP.a0 = Instance.new("Attachment", hrp)
        ESP.a0.Name = generateRandomName() -- ЗАЩИТА
        ESP.a1 = Instance.new("Attachment", targetPart)
        ESP.a1.Name = generateRandomName() -- ЗАЩИТА
        ESP.a1.Position = Vector3.new(0, 2, 0)
        
        ESP.beam = Instance.new("Beam", hrp)
        ESP.beam.Name = generateRandomName() -- ЗАЩИТА
        ESP.beam.Attachment0, ESP.beam.Attachment1 = ESP.a0, ESP.a1
        ESP.beam.Color = ColorSequence.new(Color3.fromHSV(rainbowHue, 1, 1))
        ESP.beam.Transparency = NumberSequence.new(0.3)
        ESP.beam.LightEmission, ESP.beam.LightInfluence = 1, 0
        ESP.beam.Width0, ESP.beam.Width1 = 0.5, 0.3
        ESP.beam.FaceCamera, ESP.beam.Segments = true, 20
        ESP.beam.TextureLength, ESP.beam.TextureSpeed = 1, 1
    end
end

-- ============== CREATE THIEF ESP ==============
local function createThiefESP(thiefData)
    clearThiefESP()
    if not thiefData or not CONFIG.ESP_ENABLED then return end
    THIEF_ESP.target = thiefData
    
    local targetPart = thiefData.hrp or (thiefData.character and thiefData.character:FindFirstChild("HumanoidRootPart"))
    if not targetPart then return end
    local distance = getDistanceToSpawn(targetPart)
    
    -- ЗАЩИТА: рандомные имена + gethui
    if thiefData.character then
        THIEF_ESP.hl = Instance.new("Highlight")
        THIEF_ESP.hl.Name = generateRandomName() -- ЗАЩИТА
        THIEF_ESP.hl.Adornee = thiefData.character
        THIEF_ESP.hl.FillColor, THIEF_ESP.hl.OutlineColor = Color3.fromRGB(255, 140, 0), Color3.new(1, 0, 0)
        THIEF_ESP.hl.FillTransparency, THIEF_ESP.hl.OutlineTransparency = 0.6, 0
        THIEF_ESP.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        THIEF_ESP.hl.Parent = ProtectedGuiContainer -- ЗАЩИТА: gethui
    end
    
    THIEF_ESP.bb = Instance.new("BillboardGui")
    THIEF_ESP.bb.Name = generateRandomName() -- ЗАЩИТА
    THIEF_ESP.bb.Adornee = targetPart
    THIEF_ESP.bb.Size, THIEF_ESP.bb.StudsOffset = UDim2.new(0, 250, 0, 110), Vector3.new(0, 5, 0)
    THIEF_ESP.bb.AlwaysOnTop = true
    THIEF_ESP.bb.Parent = ProtectedGuiContainer -- ЗАЩИТА: gethui
    
    local frame = Instance.new("Frame", THIEF_ESP.bb)
    frame.Name = generateRandomName() -- ЗАЩИТА
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel = Color3.fromRGB(40, 20, 0), 0.3, 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color, stroke.Thickness = Color3.fromRGB(255, 0, 0), 3
    cachedThiefStroke = stroke
    
    local thiefLabel = Instance.new("TextLabel", frame)
    thiefLabel.Name = generateRandomName() -- ЗАЩИТА
    thiefLabel.Size, thiefLabel.Position = UDim2.new(1, -10, 0, 28), UDim2.new(0, 5, 0, 3)
    thiefLabel.BackgroundTransparency, thiefLabel.Text = 1, "🚨 ВОР"
    thiefLabel.TextColor3, thiefLabel.TextScaled, thiefLabel.Font = Color3.fromRGB(255, 80, 80), true, Enum.Font.GothamBold
    
    local nameLabel = Instance.new("TextLabel", frame)
    nameLabel.Name = generateRandomName() -- ЗАЩИТА
    nameLabel.Size, nameLabel.Position = UDim2.new(1, -10, 0, 26), UDim2.new(0, 5, 0, 30)
    nameLabel.BackgroundTransparency, nameLabel.Text = 1, "🎯 " .. (thiefData.name or "Unknown")
    nameLabel.TextColor3, nameLabel.TextScaled, nameLabel.Font = Color3.fromHSV(rainbowHue, 1, 1), true, Enum.Font.GothamBold
    cachedThiefNameLabel = nameLabel
    
    local incomeText = thiefData.text or (thiefData.value and "$" .. tostring(thiefData.value) .. "/s" or "")
    if incomeText ~= "" then
        local incomeLabel = Instance.new("TextLabel", frame)
        incomeLabel.Name = generateRandomName() -- ЗАЩИТА
        incomeLabel.Size, incomeLabel.Position = UDim2.new(1, -10, 0, 22), UDim2.new(0, 5, 0, 55)
        incomeLabel.BackgroundTransparency, incomeLabel.Text = 1, "💰 " .. incomeText
        incomeLabel.TextColor3, incomeLabel.TextScaled, incomeLabel.Font = Color3.fromRGB(255, 215, 0), true, Enum.Font.GothamMedium
    end
    
    local distLabel = Instance.new("TextLabel", frame)
    distLabel.Name = generateRandomName() -- ЗАЩИТА
    distLabel.Size, distLabel.Position = UDim2.new(1, -10, 0, 22), UDim2.new(0, 5, 0, 80)
    distLabel.BackgroundTransparency, distLabel.Text = 1, string.format("📍 %.0f studs", distance)
    distLabel.TextColor3, distLabel.TextScaled, distLabel.Font = Color3.new(1,1,1), true, Enum.Font.GothamMedium
    
    -- ЗАЩИТА: рандомные имена для beam
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and targetPart then
        THIEF_ESP.a0 = Instance.new("Attachment", hrp)
        THIEF_ESP.a0.Name = generateRandomName() -- ЗАЩИТА
        THIEF_ESP.a1 = Instance.new("Attachment", targetPart)
        THIEF_ESP.a1.Name = generateRandomName() -- ЗАЩИТА
        
        THIEF_ESP.beam = Instance.new("Beam", hrp)
        THIEF_ESP.beam.Name = generateRandomName() -- ЗАЩИТА
        THIEF_ESP.beam.Attachment0, THIEF_ESP.beam.Attachment1 = THIEF_ESP.a0, THIEF_ESP.a1
        THIEF_ESP.beam.Color = ColorSequence.new(C.THIEF_BEAM_COLOR)
        THIEF_ESP.beam.Transparency = NumberSequence.new(0.3)
        THIEF_ESP.beam.LightEmission, THIEF_ESP.beam.LightInfluence = 1, 0
        THIEF_ESP.beam.Width0, THIEF_ESP.beam.Width1 = 0.6, 0.4
        THIEF_ESP.beam.FaceCamera, THIEF_ESP.beam.Segments = true, 20
        THIEF_ESP.beam.TextureLength, THIEF_ESP.beam.TextureSpeed = 1, 2
    end
end

-- ============== CREATE MY BASE THIEF ESP ==============
local function createMyBaseThiefESP(thiefData)
    clearMyBaseThiefESP()
    if not thiefData or not CONFIG.ESP_ENABLED then return end
    MY_THIEF_ESP.target = thiefData
    
    local targetPart = thiefData.hrp or (thiefData.character and thiefData.character:FindFirstChild("HumanoidRootPart"))
    if not targetPart then return end
    local distance = getDistanceToSpawn(targetPart)
    
    -- ЗАЩИТА: рандомные имена + gethui
    if thiefData.character then
        MY_THIEF_ESP.hl = Instance.new("Highlight")
        MY_THIEF_ESP.hl.Name = generateRandomName() -- ЗАЩИТА
        MY_THIEF_ESP.hl.Adornee = thiefData.character
        MY_THIEF_ESP.hl.FillColor, MY_THIEF_ESP.hl.OutlineColor = C.MY_BASE_THIEF_COLOR, C.MY_BASE_THIEF_OUTLINE
        MY_THIEF_ESP.hl.FillTransparency, MY_THIEF_ESP.hl.OutlineTransparency = 0.4, 0
        MY_THIEF_ESP.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        MY_THIEF_ESP.hl.Parent = ProtectedGuiContainer -- ЗАЩИТА: gethui
    end
    
    MY_THIEF_ESP.bb = Instance.new("BillboardGui")
    MY_THIEF_ESP.bb.Name = generateRandomName() -- ЗАЩИТА
    MY_THIEF_ESP.bb.Adornee = targetPart
    MY_THIEF_ESP.bb.Size, MY_THIEF_ESP.bb.StudsOffset = UDim2.new(0, 280, 0, 130), Vector3.new(0, 6, 0)
    MY_THIEF_ESP.bb.AlwaysOnTop = true
    MY_THIEF_ESP.bb.Parent = ProtectedGuiContainer -- ЗАЩИТА: gethui
    
    local frame = Instance.new("Frame", MY_THIEF_ESP.bb)
    frame.Name, frame.Size = "Frame", UDim2.new(1, 0, 1, 0)
    frame.Name = generateRandomName() -- ЗАЩИТА
    frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel = Color3.fromRGB(60, 0, 0), 0.2, 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color, stroke.Thickness = Color3.fromRGB(255, 0, 0), 4
    cachedMyBaseThiefStroke = stroke
    
    local thiefLabel = Instance.new("TextLabel", frame)
    thiefLabel.Name = generateRandomName() -- ЗАЩИТА
    thiefLabel.Size, thiefLabel.Position = UDim2.new(1, -10, 0, 32), UDim2.new(0, 5, 0, 3)
    thiefLabel.BackgroundTransparency, thiefLabel.Text = 1, "🏠🚨 ВОР МОЕЙ БАЗЫ!"
    thiefLabel.TextColor3, thiefLabel.TextScaled, thiefLabel.Font = Color3.fromRGB(255, 50, 50), true, Enum.Font.GothamBlack
    
    local playerNameLabel = Instance.new("TextLabel", frame)
    playerNameLabel.Name = generateRandomName() -- ЗАЩИТА
    playerNameLabel.Size, playerNameLabel.Position = UDim2.new(1, -10, 0, 26), UDim2.new(0, 5, 0, 35)
    playerNameLabel.BackgroundTransparency, playerNameLabel.Text = 1, "👤 " .. (thiefData.player and thiefData.player.Name or "Unknown")
    playerNameLabel.TextColor3, playerNameLabel.TextScaled, playerNameLabel.Font = Color3.fromRGB(255, 150, 150), true, Enum.Font.GothamBold
    cachedMyBaseThiefNameLabel = playerNameLabel
    
    local brainrotLabel = Instance.new("TextLabel", frame)
    brainrotLabel.Name = generateRandomName() -- ЗАЩИТА
    brainrotLabel.Size, brainrotLabel.Position = UDim2.new(1, -10, 0, 24), UDim2.new(0, 5, 0, 60)
    brainrotLabel.BackgroundTransparency, brainrotLabel.Text = 1, "🎯 " .. (thiefData.name or "Unknown")
    brainrotLabel.TextColor3, brainrotLabel.TextScaled, brainrotLabel.Font = Color3.fromRGB(255, 200, 100), true, Enum.Font.GothamMedium
    
    local incomeText = thiefData.text or (thiefData.value and "$" .. tostring(thiefData.value) .. "/s" or "")
    if incomeText ~= "" then
        local incomeLabel = Instance.new("TextLabel", frame)
        incomeLabel.Name = generateRandomName() -- ЗАЩИТА
        incomeLabel.Size, incomeLabel.Position = UDim2.new(1, -10, 0, 22), UDim2.new(0, 5, 0, 83)
        incomeLabel.BackgroundTransparency, incomeLabel.Text = 1, "💰 " .. incomeText
        incomeLabel.TextColor3, incomeLabel.TextScaled, incomeLabel.Font = Color3.fromRGB(255, 215, 0), true, Enum.Font.GothamMedium
    end
    
    local distLabel = Instance.new("TextLabel", frame)
    distLabel.Name = generateRandomName() -- ЗАЩИТА
    distLabel.Size, distLabel.Position = UDim2.new(1, -10, 0, 22), UDim2.new(0, 5, 0, 105)
    distLabel.BackgroundTransparency, distLabel.Text = 1, string.format("📍 %.0f studs", distance)
    distLabel.TextColor3, distLabel.TextScaled, distLabel.Font = Color3.new(1,1,1), true, Enum.Font.GothamMedium
    
    -- ЗАЩИТА: рандомные имена для beam
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and targetPart then
        MY_THIEF_ESP.a0 = Instance.new("Attachment", hrp)
        MY_THIEF_ESP.a0.Name = generateRandomName() -- ЗАЩИТА
        MY_THIEF_ESP.a1 = Instance.new("Attachment", targetPart)
        MY_THIEF_ESP.a1.Name = generateRandomName() -- ЗАЩИТА
        
        MY_THIEF_ESP.beam = Instance.new("Beam", hrp)
        MY_THIEF_ESP.beam.Name = generateRandomName() -- ЗАЩИТА
        MY_THIEF_ESP.beam.Attachment0, MY_THIEF_ESP.beam.Attachment1 = MY_THIEF_ESP.a0, MY_THIEF_ESP.a1
        MY_THIEF_ESP.beam.Color = ColorSequence.new(C.MY_BASE_THIEF_BEAM_COLOR)
        MY_THIEF_ESP.beam.Transparency = NumberSequence.new(0.2)
        MY_THIEF_ESP.beam.LightEmission, MY_THIEF_ESP.beam.LightInfluence = 1, 0
        MY_THIEF_ESP.beam.Width0, MY_THIEF_ESP.beam.Width1 = 0.8, 0.5
        MY_THIEF_ESP.beam.FaceCamera, MY_THIEF_ESP.beam.Segments = true, 25
        MY_THIEF_ESP.beam.TextureLength, MY_THIEF_ESP.beam.TextureSpeed = 1, 3
    end
end

-- ============== CREATE BASE BEAM ==============
local function createBaseBeam()
    clearBaseBeam()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local dh = getMyDeliveryHitbox()
    if not dh then return end
    
    -- ЗАЩИТА: рандомные имена для beam
    ESP.baseA0 = Instance.new("Attachment", hrp)
    ESP.baseA0.Name = generateRandomName() -- ЗАЩИТА
    ESP.baseA1 = Instance.new("Attachment", dh)
    ESP.baseA1.Name = generateRandomName() -- ЗАЩИТА
    
    ESP.baseBeam = Instance.new("Beam", hrp)
    ESP.baseBeam.Name = generateRandomName() -- ЗАЩИТА
    ESP.baseBeam.Attachment0, ESP.baseBeam.Attachment1 = ESP.baseA0, ESP.baseA1
    ESP.baseBeam.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0))
    ESP.baseBeam.Transparency = NumberSequence.new(0.2)
    ESP.baseBeam.LightEmission, ESP.baseBeam.LightInfluence = 1, 0
    ESP.baseBeam.Width0, ESP.baseBeam.Width1 = 0.8, 0.5
    ESP.baseBeam.FaceCamera, ESP.baseBeam.Segments = true, 15
    ESP.baseBeam.TextureLength, ESP.baseBeam.TextureSpeed = 1, 2
    ESP.baseVisible = true
end

-- ============== CREATE STOLEN PODIUM ESP ==============
local function createStolenPodiumESP(podiumInfo)
    clearStolenPodiumESP()
    if not podiumInfo or not CONFIG.ESP_ENABLED then return end
    local spawn, podium = podiumInfo.spawn, podiumInfo.podium
    if not spawn or not spawn.Parent or not podium or not podium.Parent then return end
    STOLEN_ESP.data = podiumInfo
    
    -- ЗАЩИТА: рандомные имена + gethui
    local base = podium:FindFirstChild("Base")
    if base then
        STOLEN_ESP.hl = Instance.new("Highlight")
        STOLEN_ESP.hl.Name = generateRandomName() -- ЗАЩИТА
        STOLEN_ESP.hl.Adornee = base
        STOLEN_ESP.hl.FillColor, STOLEN_ESP.hl.OutlineColor = Color3.fromRGB(255, 200, 0), Color3.fromRGB(255, 100, 0)
        STOLEN_ESP.hl.FillTransparency, STOLEN_ESP.hl.OutlineTransparency = 0.85, 0.3
        STOLEN_ESP.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        STOLEN_ESP.hl.Parent = ProtectedGuiContainer -- ЗАЩИТА: gethui
    end
    
    STOLEN_ESP.bb = Instance.new("BillboardGui")
    STOLEN_ESP.bb.Name = generateRandomName() -- ЗАЩИТА
    STOLEN_ESP.bb.Adornee = spawn
    STOLEN_ESP.bb.Size, STOLEN_ESP.bb.StudsOffset = UDim2.new(0, 160, 0, 50), Vector3.new(0, 3, 0)
    STOLEN_ESP.bb.AlwaysOnTop = true
    STOLEN_ESP.bb.Parent = ProtectedGuiContainer -- ЗАЩИТА: gethui
    
    local frame = Instance.new("Frame", STOLEN_ESP.bb)
    frame.Name = generateRandomName() -- ЗАЩИТА
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel = Color3.fromRGB(60, 40, 0), 0.5, 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color, stroke.Thickness = Color3.fromRGB(255, 150, 0), 2
    cachedStolenStroke = stroke
    
    local statusLabel = Instance.new("TextLabel", frame)
    statusLabel.Name = generateRandomName() -- ЗАЩИТА
    statusLabel.Size, statusLabel.Position = UDim2.new(1, -10, 0, 20), UDim2.new(0, 5, 0, 3)
    statusLabel.BackgroundTransparency, statusLabel.Text = 1, "⚠️ STOLEN"
    statusLabel.TextColor3, statusLabel.TextScaled, statusLabel.Font = Color3.fromRGB(255, 180, 0), true, Enum.Font.GothamBold
    
    local nameLabel = Instance.new("TextLabel", frame)
    nameLabel.Name = generateRandomName() -- ЗАЩИТА
    nameLabel.Size, nameLabel.Position = UDim2.new(1, -10, 0, 18), UDim2.new(0, 5, 0, 25)
    nameLabel.BackgroundTransparency, nameLabel.Text = 1, podiumInfo.name or "Unknown"
    nameLabel.TextColor3, nameLabel.TextScaled, nameLabel.Font = Color3.new(1,1,1), true, Enum.Font.GothamMedium
end

-- print("[AutoSteal] ESP system loaded")

-- ============== BASE HIGHLIGHTS SYSTEM (ORIGINAL LOGIC) ==============
local cachedPlotOwners = {}

-- Функция проверки валидности highlights (не уничтожены ли объекты)
local function areHighlightsValid()
    if #myBaseHighlights == 0 then return false end
    for _, highlight in ipairs(myBaseHighlights) do
        if not highlight or not highlight.Parent then return false end
    end
    return true
end

-- Очистка подсветки баз (только highlights своей базы, НЕ прозрачность чужих)
local function clearBasesHighlights()
    for _, h in ipairs(myBaseHighlights) do pcall(function() h:Destroy() end) end
    myBaseHighlights = {}
end

-- Функция для применения прозрачности к одной BasePart
local function applyTransparencyToPart(part, transparency)
    if not part or not part:IsA("BasePart") or part:IsA("Terrain") then return end
    -- Проверяем не была ли уже обработана эта часть
    for _, data in ipairs(transparentParts) do
        if data.part == part then
            local targetTransparency = math.max(data.originalTransparency, transparency)
            if part.Transparency < targetTransparency then
                part.Transparency = targetTransparency
            end
            return
        end
    end
    -- Сохраняем оригинальную прозрачность
    table.insert(transparentParts, { part = part, originalTransparency = part.Transparency })
    local newTransparency = math.max(part.Transparency, transparency)
    part.Transparency = newTransparency
end

-- Функция для установки прозрачности всем BasePart внутри объекта
local function setModelTransparency(model, transparency)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") and not descendant:IsA("Terrain") then
            applyTransparencyToPart(descendant, transparency)
        end
    end
    if model:IsA("BasePart") then
        applyTransparencyToPart(model, transparency)
    end
    -- Подключаем слушатель для новых объектов
    local containerId = tostring(model:GetFullName())
    if not connectedContainers[containerId] then
        connectedContainers[containerId] = true
        pcall(function()
            model.DescendantAdded:Connect(function(descendant)
                if descendant:IsA("BasePart") and not descendant:IsA("Terrain") then
                    task.defer(function()
                        if descendant and descendant.Parent then
                            applyTransparencyToPart(descendant, transparency)
                        end
                    end)
                end
            end)
        end)
    end
end

local function restoreAllTransparency()
    for _, data in ipairs(transparentParts) do
        if data.part and data.part.Parent then
            pcall(function() data.part.Transparency = data.originalTransparency end)
        end
    end
    transparentParts = {}
    processedPlots = {}
    connectedContainers = {}
    otherBasesTransparencyApplied = false
end

-- ============== MEMORY CLEANUP: Очистка мёртвых ссылок ==============
local lastTransparencyCleanup = 0
local TRANSPARENCY_CLEANUP_INTERVAL = 10 -- Очищать каждые 10 секунд

local function cleanupDeadTransparentParts()
    local now = tick()
    if now - lastTransparencyCleanup < TRANSPARENCY_CLEANUP_INTERVAL then return end
    lastTransparencyCleanup = now
    
    -- Очищаем transparentParts от мёртвых частей
    local validParts = {}
    local removedCount = 0
    for _, data in ipairs(transparentParts) do
        if data.part and data.part.Parent then
            table.insert(validParts, data)
        else
            removedCount = removedCount + 1
        end
    end
    
    if removedCount > 0 then
        transparentParts = validParts
    end
    
    -- Очищаем connectedContainers от мёртвых моделей
    local validContainers = {}
    for containerId, _ in pairs(connectedContainers) do
        -- containerId это GetFullName(), проверяем существует ли объект
        local stillExists = false
        pcall(function()
            -- Пытаемся найти объект в workspace
            local parts = string.split(containerId, ".")
            if #parts > 0 then
                local current = game
                for _, partName in ipairs(parts) do
                    current = current:FindFirstChild(partName)
                    if not current then break end
                end
                stillExists = current ~= nil
            end
        end)
        if stillExists then
            validContainers[containerId] = true
        end
    end
    connectedContainers = validContainers
    
    -- Очищаем processedPlots от несуществующих плотов
    local plotsFolder = workspace:FindFirstChild("Plots")
    if plotsFolder then
        local validPlots = {}
        for plotId, _ in pairs(processedPlots) do
            if plotsFolder:FindFirstChild(plotId) then
                validPlots[plotId] = true
            end
        end
        processedPlots = validPlots
    end
end

-- Получаем PlotModel своего плота напрямую
local function getMyPlotModel()
    -- Способ 1: Через findPlayerPlot (fallback)
    local myPlot = findPlayerPlot()
    if myPlot then return myPlot end
    
    -- Способ 2: Поиск по PlotSign с YourBase
    local plotsFolder = workspace:FindFirstChild("Plots")
    if plotsFolder then
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            local plotSign = plot:FindFirstChild("PlotSign")
            if plotSign then
                local yourBase = plotSign:FindFirstChild("YourBase")
                if yourBase and yourBase:IsA("BillboardGui") and yourBase.Enabled then
                    return plot
                end
            end
        end
    end
    return nil
end

-- Функция получения объектов для подсветки из плота
local function getAllDecorationTargets(plotModel)
    local targets = {}
    local decorations = plotModel:FindFirstChild("Decorations")
    if decorations then
        for _, child in ipairs(decorations:GetChildren()) do
            if child:IsA("Model") or child:IsA("BasePart") then
                table.insert(targets, child)
            end
        end
    end
    local building = plotModel:FindFirstChild("Building")
    if building and (building:IsA("Model") or building:IsA("BasePart")) then
        table.insert(targets, building)
    end
    if #targets == 0 and plotModel:IsA("Model") then
        table.insert(targets, plotModel)
    end
    return targets
end

-- Обновление радужного цвета своей базы (ВСЕ элементы)
local function updateMyBaseHighlight()
    if not basesHighlightEnabled then return end
    for _, highlight in ipairs(myBaseHighlights) do
        if highlight and highlight.Parent then
            pcall(function()
                highlight.FillColor = Color3.fromHSV(rainbowHue, 0.5, 1)
            end)
        end
    end
end

-- Создание подсветки баз (радужная для своей ТОЛЬКО при переноске + прозрачность для ДРУГИХ)
local function createBasesHighlights()
    clearBasesHighlights()
    if not basesHighlightEnabled then return end
    
    local myPlotModel = getMyPlotModel()
    local isCarrying = LocalPlayer:GetAttribute("Stealing") == true
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return end
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if not plot:IsA("Model") and not plot:IsA("Folder") then continue end
        
        -- Определяем свой ли это плот
        local isOwner = false
        
        -- Способ 1: прямое сравнение модели
        if myPlotModel and plot == myPlotModel then isOwner = true end
        
        -- Способ 2: проверка YourBase billboard
        if not isOwner then
            local plotSign = plot:FindFirstChild("PlotSign")
            if plotSign then
                local yourBase = plotSign:FindFirstChild("YourBase")
                if yourBase and yourBase:IsA("BillboardGui") and yourBase.Enabled then
                    isOwner = true; myPlotModel = plot
                end
            end
        end
        
        -- Способ 3: проверка PlotSign текста
        if not isOwner then
            local plotSign = plot:FindFirstChild("PlotSign")
            if plotSign then
                local surfaceGui = plotSign:FindFirstChild("SurfaceGui")
                if surfaceGui then
                    local frame = surfaceGui:FindFirstChild("Frame")
                    if frame then
                        local nameLabel = frame:FindFirstChildOfClass("TextLabel")
                        if nameLabel and type(nameLabel.Text) == "string" then
                            local nameText = nameLabel.Text
                            if string.find(nameText, LocalPlayer.DisplayName, 1, true) or
                               string.find(nameText, LocalPlayer.Name, 1, true) then
                                isOwner = true; myPlotModel = plot
                            end
                        end
                    end
                end
            end
        end
        
        -- Способ 4: проверка атрибута Owner
        if not isOwner then
            local owner = plot:GetAttribute("Owner")
            if owner and (owner == LocalPlayer.Name or owner == LocalPlayer.UserId or tostring(owner) == tostring(LocalPlayer.UserId)) then
                isOwner = true; myPlotModel = plot
            end
        end
        
        if isOwner then
            local plotId = tostring(plot:GetFullName())
            processedPlots[plotId] = true
            
            -- Радужная подсветка своей базы ТОЛЬКО когда несём brainrot
            if isCarrying then
                local highlightTargets = getAllDecorationTargets(plot)
                for _, target in ipairs(highlightTargets) do
                    local highlight = Instance.new("Highlight")
                    highlight.Name = generateRandomName()
                    highlight.Adornee = target
                    highlight.FillColor = Color3.fromHSV(rainbowHue, 0.5, 1)
                    highlight.OutlineColor = Color3.new(1, 1, 1)
                    highlight.FillTransparency = 0.5
                    highlight.OutlineTransparency = 0.3
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.Parent = ProtectedGuiContainer
                    table.insert(myBaseHighlights, highlight)
                end
            end
        else
            -- Это НЕ наш плот - делаем его полупрозрачным
            local plotId = tostring(plot:GetFullName())
            if not processedPlots[plotId] then
                local partsChanged = 0
                
                local decorations = plot:FindFirstChild("Decorations")
                if decorations then setModelTransparency(decorations, 0.7); partsChanged = partsChanged + 1 end
                
                local building = plot:FindFirstChild("Building")
                if building then setModelTransparency(building, 0.7); partsChanged = partsChanged + 1 end
                
                local plotModelChild = plot:FindFirstChild("PlotModel")
                if plotModelChild then setModelTransparency(plotModelChild, 0.7); partsChanged = partsChanged + 1 end
                
                if partsChanged == 0 then
                    local skipNames = {"AnimalPodiums", "PlotSign", "DeliveryHitbox", "SpawnLocation", "Waypoints", "PlotBase", "Ground", "Baseplate"}
                    for _, child in ipairs(plot:GetChildren()) do
                        local shouldSkip = false
                        for _, skipName in ipairs(skipNames) do
                            if child.Name == skipName then shouldSkip = true; break end
                        end
                        if not shouldSkip then
                            if child:IsA("Model") or child:IsA("Folder") then
                                setModelTransparency(child, 0.7); partsChanged = partsChanged + 1
                            elseif child:IsA("BasePart") and not child:IsA("Terrain") then
                                applyTransparencyToPart(child, 0.7); partsChanged = partsChanged + 1
                            end
                        end
                    end
                end
                
                if partsChanged > 0 then otherBasesTransparencyApplied = true end
                processedPlots[plotId] = true
            end
        end
    end
end

-- ============== ОТСЛЕЖИВАНИЕ НОВЫХ ИГРОКОВ ==============
-- Переменная для хранения подключений (чтобы не дублировать)
local plotsTrackingConnected = false
local plotChildAddedConnections = {}

-- Функция проверки владельца плота
local function isPlotOwnedByMe(plot)
    -- Способ 1: YourBase BillboardGui
    local plotSign = plot:FindFirstChild("PlotSign")
    if plotSign then
        local yourBase = plotSign:FindFirstChild("YourBase")
        if yourBase and yourBase:IsA("BillboardGui") and yourBase.Enabled then
            return true
        end
        -- Способ 2: SurfaceGui с именем
        local surfaceGui = plotSign:FindFirstChild("SurfaceGui")
        if surfaceGui then
            local frame = surfaceGui:FindFirstChild("Frame")
            if frame then
                local nameLabel = frame:FindFirstChildOfClass("TextLabel")
                if nameLabel and type(nameLabel.Text) == "string" then
                    local nameText = nameLabel.Text
                    if string.find(nameText, LocalPlayer.DisplayName, 1, true) or
                       string.find(nameText, LocalPlayer.Name, 1, true) then
                        return true
                    end
                end
            end
        end
    end
    -- Способ 3: атрибут Owner
    local owner = plot:GetAttribute("Owner")
    if owner and (owner == LocalPlayer.Name or owner == LocalPlayer.UserId or tostring(owner) == tostring(LocalPlayer.UserId)) then
        return true
    end
    return false
end

-- Функция обработки нового плота (для новых игроков)
local function handleNewPlot(plot)
    if not basesHighlightEnabled then return end
    if not plot or not plot.Parent then return end
    
    local plotId = tostring(plot:GetFullName())
    
    -- Проверяем не наш ли это плот
    if isPlotOwnedByMe(plot) then
        processedPlots[plotId] = true
        return
    end
    
    -- Это чужой плот - применяем прозрачность
    local partsChanged = 0
    
    local decorations = plot:FindFirstChild("Decorations")
    if decorations then setModelTransparency(decorations, 0.7); partsChanged = partsChanged + 1 end
    
    local building = plot:FindFirstChild("Building")
    if building then setModelTransparency(building, 0.7); partsChanged = partsChanged + 1 end
    
    local plotModelChild = plot:FindFirstChild("PlotModel")
    if plotModelChild then setModelTransparency(plotModelChild, 0.7); partsChanged = partsChanged + 1 end
    
    -- Fallback для других структур
    if partsChanged == 0 then
        local skipNames = {"AnimalPodiums", "PlotSign", "DeliveryHitbox", "SpawnLocation", "Waypoints", "PlotBase", "Ground", "Baseplate"}
        for _, child in ipairs(plot:GetChildren()) do
            local shouldSkip = false
            for _, skipName in ipairs(skipNames) do
                if child.Name == skipName then shouldSkip = true; break end
            end
            if not shouldSkip then
                if child:IsA("Model") or child:IsA("Folder") then
                    setModelTransparency(child, 0.7); partsChanged = partsChanged + 1
                elseif child:IsA("BasePart") and not child:IsA("Terrain") then
                    applyTransparencyToPart(child, 0.7); partsChanged = partsChanged + 1
                end
            end
        end
    end
    
    if partsChanged > 0 then otherBasesTransparencyApplied = true end
    processedPlots[plotId] = true
end

-- Функция для подключения слушателей добавления контента в существующий плот
local function connectPlotContentListeners(plot)
    local plotId = tostring(plot:GetFullName())
    if plotChildAddedConnections[plotId] then return end
    
    plotChildAddedConnections[plotId] = plot.ChildAdded:Connect(function(child)
        if child.Name == "Decorations" or child.Name == "Building" or child.Name == "PlotModel" then
            -- Проверяем не наш ли это плот
            if not isPlotOwnedByMe(plot) then
                task.wait(0.3)
                if child and child.Parent then
                    setModelTransparency(child, 0.7)
                    otherBasesTransparencyApplied = true
                end
            end
        end
    end)
end

-- Функция настройки отслеживания новых плотов
local function setupNewPlotTracking()
    if plotsTrackingConnected then return end
    plotsTrackingConnected = true
    
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return end
    
    -- 1. Слушаем добавление новых плотов (когда новый игрок заходит на сервер)
    plotsFolder.ChildAdded:Connect(function(newPlot)
        -- Ждём загрузку содержимого плота
        task.wait(1)
        handleNewPlot(newPlot)
        
        -- Повторная проверка через 3 секунды (для позднего контента)
        task.delay(3, function()
            if newPlot and newPlot.Parent then
                local plotId = tostring(newPlot:GetFullName())
                if not processedPlots[plotId] then
                    handleNewPlot(newPlot)
                end
            end
        end)
        
        -- Подключаем слушатель контента для этого плота
        connectPlotContentListeners(newPlot)
    end)
    
    -- 2. Слушаем DescendantAdded на папке Plots
    -- (когда игрок занимает пустой плот - плот не создаётся, меняется его содержимое)
    plotsFolder.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "Decorations" or descendant.Name == "Building" or descendant.Name == "PlotModel" then
            local plot = descendant.Parent
            if not plot or plot == plotsFolder then return end
            
            local plotId = tostring(plot:GetFullName())
            
            if not isPlotOwnedByMe(plot) then
                task.delay(0.3, function()
                    if descendant and descendant.Parent then
                        setModelTransparency(descendant, 0.7)
                        processedPlots[plotId] = true
                        otherBasesTransparencyApplied = true
                    end
                end)
            end
        end
    end)
    
    -- 3. Подключаем слушатели к уже существующим плотам
    for _, existingPlot in ipairs(plotsFolder:GetChildren()) do
        connectPlotContentListeners(existingPlot)
    end
end

-- Функция периодической перепроверки прозрачности чужих баз
local function recheckAllEnemyBasesTransparency()
    if not basesHighlightEnabled then return end
    
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return end
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if not plot:IsA("Model") and not plot:IsA("Folder") then continue end
        
        -- Пропускаем свой плот
        if isPlotOwnedByMe(plot) then continue end
        
        -- Перепроверяем прозрачность чужого плота
        local decorations = plot:FindFirstChild("Decorations")
        if decorations then
            for _, desc in ipairs(decorations:GetDescendants()) do
                if desc:IsA("BasePart") and not desc:IsA("Terrain") and desc.Transparency < 0.7 then
                    applyTransparencyToPart(desc, 0.7)
                end
            end
        end
        
        local building = plot:FindFirstChild("Building")
        if building then
            for _, desc in ipairs(building:GetDescendants()) do
                if desc:IsA("BasePart") and not desc:IsA("Terrain") and desc.Transparency < 0.7 then
                    applyTransparencyToPart(desc, 0.7)
                end
            end
        end
        
        local plotModelChild = plot:FindFirstChild("PlotModel")
        if plotModelChild then
            for _, desc in ipairs(plotModelChild:GetDescendants()) do
                if desc:IsA("BasePart") and not desc:IsA("Terrain") and desc.Transparency < 0.7 then
                    applyTransparencyToPart(desc, 0.7)
                end
            end
        end
    end
end

-- print("[AutoSteal] Base highlights loaded")

-- ============== RAINBOW BEAM LOOP ==============
local function rainbowBeamLoop()
    while true do
        task.wait(0.03)
        rainbowLoopCounter = rainbowLoopCounter + 1
        rainbowHue = (rainbowHue + C.RAINBOW_SPEED * 0.03) % 1
        baseBeamPhase = (baseBeamPhase + C.BASE_BEAM_BLINK_SPEED * 0.03) % (2 * math.pi)
        local rainbowColor = Color3.fromHSV(rainbowHue, 1, 1)
        
        -- Проверяем состояние переноски каждые 3 тика (0.09 сек)
        if rainbowLoopCounter % 3 == 0 and basesHighlightEnabled then
            local isCarrying = isCarryingBrainrotAdvanced()
            local now = tick()
            
            if isCarrying then
                local needRecreate = false
                if isCarrying ~= lastCarryingCheckState then needRecreate = true end
                if not needRecreate and not areHighlightsValid() then needRecreate = true end
                
                if needRecreate and (now - lastHighlightCreateTime) > C.HIGHLIGHT_COOLDOWN then
                    lastCarryingCheckState = isCarrying
                    lastHighlightCreateTime = now
                    createBasesHighlights()
                end
            elseif isCarrying ~= lastCarryingCheckState then
                lastCarryingCheckState = isCarrying
                lastHighlightCreateTime = now
                createBasesHighlights()
            end
        end
        
        -- Update ESP beam and name
        if CACHE.nameLabel and CACHE.nameLabel.Parent then
            pcall(function() CACHE.nameLabel.TextColor3 = rainbowColor end)
        end
        
        -- Update ESP beam color
        if ESP.beam and ESP.beam.Parent then
            local hue1, hue2, hue3 = rainbowHue, (rainbowHue + 0.33) % 1, (rainbowHue + 0.66) % 1
            pcall(function()
                ESP.beam.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(hue1, 1, 1)),
                    ColorSequenceKeypoint.new(0.5, Color3.fromHSV(hue2, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(hue3, 1, 1))
                })
            end)
        end
        
        -- Update my base highlight rainbow color
        updateMyBaseHighlight()
        
        -- Recreate ESP beam if needed
        if currentTarget and CONFIG.ESP_ENABLED and ESP.a1 and ESP.a1.Parent then
            if not ESP.beam or not ESP.beam.Parent then
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    if not ESP.a0 or not ESP.a0.Parent then
                        ESP.a0 = Instance.new("Attachment")
                        ESP.a0.Name = generateRandomName()
                        ESP.a0.Parent = hrp
                    end
                    ESP.beam = Instance.new("Beam")
                    ESP.beam.Name = generateRandomName()
                    ESP.beam.Attachment0, ESP.beam.Attachment1 = ESP.a0, ESP.a1
                    ESP.beam.Color = ColorSequence.new(rainbowColor)
                    ESP.beam.Transparency = NumberSequence.new(0.3)
                    ESP.beam.LightEmission, ESP.beam.LightInfluence = 1, 0
                    ESP.beam.Width0, ESP.beam.Width1 = 0.5, 0.3
                    ESP.beam.FaceCamera, ESP.beam.Segments = true, 20
                    ESP.beam.TextureLength, ESP.beam.TextureSpeed = 1, 1
                    ESP.beam.Parent = hrp
                end
            end
        end
        
        -- Update thief ESP
        if THIEF_ESP.target and THIEF_ESP.target.brainrotModel and THIEF_ESP.target.brainrotModel.Parent then
            if cachedThiefStroke and cachedThiefStroke.Parent then
                local flashColor = Color3.fromRGB(255, math.floor(100 + 155 * math.abs(math.sin(tick() * 3))), 0)
                pcall(function() cachedThiefStroke.Color = flashColor end)
            end
            if cachedThiefNameLabel and cachedThiefNameLabel.Parent then
                pcall(function() cachedThiefNameLabel.TextColor3 = rainbowColor end)
            end
            -- Recreate thief beam if needed
            if THIEF_ESP.a1 and THIEF_ESP.a1.Parent and (not THIEF_ESP.beam or not THIEF_ESP.beam.Parent) then
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    if not THIEF_ESP.a0 or not THIEF_ESP.a0.Parent then
                        THIEF_ESP.a0 = Instance.new("Attachment")
                        THIEF_ESP.a0.Name = generateRandomName()
                        THIEF_ESP.a0.Parent = hrp
                    end
                    THIEF_ESP.beam = Instance.new("Beam")
                    THIEF_ESP.beam.Name = generateRandomName()
                    THIEF_ESP.beam.Attachment0, THIEF_ESP.beam.Attachment1 = THIEF_ESP.a0, THIEF_ESP.a1
                    THIEF_ESP.beam.Color = ColorSequence.new(C.THIEF_BEAM_COLOR)
                    THIEF_ESP.beam.Transparency = NumberSequence.new(0.3)
                    THIEF_ESP.beam.LightEmission, THIEF_ESP.beam.LightInfluence = 1, 0
                    THIEF_ESP.beam.Width0, THIEF_ESP.beam.Width1 = 0.6, 0.4
                    THIEF_ESP.beam.FaceCamera, THIEF_ESP.beam.Segments = true, 20
                    THIEF_ESP.beam.TextureLength, THIEF_ESP.beam.TextureSpeed = 1, 2
                    THIEF_ESP.beam.Parent = hrp
                end
            end
        end
        
        -- Update my base thief ESP with pulsing
        if MY_THIEF_ESP.target and MY_THIEF_ESP.target.brainrotModel and MY_THIEF_ESP.target.brainrotModel.Parent then
            if cachedMyBaseThiefStroke and cachedMyBaseThiefStroke.Parent then
                local pulse = math.abs(math.sin(tick() * 5))
                local flashRed = math.floor(200 + 55 * pulse)
                pcall(function() cachedMyBaseThiefStroke.Color = Color3.fromRGB(flashRed, 0, 0) end)
            end
            if MY_THIEF_ESP.hl and MY_THIEF_ESP.hl.Parent then
                local blinkPhase = math.abs(math.sin(tick() * 4))
                local intensity = 0.3 + blinkPhase * 0.4
                pcall(function() MY_THIEF_ESP.hl.FillTransparency = intensity end)
                local brightness = 0.8 + blinkPhase * 0.2
                pcall(function() MY_THIEF_ESP.hl.FillColor = Color3.fromRGB(
                    math.floor(255 * brightness),
                    math.floor(50 * (1 - blinkPhase * 0.5)),
                    math.floor(50 * (1 - blinkPhase * 0.5))
                ) end)
            end
            if cachedMyBaseThiefNameLabel and cachedMyBaseThiefNameLabel.Parent then
                local blinkPhase = math.abs(math.sin(tick() * 8))
                local r, g, b = 255, math.floor(100 + blinkPhase * 100), math.floor(100 + blinkPhase * 100)
                pcall(function() cachedMyBaseThiefNameLabel.TextColor3 = Color3.fromRGB(r, g, b) end)
            end
            -- Пульсирующий красный beam к вору моей базы
            if MY_THIEF_ESP.beam and MY_THIEF_ESP.beam.Parent then
                local pulsePhase = math.sin(tick() * 6) * 0.5 + 0.5
                pcall(function()
                    MY_THIEF_ESP.beam.Width0 = 0.6 + pulsePhase * 0.6
                    MY_THIEF_ESP.beam.Width1 = 0.4 + pulsePhase * 0.4
                    MY_THIEF_ESP.beam.Transparency = NumberSequence.new(0.1 + pulsePhase * 0.3)
                    local redIntensity = 200 + pulsePhase * 55
                    MY_THIEF_ESP.beam.Color = ColorSequence.new(Color3.fromRGB(redIntensity, 0, 0))
                end)
            end
        end
        
        -- Update stolen podium ESP (highlight only, no beam)
        if cachedStolenStroke and cachedStolenStroke.Parent then
            local flashOrange = Color3.fromRGB(255, math.floor(150 + 100 * math.abs(math.sin(tick() * 4))), 0)
            pcall(function() cachedStolenStroke.Color = flashOrange end)
        end
        
        -- Check carrying and create/update base beam (red pulsing like original)
        local carrying = isCarryingBrainrotAdvanced()
        if carrying then
            if not ESP.baseVisible then
                createBaseBeam()
            end
            if ESP.baseBeam and ESP.baseBeam.Parent then
                -- Пульсация яркости через sin (как в оригинале)
                local pulse = math.abs(math.sin(baseBeamPhase * math.pi * 2))
                local brightness = 0.5 + pulse * 0.5
                -- Цвет от тёмно-красного до ярко-красного
                local red = 180 + pulse * 75
                pcall(function() ESP.baseBeam.Color = ColorSequence.new(Color3.fromRGB(red, 0, 0)) end)
                -- Прозрачность тоже пульсирует
                local transparency = 0.1 + (1 - pulse) * 0.3
                pcall(function() ESP.baseBeam.Transparency = NumberSequence.new(transparency) end)
                -- Ширина пульсирует
                pcall(function()
                    ESP.baseBeam.Width0 = 0.5 + pulse * 0.5
                    ESP.baseBeam.Width1 = 0.3 + pulse * 0.3
                end)
            end
        else
            if ESP.baseVisible then clearBaseBeam() end
        end
    end
end

-- ============== STEAL PROMPT FUNCTIONS ==============
local function getStealPromptForPodium(podium)
    if not podium then return nil end
    local base = podium:FindFirstChild("Base")
    if not base then return nil end
    local spawn = base:FindFirstChild("Spawn")
    if not spawn then return nil end
    local promptAttachment = spawn:FindFirstChild("PromptAttachment")
    if not promptAttachment then return nil end
    for _, desc in ipairs(promptAttachment:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            local state = desc:GetAttribute("State")
            local actionText = desc.ActionText
            if state == "Steal" or actionText == "Steal" then return desc end
        end
    end
    return nil
end

local function isPromptForTargetBrainrot(prompt, targetName)
    if not prompt or not targetName then return false end
    return prompt.ObjectText == targetName
end

local function unblockAllPrompts()
    local plotsFolder = CACHE.plotsFolder or workspace:FindFirstChild("Plots")
    if not plotsFolder then return end
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local animalPodiums = plot:FindFirstChild("AnimalPodiums")
        if animalPodiums then
            for _, podium in ipairs(animalPodiums:GetChildren()) do
                local base = podium:FindFirstChild("Base")
                if base then
                    local spawn = base:FindFirstChild("Spawn")
                    if spawn then
                        local promptAttachment = spawn:FindFirstChild("PromptAttachment")
                        if promptAttachment then
                            for _, desc in ipairs(promptAttachment:GetDescendants()) do
                                if desc:IsA("ProximityPrompt") then desc.Enabled = true end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ============== TRY STEAL FUNCTION ==============
local function trySteal(brainrotData)
    if not brainrotData or not brainrotData.podium then return false end
    local targetName = brainrotData.name
    local distance = getDistanceToSpawn(brainrotData.spawn)
    if distance > CONFIG.MAX_STEAL_DISTANCE then return false end
    if not canStealBrainrot(targetName) then return false end
    
    local prompt = getStealPromptForPodium(brainrotData.podium)
    if not prompt or not prompt.Enabled then return false end
    
    local state = prompt:GetAttribute("State")
    if state ~= "Steal" and prompt.ActionText ~= "Steal" then return false end
    if not isPromptForTargetBrainrot(prompt, targetName) then return false end
    
    local plotUID = brainrotData.plot.Name
    local podiumIndex = tonumber(brainrotData.podiumIndex) or brainrotData.podiumIndex
    local stealSuccess = false
    
    pcall(function()
        local StealRemote = CACHE.stealRemote or getNetRemote(STEAL_REMOTE_ID)
        local PromptRemote = CACHE.promptRemote or getNetRemote(PROMPT_REMOTE_ID)
        if not CACHE.stealRemote then CACHE.stealRemote = StealRemote end
        if not CACHE.promptRemote then CACHE.promptRemote = PromptRemote end
        
        if StealRemote and PromptRemote then
            local serverTime = workspace:GetServerTimeNow()
            PromptRemote:FireServer(serverTime + 53, HOLD_BEGAN_UUID_1)
            PromptRemote:FireServer(serverTime + 53, HOLD_BEGAN_UUID_2)
            task.wait(1.55)
            
            if not canStealBrainrot(targetName) then return end
            local currentPrompt = getStealPromptForPodium(brainrotData.podium)
            if not currentPrompt or currentPrompt.ObjectText ~= targetName then return end
            
            local serverTime2 = workspace:GetServerTimeNow()
            StealRemote:FireServer(serverTime2 + 67, STEAL_TRIGGER_UUID_1, plotUID, podiumIndex)
            StealRemote:FireServer(serverTime2 + 67, STEAL_TRIGGER_UUID_2, plotUID, podiumIndex)
            task.wait(0.3)
            if LocalPlayer:GetAttribute("Stealing") then stealSuccess = true end
        end
    end)
    return stealSuccess
end

-- ============== MAIN LOOP ==============
local function mainLoop()
    if loopRunning then return end
    loopRunning = true
    
    while CONFIG.AUTO_STEAL_ENABLED do
        local bestBrainrot = findBestBrainrot()
        
        -- Search for thief (show ESP always when someone carries brainrot)
        local thief = findStolenBrainrotThief()
        if thief then
            if THIEF_ESP.target == nil or THIEF_ESP.target.brainrotModel ~= thief.brainrotModel or THIEF_ESP.target.player ~= thief.player then
                createThiefESP(thief)
                local stolenPodium = findStolenPodiumByName(thief.name)
                if stolenPodium then createStolenPodiumESP(stolenPodium) end
            end
        elseif THIEF_ESP.target then
            clearThiefESP()
            clearStolenPodiumESP()
        end
        
        -- Update ESP for best brainrot
        if bestBrainrot then
            if not lastBestBrainrotName then
                lastBestBrainrotName = bestBrainrot.name
            elseif lastBestBrainrotName ~= bestBrainrot.name then
                if not THIEF_ESP.target then lastBestBrainrotName = bestBrainrot.name end
            end
            
            setProtectionTarget(bestBrainrot)
            
            local needRecreateESP = (currentTarget == nil) or
                (currentTarget.plot.Name ~= bestBrainrot.plot.Name) or
                (currentTarget.podiumIndex ~= bestBrainrot.podiumIndex)
            
            if needRecreateESP then
                currentTarget = bestBrainrot
                if CONFIG.ESP_ENABLED then createESP(bestBrainrot) end
            else
                currentTarget.value = bestBrainrot.value
                currentTarget.text = bestBrainrot.text
                currentTarget.name = bestBrainrot.name
            end
        else
            if currentTarget then currentTarget = nil; clearESP() end
            clearProtectionTarget()
        end
        
        local stealStatus = getStealStatus()
        currentStealState = stealStatus
        
        if stealStatus == C.STEAL_STATE.CARRYING then task.wait(0.2); continue end
        if isCurrentlyStealing then task.wait(0.1); continue end
        if tick() - lastStealTime < CONFIG.STEAL_COOLDOWN then task.wait(CONFIG.UPDATE_INTERVAL); continue end
        
        if bestBrainrot and CONFIG.AUTO_STEAL_ENABLED then
            local distance = getDistanceToSpawn(bestBrainrot.spawn)
            if distance <= CONFIG.MAX_STEAL_DISTANCE then
                local isCorrectTarget = true
                if lastBestBrainrotName and bestBrainrot.name ~= lastBestBrainrotName then isCorrectTarget = false end
                if currentTarget and currentTarget.name ~= bestBrainrot.name then isCorrectTarget = false end
                
                if isCorrectTarget and canStealBrainrot(bestBrainrot.name) then
                    isCurrentlyStealing = true
                    task.spawn(function()
                        if trySteal(bestBrainrot) then lastStealTime = tick() end
                        isCurrentlyStealing = false
                    end)
                end
            end
        end
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    loopRunning = false
end

-- ============== ESP UPDATE LOOP ==============
local lastEspSearch = 0 -- For espLoop timing

local function espLoop()
    while true do
        task.wait(ESP_RANGE_CHECK_INTERVAL)
        espLoopCounter = espLoopCounter + 1
        
        -- Fast range check every tick
        if currentTarget and CONFIG.ESP_ENABLED then
            local targetPart = currentTarget.spawn
            if not targetPart and currentTarget.model then
                targetPart = currentTarget.model.PrimaryPart or currentTarget.model:FindFirstChildWhichIsA("BasePart")
            end
            
            if targetPart and targetPart.Parent then
                local character = LocalPlayer.Character
                local hrp = character and character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local distance = (hrp.Position - targetPart.Position).Magnitude
                    local inRange = distance <= CONFIG.MAX_STEAL_DISTANCE
                    
                    if inRange ~= cachedEspInRange then
                        cachedEspInRange = inRange
                        local color = inRange and CONFIG.ESP_COLOR_IN_RANGE or CONFIG.ESP_COLOR
                        if ESP.hl and ESP.hl.Parent then ESP.hl.FillColor = color end
                        if CACHE.distLabel and CACHE.distLabel.Parent then
                            CACHE.distLabel.Text = string.format("📍 %.0f studs %s", distance, inRange and "[✓ В РАДИУСЕ!]" or "")
                            CACHE.distLabel.TextColor3 = inRange and Color3.new(0, 1, 0) or Color3.new(1, 1, 1)
                        end
                    end
                    
                    if espLoopCounter % 5 == 0 and CACHE.distLabel and CACHE.distLabel.Parent then
                        CACHE.distLabel.Text = string.format("📍 %.0f studs %s", distance, inRange and "[✓ В РАДИУСЕ!]" or "")
                    end
                end
            elseif not currentTarget.model or not currentTarget.model.Parent then
                clearESP()
                currentTarget = nil
            end
        end
        
        -- Validity check less frequently
        if espLoopCounter % 10 == 0 and currentTarget then
            local valid = false
            if currentTarget.model and currentTarget.model.Parent then valid = true
            elseif currentTarget.spawn and currentTarget.spawn.Parent and 
                   currentTarget.podium and currentTarget.podium.Parent then valid = true end
            if not valid then clearESP(); currentTarget = nil end
        end
        
        -- Search for my base thief + best brainrot thief
        if espLoopCounter % 10 == 0 then
            local myBaseThief = findMyBaseThief()
            if myBaseThief then
                if MY_THIEF_ESP.target == nil or MY_THIEF_ESP.target.brainrotModel ~= myBaseThief.brainrotModel or
                   MY_THIEF_ESP.target.player ~= myBaseThief.player then
                    createMyBaseThiefESP(myBaseThief)
                end
                if THIEF_ESP.target then clearThiefESP(); clearStolenPodiumESP() end
            else
                if MY_THIEF_ESP.target then clearMyBaseThiefESP() end
                local thief = findStolenBrainrotThief()
                if thief then
                    if THIEF_ESP.target == nil or THIEF_ESP.target.brainrotModel ~= thief.brainrotModel or
                       THIEF_ESP.target.player ~= thief.player then
                        createThiefESP(thief)
                        local stolenPodium = findStolenPodiumByName(thief.name)
                        if stolenPodium then createStolenPodiumESP(stolenPodium) end
                    end
                elseif THIEF_ESP.target then
                    clearThiefESP()
                    clearStolenPodiumESP()
                end
            end
        end
        
        -- Search for new target when Auto Steal disabled
        local now = tick()
        if not CONFIG.AUTO_STEAL_ENABLED and (now - lastEspSearch) > C.ESP_SEARCH_INTERVAL then
            lastEspSearch = now
            local bestBrainrot = findBestBrainrot(true)
            if bestBrainrot then
                if not lastBestBrainrotName then lastBestBrainrotName = bestBrainrot.name
                elseif lastBestBrainrotName ~= bestBrainrot.name and not THIEF_ESP.target then
                    lastBestBrainrotName = bestBrainrot.name
                end
                setProtectionTarget(bestBrainrot)
                local needRecreate = (currentTarget == nil) or
                    (currentTarget.plot.Name ~= bestBrainrot.plot.Name) or
                    (currentTarget.podiumIndex ~= bestBrainrot.podiumIndex)
                if needRecreate then
                    currentTarget = bestBrainrot
                    if CONFIG.ESP_ENABLED then createESP(bestBrainrot) end
                else
                    currentTarget.value = bestBrainrot.value
                    currentTarget.text = bestBrainrot.text
                    currentTarget.name = bestBrainrot.name
                end
            elseif currentTarget then
                currentTarget = nil
                clearESP()
                clearProtectionTarget()
            end
        end
        
        -- Thief validity check
        if espLoopCounter % 10 == 0 and THIEF_ESP.target then
            if not THIEF_ESP.target.brainrotModel or not THIEF_ESP.target.brainrotModel.Parent or
               not THIEF_ESP.target.character or not THIEF_ESP.target.character.Parent then
                clearThiefESP()
            end
        end
        
        -- My base thief validity check
        if espLoopCounter % 10 == 0 and MY_THIEF_ESP.target then
            if not MY_THIEF_ESP.target.brainrotModel or not MY_THIEF_ESP.target.brainrotModel.Parent or
               not MY_THIEF_ESP.target.character or not MY_THIEF_ESP.target.character.Parent then
                clearMyBaseThiefESP()
            end
        end
    end
end

-- ============== THIEF ESP LOOP ==============
local function thiefEspLoop()
    spawn(function()
        while true do
            task.wait(CONFIG.THIEF_SEARCH_INTERVAL)
            
            if not CONFIG.THIEF_ESP_ENABLED then
                clearThiefESP()
                continue
            end
            
            local bestThief = findStolenBrainrotThief()
            if bestThief then
                if not THIEF_ESP.target or THIEF_ESP.target.player ~= bestThief.player then
                    createThiefESP(bestThief)
                end
            else
                clearThiefESP()
            end
        end
    end)
end

-- ============== MY BASE THIEF LOOP ==============
local function myBaseThiefLoop()
    spawn(function()
        while true do
            task.wait(CONFIG.MY_BASE_THIEF_INTERVAL)
            
            if not CONFIG.MY_BASE_THIEF_ESP then
                clearMyBaseThiefESP()
                continue
            end
            
            local baseThief = findMyBaseThief()
            if baseThief then
                if not MY_THIEF_ESP.target or MY_THIEF_ESP.target.player ~= baseThief.player then
                    createMyBaseThiefESP(baseThief)
                end
            else
                clearMyBaseThiefESP()
            end
        end
    end)
end

-- ============== STOLEN PODIUM LOOP ==============
local function stolenPodiumLoop()
    spawn(function()
        while true do
            task.wait(1)
            
            if not CONFIG.STOLEN_PODIUM_ESP or not lastBestBrainrotName then
                clearStolenPodiumESP()
                continue
            end
            
            local stolenPodium = findStolenPodiumByName(lastBestBrainrotName)
            if stolenPodium then
                if not STOLEN_ESP.data or STOLEN_ESP.data.spawn ~= stolenPodium.spawn then
                    createStolenPodiumESP(stolenPodium)
                end
            else
                clearStolenPodiumESP()
            end
        end
    end)
end

-- print("[AutoSteal] Main loops loaded")

-- ============== GUI SYSTEM ==============

-- Удаление старых GUI (ищем по атрибуту для защиты)
local function removeOldGUI()
    -- ЗАЩИТА: Ищем по атрибуту вместо имени
    pcall(function()
        for _, child in pairs(ProtectedGuiContainer:GetChildren()) do
            if child:IsA("ScreenGui") and child:GetAttribute("_isAutoStealGui") then
                child:Destroy()
            end
        end
    end)
end

local function createToggleButtonAnimated(parent, name, text, yOffset, initialState, callback)
    local container = Instance.new("Frame")
    container.Name = generateRandomName() -- ЗАЩИТА
    container.Size = UDim2.new(1, -20, 0, 30)
    container.Position = UDim2.new(0, 10, 0, yOffset)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local label = Instance.new("TextLabel")
    label.Name = generateRandomName() -- ЗАЩИТА
    label.Size, label.Position = UDim2.new(0.7, 0, 1, 0), UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency, label.Text = 1, text
    label.TextColor3, label.TextXAlignment = Color3.new(1, 1, 1), Enum.TextXAlignment.Left
    label.Font, label.TextSize = Enum.Font.Gotham, 14
    label.Parent = container

    local toggleBg = Instance.new("Frame")
    toggleBg.Name = generateRandomName() -- ЗАЩИТА
    toggleBg.Size = UDim2.new(0, 50, 0, 24)
    toggleBg.Position = UDim2.new(1, -55, 0.5, -12)
    toggleBg.BackgroundColor3 = initialState and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(100, 100, 100)
    toggleBg.Parent = container
    Instance.new("UICorner", toggleBg).CornerRadius = UDim.new(0, 12)

    local toggleCircle = Instance.new("Frame")
    toggleCircle.Name = generateRandomName() -- ЗАЩИТА
    toggleCircle.Size = UDim2.new(0, 20, 0, 20)
    toggleCircle.Position = initialState and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10)
    toggleCircle.BackgroundColor3 = Color3.new(1, 1, 1)
    toggleCircle.Parent = toggleBg
    Instance.new("UICorner", toggleCircle).CornerRadius = UDim.new(0, 10)

    local button = Instance.new("TextButton")
    button.Name = generateRandomName() -- ЗАЩИТА
    button.Size, button.BackgroundTransparency, button.Text = UDim2.new(1, 0, 1, 0), 1, ""
    button.Parent = toggleBg

    local isEnabled = initialState
    button.MouseButton1Click:Connect(function()
        isEnabled = not isEnabled
        local targetPos = isEnabled and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10)
        local targetColor = isEnabled and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(100, 100, 100)
        pcall(function() TweenService:Create(toggleCircle, TweenInfo.new(0.2), {Position = targetPos}):Play() end)
        pcall(function() TweenService:Create(toggleBg, TweenInfo.new(0.2), {BackgroundColor3 = targetColor}):Play() end)
        if callback then callback(isEnabled) end
    end)

    return {
        container = container,
        setEnabled = function(state)
            isEnabled = state
            local targetPos = isEnabled and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10)
            local targetColor = isEnabled and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(100, 100, 100)
            toggleCircle.Position, toggleBg.BackgroundColor3 = targetPos, targetColor
        end,
        getEnabled = function() return isEnabled end
    }
end

local function createInfoLabelAnimated(parent, name, yOffset)
    local label = Instance.new("TextLabel")
    label.Name = generateRandomName() -- ЗАЩИТА
    label.Size, label.Position = UDim2.new(1, -20, 0, 50), UDim2.new(0, 10, 0, yOffset)
    label.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    label.TextColor3, label.Font, label.TextSize = Color3.new(1, 1, 1), Enum.Font.Gotham, 12
    label.TextWrapped, label.Text = true, "Цель: Нет"
    label.Parent = parent
    Instance.new("UICorner", label).CornerRadius = UDim.new(0, 6)
    return label
end

local function createGUI()
    removeOldGUI()
    
    -- ЗАЩИТА: рандомное имя + gethui + атрибут для идентификации
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = generateRandomName() -- ЗАЩИТА
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui:SetAttribute("_isAutoStealGui", true) -- для идентификации
    screenGui.Parent = ProtectedGuiContainer -- ЗАЩИТА: gethui

    mainFrame = Instance.new("Frame")
    mainFrame.Name = generateRandomName() -- ЗАЩИТА
    mainFrame.Size = UDim2.new(0, 250, 0, CONFIG.GUI_MINIMIZED and 35 or 120)
    mainFrame.Position = UDim2.new(0, CONFIG.GUI_POSITION_X, 0, CONFIG.GUI_POSITION_Y)
    mainFrame.BackgroundColor3, mainFrame.BorderSizePixel = Color3.fromRGB(30, 30, 30), 0
    mainFrame.Active = true
    mainFrame.Parent = screenGui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)
    local mainStroke = Instance.new("UIStroke", mainFrame)
    mainStroke.Color, mainStroke.Thickness = Color3.fromRGB(100, 100, 100), 1

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Name = generateRandomName() -- ЗАЩИТА
    titleBar.Size = UDim2.new(1, 0, 0, 35)
    titleBar.BackgroundColor3, titleBar.BorderSizePixel = Color3.fromRGB(50, 50, 50), 0
    titleBar.Parent = mainFrame
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

    local titleFix = Instance.new("Frame")
    titleFix.Name = generateRandomName() -- ЗАЩИТА
    titleFix.Size, titleFix.Position = UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 1, -10)
    titleFix.BackgroundColor3, titleFix.BorderSizePixel = Color3.fromRGB(50, 50, 50), 0
    titleFix.Parent = titleBar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = generateRandomName()
    titleLabel.Size, titleLabel.Position = UDim2.new(1, -70, 1, 0), UDim2.new(0, 10, 0, 0)
    titleLabel.BackgroundTransparency, titleLabel.Text = 1, "🎯 Auto Steal"
    titleLabel.TextColor3, titleLabel.TextXAlignment = Color3.new(1, 1, 1), Enum.TextXAlignment.Left
    titleLabel.Font, titleLabel.TextSize = Enum.Font.GothamBold, 16
    titleLabel.Parent = titleBar

    -- Minimize button
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = generateRandomName()
    minimizeBtn.Size, minimizeBtn.Position = UDim2.new(0, 25, 0, 25), UDim2.new(1, -60, 0.5, -12.5)
    minimizeBtn.BackgroundColor3, minimizeBtn.Text = Color3.fromRGB(80, 80, 80), CONFIG.GUI_MINIMIZED and "+" or "-"
    minimizeBtn.TextColor3, minimizeBtn.Font, minimizeBtn.TextSize = Color3.new(1, 1, 1), Enum.Font.GothamBold, 18
    minimizeBtn.Parent = titleBar
    local minCorner = Instance.new("UICorner", minimizeBtn)
    minCorner.Name = generateRandomName()
    minCorner.CornerRadius = UDim.new(0, 6)

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = generateRandomName()
    closeBtn.Size, closeBtn.Position = UDim2.new(0, 25, 0, 25), UDim2.new(1, -30, 0.5, -12.5)
    closeBtn.BackgroundColor3, closeBtn.Text = Color3.fromRGB(200, 50, 50), "×"
    closeBtn.TextColor3, closeBtn.Font, closeBtn.TextSize = Color3.new(1, 1, 1), Enum.Font.GothamBold, 18
    closeBtn.Parent = titleBar
    local closeCorner = Instance.new("UICorner", closeBtn)
    closeCorner.Name = generateRandomName()
    closeCorner.CornerRadius = UDim.new(0, 6)

    -- Content frame
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = generateRandomName()
    contentFrame.Size = UDim2.new(1, 0, 1, -35)
    contentFrame.Position, contentFrame.BackgroundTransparency = UDim2.new(0, 0, 0, 35), 1
    contentFrame.Visible = not CONFIG.GUI_MINIMIZED
    contentFrame.Parent = mainFrame

    -- Toggle buttons
    guiElements.autoStealToggle = createToggleButtonAnimated(contentFrame, "AutoSteal", "Auto Steal", 10, CONFIG.AUTO_STEAL_ENABLED, function(enabled)
        CONFIG.AUTO_STEAL_ENABLED = enabled
        _G.AutoStealEnabled = enabled
        saveConfig()
        if enabled then task.spawn(mainLoop) else unblockAllPrompts(); clearProtectionTarget() end
    end)

    guiElements.espToggle = createToggleButtonAnimated(contentFrame, "ESP", "ESP Highlight", 50, CONFIG.ESP_ENABLED, function(enabled)
        CONFIG.ESP_ENABLED = enabled
        saveConfig()
        if not enabled then clearESP(); clearThiefESP(); clearStolenPodiumESP()
        elseif currentTarget then createESP(currentTarget) end
    end)

    -- Target info
    guiElements.targetInfo = createInfoLabelAnimated(contentFrame, "TargetInfo", 90)

    -- Dragging
    local dragging, dragStart, startPos = false, nil, nil
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, mainFrame.Position
        end
    end)
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            CONFIG.GUI_POSITION_X, CONFIG.GUI_POSITION_Y = mainFrame.Position.X.Offset, mainFrame.Position.Y.Offset
            saveConfig()
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Minimize
    minimizeBtn.MouseButton1Click:Connect(function()
        CONFIG.GUI_MINIMIZED = not CONFIG.GUI_MINIMIZED
        minimizeBtn.Text = CONFIG.GUI_MINIMIZED and "+" or "-"
        contentFrame.Visible = not CONFIG.GUI_MINIMIZED
        local targetSize = CONFIG.GUI_MINIMIZED and UDim2.new(0, 250, 0, 35) or UDim2.new(0, 250, 0, 120)
        pcall(function()
            TweenService:Create(mainFrame, TweenInfo.new(0.2), {Size = targetSize}):Play()
        end)
        saveConfig()
    end)

    -- Close
    closeBtn.MouseButton1Click:Connect(function()
        CONFIG.AUTO_STEAL_ENABLED = false
        clearESP(); clearThiefESP(); clearStolenPodiumESP(); clearMyBaseThiefESP()
        screenGui:Destroy()
    end)

    return screenGui
end

local function updateGUI()
    if not guiElements.targetInfo then return end
    local carrying = isCarryingBrainrotAdvanced()
    
    if carrying then
        guiElements.targetInfo.Text = "🏃 Несу brainrot!\nДойди до базы!"
        guiElements.targetInfo.TextColor3 = Color3.fromRGB(255, 200, 0)
    elseif currentTarget then
        local targetPart = currentTarget.spawn
        if not targetPart and currentTarget.model then
            targetPart = currentTarget.model.PrimaryPart or currentTarget.model:FindFirstChildWhichIsA("BasePart")
        end
        local distance = getDistanceToSpawn(targetPart)
        local inRange = distance <= CONFIG.MAX_STEAL_DISTANCE
        guiElements.targetInfo.Text = string.format("🎯 %s\n💰 %s\n📍 %.1f studs %s", 
            currentTarget.name, currentTarget.text, distance, inRange and "✓" or "")
        guiElements.targetInfo.TextColor3 = inRange and Color3.fromRGB(0, 255, 0) or Color3.new(1, 1, 1)
    else
        guiElements.targetInfo.Text = "Цель: Не найдена"
        guiElements.targetInfo.TextColor3 = Color3.fromRGB(150, 150, 150)
    end
end

-- ============== GUI UPDATE LOOP ==============
local function guiUpdateLoop()
    while screenGui and screenGui.Parent do
        updateGUI()
        task.wait(0.1)
    end
end

-- print("[AutoSteal] GUI system loaded")

-- ============== CHARACTER RESPAWN HANDLER ==============
local function onCharacterAdded(character)
    local hrp = character:WaitForChild("HumanoidRootPart", 10)
    if not hrp then return end
    task.wait(0.3)

    -- Recreate ESP beam if target exists
    if currentTarget and CONFIG.ESP_ENABLED then
        ESP.a0, ESP.beam = nil, nil
        local targetPart = nil
        if currentTarget.spawn and currentTarget.spawn.Parent then targetPart = currentTarget.spawn
        elseif currentTarget.model and currentTarget.model.Parent then
            targetPart = currentTarget.model.PrimaryPart or currentTarget.model:FindFirstChildWhichIsA("BasePart")
        elseif ESP.bb and ESP.bb.Adornee and ESP.bb.Adornee.Parent then
            targetPart = ESP.bb.Adornee
        end
        
        if targetPart then
            ESP.a0 = Instance.new("Attachment")
            ESP.a0.Name = generateRandomName()
            ESP.a0.Parent = hrp
            if not ESP.a1 or not ESP.a1.Parent then
                ESP.a1 = Instance.new("Attachment")
                ESP.a1.Name = generateRandomName()
                ESP.a1.Position = Vector3.new(0, 2, 0)
                ESP.a1.Parent = targetPart
            end
            ESP.beam = Instance.new("Beam")
            ESP.beam.Name = generateRandomName()
            ESP.beam.Attachment0, ESP.beam.Attachment1 = ESP.a0, ESP.a1
            ESP.beam.Color = ColorSequence.new(Color3.fromHSV(rainbowHue, 1, 1))
            ESP.beam.Transparency = NumberSequence.new(0.3)
            ESP.beam.LightEmission, ESP.beam.LightInfluence = 1, 0
            ESP.beam.Width0, ESP.beam.Width1 = 0.5, 0.3
            ESP.beam.FaceCamera, ESP.beam.Segments = true, 20
            ESP.beam.TextureLength, ESP.beam.TextureSpeed = 1, 1
            ESP.beam.Parent = hrp
        end
    end

    -- Recreate base highlights
    if basesHighlightEnabled then task.wait(0.2); createBasesHighlights() end

    -- Clear old beam attachments
    ESP.baseA0, ESP.baseBeam = nil, nil
    THIEF_ESP.a0, THIEF_ESP.beam = nil, nil
    STOLEN_ESP.a0, STOLEN_ESP.beam = nil, nil
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then onCharacterAdded(LocalPlayer.Character) end

-- ============== PLOT OWNER LISTENER ==============
local function setupPlotListeners()
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return end
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot:IsA("Model") then
            local ownerValue = plot:FindFirstChild("Owner")
            if ownerValue and ownerValue:IsA("StringValue") then
                cachedPlotOwners[plot.Name] = ownerValue.Value
                ownerValue:GetPropertyChangedSignal("Value"):Connect(function()
                    cachedPlotOwners[plot.Name] = ownerValue.Value
                    if CONFIG.BASE_HIGHLIGHTS then
                        task.wait(0.5)
                        createBasesHighlights()
                    end
                end)
            end
        end
    end
end

-- ============== BASE HIGHLIGHTS BACKGROUND LOOPS ==============
local function transparencyRecheckLoop()
    task.wait(3)
    while true do
        task.wait(5)
        -- MEMORY CLEANUP: Очищаем мёртвые ссылки каждые 10 секунд
        pcall(cleanupDeadTransparentParts)
        if basesHighlightEnabled then pcall(recheckAllEnemyBasesTransparency) end
    end
end

local function highlightsRefreshLoop()
    while true do
        task.wait(15)
        if basesHighlightEnabled then pcall(createBasesHighlights) end
    end
end

local function onStealingChanged()
    local newCarryingState = LocalPlayer:GetAttribute("Stealing") == true
    lastCarryingCheckState = newCarryingState
    if not basesHighlightEnabled then return end
    
    lastHighlightCreateTime = tick()
    createBasesHighlights()
    
    if newCarryingState then
        task.delay(0.1, function()
            if isCarryingBrainrotAdvanced() and not areHighlightsValid() then
                lastHighlightCreateTime = tick(); createBasesHighlights()
            end
        end)
        task.delay(0.3, function()
            if isCarryingBrainrotAdvanced() and not areHighlightsValid() then
                lastHighlightCreateTime = tick(); createBasesHighlights()
            end
        end)
    end
end

local function startBaseHighlightsLoops()
    task.spawn(transparencyRecheckLoop)
    task.spawn(highlightsRefreshLoop)
    LocalPlayer:GetAttributeChangedSignal("Stealing"):Connect(onStealingChanged)
end

-- ============== INITIAL ESP SEARCH ==============
local function performInitialSearch()
    task.wait(1)
    if not LocalPlayer.Character then LocalPlayer.CharacterAdded:Wait() end
    local character = LocalPlayer.Character
    if character and not character:FindFirstChild("HumanoidRootPart") then
        character:WaitForChild("HumanoidRootPart", 5)
    end
    task.wait(0.5)
    
    local bestBrainrot = findBestBrainrot(true)
    if bestBrainrot then
        currentTarget = bestBrainrot
        lastBestBrainrotName = bestBrainrot.name
        if CONFIG.ESP_ENABLED then createESP(bestBrainrot) end
    end
    
    local thief = findStolenBrainrotThief(true)
    if thief then
        createThiefESP(thief)
        local stolenPodium = findStolenPodiumByName(thief.name)
        if stolenPodium then createStolenPodiumESP(stolenPodium) end
    end
end

-- ============== INITIALIZE ==============
local function initialize()
    -- print("[AutoSteal] Initializing optimized script...")
    
    setupPlotListeners()
    createGUI()
    
    task.spawn(rainbowBeamLoop)
    task.spawn(espLoop)
    task.spawn(guiUpdateLoop)
    
    task.defer(performInitialSearch)
    
    if CONFIG.BASE_HIGHLIGHTS then
        createBasesHighlights()
        setupNewPlotTracking()
        startBaseHighlightsLoops()
    end
    
    if CONFIG.AUTO_STEAL_ENABLED then task.spawn(mainLoop) end
    
    -- print("[AutoSteal] ✓ Optimized script fully loaded!")
    -- print("[AutoSteal] Press RightShift to toggle GUI")
end

-- Run initialization
initialize()

-- Export API
local AutoSteal = {}
function AutoSteal:Start()
    CONFIG.AUTO_STEAL_ENABLED = true
    _G.AutoStealEnabled = true
    saveConfig()
    task.spawn(mainLoop)
    if guiElements.autoStealToggle then guiElements.autoStealToggle.setEnabled(true) end
end

function AutoSteal:Stop()
    CONFIG.AUTO_STEAL_ENABLED = false
    _G.AutoStealEnabled = false
    saveConfig()
    clearProtectionTarget()
    unblockAllPrompts()
    if guiElements.autoStealToggle then guiElements.autoStealToggle.setEnabled(false) end
end

function AutoSteal:ToggleESP()
    CONFIG.ESP_ENABLED = not CONFIG.ESP_ENABLED
    saveConfig()
    if not CONFIG.ESP_ENABLED then clearESP(); clearThiefESP(); clearStolenPodiumESP()
    elseif currentTarget then createESP(currentTarget) end
    if guiElements.espToggle then guiElements.espToggle.setEnabled(CONFIG.ESP_ENABLED) end
end

function AutoSteal:SetMinValue(value) CONFIG.MIN_VALUE = value; saveConfig() end
function AutoSteal:FindBest() return findBestBrainrot() end
function AutoSteal:GetTarget() return currentTarget end

function AutoSteal:StealNow()
    local best = findBestBrainrot()
    if best then
        local distance = getDistanceToSpawn(best.spawn)
        if distance <= CONFIG.MAX_STEAL_DISTANCE then trySteal(best) end
    end
end

return AutoSteal
