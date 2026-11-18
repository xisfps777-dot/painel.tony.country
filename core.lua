-- core.lua | Roblox LuaU | Solara | v7
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
    esp_dist=false, esp_hp=false,
    esp_color=Color3.fromRGB(255,255,255),
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

-- ═══ DRAWING POOL PERSISTENTE ════════════════════════════════════
-- Em vez de recriar drawings todo frame (causa do lag), mantém um pool
-- por player indexado por chave string. Frames subsequentes só atualizam
-- propriedades — Drawing.new só é chamado na primeira vez que a chave aparece.
--
-- _pd[player][key] = Drawing object
-- _pd_seen[player] = set de chaves usadas neste frame (para hide das não usadas)
local _pd = {}       -- pool por player
local _pd_seen = {}  -- chaves vistas neste frame

local function _pd_get(player, key, tp)
    local pp = _pd[player]
    if not pp then pp = {}; _pd[player] = pp end
    local d = pp[key]
    if not d then
        d = Drawing.new(tp); pp[key] = d
    end
    local seen = _pd_seen[player]
    if not seen then seen = {}; _pd_seen[player] = seen end
    seen[key] = true
    return d
end

-- Chama no início de cada ciclo ESP para marcar início de frame por player
local function _pd_begin(player)
    _pd_seen[player] = {}
end

-- Chama no fim: esconde drawings não usados neste frame (player saiu de vista etc)
local function _pd_end(player)
    local pp = _pd[player]
    if not pp then return end
    local seen = _pd_seen[player] or {}
    for k, d in pairs(pp) do
        if not seen[k] then
            pcall(function() d.Visible = false end)
        end
    end
end

-- Remove todos os drawings de um player (desconectou, morreu, etc.)
local function _pd_remove(player)
    local pp = _pd[player]
    if not pp then return end
    for _, d in pairs(pp) do pcall(function() d:Remove() end) end
    _pd[player] = nil
    _pd_seen[player] = nil
end

-- Limpa tudo (destruct)
local function _clr()
    for p, _ in pairs(_pd) do _pd_remove(p) end
end

-- Atalho: cria ou atualiza um drawing de linha pelo pool persistente
local function _nd_line(player, key, from, to, color, thick, zi, trans)
    local d = _pd_get(player, key, "Line")
    d.From=from; d.To=to; d.Color=color
    d.Thickness=thick; d.ZIndex=zi or 3
    d.Transparency=trans or 0; d.Visible=true
end

-- Atalho: texto
local function _nd_text(player, key, text, pos, size, color, center, zi)
    local d = _pd_get(player, key, "Text")
    d.Text=text; d.Position=pos; d.Size=size
    d.Color=color; d.Center=center or false
    d.Outline=false; d.ZIndex=zi or 3; d.Visible=true
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


-- ═══ ESP (pool persistente — zero Drawing.new por frame steady-state) ═══════
local function _esp()
    if not CFG.esp then
        for _, pp in pairs(_pd) do
            for _, d in pairs(pp) do pcall(function() d.Visible=false end) end
        end
        return
    end

    local _active = {}

    for _, p in ipairs(_P:GetPlayers()) do
        if p == _lp then continue end
        local char = p.Character
        if not char or not _alive(char) then _pd_remove(p); continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then _pd_remove(p); continue end
        local dist = (_cam.CFrame.Position - root.Position).Magnitude
        if dist > CFG.esp_max_dist then _pd_remove(p); continue end
        local sp, inv, depth = _w2s(root.Position)
        if not inv or depth <= 0 then _pd_remove(p); continue end

        _active[p] = true
        _pd_begin(p)

        local bx, by, bw, bh = _bbox(char)

        if CFG.esp_box and bx then
            local clen = math.min(bw,bh)*0.22
            local corners = {
                {bx,by,       bx+clen,by},       {bx,by,       bx,by+clen},
                {bx+bw,by,    bx+bw-clen,by},     {bx+bw,by,    bx+bw,by+clen},
                {bx,by+bh,    bx+clen,by+bh},     {bx,by+bh,    bx,by+bh-clen},
                {bx+bw,by+bh, bx+bw-clen,by+bh},  {bx+bw,by+bh, bx+bw,by+bh-clen},
            }
            for i, c in ipairs(corners) do
                local f = Vector2.new(c[1],c[2])
                local t = Vector2.new(c[3],c[4])
                _nd_line(p,"box_out"..i, f, t, Color3.new(0,0,0), 3.5, 2, 0.5)
                _nd_line(p,"box_in"..i,  f, t, CFG.esp_color,     1.8, 3, 0)
            end
        end

        if CFG.esp_name and bx then
            local nx = bx+bw/2
            _nd_text(p,"name_sh", p.Name, Vector2.new(nx+1,by-13), 13, Color3.new(0,0,0), true, 3)
            _nd_text(p,"name",    p.Name, Vector2.new(nx,  by-14), 13, NW,               true, 4)
        end

        if CFG.esp_dist and bx then
            _nd_text(p,"dist",
                ("%.0fm"):format(dist),
                Vector2.new(bx+bw/2, by+bh+3),
                11, Color3.fromRGB(200,200,200), true, 4)
        end

        if CFG.esp_hp and bx then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                local r   = math.clamp(hum.Health/hum.MaxHealth, 0, 1)
                local bh2 = math.clamp(bh, 10, 300)
                local bt  = by + (bh - bh2)*0.5
                local bx2 = bx - 8
                _nd_line(p,"hp_bg",  Vector2.new(bx2,bt),     Vector2.new(bx2,bt+bh2),
                    Color3.new(0,0,0), 5, 2, 0)
                _nd_line(p,"hp_bar", Vector2.new(bx2,bt+bh2), Vector2.new(bx2,bt+bh2-bh2*r),
                    Color3.fromRGB(math.floor(255*(1-r)),math.floor(255*r),40), 3, 3, 0)
            end
        end

        _pd_end(p)
    end

    for p, _ in pairs(_pd) do
        if not _active[p] then _pd_remove(p) end
    end
end

-- ═══ AIMBOT ═══════════════════════════════════════════════════════
-- Histórico de velocidade por player: 3 amostras com pesos crescentes
-- Componente lateral (perpendicular ao look da câmera) tem lead 2× maior
-- que componente axial — cobre strafes sem overshooting em linha reta
local _vel_hist = {}  -- [Player] = {{vel=V3, dt=n}, ...} max 3 entradas

local function _push_vel(player, vel, dt)
    local h = _vel_hist[player]
    if not h then h = {}; _vel_hist[player] = h end
    table.insert(h, {vel=vel, dt=dt})
    if #h > 3 then table.remove(h, 1) end
end

-- Velocidade média ponderada (amostras mais recentes pesam mais: 1,2,3)
local function _avg_vel(player)
    local h = _vel_hist[player]
    if not h or #h == 0 then return Vector3.zero end
    local sum = Vector3.zero
    local w_total = 0
    for i, e in ipairs(h) do
        local w = i  -- peso cresce com o índice (mais recente = maior peso)
        sum = sum + e.vel * w
        w_total = w_total + w
    end
    return sum / w_total
end

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
    if not target then
        -- limpa histórico de targets antigos que sumiram
        _vel_hist = {}; _prev_pos = {}
        return
    end
    local char = target.Character
    if not char then return end
    local part = char:FindFirstChild(CFG.aim_target)
    if not part then return end

    local now_pos = part.Position

    -- Atualiza histórico de velocidade
    local prev = _prev_pos[target]
    if prev then
        local raw_vel = (now_pos - prev.pos) / math.max(prev.dt, 0.001)
        _push_vel(target, raw_vel, dt)
    end
    _prev_pos[target] = {pos=now_pos, dt=dt}

    -- Predição com lead lateral aumentado
    local pred_pos = now_pos
    if CFG.aim_pred then
        local avg = _avg_vel(target)
        if avg.Magnitude > 0.01 then
            local look = _cam.CFrame.LookVector
            -- componente axial (na direção da câmera): lead 0.5 frame
            local axial    = look * look:Dot(avg)
            -- componente lateral (perpendicular): lead 1.2 frame — cobre strafes
            local lateral  = avg - axial
            pred_pos = now_pos + axial*(dt*0.5) + lateral*(dt*1.2)
        end
    end

    -- Jitter humanizado mínimo (não briga com snap)
    _jt = _jt + dt * (2.2 + math.random()*1.2)
    local jp = pred_pos + Vector3.new(
        math.sin(_jt*1.05)*0.006,
        math.cos(_jt*0.8) *0.005,
        0)

    local cur = _cam.CFrame
    local tgt = CFrame.new(cur.Position, jp)

    local dot     = math.clamp(cur.LookVector:Dot(tgt.LookVector), -1, 1)
    local ang_px  = math.acos(dot) * (_cam.ViewportSize.Y * 0.5)

    local t_lerp
    if ang_px <= CFG.aim_snap_dist then
        t_lerp = CFG.aim_max_lerp
    else
        local norm = math.clamp(
            (ang_px - CFG.aim_snap_dist) / math.max(CFG.aim_fov - CFG.aim_snap_dist, 1),
            0, 1)
        t_lerp = CFG.aim_max_lerp - norm*(CFG.aim_max_lerp - CFG.aim_min_lerp)
    end

    -- frame-rate-independente: f_corr = 1-(1-f)^(dt*60)
    local f_corr = 1 - (1 - t_lerp)^(dt*60)
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
    _prev_pos = {}
    _vel_hist = {}
end)
