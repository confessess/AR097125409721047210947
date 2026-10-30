local Gui = {}
Gui.__index = Gui

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--// Background image (content panel only)
-- Roblox cannot load raw https:// in an ImageLabel, so the bytes are downloaded,
-- cached to disk and served through getcustomasset.
-- Override the source at runtime with: getgenv().BlackoutBgUrl = "https://..."
-- Silence the diagnostics with: getgenv().BlackoutBgQuiet = true
local BACKGROUND_IMAGE_URL = (getgenv and getgenv().BlackoutBgUrl)
    or "https://files.catbox.moe/60cyzp.png"
local ASSET_DIR = "blackout_assets"

local function BgLog(msg)
    if getgenv and getgenv().BlackoutBgQuiet then return end
    warn("[ENI/bg] " .. tostring(msg))
end

--// Colors — Huohuo (green) palette
local BLACK      = Color3.fromRGB(8, 14, 12)
local BACKGROUND = Color3.fromRGB(11, 19, 16)
local DARK_PANEL = Color3.fromRGB(19, 32, 27)
local GREEN        = Color3.fromRGB(111, 211, 162)
local GREEN_BRIGHT = Color3.fromRGB(160, 238, 194)
local GREEN_DARK   = Color3.fromRGB(30, 62, 50)
local SELECTED   = Color3.fromRGB(25, 51, 42)
local HOVER      = Color3.fromRGB(16, 28, 23)
local WHITE      = Color3.fromRGB(241, 255, 249)
local LIGHT      = Color3.fromRGB(213, 233, 224)
local GRAY       = Color3.fromRGB(140, 165, 155)
local BORDER     = Color3.fromRGB(40, 78, 65)

--// Static accent for every module (single color theme)
local ACCENTS = {
    Combat           = GREEN,
    Visuals          = GREEN,
    Weapon           = GREEN,
    Movement         = GREEN,
    ["Skin Changer"] = GREEN,
    World            = GREEN,
    Viewmodel        = GREEN,
    Settings         = GREEN,
}
local DEFAULT_ACCENT = GREEN

local function LerpColor(a, b, t)
    return Color3.new(
        a.R + (b.R - a.R) * t,
        a.G + (b.G - a.G) * t,
        a.B + (b.B - a.B) * t
    )
end

local function Tint(color, amount)
    return LerpColor(color, WHITE, amount)
end

local function Shade(color, amount)
    return LerpColor(color, BLACK, amount)
end

--// Wave Config
local WAVE_PEAK_TRANS   = 0.82
local WAVE_BAND_WIDTH   = 0.25
local WAVE_DURATION     = 2.7
local WAVE_PAUSE        = 1.1
local WAVE_ROTATION     = -45

--// ── Image pipeline ──────────────────────────────────────────────
local function HashString(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + string.byte(str, i)) % 4294967296
    end
    return string.format("%x", h)
end

-- Sends browser-ish headers because plain HttpGet is refused by some hosts.
local function FetchBody(url)
    local req = (syn and syn.request) or (http and http.request) or request or http_request
    if req then
        local ok, res = pcall(req, {
            Url = url,
            Method = "GET",
            Headers = {
                ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                ["Referer"] = "https://catbox.moe/",
                ["Accept"] = "image/png,image/*;q=0.8,*/*;q=0.5",
            },
        })
        if ok and res and res.Body then
            local status = res.StatusCode
            if status == nil or status < 400 then return res.Body end
            BgLog("HTTP " .. tostring(status))
        elseif not ok then
            BgLog("request() errored: " .. tostring(res))
        end
    end
    local okGet, body = pcall(function() return game:HttpGet(url, true) end)
    if okGet and type(body) == "string" and body ~= "" then return body end
    return nil
end

-- getcustomasset wants a path inside the workspace folder on some executors
-- and an absolute path on others, so try both.
local function ToCustomAsset(path)
    local candidates = { path }
    if getworkspacefolder then
        local okWs, ws = pcall(getworkspacefolder)
        if okWs and type(ws) == "string" and ws ~= "" then
            candidates[#candidates + 1] = ws .. "/" .. path
        end
    elseif getworkspace then
        local okWs, ws = pcall(getworkspace)
        if okWs and ws then
            local okStr, wsStr = pcall(function() return tostring(ws) end)
            if okStr and type(wsStr) == "string" and wsStr ~= "" and wsStr:find("\\", 1, true) then
                candidates[#candidates + 1] = wsStr .. "\\" .. path
            end
        end
    end
    for _, candidate in ipairs(candidates) do
        local ok, asset = pcall(getcustomasset, candidate)
        if ok and type(asset) == "string" and asset ~= "" then
            return asset
        end
    end
    return nil
end

local function LoadRemoteImage(url)
    if type(url) ~= "string" or url == "" then return nil, "no url" end
    if not writefile then return nil, "executor has no writefile" end
    if not getcustomasset then return nil, "executor has no getcustomasset" end

    if makefolder then pcall(makefolder, ASSET_DIR) end

    local key = HashString(url)
    local cachedPath = ASSET_DIR .. "/bg_" .. key .. ".png"

    if isfile then
        local okExists, exists = pcall(isfile, cachedPath)
        if okExists and exists then
            local cachedAsset = ToCustomAsset(cachedPath)
            if cachedAsset then
                BgLog("loaded from disk cache")
                return cachedAsset
            end
            BgLog("cache file present but getcustomasset rejected it")
        end
    end

    local body
    for attempt = 1, 3 do
        body = FetchBody(url)
        if body then break end
        BgLog("download attempt " .. attempt .. " failed")
        task.wait(attempt * 0.7)
    end
    if not body then return nil, "download failed" end
    if #body < 128 then return nil, "response too short (" .. #body .. " bytes)" end

    local magic = string.sub(body, 1, 4)
    local ext
    if magic == "\137PNG" then
        ext = "png"
    elseif string.sub(body, 1, 3) == "\255\216\255" then
        ext = "jpg"
    else
        BgLog("body is not an image, starts with: " .. string.sub(body, 1, 48):gsub("%c", " "))
        return nil, "response is not PNG/JPG"
    end

    local path = ASSET_DIR .. "/bg_" .. key .. "." .. ext
    local okWrite, writeErr = pcall(writefile, path, body)
    if not okWrite then return nil, "writefile failed: " .. tostring(writeErr) end

    local asset = ToCustomAsset(path)
    if not asset then return nil, "getcustomasset failed" end

    BgLog("applied (" .. #body .. " bytes)")
    return asset
end

--// Keybind helpers
local function KeyName(bind)
    if not bind then return "None" end
    if typeof(bind) == "EnumItem" then
        if bind.EnumType == Enum.UserInputType then
            if bind == Enum.UserInputType.MouseButton1 then return "LMB" end
            if bind == Enum.UserInputType.MouseButton2 then return "RMB" end
            if bind == Enum.UserInputType.MouseButton3 then return "MMB" end
        end
        return bind.Name
    end
    return tostring(bind)
end

--// State
local ToggleKey = Enum.KeyCode.RightShift
local WaitingForKey = false
local BindCapture = nil
local MenuOpen = true
local Animating = false

--// Mouse unlock setting
local UnlockMouseOnGUI = true
local MouseUnlockConnection = nil
local MouseUnlockHeartbeat = nil
local CameraModeHook = nil

local function ForceUnlockMouse()
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = true
    if Player.CameraMode == Enum.CameraMode.LockFirstPerson then
        Player.CameraMode = Enum.CameraMode.Classic
    end
end

local function StartMouseUnlockLoop()
    if MouseUnlockConnection then return end

    CameraModeHook = Player:GetPropertyChangedSignal("CameraMode"):Connect(function()
        if UnlockMouseOnGUI and MenuOpen and Player.CameraMode == Enum.CameraMode.LockFirstPerson then
            Player.CameraMode = Enum.CameraMode.Classic
        end
    end)

    MouseUnlockConnection = RunService.RenderStepped:Connect(function()
        if UnlockMouseOnGUI and MenuOpen then
            ForceUnlockMouse()
        end
    end)
    MouseUnlockHeartbeat = RunService.Heartbeat:Connect(function()
        if UnlockMouseOnGUI and MenuOpen then
            ForceUnlockMouse()
        end
    end)
    task.spawn(function()
        while true do
            if UnlockMouseOnGUI and MenuOpen then
                ForceUnlockMouse()
            end
            task.wait(0.016)
        end
    end)
end
StartMouseUnlockLoop()

--// State storage
Gui.ToggleStates = {}
Gui.ActiveHolds = {}

local function ApplySelectedGradient(button, enabled)
    if not button then return end
    local gradient = button:FindFirstChild("SelectedGradient")
    if gradient then
        gradient.Enabled = false
    end
end

function Gui:GetToggleState(tabName, label)
    local toggleKey = tabName .. "_" .. label
    return self.ToggleStates[toggleKey]
end

function Gui:SetToggleState(tabName, label, state)
    local toggleKey = tabName .. "_" .. label
    self.ToggleStates[toggleKey] = state
end

--// Every registered momentary control gets released here
function Gui:ReleaseAllHolds()
    for btn, entry in pairs(self.ActiveHolds) do
        if entry and entry.Release then entry.Release() end
    end
end

function Gui:ReloadBackground()
    task.spawn(function()
        local asset, err = LoadRemoteImage(BACKGROUND_IMAGE_URL)
        if asset and self.ContentBg then
            self.ContentBg.Image = asset
            self.ContentBg.Visible = true
        else
            BgLog("reload failed: " .. tostring(err))
        end
    end)
end

function Gui:Init()
    local old = PlayerGui:FindFirstChild("BlackoutGUI")
    if old then old:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "BlackoutGUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.DisplayOrder = 999999
    ScreenGui.Parent = PlayerGui

    local Main = Instance.new("Frame")
    Main.Name = "Main"
    Main.Size = UDim2.fromOffset(780, 520)
    Main.Position = UDim2.new(0.5, -390, 0.5, -260)
    Main.BackgroundColor3 = BACKGROUND
    Main.BorderSizePixel = 0
    Main.ClipsDescendants = true
    Main.Parent = ScreenGui

    local MainStroke = Instance.new("UIStroke")
    MainStroke.Color = DEFAULT_ACCENT
    MainStroke.Thickness = 2
    MainStroke.Transparency = 0.25
    MainStroke.Parent = Main

    local SavedPosition = Main.Position
    local OriginalSize = Main.Size

    local Background = Instance.new("Frame")
    Background.Name = "Background"
    Background.Size = UDim2.fromScale(1, 1)
    Background.BackgroundColor3 = BACKGROUND
    Background.BorderSizePixel = 0
    Background.ZIndex = 1
    Background.Parent = Main

    local sheen = Instance.new("Frame")
    sheen.Name = "ENI_WaveSheen"
    sheen.Size = UDim2.fromScale(1, 1)
    sheen.BackgroundColor3 = DEFAULT_ACCENT
    sheen.BackgroundTransparency = 0
    sheen.BorderSizePixel = 0
    sheen.ZIndex = 1
    sheen.Parent = Background

    local waveGrad = Instance.new("UIGradient")
    waveGrad.Rotation = WAVE_ROTATION
    waveGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.00, 1),
        NumberSequenceKeypoint.new(math.clamp(0.50 - WAVE_BAND_WIDTH, 0, 1), 1),
        NumberSequenceKeypoint.new(0.50, WAVE_PEAK_TRANS),
        NumberSequenceKeypoint.new(math.clamp(0.50 + WAVE_BAND_WIDTH, 0, 1), 1),
        NumberSequenceKeypoint.new(1.00, 1)
    })
    waveGrad.Parent = sheen

    do
        local offset = 1.5
        local paused = false
        local pauseTimer = 0
        local speed = 3.0 / WAVE_DURATION

        RunService.RenderStepped:Connect(function(dt)
            if not sheen.Parent then return end
            if not Main.Visible then return end
            if paused then
                pauseTimer = pauseTimer - dt
                if pauseTimer <= 0 then paused = false offset = 1.5 end
                return
            end
            offset = offset - (speed * dt)
            if offset <= -1.5 then paused = true pauseTimer = WAVE_PAUSE end
            waveGrad.Offset = Vector2.new(offset, 0)
        end)
    end

    local Top = Instance.new("Frame")
    Top.Name = "TopBar"
    Top.Size = UDim2.new(1, 0, 0, 64)
    Top.BackgroundColor3 = BLACK
    Top.BorderSizePixel = 0
    Top.ZIndex = 2
    Top.Parent = Main

    local TopBottom = Instance.new("Frame")
    TopBottom.Size = UDim2.new(1, 0, 0, 14)
    TopBottom.Position = UDim2.new(0, 0, 1, -14)
    TopBottom.BackgroundColor3 = BLACK
    TopBottom.BorderSizePixel = 0
    TopBottom.ZIndex = 2
    TopBottom.Parent = Top

    local Accent = Instance.new("Frame")
    Accent.Size = UDim2.new(1, -40, 0, 3)
    Accent.Position = UDim2.fromOffset(20, 61)
    Accent.BackgroundColor3 = DEFAULT_ACCENT
    Accent.BorderSizePixel = 0
    Accent.ZIndex = 5
    Accent.Parent = Top

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -140, 0, 26)
    Title.Position = UDim2.fromOffset(22, 10)
    Title.BackgroundTransparency = 1
    Title.Text = "unnamed arsenal script"
    Title.TextColor3 = WHITE
    Title.TextSize = 20
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.ZIndex = 6
    Title.Parent = Top

    local Subtitle = Instance.new("TextLabel")
    Subtitle.Size = UDim2.new(1, -140, 0, 18)
    Subtitle.Position = UDim2.fromOffset(23, 36)
    Subtitle.BackgroundTransparency = 1
    Subtitle.Text = "discord.gg/feuds"
    Subtitle.TextColor3 = GRAY
    Subtitle.TextSize = 11
    Subtitle.Font = Enum.Font.Gotham
    Subtitle.TextXAlignment = Enum.TextXAlignment.Left
    Subtitle.ZIndex = 6
    Subtitle.Parent = Top

    local Close = Instance.new("TextButton")
    Close.Name = "Close"
    Close.Size = UDim2.fromOffset(32, 30)
    Close.Position = UDim2.new(1, -44, 0, 14)
    Close.BackgroundColor3 = WHITE
    Close.BorderSizePixel = 0
    Close.Text = "×"
    Close.TextColor3 = BLACK
    Close.TextSize = 18
    Close.Font = Enum.Font.GothamBold
    Close.AutoButtonColor = false
    Close.ZIndex = 7
    Close.Parent = Top

    Close.MouseEnter:Connect(function() Close.BackgroundColor3 = Tint(GREEN, 0.6) end)
    Close.MouseLeave:Connect(function() Close.BackgroundColor3 = WHITE end)
    Close.MouseButton1Click:Connect(function() self:HideMenu() end)

    local Sidebar = Instance.new("Frame")
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.fromOffset(170, 428)
    Sidebar.Position = UDim2.fromOffset(14, 78)
    Sidebar.BackgroundColor3 = BLACK
    Sidebar.BorderSizePixel = 0
    Sidebar.ZIndex = 2
    Sidebar.Parent = Main

    local SidebarStroke = Instance.new("UIStroke")
    SidebarStroke.Color = BORDER
    SidebarStroke.Thickness = 1
    SidebarStroke.Transparency = 0.15
    SidebarStroke.Parent = Sidebar

    local SidebarPadding = Instance.new("UIPadding")
    SidebarPadding.PaddingTop = UDim.new(0, 10)
    SidebarPadding.PaddingLeft = UDim.new(0, 10)
    SidebarPadding.PaddingRight = UDim.new(0, 10)
    SidebarPadding.PaddingBottom = UDim.new(0, 10)
    SidebarPadding.Parent = Sidebar

    local TabLayout = Instance.new("UIListLayout")
    TabLayout.Padding = UDim.new(0, 4)
    TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    TabLayout.Parent = Sidebar

    local Content = Instance.new("Frame")
    Content.Name = "Content"
    Content.Size = UDim2.new(1, -228, 1, -92)
    Content.Position = UDim2.fromOffset(200, 78)
    Content.BackgroundTransparency = 1
    Content.ZIndex = 2
    Content.Parent = Main

    --// Content background image — lives in the Background layer (ZIndex 1) so
    --// the entire Content frame composites above it. 50% transparent.
    local ContentBg = Instance.new("ImageLabel")
    ContentBg.Name = "ContentBackground"
    ContentBg.Size = UDim2.new(1, -228, 1, -92)
    ContentBg.Position = UDim2.fromOffset(200, 78)
    ContentBg.BackgroundColor3 = BACKGROUND
    ContentBg.BackgroundTransparency = 1
    ContentBg.BorderSizePixel = 0
    ContentBg.Image = ""
    ContentBg.ImageTransparency = 0.5
    ContentBg.ScaleType = Enum.ScaleType.Crop
    ContentBg.Visible = false
    ContentBg.ZIndex = 1
    ContentBg.Parent = Background

    local ContentBgOverlay = Instance.new("Frame")
    ContentBgOverlay.Name = "Overlay"
    ContentBgOverlay.Size = UDim2.fromScale(1, 1)
    ContentBgOverlay.BackgroundColor3 = BACKGROUND
    ContentBgOverlay.BackgroundTransparency = 0.55
    ContentBgOverlay.BorderSizePixel = 0
    ContentBgOverlay.ZIndex = 1
    ContentBgOverlay.Parent = ContentBg

    local OverlayGrad = Instance.new("UIGradient")
    OverlayGrad.Rotation = 90
    OverlayGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.00, 0.15),
        NumberSequenceKeypoint.new(0.45, 0.45),
        NumberSequenceKeypoint.new(1.00, 0.65),
    })
    OverlayGrad.Parent = ContentBgOverlay

    local ContentBgStroke = Instance.new("UIStroke")
    ContentBgStroke.Color = BORDER
    ContentBgStroke.Thickness = 1
    ContentBgStroke.Transparency = 0.35
    ContentBgStroke.Parent = ContentBg

    task.spawn(function()
        local asset, err = LoadRemoteImage(BACKGROUND_IMAGE_URL)
        if asset and ContentBg.Parent then
            ContentBg.Image = asset
            ContentBg.Visible = true
        else
            BgLog("background not applied: " .. tostring(err))
        end
    end)

    local ContentTitle = Instance.new("TextLabel")
    ContentTitle.Size = UDim2.new(1, 0, 0, 28)
    ContentTitle.Position = UDim2.fromOffset(0, 0)
    ContentTitle.BackgroundTransparency = 1
    ContentTitle.Text = "Combat"
    ContentTitle.TextColor3 = ACCENTS.Combat
    ContentTitle.TextSize = 20
    ContentTitle.Font = Enum.Font.GothamBold
    ContentTitle.TextXAlignment = Enum.TextXAlignment.Left
    ContentTitle.ZIndex = 3
    ContentTitle.Parent = Content

    local ContentSubtitle = Instance.new("TextLabel")
    ContentSubtitle.Size = UDim2.new(1, 0, 0, 18)
    ContentSubtitle.Position = UDim2.fromOffset(0, 28)
    ContentSubtitle.BackgroundTransparency = 1
    ContentSubtitle.Text = "Configure your combat settings."
    ContentSubtitle.TextColor3 = GRAY
    ContentSubtitle.TextSize = 12
    ContentSubtitle.Font = Enum.Font.Gotham
    ContentSubtitle.TextXAlignment = Enum.TextXAlignment.Left
    ContentSubtitle.ZIndex = 3
    ContentSubtitle.Parent = Content

    local Dragging = false
    local DragStart
    local StartPosition

    Top.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        Dragging = true
        DragStart = input.Position
        StartPosition = Main.Position
        local connection
        connection = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                Dragging = false
                SavedPosition = Main.Position
                if connection then connection:Disconnect() end
            end
        end)
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not Dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - DragStart
        Main.Position = UDim2.new(
            StartPosition.X.Scale, StartPosition.X.Offset + delta.X,
            StartPosition.Y.Scale, StartPosition.Y.Offset + delta.Y
        )
    end)

    --// Single global release sweep for every momentary control
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            self:ReleaseAllHolds()
        end
    end)

    self.ScreenGui = ScreenGui
    self.Main = Main
    self.Top = Top
    self.Sidebar = Sidebar
    self.Content = Content
    self.ContentBg = ContentBg
    self.ContentTitle = ContentTitle
    self.ContentSubtitle = ContentSubtitle
    self.SavedPosition = SavedPosition
    self.OriginalSize = OriginalSize
    self.MainStroke = MainStroke
    self.AccentBar = Accent
    self.Sheen = sheen
    self.CurrentAccent = DEFAULT_ACCENT
    self.Tabs = {}
    self.CurrentTab = nil
    self.TabButtons = {}

    UserInputService.InputBegan:Connect(function(input, processed)
        --// keybind capture for keybind rows
        if BindCapture then
            local captured = nil
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode ~= Enum.KeyCode.Unknown then captured = input.KeyCode end
            elseif input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.MouseButton2
                or input.UserInputType == Enum.UserInputType.MouseButton3 then
                captured = input.UserInputType
            end
            if captured then
                local callback = BindCapture.Callback
                BindCapture = nil
                if callback then callback(captured) end
            end
            return
        end

        if WaitingForKey then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode ~= Enum.KeyCode.Unknown then
                    ToggleKey = input.KeyCode
                    WaitingForKey = false
                    local settingsBtn = Content:FindFirstChild("Keybind")
                    if settingsBtn then
                        settingsBtn.Text = ToggleKey.Name
                        settingsBtn.TextColor3 = WHITE
                        settingsBtn.BackgroundColor3 = DARK_PANEL
                        local stroke = settingsBtn:FindFirstChildOfClass("UIStroke")
                        if stroke then stroke.Color = BORDER end
                    end
                end
            end
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == ToggleKey then
            if MenuOpen then self:HideMenu() else self:ShowMenu() end
            return
        end
    end)

    return self
end

function Gui:HideMenu()
    if Animating or not MenuOpen then return end
    Animating = true
    MenuOpen = false
    self:ReleaseAllHolds()
    self.SavedPosition = self.Main.Position

    local closeSize = UDim2.fromOffset(self.OriginalSize.X.Offset - 60, self.OriginalSize.Y.Offset - 40)
    local closePos = UDim2.new(
        self.SavedPosition.X.Scale, self.SavedPosition.X.Offset + 30,
        self.SavedPosition.Y.Scale, self.SavedPosition.Y.Offset + 20
    )

    local tween = TweenService:Create(self.Main, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
        Size = closeSize, Position = closePos, BackgroundTransparency = 1
    })
    tween:Play()
    tween.Completed:Connect(function()
        self.Main.Visible = false
        self.Main.Size = self.OriginalSize
        self.Main.Position = self.SavedPosition
        self.Main.BackgroundTransparency = 0
        Animating = false
    end)
end

function Gui:ShowMenu()
    if Animating or MenuOpen then return end
    Animating = true
    MenuOpen = true
    self.Main.Visible = true
    self.Main.Size = UDim2.fromOffset(self.OriginalSize.X.Offset - 60, self.OriginalSize.Y.Offset - 40)
    self.Main.Position = UDim2.new(
        self.SavedPosition.X.Scale, self.SavedPosition.X.Offset + 30,
        self.SavedPosition.Y.Scale, self.SavedPosition.Y.Offset + 20
    )
    self.Main.BackgroundTransparency = 1

    local tween = TweenService:Create(self.Main, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Size = self.OriginalSize, Position = self.SavedPosition, BackgroundTransparency = 0
    })
    tween:Play()
    tween.Completed:Connect(function()
        self.Main.Position = self.SavedPosition
        self.Main.Size = self.OriginalSize
        Animating = false
    end)

    if UnlockMouseOnGUI then
        ForceUnlockMouse()
    end
end

function Gui:CreateTab(name, description)
    description = description or "Configure your " .. name:lower() .. " settings."
    local index = #self.Tabs + 1
    local accent = ACCENTS[name] or DEFAULT_ACCENT

    local Button = Instance.new("TextButton")
    Button.Name = name:gsub("%s+", "")
    Button.Size = UDim2.new(1, 0, 0, 46)
    Button.LayoutOrder = index
    Button.BackgroundColor3 = BLACK
    Button.BorderSizePixel = 0
    Button.Text = ""
    Button.AutoButtonColor = false
    Button.ClipsDescendants = true
    Button.ZIndex = 3
    Button.Parent = self.Sidebar

    ApplySelectedGradient(Button, false)

    local Text = Instance.new("TextLabel")
    Text.Name = "TabText"
    Text.Size = UDim2.new(1, -30, 1, 0)
    Text.Position = UDim2.fromOffset(16, 0)
    Text.BackgroundTransparency = 1
    Text.Text = name
    Text.TextColor3 = Color3.fromRGB(165, 165, 165)
    Text.TextSize = 13
    Text.Font = Enum.Font.GothamMedium
    Text.TextXAlignment = Enum.TextXAlignment.Left
    Text.TextTruncate = Enum.TextTruncate.AtEnd
    Text.ZIndex = 4
    Text.Parent = Button

    local Indicator = Instance.new("Frame")
    Indicator.Size = UDim2.fromOffset(3, 20)
    Indicator.Position = UDim2.new(0, 5, 0.5, -10)
    Indicator.BackgroundColor3 = accent
    Indicator.BorderSizePixel = 0
    Indicator.Visible = false
    Indicator.ZIndex = 5
    Indicator.Parent = Button

    local ButtonStroke = Instance.new("UIStroke")
    ButtonStroke.Thickness = 1
    ButtonStroke.Transparency = 1
    ButtonStroke.Parent = Button

    self.TabButtons[name] = { Button = Button, Text = Text, Indicator = Indicator, Stroke = ButtonStroke, Accent = accent }

    Button.MouseEnter:Connect(function()
        if self.CurrentTab ~= name then
            Button.BackgroundColor3 = HOVER
            Text.TextColor3 = Tint(accent, 0.35)
        end
    end)
    Button.MouseLeave:Connect(function()
        if self.CurrentTab ~= name then
            Button.BackgroundColor3 = BLACK
            Text.TextColor3 = Color3.fromRGB(165, 165, 165)
        end
    end)
    Button.MouseButton1Click:Connect(function() self:SwitchTab(name) end)

    local tabData = { Name = name, Description = description, Elements = {}, Accent = accent }
    table.insert(self.Tabs, tabData)

    if #self.Tabs == 1 then self:SwitchTab(name) end
    return tabData
end

function Gui:SwitchTab(name)
    self.CurrentTab = name
    local tab = self:GetTab(name)
    local accent = (tab and tab.Accent) or DEFAULT_ACCENT
    self.CurrentAccent = accent

    if self.MainStroke then self.MainStroke.Color = accent end
    if self.AccentBar then self.AccentBar.BackgroundColor3 = accent end
    if self.Sheen then self.Sheen.BackgroundColor3 = accent end

    for tabName, data in pairs(self.TabButtons) do
        local isSelected = tabName == name
        if isSelected then
            data.Button.BackgroundColor3 = Shade(accent, 0.78)
            data.Text.TextColor3 = Tint(accent, 0.15)
            data.Indicator.Visible = true
            data.Indicator.BackgroundColor3 = accent
            data.Stroke.Color = accent
            data.Stroke.Transparency = 0.45
        else
            data.Button.BackgroundColor3 = BLACK
            data.Text.TextColor3 = Color3.fromRGB(165, 165, 165)
            data.Indicator.Visible = false
            data.Stroke.Color = BLACK
            data.Stroke.Transparency = 1
        end
        ApplySelectedGradient(data.Button, isSelected)
    end

    self.ContentTitle.Text = name
    self.ContentTitle.TextColor3 = accent
    self.ContentSubtitle.Text = self:GetTabDescription(name) or ""
    self.ContentSubtitle.TextColor3 = Tint(accent, 0.55)

    self:ReleaseAllHolds()

    for _, child in ipairs(self.Content:GetChildren()) do
        if child ~= self.ContentTitle
            and child ~= self.ContentSubtitle
            and child ~= self.ContentBg then
            child:Destroy()
        end
    end

    if tab and tab.Rebuild then tab.Rebuild(self) end
end

function Gui:GetTab(name)
    for _, tab in ipairs(self.Tabs) do
        if tab.Name == name then return tab end
    end
    return nil
end

function Gui:GetTabDescription(name)
    for _, tab in ipairs(self.Tabs) do
        if tab.Name == name then return tab.Description end
    end
    return ""
end

function Gui:SetTabRebuild(name, callback)
    local tab = self:GetTab(name)
    if not tab then return end
    tab.Rebuild = callback
    --// the first tab is switched to before any module registers its builder,
    --// so build it now instead of leaving it blank until the next tab click
    if callback and self.CurrentTab == name then
        callback(self)
    end
end

function Gui:CreateScrollContent()
    local ScrollFrame = Instance.new("ScrollingFrame")
    ScrollFrame.Name = "TabScroll"
    ScrollFrame.Size = UDim2.new(1, 0, 1, -54)
    ScrollFrame.Position = UDim2.fromOffset(0, 54)
    ScrollFrame.BackgroundTransparency = 1
    ScrollFrame.BorderSizePixel = 0
    ScrollFrame.ScrollBarThickness = 4
    ScrollFrame.ScrollBarImageColor3 = self.CurrentAccent or DEFAULT_ACCENT
    ScrollFrame.ScrollBarImageTransparency = 0.5
    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ScrollFrame.ZIndex = 3
    ScrollFrame.Parent = self.Content

    local Padding = Instance.new("UIPadding")
    Padding.PaddingTop = UDim.new(0, 6)
    Padding.PaddingLeft = UDim.new(0, 4)
    Padding.PaddingRight = UDim.new(0, 20)
    Padding.PaddingBottom = UDim.new(0, 12)
    Padding.Parent = ScrollFrame

    return ScrollFrame
end

function Gui:CreateSection(text, y)
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    y = y or 0
    local Section = Instance.new("TextLabel")
    Section.Size = UDim2.new(1, 0, 0, 24)
    Section.Position = UDim2.fromOffset(0, y)
    Section.BackgroundTransparency = 1
    Section.Text = text
    Section.TextColor3 = accent
    Section.TextSize = 14
    Section.Font = Enum.Font.GothamBold
    Section.TextXAlignment = Enum.TextXAlignment.Left
    Section.ZIndex = 3
    Section.Parent = self.Content

    local Divider = Instance.new("Frame")
    Divider.Size = UDim2.new(1, 0, 0, 1)
    Divider.Position = UDim2.fromOffset(0, y + 28)
    Divider.BackgroundColor3 = Shade(accent, 0.55)
    Divider.BorderSizePixel = 0
    Divider.ZIndex = 3
    Divider.Parent = self.Content

    return y + 40
end

--// ═══════════════════════════════════════════════════════════════
--//  TOGGLE — plain single row, nothing extra underneath
--// ═══════════════════════════════════════════════════════════════
function Gui:CreateToggle(label, default, callback, y)
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    local toggleKey = self.CurrentTab .. "_" .. label
    local savedState = self.ToggleStates[toggleKey]
    local State = savedState ~= nil and savedState or default

    local ToggleFrame = Instance.new("Frame")
    ToggleFrame.Size = UDim2.new(1, 0, 0, 36)
    ToggleFrame.Position = UDim2.fromOffset(0, y)
    ToggleFrame.BackgroundTransparency = 1
    ToggleFrame.ZIndex = 3
    ToggleFrame.Parent = self.Content

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -70, 0, 36)
    Label.BackgroundTransparency = 1
    Label.Text = label
    Label.TextColor3 = Tint(accent, 0.72)
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = ToggleFrame

    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Size = UDim2.fromOffset(46, 26)
    ToggleBtn.Position = UDim2.new(1, -70, 0, 5)
    ToggleBtn.BackgroundColor3 = State and accent or DARK_PANEL
    ToggleBtn.BorderSizePixel = 0
    ToggleBtn.Text = State and "ON" or "OFF"
    ToggleBtn.TextColor3 = State and BLACK or GRAY
    ToggleBtn.TextSize = 10
    ToggleBtn.Font = Enum.Font.GothamBold
    ToggleBtn.AutoButtonColor = false
    ToggleBtn.ZIndex = 4
    ToggleBtn.Parent = ToggleFrame

    local ToggleStroke = Instance.new("UIStroke")
    ToggleStroke.Color = State and accent or Shade(accent, 0.6)
    ToggleStroke.Thickness = 1
    ToggleStroke.Parent = ToggleBtn

    local function Draw()
        ToggleBtn.BackgroundColor3 = State and accent or DARK_PANEL
        ToggleBtn.TextColor3 = State and BLACK or GRAY
        ToggleBtn.Text = State and "ON" or "OFF"
        ToggleStroke.Color = State and accent or Shade(accent, 0.6)
    end

    ToggleBtn.MouseEnter:Connect(function()
        ToggleBtn.BackgroundColor3 = State and Tint(accent, 0.35) or Shade(accent, 0.82)
    end)
    ToggleBtn.MouseLeave:Connect(function()
        ToggleBtn.BackgroundColor3 = State and accent or DARK_PANEL
    end)
    ToggleBtn.MouseButton1Click:Connect(function()
        State = not State
        self.ToggleStates[toggleKey] = State
        Draw()
        if callback then callback(State) end
    end)

    return y + 42
end

--// ═══════════════════════════════════════════════════════════════
--//  KEYBIND ROW — a bind button with a Toggle/Hold chooser under it
--//  options = { Key = Enum, Mode = "Toggle"|"Hold",
--//              OnKeyChanged = fn(key), OnModeChanged = fn(mode) }
-- ═══════════════════════════════════════════════════════════════
local ACTIVATION_MODES = { "Toggle", "Hold" }

function Gui:CreateKeybindRow(label, options, y)
    options = options or {}
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    local key = options.Key
    local mode = options.Mode or "Hold"

    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 74)
    Frame.Position = UDim2.fromOffset(0, y)
    Frame.BackgroundTransparency = 1
    Frame.ZIndex = 3
    Frame.Parent = self.Content

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -140, 0, 36)
    Label.BackgroundTransparency = 1
    Label.Text = label
    Label.TextColor3 = Tint(accent, 0.72)
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = Frame

    local BindBtn = Instance.new("TextButton")
    BindBtn.Name = "BindButton"
    BindBtn.Size = UDim2.fromOffset(120, 28)
    BindBtn.Position = UDim2.new(1, -140, 0, 4)
    BindBtn.BackgroundColor3 = DARK_PANEL
    BindBtn.BorderSizePixel = 0
    BindBtn.Text = "Bind: " .. KeyName(key)
    BindBtn.TextColor3 = key and Tint(accent, 0.4) or GRAY
    BindBtn.TextSize = 11
    BindBtn.Font = Enum.Font.GothamMedium
    BindBtn.AutoButtonColor = false
    BindBtn.ZIndex = 4
    BindBtn.Parent = Frame

    local BindStroke = Instance.new("UIStroke")
    BindStroke.Color = Shade(accent, 0.6)
    BindStroke.Thickness = 1
    BindStroke.Parent = BindBtn

    --// mode row
    local ModeCaption = Instance.new("TextLabel")
    ModeCaption.Size = UDim2.new(1, -140, 0, 22)
    ModeCaption.Position = UDim2.fromOffset(0, 40)
    ModeCaption.BackgroundTransparency = 1
    ModeCaption.Text = "Activation mode"
    ModeCaption.TextColor3 = Shade(Tint(accent, 0.5), 0.35)
    ModeCaption.TextSize = 10
    ModeCaption.Font = Enum.Font.Gotham
    ModeCaption.TextXAlignment = Enum.TextXAlignment.Left
    ModeCaption.ZIndex = 4
    ModeCaption.Parent = Frame

    local ModeChip = Instance.new("TextButton")
    ModeChip.Name = "ModeChip"
    ModeChip.Size = UDim2.fromOffset(120, 22)
    ModeChip.Position = UDim2.new(1, -140, 0, 40)
    ModeChip.BackgroundColor3 = DARK_PANEL
    ModeChip.BorderSizePixel = 0
    ModeChip.Text = mode .. "  ▾"
    ModeChip.TextColor3 = Tint(accent, 0.3)
    ModeChip.TextSize = 10
    ModeChip.Font = Enum.Font.GothamBold
    ModeChip.AutoButtonColor = false
    ModeChip.ZIndex = 4
    ModeChip.Parent = Frame

    local ModeStroke = Instance.new("UIStroke")
    ModeStroke.Color = Shade(accent, 0.6)
    ModeStroke.Thickness = 1
    ModeStroke.Parent = ModeChip

    local ModePopup = Instance.new("Frame")
    ModePopup.Name = "ModePopup"
    ModePopup.Size = UDim2.fromOffset(120, #ACTIVATION_MODES * 24 + 4)
    ModePopup.BackgroundColor3 = Color3.fromRGB(13, 22, 18)
    ModePopup.BorderSizePixel = 0
    ModePopup.Visible = false
    ModePopup.ZIndex = 100
    ModePopup.Parent = self.ScreenGui

    local ModePopupStroke = Instance.new("UIStroke")
    ModePopupStroke.Color = accent
    ModePopupStroke.Thickness = 1.5
    ModePopupStroke.Parent = ModePopup

    local function SetMode(newMode)
        if mode == newMode then return end
        mode = newMode
        ModeChip.Text = mode .. "  ▾"
        if options.OnModeChanged then pcall(options.OnModeChanged, mode) end
        for _, child in ipairs(ModePopup:GetChildren()) do
            if child:IsA("TextButton") then
                child.TextColor3 = (child:GetAttribute("ModeValue") == mode) and accent or LIGHT
            end
        end
    end

    for i, modeName in ipairs(ACTIVATION_MODES) do
        local OptBtn = Instance.new("TextButton")
        OptBtn.Size = UDim2.new(1, -4, 0, 22)
        OptBtn.Position = UDim2.fromOffset(2, 2 + (i - 1) * 24)
        OptBtn.BackgroundColor3 = Color3.fromRGB(13, 22, 18)
        OptBtn.BorderSizePixel = 0
        OptBtn.Text = "  " .. modeName
        OptBtn.TextColor3 = modeName == mode and accent or LIGHT
        OptBtn.TextSize = 10
        OptBtn.Font = Enum.Font.GothamBold
        OptBtn.TextXAlignment = Enum.TextXAlignment.Left
        OptBtn.AutoButtonColor = false
        OptBtn.ZIndex = 101
        OptBtn.Parent = ModePopup
        OptBtn:SetAttribute("ModeValue", modeName)

        OptBtn.MouseEnter:Connect(function()
            OptBtn.BackgroundColor3 = Shade(accent, 0.8)
        end)
        OptBtn.MouseLeave:Connect(function()
            OptBtn.BackgroundColor3 = Color3.fromRGB(13, 22, 18)
        end)
        OptBtn.MouseButton1Click:Connect(function()
            SetMode(modeName)
            ModePopup.Visible = false
        end)
    end

    ModeChip.MouseEnter:Connect(function()
        ModeChip.BackgroundColor3 = Shade(accent, 0.82)
        ModeStroke.Color = accent
    end)
    ModeChip.MouseLeave:Connect(function()
        ModeChip.BackgroundColor3 = DARK_PANEL
        ModeStroke.Color = Shade(accent, 0.6)
    end)
    ModeChip.MouseButton1Click:Connect(function()
        if ModePopup.Visible then
            ModePopup.Visible = false
        else
            local absPos = ModeChip.AbsolutePosition
            local absSize = ModeChip.AbsoluteSize
            ModePopup.Position = UDim2.fromOffset(absPos.X, absPos.Y + absSize.Y + 2)
            ModePopup.Visible = true
        end
    end)

    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and ModePopup.Visible then
            local mousePos = Vector2.new(input.Position.X, input.Position.Y)
            local pPos = ModePopup.AbsolutePosition
            local pSize = ModePopup.AbsoluteSize
            local cPos = ModeChip.AbsolutePosition
            local cSize = ModeChip.AbsoluteSize

            local inPopup = mousePos.X >= pPos.X and mousePos.X <= pPos.X + pSize.X and
                            mousePos.Y >= pPos.Y and mousePos.Y <= pPos.Y + pSize.Y
            local inChip = mousePos.X >= cPos.X and mousePos.X <= cPos.X + cSize.X and
                           mousePos.Y >= cPos.Y and mousePos.Y <= cPos.Y + cSize.Y

            if not inPopup and not inChip then
                ModePopup.Visible = false
            end
        end
    end)

    --// bind capture
    BindBtn.MouseEnter:Connect(function()
        BindBtn.BackgroundColor3 = Shade(accent, 0.82)
        BindStroke.Color = accent
    end)
    BindBtn.MouseLeave:Connect(function()
        BindBtn.BackgroundColor3 = DARK_PANEL
        BindStroke.Color = Shade(accent, 0.6)
    end)
    BindBtn.MouseButton1Click:Connect(function()
        if BindCapture then return end
        BindBtn.Text = "Press a key..."
        BindBtn.TextColor3 = accent
        BindCapture = {
            Callback = function(captured)
                key = captured
                BindBtn.Text = "Bind: " .. KeyName(captured)
                BindBtn.TextColor3 = Tint(accent, 0.4)
                if options.OnKeyChanged then pcall(options.OnKeyChanged, captured) end
            end,
        }
    end)

    Frame.Destroying:Connect(function()
        ModePopup:Destroy()
    end)

    return y + 76
end

function Gui:CreateSlider(label, min, max, default, callback, y)
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    local SliderFrame = Instance.new("Frame")
    SliderFrame.Size = UDim2.new(1, 0, 0, 50)
    SliderFrame.Position = UDim2.fromOffset(0, y)
    SliderFrame.BackgroundTransparency = 1
    SliderFrame.ZIndex = 3
    SliderFrame.Parent = self.Content

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -70, 0, 20)
    Label.BackgroundTransparency = 1
    Label.Text = label
    Label.TextColor3 = Tint(accent, 0.72)
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = SliderFrame

    local ValueText = Instance.new("TextLabel")
    ValueText.Size = UDim2.fromOffset(48, 20)
    ValueText.Position = UDim2.new(1, -70, 0, 0)
    ValueText.BackgroundTransparency = 1
    ValueText.Text = tostring(default)
    ValueText.TextColor3 = accent
    ValueText.TextSize = 12
    ValueText.Font = Enum.Font.GothamBold
    ValueText.TextXAlignment = Enum.TextXAlignment.Right
    ValueText.ZIndex = 4
    ValueText.Parent = SliderFrame

    local Track = Instance.new("Frame")
    Track.Size = UDim2.new(1, -16, 0, 4)
    Track.Position = UDim2.fromOffset(4, 36)
    Track.BackgroundColor3 = DARK_PANEL
    Track.BorderSizePixel = 0
    Track.ZIndex = 4
    Track.Parent = SliderFrame

    local Fill = Instance.new("Frame")
    local range = max - min
    local startPos = range > 0 and (default - min) / range or 0
    Fill.Size = UDim2.new(startPos, 0, 1, 0)
    Fill.BackgroundColor3 = accent
    Fill.BorderSizePixel = 0
    Fill.ZIndex = 5
    Fill.Parent = Track

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.fromOffset(10, 10)
    Knob.Position = UDim2.new(startPos, -5, 0.5, -5)
    Knob.BackgroundColor3 = Tint(accent, 0.5)
    Knob.BorderSizePixel = 0
    Knob.ZIndex = 5
    Knob.Parent = Track

    local Dragging = false

    local function update(input)
        local pos = math.clamp((input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
        local value = math.floor(min + (pos * range))
        Fill.Size = UDim2.new(pos, 0, 1, 0)
        Knob.Position = UDim2.new(pos, -5, 0.5, -5)
        ValueText.Text = tostring(value)
        if callback then callback(value) end
    end

    Knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then Dragging = true end
    end)
    Track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then Dragging = true update(input) end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if Dragging and input.UserInputType == Enum.UserInputType.MouseMovement then update(input) end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then Dragging = false end
    end)

    return y + 56
end

function Gui:CreateDropdown(label, options, default, callback, y)
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    local DropFrame = Instance.new("Frame")
    DropFrame.Size = UDim2.new(1, 0, 0, 36)
    DropFrame.Position = UDim2.fromOffset(0, y)
    DropFrame.BackgroundTransparency = 1
    DropFrame.ZIndex = 3
    DropFrame.Parent = self.Content

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.4, 0, 1, 0)
    Label.BackgroundTransparency = 1
    Label.Text = label
    Label.TextColor3 = Tint(accent, 0.72)
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = DropFrame

    local selected = tostring(default or options[1])

    local DropBtn = Instance.new("TextButton")
    DropBtn.Size = UDim2.fromOffset(150, 28)
    DropBtn.Position = UDim2.new(1, -174, 0, 4)
    DropBtn.BackgroundColor3 = DARK_PANEL
    DropBtn.BorderSizePixel = 0
    DropBtn.Text = selected .. " ▼"
    DropBtn.TextColor3 = Tint(accent, 0.4)
    DropBtn.TextSize = 11
    DropBtn.Font = Enum.Font.GothamMedium
    DropBtn.AutoButtonColor = false
    DropBtn.ZIndex = 4
    DropBtn.Parent = DropFrame

    local DropStroke = Instance.new("UIStroke")
    DropStroke.Color = Shade(accent, 0.6)
    DropStroke.Thickness = 1
    DropStroke.Parent = DropBtn

    local Popup = Instance.new("Frame")
    Popup.Name = "DropdownPopup"
    Popup.Size = UDim2.fromOffset(150, math.min(#options * 26, 260))
    Popup.BackgroundColor3 = Color3.fromRGB(13, 22, 18)
    Popup.BorderSizePixel = 0
    Popup.Visible = false
    Popup.ZIndex = 100
    Popup.Parent = self.ScreenGui

    local function SetSelectedValue(value)
        local newValue = tostring(value)
        selected = newValue
        DropBtn.Text = newValue .. " ▼"
        if callback then callback(newValue) end
    end

    local PopupStroke = Instance.new("UIStroke")
    PopupStroke.Color = accent
    PopupStroke.Thickness = 1.5
    PopupStroke.Parent = Popup

    local PopupScroll = Instance.new("ScrollingFrame")
    PopupScroll.Size = UDim2.new(1, -4, 1, -4)
    PopupScroll.Position = UDim2.fromOffset(2, 2)
    PopupScroll.BackgroundTransparency = 1
    PopupScroll.BorderSizePixel = 0
    PopupScroll.ScrollBarThickness = 3
    PopupScroll.ScrollBarImageColor3 = accent
    PopupScroll.CanvasSize = UDim2.new(0, 0, 0, #options * 26)
    PopupScroll.ZIndex = 101
    PopupScroll.Parent = Popup

    local PopupLayout = Instance.new("UIListLayout")
    PopupLayout.SortOrder = Enum.SortOrder.LayoutOrder
    PopupLayout.Padding = UDim.new(0, 1)
    PopupLayout.Parent = PopupScroll

    for i, opt in ipairs(options) do
        local OptBtn = Instance.new("TextButton")
        OptBtn.Size = UDim2.new(1, 0, 0, 25)
        OptBtn.LayoutOrder = i
        OptBtn.BackgroundColor3 = Color3.fromRGB(13, 22, 18)
        OptBtn.BorderSizePixel = 0
        OptBtn.Text = "  " .. opt
        OptBtn.TextColor3 = opt == selected and accent or LIGHT
        OptBtn.TextSize = 11
        OptBtn.Font = Enum.Font.GothamMedium
        OptBtn.TextXAlignment = Enum.TextXAlignment.Left
        OptBtn.AutoButtonColor = false
        OptBtn.ZIndex = 102
        OptBtn.Parent = PopupScroll

        OptBtn.MouseEnter:Connect(function()
            OptBtn.BackgroundColor3 = Shade(accent, 0.8)
        end)
        OptBtn.MouseLeave:Connect(function()
            OptBtn.BackgroundColor3 = Color3.fromRGB(13, 22, 18)
        end)
        OptBtn.MouseButton1Click:Connect(function()
            local newValue = tostring(opt)
            selected = newValue
            DropBtn.Text = newValue .. " ▼"
            for _, child in ipairs(PopupScroll:GetChildren()) do
                if child:IsA("TextButton") then
                    local txt = child.Text:gsub("^%s+", "")
                    child.TextColor3 = txt == newValue and accent or LIGHT
                end
            end
            Popup.Visible = false
            if callback then callback(newValue) end
        end)
    end

    DropBtn.MouseButton1Click:Connect(function()
        if Popup.Visible then
            Popup.Visible = false
        else
            local absPos = DropBtn.AbsolutePosition
            local absSize = DropBtn.AbsoluteSize
            Popup.Position = UDim2.fromOffset(absPos.X, absPos.Y + absSize.Y + 2)
            Popup.Visible = true
        end
    end)

    SetSelectedValue(selected)

    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and Popup.Visible then
            local mousePos = Vector2.new(input.Position.X, input.Position.Y)
            local absPos = Popup.AbsolutePosition
            local absSize = Popup.AbsoluteSize
            local btnPos = DropBtn.AbsolutePosition
            local btnSize = DropBtn.AbsoluteSize

            local inPopup = mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X and
                           mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y
            local inBtn = mousePos.X >= btnPos.X and mousePos.X <= btnPos.X + btnSize.X and
                         mousePos.Y >= btnPos.Y and mousePos.Y <= btnPos.Y + btnSize.Y

            if not inPopup and not inBtn then
                Popup.Visible = false
            end
        end
    end)

    return y + 42
end

--// ═══════════════════════════════════════════════════════════════
--//  COLOR WHEEL (HSV)
--// ═══════════════════════════════════════════════════════════════
function Gui:CreateColorPicker(label, defaultColor, callback, y)
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    local color = defaultColor or Color3.fromRGB(111, 211, 162)

    local PickerFrame = Instance.new("Frame")
    PickerFrame.Size = UDim2.new(1, 0, 0, 36)
    PickerFrame.Position = UDim2.fromOffset(0, y)
    PickerFrame.BackgroundTransparency = 1
    PickerFrame.ZIndex = 3
    PickerFrame.Parent = self.Content

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -100, 0, 36)
    Label.BackgroundTransparency = 1
    Label.Text = label
    Label.TextColor3 = Tint(accent, 0.72)
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = PickerFrame

    local Swatch = Instance.new("TextButton")
    Swatch.Size = UDim2.fromOffset(80, 26)
    Swatch.Position = UDim2.new(1, -100, 0, 5)
    Swatch.BackgroundColor3 = color
    Swatch.BorderSizePixel = 0
    Swatch.Text = ""
    Swatch.AutoButtonColor = false
    Swatch.ZIndex = 4
    Swatch.Parent = PickerFrame

    local SwatchStroke = Instance.new("UIStroke")
    SwatchStroke.Color = Shade(accent, 0.5)
    SwatchStroke.Thickness = 1
    SwatchStroke.Parent = Swatch

    --// Popup
    local Popup = Instance.new("Frame")
    Popup.Name = "ColorPickerPopup"
    Popup.Size = UDim2.fromOffset(212, 214)
    Popup.BackgroundColor3 = Color3.fromRGB(11, 19, 16)
    Popup.BorderSizePixel = 0
    Popup.Visible = false
    Popup.ZIndex = 100
    Popup.Parent = self.ScreenGui

    local PopupStroke = Instance.new("UIStroke")
    PopupStroke.Color = accent
    PopupStroke.Thickness = 1.5
    PopupStroke.Parent = Popup

    local h, s, v = Color3.toHSV(color)

    local SV = Instance.new("Frame")
    SV.Size = UDim2.fromOffset(196, 122)
    SV.Position = UDim2.fromOffset(8, 8)
    SV.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
    SV.BorderSizePixel = 0
    SV.ZIndex = 101
    SV.Parent = Popup

    local SatGrad = Instance.new("Frame")
    SatGrad.Size = UDim2.fromScale(1, 1)
    SatGrad.BackgroundColor3 = WHITE
    SatGrad.BorderSizePixel = 0
    SatGrad.ZIndex = 102
    SatGrad.Parent = SV

    local SatGradient = Instance.new("UIGradient")
    SatGradient.Rotation = 0
    SatGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    SatGradient.Parent = SatGrad

    local ValGrad = Instance.new("Frame")
    ValGrad.Size = UDim2.fromScale(1, 1)
    ValGrad.BackgroundColor3 = BLACK
    ValGrad.BorderSizePixel = 0
    ValGrad.ZIndex = 103
    ValGrad.Parent = SV

    local ValGradient = Instance.new("UIGradient")
    ValGradient.Rotation = 90
    ValGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0),
    })
    ValGradient.Parent = ValGrad

    local Cursor = Instance.new("Frame")
    Cursor.Size = UDim2.fromOffset(8, 8)
    Cursor.BackgroundTransparency = 1
    Cursor.BorderSizePixel = 0
    Cursor.ZIndex = 104
    Cursor.Parent = SV

    local CursorStroke = Instance.new("UIStroke")
    CursorStroke.Color = WHITE
    CursorStroke.Thickness = 1.5
    CursorStroke.Parent = Cursor

    local HueBar = Instance.new("Frame")
    HueBar.Size = UDim2.fromOffset(196, 14)
    HueBar.Position = UDim2.fromOffset(8, 138)
    HueBar.BackgroundColor3 = WHITE
    HueBar.BorderSizePixel = 0
    HueBar.ZIndex = 101
    HueBar.Parent = Popup

    local HueGradient = Instance.new("UIGradient")
    HueGradient.Rotation = 0
    HueGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.000, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.167, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.333, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.500, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.667, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.833, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1.000, Color3.fromRGB(255, 0, 0)),
    })
    HueGradient.Parent = HueBar

    local HueCursor = Instance.new("Frame")
    HueCursor.Size = UDim2.fromOffset(4, 20)
    HueCursor.Position = UDim2.new(h, -2, 0.5, -10)
    HueCursor.BackgroundColor3 = WHITE
    HueCursor.BorderSizePixel = 0
    HueCursor.ZIndex = 102
    HueCursor.Parent = HueBar

    local Preview = Instance.new("Frame")
    Preview.Size = UDim2.fromOffset(56, 24)
    Preview.Position = UDim2.fromOffset(8, 162)
    Preview.BackgroundColor3 = color
    Preview.BorderSizePixel = 0
    Preview.ZIndex = 101
    Preview.Parent = Popup

    local PreviewStroke = Instance.new("UIStroke")
    PreviewStroke.Color = Color3.fromRGB(60, 60, 60)
    PreviewStroke.Thickness = 1
    PreviewStroke.Parent = Preview

    local HexLabel = Instance.new("TextLabel")
    HexLabel.Size = UDim2.fromOffset(132, 24)
    HexLabel.Position = UDim2.fromOffset(72, 162)
    HexLabel.BackgroundColor3 = Color3.fromRGB(18, 30, 25)
    HexLabel.BorderSizePixel = 0
    HexLabel.Text = ""
    HexLabel.TextColor3 = WHITE
    HexLabel.TextSize = 12
    HexLabel.Font = Enum.Font.Code
    HexLabel.ZIndex = 101
    HexLabel.Parent = Popup

    local RGBLabel = Instance.new("TextLabel")
    RGBLabel.Size = UDim2.fromOffset(196, 16)
    RGBLabel.Position = UDim2.fromOffset(8, 190)
    RGBLabel.BackgroundTransparency = 1
    RGBLabel.Text = ""
    RGBLabel.TextColor3 = GRAY
    RGBLabel.TextSize = 11
    RGBLabel.Font = Enum.Font.Code
    RGBLabel.TextXAlignment = Enum.TextXAlignment.Left
    RGBLabel.ZIndex = 101
    RGBLabel.Parent = Popup

    local function PushColor(fireCallback)
        local c = Color3.fromHSV(h, s, v)
        color = c
        Swatch.BackgroundColor3 = c
        Preview.BackgroundColor3 = c
        SV.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        HueCursor.Position = UDim2.new(h, -2, 0.5, -10)
        Cursor.Position = UDim2.new(s, -4, 1 - v, -4)
        HexLabel.Text = string.format("#%02X%02X%02X",
            math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
        RGBLabel.Text = string.format("R %d   G %d   B %d",
            math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
        if fireCallback and callback then callback(c) end
    end

    local draggingSV = false
    local draggingHue = false

    local function UpdateSV(input)
        local pos = SV.AbsolutePosition
        local size = SV.AbsoluteSize
        s = math.clamp((input.Position.X - pos.X) / size.X, 0, 1)
        v = 1 - math.clamp((input.Position.Y - pos.Y) / size.Y, 0, 1)
        PushColor(true)
    end

    local function UpdateHue(input)
        local pos = HueBar.AbsolutePosition
        local size = HueBar.AbsoluteSize
        h = math.clamp((input.Position.X - pos.X) / size.X, 0, 1)
        PushColor(true)
    end

    SV.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSV = true
            UpdateSV(input)
        end
    end)
    HueBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingHue = true
            UpdateHue(input)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        if draggingSV then UpdateSV(input) end
        if draggingHue then UpdateHue(input) end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSV = false
            draggingHue = false
        end
    end)

    Swatch.MouseEnter:Connect(function() SwatchStroke.Color = accent end)
    Swatch.MouseLeave:Connect(function() SwatchStroke.Color = Shade(accent, 0.5) end)
    Swatch.MouseButton1Click:Connect(function()
        if Popup.Visible then
            Popup.Visible = false
        else
            local absPos = Swatch.AbsolutePosition
            local absSize = Swatch.AbsoluteSize
            local px = math.clamp(absPos.X + absSize.X - 212, 4, 10000)
            local py = math.clamp(absPos.Y + absSize.Y + 4, 4, 10000)
            Popup.Position = UDim2.fromOffset(px, py)
            Popup.Visible = true
            PushColor(false)
        end
    end)

    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and Popup.Visible then
            if draggingSV or draggingHue then return end
            local mousePos = Vector2.new(input.Position.X, input.Position.Y)
            local absPos = Popup.AbsolutePosition
            local absSize = Popup.AbsoluteSize
            local btnPos = Swatch.AbsolutePosition
            local btnSize = Swatch.AbsoluteSize

            local inPopup = mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X and
                            mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y
            local inBtn = mousePos.X >= btnPos.X and mousePos.X <= btnPos.X + btnSize.X and
                          mousePos.Y >= btnPos.Y and mousePos.Y <= btnPos.Y + btnSize.Y

            if not inPopup and not inBtn then
                Popup.Visible = false
            end
        end
    end)

    PushColor(false)

    return y + 42
end

function Gui:CreateButton(label, callback, y)
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 34)
    Btn.Position = UDim2.fromOffset(0, y)
    Btn.BackgroundColor3 = DARK_PANEL
    Btn.BorderSizePixel = 0
    Btn.Text = label
    Btn.TextColor3 = Tint(accent, 0.5)
    Btn.TextSize = 12
    Btn.Font = Enum.Font.GothamBold
    Btn.AutoButtonColor = false
    Btn.ZIndex = 3
    Btn.Parent = self.Content

    local BtnStroke = Instance.new("UIStroke")
    BtnStroke.Color = Shade(accent, 0.6)
    BtnStroke.Thickness = 1
    BtnStroke.Parent = Btn

    Btn.MouseEnter:Connect(function()
        Btn.BackgroundColor3 = Shade(accent, 0.86)
        BtnStroke.Color = accent
    end)
    Btn.MouseLeave:Connect(function()
        Btn.BackgroundColor3 = DARK_PANEL
        BtnStroke.Color = Shade(accent, 0.6)
    end)
    Btn.MouseButton1Click:Connect(function() if callback then callback() end end)

    return y + 40
end

--// ── Standalone hold button ──────────────────────────────────────
-- Momentary control: callback(true) while pressed, callback(false) on release.
function Gui:CreateHoldButton(label, callback, y, options)
    options = options or {}
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    local holdText = options.HoldText or "HOLDING"

    local Btn = Instance.new("TextButton")
    Btn.Name = options.Name or (label:gsub("%s+", ""))
    Btn.Size = UDim2.new(1, 0, 0, 34)
    Btn.Position = UDim2.fromOffset(0, y)
    Btn.BackgroundColor3 = DARK_PANEL
    Btn.BorderSizePixel = 0
    Btn.Text = label
    Btn.TextColor3 = Tint(accent, 0.5)
    Btn.TextSize = 12
    Btn.Font = Enum.Font.GothamBold
    Btn.AutoButtonColor = false
    Btn.ZIndex = 3
    Btn.Parent = self.Content

    local BtnStroke = Instance.new("UIStroke")
    BtnStroke.Color = Shade(accent, 0.6)
    BtnStroke.Thickness = 1
    BtnStroke.Parent = Btn

    local Fill = Instance.new("Frame")
    Fill.Size = UDim2.fromScale(0, 1)
    Fill.BackgroundColor3 = accent
    Fill.BackgroundTransparency = 0.7
    Fill.BorderSizePixel = 0
    Fill.ZIndex = 3
    Fill.Parent = Btn

    local held = false

    local function Idle()
        Btn.BackgroundColor3 = DARK_PANEL
        Btn.TextColor3 = Tint(accent, 0.5)
        BtnStroke.Color = Shade(accent, 0.6)
        Btn.Text = label
        Fill.Size = UDim2.fromScale(0, 1)
    end

    local function Press()
        if held or not Btn.Parent then return end
        held = true
        Btn.BackgroundColor3 = accent
        Btn.TextColor3 = BLACK
        BtnStroke.Color = Tint(accent, 0.4)
        Btn.Text = holdText
        Fill.Size = UDim2.fromScale(1, 1)
        if callback then task.spawn(function() pcall(callback, true) end) end
    end

    local function Release()
        if not held then return end
        held = false
        Idle()
        if callback then task.spawn(function() pcall(callback, false) end) end
    end

    self.ActiveHolds[Btn] = { Release = Release }

    Btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            Press()
        end
    end)
    Btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            Release()
        end
    end)
    Btn.MouseLeave:Connect(Release)
    Btn.Destroying:Connect(function()
        held = false
        self.ActiveHolds[Btn] = nil
    end)

    return y + 40
end

function Gui:CreateKeybindSetting(y)
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    local KeyLabel = Instance.new("TextLabel")
    KeyLabel.Size = UDim2.new(1, -140, 0, 28)
    KeyLabel.Position = UDim2.fromOffset(0, y)
    KeyLabel.BackgroundTransparency = 1
    KeyLabel.Text = "GUI Toggle Keybind"
    KeyLabel.TextColor3 = Tint(accent, 0.72)
    KeyLabel.TextSize = 13
    KeyLabel.Font = Enum.Font.GothamMedium
    KeyLabel.TextXAlignment = Enum.TextXAlignment.Left
    KeyLabel.ZIndex = 3
    KeyLabel.Parent = self.Content

    local KeyDescription = Instance.new("TextLabel")
    KeyDescription.Size = UDim2.new(1, -140, 0, 14)
    KeyDescription.Position = UDim2.fromOffset(0, y + 22)
    KeyDescription.BackgroundTransparency = 1
    KeyDescription.Text = "Press this key to show or hide the GUI."
    KeyDescription.TextColor3 = GRAY
    KeyDescription.TextSize = 10
    KeyDescription.Font = Enum.Font.Gotham
    KeyDescription.TextXAlignment = Enum.TextXAlignment.Left
    KeyDescription.ZIndex = 3
    KeyDescription.Parent = self.Content

    local Keybind = Instance.new("TextButton")
    Keybind.Name = "Keybind"
    Keybind.Size = UDim2.fromOffset(100, 30)
    Keybind.Position = UDim2.new(1, -140, 0, y)
    Keybind.BackgroundColor3 = DARK_PANEL
    Keybind.BorderSizePixel = 0
    Keybind.Text = ToggleKey.Name
    Keybind.TextColor3 = WHITE
    Keybind.TextSize = 12
    Keybind.Font = Enum.Font.GothamMedium
    Keybind.AutoButtonColor = false
    Keybind.ZIndex = 3
    Keybind.Parent = self.Content

    local KeyStroke = Instance.new("UIStroke")
    KeyStroke.Color = Shade(accent, 0.6)
    KeyStroke.Thickness = 1
    KeyStroke.Parent = Keybind

    Keybind.MouseEnter:Connect(function()
        if not WaitingForKey then Keybind.BackgroundColor3 = Shade(accent, 0.78) KeyStroke.Color = accent end
    end)
    Keybind.MouseLeave:Connect(function()
        if not WaitingForKey then Keybind.BackgroundColor3 = DARK_PANEL KeyStroke.Color = Shade(accent, 0.6) end
    end)
    Keybind.MouseButton1Click:Connect(function()
        if WaitingForKey then return end
        WaitingForKey = true
        Keybind.Text = "Press a key..."
        Keybind.TextColor3 = accent
        Keybind.BackgroundColor3 = Shade(accent, 0.7)
        KeyStroke.Color = accent
    end)

    return y + 58
end

function Gui:CreateMouseUnlockToggle(y)
    local accent = self.CurrentAccent or DEFAULT_ACCENT
    local toggleKey = self.CurrentTab .. "_UnlockMouseOnGUI"
    local savedState = self.ToggleStates[toggleKey]
    local State = savedState ~= nil and savedState or true
    UnlockMouseOnGUI = State

    local ToggleFrame = Instance.new("Frame")
    ToggleFrame.Size = UDim2.new(1, 0, 0, 36)
    ToggleFrame.Position = UDim2.fromOffset(0, y)
    ToggleFrame.BackgroundTransparency = 1
    ToggleFrame.ZIndex = 3
    ToggleFrame.Parent = self.Content

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -70, 0, 36)
    Label.BackgroundTransparency = 1
    Label.Text = "Unlock Mouse on GUI Toggle"
    Label.TextColor3 = Tint(accent, 0.72)
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = ToggleFrame

    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Size = UDim2.fromOffset(46, 26)
    ToggleBtn.Position = UDim2.new(1, -70, 0, 5)
    ToggleBtn.BackgroundColor3 = State and accent or DARK_PANEL
    ToggleBtn.BorderSizePixel = 0
    ToggleBtn.Text = State and "ON" or "OFF"
    ToggleBtn.TextColor3 = State and BLACK or GRAY
    ToggleBtn.TextSize = 10
    ToggleBtn.Font = Enum.Font.GothamBold
    ToggleBtn.AutoButtonColor = false
    ToggleBtn.ZIndex = 4
    ToggleBtn.Parent = ToggleFrame
    ApplySelectedGradient(ToggleBtn, State)

    local ToggleStroke = Instance.new("UIStroke")
    ToggleStroke.Color = State and accent or Shade(accent, 0.6)
    ToggleStroke.Thickness = 1
    ToggleStroke.Parent = ToggleBtn

    ToggleBtn.MouseEnter:Connect(function()
        ToggleBtn.BackgroundColor3 = State and Tint(accent, 0.35) or Shade(accent, 0.82)
        ApplySelectedGradient(ToggleBtn, State)
    end)
    ToggleBtn.MouseLeave:Connect(function()
        ToggleBtn.BackgroundColor3 = State and accent or DARK_PANEL
        ApplySelectedGradient(ToggleBtn, State)
    end)
    ToggleBtn.MouseButton1Click:Connect(function()
        State = not State
        self.ToggleStates[toggleKey] = State
        UnlockMouseOnGUI = State
        ToggleBtn.BackgroundColor3 = State and accent or DARK_PANEL
        ToggleBtn.TextColor3 = State and BLACK or GRAY
        ToggleBtn.Text = State and "ON" or "OFF"
        ToggleStroke.Color = State and accent or Shade(accent, 0.6)
        ApplySelectedGradient(ToggleBtn, State)
    end)

    return y + 42
end

return Gui
