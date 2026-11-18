--- core.lua | Roblox LuaU | Solara | v7
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
local _FOV_DEF  = bit32.bxor(0xFF,0x69)
local _SM_DEF   = 14/100
local _DIST_DEF = 10^3

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
    aim_smooth=_SM_DEF,
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

-- ═══ CORES ════════════════════════════════════════════════════════
local NW  = Color3.fromRGB(255,255,255)
local NR  = Color3.fromRGB(255,30,30)
-- azul neon igual ao painel de referência
local NEON      = Color3.fromRGB(255,255,255)
local NEON_DARK = Color3.fromRGB(180,180,180)
local BG_WIN    = Color3.fromRGB(5,5,5)      -- azul muito escuro
local BG_HDR    = Color3.fromRGB(10,10,10)
local BG_ROW    = Color3.fromRGB(8,8,8)
local BG_SEC    = Color3.fromRGB(12,12,12)

-- ═══ HELPERS ══════════════════════════════════════════════════════
local function _corner(p,r)
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,r or 6); c.Parent=p
end

-- glow triplo só para botões ON e DESTRUCT
local function _glow_stroke(parent, color, thick1, thick2, thick3)
    local s1=Instance.new("UIStroke")
    s1.Color=color; s1.Thickness=thick1 or 1.5; s1.Transparency=0
    s1.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s1.Parent=parent
    local s2=Instance.new("UIStroke")
    s2.Color=color; s2.Thickness=thick2 or 4; s2.Transparency=0.45
    s2.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s2.Parent=parent
    local s3=Instance.new("UIStroke")
    s3.Color=color; s3.Thickness=thick3 or 10; s3.Transparency=0.72
    s3.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s3.Parent=parent
    return s1, s2, s3
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

    -- ── JANELA ───────────────────────────────────────────────────
    local win=Instance.new("Frame")
    win.Name="Win"
    win.Size=UDim2.new(0,300,0,10)
    win.Position=UDim2.new(0,24,0.5,-200)
    win.BackgroundColor3=BG_WIN
    win.BorderSizePixel=0
    win.Active=true; win.Draggable=true
    win.ClipsDescendants=false; win.Parent=gui
    _corner(win,10)

    -- borda simples, sem brilho
    local _ws=Instance.new("UIStroke")
    _ws.Color=Color3.fromRGB(30,30,30); _ws.Thickness=1; _ws.Transparency=0
    _ws.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; _ws.Parent=win

    -- ── HEADER ───────────────────────────────────────────────────
    local hdr=Instance.new("Frame")
    hdr.Size=UDim2.new(1,0,0,60)
    hdr.BackgroundColor3=BG_HDR
    hdr.BorderSizePixel=0; hdr.ZIndex=2; hdr.Parent=win
    _corner(hdr,10)

    -- título sem glow
    local title=_label(hdr,"TONY COUNTRY",19,NW,
        Enum.TextXAlignment.Center,
        UDim2.new(0,0,0,10),UDim2.new(1,0,0,28),4,true)
    title.TextStrokeTransparency=1

    local sub=_label(hdr,"BY BARRETO",9,
        Color3.fromRGB(160,160,160),
        Enum.TextXAlignment.Center,
        UDim2.new(0,0,0,38),UDim2.new(1,0,0,16),3,false)
    sub.TextStrokeTransparency=1

    -- separador simples
    local sep=Instance.new("Frame")
    sep.Size=UDim2.new(1,-16,0,1)
    sep.Position=UDim2.new(0,8,0,62)
    sep.BackgroundColor3=Color3.fromRGB(35,35,35)
    sep.BackgroundTransparency=0
    sep.BorderSizePixel=0; sep.ZIndex=3; sep.Parent=win

    -- ── SECTION LABEL ────────────────────────────────────────────
    local function _sec(text,y)
        local f=Instance.new("Frame")
        f.Size=UDim2.new(1,-16,0,22)
        f.Position=UDim2.new(0,8,0,y)
        f.BackgroundColor3=BG_SEC
        f.BorderSizePixel=0; f.ZIndex=2; f.Parent=win
        _corner(f,5)
        local _fs=Instance.new("UIStroke")
        _fs.Color=Color3.fromRGB(35,35,35); _fs.Thickness=1; _fs.Transparency=0
        _fs.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; _fs.Parent=f
        _label(f,"  "..text,11,NW,
            Enum.TextXAlignment.Left,
            UDim2.new(0,0,0,0),UDim2.new(1,0,1,0),3,true)
    end

    -- ── TOGGLE ROW ───────────────────────────────────────────────
    local function _row(text,state,y,cb)
        local row=Instance.new("Frame")
        row.Size=UDim2.new(1,-16,0,30)
        row.Position=UDim2.new(0,8,0,y)
        row.BackgroundColor3=BG_ROW
        row.BorderSizePixel=0; row.ZIndex=2; row.Parent=win
        _corner(row,7)
        local _rs=Instance.new("UIStroke")
        _rs.Color=Color3.fromRGB(35,35,35); _rs.Thickness=1; _rs.Transparency=0
        _rs.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; _rs.Parent=row

        _label(row,text,12,Color3.fromRGB(210,210,210),
            Enum.TextXAlignment.Left,
            UDim2.new(0,12,0,0),UDim2.new(0.6,0,1,0),3,false)

        local btn=Instance.new("TextButton")
        btn.Size=UDim2.new(0,58,0,22)
        btn.Position=UDim2.new(1,-64,0.5,-11)
        btn.BackgroundColor3=Color3.fromRGB(14,14,14)
        btn.Text="OFF"
        btn.TextColor3=Color3.fromRGB(90,90,90)
        btn.TextSize=12; btn.Font=Enum.Font.GothamBold
        btn.BorderSizePixel=0; btn.ZIndex=4; btn.Parent=row
        _corner(btn,6)
        local bs1,bs2,bs3=_glow_stroke(btn,NEON,1,4,10)
        bs1.Transparency=1; bs2.Transparency=1; bs3.Transparency=1
        local bpf=nil

        local _st=state
        local function _ref()
            if _st then
                -- ON: botão branco brilhante, glow full
                btn.BackgroundColor3=NW
                btn.TextColor3=Color3.fromRGB(0,0,0); btn.Text="ON"
                -- glow só no botão
                bs1.Transparency=0; bs2.Transparency=0.3; bs3.Transparency=0.6
                -- pulse no botão
                if bpf then
                    for i,fn in ipairs(_pulse_fns) do
                        if fn==bpf then table.remove(_pulse_fns,i); break end
                    end
                end
                bpf=function(t)
                    pcall(function()
                        local v=math.abs(math.sin(t*2.2))
                        bs2.Transparency=0.2+v*0.3
                        bs3.Transparency=0.5+v*0.3
                    end)
                end
                table.insert(_pulse_fns,bpf)
            else
                -- OFF: escuro, sem glow
                btn.BackgroundColor3=Color3.fromRGB(14,14,14)
                btn.TextColor3=Color3.fromRGB(90,90,90); btn.Text="OFF"
                bs1.Transparency=1; bs2.Transparency=1; bs3.Transparency=1
                if bpf then
                    for i,fn in ipairs(_pulse_fns) do
                        if fn==bpf then table.remove(_pulse_fns,i); break end
                    end
                end
                bpf=nil
            end
        end
        _ref()
        btn.MouseButton1Click:Connect(function() _st=not _st; cb(_st); _ref() end)
    end

    -- ── FOV SLIDER ───────────────────────────────────────────────
    local function _fov_slider(y)
        local frame=Instance.new("Frame")
        frame.Size=UDim2.new(1,-16,0,46)
        frame.Position=UDim2.new(0,8,0,y)
        frame.BackgroundColor3=BG_ROW
        frame.BorderSizePixel=0; frame.ZIndex=2; frame.Parent=win
        _corner(frame,7)
        local _sfs=Instance.new("UIStroke")
        _sfs.Color=Color3.fromRGB(35,35,35); _sfs.Thickness=1; _sfs.Transparency=0
        _sfs.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; _sfs.Parent=frame

        _label(frame,"  FOV",12,Color3.fromRGB(210,210,210),
            Enum.TextXAlignment.Left,
            UDim2.new(0,0,0,2),UDim2.new(0.4,0,0,20),3,false)

        local val_lbl=Instance.new("TextLabel")
        val_lbl.Size=UDim2.new(0.3,0,0,20)
        val_lbl.Position=UDim2.new(0.7,0,0,2)
        val_lbl.BackgroundTransparency=1
        val_lbl.Text=tostring(CFG.aim_fov)
        val_lbl.TextColor3=NW
        val_lbl.TextSize=12; val_lbl.Font=Enum.Font.GothamBold
        val_lbl.TextXAlignment=Enum.TextXAlignment.Right
        val_lbl.TextStrokeTransparency=1
        val_lbl.ZIndex=3; val_lbl.Parent=frame

        local track=Instance.new("Frame")
        track.Size=UDim2.new(1,-18,0,5)
        track.Position=UDim2.new(0,9,0,32)
        track.BackgroundColor3=Color3.fromRGB(25,25,25)
        track.BorderSizePixel=0; track.ZIndex=3; track.Parent=frame
        _corner(track,3)

        local fill=Instance.new("Frame")
        fill.Size=UDim2.new(CFG.aim_fov/500,0,1,0)
        fill.BackgroundColor3=NEON
        fill.BorderSizePixel=0; fill.ZIndex=4; fill.Parent=track
        _corner(fill,3)

        local handle=Instance.new("TextButton")
        handle.Size=UDim2.new(0,14,0,14)
        handle.Position=UDim2.new(CFG.aim_fov/500,0,0.5,-7)
        handle.BackgroundColor3=NW
        handle.Text=""; handle.BorderSizePixel=0
        handle.ZIndex=5; handle.Parent=track
        _corner(handle,7)

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
            handle.Position=UDim2.new(rel,0,0.5,-7)
        end)
    end

    -- ── LAYOUT ───────────────────────────────────────────────────
    local Y=66

    _sec("ESP",Y); Y=Y+26
    _row("  ESP Master",   CFG.esp,      Y, function(v) CFG.esp=v end);       Y=Y+34
    _row("  Box (corner)", CFG.esp_box,  Y, function(v) CFG.esp_box=v end);   Y=Y+34
    _row("  Nome",         CFG.esp_name, Y, function(v) CFG.esp_name=v end);  Y=Y+34
    _row("  Distância",    CFG.esp_dist, Y, function(v) CFG.esp_dist=v end);  Y=Y+34
    _row("  HP Bar",       CFG.esp_hp,   Y, function(v) CFG.esp_hp=v end);    Y=Y+38

    _sec("AIMBOT",Y); Y=Y+26
    _row("  Aimbot Master",  CFG.aim,           Y, function(v) CFG.aim=v end);           Y=Y+34
    _row("  Team Check",     CFG.aim_teamcheck, Y, function(v) CFG.aim_teamcheck=v end); Y=Y+38

    _sec("FOV CONTROL",Y); Y=Y+26
    _fov_slider(Y); Y=Y+54

    local info=Instance.new("TextLabel")
    info.Size=UDim2.new(1,-16,0,14)
    info.Position=UDim2.new(0,8,0,Y)
    info.BackgroundTransparency=1
    info.Text="X = toggle aim  ·  RMB = aim  ·  RShift = hide"
    info.TextColor3=Color3.fromRGB(55,55,55)
    info.TextSize=9; info.Font=Enum.Font.Gotham
    info.TextXAlignment=Enum.TextXAlignment.Center
    info.ZIndex=3; info.Parent=win
    Y=Y+20

    local db=Instance.new("TextButton")
    db.Size=UDim2.new(1,-16,0,32)
    db.Position=UDim2.new(0,8,0,Y)
    db.BackgroundColor3=Color3.fromRGB(18,4,4)
    db.Text="✖  DESTRUCT"
    db.TextColor3=NR
    db.TextSize=13; db.Font=Enum.Font.GothamBold
    db.BorderSizePixel=0; db.ZIndex=3; db.Parent=win
    _corner(db,7)
    local ds1=Instance.new("UIStroke")
    ds1.Color=NR; ds1.Thickness=1.5; ds1.Transparency=0
    ds1.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; ds1.Parent=db
    local ds2=Instance.new("UIStroke")
    ds2.Color=NR; ds2.Thickness=6; ds2.Transparency=0.5
    ds2.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; ds2.Parent=db
    table.insert(_pulse_fns,function(t)
        pcall(function() ds2.Transparency=0.3+math.abs(math.sin(t*1.6))*0.45 end)
    end)
    db.MouseEnter:Connect(function() db.BackgroundColor3=Color3.fromRGB(40,8,8) end)
    db.MouseLeave:Connect(function() db.BackgroundColor3=Color3.fromRGB(18,4,4) end)
    db.MouseButton1Click:Connect(function()
        _DESTROYED=true
        _clr()
        pcall(function() _fc:Remove() end)
        pcall(function() _gui_ref:Destroy() end)
    end)

    win.Size=UDim2.new(0,300,0,Y+46)
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
    local vp   = _cam.ViewportSize
    local mnx,mny,mxx,mxy = math.huge,math.huge,-math.huge,-math.huge
    for _,p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            -- ignora partes gigantes (terreno, veículos, etc.)
            local sz = p.Size
            if sz.X>12 or sz.Y>12 or sz.Z>12 then continue end
            local hs = sz*0.5; local cf = p.CFrame
            for _,o in ipairs({
                Vector3.new( hs.X, hs.Y, hs.Z),Vector3.new(-hs.X, hs.Y, hs.Z),
                Vector3.new( hs.X,-hs.Y, hs.Z),Vector3.new(-hs.X,-hs.Y, hs.Z),
                Vector3.new( hs.X, hs.Y,-hs.Z),Vector3.new(-hs.X, hs.Y,-hs.Z),
                Vector3.new( hs.X,-hs.Y,-hs.Z),Vector3.new(-hs.X,-hs.Y,-hs.Z),
            }) do
                local wp = (cf*CFrame.new(o)).Position
                local sp,inv,d = _w2s(wp)
                if inv and d>0 then
                    -- clamp no viewport para não explodir a box
                    local sx = math.clamp(sp.X,-50,vp.X+50)
                    local sy = math.clamp(sp.Y,-50,vp.Y+50)
                    if sx<mnx then mnx=sx end
                    if sy<mny then mny=sy end
                    if sx>mxx then mxx=sx end
                    if sy>mxy then mxy=sy end
                end
            end
        end
    end
    if mnx==math.huge then return nil end
    local w,h = mxx-mnx, mxy-mny
    -- descarta bbox absurda (> metade do viewport)
    if w>vp.X*0.6 or h>vp.Y*0.6 then return nil end
    return mnx,mny,w,h
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
local AIM_PRED_GAIN  = 3.0
local AIM_EMA_ALPHA  = 0.25
local AIM_SNAP_ANGLE = 0.035
local AIM_K_BASE     = 18.0

local _lock_target = nil
local _lock_lost   = 0
local LOCK_GRACE   = 0.12
local _ema_vel     = Vector3.new(0,0,0)
local _last_pos    = nil

local function _in_fov(part)
    local center=_cam.ViewportSize/2
    local sp,inv,d=_w2s(part.Position)
    if not inv or d<=0 then return false,0 end
    local dist_px=(sp-center).Magnitude
    return dist_px<=CFG.aim_fov, dist_px
end

local function _pick_target()
    if _lock_target then
        local char=_lock_target.Character
        local part=char and char:FindFirstChild(CFG.aim_target)
        if part and _alive(char) and not _smt(_lock_target) then
            local ok,_=_in_fov(part)
            if ok then _lock_lost=0; return _lock_target end
        end
        _lock_lost=_lock_lost+(1/60)
        if _lock_lost<LOCK_GRACE then return _lock_target end
        _lock_target=nil; _lock_lost=0
        _ema_vel=Vector3.new(0,0,0); _last_pos=nil
    end
    local center=_cam.ViewportSize/2
    local best,best_dist=nil,CFG.aim_fov
    for _,p in ipairs(_P:GetPlayers()) do
        if p==_lp or _smt(p) then continue end
        local char=p.Character
        if not char or not _alive(char) then continue end
        local part=char:FindFirstChild(CFG.aim_target)
        if not part then continue end
        local ok,d=_in_fov(part)
        if ok and d<best_dist then best_dist=d; best=p end
    end
    if best then
        _lock_target=best; _lock_lost=0
        _ema_vel=Vector3.new(0,0,0); _last_pos=nil
    end
    return best
end

local function _aimbot(dt)
    if not CFG.aim then
        _lock_target=nil; _lock_lost=0
        _ema_vel=Vector3.new(0,0,0); _last_pos=nil
        return
    end
    local holding=_UIS:IsMouseButtonPressed(CFG.aim_hold)
    if not holding then
        _lock_lost=_lock_lost+dt
        if _lock_lost>=LOCK_GRACE then
            _lock_target=nil; _lock_lost=0
            _ema_vel=Vector3.new(0,0,0); _last_pos=nil
        end
        return
    end
    if _lock_target then
        local char=_lock_target.Character
        local part=char and char:FindFirstChild(CFG.aim_target)
        if part and _alive(char) then
            local ok,_=_in_fov(part)
            if ok then _lock_lost=0 else _lock_lost=_lock_lost+dt end
        else
            _lock_lost=_lock_lost+dt
        end
        if _lock_lost>=LOCK_GRACE then
            _lock_target=nil; _lock_lost=0
            _ema_vel=Vector3.new(0,0,0); _last_pos=nil
        end
    end
    local target=_pick_target(); if not target then return end
    local char=target.Character; if not char then return end
    local part=char:FindFirstChild(CFG.aim_target); if not part then return end
    local cur_pos=part.Position
    if _last_pos then
        local raw_vel=(cur_pos-_last_pos)/math.max(dt,0.001)
        _ema_vel=_ema_vel+(raw_vel-_ema_vel)*AIM_EMA_ALPHA
    end
    _last_pos=cur_pos
    local predicted=cur_pos+_ema_vel*dt*AIM_PRED_GAIN
    local cur=_cam.CFrame
    local dir=(predicted-cur.Position)
    if dir.Magnitude<0.001 then return end
    dir=dir.Unit
    local tgt_cf=CFrame.new(cur.Position,cur.Position+dir)
    local dot=math.clamp(cur.LookVector:Dot(tgt_cf.LookVector),-1,1)
    local angle=math.acos(dot)
    local k_scale=math.clamp(1.0-CFG.aim_smooth,0.05,1.0)
    local angle_boost=math.clamp(angle*8.0,0.0,3.0)
    local k=AIM_K_BASE*k_scale*(1.0+angle_boost)
    local alpha=1.0-math.exp(-k*dt)
    if angle<AIM_SNAP_ANGLE then alpha=1.0 end
    alpha=math.clamp(alpha,0.0,1.0)
    pcall(function() _cam.CFrame=cur:Lerp(tgt_cf,alpha) end)
end

-- ═══ INIT ═════════════════════════════════════════════════════════
_build_gui()

_UIS.InputBegan:Connect(function(input,gpe)
    if gpe or _DESTROYED then return end
    if input.KeyCode==CFG.gui_toggle then
        _gui_vis=not _gui_vis
        if _win_ref then _win_ref.Visible=_gui_vis end
    end
    if input.KeyCode==CFG.aim_toggle then
        CFG.aim=not CFG.aim
        if not CFG.aim then
            _lock_target=nil; _lock_lost=0
            _ema_vel=Vector3.new(0,0,0); _last_pos=nil
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
    _t=_t+dt
    _cam=workspace.CurrentCamera
    for _,fn in ipairs(_pulse_fns) do fn(_t) end
    _fc.Position=_cam.ViewportSize/2
    _fc.Visible=CFG.aim
    _esp()
    _aimbot(dt)
end)

_lp.CharacterAdded:Connect(function()
    if _DESTROYED then return end
    _cam=workspace.CurrentCamera
    _lock_target=nil; _lock_lost=0
    _ema_vel=Vector3.new(0,0,0); _last_pos=nil
end)
