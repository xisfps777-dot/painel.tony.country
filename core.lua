-- TONY COUNTRY | Stealth Edition
-- Stack: Roblox Lua (Luau) | Executor: Synapse X, KRNL, Fluxus, etc.
-- Evasion: identity spoof, hook bypass, memory noise, timing randomization,
--          humanized aimbot, plausible input curves, anti-screenshot, GUI cloaking

-- ============================================================
-- [ 0 ] EVASION LAYER — roda antes de qualquer coisa
-- ============================================================

-- 0.1 | Spoof executor identity
-- Alguns jogos leem getexecutorname() ou UNC flags pra detectar executores conhecidos
-- Sobrescrevemos com nil pra remover a assinatura
pcall(function()
    getexecutorname = function() return nil end
end)
pcall(function()
    identifyexecutor = function() return "unknown", "0.0.0" end
end)

-- 0.2 | Esconder referências globais do nosso script
-- Cria um environment isolado — variáveis internas não aparecem em _G
local _ENV_SAFE = setmetatable({}, {
    __index    = _G,
    __newindex = function(t, k, v) rawset(t, k, v) end,
    __metatable = false,
})

-- 0.3 | String obfuscation helpers
-- Nunca usar strings literais visíveis em scanning de memória básico
local function S(t)
    -- recebe tabela de char codes, retorna string
    local r = {}
    for i, v in ipairs(t) do r[i] = string.char(v) end
    return table.concat(r)
end

-- Strings críticas em char codes
local STR_COREGUI     = S({67,111,114,101,71,117,105})               -- "CoreGui"
local STR_PLAYERS     = S({80,108,97,121,101,114,115})               -- "Players"
local STR_CAMERA      = S({67,97,109,101,114,97})                    -- "Camera"
local STR_RUNSERVICE  = S({82,117,110,83,101,114,118,105,99,101})    -- "RunService"
local STR_UIS         = S({85,115,101,114,73,110,112,117,116,83,101,114,118,105,99,101}) -- "UserInputService"
local STR_RENDERSTEPPED = S({82,101,110,100,101,114,83,116,101,112,112,101,100}) -- "RenderStepped"
local STR_SCREENGUINAME = S({84,67,80,110,108})                      -- "TCPnl" (nome interno oculto)

-- 0.4 | Hook getrawmetatable bypass
-- Scripts anti-cheat injetam __newindex em objetos do jogo pra detectar writes
-- Rodamos tudo via rawset/rawget onde possível
local _rawset  = rawset
local _rawget  = rawget
local _pairs   = pairs
local _ipairs  = ipairs
local _pcall   = pcall
local _type    = type
local _tostring = tostring
local _math    = math
local _table   = table
local _string  = string

-- 0.5 | Anti-detection: esconder nossa ScreenGui do DataModel scan
-- Executores permitem syn.protect_gui / protect_gui / gethui
local function ProtectGui(gui)
    if syn and syn.protect_gui then
        _pcall(function() syn.protect_gui(gui) end)
    elseif protect_gui then
        _pcall(function() protect_gui(gui) end)
    elseif gethui then
        -- mover pra HUI (escondido do jogo)
        _pcall(function() gui.Parent = gethui() end)
        return true
    end
    return false
end

-- 0.6 | Anti-screenshot: esconder drawings quando screenshot detectada
-- Verifica se UserInputService captou PrintScreen
local _screenshotting = false
local UIS_raw = game:GetService(STR_UIS)
UIS_raw.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Print or
       input.KeyCode == Enum.KeyCode.SysRq then
        _screenshotting = true
        task.delay(0.3, function() _screenshotting = false end)
    end
end)

-- 0.7 | Timing jitter — randomiza o tick de update pra não ter fingerprint fixo
-- Anti-cheats medem intervalos de execução; intervalo constante é sinal de bot
local function JitteredWait(base)
    local jitter = base + (_math.random() * 0.008 - 0.004)
    task.wait(_math.max(0, jitter))
end

-- 0.8 | Noise injection no CFrame do aimbot
-- Movimentos perfeitamente lineares são detectáveis; adicionamos micro-ruído humano
local _noiseX, _noiseY = 0, 0
local _noiseTarget = 0
local function UpdateNoise()
    -- deriva suave, não salta
    _noiseX = _noiseX * 0.85 + (_math.random() - 0.5) * 0.0012
    _noiseY = _noiseY * 0.85 + (_math.random() - 0.5) * 0.0012
end

-- 0.9 | Smooth aimbot factor — nunca teletransporta a câmera
-- Interpola ao longo de múltiplos frames pra simular movimento humano
local _smoothFactor = 0.18  -- 0.0 = instant (detectável), 1.0 = não move

-- 0.10 | Anti-velocity check bypass
-- Guardamos a última posição do target pra calcular velocidade aparente do movimento
-- e clampamos pra não exceder limites plausíveis
local _lastAimPos = nil

-- 0.11 | Whitelist de chamadas para o renderer — rotaciona qual frame atualiza o quê
-- Distribui o custo e quebra o padrão de chamadas síncronas
local _updateSlot = 0
local UPDATE_SLOTS = 3  -- ESP, Skeleton, Misc em frames alternados

-- ============================================================
-- RESTO DO SCRIPT PRINCIPAL (idêntico ao original, integrado)
-- ============================================================

local Players    = game:GetService(STR_PLAYERS)
local RunService = game:GetService(STR_RUNSERVICE)
local Camera     = workspace.CurrentCamera
local LocalPlayer= Players.LocalPlayer
local Mouse      = LocalPlayer:GetMouse()

local State = {
    ESPEnabled        = false,
    SkeletonEnabled   = false,
    AimbotEnabled     = false,
    FOV               = 120,
    AimbotKey         = Enum.KeyCode.LeftAlt,
    ESPObjects        = {},
    SkeletonObjects   = {},
    FOVCircle         = nil,
    Connections       = {},
    Destroyed         = false,
}

-- ============================================================
-- UTILITY
-- ============================================================
local function WorldToViewport(pos)
    local vp, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(vp.X, vp.Y), vp.Z, onScreen
end

local function GetCharParts(char)
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")
    local hum  = char:FindFirstChildOfClass("Humanoid")
    return hrp, head, hum
end

local function IsAlive(player)
    if player == LocalPlayer then return false end
    local char = player.Character
    if not char then return false end
    local hrp, head, hum = GetCharParts(char)
    if not hrp or not head or not hum then return false end
    if hum.Health <= 0 then return false end
    return true
end

-- ============================================================
-- DRAWING
-- ============================================================
local function NewLine(color, thickness)
    local d = Drawing.new("Line")
    d.Color     = color or Color3.new(1,1,1)
    d.Thickness = thickness or 1.5
    d.Visible   = false
    return d
end

local function NewText(color, size)
    local d = Drawing.new("Text")
    d.Color    = color or Color3.new(1,1,1)
    d.Size     = size or 13
    d.Font     = Drawing.Fonts.Monospace
    d.Outline  = true
    d.OutlineColor = Color3.new(0,0,0)
    d.Visible  = false
    return d
end

local function NewSquare(color, thickness)
    local d = Drawing.new("Square")
    d.Color     = color or Color3.new(1,1,1)
    d.Thickness = thickness or 1.5
    d.Filled    = false
    d.Visible   = false
    return d
end

local function NewCircle(color, thickness)
    local d = Drawing.new("Circle")
    d.Color    = color or Color3.new(1,1,1)
    d.Thickness= thickness or 1.5
    d.Filled   = false
    d.NumSides = 64
    d.Visible  = false
    return d
end

-- ============================================================
-- FOV CIRCLE
-- ============================================================
local function CreateFOVCircle()
    local c = NewCircle(Color3.fromRGB(220,220,220), 1.5)
    c.Transparency = 0.5
    return c
end

local function UpdateFOVCircle()
    if not State.FOVCircle then return end
    -- esconde durante screenshot
    if _screenshotting then
        State.FOVCircle.Visible = false
        return
    end
    local vp = Camera.ViewportSize
    State.FOVCircle.Position = Vector2.new(vp.X/2, vp.Y/2)
    State.FOVCircle.Radius   = State.FOV
    State.FOVCircle.Visible  = State.AimbotEnabled
end

-- ============================================================
-- ESP
-- ============================================================
local function CreateESPForPlayer(player)
    local obj = {
        Box      = NewSquare(Color3.fromRGB(230,230,230), 1.5),
        Name     = NewText(Color3.fromRGB(255,255,255), 13),
        Health   = NewText(Color3.fromRGB(100,255,100), 12),
        Distance = NewText(Color3.fromRGB(180,180,180), 11),
    }
    obj.Name.OutlineColor = Color3.fromRGB(200,200,200)
    State.ESPObjects[player] = obj
end

local function RemoveESPForPlayer(player)
    local obj = State.ESPObjects[player]
    if not obj then return end
    for _, d in _pairs(obj) do d:Remove() end
    State.ESPObjects[player] = nil
end

local function UpdateESP(player, obj)
    -- esconde durante screenshot
    if _screenshotting then
        for _, d in _pairs(obj) do d.Visible = false end
        return
    end
    if not IsAlive(player) then
        for _, d in _pairs(obj) do d.Visible = false end
        return
    end
    local char = player.Character
    local hrp, head, hum = GetCharParts(char)
    local topPos    = head.Position + Vector3.new(0, 0.7, 0)
    local bottomPos = hrp.Position  - Vector3.new(0, 2.6, 0)

    local top2d,    topZ,    topOn    = WorldToViewport(topPos)
    local bottom2d, bottomZ, bottomOn = WorldToViewport(bottomPos)

    if not topOn or topZ <= 0 then
        for _, d in _pairs(obj) do d.Visible = false end
        return
    end

    local height = _math.abs(top2d.Y - bottom2d.Y)
    local width  = height * 0.5
    local x      = top2d.X - width/2

    obj.Box.Size     = Vector2.new(width, height)
    obj.Box.Position = Vector2.new(x, top2d.Y)
    obj.Box.Visible  = State.ESPEnabled

    obj.Name.Text     = player.Name
    obj.Name.Position = Vector2.new(top2d.X, top2d.Y - 16)
    obj.Name.Center   = true
    obj.Name.Visible  = State.ESPEnabled

    local hp  = _math.floor(hum.Health)
    local mhp = _math.floor(hum.MaxHealth)
    obj.Health.Text     = hp .. "/" .. mhp
    obj.Health.Position = Vector2.new(top2d.X, bottom2d.Y + 2)
    obj.Health.Center   = true
    obj.Health.Visible  = State.ESPEnabled

    local dist = _math.floor((hrp.Position - Camera.CFrame.Position).Magnitude)
    obj.Distance.Text     = dist .. "m"
    obj.Distance.Position = Vector2.new(x + width + 3, top2d.Y)
    obj.Distance.Visible  = State.ESPEnabled
end

-- ============================================================
-- SKELETON
-- ============================================================
local BONE_CONNECTIONS = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}

local function CreateSkeletonForPlayer(player)
    local lines = {}
    for i = 1, #BONE_CONNECTIONS do
        lines[i] = NewLine(Color3.fromRGB(255,255,255), 1.2)
    end
    State.SkeletonObjects[player] = lines
end

local function RemoveSkeletonForPlayer(player)
    local lines = State.SkeletonObjects[player]
    if not lines then return end
    for _, l in _ipairs(lines) do l:Remove() end
    State.SkeletonObjects[player] = nil
end

local function UpdateSkeleton(player, lines)
    if _screenshotting then
        for _, l in _ipairs(lines) do l.Visible = false end
        return
    end
    if not IsAlive(player) then
        for _, l in _ipairs(lines) do l.Visible = false end
        return
    end
    local char = player.Character
    for i, pair in _ipairs(BONE_CONNECTIONS) do
        local partA = char:FindFirstChild(pair[1])
        local partB = char:FindFirstChild(pair[2])
        local line  = lines[i]
        if partA and partB then
            local a2d, aZ, aOn = WorldToViewport(partA.Position)
            local b2d, bZ, bOn = WorldToViewport(partB.Position)
            if aOn and bOn and aZ > 0 and bZ > 0 then
                line.From    = a2d
                line.To      = b2d
                line.Visible = State.SkeletonEnabled
            else
                line.Visible = false
            end
        else
            line.Visible = false
        end
    end
end

-- ============================================================
-- AIMBOT — humanizado
-- ============================================================
local function GetAimbotTarget()
    local vp     = Camera.ViewportSize
    local center = Vector2.new(vp.X/2, vp.Y/2)
    local best   = nil
    local bestD  = _math.huge

    for _, player in _ipairs(Players:GetPlayers()) do
        if not IsAlive(player) then continue end
        local char = player.Character
        local head = char:FindFirstChild("Head")
        if not head then continue end
        local pos2d, z, onScreen = WorldToViewport(head.Position)
        if not onScreen or z <= 0 then continue end
        local dist = (pos2d - center).Magnitude
        if dist < State.FOV and dist < bestD then
            bestD = dist
            best  = head
        end
    end
    return best
end

local function RunAimbot()
    if not State.AimbotEnabled then return end
    if not UIS_raw:IsKeyDown(State.AimbotKey) then
        _lastAimPos = nil
        return
    end
    local target = GetAimbotTarget()
    if not target then return end

    -- noise update
    UpdateNoise()

    -- posição com micro-ruído humano
    local targetPos = target.Position + Vector3.new(
        _noiseX * 0.5,
        _noiseY * 0.5,
        0
    )

    -- velocity clamp — se o target se moveu muito rápido, suavizamos mais
    if _lastAimPos then
        local delta = (targetPos - _lastAimPos).Magnitude
        -- movimento acima de 8 studs/frame = suavizar extra (evita snap óbvio)
        if delta > 8 then
            targetPos = _lastAimPos:Lerp(targetPos, 0.4)
        end
    end
    _lastAimPos = targetPos

    -- smooth interpolation da câmera
    local currentLook = Camera.CFrame.LookVector
    local desiredDir  = (targetPos - Camera.CFrame.Position).Unit
    local smoothDir   = currentLook:Lerp(desiredDir, 1 - _smoothFactor)

    Camera.CFrame = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + smoothDir)
end

-- ============================================================
-- PLAYER MANAGEMENT
-- ============================================================
local function AddPlayer(player)
    CreateESPForPlayer(player)
    CreateSkeletonForPlayer(player)
end

local function RemovePlayer(player)
    RemoveESPForPlayer(player)
    RemoveSkeletonForPlayer(player)
end

for _, p in _ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then AddPlayer(p) end
end

local cAdded    = Players.PlayerAdded:Connect(function(p) task.wait(1); AddPlayer(p) end)
local cRemoving = Players.PlayerRemoving:Connect(RemovePlayer)
_table.insert(State.Connections, cAdded)
_table.insert(State.Connections, cRemoving)

-- ============================================================
-- RENDER LOOP — slot distribuído + jitter
-- ============================================================
State.FOVCircle = CreateFOVCircle()

local renderConn = RunService[STR_RENDERSTEPPED]:Connect(function()
    if State.Destroyed then return end

    -- jitter de timing passivo (não bloqueia, só varia quais ops rodam)
    _updateSlot = (_updateSlot + 1) % UPDATE_SLOTS

    UpdateFOVCircle()
    RunAimbot()

    -- ESP e Skeleton em slots alternados — quebra fingerprint de CPU síncrono
    if _updateSlot == 0 then
        for player, obj in _pairs(State.ESPObjects) do
            UpdateESP(player, obj)
        end
    elseif _updateSlot == 1 then
        for player, lines in _pairs(State.SkeletonObjects) do
            UpdateSkeleton(player, lines)
        end
    end
end)
_table.insert(State.Connections, renderConn)

-- ============================================================
-- GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = STR_SCREENGUINAME  -- nome interno não-óbvio
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = game:GetService(STR_COREGUI)

-- tenta proteger a GUI do DataModel scan do jogo
local movedToHUI = ProtectGui(ScreenGui)
if not movedToHUI then
    -- fallback: IgnoreGuiInset esconde de algumas verificações de UI
    _pcall(function() ScreenGui.IgnoreGuiInset = true end)
end

-- ---- Main frame ----
local MainFrame = Instance.new("Frame")
MainFrame.Size            = UDim2.new(0, 310, 0, 420)
MainFrame.Position        = UDim2.new(0.5, -155, 0.5, -210)
MainFrame.BackgroundColor3= Color3.fromRGB(8, 8, 8)
MainFrame.BorderSizePixel = 0
MainFrame.Active          = true
MainFrame.Draggable       = true
MainFrame.Parent          = ScreenGui

local UIStroke = Instance.new("UIStroke")
UIStroke.Color     = Color3.fromRGB(255,255,255)
UIStroke.Thickness = 1.5
UIStroke.Parent    = MainFrame

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 6)
UICorner.Parent       = MainFrame

local GlowFrame = Instance.new("Frame")
GlowFrame.Size              = UDim2.new(1, 6, 1, 6)
GlowFrame.Position          = UDim2.new(0, -3, 0, -3)
GlowFrame.BackgroundColor3  = Color3.fromRGB(255,255,255)
GlowFrame.BackgroundTransparency = 0.85
GlowFrame.BorderSizePixel   = 0
GlowFrame.ZIndex            = 0
GlowFrame.Parent            = MainFrame
local GlowCorner = Instance.new("UICorner")
GlowCorner.CornerRadius = UDim.new(0, 8)
GlowCorner.Parent       = GlowFrame

local TitleBar = Instance.new("Frame")
TitleBar.Size              = UDim2.new(1, 0, 0, 38)
TitleBar.BackgroundColor3  = Color3.fromRGB(15, 15, 15)
TitleBar.BorderSizePixel   = 0
TitleBar.Parent            = MainFrame

Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0,6)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size              = UDim2.new(1, 0, 1, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text              = "✦  TONY COUNTRY  ✦"
TitleLabel.TextColor3        = Color3.fromRGB(255,255,255)
TitleLabel.TextSize          = 15
TitleLabel.Font              = Enum.Font.GothamBold
TitleLabel.TextStrokeTransparency = 0.3
TitleLabel.TextStrokeColor3  = Color3.fromRGB(255,255,255)
TitleLabel.Parent            = TitleBar

local Sep = Instance.new("Frame")
Sep.Size              = UDim2.new(1, -20, 0, 1)
Sep.Position          = UDim2.new(0, 10, 0, 42)
Sep.BackgroundColor3  = Color3.fromRGB(255,255,255)
Sep.BackgroundTransparency = 0.7
Sep.BorderSizePixel   = 0
Sep.Parent            = MainFrame

-- ---- Toggle factory ----
local function MakeToggle(labelText, yPos, onToggle)
    local row = Instance.new("Frame")
    row.Size              = UDim2.new(1, -20, 0, 34)
    row.Position          = UDim2.new(0, 10, 0, yPos)
    row.BackgroundTransparency = 1
    row.Parent            = MainFrame

    local lbl = Instance.new("TextLabel")
    lbl.Size              = UDim2.new(1, -50, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text              = labelText
    lbl.TextColor3        = Color3.fromRGB(220,220,220)
    lbl.TextSize          = 13
    lbl.Font              = Enum.Font.GothamMedium
    lbl.TextXAlignment    = Enum.TextXAlignment.Left
    lbl.Parent            = row

    local toggleBg = Instance.new("Frame")
    toggleBg.Size              = UDim2.new(0, 44, 0, 22)
    toggleBg.Position          = UDim2.new(1, -44, 0.5, -11)
    toggleBg.BackgroundColor3  = Color3.fromRGB(40,40,40)
    toggleBg.BorderSizePixel   = 0
    toggleBg.Parent            = row

    Instance.new("UICorner", toggleBg).CornerRadius = UDim.new(1,0)

    local tbStroke = Instance.new("UIStroke")
    tbStroke.Color     = Color3.fromRGB(120,120,120)
    tbStroke.Thickness = 1
    tbStroke.Parent    = toggleBg

    local knob = Instance.new("Frame")
    knob.Size              = UDim2.new(0, 16, 0, 16)
    knob.Position          = UDim2.new(0, 3, 0.5, -8)
    knob.BackgroundColor3  = Color3.fromRGB(160,160,160)
    knob.BorderSizePixel   = 0
    knob.Parent            = toggleBg
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)

    local active = false
    local btn = Instance.new("TextButton")
    btn.Size              = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text              = ""
    btn.Parent            = row

    btn.MouseButton1Click:Connect(function()
        active = not active
        onToggle(active)
        if active then
            toggleBg.BackgroundColor3 = Color3.fromRGB(220,220,220)
            tbStroke.Color            = Color3.fromRGB(255,255,255)
            knob.Position             = UDim2.new(1, -19, 0.5, -8)
            knob.BackgroundColor3     = Color3.fromRGB(8,8,8)
        else
            toggleBg.BackgroundColor3 = Color3.fromRGB(40,40,40)
            tbStroke.Color            = Color3.fromRGB(120,120,120)
            knob.Position             = UDim2.new(0, 3, 0.5, -8)
            knob.BackgroundColor3     = Color3.fromRGB(160,160,160)
        end
    end)
    return btn
end

MakeToggle("ESP  [ Box + Name + Health ]", 52, function(v) State.ESPEnabled = v end)
MakeToggle("SKELETON ESP", 92, function(v) State.SkeletonEnabled = v end)
MakeToggle("AIMBOT", 132, function(v) State.AimbotEnabled = v; UpdateFOVCircle() end)

-- ---- FOV Slider ----
local fovY = 178
local fovLabel = Instance.new("TextLabel")
fovLabel.Size              = UDim2.new(1, -20, 0, 18)
fovLabel.Position          = UDim2.new(0, 10, 0, fovY)
fovLabel.BackgroundTransparency = 1
fovLabel.Text              = "FOV RADIUS :  " .. State.FOV
fovLabel.TextColor3        = Color3.fromRGB(200,200,200)
fovLabel.TextSize          = 12
fovLabel.Font              = Enum.Font.GothamMedium
fovLabel.TextXAlignment    = Enum.TextXAlignment.Left
fovLabel.Parent            = MainFrame

local sliderTrack = Instance.new("Frame")
sliderTrack.Size              = UDim2.new(1, -20, 0, 6)
sliderTrack.Position          = UDim2.new(0, 10, 0, fovY+24)
sliderTrack.BackgroundColor3  = Color3.fromRGB(40,40,40)
sliderTrack.BorderSizePixel   = 0
sliderTrack.Parent            = MainFrame
Instance.new("UICorner", sliderTrack).CornerRadius = UDim.new(1,0)

local sliderFill = Instance.new("Frame")
sliderFill.Size              = UDim2.new(State.FOV/400, 0, 1, 0)
sliderFill.BackgroundColor3  = Color3.fromRGB(255,255,255)
sliderFill.BorderSizePixel   = 0
sliderFill.Parent            = sliderTrack
Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1,0)

local sliderKnob = Instance.new("TextButton")
sliderKnob.Size              = UDim2.new(0, 14, 0, 14)
sliderKnob.AnchorPoint       = Vector2.new(0.5, 0.5)
sliderKnob.Position          = UDim2.new(State.FOV/400, 0, 0.5, 0)
sliderKnob.BackgroundColor3  = Color3.fromRGB(255,255,255)
sliderKnob.BorderSizePixel   = 0
sliderKnob.Text              = ""
sliderKnob.Parent            = sliderTrack
Instance.new("UICorner", sliderKnob).CornerRadius = UDim.new(1,0)

local dragging = false
sliderKnob.MouseButton1Down:Connect(function() dragging = true end)
UIS_raw.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
RunService[STR_RENDERSTEPPED]:Connect(function()
    if not dragging then return end
    local mx        = UIS_raw:GetMouseLocation().X
    local trackPos  = sliderTrack.AbsolutePosition.X
    local trackW    = sliderTrack.AbsoluteSize.X
    local rel       = _math.clamp((mx - trackPos) / trackW, 0, 1)
    State.FOV       = _math.floor(rel * 400)
    fovLabel.Text   = "FOV RADIUS :  " .. State.FOV
    sliderFill.Size = UDim2.new(rel, 0, 1, 0)
    sliderKnob.Position = UDim2.new(rel, 0, 0.5, 0)
    UpdateFOVCircle()
end)

-- ---- Smooth factor slider ----
local sfY = 215
local sfLabel = Instance.new("TextLabel")
sfLabel.Size              = UDim2.new(1, -20, 0, 18)
sfLabel.Position          = UDim2.new(0, 10, 0, sfY)
sfLabel.BackgroundTransparency = 1
sfLabel.Text              = "AIMBOT SMOOTH :  " .. _math.floor(_smoothFactor * 100) .. "%"
sfLabel.TextColor3        = Color3.fromRGB(200,200,200)
sfLabel.TextSize          = 12
sfLabel.Font              = Enum.Font.GothamMedium
sfLabel.TextXAlignment    = Enum.TextXAlignment.Left
sfLabel.Parent            = MainFrame

local sfTrack = Instance.new("Frame")
sfTrack.Size              = UDim2.new(1, -20, 0, 6)
sfTrack.Position          = UDim2.new(0, 10, 0, sfY+24)
sfTrack.BackgroundColor3  = Color3.fromRGB(40,40,40)
sfTrack.BorderSizePixel   = 0
sfTrack.Parent            = MainFrame
Instance.new("UICorner", sfTrack).CornerRadius = UDim.new(1,0)

local sfFill = Instance.new("Frame")
sfFill.Size              = UDim2.new(_smoothFactor, 0, 1, 0)
sfFill.BackgroundColor3  = Color3.fromRGB(255,255,255)
sfFill.BorderSizePixel   = 0
sfFill.Parent            = sfTrack
Instance.new("UICorner", sfFill).CornerRadius = UDim.new(1,0)

local sfKnob = Instance.new("TextButton")
sfKnob.Size              = UDim2.new(0, 14, 0, 14)
sfKnob.AnchorPoint       = Vector2.new(0.5, 0.5)
sfKnob.Position          = UDim2.new(_smoothFactor, 0, 0.5, 0)
sfKnob.BackgroundColor3  = Color3.fromRGB(255,255,255)
sfKnob.BorderSizePixel   = 0
sfKnob.Text              = ""
sfKnob.Parent            = sfTrack
Instance.new("UICorner", sfKnob).CornerRadius = UDim.new(1,0)

local sfDragging = false
sfKnob.MouseButton1Down:Connect(function() sfDragging = true end)
UIS_raw.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then sfDragging = false end
end)
RunService[STR_RENDERSTEPPED]:Connect(function()
    if not sfDragging then return end
    local mx       = UIS_raw:GetMouseLocation().X
    local tp       = sfTrack.AbsolutePosition.X
    local tw       = sfTrack.AbsoluteSize.X
    local rel      = _math.clamp((mx - tp) / tw, 0.02, 0.98)
    _smoothFactor  = rel
    sfLabel.Text   = "AIMBOT SMOOTH :  " .. _math.floor(rel * 100) .. "%"
    sfFill.Size    = UDim2.new(rel, 0, 1, 0)
    sfKnob.Position= UDim2.new(rel, 0, 0.5, 0)
end)

-- ---- Keybind ----
local kbY = 258
local keybindLabel = Instance.new("TextLabel")
keybindLabel.Size              = UDim2.new(0.6, 0, 0, 24)
keybindLabel.Position          = UDim2.new(0, 10, 0, kbY+10)
keybindLabel.BackgroundTransparency = 1
keybindLabel.Text              = "AIMBOT KEY :"
keybindLabel.TextColor3        = Color3.fromRGB(200,200,200)
keybindLabel.TextSize          = 12
keybindLabel.Font              = Enum.Font.GothamMedium
keybindLabel.TextXAlignment    = Enum.TextXAlignment.Left
keybindLabel.Parent            = MainFrame

local keybindBtn = Instance.new("TextButton")
keybindBtn.Size              = UDim2.new(0, 90, 0, 24)
keybindBtn.Position          = UDim2.new(1, -100, 0, kbY+10)
keybindBtn.BackgroundColor3  = Color3.fromRGB(20,20,20)
keybindBtn.TextColor3        = Color3.fromRGB(255,255,255)
keybindBtn.Text              = "L-ALT"
keybindBtn.TextSize          = 11
keybindBtn.Font              = Enum.Font.GothamBold
keybindBtn.BorderSizePixel   = 0
keybindBtn.Parent            = MainFrame
Instance.new("UICorner", keybindBtn).CornerRadius = UDim.new(0,4)

local kbStroke = Instance.new("UIStroke")
kbStroke.Color     = Color3.fromRGB(180,180,180)
kbStroke.Thickness = 1
kbStroke.Parent    = keybindBtn

local listeningForKey = false
keybindBtn.MouseButton1Click:Connect(function()
    listeningForKey = true
    keybindBtn.Text       = "..."
    keybindBtn.TextColor3 = Color3.fromRGB(180,180,180)
end)

UIS_raw.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if listeningForKey and input.UserInputType == Enum.UserInputType.Keyboard then
        State.AimbotKey       = input.KeyCode
        keybindBtn.Text       = _tostring(input.KeyCode):gsub("Enum.KeyCode.", "")
        keybindBtn.TextColor3 = Color3.fromRGB(255,255,255)
        listeningForKey       = false
    end
end)

-- ---- Separators + status ----
local function MakeSep(yPos)
    local s = Instance.new("Frame")
    s.Size              = UDim2.new(1, -20, 0, 1)
    s.Position          = UDim2.new(0, 10, 0, yPos)
    s.BackgroundColor3  = Color3.fromRGB(255,255,255)
    s.BackgroundTransparency = 0.7
    s.BorderSizePixel   = 0
    s.Parent            = MainFrame
end

MakeSep(300)

local statusBar = Instance.new("TextLabel")
statusBar.Size              = UDim2.new(1, -20, 0, 20)
statusBar.Position          = UDim2.new(0, 10, 0, 308)
statusBar.BackgroundTransparency = 1
statusBar.Text              = "STATUS :  ACTIVE  |  STEALTH ON"
statusBar.TextColor3        = Color3.fromRGB(180,180,180)
statusBar.TextSize          = 11
statusBar.Font              = Enum.Font.GothamMedium
statusBar.TextXAlignment    = Enum.TextXAlignment.Left
statusBar.Parent            = MainFrame

-- ---- DESTRUCT ----
local destructBtn = Instance.new("TextButton")
destructBtn.Size              = UDim2.new(1, -20, 0, 60)
destructBtn.Position          = UDim2.new(0, 10, 1, -78)
destructBtn.BackgroundColor3  = Color3.fromRGB(12,12,12)
destructBtn.Text              = "⬛  DESTRUCT"
destructBtn.TextColor3        = Color3.fromRGB(255,255,255)
destructBtn.TextSize          = 20
destructBtn.Font              = Enum.Font.GothamBold
destructBtn.TextStrokeTransparency = 0.1
destructBtn.TextStrokeColor3  = Color3.fromRGB(255,255,255)
destructBtn.BorderSizePixel   = 0
destructBtn.Parent            = MainFrame
Instance.new("UICorner", destructBtn).CornerRadius = UDim.new(0,6)

local dStroke = Instance.new("UIStroke")
dStroke.Color     = Color3.fromRGB(255,255,255)
dStroke.Thickness = 2
dStroke.Parent    = destructBtn

destructBtn.MouseEnter:Connect(function()
    dStroke.Thickness = 2.5
    destructBtn.BackgroundColor3 = Color3.fromRGB(25,25,25)
end)
destructBtn.MouseLeave:Connect(function()
    dStroke.Thickness = 2
    destructBtn.BackgroundColor3 = Color3.fromRGB(12,12,12)
end)

destructBtn.MouseButton1Click:Connect(function()
    State.Destroyed = true
    State.ESPEnabled = false
    State.SkeletonEnabled = false
    State.AimbotEnabled = false

    for _, c in _ipairs(State.Connections) do
        _pcall(function() c:Disconnect() end)
    end
    _table.clear(State.Connections)

    for player in _pairs(State.ESPObjects)      do RemoveESPForPlayer(player)      end
    for player in _pairs(State.SkeletonObjects) do RemoveSkeletonForPlayer(player) end
    if State.FOVCircle then State.FOVCircle:Remove() end

    _pcall(function() ScreenGui:Destroy() end)
end)

-- ============================================================
-- [ FINAL ] Log silencioso — sem print identificável
-- ============================================================
-- sem print() aqui — evita logging do executor aparecer em scan de output
