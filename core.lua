-- core.lua | Roblox LuaU | Solara | v6
-- Evasão: XOR, string split, junk globals, dead code, constant folding, anti-tamper

-- ═══ ANTI-TAMPER ══════════════════════════════════════════════════
local _env_ok = (type(Drawing)=="table" or type(Drawing)=="userdata")
    and type(bit32)=="table" and type(game)=="userdata"
if not _env_ok then return end

-- ═══ STRING UTILS ═════════════════════════════════════════════════
local function _j(...) return table.concat({...}) end
local function _rid(n)
    local c,t="abcdefghijklmnopqrstuvwxyz0123456789",{}
    for i=1,n or 10 do local p=math.random(1,#c); t[i]=c:sub(p,p) end
    return table.concat(t)
end

local _svc={
    _j("Pl","ay","er","s"),
    _j("Ru","nS","er","vi","ce"),
    _j("Us","er","In","pu","tS","er","vi","ce"),
    _j("St","ar","te","rG","ui"),
    _j("Co","re","Gu","i"),
}

-- ═══ JUNK GLOBALS ═════════════════════════════════════════════════
for _=1,24 do rawset(_G,"_".._rid(9),math.random()*9999) end

-- ═══ DEAD CODE ════════════════════════════════════════════════════
if false then
    local _g=game:GetService("HttpService")
    _g:GetAsync("https://example.com")
    Drawing.new("Square").Visible=true
end

-- ═══ CONSTANT FOLDING ═════════════════════════════════════════════
local _FOV_DEF  = bit32.bxor(0xFF,0x69)   -- 150
local _SM_DEF   = 14/100                   -- 0.14
local _DIST_DEF = 10^3                     -- 1000

-- ═══ SERVICES ═════════════════════════════════════════════════════
local _P   = game:GetService(_svc[1])
local _RS  = game:GetService(_svc[2])
local _UIS = game:GetService(_svc[3])
local _SG  = game:GetService(_svc[4])
local _lp  = _P.LocalPlayer
local _cam = workspace.CurrentCamera

-- ═══ CONFIG ═══════════════════════════════════════════════════════
local CFG={
    esp=false, esp_box=false, esp_name=false,
    esp_dist=false, esp_hp=false,
    esp_color=Color3.fromRGB(255,255,255),
    esp_max_dist=_DIST_DEF,

    aim=false,
    aim_toggle=Enum.KeyCode.X,
    aim_hold=Enum.UserInputType.MouseButton2,
    aim_fov=_FOV_DEF,
    aim_smooth=_SM_DEF,       -- 0.0 = snap, 1.0 = muito suave
    aim_target=_j("He","ad"),
    aim_teamcheck=false,

    gui_toggle=Enum.KeyCode.RightShift,
}

-- ═══ STATE ════════════════════════════════════════════════════════
local _pool={}
local _DESTROYED=false
local _pulse_fns={}
local _gui_ref=nil
local _win_ref=nil
local _gui_vis=true
local _t=0

local _fc=Drawing.new("Circle")
_fc.Thickness=1; _fc.Radius=CFG.aim_fov
_fc.Color=Color3.fromRGB(255,255,255)
_fc.Filled=false; _fc.ZIndex=10; _fc.Visible=false

-- ═══ DRAWING POOL ═════════════════════════════════════════════════
local function _nd(tp,props)
    local d=Drawing.new(tp)
    for k,v in pairs(props) do d[k]=v end
    table.insert(_pool,d); return d
end
local function _clr()
    for _,d in ipairs(_pool) do pcall(function() d:Remove() end) end
    _pool={}
end

-- ═══ NEON HELPERS ═════════════════════════════════════════════════
local NW=Color3.fromRGB(255,255,255)
local NR=Color3.fromRGB(255,30,30)
local BG_DARK = Color3.fromRGB(4,4,4)
local BG_ROW  = Color3.fromRGB(8,8,8)
local BG_HDR  = Color3.fromRGB(10,10,10)

local function _stroke(parent,color,thick,trans)
    local s=Instance.new("UIStroke")
    s.Color=color; s.Thickness=thick or 1.5
    s.Transparency=trans or 0
    s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    s.Parent=parent; return s
end
local function _mk_pulse(stroke,base,amp,spd)
    return function(t)
        pcall(function()
            stroke.Transparency=base+math.abs(math.sin(t*spd))*amp
        end)
    end
end
local function _corner(p,r)
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,r or 6); c.Parent=p
end
local function _label(parent,text,size,color,xa,pos,sz,zi,bold)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.Text=text; l.TextSize=size
    l.TextColor3=color
    l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextXAlignment=xa or Enum.TextXAlignment.Left
    if pos then l.Position=pos end
    if sz  then l.Size=sz end
    l.ZIndex=zi or 3; l.Parent=parent
    return l
end

-- ═══ BUILD GUI ════════════════════════════════════════════════════
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

    local win=Instance.new("Frame")
    win.Name="Win"
    win.Size=UDim2.new(0,300,0,10)
    win.Position=UDim2.new(0,24,0.5,-200)
    win.BackgroundColor3=BG_DARK
    win.BorderSizePixel=0
    win.Active=true; win.Draggable=true
    win.ClipsDescendants=false; win.Parent=gui
    _corner(win,8)

    local ws1=_stroke(win,NW,2.5,0)
    local ws2=_stroke(win,NW,5,0.6)
    table.insert(_pulse_fns,_mk_pulse(ws1,0,0.15,1.1))
    table.insert(_pulse_fns,_mk_pulse(ws2,0.4,0.4,1.1))

    local hdr=Instance.new("Frame")
    hdr.Size=UDim2.new(1,0,0,52)
    hdr.BackgroundColor3=BG_HDR
    hdr.BorderSizePixel=0; hdr.ZIndex=2; hdr.Parent=win
    _corner(hdr,8)

    local htop=Instance.new("Frame")
    htop.Size=UDim2.new(1,0,0,2)
    htop.BackgroundColor3=NW
    htop.BorderSizePixel=0; htop.ZIndex=4; htop.Parent=hdr
    local hts=_stroke(htop,NW,3,0.3)
    table.insert(_pulse_fns,_mk_pulse(hts,0.1,0.5,1.4))

    _label(hdr,"TONY COUNTRY",17,NW,
        Enum.TextXAlignment.Center,
        UDim2.new(0,0,0,8),UDim2.new(1,0,0,26),3,true)
    _label(hdr,"✦  ESP  ·  AIMBOT  ✦",9,
        Color3.fromRGB(140,140,140),
        Enum.TextXAlignment.Center,
        UDim2.new(0,0,0,32),UDim2.new(1,0,0,16),3,false)

    local sep=Instance.new("Frame")
    sep.Size=UDim2.new(1,-20,0,1)
    sep.Position=UDim2.new(0,10,0,54)
    sep.BackgroundColor3=NW
    sep.BackgroundTransparency=0.7
    sep.BorderSizePixel=0; sep.ZIndex=2; sep.Parent=win

    local function _sec(text,y)
        local f=Instance.new("Frame")
        f.Size=UDim2.new(1,-20,0,20)
        f.Position=UDim2.new(0,10,0,y)
        f.BackgroundColor3=Color3.fromRGB(12,12,12)
        f.BorderSizePixel=0; f.ZIndex=2; f.Parent=win
        _corner(f,4)
        _stroke(f,NW,1,0.5)
        _label(f,"  "..text,10,NW,
            Enum.TextXAlignment.Left,
            UDim2.new(0,0,0,0),UDim2.new(1,0,1,0),3,true)
    end

    local function _row(text,state,y,cb)
        local row=Instance.new("Frame")
        row.Size=UDim2.new(1,-20,0,28)
        row.Position=UDim2.new(0,10,0,y)
        row.BackgroundColor3=BG_ROW
        row.BorderSizePixel=0; row.ZIndex=2; row.Parent=win
        _corner(row,6)
        local rs=_stroke(row,NW,1,1)

        _label(row,text,11,Color3.fromRGB(200,200,200),
            Enum.TextXAlignment.Left,
            UDim2.new(0,10,0,0),UDim2.new(0.65,0,1,0),3,false)

        local btn=Instance.new("TextButton")
        btn.Size=UDim2.new(0,52,0,20)
        btn.Position=UDim2.new(1,-58,0.5,-10)
        btn.BackgroundColor3=Color3.fromRGB(14,14,14)
        btn.Text="OFF"
        btn.TextColor3=Color3.fromRGB(90,90,90)
        btn.TextSize=11; btn.Font=Enum.Font.GothamBold
        btn.BorderSizePixel=0; btn.ZIndex=3; btn.Parent=row
        _corner(btn,5)
        local bs=_stroke(btn,NW,1.5,1)

        local _st=state; local _pf=nil
        local function _ref()
            if _st then
                btn.BackgroundColor3=Color3.fromRGB(230,230,230)
                btn.TextColor3=Color3.fromRGB(0,0,0); btn.Text="ON"
                bs.Transparency=0; rs.Transparency=0
                if _pf then
                    for i,fn in ipairs(_pulse_fns) do
                        if fn==_pf then table.remove(_pulse_fns,i); break end
                    end
                end
                _pf=_mk_pulse(bs,0,0.4,2.4)
                table.insert(_pulse_fns,_pf)
            else
                btn.BackgroundColor3=Color3.fromRGB(14,14,14)
                btn.TextColor3=Color3.fromRGB(90,90,90); btn.Text="OFF"
                bs.Transparency=1; rs.Transparency=1
                if _pf then
                    for i,fn in ipairs(_pulse_fns) do
                        if fn==_pf then table.remove(_pulse_fns,i); break end
                    end
                    _pf=nil
                end
            end
        end
        _ref()
        btn.MouseButton1Click:Connect(function() _st=not _st; cb(_st); _ref() end)
    end

    local function _fov_slider(y)
        local frame=Instance.new("Frame")
        frame.Size=UDim2.new(1,-20,0,44)
        frame.Position=UDim2.new(0,10,0,y)
        frame.BackgroundColor3=BG_ROW
        frame.BorderSizePixel=0; frame.ZIndex=2; frame.Parent=win
        _corner(frame,6)
        _stroke(frame,NW,1,0.6)

        _label(frame,"  FOV",11,Color3.fromRGB(200,200,200),
            Enum.TextXAlignment.Left,
            UDim2.new(0,0,0,2),UDim2.new(0.4,0,0,18),3,false)

        local val_lbl=Instance.new("TextLabel")
        val_lbl.Size=UDim2.new(0.3,0,0,18)
        val_lbl.Position=UDim2.new(0.7,0,0,2)
        val_lbl.BackgroundTransparency=1
        val_lbl.Text=tostring(CFG.aim_fov)
        val_lbl.TextColor3=NW
        val_lbl.TextSize=11; val_lbl.Font=Enum.Font.GothamBold
        val_lbl.TextXAlignment=Enum.TextXAlignment.Right
        val_lbl.ZIndex=3; val_lbl.Parent=frame

        local track=Instance.new("Frame")
        track.Size=UDim2.new(1,-16,0,4)
        track.Position=UDim2.new(0,8,0,30)
        track.BackgroundColor3=Color3.fromRGB(30,30,30)
        track.BorderSizePixel=0; track.ZIndex=3; track.Parent=frame
        _corner(track,2)

        local fill=Instance.new("Frame")
        fill.Size=UDim2.new(CFG.aim_fov/500,0,1,0)
        fill.BackgroundColor3=NW
        fill.BorderSizePixel=0; fill.ZIndex=4; fill.Parent=track
        _corner(fill,2)
        local fs=_stroke(fill,NW,2,0.3)
        table.insert(_pulse_fns,_mk_pulse(fs,0.1,0.4,1.5))

        local handle=Instance.new("TextButton")
        handle.Size=UDim2.new(0,12,0,12)
        handle.Position=UDim2.new(CFG.aim_fov/500,0,0.5,-6)
        handle.BackgroundColor3=NW
        handle.Text=""; handle.BorderSizePixel=0
        handle.ZIndex=5; handle.Parent=track
        _corner(handle,6)
        _stroke(handle,NW,2,0)

        local dragging=false
        handle.MouseButton1Down:Connect(function() dragging=true end)
        _UIS.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
        end)
        _UIS.InputChanged:Connect(function(i)
            if not dragging then return end
            if i.UserInputType~=Enum.UserInputType.MouseMovement then return end
            local tp=track.AbsolutePosition
            local ts=track.AbsoluteSize
            local rel=math.clamp((i.Position.X-tp.X)/ts.X,0,1)
            local nf=math.max(math.floor(rel*500),10)
            CFG.aim_fov=nf
            _fc.Radius=nf
            val_lbl.Text=tostring(nf)
            fill.Size=UDim2.new(rel,0,1,0)
            handle.Position=UDim2.new(rel,0,0.5,-6)
        end)
    end

    -- layout — sem skeleton
    local Y=60

    _sec("ESP",Y); Y=Y+24
    _row("  ESP Master",   CFG.esp,      Y, function(v) CFG.esp=v end);       Y=Y+32
    _row("  Box (corner)", CFG.esp_box,  Y, function(v) CFG.esp_box=v end);   Y=Y+32
    _row("  Nome",         CFG.esp_name, Y, function(v) CFG.esp_name=v end);  Y=Y+32
    _row("  Distância",    CFG.esp_dist, Y, function(v) CFG.esp_dist=v end);  Y=Y+32
    _row("  HP Bar",       CFG.esp_hp,   Y, function(v) CFG.esp_hp=v end);    Y=Y+36

    _sec("AIMBOT",Y); Y=Y+24
    _row("  Aimbot Master",  CFG.aim,           Y, function(v) CFG.aim=v end);           Y=Y+32
    _row("  Team Check",     CFG.aim_teamcheck, Y, function(v) CFG.aim_teamcheck=v end); Y=Y+36

    _sec("FOV CONTROL",Y); Y=Y+24
    _fov_slider(Y); Y=Y+52

    local info=Instance.new("TextLabel")
    info.Size=UDim2.new(1,-20,0,14)
    info.Position=UDim2.new(0,10,0,Y)
    info.BackgroundTransparency=1
    info.Text="X = toggle aim  ·  RMB (hold) = aim  ·  RShift = hide"
    info.TextColor3=Color3.fromRGB(55,55,55)
    info.TextSize=9; info.Font=Enum.Font.Gotham
    info.TextXAlignment=Enum.TextXAlignment.Center
    info.ZIndex=3; info.Parent=win
    Y=Y+20

    local db=Instance.new("TextButton")
    db.Size=UDim2.new(1,-20,0,30)
    db.Position=UDim2.new(0,10,0,Y)
    db.BackgroundColor3=Color3.fromRGB(14,3,3)
    db.Text="✖  DESTRUCT"
    db.TextColor3=NR
    db.TextSize=13; db.Font=Enum.Font.GothamBold
    db.BorderSizePixel=0; db.ZIndex=3; db.Parent=win
    _corner(db,6)
    local ds=_stroke(db,NR,2,0)
    table.insert(_pulse_fns,_mk_pulse(ds,0,0.6,1.6))
    db.MouseEnter:Connect(function() db.BackgroundColor3=Color3.fromRGB(36,6,6) end)
    db.MouseLeave:Connect(function() db.BackgroundColor3=Color3.fromRGB(14,3,3) end)
    db.MouseButton1Click:Connect(function()
        _DESTROYED=true
        _clr()
        pcall(function() _fc:Remove() end)
        pcall(function() _gui_ref:Destroy() end)
    end)

    win.Size=UDim2.new(0,300,0,Y+44)
    _win_ref=win
end

-- ═══ UTILS ════════════════════════════════════════════════════════
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
                Vector3.new( sz.X, sz.Y, sz.Z),Vector3.new(-sz.X, sz.Y, sz.Z),
                Vector3.new( sz.X,-sz.Y, sz.Z),Vector3.new(-sz.X,-sz.Y, sz.Z),
                Vector3.new( sz.X, sz.Y,-sz.Z),Vector3.new(-sz.X, sz.Y,-sz.Z),
                Vector3.new( sz.X,-sz.Y,-sz.Z),Vector3.new(-sz.X,-sz.Y,-sz.Z),
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

-- ═══ ESP ══════════════════════════════════════════════════════════
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

        if CFG.esp_box and bx then
            local clen=math.min(bw,bh)*0.22
            for _,c in ipairs({
                {{bx,by},{bx+clen,by}},            {{bx,by},{bx,by+clen}},
                {{bx+bw,by},{bx+bw-clen,by}},      {{bx+bw,by},{bx+bw,by+clen}},
                {{bx,by+bh},{bx+clen,by+bh}},      {{bx,by+bh},{bx,by+bh-clen}},
                {{bx+bw,by+bh},{bx+bw-clen,by+bh}},{{bx+bw,by+bh},{bx+bw,by+bh-clen}},
            }) do
                _nd("Line",{From=Vector2.new(c[1][1],c[1][2]),
                    To=Vector2.new(c[2][1],c[2][2]),
                    Color=Color3.new(0,0,0),Thickness=3.5,
                    Transparency=0.5,Visible=true,ZIndex=2})
                _nd("Line",{From=Vector2.new(c[1][1],c[1][2]),
                    To=Vector2.new(c[2][1],c[2][2]),
                    Color=CFG.esp_color,Thickness=1.8,
                    Transparency=0,Visible=true,ZIndex=3})
            end
        end

        if CFG.esp_name and bx then
            _nd("Text",{Text=p.Name,
                Position=Vector2.new(bx+bw/2+1,by-13),
                Size=13,Color=Color3.new(0,0,0),
                Outline=false,Center=true,Visible=true,ZIndex=3})
            _nd("Text",{Text=p.Name,
                Position=Vector2.new(bx+bw/2,by-14),
                Size=13,Color=NW,
                Outline=false,Center=true,Visible=true,ZIndex=4})
        end

        if CFG.esp_dist and bx then
            _nd("Text",{
                Text=("%.0fm"):format(dist),
                Position=Vector2.new(bx+bw/2,by+bh+3),
                Size=11,Color=Color3.fromRGB(190,190,190),
                Outline=true,Center=true,Visible=true,ZIndex=4})
        end

        if CFG.esp_hp and bx then
            local h=char:FindFirstChildOfClass("Humanoid")
            if h then
                local r=math.clamp(h.Health/h.MaxHealth,0,1)
                local bx2=bx-8
                _nd("Line",{From=Vector2.new(bx2,by),To=Vector2.new(bx2,by+bh),
                    Color=Color3.new(0,0,0),Thickness=5,Visible=true,ZIndex=2})
                _nd("Line",{
                    From=Vector2.new(bx2,by+bh),
                    To=Vector2.new(bx2,by+bh-(bh*r)),
                    Color=Color3.fromRGB(math.floor(255*(1-r)),math.floor(255*r),40),
                    Thickness=3,Visible=true,ZIndex=3})
            end
        end
    end
end

-- ═══ AIMBOT v3 ════════════════════════════════════════════════════
--
-- DESIGN:
--   • Sem CameraType.Scriptable — câmera Custom o tempo todo
--   • Target lock: persiste o alvo enquanto ele tiver dentro do FOV
--     e estiver vivo, em vez de recalcular todo frame (evita flicker)
--   • Predição: Kalman-lite — média exponencial da velocidade (EMA)
--     com ganho separado para aceleração, muito mais estável que lerp puro
--   • Smoothing exponencial: alpha = 1 - exp(-k * dt)
--     — independente de framerate, não robótico, gruda gradualmente
--   • Boost de snap perto do alvo: quando o ângulo é < 2°, força alpha
--     alto para não ficar oscilando em volta da head

-- constantes de tuning (não expor no CFG pra não poluir a UI)
local AIM_PRED_GAIN   = 3.0   -- multiplicador de predição (frames à frente)
local AIM_EMA_ALPHA   = 0.25  -- suavização da velocidade estimada (0=lento,1=instantâneo)
local AIM_SNAP_ANGLE  = 0.035 -- rad (~2°): abaixo disso força snap total
local AIM_K_BASE      = 18.0  -- constante exponencial base (maior = mais rápido)

-- estado do lock
local _lock_target  = nil   -- Player travado atualmente
local _lock_lost    = 0     -- tempo (s) desde que perdeu visão (grace period)
local LOCK_GRACE    = 0.12  -- segundos de grace antes de soltar o alvo

-- estado de predição (por alvo — reseta ao trocar)
local _ema_vel      = Vector3.new(0,0,0)
local _last_pos     = nil

local function _in_fov(part)
    local center = _cam.ViewportSize / 2
    local sp, inv, d = _w2s(part.Position)
    if not inv or d <= 0 then return false, 0 end
    local dist_px = (sp - center).Magnitude
    return dist_px <= CFG.aim_fov, dist_px
end

local function _pick_target()
    -- se o alvo travado ainda é válido, mantém
    if _lock_target then
        local char = _lock_target.Character
        local part = char and char:FindFirstChild(CFG.aim_target)
        if part and _alive(char) and not _smt(_lock_target) then
            local ok, _ = _in_fov(part)
            if ok then
                _lock_lost = 0
                return _lock_target
            end
        end
        -- perdeu visão — aplica grace period antes de soltar
        _lock_lost = _lock_lost + (1/60)  -- aproximado; atualizado em _aimbot(dt)
        if _lock_lost < LOCK_GRACE then
            return _lock_target  -- ainda dentro do grace
        end
        -- solta o alvo
        _lock_target = nil
        _lock_lost   = 0
        _ema_vel     = Vector3.new(0,0,0)
        _last_pos    = nil
    end

    -- procura novo alvo mais próximo do centro do FOV
    local center = _cam.ViewportSize / 2
    local best, best_dist = nil, CFG.aim_fov
    for _, p in ipairs(_P:GetPlayers()) do
        if p == _lp or _smt(p) then continue end
        local char = p.Character
        if not char or not _alive(char) then continue end
        local part = char:FindFirstChild(CFG.aim_target)
        if not part then continue end
        local ok, d = _in_fov(part)
        if ok and d < best_dist then
            best_dist = d
            best = p
        end
    end

    if best then
        _lock_target = best
        _lock_lost   = 0
        _ema_vel     = Vector3.new(0,0,0)
        _last_pos    = nil
    end
    return best
end

local function _aimbot(dt)
    if not CFG.aim then
        _lock_target = nil
        _lock_lost   = 0
        _ema_vel     = Vector3.new(0,0,0)
        _last_pos    = nil
        return
    end

    local holding = _UIS:IsMouseButtonPressed(CFG.aim_hold)
    if not holding then
        -- não reseta o lock ao soltar RMB, só para de mover a câmera
        -- (melhora UX: ao apertar de novo já retoma o alvo)
        _lock_lost = _lock_lost + dt
        if _lock_lost >= LOCK_GRACE then
            _lock_target = nil
            _lock_lost   = 0
            _ema_vel     = Vector3.new(0,0,0)
            _last_pos    = nil
        end
        return
    end

    -- atualiza grace com dt real
    if _lock_target then
        local char = _lock_target.Character
        local part = char and char:FindFirstChild(CFG.aim_target)
        if part and _alive(char) then
            local ok, _ = _in_fov(part)
            if ok then _lock_lost = 0
            else        _lock_lost = _lock_lost + dt end
        else
            _lock_lost = _lock_lost + dt
        end
        if _lock_lost >= LOCK_GRACE then
            _lock_target = nil
            _lock_lost   = 0
            _ema_vel     = Vector3.new(0,0,0)
            _last_pos    = nil
        end
    end

    local target = _pick_target()
    if not target then return end

    local char = target.Character; if not char then return end
    local part = char:FindFirstChild(CFG.aim_target); if not part then return end

    -- ── PREDIÇÃO: EMA de velocidade ──────────────────────────────
    -- calcula velocidade real entre frames (mais preciso que AssemblyLinearVelocity
    -- que pode ter jitter de network)
    local cur_pos = part.Position
    if _last_pos then
        local raw_vel = (cur_pos - _last_pos) / math.max(dt, 0.001)
        -- EMA: suaviza a estimativa de velocidade frame a frame
        _ema_vel = _ema_vel + (raw_vel - _ema_vel) * AIM_EMA_ALPHA
    end
    _last_pos = cur_pos

    -- posição predita: posição atual + velocidade suavizada * tempo à frente
    local predicted = cur_pos + _ema_vel * dt * AIM_PRED_GAIN

    -- ── CÂMERA: rotação sem mudar CameraType ─────────────────────
    local cur = _cam.CFrame
    local dir = (predicted - cur.Position)
    if dir.Magnitude < 0.001 then return end
    dir = dir.Unit

    local tgt_cf = CFrame.new(cur.Position, cur.Position + dir)

    -- ângulo entre direção atual e alvo
    local dot = math.clamp(cur.LookVector:Dot(tgt_cf.LookVector), -1, 1)
    local angle = math.acos(dot)   -- rad

    -- smoothing exponencial: alpha = 1 - exp(-k * dt)
    -- k aumenta quando estamos longe (chega rápido), diminui perto (suave)
    -- CFG.aim_smooth: 0 = máximo snap (k alto), 1 = muito suave (k baixo)
    local k_scale = math.clamp(1.0 - CFG.aim_smooth, 0.05, 1.0)
    -- boost de distância: longe do alvo acelera o lock
    local angle_boost = math.clamp(angle * 8.0, 0.0, 3.0)
    local k = AIM_K_BASE * k_scale * (1.0 + angle_boost)
    local alpha = 1.0 - math.exp(-k * dt)

    -- snap forçado quando está quase no alvo (evita oscilação residual)
    if angle < AIM_SNAP_ANGLE then
        alpha = 1.0
    end

    alpha = math.clamp(alpha, 0.0, 1.0)

    pcall(function()
        _cam.CFrame = cur:Lerp(tgt_cf, alpha)
    end)
end

-- ═══ INIT ═════════════════════════════════════════════════════════
_build_gui()

_UIS.InputBegan:Connect(function(input, gpe)
    if gpe or _DESTROYED then return end
    if input.KeyCode == CFG.gui_toggle then
        _gui_vis = not _gui_vis
        if _win_ref then _win_ref.Visible = _gui_vis end
    end
    if input.KeyCode == CFG.aim_toggle then
        CFG.aim = not CFG.aim
        if not CFG.aim then
            _lock_target = nil
            _lock_lost   = 0
            _ema_vel     = Vector3.new(0,0,0)
            _last_pos    = nil
        end
        pcall(function()
            _SG:SetCore("SendNotification",{
                Title="Aimbot",
                Text=CFG.aim and "ATIVADO" or "DESATIVADO",
                Duration=1.5,
            })
        end)
    end
end)

_RS.RenderStepped:Connect(function(dt)
    if _DESTROYED then return end
    _t = _t + dt
    _cam = workspace.CurrentCamera
    for _, fn in ipairs(_pulse_fns) do fn(_t) end
    _fc.Position = _cam.ViewportSize / 2
    _fc.Visible  = CFG.aim
    _esp()
    _aimbot(dt)
end)

_lp.CharacterAdded:Connect(function()
    if _DESTROYED then return end
    _cam        = workspace.CurrentCamera
    _lock_target = nil
    _lock_lost   = 0
    _ema_vel     = Vector3.new(0,0,0)
    _last_pos    = nil
end)
