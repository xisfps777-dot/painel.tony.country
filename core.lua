 -- core.lua | Roblox LuaU | Solara executor | GUI + ESP + Aimbot
-- Evasão: XOR strings, identifiers randômicos, jitter, smoothing adaptativo
-- GUI: ScreenGui injetada via CoreGui (bypassa FilteringEnabled)

-- ─── XOR ENGINE ───────────────────────────────────────────────────────────────
local _K = 0x5A

local function _xd(s)
    local o = table.create(#s)
    for i = 1, #s do
        o[i] = string.char(bit32.bxor(string.byte(s,i), _K))
    end
    return table.concat(o)
end

-- helper offline pra encriptar novas strings:
-- for c in ("SuaString"):gmatch(".") do io.write(("\\x%02x"):format(bit32.bxor(c:byte(),0x5A))) end

local _S = {
    Players    = _xd("\x0a\x1e\x38\x3b\x14\x1b\x2f"),
    RS         = _xd("\x08\x2f\x1f\x01\x14\x1b\x2e\x09\x2e\x14"),
    UIS        = _xd("\x2f\x14\x1b\x08\x06\x1f\x2a\x1f\x2d\x14\x01\x08\x20\x14\x1a\x2f\x14\x1b\x2e\x09\x2e\x14"),
    SG         = _xd("\x09\x20\x38\x1b\x20\x14\x1b\x0e\x2f\x09"),
    CoreGui    = _xd("\x19\x1f\x1b\x14\x0e\x2f\x09"),
    HRP        = _xd("\x12\x2f\x2d\x1a\x1f\x2d\x1f\x14\x08\x0e\x1f\x1f\x20\x17\x38\x1b\x20"),
    Head       = _xd("\x12\x14\x38\x14"),
    Humanoid   = _xd("\x12\x2f\x2d\x1a\x1f\x2d\x1f\x14"),
}

-- ─── RANDOMIZAÇÃO ─────────────────────────────────────────────────────────────
local function _rid()
    local c = "abcdefghijklmnopqrstuvwxyz"
    local t = table.create(8)
    for i = 1,8 do t[i] = c:sub(math.random(1,#c),math.random(1,#c)) end
    return table.concat(t)
end

local _pfx = "_" .. _rid()  -- prefixo único por sessão

-- ─── SERVICES ─────────────────────────────────────────────────────────────────
local _P    = game:GetService("Players")
local _RS   = game:GetService("RunService")
local _UIS  = game:GetService("UserInputService")
local _SG   = game:GetService("StarterGui")
local _lp   = _P.LocalPlayer
local _cam  = workspace.CurrentCamera

-- ─── CONFIG ───────────────────────────────────────────────────────────────────
local CFG = {
    -- ESP
    esp           = true,
    esp_box       = true,
    esp_name      = true,
    esp_dist      = true,
    esp_hp        = true,
    esp_color     = Color3.fromRGB(255, 60, 60),
    esp_max_dist  = 1000,

    -- AIMBOT
    aim           = true,
    aim_active    = false,
    aim_toggle    = Enum.KeyCode.X,
    aim_hold      = Enum.UserInputType.MouseButton2,
    aim_fov       = 150,
    aim_smooth    = 0.14,
    aim_target    = "Head",
    aim_teamcheck = true,

    -- GUI
    gui_toggle    = Enum.KeyCode.RightShift,
}

-- ─── GUI ──────────────────────────────────────────────────────────────────────
-- injeta em CoreGui — não aparece em PlayerGui, bypassa detecção comum
local _gui_visible = true

local function _build_gui()
    -- remove instância anterior se reexecutar
    pcall(function()
        local old = game:GetService("CoreGui"):FindFirstChild(_pfx .. "GUI")
        if old then old:Destroy() end
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name              = _pfx .. "GUI"
    gui.ResetOnSpawn      = false
    gui.DisplayOrder      = 999
    gui.IgnoreGuiInset    = true

    -- tenta CoreGui primeiro (Solara tem acesso)
    local ok = pcall(function()
        gui.Parent = game:GetService("CoreGui")
    end)
    if not ok then
        gui.Parent = _lp:WaitForChild("PlayerGui")
    end

    -- janela principal
    local win = Instance.new("Frame")
    win.Name              = "Win"
    win.Size              = UDim2.new(0, 220, 0, 260)
    win.Position          = UDim2.new(0, 20, 0.5, -130)
    win.BackgroundColor3  = Color3.fromRGB(18, 18, 22)
    win.BorderSizePixel   = 0
    win.Active            = true
    win.Draggable         = true
    win.Parent            = gui

    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 8)

    -- barra de título
    local bar = Instance.new("Frame")
    bar.Size             = UDim2.new(1, 0, 0, 30)
    bar.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    bar.BorderSizePixel  = 0
    bar.Parent           = win
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)

    local title = Instance.new("TextLabel")
    title.Size             = UDim2.new(1, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Text             = "✦ cheat  [RShift = hide]"
    title.TextColor3       = Color3.fromRGB(220, 220, 240)
    title.TextSize         = 13
    title.Font             = Enum.Font.GothamBold
    title.Parent           = bar

    -- helper: cria toggle row
    local function _row(parent, label, state, y, on_toggle)
        local row = Instance.new("Frame")
        row.Size            = UDim2.new(1, -20, 0, 28)
        row.Position        = UDim2.new(0, 10, 0, y)
        row.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
        row.BorderSizePixel  = 0
        row.Parent           = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel")
        lbl.Size             = UDim2.new(0.7, 0, 1, 0)
        lbl.Position         = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text             = label
        lbl.TextColor3       = Color3.fromRGB(200, 200, 215)
        lbl.TextSize         = 12
        lbl.Font             = Enum.Font.Gotham
        lbl.TextXAlignment   = Enum.TextXAlignment.Left
        lbl.Parent           = row

        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(0, 44, 0, 20)
        btn.Position         = UDim2.new(1, -54, 0.5, -10)
        btn.BackgroundColor3 = state and Color3.fromRGB(80, 200, 100) or Color3.fromRGB(200, 70, 70)
        btn.Text             = state and "ON" or "OFF"
        btn.TextColor3       = Color3.new(1,1,1)
        btn.TextSize         = 11
        btn.Font             = Enum.Font.GothamBold
        btn.BorderSizePixel  = 0
        btn.Parent           = row
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

        local _state = state
        btn.MouseButton1Click:Connect(function()
            _state = not _state
            btn.BackgroundColor3 = _state and Color3.fromRGB(80,200,100) or Color3.fromRGB(200,70,70)
            btn.Text             = _state and "ON" or "OFF"
            on_toggle(_state)
        end)

        return btn
    end

    local rows = {
        {"ESP",           CFG.esp,       function(v) CFG.esp = v end},
        {"  Box",         CFG.esp_box,   function(v) CFG.esp_box = v end},
        {"  Nome",        CFG.esp_name,  function(v) CFG.esp_name = v end},
        {"  Distância",   CFG.esp_dist,  function(v) CFG.esp_dist = v end},
        {"  HP Bar",      CFG.esp_hp,    function(v) CFG.esp_hp = v end},
        {"Aimbot",        CFG.aim,       function(v) CFG.aim = v end},
        {"  Team Check",  CFG.aim_teamcheck, function(v) CFG.aim_teamcheck = v end},
    }

    for i, r in ipairs(rows) do
        _row(win, r[1], r[2], 32 + (i-1)*30, r[3])
    end

    -- info keybinds
    local info = Instance.new("TextLabel")
    info.Size              = UDim2.new(1, -20, 0, 24)
    info.Position          = UDim2.new(0, 10, 1, -28)
    info.BackgroundTransparency = 1
    info.Text              = "X = toggle aim  |  RMB = hold aim"
    info.TextColor3        = Color3.fromRGB(120, 120, 140)
    info.TextSize          = 10
    info.Font              = Enum.Font.Gotham
    info.TextXAlignment    = Enum.TextXAlignment.Center
    info.Parent            = win

    return gui, win
end

local _gui, _win = _build_gui()

-- hide/show GUI
_UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == CFG.gui_toggle then
        _gui_visible = not _gui_visible
        _win.Visible  = _gui_visible
    end
    if input.KeyCode == CFG.aim_toggle then
        CFG.aim_active = not CFG.aim_active
        _SG:SetCore("SendNotification", {
            Title    = "Aimbot",
            Text     = CFG.aim_active and "ATIVADO" or "DESATIVADO",
            Duration = 1.5,
        })
    end
end)

-- ─── DRAWING POOL ─────────────────────────────────────────────────────────────
local _pool = {}

local function _nd(t, props)
    local d = Drawing.new(t)
    for k,v in pairs(props) do d[k] = v end
    table.insert(_pool, d)
    return d
end

local function _clr()
    for _, d in ipairs(_pool) do pcall(function() d:Remove() end) end
    _pool = {}
end

-- ─── UTILS ────────────────────────────────────────────────────────────────────
local function _alive(char)
    local h = char and char:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function _smt(p)
    if not CFG.aim_teamcheck then return false end
    return p.Team ~= nil and p.Team == _lp.Team
end

local function _w2s(pos)
    local s, inv = _cam:WorldToViewportPoint(pos)
    return Vector2.new(s.X, s.Y), inv, s.Z
end

local function _bbox(char)
    local mn_x, mn_y, mx_x, mx_y = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            local sz = p.Size * 0.5
            local cf = p.CFrame
            for _, o in ipairs({
                Vector3.new( sz.X, sz.Y, sz.Z),  Vector3.new(-sz.X, sz.Y, sz.Z),
                Vector3.new( sz.X,-sz.Y, sz.Z),  Vector3.new(-sz.X,-sz.Y, sz.Z),
                Vector3.new( sz.X, sz.Y,-sz.Z),  Vector3.new(-sz.X, sz.Y,-sz.Z),
                Vector3.new( sz.X,-sz.Y,-sz.Z),  Vector3.new(-sz.X,-sz.Y,-sz.Z),
            }) do
                local wp = (cf * CFrame.new(o)).Position
                local sp, inv, d = _w2s(wp)
                if inv and d > 0 then
                    if sp.X < mn_x then mn_x = sp.X end
                    if sp.Y < mn_y then mn_y = sp.Y end
                    if sp.X > mx_x then mx_x = sp.X end
                    if sp.Y > mx_y then mx_y = sp.Y end
                end
            end
        end
    end
    if mn_x == math.huge then return nil end
    return mn_x, mn_y, mx_x - mn_x, mx_y - mn_y
end

-- ─── ESP ──────────────────────────────────────────────────────────────────────
local function _esp()
    _clr()
    if not CFG.esp then return end
    for _, p in ipairs(_P:GetPlayers()) do
        if p == _lp then continue end
        local char = p.Character
        if not char or not _alive(char) then continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        local dist = (_cam.CFrame.Position - root.Position).Magnitude
        if dist > CFG.esp_max_dist then continue end
        local sp, inv, depth = _w2s(root.Position)
        if not inv or depth <= 0 then continue end
        local bx, by, bw, bh = _bbox(char)

        if CFG.esp_box and bx then
            for _, seg in ipairs({
                {Vector2.new(bx,by),        Vector2.new(bx+bw,by)},
                {Vector2.new(bx+bw,by),     Vector2.new(bx+bw,by+bh)},
                {Vector2.new(bx+bw,by+bh),  Vector2.new(bx,by+bh)},
                {Vector2.new(bx,by+bh),      Vector2.new(bx,by)},
            }) do
                _nd("Line",{From=seg[1],To=seg[2],Color=CFG.esp_color,Thickness=1,Visible=true,ZIndex=1})
            end
        end

        if CFG.esp_name and bx then
            _nd("Text",{Text=p.Name, Position=Vector2.new(bx+bw/2,by-14),
                Size=13, Color=Color3.new(1,1,1), Outline=true, Center=true, Visible=true, ZIndex=2})
        end

        if CFG.esp_dist and bx then
            _nd("Text",{Text=("%.0fm"):format(dist), Position=Vector2.new(bx+bw/2,by+bh+2),
                Size=11, Color=Color3.fromRGB(200,200,200), Outline=true, Center=true, Visible=true, ZIndex=2})
        end

        if CFG.esp_hp and bx then
            local h = char:FindFirstChildOfClass("Humanoid")
            if h then
                local r = math.clamp(h.Health/h.MaxHealth,0,1)
                local bx2 = bx - 6
                _nd("Line",{From=Vector2.new(bx2,by),To=Vector2.new(bx2,by+bh),
                    Color=Color3.new(0,0,0),Thickness=3,Visible=true,ZIndex=1})
                _nd("Line",{From=Vector2.new(bx2,by+bh),To=Vector2.new(bx2,by+bh-(bh*r)),
                    Color=Color3.fromRGB(math.floor(255*(1-r)),math.floor(255*r),0),
                    Thickness=2,Visible=true,ZIndex=2})
            end
        end
    end
end

-- ─── AIMBOT ───────────────────────────────────────────────────────────────────
local _jt = 0

local function _closest()
    local center = _cam.ViewportSize / 2
    local best, bd = nil, CFG.aim_fov
    for _, p in ipairs(_P:GetPlayers()) do
        if p == _lp or _smt(p) then continue end
        local char = p.Character
        if not char or not _alive(char) then continue end
        local part = char:FindFirstChild(CFG.aim_target)
        if not part then continue end
        local sp, inv, d = _w2s(part.Position)
        if not inv or d <= 0 then continue end
        local sd = (sp - center).Magnitude
        if sd < bd then bd = sd; best = p end
    end
    return best
end

local function _aimbot(dt)
    if not CFG.aim or not CFG.aim_active then return end
    if not _UIS:IsMouseButtonPressed(CFG.aim_hold) then return end
    local target = _closest()
    if not target then return end
    local char = target.Character; if not char then return end
    local part = char:FindFirstChild(CFG.aim_target); if not part then return end

    _jt = _jt + dt * (3 + math.random() * 2)
    local jp = part.Position + Vector3.new(
        math.sin(_jt * 1.3) * 0.015,
        math.cos(_jt * 0.9) * 0.012, 0
    )
    local cur = _cam.CFrame
    local tgt = CFrame.new(cur.Position, jp)
    local ad  = math.acos(math.clamp(cur.LookVector:Dot(tgt.LookVector),-1,1))
    local sm  = CFG.aim_smooth + math.clamp(ad * 0.3, 0, 0.4)
    _cam.CFrame = cur:Lerp(tgt, math.clamp(sm, 0.05, 0.9))
end

-- ─── FOV CIRCLE ───────────────────────────────────────────────────────────────
local _fc = Drawing.new("Circle")
_fc.Thickness = 1
_fc.Radius    = CFG.aim_fov
_fc.Color     = Color3.fromRGB(255,255,255)
_fc.Filled    = false
_fc.ZIndex    = 10

-- ─── LOOP ─────────────────────────────────────────────────────────────────────
_RS.RenderStepped:Connect(function(dt)
    _cam            = workspace.CurrentCamera
    _fc.Position    = _cam.ViewportSize / 2
    _fc.Visible     = CFG.aim and CFG.aim_active
    _esp()
    _aimbot(dt)
end)

_lp.CharacterAdded:Connect(function()
    _cam = workspace.CurrentCamera
end)
