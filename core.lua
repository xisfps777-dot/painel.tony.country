-- core.lua | Roblox LuaU | Solara | v10
-- Evasão: XOR, string split, junk globals, dead code, constant folding, anti-tamper

-- ═══ ANTI-TAMPER ══════════════════════════════════════════════════
local _env_ok = (type(Drawing)=="table" or type(Drawing)=="userdata")
    and type(bit32)=="table" and type(game)=="userdata"
if not _env_ok then return end

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

for _=1,16 do rawset(_G,"_".._rid(8),math.random()*9999) end
if false then game:GetService("HttpService"):GetAsync("https://example.com") end

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
    -- "highlight" = Highlight (wallbang, 100% compat)
    -- "selection" = SelectionBox nativo
    -- "drawing"   = bbox projetada
    esp_method="highlight",

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
local _gui_ref,_win_ref=nil,nil
local _gui_vis=true
local _t=0

-- pools por player — criados uma vez, atualizados por frame
local _hl={}   -- highlight pool  { [player] = {hl, name_sh, name_d, dist_d, hp_bg, hp_bar} }
local _sel={}  -- selection pool  { [player] = {box, name_sh, name_d, dist_d, hp_bg, hp_bar} }

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

-- ═══ HELPERS COMUNS ═══════════════════════════════════════════════
-- cria 5 drawings reutilizáveis para texto+hp (compartilhado por HL e SEL)
local function _make_text_drawings()
    local name_sh=Drawing.new("Text"); name_sh.Size=13; name_sh.Color=Color3.new(0,0,0)
    name_sh.Outline=false; name_sh.Center=true; name_sh.Visible=false; name_sh.ZIndex=3
    local name_d=Drawing.new("Text"); name_d.Size=13; name_d.Color=Color3.fromRGB(255,255,255)
    name_d.Outline=false; name_d.Center=true; name_d.Visible=false; name_d.ZIndex=4
    local dist_d=Drawing.new("Text"); dist_d.Size=11; dist_d.Color=Color3.fromRGB(190,190,190)
    dist_d.Outline=true; dist_d.Center=true; dist_d.Visible=false; dist_d.ZIndex=4
    local hp_bg=Drawing.new("Line"); hp_bg.Color=Color3.new(0,0,0); hp_bg.Thickness=5
    hp_bg.Visible=false; hp_bg.ZIndex=2
    local hp_bar=Drawing.new("Line"); hp_bar.Thickness=3; hp_bar.Visible=false; hp_bar.ZIndex=3
    return name_sh,name_d,dist_d,hp_bg,hp_bar
end

local function _remove_text_drawings(e)
    pcall(function() e.name_sh:Remove() end)
    pcall(function() e.name_d:Remove()  end)
    pcall(function() e.dist_d:Remove()  end)
    pcall(function() e.hp_bg:Remove()   end)
    pcall(function() e.hp_bar:Remove()  end)
end

local function _hide_text_drawings(e)
    e.name_sh.Visible=false; e.name_d.Visible=false
    e.dist_d.Visible=false
    e.hp_bg.Visible=false; e.hp_bar.Visible=false
end

-- ═══ FOLDER PARA INSTÂNCIAS ═══════════════════════════════════════
local _inst_folder=nil
local function _get_folder()
    if _inst_folder and _inst_folder.Parent then return _inst_folder end
    local f=Instance.new("Folder"); f.Name="TC_INST"
    local ok=false
    if not ok then pcall(function() f.Parent=game:GetService(_svc[5]); ok=true end) end
    if not ok then pcall(function() f.Parent=_lp:WaitForChild("PlayerGui",1); ok=true end) end
    _inst_folder=f; return f
end

-- ═══ HIGHLIGHT POOL ═══════════════════════════════════════════════
-- Highlight atravessa paredes por design (DepthMode=AlwaysOnTop por padrão)
-- FillTransparency=1 → só silhueta; mude para 0.7 se quiser fill sólido
local function _hl_ensure(p)
    if _hl[p] then return _hl[p] end
    local hl=Instance.new("Highlight")
    hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop  -- atravessa paredes
    hl.FillTransparency=1                              -- sem fill
    hl.OutlineTransparency=0
    hl.OutlineColor=CFG.esp_color
    hl.Enabled=false
    hl.Parent=_get_folder()
    local n1,n2,dist,hbg,hbar=_make_text_drawings()
    local entry={hl=hl,name_sh=n1,name_d=n2,dist_d=dist,hp_bg=hbg,hp_bar=hbar}
    _hl[p]=entry; return entry
end

local function _hl_hide_all()
    for _,e in pairs(_hl) do
        pcall(function() e.hl.Enabled=false end)
        _hide_text_drawings(e)
    end
end

local function _hl_destroy_all()
    for _,e in pairs(_hl) do
        pcall(function() e.hl:Destroy() end)
        _remove_text_drawings(e)
    end
    _hl={}
end

-- ═══ SELECTION POOL ═══════════════════════════════════════════════
local function _sel_ensure(p)
    if _sel[p] then return _sel[p] end
    local box=Instance.new("SelectionBox")
    box.Color3=CFG.esp_color; box.LineThickness=0.04
    box.SurfaceTransparency=1; box.SurfaceColor3=Color3.new(0,0,0)
    box.Visible=false; box.Parent=_get_folder()
    local n1,n2,dist,hbg,hbar=_make_text_drawings()
    local entry={box=box,name_sh=n1,name_d=n2,dist_d=dist,hp_bg=hbg,hp_bar=hbar}
    _sel[p]=entry; return entry
end

local function _sel_hide_all()
    for _,e in pairs(_sel) do
        pcall(function() e.box.Visible=false end)
        _hide_text_drawings(e)
    end
end

local function _sel_destroy_all()
    for _,e in pairs(_sel) do
        pcall(function() e.box:Destroy() end)
        _remove_text_drawings(e)
    end
    _sel={}
end

-- ═══ CORES ════════════════════════════════════════════════════════
local NW=Color3.fromRGB(255,255,255)
local NR=Color3.fromRGB(255,30,30)
local BG_WIN=Color3.fromRGB(5,5,5)
local BG_HDR=Color3.fromRGB(10,10,10)
local BG_ROW=Color3.fromRGB(8,8,8)
local BG_SEC=Color3.fromRGB(12,12,12)

local function _corner(p,r)
    local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=p
end
local function _stroke(p,color,thick)
    local s=Instance.new("UIStroke"); s.Color=color; s.Thickness=thick or 1
    s.Transparency=0; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=p; return s
end
local function _label(parent,text,size,color,xa,pos,sz,zi,bold)
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1
    l.Text=text; l.TextSize=size; l.TextColor3=color
    l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextXAlignment=xa or Enum.TextXAlignment.Left
    l.TextStrokeTransparency=1
    if pos then l.Position=pos end
    if sz  then l.Size=sz end
    l.ZIndex=zi or 3; l.Parent=parent; return l
end

-- ═══ BUILD GUI ════════════════════════════════════════════════════
local function _build_gui()
    pcall(function() game:GetService(_svc[5]):FindFirstChild(_j("TC","_G")):Destroy() end)
    pcall(function() _lp.PlayerGui:FindFirstChild(_j("TC","_G")):Destroy() end)

    local gui=Instance.new("ScreenGui")
    gui.Name=_j("TC","_G"); gui.ResetOnSpawn=false
    gui.DisplayOrder=999; gui.IgnoreGuiInset=true
    gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling

    local ok=false
    if not ok then pcall(function() gui.Parent=game:GetService(_svc[5]); ok=true end) end
    if not ok then pcall(function() gui.Parent=_lp:WaitForChild("PlayerGui",3); ok=true end) end
    if not ok then pcall(function() gui.Parent=gethui(); ok=true end) end
    if not ok then return end
    _gui_ref=gui

    local win=Instance.new("Frame")
    win.Name="Win"; win.Size=UDim2.new(0,280,0,10)
    win.Position=UDim2.new(0,24,0.5,-180)
    win.BackgroundColor3=BG_WIN; win.BorderSizePixel=0
    win.Active=true; win.Draggable=true
    win.ClipsDescendants=false; win.Parent=gui
    _corner(win,8); _stroke(win,Color3.fromRGB(28,28,28),1)

    local hdr=Instance.new("Frame")
    hdr.Size=UDim2.new(1,0,0,52); hdr.BackgroundColor3=BG_HDR
    hdr.BorderSizePixel=0; hdr.ZIndex=2; hdr.Parent=win; _corner(hdr,8)
    _label(hdr,"TONY COUNTRY",17,NW,Enum.TextXAlignment.Center,
        UDim2.new(0,0,0,8),UDim2.new(1,0,0,24),4,true)
    _label(hdr,"ESP  ·  AIMBOT",9,Color3.fromRGB(120,120,120),
        Enum.TextXAlignment.Center,
        UDim2.new(0,0,0,32),UDim2.new(1,0,0,14),3,false)

    local sep=Instance.new("Frame")
    sep.Size=UDim2.new(1,-16,0,1); sep.Position=UDim2.new(0,8,0,54)
    sep.BackgroundColor3=Color3.fromRGB(28,28,28); sep.BorderSizePixel=0
    sep.ZIndex=3; sep.Parent=win

    local function _sec(text,y)
        local f=Instance.new("Frame"); f.Size=UDim2.new(1,-16,0,20)
        f.Position=UDim2.new(0,8,0,y); f.BackgroundColor3=BG_SEC
        f.BorderSizePixel=0; f.ZIndex=2; f.Parent=win; _corner(f,4)
        _stroke(f,Color3.fromRGB(28,28,28),1)
        _label(f,"  "..text,10,Color3.fromRGB(160,160,160),
            Enum.TextXAlignment.Left,UDim2.new(0,0,0,0),UDim2.new(1,0,1,0),3,true)
    end

    local function _row(text,state,y,cb)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,-16,0,28)
        row.Position=UDim2.new(0,8,0,y); row.BackgroundColor3=BG_ROW
        row.BorderSizePixel=0; row.ZIndex=2; row.Parent=win; _corner(row,6)
        _stroke(row,Color3.fromRGB(28,28,28),1)
        _label(row,text,11,Color3.fromRGB(200,200,200),
            Enum.TextXAlignment.Left,
            UDim2.new(0,10,0,0),UDim2.new(0.6,0,1,0),3,false)
        local btn=Instance.new("TextButton")
        btn.Size=UDim2.new(0,52,0,20); btn.Position=UDim2.new(1,-58,0.5,-10)
        btn.TextSize=11; btn.Font=Enum.Font.GothamBold
        btn.BorderSizePixel=0; btn.ZIndex=4; btn.Parent=row; _corner(btn,5)
        local _st=state
        local function _ref()
            if _st then
                btn.BackgroundColor3=NW; btn.TextColor3=Color3.new(0,0,0); btn.Text="ON"
            else
                btn.BackgroundColor3=Color3.fromRGB(18,18,18)
                btn.TextColor3=Color3.fromRGB(80,80,80); btn.Text="OFF"
            end
        end
        _ref()
        btn.MouseButton1Click:Connect(function() _st=not _st; cb(_st); _ref() end)
    end

    -- ── ESP METHOD: 3 modos em ciclo ─────────────────────────────
    -- HL (wallbang) → SEL (nativo) → DRAW (projetado) → HL …
    local _modes={"highlight","selection","drawing"}
    local _mode_labels={
        highlight="HL ✔",
        selection="SEL ✔",
        drawing="DRAW",
    }
    local _mode_colors={
        highlight={bg=Color3.fromRGB(8,16,28),  fg=Color3.fromRGB(80,160,255)},
        selection={bg=Color3.fromRGB(8,22,8),   fg=Color3.fromRGB(80,210,80)},
        drawing  ={bg=Color3.fromRGB(18,18,18), fg=Color3.fromRGB(140,140,140)},
    }

    local function _method_row(y)
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,-16,0,28)
        row.Position=UDim2.new(0,8,0,y); row.BackgroundColor3=BG_ROW
        row.BorderSizePixel=0; row.ZIndex=2; row.Parent=win; _corner(row,6)
        _stroke(row,Color3.fromRGB(28,28,28),1)
        _label(row,"  Modo ESP",11,Color3.fromRGB(200,200,200),
            Enum.TextXAlignment.Left,
            UDim2.new(0,10,0,0),UDim2.new(0.52,0,1,0),3,false)

        -- hint pequeno (descreve o modo atual)
        local hint=Instance.new("TextLabel"); hint.Size=UDim2.new(0,55,1,0)
        hint.Position=UDim2.new(0,105,0,0); hint.BackgroundTransparency=1
        hint.TextSize=9; hint.Font=Enum.Font.Gotham
        hint.TextXAlignment=Enum.TextXAlignment.Left
        hint.TextStrokeTransparency=1; hint.ZIndex=3; hint.Parent=row

        local btn=Instance.new("TextButton")
        btn.Size=UDim2.new(0,66,0,20); btn.Position=UDim2.new(1,-72,0.5,-10)
        btn.TextSize=10; btn.Font=Enum.Font.GothamBold
        btn.BorderSizePixel=0; btn.ZIndex=4; btn.Parent=row; _corner(btn,5)

        local _hints={
            highlight="wallbang",
            selection="nativo",
            drawing="projetado",
        }

        local function _ref()
            local m=CFG.esp_method
            local lbl=_mode_labels[m]; local col=_mode_colors[m]
            btn.Text=lbl; btn.BackgroundColor3=col.bg; btn.TextColor3=col.fg
            hint.Text=_hints[m]; hint.TextColor3=col.fg
        end
        _ref()

        btn.MouseButton1Click:Connect(function()
            -- cicla para o próximo modo e limpa o pool do anterior
            local cur=CFG.esp_method
            local idx=1
            for i,m in ipairs(_modes) do if m==cur then idx=i; break end end
            local nxt=_modes[(idx%#_modes)+1]
            -- limpeza
            if cur=="highlight" then _hl_hide_all()
            elseif cur=="selection" then _sel_hide_all()
            else _clr() end
            CFG.esp_method=nxt
            _ref()
        end)
    end

    local function _fov_slider(y)
        local frame=Instance.new("Frame"); frame.Size=UDim2.new(1,-16,0,44)
        frame.Position=UDim2.new(0,8,0,y); frame.BackgroundColor3=BG_ROW
        frame.BorderSizePixel=0; frame.ZIndex=2; frame.Parent=win; _corner(frame,6)
        _stroke(frame,Color3.fromRGB(28,28,28),1)
        _label(frame,"  FOV",11,Color3.fromRGB(200,200,200),
            Enum.TextXAlignment.Left,UDim2.new(0,0,0,2),UDim2.new(0.4,0,0,18),3,false)
        local val_lbl=Instance.new("TextLabel")
        val_lbl.Size=UDim2.new(0.3,0,0,18); val_lbl.Position=UDim2.new(0.7,0,0,2)
        val_lbl.BackgroundTransparency=1; val_lbl.Text=tostring(CFG.aim_fov)
        val_lbl.TextColor3=NW; val_lbl.TextSize=11; val_lbl.Font=Enum.Font.GothamBold
        val_lbl.TextXAlignment=Enum.TextXAlignment.Right
        val_lbl.TextStrokeTransparency=1; val_lbl.ZIndex=3; val_lbl.Parent=frame
        local track=Instance.new("Frame"); track.Size=UDim2.new(1,-18,0,4)
        track.Position=UDim2.new(0,9,0,30); track.BackgroundColor3=Color3.fromRGB(22,22,22)
        track.BorderSizePixel=0; track.ZIndex=3; track.Parent=frame; _corner(track,2)
        local fill=Instance.new("Frame"); fill.Size=UDim2.new(CFG.aim_fov/500,0,1,0)
        fill.BackgroundColor3=NW; fill.BorderSizePixel=0; fill.ZIndex=4; fill.Parent=track
        _corner(fill,2)
        local handle=Instance.new("TextButton")
        handle.Size=UDim2.new(0,12,0,12); handle.Position=UDim2.new(CFG.aim_fov/500,0,0.5,-6)
        handle.BackgroundColor3=NW; handle.Text=""; handle.BorderSizePixel=0
        handle.ZIndex=5; handle.Parent=track; _corner(handle,6)
        local dragging=false
        handle.MouseButton1Down:Connect(function() dragging=true end)
        _UIS.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
        end)
        _UIS.InputChanged:Connect(function(i)
            if not dragging or i.UserInputType~=Enum.UserInputType.MouseMovement then return end
            local tp=track.AbsolutePosition; local ts=track.AbsoluteSize
            local rel=math.clamp((i.Position.X-tp.X)/ts.X,0,1)
            local nf=math.max(math.floor(rel*500),10)
            CFG.aim_fov=nf; _fc.Radius=nf
            val_lbl.Text=tostring(nf)
            fill.Size=UDim2.new(rel,0,1,0)
            handle.Position=UDim2.new(rel,0,0.5,-6)
        end)
    end

    -- ── LAYOUT ───────────────────────────────────────────────────
    local Y=57
    _sec("ESP",Y); Y=Y+24
    _row("  ESP Master",   CFG.esp,      Y, function(v) CFG.esp=v end);       Y=Y+32
    _method_row(Y); Y=Y+32
    _row("  Box / Outline",CFG.esp_box,  Y, function(v) CFG.esp_box=v end);   Y=Y+32
    _row("  Nome",         CFG.esp_name, Y, function(v) CFG.esp_name=v end);  Y=Y+32
    _row("  Distância",    CFG.esp_dist, Y, function(v) CFG.esp_dist=v end);  Y=Y+32
    _row("  HP Bar",       CFG.esp_hp,   Y, function(v) CFG.esp_hp=v end);    Y=Y+36

    _sec("AIMBOT",Y); Y=Y+24
    _row("  Aimbot",       CFG.aim,           Y, function(v) CFG.aim=v end);           Y=Y+32
    _row("  Team Check",   CFG.aim_teamcheck, Y, function(v) CFG.aim_teamcheck=v end); Y=Y+36

    _sec("FOV",Y); Y=Y+24
    _fov_slider(Y); Y=Y+52

    local info=Instance.new("TextLabel")
    info.Size=UDim2.new(1,-16,0,12); info.Position=UDim2.new(0,8,0,Y)
    info.BackgroundTransparency=1
    info.Text="X = aim  ·  RMB = hold  ·  RShift = hide"
    info.TextColor3=Color3.fromRGB(50,50,50); info.TextSize=8
    info.Font=Enum.Font.Gotham; info.TextXAlignment=Enum.TextXAlignment.Center
    info.ZIndex=3; info.Parent=win; Y=Y+18

    local db=Instance.new("TextButton")
    db.Size=UDim2.new(1,-16,0,28); db.Position=UDim2.new(0,8,0,Y)
    db.BackgroundColor3=Color3.fromRGB(16,4,4)
    db.Text="✖  DESTRUCT"; db.TextColor3=NR
    db.TextSize=12; db.Font=Enum.Font.GothamBold
    db.BorderSizePixel=0; db.ZIndex=3; db.Parent=win; _corner(db,6)
    _stroke(db,NR,1)
    db.MouseEnter:Connect(function() db.BackgroundColor3=Color3.fromRGB(36,8,8) end)
    db.MouseLeave:Connect(function() db.BackgroundColor3=Color3.fromRGB(16,4,4) end)
    db.MouseButton1Click:Connect(function()
        _DESTROYED=true; _clr()
        _hl_destroy_all(); _sel_destroy_all()
        pcall(function() _fc:Remove() end)
        pcall(function() _gui_ref:Destroy() end)
        if _inst_folder then pcall(function() _inst_folder:Destroy() end) end
    end)

    win.Size=UDim2.new(0,280,0,Y+40)
    _win_ref=win
end

-- ═══ UTILS ════════════════════════════════════════════════════════
local function _get_hum(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
        or char:FindFirstChildWhichIsA("Humanoid")
end
local function _alive(char)
    local h=_get_hum(char); return h and h.Health>0
end
local function _get_root(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChildWhichIsA("BasePart")
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
    local vp=_cam.ViewportSize; local vpX,vpY=vp.X,vp.Y
    local mnx,mny,mxx,mxy=math.huge,math.huge,-math.huge,-math.huge
    local found=false
    local root=_get_root(char); local rootPos=root and root.Position or nil
    for _,p in ipairs(char:GetDescendants()) do
        if not p:IsA("BasePart") then continue end
        if rootPos and (p.Position-rootPos).Magnitude>20 then continue end
        local hs=p.Size*0.5; local cf=p.CFrame
        for _,o in ipairs({
            Vector3.new( hs.X, hs.Y, hs.Z),Vector3.new(-hs.X, hs.Y, hs.Z),
            Vector3.new( hs.X,-hs.Y, hs.Z),Vector3.new(-hs.X,-hs.Y, hs.Z),
            Vector3.new( hs.X, hs.Y,-hs.Z),Vector3.new(-hs.X, hs.Y,-hs.Z),
            Vector3.new( hs.X,-hs.Y,-hs.Z),Vector3.new(-hs.X,-hs.Y,-hs.Z),
        }) do
            local wp=(cf*CFrame.new(o)).Position
            local sp,inv2,d=_w2s(wp)
            if not inv2 or d<=0 then continue end
            local sx=math.clamp(sp.X,0,vpX); local sy=math.clamp(sp.Y,0,vpY)
            if sx<mnx then mnx=sx end; if sy<mny then mny=sy end
            if sx>mxx then mxx=sx end; if sy>mxy then mxy=sy end
            found=true
        end
    end
    if not found and rootPos then
        local hum=_get_hum(char); local hipH=hum and hum.HipHeight or 1.5
        for _,wp in ipairs({
            rootPos+Vector3.new( 0.5,hipH+1.0,0),rootPos+Vector3.new(-0.5,hipH+1.0,0),
            rootPos+Vector3.new( 0.5,-hipH*0.4,0),rootPos+Vector3.new(-0.5,-hipH*0.4,0),
        }) do
            local sp,inv2,d=_w2s(wp)
            if not inv2 or d<=0 then continue end
            local sx=math.clamp(sp.X,0,vpX); local sy=math.clamp(sp.Y,0,vpY)
            if sx<mnx then mnx=sx end; if sy<mny then mny=sy end
            if sx>mxx then mxx=sx end; if sy>mxy then mxy=sy end
            found=true
        end
    end
    if not found then return nil end
    local w,h=mxx-mnx,mxy-mny
    if w<2 or h<2 then return nil end
    return mnx,mny,w,h
end

-- ═══ OVERLAY DE TEXTO COMUM (nome/dist/hp) ════════════════════════
local function _update_text_overlay(e,p,char,root,dist)
    local bx,by,bw,bh=_bbox(char)
    if not bx then
        local rsp=_w2s(root.Position)
        bx=rsp.X-18; by=rsp.Y-40; bw=36; bh=50
    end

    if CFG.esp_name then
        e.name_sh.Text=p.Name; e.name_sh.Position=Vector2.new(bx+bw/2+1,by-13); e.name_sh.Visible=true
        e.name_d.Text=p.Name;  e.name_d.Position=Vector2.new(bx+bw/2,by-14);    e.name_d.Visible=true
    else e.name_sh.Visible=false; e.name_d.Visible=false end

    if CFG.esp_dist then
        e.dist_d.Text=("%.0fm"):format(dist)
        e.dist_d.Position=Vector2.new(bx+bw/2,by+bh+3); e.dist_d.Visible=true
    else e.dist_d.Visible=false end

    if CFG.esp_hp then
        local hum=_get_hum(char)
        if hum and hum.MaxHealth>0 then
            local ratio=math.clamp(hum.Health/hum.MaxHealth,0,1)
            local barH=math.max(bh,20); local bx2=bx-7
            e.hp_bg.From=Vector2.new(bx2,by);       e.hp_bg.To=Vector2.new(bx2,by+barH); e.hp_bg.Visible=true
            e.hp_bar.From=Vector2.new(bx2,by+barH); e.hp_bar.To=Vector2.new(bx2,by+barH-barH*ratio)
            e.hp_bar.Color=Color3.fromRGB(math.floor(255*(1-ratio)),math.floor(255*ratio),40)
            e.hp_bar.Visible=true
        else e.hp_bg.Visible=false; e.hp_bar.Visible=false end
    else e.hp_bg.Visible=false; e.hp_bar.Visible=false end
end

-- ═══ ESP — ITERATE PLAYERS (compartilhado pelos 3 modos) ══════════
local function _iter_players()
    local result={}
    for _,p in ipairs(_P:GetPlayers()) do
        if p==_lp then continue end
        local char=p.Character; if not char or not _alive(char) then continue end
        local root=_get_root(char); if not root then continue end
        local dist=(_cam.CFrame.Position-root.Position).Magnitude
        if dist>CFG.esp_max_dist then continue end
        result[p]={char=char,root=root,dist=dist}
    end
    return result
end

-- ─── HIGHLIGHT (wallbang) ─────────────────────────────────────────
local function _esp_highlight()
    if not CFG.esp then _hl_hide_all(); return end
    local active=_iter_players()
    for p,e in pairs(_hl) do
        if not active[p] then
            pcall(function() e.hl.Enabled=false end); _hide_text_drawings(e)
        end
    end
    for p,info in pairs(active) do
        local e=_hl_ensure(p)
        local char,root,dist=info.char,info.root,info.dist
        if e.hl.Adornee~=char then e.hl.Adornee=char end
        e.hl.OutlineColor=CFG.esp_color
        -- esp_box = outline visível; desligado = hl transparente (só nome/dist/hp)
        e.hl.OutlineTransparency = CFG.esp_box and 0 or 1
        e.hl.Enabled=true
        _update_text_overlay(e,p,char,root,dist)
    end
end

-- ─── SELECTION ────────────────────────────────────────────────────
local function _esp_selection()
    if not CFG.esp then _sel_hide_all(); return end
    local active=_iter_players()
    for p,e in pairs(_sel) do
        if not active[p] then
            pcall(function() e.box.Visible=false end); _hide_text_drawings(e)
        end
    end
    for p,info in pairs(active) do
        local e=_sel_ensure(p)
        local char,root,dist=info.char,info.root,info.dist
        if e.box.Adornee~=char then e.box.Adornee=char end
        e.box.Color3=CFG.esp_color
        e.box.Visible=CFG.esp_box
        _update_text_overlay(e,p,char,root,dist)
    end
end

-- ─── DRAWING ──────────────────────────────────────────────────────
local function _esp_drawing()
    _clr(); if not CFG.esp then return end
    for _,p in ipairs(_P:GetPlayers()) do
        if p==_lp then continue end
        local char=p.Character; if not char or not _alive(char) then continue end
        local root=_get_root(char); if not root then continue end
        local dist=(_cam.CFrame.Position-root.Position).Magnitude
        if dist>CFG.esp_max_dist then continue end
        local _,inv2,depth=_w2s(root.Position)
        if not inv2 or depth<=0 then continue end

        local bx,by,bw,bh=_bbox(char)
        if not bx then
            local hum=_get_hum(char); local hipH=hum and hum.HipHeight or 1.5
            local topPt=_w2s(root.Position+Vector3.new(0,hipH+1,0))
            local botPt=_w2s(root.Position-Vector3.new(0,hipH*0.4,0))
            local lPt=_w2s(root.Position+Vector3.new(-1,0,0))
            local rPt=_w2s(root.Position+Vector3.new(1,0,0))
            local vp=_cam.ViewportSize
            local x1=math.clamp(math.min(lPt.X,rPt.X),0,vp.X)
            local x2=math.clamp(math.max(lPt.X,rPt.X),0,vp.X)
            local w=math.max(x2-x1,20); local h=math.max(botPt.Y-topPt.Y,30)
            local rsp=_w2s(root.Position)
            bx=rsp.X-w/2; by=topPt.Y; bw=w; bh=h
        end

        if CFG.esp_box then
            local clen=math.min(bw,bh)*0.22
            for _,c in ipairs({
                {{bx,by},{bx+clen,by}},            {{bx,by},{bx,by+clen}},
                {{bx+bw,by},{bx+bw-clen,by}},      {{bx+bw,by},{bx+bw,by+clen}},
                {{bx,by+bh},{bx+clen,by+bh}},      {{bx,by+bh},{bx,by+bh-clen}},
                {{bx+bw,by+bh},{bx+bw-clen,by+bh}},{{bx+bw,by+bh},{bx+bw,by+bh-clen}},
            }) do
                _nd("Line",{From=Vector2.new(c[1][1],c[1][2]),To=Vector2.new(c[2][1],c[2][2]),
                    Color=Color3.new(0,0,0),Thickness=3,Transparency=0.5,Visible=true,ZIndex=2})
                _nd("Line",{From=Vector2.new(c[1][1],c[1][2]),To=Vector2.new(c[2][1],c[2][2]),
                    Color=CFG.esp_color,Thickness=1.5,Transparency=0,Visible=true,ZIndex=3})
            end
        end
        if CFG.esp_name then
            _nd("Text",{Text=p.Name,Position=Vector2.new(bx+bw/2+1,by-13),
                Size=13,Color=Color3.new(0,0,0),Outline=false,Center=true,Visible=true,ZIndex=3})
            _nd("Text",{Text=p.Name,Position=Vector2.new(bx+bw/2,by-14),
                Size=13,Color=Color3.fromRGB(255,255,255),Outline=false,Center=true,Visible=true,ZIndex=4})
        end
        if CFG.esp_dist then
            _nd("Text",{Text=("%.0fm"):format(dist),
                Position=Vector2.new(bx+bw/2,by+bh+3),
                Size=11,Color=Color3.fromRGB(190,190,190),
                Outline=true,Center=true,Visible=true,ZIndex=4})
        end
        if CFG.esp_hp then
            local hum=_get_hum(char)
            if hum and hum.MaxHealth>0 then
                local ratio=math.clamp(hum.Health/hum.MaxHealth,0,1)
                local barH=math.max(bh,20); local bx2=bx-7
                local topY=by; local botY=by+barH; local fillY=botY-barH*ratio
                _nd("Line",{From=Vector2.new(bx2,topY),To=Vector2.new(bx2,botY),
                    Color=Color3.new(0,0,0),Thickness=5,Visible=true,ZIndex=2})
                _nd("Line",{From=Vector2.new(bx2,botY),To=Vector2.new(bx2,fillY),
                    Color=Color3.fromRGB(math.floor(255*(1-ratio)),math.floor(255*ratio),40),
                    Thickness=3,Visible=true,ZIndex=3})
            end
        end
    end
end

-- ─── DISPATCHER ───────────────────────────────────────────────────
local function _esp()
    local m=CFG.esp_method
    if m=="highlight" then
        _esp_highlight()
    elseif m=="selection" then
        _esp_selection()
    else
        _esp_drawing()
    end
end

-- ═══ AIMBOT v3 ════════════════════════════════════════════════════
local AIM_PRED_GAIN=3.0; local AIM_EMA_ALPHA=0.25
local AIM_SNAP_ANGLE=0.035; local AIM_K_BASE=18.0
local _lock_target=nil; local _lock_lost=0; local LOCK_GRACE=0.12
local _ema_vel=Vector3.new(0,0,0); local _last_pos=nil

local function _in_fov(part)
    local center=_cam.ViewportSize/2
    local sp,inv,d=_w2s(part.Position)
    if not inv or d<=0 then return false,0 end
    return (sp-center).Magnitude<=CFG.aim_fov,(sp-center).Magnitude
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
    local best,best_dist=nil,CFG.aim_fov
    for _,p in ipairs(_P:GetPlayers()) do
        if p==_lp or _smt(p) then continue end
        local char=p.Character; if not char or not _alive(char) then continue end
        local part=char:FindFirstChild(CFG.aim_target); if not part then continue end
        local ok,d=_in_fov(part)
        if ok and d<best_dist then best_dist=d; best=p end
    end
    if best then _lock_target=best; _lock_lost=0
        _ema_vel=Vector3.new(0,0,0); _last_pos=nil end
    return best
end

local function _aimbot(dt)
    if not CFG.aim then
        _lock_target=nil; _lock_lost=0
        _ema_vel=Vector3.new(0,0,0); _last_pos=nil; return
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
            local ok,_=_in_fov(part); if ok then _lock_lost=0 else _lock_lost=_lock_lost+dt end
        else _lock_lost=_lock_lost+dt end
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
    local k_scale=math.clamp(1-CFG.aim_smooth,0.05,1)
    local k=AIM_K_BASE*k_scale*(1+math.clamp(angle*8,0,3))
    local alpha=math.clamp(1-math.exp(-k*dt),0,1)
    if angle<AIM_SNAP_ANGLE then alpha=1 end
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
