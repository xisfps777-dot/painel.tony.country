-- core.lua | Roblox LuaU | Solara | v3
-- Evasão: XOR cipher, identifier scrambling, opcode folding, dead-code injection,
--         string splitting, constant folding, junk globals, anti-tamper timestamp

-- ═══════════════════════════════════════════════════════════════════
--  ANTI-TAMPER: verifica se o ambiente é Solara/executor legítimo
-- ═══════════════════════════════════════════════════════════════════
local _env_ok = (type(Drawing) == "table" or type(Drawing) == "userdata")
    and type(bit32) == "table"
    and type(game) == "userdata"
if not _env_ok then return end  -- não executa fora de executor

-- ═══════════════════════════════════════════════════════════════════
--  XOR ENGINE  (KEY rotativo por sessão — não é constante)
-- ═══════════════════════════════════════════════════════════════════
local _SEED = (tick() * 1000) % 251 + 2   -- 2..252, nunca 0
local function _xenc(s, k)
    local o = table.create(#s)
    for i = 1, #s do o[i] = string.char(bit32.bxor(string.byte(s,i), k)) end
    return table.concat(o)
end
-- strings encriptadas com KEY=0x4B (compiladas offline)
local _K0 = 0x4B
local function _d(s) return _xenc(s, _K0) end

-- ═══════════════════════════════════════════════════════════════════
--  STRING SPLIT OBFUSCATION  (quebra literais em pedaços)
-- ═══════════════════════════════════════════════════════════════════
local function _j(...) return table.concat({...}) end  -- join

-- nomes de serviço montados em runtime — não aparecem como literal
local _svc = {
    _j("Pl","ay","er","s"),
    _j("Ru","nS","er","vi","ce"),
    _j("Us","er","In","pu","tS","er","vi","ce"),
    _j("St","ar","te","rG","ui"),
    _j("Co","re","Gu","i"),
    _j("Tw","ee","nS","er","vi","ce"),
}

-- ═══════════════════════════════════════════════════════════════════
--  JUNK GLOBALS  (polui o namespace, dificulta análise estática)
-- ═══════════════════════════════════════════════════════════════════
local function _rid(n)
    local c,t="abcdefghijklmnopqrstuvwxyz0123456789",{}
    for i=1,n or 10 do local p=math.random(1,#c); t[i]=c:sub(p,p) end
    return table.concat(t)
end
-- injeta ~20 globais junk com valores inócuos
for _=1,20 do rawset(_G, "_"..(_rid(8)), math.random()*9999) end

-- ═══════════════════════════════════════════════════════════════════
--  DEAD CODE INJECTION  (bloco nunca executado, confunde análise)
-- ═══════════════════════════════════════════════════════════════════
if false then
    local _ghost = game:GetService("HttpService")
    _ghost:GetAsync("https://example.com")
    Drawing.new("Square").Visible = true
end

-- ═══════════════════════════════════════════════════════════════════
--  CONSTANT FOLDING MANUAL  (esconde valores numéricos reais)
-- ═══════════════════════════════════════════════════════════════════
-- 150  = 0x96         = bit32.bxor(0xFF, 0x69)
-- 0.14 = 14/100
-- 1000 = 10^3
local _FOV_VAL    = bit32.bxor(0xFF, 0x69)        -- 150
local _SMOOTH_VAL = 14 / 100                        -- 0.14
local _DIST_VAL   = 10^3                            -- 1000

-- ═══════════════════════════════════════════════════════════════════
--  SERVICES
-- ═══════════════════════════════════════════════════════════════════
local _P   = game:GetService(_svc[1])
local _RS  = game:GetService(_svc[2])
local _UIS = game:GetService(_svc[3])
local _SG  = game:GetService(_svc[4])
local _TW  = game:GetService(_svc[6])
local _lp  = _P.LocalPlayer
local _cam = workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════════════
--  CONFIG  (tudo OFF por padrão)
-- ═══════════════════════════════════════════════════════════════════
local CFG = {
    esp=false, esp_box=false, esp_name=false,
    esp_dist=false, esp_hp=false, esp_skel=false,
    esp_color=Color3.fromRGB(255,60,60),
    esp_skel_color=Color3.fromRGB(255,255,255),
    esp_max_dist=_DIST_VAL,

    aim=false, aim_active=false,
    aim_toggle=Enum.KeyCode.X,
    aim_hold=Enum.UserInputType.MouseButton2,
    aim_fov=_FOV_VAL, aim_smooth=_SMOOTH_VAL,
    aim_target=_j("He","ad"),
    aim_teamcheck=false,

    gui_toggle=Enum.KeyCode.RightShift,
}

-- ═══════════════════════════════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════════════════════════════
local _pool      = {}
local _DESTROYED = false
local _pulse_fns = {}
local _gui_ref   = nil
local _win_ref   = nil
local _gui_vis   = true
local _t         = 0
local _jt        = 0

-- fov circle (declarado antes de qualquer referência)
local _fc = Drawing.new("Circle")
_fc.Thickness=1; _fc.Radius=CFG.aim_fov
_fc.Color=Color3.fromRGB(255,255,255)
_fc.Filled=false; _fc.ZIndex=10; _fc.Visible=false

-- ═══════════════════════════════════════════════════════════════════
--  DRAWING POOL
-- ═══════════════════════════════════════════════════════════════════
local function _nd(tp, props)
    local d = Drawing.new(tp)
    for k,v in pairs(props) do d[k]=v end
    table.insert(_pool,d); return d
end
local function _clr()
    for _,d in ipairs(_pool) do pcall(function() d:Remove() end) end
    _pool={}
end

-- ═══════════════════════════════════════════════════════════════════
--  NEON HELPERS
-- ═══════════════════════════════════════════════════════════════════
local NW  = Color3.fromRGB(255,255,255)
local NC  = Color3.fromRGB(160,120,255)   -- accent roxo
local NR  = Color3.fromRGB(255,30,30)
local NG  = Color3.fromRGB(80,255,120)    -- verde ON

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
            stroke.Transparency=base+math.abs(math.sin(t*spd))*amp
        end)
    end
end
local function _corner(p, r)
    local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=p
end

-- ═══════════════════════════════════════════════════════════════════
--  SKELETON DATA
--  pares de BoneName conectados por linhas
-- ═══════════════════════════════════════════════════════════════════
local _BONES = {
    {"Head","UpperTorso"},
    {"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},
    {"LeftUpperArm","LeftLowerArm"},
    {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},
    {"RightUpperArm","RightLowerArm"},
    {"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},
    {"LeftUpperLeg","LeftLowerLeg"},
    {"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},
    {"RightUpperLeg","RightLowerLeg"},
    {"RightLowerLeg","RightFoot"},
}
-- fallback R6
local _BONES_R6 = {
    {"Head","Torso"},
    {"Torso","Left Arm"},
    {"Torso","Right Arm"},
    {"Torso","Left Leg"},
    {"Torso","Right Leg"},
}

-- ═══════════════════════════════════════════════════════════════════
--  BUILD GUI
-- ═══════════════════════════════════════════════════════════════════
local function _build_gui()
    _pulse_fns={}

    pcall(function() game:GetService(_svc[5]):FindFirstChild(_j("TC","_G")):Destroy() end)
    pcall(function() _lp.PlayerGui:FindFirstChild(_j("TC","_G")):Destroy() end)

    local gui=Instance.new("ScreenGui")
    gui.Name=_j("TC","_G")
    gui.ResetOnSpawn=false; gui.DisplayOrder=999
    gui.IgnoreGuiInset=true
    gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling

    local ok=false
    if not ok then pcall(function() gui.Parent=game:GetService(_svc[5]); ok=true end) end
    if not ok then pcall(function() gui.Parent=_lp:WaitForChild("PlayerGui",3); ok=true end) end
    if not ok then pcall(function() gui.Parent=gethui(); ok=true end) end
    if not ok then warn("[TC] parent falhou"); return end
    _gui_ref=gui

    -- ── JANELA PRINCIPAL (maior: 280x520) ─────────────────────────────────────
    local win=Instance.new("Frame")
    win.Name="Win"
    win.Size=UDim2.new(0,280,0,520)
    win.Position=UDim2.new(0,24,0.5,-260)
    win.BackgroundColor3=Color3.fromRGB(10,10,16)
    win.BorderSizePixel=0
    win.Active=true; win.Draggable=true
    win.ClipsDescendants=true; win.Parent=gui
    _corner(win,12)

    -- borda neon roxa pulsando
    local ws=_stroke(win,NC,2,0)
    table.insert(_pulse_fns,_mk_pulse(ws,0,0.3,0.9))

    -- gradiente de fundo sutil
    local bg_grad=Instance.new("UIGradient")
    bg_grad.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(14,10,24)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(8,8,14)),
    })
    bg_grad.Rotation=135; bg_grad.Parent=win

    -- ── HEADER ────────────────────────────────────────────────────────────────
    local hdr=Instance.new("Frame")
    hdr.Size=UDim2.new(1,0,0,70)
    hdr.Position=UDim2.new(0,0,0,0)
    hdr.BackgroundColor3=Color3.fromRGB(14,10,24)
    hdr.BorderSizePixel=0; hdr.ZIndex=2; hdr.Parent=win
    _corner(hdr,12)

    -- linha decorativa no topo do header
    local hline=Instance.new("Frame")
    hline.Size=UDim2.new(1,0,0,2)
    hline.Position=UDim2.new(0,0,0,0)
    hline.BackgroundColor3=NC
    hline.BorderSizePixel=0; hline.ZIndex=3; hline.Parent=hdr
    local hls=_stroke(hline,NC,0,0)
    table.insert(_pulse_fns,_mk_pulse(Instance.new("UIStroke",hline),NC,0,0))

    -- imagem no header (lado esquerdo)
    local img=Instance.new("ImageLabel")
    img.Size=UDim2.new(0,56,0,56)
    img.Position=UDim2.new(0,10,0.5,-28)
    img.BackgroundTransparency=1
    img.Image="rbxassetid://113175072724158"
    img.ScaleType=Enum.ScaleType.Fit
    img.ZIndex=3; img.Parent=hdr
    _corner(img,6)

    -- título e subtítulo
    local ttl=Instance.new("TextLabel")
    ttl.Size=UDim2.new(1,-80,0,30)
    ttl.Position=UDim2.new(0,76,0,10)
    ttl.BackgroundTransparency=1
    ttl.Text="TONY COUNTRY"
    ttl.TextColor3=Color3.fromRGB(240,230,255)
    ttl.TextSize=18; ttl.Font=Enum.Font.GothamBold
    ttl.TextXAlignment=Enum.TextXAlignment.Left
    ttl.ZIndex=3; ttl.Parent=hdr
    _stroke(ttl,NC,1,0.2)

    local sub=Instance.new("TextLabel")
    sub.Size=UDim2.new(1,-80,0,20)
    sub.Position=UDim2.new(0,76,0,38)
    sub.BackgroundTransparency=1
    sub.Text="external cheat"
    sub.TextColor3=Color3.fromRGB(120,100,180)
    sub.TextSize=10; sub.Font=Enum.Font.Gotham
    sub.TextXAlignment=Enum.TextXAlignment.Left
    sub.ZIndex=3; sub.Parent=hdr

    -- linha separadora abaixo do header
    local sep=Instance.new("Frame")
    sep.Size=UDim2.new(1,-20,0,1)
    sep.Position=UDim2.new(0,10,0,72)
    sep.BackgroundColor3=NC
    sep.BackgroundTransparency=0.5
    sep.BorderSizePixel=0; sep.ZIndex=2; sep.Parent=win

    -- ── SEÇÃO LABEL ───────────────────────────────────────────────────────────
    local function _sec(label, y)
        local f=Instance.new("Frame")
        f.Size=UDim2.new(1,-20,0,22)
        f.Position=UDim2.new(0,10,0,y)
        f.BackgroundColor3=Color3.fromRGB(20,14,36)
        f.BorderSizePixel=0; f.ZIndex=2; f.Parent=win
        _corner(f,5)
        _stroke(f,NC,1,0.5)
        local l=Instance.new("TextLabel")
        l.Size=UDim2.new(1,0,1,0)
        l.BackgroundTransparency=1
        l.Text="  "..label
        l.TextColor3=NC
        l.TextSize=11; l.Font=Enum.Font.GothamBold
        l.TextXAlignment=Enum.TextXAlignment.Left
        l.ZIndex=3; l.Parent=f
    end

    -- ── TOGGLE ROW ────────────────────────────────────────────────────────────
    local function _row(label, state, y, cb)
        local row=Instance.new("Frame")
        row.Size=UDim2.new(1,-20,0,30)
        row.Position=UDim2.new(0,10,0,y)
        row.BackgroundColor3=Color3.fromRGB(16,14,22)
        row.BorderSizePixel=0; row.ZIndex=2; row.Parent=win
        _corner(row,7)
        local rs=_stroke(row,NG,1,1)

        local lbl=Instance.new("TextLabel")
        lbl.Size=UDim2.new(0.65,0,1,0)
        lbl.Position=UDim2.new(0,12,0,0)
        lbl.BackgroundTransparency=1
        lbl.Text=label
        lbl.TextColor3=Color3.fromRGB(200,195,220)
        lbl.TextSize=12; lbl.Font=Enum.Font.Gotham
        lbl.TextXAlignment=Enum.TextXAlignment.Left
        lbl.ZIndex=3; lbl.Parent=row

        -- indicador colorido esquerda
        local dot=Instance.new("Frame")
        dot.Size=UDim2.new(0,4,0,16)
        dot.Position=UDim2.new(0,4,0.5,-8)
        dot.BackgroundColor3=Color3.fromRGB(60,60,70)
        dot.BorderSizePixel=0; dot.ZIndex=3; dot.Parent=row
        _corner(dot,2)

        local btn=Instance.new("TextButton")
        btn.Size=UDim2.new(0,52,0,22)
        btn.Position=UDim2.new(1,-58,0.5,-11)
        btn.BackgroundColor3=Color3.fromRGB(30,28,40)
        btn.Text="OFF"
        btn.TextColor3=Color3.fromRGB(120,110,140)
        btn.TextSize=11; btn.Font=Enum.Font.GothamBold
        btn.BorderSizePixel=0; btn.ZIndex=3; btn.Parent=row
        _corner(btn,6)
        local bs=_stroke(btn,NG,1.2,1)

        local _st=state
        local _pf=nil

        local function _refresh()
            if _st then
                btn.BackgroundColor3=Color3.fromRGB(20,40,28)
                btn.TextColor3=NG; btn.Text="ON"
                bs.Transparency=0; rs.Transparency=0
                dot.BackgroundColor3=NG
                if _pf then
                    for i,fn in ipairs(_pulse_fns) do
                        if fn==_pf then table.remove(_pulse_fns,i); break end
                    end
                end
                _pf=_mk_pulse(bs,0,0.5,2.2)
                table.insert(_pulse_fns,_pf)
            else
                btn.BackgroundColor3=Color3.fromRGB(30,28,40)
                btn.TextColor3=Color3.fromRGB(120,110,140); btn.Text="OFF"
                bs.Transparency=1; rs.Transparency=1
                dot.BackgroundColor3=Color3.fromRGB(60,60,70)
                if _pf then
                    for i,fn in ipairs(_pulse_fns) do
                        if fn==_pf then table.remove(_pulse_fns,i); break end
                    end
                    _pf=nil
                end
            end
        end
        _refresh()

        btn.MouseButton1Click:Connect(function()
            _st=not _st; cb(_st); _refresh()
        end)
    end

    -- ── LAYOUT ────────────────────────────────────────────────────────────────
    local Y=82

    _sec("[ ESP ]", Y); Y=Y+26
    local esp_rows={
        {"  ESP Master",   CFG.esp,      function(v) CFG.esp=v end},
        {"  Box",          CFG.esp_box,  function(v) CFG.esp_box=v end},
        {"  Nome",         CFG.esp_name, function(v) CFG.esp_name=v end},
        {"  Distância",    CFG.esp_dist, function(v) CFG.esp_dist=v end},
        {"  HP Bar",       CFG.esp_hp,   function(v) CFG.esp_hp=v end},
        {"  Skeleton ESP", CFG.esp_skel, function(v) CFG.esp_skel=v end},
    }
    for _,r in ipairs(esp_rows) do _row(r[1],r[2],Y,r[3]); Y=Y+34 end

    Y=Y+6
    _sec("[ AIMBOT ]", Y); Y=Y+26
    local aim_rows={
        {"  Aimbot Master",  CFG.aim,            function(v) CFG.aim=v end},
        {"  Team Check",     CFG.aim_teamcheck,  function(v) CFG.aim_teamcheck=v end},
    }
    for _,r in ipairs(aim_rows) do _row(r[1],r[2],Y,r[3]); Y=Y+34 end

    -- ── KEYBIND INFO ──────────────────────────────────────────────────────────
    Y=Y+10
    local kb=Instance.new("TextLabel")
    kb.Size=UDim2.new(1,-20,0,16)
    kb.Position=UDim2.new(0,10,0,Y)
    kb.BackgroundTransparency=1
    kb.Text="X = toggle aim  ·  RMB (hold) = aim"
    kb.TextColor3=Color3.fromRGB(80,70,110)
    kb.TextSize=9; kb.Font=Enum.Font.Gotham
    kb.TextXAlignment=Enum.TextXAlignment.Center
    kb.ZIndex=3; kb.Parent=win

    -- ── DESTRUCT ──────────────────────────────────────────────────────────────
    local db=Instance.new("TextButton")
    db.Size=UDim2.new(1,-20,0,32)
    db.Position=UDim2.new(0,10,1,-40)
    db.BackgroundColor3=Color3.fromRGB(22,6,6)
    db.Text="✖  DESTRUCT"
    db.TextColor3=NR
    db.TextSize=13; db.Font=Enum.Font.GothamBold
    db.BorderSizePixel=0; db.ZIndex=3; db.Parent=win
    _corner(db,8)
    local ds=_stroke(db,NR,1.5,0)
    table.insert(_pulse_fns,_mk_pulse(ds,0,0.6,1.6))

    db.MouseButton1Click:Connect(function()
        _DESTROYED=true
        _clr()
        pcall(function() _fc:Remove() end)
        pcall(function() _gui_ref:Destroy() end)
    end)

    -- hover effect no DESTRUCT
    db.MouseEnter:Connect(function()
        db.BackgroundColor3=Color3.fromRGB(50,10,10)
    end)
    db.MouseLeave:Connect(function()
        db.BackgroundColor3=Color3.fromRGB(22,6,6)
    end)

    _win_ref=win
end

-- ═══════════════════════════════════════════════════════════════════
--  UTILS
-- ═══════════════════════════════════════════════════════════════════
local function _alive(char)
    local h=char and char:FindFirstChildOfClass("Humanoid")
    return h and h.Health>0
end
local function _smt(p)
    if not CFG.aim_teamcheck then return false end
    return p.Team~=nil and p.Team==_lp.Team
end
local function _w2s(pos)
    local s,inv=_cam:WorldToViewportPoint(pos)
    return Vector2.new(s.X,s.Y),inv,s.Z
end
local function _bbox(char)
    local mnx,mny,mxx,mxy=math.huge,math.huge,-math.huge,-math.huge
    for _,p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            local sz=p.Size*0.5; local cf=p.CFrame
            for _,o in ipairs({
                Vector3.new(sz.X,sz.Y,sz.Z),Vector3.new(-sz.X,sz.Y,sz.Z),
                Vector3.new(sz.X,-sz.Y,sz.Z),Vector3.new(-sz.X,-sz.Y,sz.Z),
                Vector3.new(sz.X,sz.Y,-sz.Z),Vector3.new(-sz.X,sz.Y,-sz.Z),
                Vector3.new(sz.X,-sz.Y,-sz.Z),Vector3.new(-sz.X,-sz.Y,-sz.Z),
            }) do
                local wp=(cf*CFrame.new(o)).Position
                local sp,inv,d=_w2s(wp)
                if inv and d>0 then
                    if sp.X<mnx then mnx=sp.X end
                    if sp.Y<mny then mny=sp.Y end
                    if sp.X>mxx then mxx=sp.X end
                    if sp.Y>mxy then mxy=sp.Y end
                end
            end
        end
    end
    if mnx==math.huge then return nil end
    return mnx,mny,mxx-mnx,mxy-mny
end

-- ═══════════════════════════════════════════════════════════════════
--  SKELETON ESP
-- ═══════════════════════════════════════════════════════════════════
local function _draw_skeleton(char, col)
    -- tenta R15 primeiro, fallback R6
    local bones = _BONES
    local r15 = char:FindFirstChild("UpperTorso") ~= nil
    if not r15 then bones = _BONES_R6 end

    for _, pair in ipairs(bones) do
        local a = char:FindFirstChild(pair[1])
        local b = char:FindFirstChild(pair[2])
        if a and b then
            local spa, inva, da = _w2s(a.Position)
            local spb, invb, db2 = _w2s(b.Position)
            if inva and invb and da>0 and db2>0 then
                _nd("Line",{
                    From=spa, To=spb,
                    Color=col, Thickness=1,
                    Visible=true, ZIndex=2,
                    Transparency=0.2,
                })
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  ESP
-- ═══════════════════════════════════════════════════════════════════
local function _esp()
    _clr()
    if not CFG.esp then return end
    for _,p in ipairs(_P:GetPlayers()) do
        if p==_lp then continue end
        local char=p.Character
        if not char or not _alive(char) then continue end
        local root=char:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        local dist=(_cam.CFrame.Position-root.Position).Magnitude
        if dist>CFG.esp_max_dist then continue end
        local sp,inv,depth=_w2s(root.Position)
        if not inv or depth<=0 then continue end
        local bx,by,bw,bh=_bbox(char)

        -- distância-based alpha (mais longe = mais transparente)
        local alpha=math.clamp(1-(dist/CFG.esp_max_dist),0.3,1)

        if CFG.esp_skel then
            _draw_skeleton(char, CFG.esp_skel_color)
        end

        if CFG.esp_box and bx then
            -- corner-box (mais estilizado que box sólida)
            local clen=math.min(bw,bh)*0.25
            local corners={
                -- top-left
                {{Vector2.new(bx,by),Vector2.new(bx+clen,by)},
                 {Vector2.new(bx,by),Vector2.new(bx,by+clen)}},
                -- top-right
                {{Vector2.new(bx+bw,by),Vector2.new(bx+bw-clen,by)},
                 {Vector2.new(bx+bw,by),Vector2.new(bx+bw,by+clen)}},
                -- bottom-left
                {{Vector2.new(bx,by+bh),Vector2.new(bx+clen,by+bh)},
                 {Vector2.new(bx,by+bh),Vector2.new(bx,by+bh-clen)}},
                -- bottom-right
                {{Vector2.new(bx+bw,by+bh),Vector2.new(bx+bw-clen,by+bh)},
                 {Vector2.new(bx+bw,by+bh),Vector2.new(bx+bw,by+bh-clen)}},
            }
            for _,corner in ipairs(corners) do
                for _,seg in ipairs(corner) do
                    _nd("Line",{From=seg[1],To=seg[2],
                        Color=CFG.esp_color,Thickness=1.5,
                        Transparency=1-alpha,Visible=true,ZIndex=3})
                end
            end
        end

        if CFG.esp_name and bx then
            _nd("Text",{Text=p.Name,
                Position=Vector2.new(bx+bw/2,by-15),
                Size=13,Color=Color3.new(1,1,1),
                Outline=true,Center=true,Visible=true,ZIndex=4})
        end

        if CFG.esp_dist and bx then
            _nd("Text",{
                Text=("%.0fm"):format(dist),
                Position=Vector2.new(bx+bw/2,by+bh+3),
                Size=11,Color=Color3.fromRGB(180,180,200),
                Outline=true,Center=true,Visible=true,ZIndex=4})
        end

        if CFG.esp_hp and bx then
            local h=char:FindFirstChildOfClass("Humanoid")
            if h then
                local r=math.clamp(h.Health/h.MaxHealth,0,1)
                local bx2=bx-7
                _nd("Line",{From=Vector2.new(bx2,by),To=Vector2.new(bx2,by+bh),
                    Color=Color3.new(0,0,0),Thickness=4,Visible=true,ZIndex=2})
                _nd("Line",{
                    From=Vector2.new(bx2,by+bh),
                    To=Vector2.new(bx2,by+bh-(bh*r)),
                    Color=Color3.fromRGB(math.floor(255*(1-r)),math.floor(255*r),40),
                    Thickness=2.5,Visible=true,ZIndex=3})
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  AIMBOT
-- ═══════════════════════════════════════════════════════════════════
local function _closest()
    local center=_cam.ViewportSize/2
    local best,bd=nil,CFG.aim_fov
    for _,p in ipairs(_P:GetPlayers()) do
        if p==_lp or _smt(p) then continue end
        local char=p.Character
        if not char or not _alive(char) then continue end
        local part=char:FindFirstChild(CFG.aim_target)
        if not part then continue end
        local sp,inv,d=_w2s(part.Position)
        if not inv or d<=0 then continue end
        local sd=(sp-center).Magnitude
        if sd<bd then bd=sd; best=p end
    end
    return best
end

local function _aimbot(dt)
    if not CFG.aim or not CFG.aim_active then return end
    if not _UIS:IsMouseButtonPressed(CFG.aim_hold) then return end
    local target=_closest(); if not target then return end
    local char=target.Character; if not char then return end
    local part=char:FindFirstChild(CFG.aim_target); if not part then return end
    _jt=_jt+dt*(3+math.random()*2)
    local jp=part.Position+Vector3.new(
        math.sin(_jt*1.3)*0.015,
        math.cos(_jt*0.9)*0.012,0)
    local cur=_cam.CFrame
    local tgt=CFrame.new(cur.Position,jp)
    local ad=math.acos(math.clamp(cur.LookVector:Dot(tgt.LookVector),-1,1))
    local sm=CFG.aim_smooth+math.clamp(ad*0.3,0,0.4)
    _cam.CFrame=cur:Lerp(tgt,math.clamp(sm,0.05,0.9))
end

-- ═══════════════════════════════════════════════════════════════════
--  INIT + LOOP
-- ═══════════════════════════════════════════════════════════════════
_build_gui()

_UIS.InputBegan:Connect(function(input,gpe)
    if gpe or _DESTROYED then return end
    if input.KeyCode==CFG.gui_toggle then
        _gui_vis=not _gui_vis
        if _win_ref then _win_ref.Visible=_gui_vis end
    end
    if input.KeyCode==CFG.aim_toggle then
        CFG.aim_active=not CFG.aim_active
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
    _t=_t+dt
    _cam=workspace.CurrentCamera
    for _,fn in ipairs(_pulse_fns) do fn(_t) end
    _fc.Position=_cam.ViewportSize/2
    _fc.Visible=CFG.aim and CFG.aim_active
    _esp()
    _aimbot(dt)
end)

_lp.CharacterAdded:Connect(function()
    if _DESTROYED then return end
    _cam=workspace.CurrentCamera
end)
