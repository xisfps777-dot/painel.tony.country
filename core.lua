 local function _build_gui()
    pcall(function()
        local old = game:GetService("CoreGui"):FindFirstChild(_pfx .. "GUI")
        if old then old:Destroy() end
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name              = _pfx .. "GUI"
    gui.ResetOnSpawn      = false
    gui.DisplayOrder      = 999
    gui.IgnoreGuiInset    = true

    local ok = pcall(function()
        gui.Parent = game:GetService("CoreGui")
    end)
    if not ok then
        gui.Parent = _lp:WaitForChild("PlayerGui")
    end

    -- janela principal — altura aumentada pra caber a imagem no topo
    local win = Instance.new("Frame")
    win.Name              = "Win"
    win.Size              = UDim2.new(0, 220, 0, 360)
    win.Position          = UDim2.new(0, 20, 0.5, -180)
    win.BackgroundColor3  = Color3.fromRGB(18, 18, 22)
    win.BorderSizePixel   = 0
    win.Active            = true
    win.Draggable         = true
    win.Parent            = gui
    win.ClipsDescendants  = true
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 8)

    -- ── IMAGEM DE FUNDO (anjo/diabo yin yang) ────────────────────────────────
    -- Roblox não aceita URLs externas em ImageLabel — precisa de asset ID
    -- FILL: sobe a imagem em roblox.com/create → Decals → pega o ID
    --       formato: "rbxassetid://ID_AQUI"
    local bg_img = Instance.new("ImageLabel")
    bg_img.Size                 = UDim2.new(1, 0, 0, 110)
    bg_img.Position             = UDim2.new(0, 0, 0, 0)
    bg_img.BackgroundTransparency = 1
    bg_img.Image                = "rbxassetid://74387664833992"
    bg_img.ImageTransparency    = 0.15   -- leve transparência pra não cobrir o título
    bg_img.ScaleType            = Enum.ScaleType.Fit
    bg_img.ZIndex               = 0
    bg_img.Parent               = win

    -- gradiente sobre a imagem (fade pra baixo, integra com o fundo escuro)
    local grad = Instance.new("UIGradient")
    grad.Color      = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(0,0,0)),
        ColorSequenceKeypoint.new(0.6, Color3.new(0,0,0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(18,18,22)),
    })
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.7, 1),
        NumberSequenceKeypoint.new(1, 0),
    })
    grad.Rotation   = 90
    grad.Parent     = bg_img

    -- ── BARRA DE TÍTULO ───────────────────────────────────────────────────────
    local bar = Instance.new("Frame")
    bar.Size             = UDim2.new(1, 0, 0, 30)
    bar.Position         = UDim2.new(0, 0, 0, 100)   -- abaixo da imagem
    bar.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    bar.BackgroundTransparency = 0.3
    bar.BorderSizePixel  = 0
    bar.ZIndex           = 2
    bar.Parent           = win

    local title = Instance.new("TextLabel")
    title.Size                 = UDim2.new(1, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Text                 = "☯︎TONY COUNTRY☯︎"
    title.TextColor3           = Color3.fromRGB(220, 220, 240)
    title.TextSize             = 13
    title.Font                 = Enum.Font.GothamBold
    title.ZIndex               = 3
    title.Parent               = bar

    -- ── TOGGLE ROWS ───────────────────────────────────────────────────────────
    local function _row(parent, label, state, y, on_toggle)
        local row = Instance.new("Frame")
        row.Size             = UDim2.new(1, -20, 0, 28)
        row.Position         = UDim2.new(0, 10, 0, y)
        row.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
        row.BorderSizePixel  = 0
        row.ZIndex           = 2
        row.Parent           = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel")
        lbl.Size                 = UDim2.new(0.7, 0, 1, 0)
        lbl.Position             = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text                 = label
        lbl.TextColor3           = Color3.fromRGB(200, 200, 215)
        lbl.TextSize             = 12
        lbl.Font                 = Enum.Font.Gotham
        lbl.TextXAlignment       = Enum.TextXAlignment.Left
        lbl.ZIndex               = 3
        lbl.Parent               = row

        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(0, 44, 0, 20)
        btn.Position         = UDim2.new(1, -54, 0.5, -10)
        btn.BackgroundColor3 = state and Color3.fromRGB(80,200,100) or Color3.fromRGB(200,70,70)
        btn.Text             = state and "ON" or "OFF"
        btn.TextColor3       = Color3.new(1,1,1)
        btn.TextSize         = 11
        btn.Font             = Enum.Font.GothamBold
        btn.BorderSizePixel  = 0
        btn.ZIndex           = 3
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
        {"ESP",          CFG.esp,            function(v) CFG.esp = v end},
        {"  Box",        CFG.esp_box,        function(v) CFG.esp_box = v end},
        {"  Nome",       CFG.esp_name,       function(v) CFG.esp_name = v end},
        {"  Distância",  CFG.esp_dist,       function(v) CFG.esp_dist = v end},
        {"  HP Bar",     CFG.esp_hp,         function(v) CFG.esp_hp = v end},
        {"Aimbot",       CFG.aim,            function(v) CFG.aim = v end},
        {"  Team Check", CFG.aim_teamcheck,  function(v) CFG.aim_teamcheck = v end},
    }

    -- offset Y começa após imagem + barra de título
    for i, r in ipairs(rows) do
        _row(win, r[1], r[2], 132 + (i-1)*30, r[3])
    end

    local info = Instance.new("TextLabel")
    info.Size                 = UDim2.new(1, -20, 0, 24)
    info.Position             = UDim2.new(0, 10, 1, -28)
    info.BackgroundTransparency = 1
    info.Text                 = "X = toggle aim  |  RMB = hold aim"
    info.TextColor3           = Color3.fromRGB(120, 120, 140)
    info.TextSize             = 10
    info.Font                 = Enum.Font.Gotham
    info.TextXAlignment       = Enum.TextXAlignment.Center
    info.ZIndex               = 3
    info.Parent               = win

    return gui, win
end
