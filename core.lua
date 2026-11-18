-- TONY COUNTRY v3 | Stealth Edition
-- Stack: Roblox Lua (Luau) | Any executor (Synapse X, KRNL, Fluxus...)
-- Visual: deep black #030303, white neon accents, red DESTRUCT
-- ESP separado por opção, box com cantos estilo corner-bracket

-- ============================================================
-- [ 0 ] EVASION LAYER
-- ============================================================
pcall(function() getexecutorname  = function() return nil end end)
pcall(function() identifyexecutor = function() return "unknown","0.0.0" end end)

local function S(t)
    local r = {} for i,v in ipairs(t) do r[i]=string.char(v) end return table.concat(r)
end

local STR_COREGUI       = S({67,111,114,101,71,117,105})
local STR_PLAYERS       = S({80,108,97,121,101,114,115})
local STR_RUNSERVICE    = S({82,117,110,83,101,114,118,105,99,101})
local STR_UIS           = S({85,115,101,114,73,110,112,117,116,83,101,114,118,105,99,101})
local STR_RENDERSTEPPED = S({82,101,110,100,101,114,83,116,101,112,112,101,100})
local STR_GUINAME       = S({84,67,80,110,108,95,118,51})

local _rawset   = rawset
local _pairs    = pairs
local _ipairs   = ipairs
local _pcall    = pcall
local _math     = math
local _table    = table
local _tostring = tostring

local function ProtectGui(gui)
    if syn and syn.protect_gui then _pcall(function() syn.protect_gui(gui) end)
    elseif protect_gui then         _pcall(function() protect_gui(gui) end)
    elseif gethui then              _pcall(function() gui.Parent = gethui() end); return true end
    return false
end

local _screenshotting = false

-- ============================================================
-- SERVICES
-- ============================================================
local Players    = game:GetService(STR_PLAYERS)
local RunService = game:GetService(STR_RUNSERVICE)
local UIS        = game:GetService(STR_UIS)
local Camera     = workspace.CurrentCamera
local LP         = Players.LocalPlayer

-- ============================================================
-- STATE
-- ============================================================
local State = {
    ESPBox        = false,
    ESPName       = false,
    ESPHealth     = false,   -- texto "120 hp"
    ESPHPBar      = false,   -- barra visual de vida
    ESPDistance   = false,
    AimbotEnabled = false,
    FOV           = 120,
    Smooth        = 0.18,
    AimbotKey     = Enum.KeyCode.LeftAlt,
    ESPObjects    = {},
    FOVCircle     = nil,
    Connections   = {},
    Destroyed     = false,
    PanelVisible  = true,
}

-- ============================================================
-- COLORS
-- ============================================================
local C = {
    BG          = Color3.fromRGB(3,   3,   3),    -- #030303 fundo principal
    BG2         = Color3.fromRGB(8,   8,   8),    -- seções internas
    BG3         = Color3.fromRGB(14,  14,  14),   -- elementos
    BORDER      = Color3.fromRGB(255, 255, 255),  -- branco neon
    BORDER_DIM  = Color3.fromRGB(55,  55,  55),   -- cinza escuro
    TEXT        = Color3.fromRGB(240, 240, 240),
    TEXT_DIM    = Color3.fromRGB(130, 130, 130),
    ACCENT      = Color3.fromRGB(255, 255, 255),  -- branco puro
    RED         = Color3.fromRGB(220,  40,  40),  -- DESTRUCT
    RED_HOVER   = Color3.fromRGB(255,  60,  60),
    GREEN       = Color3.fromRGB(80,  255, 120),  -- HP bar
    KNOB_ON     = Color3.fromRGB(3,    3,   3),
    KNOB_OFF    = Color3.fromRGB(100, 100, 100),
    TOGGLE_ON   = Color3.fromRGB(255, 255, 255),
    TOGGLE_OFF  = Color3.fromRGB(28,  28,  28),
}

-- ============================================================
-- DRAWING HELPERS
-- ============================================================
local function NewLine(col, thick)
    local d = Drawing.new("Line")
    d.Color = col or C.BORDER; d.Thickness = thick or 1.4; d.Visible = false
    return d
end
local function NewText(col, sz)
    local d = Drawing.new("Text")
    d.Color = col or C.TEXT; d.Size = sz or 13
    d.Font  = Drawing.Fonts.Monospace
    d.Outline = true; d.OutlineColor = Color3.new(0,0,0); d.Visible = false
    return d
end
local function NewSquare(col, thick)
    local d = Drawing.new("Square")
    d.Color = col or C.BORDER; d.Thickness = thick or 1.5
    d.Filled = false; d.Visible = false
    return d
end
local function NewCircle(col, thick)
    local d = Drawing.new("Circle")
    d.Color = col or C.BORDER; d.Thickness = thick or 1.5
    d.Filled = false; d.NumSides = 64; d.Visible = false
    return d
end

-- corner-bracket lines (4 cantos, 3 linhas cada = 12 linhas)
local function NewCornerBracket()
    local lines = {}
    for i = 1, 12 do
        local l = Drawing.new("Line")
        l.Color = C.BORDER; l.Thickness = 1.8; l.Visible = false
        lines[i] = l
    end
    return lines
end

-- atualiza corner-bracket dado x,y,w,h
local function UpdateCornerBracket(lines, x, y, w, h)
    local seg = _math.min(w, h) * 0.22  -- tamanho do canto
    -- top-left
    lines[1].From = Vector2.new(x, y+seg);         lines[1].To = Vector2.new(x, y)
    lines[2].From = Vector2.new(x, y);              lines[2].To = Vector2.new(x+seg, y)
    lines[3].From = Vector2.new(x, y+h*0.5-1);     lines[3].To = Vector2.new(x, y+h*0.5+1) -- tick lateral
    -- top-right
    lines[4].From = Vector2.new(x+w-seg, y);        lines[4].To = Vector2.new(x+w, y)
    lines[5].From = Vector2.new(x+w, y);            lines[5].To = Vector2.new(x+w, y+seg)
    lines[6].From = Vector2.new(x+w, y+h*0.5-1);   lines[6].To = Vector2.new(x+w, y+h*0.5+1)
    -- bottom-left
    lines[7].From = Vector2.new(x, y+h-seg);        lines[7].To = Vector2.new(x, y+h)
    lines[8].From = Vector2.new(x, y+h);            lines[8].To = Vector2.new(x+seg, y+h)
    -- bottom-right
    lines[9].From = Vector2.new(x+w-seg, y+h);      lines[9].To  = Vector2.new(x+w, y+h)
    lines[10].From= Vector2.new(x+w, y+h-seg);      lines[10].To = Vector2.new(x+w, y+h)
    -- crosshair dot center (pequeno tick no centro inferior)
    lines[11].From= Vector2.new(x+w*0.5-3, y+h+5); lines[11].To = Vector2.new(x+w*0.5+3, y+h+5)
    lines[12].From= Vector2.new(x+w*0.5, y+h+2);   lines[12].To = Vector2.new(x+w*0.5, y+h+8)
end

local function SetBracketVisible(lines, v)
    for _, l in _ipairs(lines) do l.Visible = v end
end

-- ============================================================
-- FOV CIRCLE
-- ============================================================
State.FOVCircle = NewCircle(Color3.fromRGB(255,255,255), 1.2)
State.FOVCircle.Transparency = 0.6

local function UpdateFOVCircle()
    if not State.FOVCircle then return end
    if _screenshotting then State.FOVCircle.Visible = false; return end
    local vp = Camera.ViewportSize
    State.FOVCircle.Position = Vector2.new(vp.X/2, vp.Y/2)
    State.FOVCircle.Radius   = State.FOV
    State.FOVCircle.Visible  = State.AimbotEnabled
end

-- ============================================================
-- WORLD TO VIEWPORT
-- ============================================================
local function W2V(pos)
    local vp, on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(vp.X, vp.Y), vp.Z, on
end

local function GetParts(char)
    return char:FindFirstChild("HumanoidRootPart"),
           char:FindFirstChild("Head"),
           char:FindFirstChildOfClass("Humanoid")
end

local function IsAlive(p)
    if p == LP then return false end
    local c = p.Character; if not c then return false end
    local hrp,head,hum = GetParts(c)
    if not hrp or not head or not hum then return false end
    return hum.Health > 0
end

-- ============================================================
-- ESP PER PLAYER
-- ============================================================
local function CreateESP(player)
    State.ESPObjects[player] = {
        Bracket  = NewCornerBracket(),
        Name     = NewText(Color3.fromRGB(255,255,255), 13),
        Health   = NewText(C.GREEN, 12),
        Distance = NewText(Color3.fromRGB(160,160,160), 11),
        HPBar    = NewSquare(C.GREEN, 2),
        HPBarBG  = NewSquare(Color3.fromRGB(50,50,50), 1),
    }
    State.ESPObjects[player].HPBar.Filled   = true
    State.ESPObjects[player].HPBarBG.Filled = true
end

local function RemoveESP(player)
    local obj = State.ESPObjects[player]; if not obj then return end
    for _, l in _ipairs(obj.Bracket) do l:Remove() end
    obj.Name:Remove(); obj.Health:Remove()
    obj.Distance:Remove(); obj.HPBar:Remove(); obj.HPBarBG:Remove()
    State.ESPObjects[player] = nil
end

local function HideESP(obj)
    SetBracketVisible(obj.Bracket, false)
    obj.Name.Visible = false; obj.Health.Visible = false
    obj.Distance.Visible = false
    obj.HPBar.Visible = false; obj.HPBarBG.Visible = false
end

local function UpdateESP(player, obj)
    if _screenshotting then HideESP(obj); return end
    if not IsAlive(player) then HideESP(obj); return end

    local char = player.Character
    local hrp, head, hum = GetParts(char)
    local top2d,    tZ, tOn = W2V(head.Position + Vector3.new(0, 0.75, 0))
    local bot2d,    bZ, bOn = W2V(hrp.Position  - Vector3.new(0, 2.6,  0))

    if not tOn or tZ <= 0 then HideESP(obj); return end

    local h  = _math.abs(top2d.Y - bot2d.Y)
    local w  = h * 0.48
    local x  = top2d.X - w/2

    -- bracket box
    local showBox = State.ESPBox
    UpdateCornerBracket(obj.Bracket, x, top2d.Y, w, h)
    SetBracketVisible(obj.Bracket, showBox)

    -- name
    obj.Name.Text     = player.Name
    obj.Name.Position = Vector2.new(top2d.X, top2d.Y - 17)
    obj.Name.Center   = true
    obj.Name.Visible  = State.ESPName

    -- HP bar (esquerda do box, vertical)
    local barW = 3
    local barX = x - 6
    local hpRatio = _math.clamp(hum.Health / _math.max(1, hum.MaxHealth), 0, 1)
    local barH = h * hpRatio

    -- HP bar — toggle independente
    obj.HPBarBG.Size     = Vector2.new(barW, h)
    obj.HPBarBG.Position = Vector2.new(barX, top2d.Y)
    obj.HPBarBG.Visible  = State.ESPHPBar

    obj.HPBar.Size     = Vector2.new(barW, barH)
    obj.HPBar.Position = Vector2.new(barX, top2d.Y + (h - barH))
    local r = _math.floor(255 * (1 - hpRatio))
    local g = _math.floor(255 * hpRatio)
    obj.HPBar.Color   = Color3.fromRGB(_math.clamp(r*2,0,255), _math.clamp(g*2,0,255), 60)
    obj.HPBar.Visible = State.ESPHPBar

    -- hp text — toggle independente
    obj.Health.Text     = _math.floor(hum.Health) .. " hp"
    obj.Health.Position = Vector2.new(barX - 2, top2d.Y + h - 12)
    obj.Health.Center   = true
    obj.Health.Visible  = State.ESPHealth

    -- distance
    local dist = _math.floor((hrp.Position - Camera.CFrame.Position).Magnitude)
    obj.Distance.Text     = dist .. "m"
    obj.Distance.Position = Vector2.new(x + w + 4, top2d.Y)
    obj.Distance.Visible  = State.ESPDistance
end



-- ============================================================
-- AIMBOT
-- ============================================================
local _noiseX, _noiseY, _lastAimPos = 0, 0, nil

local function UpdateNoise()
    _noiseX = _noiseX * 0.85 + (_math.random()-0.5) * 0.0014
    _noiseY = _noiseY * 0.85 + (_math.random()-0.5) * 0.0014
end

local function GetTarget()
    local vp     = Camera.ViewportSize
    local center = Vector2.new(vp.X/2, vp.Y/2)
    local best, bestD = nil, _math.huge
    for _, p in _ipairs(Players:GetPlayers()) do
        if not IsAlive(p) then continue end
        local head = p.Character:FindFirstChild("Head"); if not head then continue end
        local p2d, z, on = W2V(head.Position)
        if not on or z <= 0 then continue end
        local d = (p2d - center).Magnitude
        if d < State.FOV and d < bestD then bestD = d; best = head end
    end
    return best
end

local function RunAimbot()
    if not State.AimbotEnabled then return end
    if not UIS:IsKeyDown(State.AimbotKey) then _lastAimPos = nil; return end
    local target = GetTarget(); if not target then return end
    UpdateNoise()
    local tp = target.Position + Vector3.new(_noiseX*0.5, _noiseY*0.5, 0)
    if _lastAimPos then
        local delta = (tp - _lastAimPos).Magnitude
        if delta > 8 then tp = _lastAimPos:Lerp(tp, 0.4) end
    end
    _lastAimPos = tp
    local cur  = Camera.CFrame.LookVector
    local des  = (tp - Camera.CFrame.Position).Unit
    local sDir = cur:Lerp(des, 1 - State.Smooth)
    Camera.CFrame = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + sDir)
end

-- ============================================================
-- PLAYER MANAGEMENT
-- ============================================================
local function AddPlayer(p) CreateESP(p) end
local function RemPlayer(p) RemoveESP(p) end

for _, p in _ipairs(Players:GetPlayers()) do
    if p ~= LP then AddPlayer(p) end
end

local cA = Players.PlayerAdded:Connect(function(p) task.wait(1); AddPlayer(p) end)
local cR = Players.PlayerRemoving:Connect(RemPlayer)
_table.insert(State.Connections, cA)
_table.insert(State.Connections, cR)

-- Screenshot detection
UIS.InputBegan:Connect(function(inp)
    if inp.KeyCode == Enum.KeyCode.Print or inp.KeyCode == Enum.KeyCode.SysRq then
        _screenshotting = true
        task.delay(0.35, function() _screenshotting = false end)
    end
end)

-- ============================================================
-- RENDER LOOP
-- ============================================================
local _slot = 0
local renderConn = RunService[STR_RENDERSTEPPED]:Connect(function()
    if State.Destroyed then return end
    _slot = (_slot + 1) % 2
    UpdateFOVCircle()
    RunAimbot()
    if _slot == 0 then
        for p, obj in _pairs(State.ESPObjects) do UpdateESP(p, obj) end
    end
end)
_table.insert(State.Connections, renderConn)

-- ============================================================
-- GUI HELPERS
-- ============================================================
local function Frame(parent, size, pos, color, trans)
    local f = Instance.new("Frame")
    f.Size = size; f.Position = pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3 = color or C.BG
    f.BackgroundTransparency = trans or 0
    f.BorderSizePixel = 0; f.Parent = parent
    return f
end

local function Label(parent, text, size, color, font, xa)
    local l = Instance.new("TextLabel")
    l.Size = size; l.BackgroundTransparency = 1
    l.Text = text; l.TextColor3 = color or C.TEXT
    l.TextSize = 12; l.Font = font or Enum.Font.GothamMedium
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.Parent = parent; return l
end

local function Corner(parent, px)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, px or 6); c.Parent = parent; return c
end

local function Stroke(parent, color, thick)
    local s = Instance.new("UIStroke")
    s.Color = color or C.BORDER; s.Thickness = thick or 1.5
    s.Parent = parent; return s
end

-- ============================================================
-- SCREENGI & MAIN FRAME
-- ============================================================
local SG = Instance.new("ScreenGui")
SG.Name = STR_GUINAME; SG.ResetOnSpawn = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.Parent = game:GetService(STR_COREGUI)

local movedHUI = ProtectGui(SG)
if not movedHUI then _pcall(function() SG.IgnoreGuiInset = true end) end

-- outer glow aura — começa invisível, dimensionada depois de totalH ser calculado
local Aura = Frame(SG, UDim2.new(0,322,0,10), UDim2.new(0.5,-161,0.5,-5), C.BORDER, 1)
Corner(Aura, 10)

-- main
local MF = Frame(SG, UDim2.new(0,316,0,10), UDim2.new(0.5,-158,0.5,-5), C.BG)
Corner(MF, 8)
Stroke(MF, C.BORDER, 1.5)
MF.Active = true; MF.Draggable = true

-- ============================================================
-- HEADER
-- ============================================================
local Header = Frame(MF, UDim2.new(1,0,0,46), UDim2.new(0,0,0,0), C.BG2)
Corner(Header, 8)

-- bottom fill to square off lower corners of header
local HFill = Frame(Header, UDim2.new(1,0,0,8), UDim2.new(0,0,1,-8), C.BG2)

-- title
local TitleContainer = Frame(Header, UDim2.new(1,-16,1,0), UDim2.new(0,8,0,0), C.BG2, 1)
local TitleMain = Instance.new("TextLabel")
TitleMain.Size = UDim2.new(1,0,0.6,0)
TitleMain.Position = UDim2.new(0,0,0.1,0)
TitleMain.BackgroundTransparency = 1
TitleMain.Text = "TONY COUNTRY"
TitleMain.TextColor3 = C.BORDER
TitleMain.TextSize = 16
TitleMain.Font = Enum.Font.GothamBold
TitleMain.TextStrokeTransparency = 0.5
TitleMain.TextStrokeColor3 = C.BORDER
TitleMain.TextXAlignment = Enum.TextXAlignment.Center
TitleMain.Parent = TitleContainer

local TitleSub = Instance.new("TextLabel")
TitleSub.Size = UDim2.new(1,0,0.3,0)
TitleSub.Position = UDim2.new(0,0,0.68,0)
TitleSub.BackgroundTransparency = 1
TitleSub.Text = "✦  STEALTH EDITION  ✦"
TitleSub.TextColor3 = Color3.fromRGB(100,100,100)
TitleSub.TextSize = 9
TitleSub.Font = Enum.Font.GothamMedium
TitleSub.TextXAlignment = Enum.TextXAlignment.Center
TitleSub.Parent = TitleContainer

-- separador header
local HSep = Frame(MF, UDim2.new(1,-24,0,1), UDim2.new(0,12,0,46), C.BORDER, 0.82)

-- ============================================================
-- SCROLL / CONTENT AREA
-- ============================================================
local Content = Frame(MF, UDim2.new(1,-20,0,460), UDim2.new(0,10,0,54))
Content.BackgroundTransparency = 1

local yOff = 0
local function NextY(h, gap)
    local cur = yOff
    yOff = yOff + h + (gap or 6)
    return cur
end

-- ---- section label ----
local function SectionLabel(text)
    local lf = Frame(Content, UDim2.new(1,0,0,18), UDim2.new(0,0,0,NextY(18,4)))
    lf.BackgroundTransparency = 1
    local l = Label(lf, text, UDim2.new(1,0,1,0), Color3.fromRGB(80,80,80), Enum.Font.GothamBold)
    l.TextSize = 9
    -- linha decorativa após o texto
    local line = Frame(lf, UDim2.new(1,-60,0,1), UDim2.new(0,56,0.5,0), C.BORDER_DIM)
end

-- ---- toggle row ----
local function MakeToggle(labelText, getState, setState)
    local rowY = NextY(32, 4)
    local row  = Frame(Content, UDim2.new(1,0,0,32), UDim2.new(0,0,0,rowY), C.BG3)
    Corner(row, 5)
    Stroke(row, C.BORDER_DIM, 1)

    -- ícone lateral esquerdo
    local ledBG = Frame(row, UDim2.new(0,3,0.6,0), UDim2.new(0,0,0.2,0), C.BORDER_DIM)
    Corner(ledBG, 2)

    local lbl = Label(row, labelText, UDim2.new(1,-58,1,0), C.TEXT, Enum.Font.GothamMedium)
    lbl.Position = UDim2.new(0,10,0,0)
    lbl.TextSize = 12

    -- toggle pill
    local pill = Frame(row, UDim2.new(0,38,0,20), UDim2.new(1,-44,0.5,-10), C.TOGGLE_OFF)
    Corner(pill, 10)
    local pillStroke = Stroke(pill, C.BORDER_DIM, 1)

    local knob = Frame(pill, UDim2.new(0,14,0,14), UDim2.new(0,3,0.5,-7), C.KNOB_OFF)
    Corner(knob, 7)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1
    btn.Text = ""; btn.Parent = row

    local function Refresh()
        local on = getState()
        pill.BackgroundColor3  = on and C.TOGGLE_ON  or C.TOGGLE_OFF
        pillStroke.Color       = on and C.BORDER     or C.BORDER_DIM
        knob.Position          = on and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)
        knob.BackgroundColor3  = on and C.KNOB_ON    or C.KNOB_OFF
        ledBG.BackgroundColor3 = on and C.BORDER     or C.BORDER_DIM
    end
    Refresh()

    btn.MouseButton1Click:Connect(function()
        setState(not getState())
        Refresh()
    end)

    -- hover
    btn.MouseEnter:Connect(function() row.BackgroundColor3 = Color3.fromRGB(18,18,18) end)
    btn.MouseLeave:Connect(function() row.BackgroundColor3 = C.BG3 end)
end

-- ---- slider ----
local function MakeSlider(labelPrefix, getValue, setValue, minV, maxV)
    local rowY  = NextY(42, 4)
    local srow  = Frame(Content, UDim2.new(1,0,0,42), UDim2.new(0,0,0,rowY), C.BG3)
    Corner(srow, 5)
    Stroke(srow, C.BORDER_DIM, 1)

    local lbl = Label(srow, labelPrefix .. getValue(), UDim2.new(1,-12,0,18), C.TEXT, Enum.Font.GothamMedium)
    lbl.Position = UDim2.new(0,10,0,4); lbl.TextSize = 11

    local track = Frame(srow, UDim2.new(1,-20,0,4), UDim2.new(0,10,1,-12), C.BORDER_DIM)
    Corner(track, 2)

    local rel = (getValue() - minV) / (maxV - minV)
    local fill = Frame(track, UDim2.new(rel,0,1,0), UDim2.new(0,0,0,0), C.BORDER)
    Corner(fill, 2)

    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0,12,0,12); knob.AnchorPoint = Vector2.new(0.5,0.5)
    knob.Position = UDim2.new(rel,0,0.5,0)
    knob.BackgroundColor3 = C.BORDER; knob.BorderSizePixel = 0
    knob.Text = ""; knob.Parent = track
    Corner(knob, 6)

    local drag = false
    knob.MouseButton1Down:Connect(function() drag = true end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
    end)
    RunService[STR_RENDERSTEPPED]:Connect(function()
        if not drag then return end
        local mx  = UIS:GetMouseLocation().X
        local tp  = track.AbsolutePosition.X
        local tw  = track.AbsoluteSize.X
        local r   = _math.clamp((mx-tp)/tw, 0, 1)
        local val = _math.floor(minV + r*(maxV-minV))
        setValue(val)
        fill.Size       = UDim2.new(r,0,1,0)
        knob.Position   = UDim2.new(r,0,0.5,0)
        lbl.Text        = labelPrefix .. getValue()
    end)
end

-- ---- keybind ----
local function MakeKeybind()
    local rowY = NextY(32, 4)
    local row  = Frame(Content, UDim2.new(1,0,0,32), UDim2.new(0,0,0,rowY), C.BG3)
    Corner(row, 5)
    Stroke(row, C.BORDER_DIM, 1)

    local lbl = Label(row, "Aimbot Key", UDim2.new(0.55,0,1,0), C.TEXT, Enum.Font.GothamMedium)
    lbl.Position = UDim2.new(0,10,0,0); lbl.TextSize = 12

    local kbtn = Instance.new("TextButton")
    kbtn.Size = UDim2.new(0,80,0,22); kbtn.Position = UDim2.new(1,-88,0.5,-11)
    kbtn.BackgroundColor3 = C.BG2; kbtn.BorderSizePixel = 0
    kbtn.TextColor3 = C.TEXT; kbtn.TextSize = 10
    kbtn.Font = Enum.Font.GothamBold
    kbtn.Text = "L-ALT"; kbtn.Parent = row
    Corner(kbtn, 4)
    Stroke(kbtn, C.BORDER_DIM, 1)

    local listening = false
    kbtn.MouseButton1Click:Connect(function()
        listening = true; kbtn.Text = "· · ·"
        kbtn.TextColor3 = Color3.fromRGB(160,160,160)
    end)
    UIS.InputBegan:Connect(function(inp, gpe)
        if gpe or not listening then return end
        if inp.UserInputType == Enum.UserInputType.Keyboard then
            State.AimbotKey     = inp.KeyCode
            kbtn.Text           = _tostring(inp.KeyCode):gsub("Enum.KeyCode.","")
            kbtn.TextColor3     = C.TEXT
            listening           = false
        end
    end)
end

-- ============================================================
-- BUILD SECTIONS
-- ============================================================

-- ESP
SectionLabel("— ESP")
MakeToggle("Box ESP",        function() return State.ESPBox      end, function(v) State.ESPBox      = v end)
MakeToggle("Name ESP",       function() return State.ESPName     end, function(v) State.ESPName     = v end)
MakeToggle("Health Text",    function() return State.ESPHealth   end, function(v) State.ESPHealth   = v end)
MakeToggle("Health Bar",     function() return State.ESPHPBar    end, function(v) State.ESPHPBar    = v end)
MakeToggle("Distance ESP",   function() return State.ESPDistance end, function(v) State.ESPDistance = v end)

-- AIMBOT
SectionLabel("— Aimbot")
MakeToggle("Aimbot",       function() return State.AimbotEnabled end, function(v)
    State.AimbotEnabled = v; UpdateFOVCircle()
end)
MakeSlider("FOV  ", function() return State.FOV end, function(v) State.FOV = v end, 20, 500)
MakeSlider("Smooth  ", function() return _math.floor(State.Smooth*100) end, function(v)
    State.Smooth = v/100
end, 2, 95)
MakeKeybind()

-- ============================================================
-- STATUS BAR
-- ============================================================
local sepY = yOff + 54 + 6
local StatusSep = Frame(MF, UDim2.new(1,-24,0,1), UDim2.new(0,12,0,sepY), C.BORDER_DIM, 0.4)

local StatusBar = Label(MF, "● ACTIVE  |  STEALTH ON",
    UDim2.new(1,-20,0,16), Color3.fromRGB(70,70,70), Enum.Font.GothamMedium,
    Enum.TextXAlignment.Left)
StatusBar.Position = UDim2.new(0,12,0,sepY+6)
StatusBar.TextSize = 10

-- ============================================================
-- DESTRUCT BUTTON
-- ============================================================
local DBtn = Instance.new("TextButton")
DBtn.Size              = UDim2.new(1,-20,0,52)
DBtn.Position          = UDim2.new(0,10,1,-62)
DBtn.BackgroundColor3  = Color3.fromRGB(18,4,4)
DBtn.BorderSizePixel   = 0
DBtn.Text              = "DESTRUCT"
DBtn.TextColor3        = C.RED
DBtn.TextSize          = 18
DBtn.Font              = Enum.Font.GothamBold
DBtn.TextStrokeTransparency = 0.4
DBtn.TextStrokeColor3  = C.RED
DBtn.Parent            = MF
Corner(DBtn, 6)

local DStroke = Stroke(DBtn, C.RED, 1.8)

-- pulsing glow sim via stroke thickness
local _dbPulse = 0
local dbConn = RunService[STR_RENDERSTEPPED]:Connect(function()
    if State.Destroyed then return end
    _dbPulse = _dbPulse + 0.06
    local pulse = 1.4 + _math.sin(_dbPulse) * 0.4
    DStroke.Thickness = pulse
end)
_table.insert(State.Connections, dbConn)

DBtn.MouseEnter:Connect(function()
    DBtn.BackgroundColor3 = Color3.fromRGB(35,6,6)
    DBtn.TextColor3       = C.RED_HOVER
    DStroke.Color         = C.RED_HOVER
end)
DBtn.MouseLeave:Connect(function()
    DBtn.BackgroundColor3 = Color3.fromRGB(18,4,4)
    DBtn.TextColor3       = C.RED
    DStroke.Color         = C.RED
end)

DBtn.MouseButton1Click:Connect(function()
    State.Destroyed = true

    for _, c in _ipairs(State.Connections) do _pcall(function() c:Disconnect() end) end
    _table.clear(State.Connections)

    for p in _pairs(State.ESPObjects) do RemoveESP(p) end
    if State.FOVCircle then State.FOVCircle:Remove() end

    _pcall(function() SG:Destroy() end)
    _pcall(function() Aura:Destroy() end)
end)

-- ============================================================
-- resize main frame to content — agora que yOff está final
-- ============================================================
local totalH = yOff + 54 + 6 + 16 + 10 + 52 + 20
MF.Size      = UDim2.new(0, 316, 0, totalH)
MF.Position  = UDim2.new(0.5,-158,0.5,-(totalH/2))
-- Aura: só agora revelada com o tamanho correto
Aura.Size                    = UDim2.new(0, 322, 0, totalH + 6)
Aura.Position                = UDim2.new(0.5,-161,0.5,-(totalH/2)-3)
Aura.BackgroundTransparency  = 0.93   -- glow visível, não mancha

-- ============================================================
-- LSHIFT: esconder / mostrar painel
-- ============================================================
local shiftConn = UIS.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.LeftShift then
        State.PanelVisible = not State.PanelVisible
        MF.Visible   = State.PanelVisible
        Aura.Visible = State.PanelVisible
    end
end)
_table.insert(State.Connections, shiftConn)
