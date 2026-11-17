-- core.lua | Roblox LuaU | Solara | GUI + ESP + Aimbot
-- fix: ordem de declaração, parent robusto, pcall em tudo

local _K = 0x5A
local function _xd(s)
    local o = table.create(#s)
    for i=1,#s do o[i]=string.char(bit32.bxor(string.byte(s,i),_K)) end
    return table.concat(o)
end

local function _rid()
    local c,t="abcdefghijklmnopqrstuvwxyz",table.create(8)
    for i=1,8 do t[i]=c:sub(math.random(1,#c),math.random(1,#c)) end
    return table.concat(t)
end
local _pfx = "_".._rid()

-- services
local _P   = game:GetService("Players")
local _RS  = game:GetService("RunService")
local _UIS = game:GetService("UserInputService")
local _SG  = game:GetService("StarterGui")
local _lp  = _P.LocalPlayer
local _cam = workspace.CurrentCamera

-- config — tudo OFF
local CFG = {
    esp=false, esp_box=false, esp_name=false, esp_dist=false, esp_hp=false,
    esp_color=Color3.fromRGB(255,60,60), esp_max_dist=1000,
    aim=false, aim_active=false,
    aim_toggle=Enum.KeyCode.X,
    aim_hold=Enum.UserInputType.MouseButton2,
    aim_fov=150, aim_smooth=0.14, aim_target="Head", aim_teamcheck=false,
    gui_toggle=Enum.KeyCode.RightShift,
}

-- estado global
local _pool      = {}
local _DESTROYED = false
local _pulse_fns = {}
local _gui_ref   = nil
local _win_ref   = nil
local _gui_vis   = true
local _t         = 0

-- fov circle — declarado ANTES de qualquer referência
local _fc = Drawing.new("Circle")
_fc.Thickness=1; _fc.Radius=CFG.aim_fov
_fc.Color=Color3.fromRGB(255,255,255); _fc.Filled=false; _fc.ZIndex=10; _fc.Visible=false

-- drawing pool
local function _nd(tp, props)
    local d=Drawing.new(tp)
    for k,v in pairs(props) do d[k]=v end
    table.insert(_pool,d); return d
end
local function _clr()
    for _,d in ipairs(_pool) do pcall(function() d:Remove() end) end
    _pool={}
end

-- neon
local NW=Color3.fromRGB(255,255,255)
local NR=Color3.fromRGB(255,30,30)

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

-- ─── BUILD GUI ────────────────────────────────────────────────────────────────
local function _build_gui()
    _pulse_fns={}

    -- limpa anterior
    pcall(function()
        game:GetService("CoreGui"):FindFirstChild(_pfx.."G"):Destroy()
    end)
    pcall(function()
        _lp.PlayerGui:FindFirstChild(_pfx.."G"):Destroy()
    end)

    local gui=Instance.new("ScreenGui")
    gui.Name=_pfx.."G"
    gui.ResetOnSpawn=false
    gui.DisplayOrder=999
    gui.IgnoreGuiInset=true
    gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling

    -- tenta CoreGui, fallback PlayerGui, fallback gethui()
    local parented=false
    if not parented then
        pcall(function()
            gui.Parent=game:GetService("CoreGui")
            parented=true
        end)
    end
    if not parented then
        pcall(function()
            gui.Parent=_lp:WaitForChild("PlayerGui",3)
            parented=true
        end)
    end
    if not parented then
        -- alguns executores expõem gethui()
        pcall(function()
            gui.Parent=gethui()
            parented=true
        end)
    end
    if not parented then
        warn("[TC] falha ao parental GUI")
        return nil, nil
    end

    _gui_ref=gui

    -- janela
    local win=Instance.new("Frame")
    win.Name="Win"
    win.Size=UDim2.new(0,220,0,390)
    win.Position=UDim2.new(0,20,0.5,-195)
    win.BackgroundColor3=Color3.fromRGB(12,12,16)
    win.BorderSizePixel=0
    win.Active=true
    win.Draggable=true
    win.ClipsDescendants=true
    win.Parent=gui
    Instance.new("UICorner",win).CornerRadius=UDim.new(0,10)

    local ws=_stroke(win,NW,2,0)
    table.insert(_pulse_fns,_mk_pulse(ws,0,0.35,1.2))

    -- imagem de fundo
    local bg=Instance.new("ImageLabel")
    bg.Size=UDim2.new(1,0,0,115)
    bg.Position=UDim2.new(0,0,0,0)
    bg.BackgroundTransparency=1
    bg.Image="rbxassetid://113175072724158"
    bg.ImageTransparency=0.1
    bg.ScaleType=Enum.ScaleType.Fit
    bg.ZIndex=1
    bg.Parent=win

    local gr=Instance.new("UIGradient")
    gr.Transparency=NumberSequence.new({
        NumberSequenceKeypoint.new(0,0),
        NumberSequenceKeypoint.new(0.65,0),
        NumberSequenceKeypoint.new(1,1),
    })
    gr.Rotation=90; gr.Parent=bg

    -- título
    local bar=Instance.new("Frame")
    bar.Size=UDim2.new(1,0,0,30)
    bar.Position=UDim2.new(0,0,0,108)
    bar.BackgroundColor3=Color3.fromRGB(8,8,12)
    bar.BackgroundTransparency=0.1
    bar.BorderSizePixel=0
    bar.ZIndex=2; bar.Parent=win

    local ttl=Instance.new("TextLabel")
    ttl.Size=UDim2.new(1,0,1,0)
    ttl.BackgroundTransparency=1
    ttl.Text="☯︎TONY COUNTRY☯︎"
    ttl.TextColor3=Color3.fromRGB(230,230,255)
    ttl.TextSize=12
    ttl.Font=Enum.Font.GothamBold
    ttl.ZIndex=3; ttl.Parent=bar
    _stroke(ttl,NW,1,0.3)

    -- row factory
    local function _row(label,state,y,cb)
        local row=Instance.new("Frame")
        row.Size=UDim2.new(1,-20,0,26)
        row.Position=UDim2.new(0,10,0,y)
        row.BackgroundColor3=Color3.fromRGB(18,18,24)
        row.BorderSizePixel=0; row.ZIndex=2; row.Parent=win
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,6)
        local rs=_stroke(row,NW,1.2,1)

        local lbl=Instance.new("TextLabel")
        lbl.Size=UDim2.new(0.65,0,1,0)
        lbl.Position=UDim2.new(0,8,0,0)
        lbl.BackgroundTransparency=1
        lbl.Text=label
        lbl.TextColor3=Color3.fromRGB(190,190,210)
        lbl.TextSize=11; lbl.Font=Enum.Font.Gotham
        lbl.TextXAlignment=Enum.TextXAlignment.Left
        lbl.ZIndex=3; lbl.Parent=row

        local btn=Instance.new("TextButton")
        btn.Size=UDim2.new(0,42,0,18)
        btn.Position=UDim2.new(1,-50,0.5,-9)
        btn.BackgroundColor3=Color3.fromRGB(50,50,60)
        btn.Text="OFF"
        btn.TextColor3=Color3.fromRGB(150,150,160)
        btn.TextSize=10; btn.Font=Enum.Font.GothamBold
        btn.BorderSizePixel=0; btn.ZIndex=3; btn.Parent=row
        Instance.new("UICorner",btn).CornerRadius=UDim.new(0,4)
        local bs=_stroke(btn,NW,1,1)

        local _st=state
        local _pf=nil  -- pulse fn slot

        local function _refresh()
            if _st then
                btn.BackgroundColor3=Color3.fromRGB(230,230,255)
                btn.TextColor3=Color3.fromRGB(10,10,20)
                btn.Text="ON"
                bs.Transparency=0; rs.Transparency=0
                -- substitui pulse fn
                if _pf then
                    for i,fn in ipairs(_pulse_fns) do
                        if fn==_pf then table.remove(_pulse_fns,i); break end
                    end
                end
                _pf=_mk_pulse(bs,0,0.4,2.0)
                table.insert(_pulse_fns,_pf)
            else
                btn.BackgroundColor3=Color3.fromRGB(50,50,60)
                btn.TextColor3=Color3.fromRGB(150,150,160)
                btn.Text="OFF"
                bs.Transparency=1; rs.Transparency=1
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

    local R_Y=142
    local R_G=29
    local defs={
        {"ESP",         CFG.esp,           function(v) CFG.esp=v end},
        {"  Box",       CFG.esp_box,       function(v) CFG.esp_box=v end},
        {"  Nome",      CFG.esp_name,      function(v) CFG.esp_name=v end},
        {"  Distância", CFG.esp_dist,      function(v) CFG.esp_dist=v end},
        {"  HP Bar",    CFG.esp_hp,        function(v) CFG.esp_hp=v end},
        {"Aimbot",      CFG.aim,           function(v) CFG.aim=v end},
        {"  TeamCheck", CFG.aim_teamcheck, function(v) CFG.aim_teamcheck=v end},
    }
    for i,d in ipairs(defs) do _row(d[1],d[2],R_Y+(i-1)*R_G,d[3]) end

    -- keybinds info
    local info=Instance.new("TextLabel")
    info.Size=UDim2.new(1,-20,0,16)
    info.Position=UDim2.new(0,10,1,-54)
    info.BackgroundTransparency=1
    info.Text="X = toggle aim  |  RMB = hold aim"
    info.TextColor3=Color3.fromRGB(90,90,110)
    info.TextSize=9; info.Font=Enum.Font.Gotham
    info.TextXAlignment=Enum.TextXAlignment.Center
    info.ZIndex=3; info.Parent=win

    -- DESTRUCT
    local db=Instance.new("TextButton")
    db.Size=UDim2.new(1,-20,0,26)
    db.Position=UDim2.new(0,10,1,-30)
    db.BackgroundColor3=Color3.fromRGB(18,4,4)
    db.Text="✖  DESTRUCT"
    db.TextColor3=NR
    db.TextSize=12; db.Font=Enum.Font.GothamBold
    db.BorderSizePixel=0; db.ZIndex=3; db.Parent=win
    Instance.new("UICorner",db).CornerRadius=UDim.new(0,6)
    local ds=_stroke(db,NR,1.5,0)
    table.insert(_pulse_fns,_mk_pulse(ds,0,0.5,1.8))

    db.MouseButton1Click:Connect(function()
        _DESTROYED=true
        _clr()
        pcall(function() _fc:Remove() end)
        pcall(function() _gui_ref:Destroy() end)
    end)

    _win_ref=win
    return gui, win
end

-- ─── build ────────────────────────────────────────────────────────────────────
_build_gui()

-- ─── keybinds ─────────────────────────────────────────────────────────────────
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

-- ─── utils ────────────────────────────────────────────────────────────────────
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

-- ─── esp ──────────────────────────────────────────────────────────────────────
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
            for _,seg in ipairs({
                {Vector2.new(bx,by),Vector2.new(bx+bw,by)},
                {Vector2.new(bx+bw,by),Vector2.new(bx+bw,by+bh)},
                {Vector2.new(bx+bw,by+bh),Vector2.new(bx,by+bh)},
                {Vector2.new(bx,by+bh),Vector2.new(bx,by)},
            }) do
                _nd("Line",{From=seg[1],To=seg[2],Color=CFG.esp_color,Thickness=1,Visible=true,ZIndex=1})
            end
        end
        if CFG.esp_name and bx then
            _nd("Text",{Text=p.Name,Position=Vector2.new(bx+bw/2,by-14),
                Size=13,Color=Color3.new(1,1,1),Outline=true,Center=true,Visible=true,ZIndex=2})
        end
        if CFG.esp_dist and bx then
            _nd("Text",{Text=("%.0fm"):format(dist),Position=Vector2.new(bx+bw/2,by+bh+2),
                Size=11,Color=Color3.fromRGB(200,200,200),Outline=true,Center=true,Visible=true,ZIndex=2})
        end
        if CFG.esp_hp and bx then
            local h=char:FindFirstChildOfClass("Humanoid")
            if h then
                local r=math.clamp(h.Health/h.MaxHealth,0,1)
                local bx2=bx-6
                _nd("Line",{From=Vector2.new(bx2,by),To=Vector2.new(bx2,by+bh),
                    Color=Color3.new(0,0,0),Thickness=3,Visible=true,ZIndex=1})
                _nd("Line",{From=Vector2.new(bx2,by+bh),To=Vector2.new(bx2,by+bh-(bh*r)),
                    Color=Color3.fromRGB(math.floor(255*(1-r)),math.floor(255*r),0),
                    Thickness=2,Visible=true,ZIndex=2})
            end
        end
    end
end

-- ─── aimbot ───────────────────────────────────────────────────────────────────
local _jt=0
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
        math.sin(_jt*1.3)*0.015,math.cos(_jt*0.9)*0.012,0)
    local cur=_cam.CFrame
    local tgt=CFrame.new(cur.Position,jp)
    local ad=math.acos(math.clamp(cur.LookVector:Dot(tgt.LookVector),-1,1))
    local sm=CFG.aim_smooth+math.clamp(ad*0.3,0,0.4)
    _cam.CFrame=cur:Lerp(tgt,math.clamp(sm,0.05,0.9))
end

-- ─── loop ─────────────────────────────────────────────────────────────────────
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
