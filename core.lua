-- TONY COUNTRY v4 | Stealth Edition
-- Stack: Roblox Lua (Luau) | Synapse X, KRNL, Fluxus...
-- New: HP bar toggle, mouse button keybinds, LShift hide/show, hardened evasion

-- ============================================================
-- [ 0 ] EVASION LAYER — executa antes de tudo
-- ============================================================

-- 0.1 spoof executor identity
pcall(function() getexecutorname  = function() return nil end end)
pcall(function() identifyexecutor = function() return "unknown","0.0.0" end end)

-- 0.2 string encoder — sem literais visíveis em scan de memória
local function S(t)
    local r={} for i,v in ipairs(t) do r[i]=string.char(v) end return table.concat(r)
end

local STR_COREGUI    = S({67,111,114,101,71,117,105})
local STR_PLAYERS    = S({80,108,97,121,101,114,115})
local STR_RS         = S({82,117,110,83,101,114,118,105,99,101})
local STR_UIS        = S({85,115,101,114,73,110,112,117,116,83,101,114,118,105,99,101})
local STR_RENDER     = S({82,101,110,100,101,114,83,116,101,112,112,101,100})
local STR_GUINAME    = S({95,84,67,52,95,120,120})   -- "_TC4_xx"

-- 0.3 localize stdlib — impede hook via __index em _G
local _rawset   = rawset
local _rawget   = rawget
local _pairs    = pairs
local _ipairs   = ipairs
local _pcall    = pcall
local _math     = math
local _table    = table
local _tostring = tostring
local _type     = type
local _unpack   = table.unpack or unpack

-- 0.4 GUI protection
local function ProtectGui(gui)
    if syn and syn.protect_gui then
        _pcall(function() syn.protect_gui(gui) end)
    elseif protect_gui then
        _pcall(function() protect_gui(gui) end)
    elseif gethui then
        _pcall(function() gui.Parent = gethui() end)
        return true
    end
    return false
end

-- 0.5 hook-safe Drawing — recria Drawing.new através de rawget
-- alguns AC hookeiam Drawing.new globalmente; usamos pcall em cada create
local function SafeDraw(kind)
    local ok, d = _pcall(function() return Drawing.new(kind) end)
    return ok and d or nil
end

-- 0.6 environment isolation — variáveis internas não aparecem em _G scan
local _ENV_ISOLATED = setmetatable({},{
    __index    = _G,
    __newindex = function(t,k,v) _rawset(t,k,v) end,
    __metatable= false,
})

-- 0.7 anti-screenshot
local _screenshot = false

-- 0.8 timing jitter seed
_math.randomseed(os.clock() * 1e9 % 2^31)

-- ============================================================
-- SERVICES
-- ============================================================
local Players    = game:GetService(STR_PLAYERS)
local RunService = game:GetService(STR_RS)
local UIS        = game:GetService(STR_UIS)
local Camera     = workspace.CurrentCamera
local LP         = Players.LocalPlayer

-- ============================================================
-- STATE
-- ============================================================
local State = {
    ESPBox        = false,
    ESPName       = false,
    ESPHealth     = false,   -- text "120 hp"
    ESPHPBar      = false,   -- barra visual
    ESPDistance   = false,
    AimbotEnabled = false,
    FOV           = 120,
    Smooth        = 18,      -- 2–95 (percent)
    -- keybind: pode ser KeyCode OU MouseButton
    AimbotBindType = "key",           -- "key" | "mouse"
    AimbotKey      = Enum.KeyCode.LeftAlt,
    AimbotMouse    = Enum.UserInputType.MouseButton2,
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
    BG          = Color3.fromRGB(3,   3,   3),
    BG2         = Color3.fromRGB(9,   9,   9),
    BG3         = Color3.fromRGB(15,  15,  15),
    BORDER      = Color3.fromRGB(255, 255, 255),
    BORDER_DIM  = Color3.fromRGB(48,  48,  48),
    TEXT        = Color3.fromRGB(235, 235, 235),
    TEXT_DIM    = Color3.fromRGB(100, 100, 100),
    RED         = Color3.fromRGB(215,  38,  38),
    RED_HOVER   = Color3.fromRGB(255,  65,  65),
    RED_BG      = Color3.fromRGB(18,   4,   4),
    GREEN       = Color3.fromRGB(72,  230, 110),
    KNOB_ON     = Color3.fromRGB(3,    3,   3),
    KNOB_OFF    = Color3.fromRGB(90,  90,  90),
    TOG_ON      = Color3.fromRGB(255, 255, 255),
    TOG_OFF     = Color3.fromRGB(24,  24,  24),
}

-- ============================================================
-- DRAWING HELPERS
-- ============================================================
local function NewLine(col, thick)
    local d = SafeDraw("Line"); if not d then return end
    d.Color=col or C.BORDER; d.Thickness=thick or 1.4; d.Visible=false; return d
end
local function NewText(col, sz)
    local d = SafeDraw("Text"); if not d then return end
    d.Color=col or C.TEXT; d.Size=sz or 13
    d.Font=Drawing.Fonts.Monospace; d.Outline=true
    d.OutlineColor=Color3.new(0,0,0); d.Visible=false; return d
end
local function NewSquare(col, thick, filled)
    local d = SafeDraw("Square"); if not d then return end
    d.Color=col or C.BORDER; d.Thickness=thick or 1.5
    d.Filled=filled or false; d.Visible=false; return d
end
local function NewCircle(col, thick)
    local d = SafeDraw("Circle"); if not d then return end
    d.Color=col or C.BORDER; d.Thickness=thick or 1.5
    d.Filled=false; d.NumSides=64; d.Visible=false; return d
end

-- corner-bracket (12 linhas)
local function NewBracket()
    local ls={}
    for i=1,12 do
        local l=SafeDraw("Line")
        if l then l.Color=C.BORDER; l.Thickness=1.8; l.Visible=false end
        ls[i]=l
    end
    return ls
end

local function UpdateBracket(ls, x, y, w, h)
    local seg = _math.min(w,h)*0.22
    local function set(i, fx,fy, tx,ty)
        if not ls[i] then return end
        ls[i].From=Vector2.new(fx,fy); ls[i].To=Vector2.new(tx,ty)
    end
    set(1,  x,       y+seg,  x,       y      )
    set(2,  x,       y,      x+seg,   y      )
    set(3,  x,       y+h*.5-1, x,     y+h*.5+1)
    set(4,  x+w-seg, y,      x+w,     y      )
    set(5,  x+w,     y,      x+w,     y+seg  )
    set(6,  x+w,     y+h*.5-1, x+w,   y+h*.5+1)
    set(7,  x,       y+h-seg, x,      y+h    )
    set(8,  x,       y+h,    x+seg,   y+h    )
    set(9,  x+w-seg, y+h,    x+w,     y+h    )
    set(10, x+w,     y+h-seg, x+w,    y+h    )
    set(11, x+w*.5-3,y+h+5,  x+w*.5+3,y+h+5 )
    set(12, x+w*.5,  y+h+2,  x+w*.5,  y+h+8 )
end

local function BracketVis(ls, v)
    for _,l in _ipairs(ls) do if l then l.Visible=v end end
end

-- ============================================================
-- FOV CIRCLE
-- ============================================================
State.FOVCircle = NewCircle(Color3.fromRGB(255,255,255), 1.2)
if State.FOVCircle then State.FOVCircle.Transparency=0.6 end

local function UpdateFOV()
    local c = State.FOVCircle; if not c then return end
    if _screenshot then c.Visible=false; return end
    local vp = Camera.ViewportSize
    c.Position = Vector2.new(vp.X/2, vp.Y/2)
    c.Radius   = State.FOV
    c.Visible  = State.AimbotEnabled
end

-- ============================================================
-- WORLD TO SCREEN
-- ============================================================
local function W2V(pos)
    local vp,on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(vp.X,vp.Y), vp.Z, on
end
local function Parts(char)
    return char:FindFirstChild("HumanoidRootPart"),
           char:FindFirstChild("Head"),
           char:FindFirstChildOfClass("Humanoid")
end
local function Alive(p)
    if p==LP then return false end
    local c=p.Character; if not c then return false end
    local h,hd,hm=Parts(c)
    if not h or not hd or not hm then return false end
    return hm.Health>0
end

-- ============================================================
-- ESP
-- ============================================================
local function MakeESP(p)
    State.ESPObjects[p]={
        Bracket  = NewBracket(),
        Name     = NewText(Color3.fromRGB(255,255,255),13),
        HPText   = NewText(C.GREEN,12),
        Dist     = NewText(Color3.fromRGB(150,150,150),11),
        BarBG    = NewSquare(Color3.fromRGB(40,40,40),1,true),
        Bar      = NewSquare(C.GREEN,1,true),
    }
end

local function KillESP(p)
    local o=State.ESPObjects[p]; if not o then return end
    BracketVis(o.Bracket,false)
    for _,k in _ipairs({"Name","HPText","Dist","BarBG","Bar"}) do
        if o[k] then o[k]:Remove() end
    end
    State.ESPObjects[p]=nil
end

local function HideESPObj(o)
    BracketVis(o.Bracket,false)
    for _,k in _ipairs({"Name","HPText","Dist","BarBG","Bar"}) do
        if o[k] then o[k].Visible=false end
    end
end

local function TickESP(p,o)
    if _screenshot then HideESPObj(o); return end
    if not Alive(p) then HideESPObj(o); return end
    local char=p.Character
    local hrp,head,hum=Parts(char)
    local t2d,tZ,tOn = W2V(head.Position+Vector3.new(0,0.75,0))
    local b2d,bZ,bOn = W2V(hrp.Position -Vector3.new(0,2.6,0))
    if not tOn or tZ<=0 then HideESPObj(o); return end

    local h=_math.abs(t2d.Y-b2d.Y)
    local w=h*0.48
    local x=t2d.X-w/2

    -- box
    UpdateBracket(o.Bracket,x,t2d.Y,w,h)
    BracketVis(o.Bracket,State.ESPBox)

    -- name
    if o.Name then
        o.Name.Text=p.Name; o.Name.Position=Vector2.new(t2d.X,t2d.Y-17)
        o.Name.Center=true; o.Name.Visible=State.ESPName
    end

    -- hp text
    local hp   = _math.floor(hum.Health)
    local maxhp= _math.floor(_math.max(1,hum.MaxHealth))
    local ratio= _math.clamp(hp/maxhp,0,1)
    if o.HPText then
        o.HPText.Text=hp.."/"..maxhp; o.HPText.Position=Vector2.new(t2d.X,b2d.Y+3)
        o.HPText.Center=true; o.HPText.Visible=State.ESPHealth
    end

    -- hp bar (esquerda, vertical, 4px largura)
    local barW=4; local barX=x-8
    if o.BarBG then
        o.BarBG.Size=Vector2.new(barW,h); o.BarBG.Position=Vector2.new(barX,t2d.Y)
        o.BarBG.Visible=State.ESPHPBar
    end
    if o.Bar then
        local barH=_math.max(1,h*ratio)
        local r=_math.clamp(_math.floor(255*(1-ratio)*2),0,255)
        local g=_math.clamp(_math.floor(255*ratio*2),0,255)
        o.Bar.Color=Color3.fromRGB(r,g,50)
        o.Bar.Size=Vector2.new(barW,barH)
        o.Bar.Position=Vector2.new(barX,t2d.Y+(h-barH))
        o.Bar.Visible=State.ESPHPBar
    end

    -- distance
    if o.Dist then
        local dist=_math.floor((hrp.Position-Camera.CFrame.Position).Magnitude)
        o.Dist.Text=dist.."m"; o.Dist.Position=Vector2.new(x+w+5,t2d.Y)
        o.Dist.Visible=State.ESPDistance
    end
end

-- ============================================================
-- AIMBOT — humanizado + noise
-- ============================================================
local _nX,_nY,_lastAim=0,0,nil

local function UpdNoise()
    _nX=_nX*0.85+(_math.random()-0.5)*0.0015
    _nY=_nY*0.85+(_math.random()-0.5)*0.0015
end

-- verifica se a bind está pressionada (key OU mouse button)
local function BindHeld()
    if State.AimbotBindType=="mouse" then
        return UIS:IsMouseButtonPressed(State.AimbotMouse)
    else
        return UIS:IsKeyDown(State.AimbotKey)
    end
end

local function BestTarget()
    local vp=Camera.ViewportSize
    local ctr=Vector2.new(vp.X/2,vp.Y/2)
    local best,bestD=nil,_math.huge
    for _,p in _ipairs(Players:GetPlayers()) do
        if not Alive(p) then continue end
        local hd=p.Character:FindFirstChild("Head"); if not hd then continue end
        local p2d,z,on=W2V(hd.Position)
        if not on or z<=0 then continue end
        local d=(p2d-ctr).Magnitude
        if d<State.FOV and d<bestD then bestD=d; best=hd end
    end
    return best
end

local function RunAimbot()
    if not State.AimbotEnabled then return end
    if not BindHeld() then _lastAim=nil; return end
    local t=BestTarget(); if not t then return end
    UpdNoise()
    local tp=t.Position+Vector3.new(_nX*.5,_nY*.5,0)
    if _lastAim then
        if (tp-_lastAim).Magnitude>8 then tp=_lastAim:Lerp(tp,0.4) end
    end
    _lastAim=tp
    local cur=Camera.CFrame.LookVector
    local des=(tp-Camera.CFrame.Position).Unit
    local sf=1-(State.Smooth/100)
    Camera.CFrame=CFrame.new(Camera.CFrame.Position,Camera.CFrame.Position+cur:Lerp(des,sf))
end

-- ============================================================
-- PLAYER MANAGEMENT
-- ============================================================
for _,p in _ipairs(Players:GetPlayers()) do if p~=LP then MakeESP(p) end end

local cA=Players.PlayerAdded:Connect(function(p) task.wait(1); MakeESP(p) end)
local cR=Players.PlayerRemoving:Connect(function(p) KillESP(p) end)
_table.insert(State.Connections,cA)
_table.insert(State.Connections,cR)

-- screenshot guard
UIS.InputBegan:Connect(function(inp)
    if inp.KeyCode==Enum.KeyCode.Print or inp.KeyCode==Enum.KeyCode.SysRq then
        _screenshot=true; task.delay(0.35,function() _screenshot=false end)
    end
end)

-- ============================================================
-- RENDER LOOP
-- ============================================================
local _slot=0
local rcConn=RunService[STR_RENDER]:Connect(function()
    if State.Destroyed then return end
    _slot=(_slot+1)%2
    UpdateFOV(); RunAimbot()
    if _slot==0 then
        for p,o in _pairs(State.ESPObjects) do TickESP(p,o) end
    end
end)
_table.insert(State.Connections,rcConn)

-- ============================================================
-- GUI UTILS
-- ============================================================
local function Fr(par,sz,pos,col,tr)
    local f=Instance.new("Frame")
    f.Size=sz; f.Position=pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3=col or C.BG; f.BackgroundTransparency=tr or 0
    f.BorderSizePixel=0; f.Parent=par; return f
end
local function Lbl(par,txt,sz,pos,col,fs,xa)
    local l=Instance.new("TextLabel")
    l.Size=sz; l.Position=pos or UDim2.new(0,0,0,0)
    l.BackgroundTransparency=1; l.Text=txt
    l.TextColor3=col or C.TEXT; l.TextSize=12
    l.Font=fs or Enum.Font.GothamMedium
    l.TextXAlignment=xa or Enum.TextXAlignment.Left
    l.Parent=par; return l
end
local function Corn(par,px)
    local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,px or 6); c.Parent=par; return c
end
local function Strk(par,col,th)
    local s=Instance.new("UIStroke"); s.Color=col or C.BORDER; s.Thickness=th or 1.5; s.Parent=par; return s
end

-- ============================================================
-- SCREENGI
-- ============================================================
local SG=Instance.new("ScreenGui")
SG.Name=STR_GUINAME; SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
SG.Parent=game:GetService(STR_COREGUI)
local movedHUI=ProtectGui(SG)
if not movedHUI then _pcall(function() SG.IgnoreGuiInset=true end) end

-- aura glow
local Aura=Fr(SG,UDim2.new(0,324,0,10),UDim2.new(0.5,-162,0.5,-5),C.BORDER,0.92)
Corn(Aura,10)

-- main frame
local MF=Fr(SG,UDim2.new(0,318,0,10),UDim2.new(0.5,-159,0.5,-5),C.BG)
Corn(MF,8); Strk(MF,C.BORDER,1.5)
MF.Active=true; MF.Draggable=true

-- header
local Header=Fr(MF,UDim2.new(1,0,0,48),UDim2.new(0,0,0,0),C.BG2)
Corn(Header,8)
Fr(Header,UDim2.new(1,0,0,8),UDim2.new(0,0,1,-8),C.BG2)   -- bottom square-off

local TitleL=Lbl(Header,"TONY COUNTRY",UDim2.new(1,0,0,26),UDim2.new(0,0,0,6),
    C.BORDER,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
TitleL.TextSize=16; TitleL.TextStrokeTransparency=0.4; TitleL.TextStrokeColor3=C.BORDER

local SubL=Lbl(Header,"✦  v4  STEALTH EDITION  ✦",UDim2.new(1,0,0,14),UDim2.new(0,0,0,32),
    Color3.fromRGB(70,70,70),Enum.Font.GothamMedium,Enum.TextXAlignment.Center)
SubL.TextSize=9

Fr(MF,UDim2.new(1,-24,0,1),UDim2.new(0,12,0,48),C.BORDER,0.8)  -- sep line

-- hide hint
local HintL=Lbl(MF,"LShift → ocultar",UDim2.new(1,-20,0,14),UDim2.new(0,10,0,52),
    Color3.fromRGB(50,50,50),Enum.Font.GothamMedium,Enum.TextXAlignment.Right)
HintL.TextSize=9

-- content container
local Content=Fr(MF,UDim2.new(1,-20,0,10),UDim2.new(0,10,0,70))
Content.BackgroundTransparency=1

local yOff=0
local function NY(h,gap) local y=yOff; yOff=yOff+h+(gap or 5); return y end

-- section header
local function SecHdr(text)
    local f=Fr(Content,UDim2.new(1,0,0,16),UDim2.new(0,0,0,NY(16,3)))
    f.BackgroundTransparency=1
    local l=Lbl(f,text,UDim2.new(0.4,0,1,0),UDim2.new(0,0,0,0),
        Color3.fromRGB(75,75,75),Enum.Font.GothamBold)
    l.TextSize=9
    Fr(f,UDim2.new(0.56,0,0,1),UDim2.new(0.42,0,0.5,0),C.BORDER_DIM)
end

-- toggle
local function MkToggle(label,get,set)
    local row=Fr(Content,UDim2.new(1,0,0,30),UDim2.new(0,0,0,NY(30,4)),C.BG3)
    Corn(row,5); Strk(row,C.BORDER_DIM,1)
    -- led
    local led=Fr(row,UDim2.new(0,3,0.56,0),UDim2.new(0,0,0.22,0),C.BORDER_DIM); Corn(led,2)
    local lbl=Lbl(row,label,UDim2.new(1,-54,1,0),UDim2.new(0,10,0,0),C.TEXT,Enum.Font.GothamMedium)
    lbl.TextSize=12
    -- pill
    local pill=Fr(row,UDim2.new(0,38,0,20),UDim2.new(1,-42,0.5,-10),C.TOG_OFF); Corn(pill,10)
    local ps=Strk(pill,C.BORDER_DIM,1)
    local knob=Fr(pill,UDim2.new(0,14,0,14),UDim2.new(0,3,0.5,-7),C.KNOB_OFF); Corn(knob,7)
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.Parent=row
    local function Ref()
        local on=get()
        pill.BackgroundColor3 = on and C.TOG_ON  or C.TOG_OFF
        ps.Color              = on and C.BORDER  or C.BORDER_DIM
        knob.Position         = on and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)
        knob.BackgroundColor3 = on and C.KNOB_ON or C.KNOB_OFF
        led.BackgroundColor3  = on and C.BORDER  or C.BORDER_DIM
    end
    Ref()
    btn.MouseButton1Click:Connect(function() set(not get()); Ref() end)
    btn.MouseEnter:Connect(function() row.BackgroundColor3=Color3.fromRGB(19,19,19) end)
    btn.MouseLeave:Connect(function() row.BackgroundColor3=C.BG3 end)
end

-- slider
local function MkSlider(prefix,get,set,mn,mx)
    local row=Fr(Content,UDim2.new(1,0,0,40),UDim2.new(0,0,0,NY(40,4)),C.BG3)
    Corn(row,5); Strk(row,C.BORDER_DIM,1)
    local lbl=Lbl(row,prefix..get(),UDim2.new(1,-12,0,16),UDim2.new(0,10,0,3),C.TEXT,Enum.Font.GothamMedium)
    lbl.TextSize=11
    local track=Fr(row,UDim2.new(1,-20,0,4),UDim2.new(0,10,1,-11),C.BORDER_DIM); Corn(track,2)
    local rel=(get()-mn)/(mx-mn)
    local fill=Fr(track,UDim2.new(rel,0,1,0),UDim2.new(0,0,0,0),C.BORDER); Corn(fill,2)
    local knob=Instance.new("TextButton")
    knob.Size=UDim2.new(0,12,0,12); knob.AnchorPoint=Vector2.new(0.5,0.5)
    knob.Position=UDim2.new(rel,0,0.5,0); knob.BackgroundColor3=C.BORDER
    knob.BorderSizePixel=0; knob.Text=""; knob.Parent=track; Corn(knob,6)
    local drag=false
    knob.MouseButton1Down:Connect(function() drag=true end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
    end)
    RunService[STR_RENDER]:Connect(function()
        if not drag then return end
        local mx2=UIS:GetMouseLocation().X
        local tp=track.AbsolutePosition.X; local tw=track.AbsoluteSize.X
        local r=_math.clamp((mx2-tp)/tw,0,1)
        local v=_math.floor(mn+r*(mx-mn)); set(v)
        fill.Size=UDim2.new(r,0,1,0); knob.Position=UDim2.new(r,0,0.5,0)
        lbl.Text=prefix..get()
    end)
end

-- keybind (key + mouse button)
local MOUSE_NAMES = {
    [Enum.UserInputType.MouseButton1] = "Mouse1",
    [Enum.UserInputType.MouseButton2] = "Mouse2",
    [Enum.UserInputType.MouseButton3] = "Mouse3",
}

local function MkKeybind()
    local row=Fr(Content,UDim2.new(1,0,0,30),UDim2.new(0,0,0,NY(30,4)),C.BG3)
    Corn(row,5); Strk(row,C.BORDER_DIM,1)
    local lbl=Lbl(row,"Aimbot Key",UDim2.new(0.55,0,1,0),UDim2.new(0,10,0,0),C.TEXT,Enum.Font.GothamMedium)
    lbl.TextSize=12

    local kbtn=Instance.new("TextButton")
    kbtn.Size=UDim2.new(0,86,0,22); kbtn.Position=UDim2.new(1,-92,0.5,-11)
    kbtn.BackgroundColor3=C.BG2; kbtn.BorderSizePixel=0
    kbtn.TextColor3=C.TEXT; kbtn.TextSize=10; kbtn.Font=Enum.Font.GothamBold
    kbtn.Text="L-ALT"; kbtn.Parent=row
    Corn(kbtn,4); Strk(kbtn,C.BORDER_DIM,1)

    -- label menor abaixo
    local hint=Lbl(row,"clique p/ mudar • aceita mouse",
        UDim2.new(1,-12,0,10),UDim2.new(0,10,1,-1),
        Color3.fromRGB(50,50,50),Enum.Font.GothamMedium)
    hint.TextSize=8

    local listening=false
    kbtn.MouseButton1Click:Connect(function()
        listening=true; kbtn.Text="· · ·"
        kbtn.TextColor3=Color3.fromRGB(140,140,140)
    end)

    -- captura teclado
    UIS.InputBegan:Connect(function(inp,gpe)
        if gpe or not listening then return end
        -- mouse buttons
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or
           inp.UserInputType==Enum.UserInputType.MouseButton2 or
           inp.UserInputType==Enum.UserInputType.MouseButton3 then
            State.AimbotBindType = "mouse"
            State.AimbotMouse    = inp.UserInputType
            kbtn.Text            = MOUSE_NAMES[inp.UserInputType] or "Mouse?"
            kbtn.TextColor3      = C.TEXT
            listening            = false
        elseif inp.UserInputType==Enum.UserInputType.Keyboard then
            -- bloqueia LShift de virar keybind (reservado ao hide)
            if inp.KeyCode==Enum.KeyCode.LeftShift then return end
            State.AimbotBindType = "key"
            State.AimbotKey      = inp.KeyCode
            kbtn.Text            = _tostring(inp.KeyCode):gsub("Enum%.KeyCode%.","")
            kbtn.TextColor3      = C.TEXT
            listening            = false
        end
    end)
end

-- ============================================================
-- BUILD UI
-- ============================================================
SecHdr("— ESP")
MkToggle("Box ESP",      function() return State.ESPBox      end, function(v) State.ESPBox      =v end)
MkToggle("Name ESP",     function() return State.ESPName     end, function(v) State.ESPName     =v end)
MkToggle("Health Text",  function() return State.ESPHealth   end, function(v) State.ESPHealth   =v end)
MkToggle("Health Bar",   function() return State.ESPHPBar    end, function(v) State.ESPHPBar    =v end)
MkToggle("Distance",     function() return State.ESPDistance end, function(v) State.ESPDistance =v end)

SecHdr("— Aimbot")
MkToggle("Aimbot",       function() return State.AimbotEnabled end, function(v)
    State.AimbotEnabled=v; UpdateFOV()
end)
MkSlider("FOV  ",    function() return State.FOV    end, function(v) State.FOV=v    end, 20,500)
MkSlider("Smooth  ", function() return State.Smooth end, function(v) State.Smooth=v end, 2,95)
MkKeybind()

-- ============================================================
-- STATUS + DESTRUCT
-- ============================================================
local sepY=yOff+70+8
Fr(MF,UDim2.new(1,-24,0,1),UDim2.new(0,12,0,sepY),C.BORDER_DIM,0.5)

local StatL=Lbl(MF,"● ACTIVE  |  STEALTH ON",
    UDim2.new(1,-20,0,14),UDim2.new(0,12,0,sepY+6),
    Color3.fromRGB(55,55,55),Enum.Font.GothamMedium)
StatL.TextSize=10

local DBtn=Instance.new("TextButton")
DBtn.Size=UDim2.new(1,-20,0,50); DBtn.Position=UDim2.new(0,10,0,sepY+26)
DBtn.BackgroundColor3=C.RED_BG; DBtn.BorderSizePixel=0
DBtn.Text="DESTRUCT"; DBtn.TextColor3=C.RED
DBtn.TextSize=18; DBtn.Font=Enum.Font.GothamBold
DBtn.TextStrokeTransparency=0.4; DBtn.TextStrokeColor3=C.RED
DBtn.Parent=MF; Corn(DBtn,6)
local DS=Strk(DBtn,C.RED,1.6)

-- pulso na borda vermelha
local _dp=0
local dpConn=RunService[STR_RENDER]:Connect(function()
    if State.Destroyed then return end
    _dp=_dp+0.055
    DS.Thickness=1.2+_math.sin(_dp)*0.5
end)
_table.insert(State.Connections,dpConn)

DBtn.MouseEnter:Connect(function()
    DBtn.BackgroundColor3=Color3.fromRGB(32,6,6)
    DBtn.TextColor3=C.RED_HOVER; DS.Color=C.RED_HOVER
end)
DBtn.MouseLeave:Connect(function()
    DBtn.BackgroundColor3=C.RED_BG
    DBtn.TextColor3=C.RED; DS.Color=C.RED
end)

DBtn.MouseButton1Click:Connect(function()
    State.Destroyed=true
    for _,c in _ipairs(State.Connections) do _pcall(function() c:Disconnect() end) end
    _table.clear(State.Connections)
    for p in _pairs(State.ESPObjects) do KillESP(p) end
    if State.FOVCircle then State.FOVCircle:Remove() end
    _pcall(function() SG:Destroy() end)
    _pcall(function() Aura:Destroy() end)
end)

-- ============================================================
-- RESIZE FRAME PARA CONTEÚDO
-- ============================================================
local totalH = sepY + 26 + 50 + 14
MF.Size    = UDim2.new(0,318,0,totalH)
Aura.Size  = UDim2.new(0,324,0,totalH+6)
MF.Position  = UDim2.new(0.5,-159,0.5,-(totalH/2))
Aura.Position= UDim2.new(0.5,-162,0.5,-(totalH/2)-3)
Content.Size = UDim2.new(1,-20,0,yOff)

-- ============================================================
-- LSHIFT HIDE / SHOW
-- ============================================================
local shiftConn=UIS.InputBegan:Connect(function(inp,gpe)
    if gpe then return end
    if inp.KeyCode==Enum.KeyCode.LeftShift then
        State.PanelVisible=not State.PanelVisible
        MF.Visible   = State.PanelVisible
        Aura.Visible = State.PanelVisible
    end
end)
_table.insert(State.Connections,shiftConn)
