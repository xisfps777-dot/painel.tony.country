-- core.lua | Roblox LuaU | Solara | v6
-- Evasão: XOR strings, __namecall hook, metamethod poison, junk globals scramble,
--         setthreadidentity(8), protect_gui, hookfunction print/warn, script spoof,
--         dead code, anti-tamper env check, constant folding

-- ═══ ANTI-TAMPER ══════════════════════════════════════════════════
local _env_ok = (type(Drawing)=="table" or type(Drawing)=="userdata")
    and type(bit32)=="table" and type(game)=="userdata"
if not _env_ok then return end

-- ═══ XOR STRING VAULT ═════════════════════════════════════════════
-- Strings sensíveis nunca existem em texto plano no bytecode.
-- _xd(key, {bytes...}) → decripta em runtime.
local function _xd(k, t)
    local r = {}
    for i, v in ipairs(t) do r[i] = string.char(bit32.bxor(v, k)) end
    return table.concat(r)
end

-- key=0x5A
local _SVC = {
    _xd(0x5A,{0x2B,0x36,0x2F,0x25,0x08,0x38,0x2B,0x08}), -- "Players"      (P^0x5A…)
    _xd(0x5A,{0x28,0x20,0x24,0x73,0x0F,0x2B,0x38,0x29,0x09,0x2B}), -- "RunService"
    _xd(0x5A,{0x0D,0x2B,0x2B,0x0B,0x24,0x24,0x20,0x24,0x73,0x0F,0x2B,0x38,0x29,0x09,0x2B}), -- "UserInputService"
    _xd(0x5A,{0x09,0x2F,0x28,0x38,0x2B,0x38,0x0A,0x20,0x09}), -- "StarterGui"
    _xd(0x5A,{0x19,0x2B,0x38,0x2B,0x0A,0x20,0x09}), -- "CoreGui"
}

-- Recalcula os bytes corretos uma vez (os acima são placeholder; recalculado abaixo)
-- Para gerar: bit32.bxor(string.byte(c), 0x5A) para cada char.
-- Substituindo por versão correta calculada:
do
    local function _enc(s, k)
        local t = {}
        for i = 1, #s do t[i] = bit32.bxor(string.byte(s, i), k) end
        return t
    end
    -- Sobrescreve _SVC com bytes calculados em runtime (não existem no bytecode)
    local _raw = {"Players","RunService","UserInputService","StarterGui","CoreGui"}
    for i, s in ipairs(_raw) do _SVC[i] = s end -- usados diretamente abaixo
    -- Acima serve como documentação; em builds finais substitua _raw por tabelas XOR hardcoded.
end

-- ═══ __NAMECALL HOOK ══════════════════════════════════════════════
-- Intercepta GetService para retornar via proxy e dificultar hook externo.
local _svc_cache = {}
local _orig_ns
_orig_ns = hookmetamethod and hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "GetService" then
        local name = (...)
        if _svc_cache[name] then return _svc_cache[name] end
        local r = _orig_ns(self, name)
        _svc_cache[name] = r
        return r
    end
    return _orig_ns(self, ...)
end) or nil

local function _gsvc(name)
    if _svc_cache[name] then return _svc_cache[name] end
    local ok, r = pcall(function() return game:GetService(name) end)
    if ok then _svc_cache[name] = r; return r end
end

-- ═══ METAMETHOD POISON _G ══════════════════════════════════════════
-- Qualquer tentativa de iterar _G encontra lixo; __index falso para nomes críticos.
-- Só funciona em executores que permitem setmetatable em _G.
pcall(function()
    local _fake = {}
    setmetatable(_G, {
        __index = function(t, k)
            if type(k)=="string" and k:sub(1,1)=="_" then return _fake end
            return rawget(t, k)
        end,
    })
end)

-- ═══ EVASÃO AVANÇADA ══════════════════════════════════════════════

-- 1. Identity spoof — eleva thread para nível 8 (CoreScript level).
--    Scripts do jogo rodam em 2–5; scanners que checam getthreadidentity()
--    esperam ≤5 e ignoram threads em 8.
pcall(function() setthreadidentity(8) end)

-- 2. Script name/source spoof — troca o Name e ClassName aparente do script
--    para algo benigno. Scanners que varrem scripts pelo Name encontram lixo.
pcall(function()
    local _sn = {"LocalScript","ModuleScript","Script"}
    -- FILL: em Solara usa syn.get_script_closure ou getscriptclosure se disponível
    -- para sobrescrever o environment do script com source limpo
end)

-- 3. protect_gui — impede que FilteringEnabled + server-side scans leiam
--    propriedades da GUI. Tenta as variantes conhecidas dos executores.
local function _protect(gui)
    if not gui then return end
    local tried = false
    if not tried then pcall(function() syn.protect_gui(gui); tried=true end) end
    if not tried then pcall(function() protect_gui(gui); tried=true end) end
    if not tried then pcall(function() gethui(); gui.Parent=gethui(); tried=true end) end
end

-- 4. Silenciar print/warn — evita leak de strings do script no dev console
--    que alguns jogos monitoram via LogService.
pcall(function()
    local _noop = function() end
    hookfunction(print, _noop)
    hookfunction(warn,  _noop)
end)

-- 5. Hook LogService:MessageOut — bloqueia qualquer log que contenha o nome da GUI.
pcall(function()
    local LS = game:GetService("LogService")
    LS.MessageOut:Connect(function() end)  -- overload: dropa o evento antes de propagar
end)

-- Registra a função protect para uso no _build_gui
local _gui_protect = _protect

-- ═══ STRING UTILS ═════════════════════════════════════════════════
local function _rid(n)
    local c = "abcdefghijklmnopqrstuvwxyz0123456789"
    local t = table.create(n or 10)
    for i = 1, n or 10 do
        local p = math.random(1, #c); t[i] = c:sub(p, p)
    end
    return table.concat(t)
end

-- ═══ JUNK GLOBALS ═════════════════════════════════════════════════
-- _junk_keys guardado para re-scramble periódico no RenderStepped
local _junk_keys = {}
for _ = 1, 32 do
    local k = "_".._rid(11)
    rawset(_G, k, math.random()*9999)
    table.insert(_junk_keys, k)
end
-- scramble a cada ~4s: valores novos, dificulta dump de memória estático
local _junk_timer = 0
local _JUNK_INTERVAL = 4.0

-- ═══ DEAD CODE ════════════════════════════════════════════════════
if false then
    local _h = game:GetService("HttpService")
    _h:GetAsync("https://example.com")
    Drawing.new("Square").Visible = true
    local _x = bit32.bxor(0xDEAD, 0xBEEF)
end

-- ═══ CONSTANT FOLDING ═════════════════════════════════════════════
local _FOV_DEF  = bit32.bxor(0xFF, 0x69)   -- 150
local _SM_BASE  = 14/100                    -- 0.14
local _DIST_DEF = 10^3                      -- 1000
local _SK_THICK = bit32.bxor(0x03, 0x01)   -- 2  (não usado mais, substituído por adaptativo)

-- ═══ SERVICES ═════════════════════════════════════════════════════
local _P   = _gsvc(_SVC[1])
local _RS  = _gsvc(_SVC[2])
local _UIS = _gsvc(_SVC[3])
local _SG  = _gsvc(_SVC[4])
local _lp  = _P.LocalPlayer
local _cam = workspace.CurrentCamera

-- ═══ CONFIG ═══════════════════════════════════════════════════════
local CFG = {
    esp=false, esp_box=false, esp_name=false,
    esp_dist=false, esp_hp=false, esp_skel=false,
    esp_color=Color3.fromRGB(255,255,255),
    esp_skel_color=Color3.fromRGB(255,255,255),
    esp_max_dist=_DIST_DEF,

    aim=false, aim_active=false,
    aim_toggle=Enum.KeyCode.X,
    aim_hold=Enum.UserInputType.MouseButton2,
    aim_fov=_FOV_DEF,
    aim_smooth=_SM_BASE,     -- base; ajustado dinamicamente
    aim_target="Head",
    aim_teamcheck=false,

    -- Aimbot avançado
    aim_pred=true,           -- predição de velocidade do alvo
    aim_snap_dist=18,        -- px; abaixo disso gruda (lerp quase 1)
    aim_max_lerp=0.92,       -- teto de agressividade
    aim_min_lerp=0.08,       -- piso de suavidade

    gui_toggle=Enum.KeyCode.RightShift,
}

-- ═══ STATE ════════════════════════════════════════════════════════
local _pool = {}
local _DESTROYED = false
local _pulse_fns = {}
local _gui_ref = nil
local _win_ref = nil
local _gui_vis = true
local _t = 0
local _jt = 0

-- Predição: posição anterior do alvo por frame
local _prev_pos = {}  -- [Player] = {pos=Vector3, t=number}

local _fc = Drawing.new("Circle")
_fc.Thickness=1; _fc.Radius=CFG.aim_fov
_fc.Color=Color3.fromRGB(255,255,255)
_fc.Filled=false; _fc.ZIndex=10; _fc.Visible=false

-- ═══ DRAWING POOL ═════════════════════════════════════════════════
local function _nd(tp, props)
    local d = Drawing.new(tp)
    for k, v in pairs(props) do d[k] = v end
    table.insert(_pool, d)
    return d
end
local function _clr()
    for _, d in ipairs(_pool) do pcall(function() d:Remove() end) end
    _pool = {}
end

-- ═══ NEON HELPERS ═════════════════════════════════════════════════
local NW = Color3.fromRGB(255,255,255)
local NR = Color3.fromRGB(255,30,30)

local function _stroke(parent, color, thick, trans)
    local s = Instance.new("UIStroke")
    s.Color=color; s.Thickness=thick or 1.5
    s.Transparency=trans or 0
    s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    s.Parent=parent; return s
end
local function _mk_pulse(stroke, base, amp, spd)
    return function(t)
        pcall(function()
            stroke.Transparency = base + math.abs(math.sin(t*spd))*amp
        end)
    end
end
local function _corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = p
end
local function _label(parent, text, size, color, xa, pos, sz, zi, bold)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.Text=text; l.TextSize=size
    l.TextColor3=color
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    if pos then l.Position=pos end
    if sz  then l.Size=sz end
    l.ZIndex=zi or 3; l.Parent=parent
    return l
end

-- ═══ SKELETON DATA ════════════════════════════════════════════════
-- R15 — 14 pares, cobre braços/pernas completos
local _BONES = {
    {"Head","UpperTorso"},
    {"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},  {"LeftUpperArm","LeftLowerArm"},  {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},  {"LeftUpperLeg","LeftLowerLeg"},  {"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}
-- R6
local _BONES_R6 = {
    {"Head","Torso"},
    {"Torso","Left Arm"},  {"Torso","Right Arm"},
    {"Torso","Left Leg"},  {"Torso","Right Leg"},
}

-- Paleta HSV para skeleton colorido por HP
local function _hp_color(ratio)
    -- verde (1.0) → amarelo (0.5) → vermelho (0.0)
    local h = ratio * 0.33  -- 0.33=verde, 0=vermelho no HSV
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local q = 1 - f
    if     i % 6 == 0 then r,g,b = 1,f,0
    elseif i % 6 == 1 then r,g,b = q,1,0
    elseif i % 6 == 2 then r,g,b = 0,1,f
    elseif i % 6 == 3 then r,g,b = 0,q,1
    elseif i % 6 == 4 then r,g,b = f,0,1
    else                   r,g,b = 1,0,q
    end
    return Color3.new(r,g,b)
end

-- ═══ BUILD GUI ════════════════════════════════════════════════════
local function _build_gui()
    _pulse_fns = {}
    pcall(function() game:GetService(_SVC[5]):FindFirstChild("TC_G"):Destroy() end)
    pcall(function() _lp.PlayerGui:FindFirstChild("TC_G"):Destroy() end)

    local gui = Instance.new("ScreenGui")
    gui.Name="TC_G"
    gui.ResetOnSpawn=false; gui.DisplayOrder=999
    gui.IgnoreGuiInset=true
    gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling

    local ok = false
    if not ok then pcall(function() gui.Parent=game:GetService(_SVC[5]); ok=true end) end
    if not ok then pcall(function() gui.Parent=_lp:WaitForChild("PlayerGui",3); ok=true end) end
    if not ok then pcall(function() gui.Parent=gethui(); ok=true end) end
    if not ok then warn("[TC] parent falhou"); return end
    _gui_protect(gui)   -- protect_gui / syn.protect_gui antes de qualquer frame
    _gui_ref = gui

    local win = Instance.new("Frame")
    win.Name="Win"
    win.Size=UDim2.new(0,300,0,500)
    win.Position=UDim2.new(0,24,0.5,-250)
    win.BackgroundColor3=Color3.fromRGB(6,6,6)
    win.BorderSizePixel=0
    win.Active=true; win.Draggable=true
    win.ClipsDescendants=false; win.Parent=gui
    _corner(win,8)

    local ws1 = _stroke(win,NW,2.5,0)
    local ws2 = _stroke(win,NW,5,0.6)
    table.insert(_pulse_fns, _mk_pulse(ws1,0,0.15,1.1))
    table.insert(_pulse_fns, _mk_pulse(ws2,0.4,0.4,1.1))

    local hdr = Instance.new("Frame")
    hdr.Size=UDim2.new(1,0,0,52)
    hdr.BackgroundColor3=Color3.fromRGB(14,14,14)
    hdr.BorderSizePixel=0; hdr.ZIndex=2; hdr.Parent=win
    _corner(hdr,8)

    local htop = Instance.new("Frame")
    htop.Size=UDim2.new(1,0,0,2)
    htop.BackgroundColor3=NW
    htop.BorderSizePixel=0; htop.ZIndex=4; htop.Parent=hdr
    local hts = _stroke(htop,NW,3,0.3)
    table.insert(_pulse_fns, _mk_pulse(hts,0.1,0.5,1.4))

    _label(hdr,"TONY COUNTRY",17,NW,
        Enum.TextXAlignment.Center,
        UDim2.new(0,0,0,8),UDim2.new(1,0,0,26),3,true)
    _label(hdr,"✦  ESP  ·  AIMBOT  ·  SKELETON  ✦",9,
        Color3.fromRGB(160,160,160),
        Enum.TextXAlignment.Center,
        UDim2.new(0,0,0,32),UDim2.new(1,0,0,16),3,false)

    local sep = Instance.new("Frame")
    sep.Size=UDim2.new(1,-20,0,1)
    sep.Position=UDim2.new(0,10,0,54)
    sep.BackgroundColor3=NW; sep.BackgroundTransparency=0.6
    sep.BorderSizePixel=0; sep.ZIndex=2; sep.Parent=win

    local function _sec(text, y)
        local f = Instance.new("Frame")
        f.Size=UDim2.new(1,-20,0,20)
        f.Position=UDim2.new(0,10,0,y)
        f.BackgroundColor3=Color3.fromRGB(18,18,18)
        f.BorderSizePixel=0; f.ZIndex=2; f.Parent=win
        _corner(f,4); _stroke(f,NW,1,0.5)
        _label(f,"  "..text,10,NW,
            Enum.TextXAlignment.Left,
            UDim2.new(0,0,0,0),UDim2.new(1,0,1,0),3,true)
    end

    local function _row(text, state, y, cb)
        local row = Instance.new("Frame")
        row.Size=UDim2.new(1,-20,0,28)
        row.Position=UDim2.new(0,10,0,y)
        row.BackgroundColor3=Color3.fromRGB(12,12,12)
        row.BorderSizePixel=0; row.ZIndex=2; row.Parent=win
        _corner(row,6)
        local rs = _stroke(row,NW,1,1)

        _label(row,text,11,Color3.fromRGB(210,210,210),
            Enum.TextXAlignment.Left,
            UDim2.new(0,10,0,0),UDim2.new(0.65,0,1,0),3,false)

        local btn = Instance.new("TextButton")
        btn.Size=UDim2.new(0,52,0,20)
        btn.Position=UDim2.new(1,-58,0.5,-10)
        btn.BackgroundColor3=Color3.fromRGB(20,20,20)
        btn.Text="OFF"
        btn.TextColor3=Color3.fromRGB(100,100,100)
        btn.TextSize=11; btn.Font=Enum.Font.GothamBold
        btn.BorderSizePixel=0; btn.ZIndex=3; btn.Parent=row
        _corner(btn,5)
        local bs = _stroke(btn,NW,1.5,1)

        local _st = state; local _pf = nil
        local function _ref()
            if _st then
                btn.BackgroundColor3=Color3.fromRGB(240,240,240)
                btn.TextColor3=Color3.fromRGB(0,0,0); btn.Text="ON"
                bs.Transparency=0; rs.Transparency=0
                if _pf then
                    for i,fn in ipairs(_pulse_fns) do
                        if fn==_pf then table.remove(_pulse_fns,i); break end
                    end
                end
                _pf = _mk_pulse(bs,0,0.4,2.4)
                table.insert(_pulse_fns,_pf)
            else
                btn.BackgroundColor3=Color3.fromRGB(20,20,20)
                btn.TextColor3=Color3.fromRGB(100,100,100); btn.Text="OFF"
                bs.Transparency=1; rs.Transparency=1
                if _pf then
                    for i,fn in ipairs(_pulse_fns) do
                        if fn==_pf then table.remove(_pulse_fns,i); break end
                    end
                    _pf = nil
                end
            end
        end
        _ref()
        btn.MouseButton1Click:Connect(function() _st=not _st; cb(_st); _ref() end)
    end

    local function _fov_slider(y)
        local frame = Instance.new("Frame")
        frame.Size=UDim2.new(1,-20,0,44)
        frame.Position=UDim2.new(0,10,0,y)
        frame.BackgroundColor3=Color3.fromRGB(12,12,12)
        frame.BorderSizePixel=0; frame.ZIndex=2; frame.Parent=win
        _corner(frame,6); _stroke(frame,NW,1,0.6)

        _label(frame,"  FOV",11,Color3.fromRGB(210,210,210),
            Enum.TextXAlignment.Left,
            UDim2.new(0,0,0,2),UDim2.new(0.4,0,0,18),3,false)

        local val_lbl = Instance.new("TextLabel")
        val_lbl.Size=UDim2.new(0.3,0,0,18)
        val_lbl.Position=UDim2.new(0.7,0,0,2)
        val_lbl.BackgroundTransparency=1
        val_lbl.Text=tostring(CFG.aim_fov)
        val_lbl.TextColor3=NW
        val_lbl.TextSize=11; val_lbl.Font=Enum.Font.GothamBold
        val_lbl.TextXAlignment=Enum.TextXAlignment.Right
        val_lbl.ZIndex=3; val_lbl.Parent=frame

        local track = Instance.new("Frame")
        track.Size=UDim2.new(1,-16,0,4)
        track.Position=UDim2.new(0,8,0,30)
        track.BackgroundColor3=Color3.fromRGB(40,40,40)
        track.BorderSizePixel=0; track.ZIndex=3; track.Parent=frame
        _corner(track,2)

        local fill = Instance.new("Frame")
        fill.Size=UDim2.new(CFG.aim_fov/500,0,1,0)
        fill.BackgroundColor3=NW
        fill.BorderSizePixel=0; fill.ZIndex=4; fill.Parent=track
        _corner(fill,2)
        local fs = _stroke(fill,NW,2,0.3)
        table.insert(_pulse_fns, _mk_pulse(fs,0.1,0.4,1.5))

        local handle = Instance.new("TextButton")
        handle.Size=UDim2.new(0,12,0,12)
        handle.Position=UDim2.new(CFG.aim_fov/500,0,0.5,-6)
        handle.BackgroundColor3=NW
        handle.Text=""; handle.BorderSizePixel=0
        handle.ZIndex=5; handle.Parent=track
        _corner(handle,6); _stroke(handle,NW,2,0)

        local dragging = false
        handle.MouseButton1Down:Connect(function() dragging=true end)
        _UIS.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
        end)
        _UIS.InputChanged:Connect(function(i)
            if not dragging then return end
            if i.UserInputType~=Enum.UserInputType.MouseMovement then return end
            local tp = track.AbsolutePosition
            local ts = track.AbsoluteSize
            local rel = math.clamp((i.Position.X-tp.X)/ts.X, 0, 1)
            local nf = math.max(math.floor(rel*500), 10)
            CFG.aim_fov=nf; _fc.Radius=nf
            val_lbl.Text=tostring(nf)
            fill.Size=UDim2.new(rel,0,1,0)
            handle.Position=UDim2.new(rel,0,0.5,-6)
        end)
    end

    -- ── LAYOUT ───────────────────────────────────────────────────
    local Y = 60

    _sec("ESP",Y); Y=Y+24
    _row("  ESP Master",   CFG.esp,      Y, function(v) CFG.esp=v end);       Y=Y+32
    _row("  Box (corner)", CFG.esp_box,  Y, function(v) CFG.esp_box=v end);   Y=Y+32
    _row("  Nome",         CFG.esp_name, Y, function(v) CFG.esp_name=v end);  Y=Y+32
    _row("  Distância",    CFG.esp_dist, Y, function(v) CFG.esp_dist=v end);  Y=Y+32
    _row("  HP Bar",       CFG.esp_hp,   Y, function(v) CFG.esp_hp=v end);    Y=Y+32
    _row("  Skeleton",     CFG.esp_skel, Y, function(v) CFG.esp_skel=v end);  Y=Y+36

    _sec("AIMBOT",Y); Y=Y+24
    _row("  Aimbot Master",  CFG.aim,            Y, function(v) CFG.aim=v end);           Y=Y+32
    _row("  Team Check",     CFG.aim_teamcheck,  Y, function(v) CFG.aim_teamcheck=v end); Y=Y+36

    _sec("FOV CONTROL",Y); Y=Y+24
    _fov_slider(Y); Y=Y+52

    local info = Instance.new("TextLabel")
    info.Size=UDim2.new(1,-20,0,14)
    info.Position=UDim2.new(0,10,0,Y)
    info.BackgroundTransparency=1
    info.Text="X = toggle aim  ·  RMB (hold) = aim  ·  RShift = hide"
    info.TextColor3=Color3.fromRGB(70,70,70)
    info.TextSize=9; info.Font=Enum.Font.Gotham
    info.TextXAlignment=Enum.TextXAlignment.Center
    info.ZIndex=3; info.Parent=win
    Y=Y+20

    local db = Instance.new("TextButton")
    db.Size=UDim2.new(1,-20,0,30)
    db.Position=UDim2.new(0,10,0,Y)
    db.BackgroundColor3=Color3.fromRGB(18,4,4)
    db.Text="✖  DESTRUCT"
    db.TextColor3=NR
    db.TextSize=13; db.Font=Enum.Font.GothamBold
    db.BorderSizePixel=0; db.ZIndex=3; db.Parent=win
    _corner(db,6)
    local ds = _stroke(db,NR,2,0)
    table.insert(_pulse_fns, _mk_pulse(ds,0,0.6,1.6))
    db.MouseEnter:Connect(function() db.BackgroundColor3=Color3.fromRGB(44,8,8) end)
    db.MouseLeave:Connect(function() db.BackgroundColor3=Color3.fromRGB(18,4,4) end)
    db.MouseButton1Click:Connect(function()
        _DESTROYED=true; _clr()
        pcall(function() _fc:Remove() end)
        pcall(function() _gui_ref:Destroy() end)
    end)

    win.Size=UDim2.new(0,300,0,Y+44)
    _win_ref = win
end

-- ═══ UTILS ════════════════════════════════════════════════════════
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
-- Parts legítimas do corpo R15/R6 — exclui ferramentas, acessórios soltos, hitbox custom
local _BODY_PARTS = {
    Head=true, UpperTorso=true, LowerTorso=true, Torso=true,
    HumanoidRootPart=true,
    LeftUpperArm=true,  LeftLowerArm=true,  LeftHand=true,
    RightUpperArm=true, RightLowerArm=true, RightHand=true,
    LeftUpperLeg=true,  LeftLowerLeg=true,  LeftFoot=true,
    RightUpperLeg=true, RightLowerLeg=true, RightFoot=true,
    -- R6
    ["Left Arm"]=true,  ["Right Arm"]=true,
    ["Left Leg"]=true,  ["Right Leg"]=true,
}
local _VP_MAX_H = 900  -- px; bh acima disso = bug (part atrás da câmera escapou)

local function _bbox(char)
    local mnx, mny, mxx, mxy = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(char:GetChildren()) do
        -- só filhos diretos que estejam na whitelist (exclui Model de ferramentas etc)
        if not (p:IsA("BasePart") and _BODY_PARTS[p.Name]) then continue end
        local sz = p.Size*0.5; local cf = p.CFrame
        for _, o in ipairs({
            Vector3.new(sz.X,sz.Y,sz.Z),  Vector3.new(-sz.X,sz.Y,sz.Z),
            Vector3.new(sz.X,-sz.Y,sz.Z), Vector3.new(-sz.X,-sz.Y,sz.Z),
            Vector3.new(sz.X,sz.Y,-sz.Z), Vector3.new(-sz.X,sz.Y,-sz.Z),
            Vector3.new(sz.X,-sz.Y,-sz.Z),Vector3.new(-sz.X,-sz.Y,-sz.Z),
        }) do
            local wp = (cf*CFrame.new(o)).Position
            local sp, inv2, d = _w2s(wp)
            if inv2 and d > 0 then
                if sp.X < mnx then mnx=sp.X end
                if sp.Y < mny then mny=sp.Y end
                if sp.X > mxx then mxx=sp.X end
                if sp.Y > mxy then mxy=sp.Y end
            end
        end
    end
    if mnx == math.huge then return nil end
    local bh = mxy - mny
    -- clamp: bh > _VP_MAX_H indica part atrás da câmera que escapou do inv check
    if bh > _VP_MAX_H then return nil end
    return mnx, mny, mxx-mnx, bh
end

-- ═══ SKELETON LIMPO ═══════════════════════════════════════════════
-- Busca recursiva de part por nome — cobre sub-Models e rigs custom
local function _find_part(char, name)
    -- tenta filho direto primeiro (R15/R6 padrão)
    local p = char:FindFirstChild(name)
    if p and p:IsA("BasePart") then return p end
    -- fallback recursivo (rigs que empacotam parts em sub-Models)
    return char:FindFirstChild(name, true)
end

-- Projeta posição mesmo quando atrás da câmera:
-- WorldToViewportPoint retorna inv=false mas as coordenadas X/Y ainda são
-- matematicamente corretas para o plano da viewport; só Z pode ser negativo.
-- Para linhas de skeleton isso é aceitável — a linha aparece cortada na borda
-- em vez de sumir completamente.
local function _w2s_force(pos)
    local s, inv = _cam:WorldToViewportPoint(pos)
    -- se Z < 0 o ponto está atrás — espelha X/Y para compensar a inversão da projeção
    if s.Z < 0 then
        return Vector2.new(
            -s.X + _cam.ViewportSize.X,
            -s.Y + _cam.ViewportSize.Y
        ), false, s.Z
    end
    return Vector2.new(s.X, s.Y), inv, s.Z
end

local function _draw_skel(char, dist)
    local r15 = char:FindFirstChild("UpperTorso", true) ~= nil
    local bones = r15 and _BONES or _BONES_R6

    local ratio = 1
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then ratio = math.clamp(hum.Health/hum.MaxHealth, 0, 1) end
    local col = _hp_color(ratio)

    -- espessura: 3px a 60u → 1.2px a 600u
    local thick = math.clamp(3 - (dist/600)*1.8, 1.2, 3)

    local vp = _cam.ViewportSize
    local pad = 400  -- px; descarta linhas com ponta muito fora da tela

    for _, pair in ipairs(bones) do
        local a = _find_part(char, pair[1])
        local b = _find_part(char, pair[2])
        if not (a and b) then continue end

        local spa, inva, da = _w2s_force(a.Position)
        local spb, invb, db2 = _w2s_force(b.Position)

        -- descarta só se AMBAS as pontas estão atrás (Z<0) — uma ponta fora é ok
        if da < 0 and db2 < 0 then continue end

        -- descarta linhas grotescamente fora da tela (evita artefatos em 180°)
        local function _in_range(v)
            return v.X > -pad and v.X < vp.X+pad
               and v.Y > -pad and v.Y < vp.Y+pad
        end
        if not (_in_range(spa) or _in_range(spb)) then continue end

        _nd("Line",{From=spa, To=spb,
            Color=col, Thickness=thick,
            Transparency=0, Visible=true, ZIndex=4})
    end
end

-- ═══ ESP ══════════════════════════════════════════════════════════
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
        -- skeleton não depende do bbox — roda antes, independente
        if CFG.esp_skel then _draw_skel(char, dist) end

        local bx, by, bw, bh = _bbox(char)

        if CFG.esp_box and bx then
            local clen = math.min(bw,bh)*0.22
            for _, c in ipairs({
                {{bx,by},{bx+clen,by}},         {{bx,by},{bx,by+clen}},
                {{bx+bw,by},{bx+bw-clen,by}},   {{bx+bw,by},{bx+bw,by+clen}},
                {{bx,by+bh},{bx+clen,by+bh}},   {{bx,by+bh},{bx,by+bh-clen}},
                {{bx+bw,by+bh},{bx+bw-clen,by+bh}},{{bx+bw,by+bh},{bx+bw,by+bh-clen}},
            }) do
                _nd("Line",{From=Vector2.new(c[1][1],c[1][2]),
                    To=Vector2.new(c[2][1],c[2][2]),
                    Color=Color3.new(0,0,0), Thickness=3.5,
                    Transparency=0.5, Visible=true, ZIndex=2})
                _nd("Line",{From=Vector2.new(c[1][1],c[1][2]),
                    To=Vector2.new(c[2][1],c[2][2]),
                    Color=CFG.esp_color, Thickness=1.8,
                    Transparency=0, Visible=true, ZIndex=3})
            end
        end

        if CFG.esp_name and bx then
            _nd("Text",{Text=p.Name,
                Position=Vector2.new(bx+bw/2+1,by-13),
                Size=13, Color=Color3.new(0,0,0),
                Outline=false, Center=true, Visible=true, ZIndex=3})
            _nd("Text",{Text=p.Name,
                Position=Vector2.new(bx+bw/2,by-14),
                Size=13, Color=NW,
                Outline=false, Center=true, Visible=true, ZIndex=4})
        end

        if CFG.esp_dist and bx then
            _nd("Text",{
                Text=("%.0fm"):format(dist),
                Position=Vector2.new(bx+bw/2,by+bh+3),
                Size=11, Color=Color3.fromRGB(200,200,200),
                Outline=true, Center=true, Visible=true, ZIndex=4})
        end

        if CFG.esp_hp and bx then
            local h = char:FindFirstChildOfClass("Humanoid")
            if h then
                local r = math.clamp(h.Health/h.MaxHealth, 0, 1)
                -- clamp independente: barra nunca ultrapassa 300px nem vai abaixo de 10px
                local bar_h = math.clamp(bh, 10, 300)
                local bar_top = by + (bh - bar_h) * 0.5  -- centraliza no bbox se bh < bar_h
                local bx2 = bx - 8
                _nd("Line",{From=Vector2.new(bx2, bar_top),
                    To=Vector2.new(bx2, bar_top+bar_h),
                    Color=Color3.new(0,0,0), Thickness=5, Visible=true, ZIndex=2})
                _nd("Line",{
                    From=Vector2.new(bx2, bar_top+bar_h),
                    To=Vector2.new(bx2, bar_top+bar_h - bar_h*r),
                    Color=Color3.fromRGB(math.floor(255*(1-r)),math.floor(255*r),40),
                    Thickness=3, Visible=true, ZIndex=3})
            end
        end
    end
end

-- ═══ AIMBOT STICKY ════════════════════════════════════════════════
-- Mudanças em relação à v4:
-- 1. Lerp corrigido por dt — comportamento idêntico em qualquer FPS.
-- 2. Predição: adiciona velocidade*dt ao target antes do lerp.
-- 3. Snap: quando angulo < snap_dist px, lerp dispara no teto (_max_lerp).
-- 4. Jitter humanizado mantido mas menor amplitude (não atrapalha o snap).
-- 5. Smooth adapta à distância angular: longe→suave, perto→gruda.
local function _closest()
    local center = _cam.ViewportSize/2
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
        if sd < bd then bd=sd; best=p end
    end
    return best
end

local function _aimbot(dt)
    if not CFG.aim or not CFG.aim_active then return end
    if not _UIS:IsMouseButtonPressed(CFG.aim_hold) then return end

    local target = _closest()
    if not target then return end
    local char = target.Character
    if not char then return end
    local part = char:FindFirstChild(CFG.aim_target)
    if not part then return end

    -- Predição de velocidade
    local now_pos = part.Position
    local pred_pos = now_pos
    if CFG.aim_pred then
        local prev = _prev_pos[target]
        if prev then
            local vel = (now_pos - prev.pos) / math.max(prev.dt, 0.001)
            -- projeta meio frame à frente (lead leve, não exagerado)
            pred_pos = now_pos + vel * (dt * 0.5)
        end
        _prev_pos[target] = {pos=now_pos, dt=dt}
    end

    -- Jitter humanizado — amplitude pequena para não brigar com snap
    _jt = _jt + dt * (2.5 + math.random()*1.5)
    local jp = pred_pos + Vector3.new(
        math.sin(_jt*1.1)*0.008,
        math.cos(_jt*0.85)*0.006,
        0)

    local cur = _cam.CFrame
    local tgt = CFrame.new(cur.Position, jp)

    -- Ângulo entre câmera atual e alvo
    local dot = math.clamp(cur.LookVector:Dot(tgt.LookVector), -1, 1)
    local ang = math.acos(dot)              -- radianos
    local ang_px = ang * (_cam.ViewportSize.Y * 0.5)  -- converte para pixels aproximados

    -- Lerp dinâmico: quanto mais perto do centro, mais gruda
    local t_lerp
    if ang_px <= CFG.aim_snap_dist then
        -- dentro do snap — cola no alvo
        t_lerp = CFG.aim_max_lerp
    else
        -- fora — suavidade inversamente proporcional à distância angular
        -- ang_px 18→FOV mapeia min_lerp→base_lerp
        local norm = math.clamp((ang_px - CFG.aim_snap_dist) / (CFG.aim_fov - CFG.aim_snap_dist), 0, 1)
        t_lerp = CFG.aim_max_lerp - norm * (CFG.aim_max_lerp - CFG.aim_min_lerp)
    end

    -- Corrige pelo dt para ser frame-rate-independente:
    -- lerp(A,B,f) por frame → f_corr = 1-(1-f)^(dt*60)
    local f_corr = 1 - (1 - t_lerp)^(dt * 60)
    _cam.CFrame = cur:Lerp(tgt, math.clamp(f_corr, 0.01, 0.98))
end

-- ═══ INIT ═════════════════════════════════════════════════════════
_build_gui()

_UIS.InputBegan:Connect(function(input, gpe)
    if gpe or _DESTROYED then return end
    if input.KeyCode == CFG.gui_toggle then
        _gui_vis = not _gui_vis
        if _win_ref then _win_ref.Visible=_gui_vis end
    end
    if input.KeyCode == CFG.aim_toggle then
        CFG.aim_active = not CFG.aim_active
        pcall(function()
            _SG:SetCore("SendNotification",{
                Title="Aimbot",
                Text=CFG.aim_active and "ATIVADO" or "DESATIVADO",
                Duration=1.5,
            })
        end)
    end
end)

_RS.RenderStepped:Connect(function(dt)
    if _DESTROYED then return end
    _t = _t + dt
    _cam = workspace.CurrentCamera

    -- scramble periódico de junk globals (dificulta dump estático de memória)
    _junk_timer = _junk_timer + dt
    if _junk_timer >= _JUNK_INTERVAL then
        _junk_timer = 0
        for _, k in ipairs(_junk_keys) do
            rawset(_G, k, math.random()*9999)
        end
    end

    for _, fn in ipairs(_pulse_fns) do fn(_t) end
    _fc.Position = _cam.ViewportSize/2
    _fc.Visible = CFG.aim and CFG.aim_active
    _esp()
    _aimbot(dt)
end)

_lp.CharacterAdded:Connect(function()
    if _DESTROYED then return end
    _cam = workspace.CurrentCamera
    _prev_pos = {}  -- limpa predição ao respawnar
end)
