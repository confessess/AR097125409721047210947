local Gui = {}
Gui.__index = Gui

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--// Colors
local BLACK      = Color3.fromRGB(8, 9, 12)
local BACKGROUND = Color3.fromRGB(18, 19, 24)
local DARK_PANEL = Color3.fromRGB(24, 25, 31)
local PANEL_ALT  = Color3.fromRGB(30, 32, 39)
local RED        = Color3.fromRGB(126, 131, 139)
local RED_BRIGHT = Color3.fromRGB(162, 168, 178)
local RED_DARK   = Color3.fromRGB(90, 96, 105)
local SELECTED   = Color3.fromRGB(142, 147, 157)
local HOVER      = Color3.fromRGB(35, 38, 46)
local WHITE      = Color3.fromRGB(245, 245, 247)
local LIGHT      = Color3.fromRGB(225, 226, 230)
local GRAY       = Color3.fromRGB(170, 176, 186)
local BORDER     = Color3.fromRGB(72, 77, 87)

--// Wave Config
local WAVE_COLOR        = Color3.fromRGB(170, 176, 184)
local WAVE_PEAK_TRANS   = 0.82
local WAVE_BAND_WIDTH   = 0.28
local WAVE_DURATION     = 2.4
local WAVE_PAUSE        = 1.0
local WAVE_ROTATION     = -45

--// State
local ToggleKey = Enum.KeyCode.RightShift
local WaitingForKey = false
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

--// Toggle state storage
Gui.ToggleStates = {}

--// NEW: Get toggle state
function Gui:GetToggleState(tabName, label)
    local toggleKey = tabName .. "_" .. label
    return self.ToggleStates[toggleKey]
end

--// NEW: Set toggle state (for hotkey sync)
function Gui:SetToggleState(tabName, label, state)
    local toggleKey = tabName .. "_" .. label
    self.ToggleStates[toggleKey] = state
end

--// ScreenGui
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

    local MainCorner = Instance.new("UICorner")
    MainCorner.CornerRadius = UDim.new(0, 14)
    MainCorner.Parent = Main

    local MainStroke = Instance.new("UIStroke")
    MainStroke.Color = RED
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

    local BgCorner = Instance.new("UICorner")
    BgCorner.CornerRadius = UDim.new(0, 14)
    BgCorner.Parent = Background

    local sheen = Instance.new("Frame")
    sheen.Name = "ENI_WaveSheen"
    sheen.Size = UDim2.fromScale(1, 1)
    sheen.BackgroundColor3 = WAVE_COLOR
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

    local TopCorner = Instance.new("UICorner")
    TopCorner.CornerRadius = UDim.new(0, 14)
    TopCorner.Parent = Top

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
    Accent.BackgroundColor3 = RED_BRIGHT
    Accent.BorderSizePixel = 0
    Accent.ZIndex = 5
    Accent.Parent = Top

    local AccentCorner = Instance.new("UICorner")
    AccentCorner.CornerRadius = UDim.new(1, 0)
    AccentCorner.Parent = Accent

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -140, 0, 26)
    Title.Position = UDim2.fromOffset(22, 10)
    Title.BackgroundTransparency = 1
    Title.Text = "LIGHT HUB"
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
    Subtitle.Text = "Arsenal • Utility Hub"
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

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 8)
    CloseCorner.Parent = Close

    Close.MouseEnter:Connect(function() Close.BackgroundColor3 = Color3.fromRGB(215, 215, 215) end)
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

    local SidebarCorner = Instance.new("UICorner")
    SidebarCorner.CornerRadius = UDim.new(0, 10)
    SidebarCorner.Parent = Sidebar

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

    local ContentTitle = Instance.new("TextLabel")
    ContentTitle.Size = UDim2.new(1, 0, 0, 28)
    ContentTitle.Position = UDim2.fromOffset(0, 0)
    ContentTitle.BackgroundTransparency = 1
    ContentTitle.Text = "Combat"
    ContentTitle.TextColor3 = WHITE
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

    self.ScreenGui = ScreenGui
    self.Main = Main
    self.Top = Top
    self.Sidebar = Sidebar
    self.Content = Content
    self.ContentTitle = ContentTitle
    self.ContentSubtitle = ContentSubtitle
    self.SavedPosition = SavedPosition
    self.OriginalSize = OriginalSize
    self.Tabs = {}
    self.CurrentTab = nil
    self.TabButtons = {}

    UserInputService.InputBegan:Connect(function(input, processed)
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

    local ButtonCorner = Instance.new("UICorner")
    ButtonCorner.CornerRadius = UDim.new(0, 8)
    ButtonCorner.Parent = Button

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
    Indicator.BackgroundColor3 = RED_BRIGHT
    Indicator.BorderSizePixel = 0
    Indicator.Visible = false
    Indicator.ZIndex = 5
    Indicator.Parent = Button

    local IndicatorCorner = Instance.new("UICorner")
    IndicatorCorner.CornerRadius = UDim.new(1, 0)
    IndicatorCorner.Parent = Indicator

    local ButtonStroke = Instance.new("UIStroke")
    ButtonStroke.Thickness = 1
    ButtonStroke.Transparency = 1
    ButtonStroke.Parent = Button

    self.TabButtons[name] = { Button = Button, Text = Text, Indicator = Indicator, Stroke = ButtonStroke }

    Button.MouseEnter:Connect(function()
        if self.CurrentTab ~= name then
            Button.BackgroundColor3 = HOVER
            Text.TextColor3 = WHITE
        end
    end)
    Button.MouseLeave:Connect(function()
        if self.CurrentTab ~= name then
            Button.BackgroundColor3 = BLACK
            Text.TextColor3 = Color3.fromRGB(165, 165, 165)
        end
    end)
    Button.MouseButton1Click:Connect(function() self:SwitchTab(name) end)

    local tabData = { Name = name, Description = description, Elements = {} }
    table.insert(self.Tabs, tabData)

    if #self.Tabs == 1 then self:SwitchTab(name) end
    return tabData
end

function Gui:SwitchTab(name)
    self.CurrentTab = name
    for tabName, data in pairs(self.TabButtons) do
        if tabName == name then
            data.Button.BackgroundColor3 = SELECTED
            data.Text.TextColor3 = WHITE
            data.Indicator.Visible = true
            data.Stroke.Color = RED_BRIGHT
            data.Stroke.Transparency = 0.45
        else
            data.Button.BackgroundColor3 = BLACK
            data.Text.TextColor3 = Color3.fromRGB(165, 165, 165)
            data.Indicator.Visible = false
            data.Stroke.Color = BLACK
            data.Stroke.Transparency = 1
        end
    end

    self.ContentTitle.Text = name
    self.ContentSubtitle.Text = self:GetTabDescription(name) or ""

    for _, child in ipairs(self.Content:GetChildren()) do
        if child ~= self.ContentTitle and child ~= self.ContentSubtitle then
            child:Destroy()
        end
    end

    local tab = self:GetTab(name)
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
    if tab then tab.Rebuild = callback end
end

function Gui:CreateScrollContent()
    local ScrollFrame = Instance.new("ScrollingFrame")
    ScrollFrame.Name = "TabScroll"
    ScrollFrame.Size = UDim2.new(1, 0, 1, -54)
    ScrollFrame.Position = UDim2.fromOffset(0, 54)
    ScrollFrame.BackgroundTransparency = 1
    ScrollFrame.BorderSizePixel = 0
    ScrollFrame.ScrollBarThickness = 4
    ScrollFrame.ScrollBarImageColor3 = RED_BRIGHT
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
    y = y or 0
    local Section = Instance.new("TextLabel")
    Section.Size = UDim2.new(1, 0, 0, 24)
    Section.Position = UDim2.fromOffset(0, y)
    Section.BackgroundTransparency = 1
    Section.Text = text
    Section.TextColor3 = WHITE
    Section.TextSize = 14
    Section.Font = Enum.Font.GothamBold
    Section.TextXAlignment = Enum.TextXAlignment.Left
    Section.ZIndex = 3
    Section.Parent = self.Content

    local Divider = Instance.new("Frame")
    Divider.Size = UDim2.new(1, 0, 0, 1)
    Divider.Position = UDim2.fromOffset(0, y + 28)
    Divider.BackgroundColor3 = BORDER
    Divider.BorderSizePixel = 0
    Divider.ZIndex = 3
    Divider.Parent = self.Content

    return y + 40
end

function Gui:CreateToggle(label, default, callback, y)
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
    Label.TextColor3 = LIGHT
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = ToggleFrame

    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Size = UDim2.fromOffset(46, 26)
    ToggleBtn.Position = UDim2.new(1, -70, 0, 5)
    ToggleBtn.BackgroundColor3 = State and RED_BRIGHT or DARK_PANEL
    ToggleBtn.BorderSizePixel = 0
    ToggleBtn.Text = State and "ON" or "OFF"
    ToggleBtn.TextColor3 = State and WHITE or GRAY
    ToggleBtn.TextSize = 10
    ToggleBtn.Font = Enum.Font.GothamBold
    ToggleBtn.AutoButtonColor = false
    ToggleBtn.ZIndex = 4
    ToggleBtn.Parent = ToggleFrame

    local ToggleCorner = Instance.new("UICorner")
    ToggleCorner.CornerRadius = UDim.new(0, 6)
    ToggleCorner.Parent = ToggleBtn

    local ToggleStroke = Instance.new("UIStroke")
    ToggleStroke.Color = State and RED or BORDER
    ToggleStroke.Thickness = 1
    ToggleStroke.Parent = ToggleBtn

    ToggleBtn.MouseEnter:Connect(function()
        ToggleBtn.BackgroundColor3 = State and Color3.fromRGB(215, 40, 45) or Color3.fromRGB(25, 25, 25)
    end)
    ToggleBtn.MouseLeave:Connect(function()
        ToggleBtn.BackgroundColor3 = State and RED_BRIGHT or DARK_PANEL
    end)
    ToggleBtn.MouseButton1Click:Connect(function()
        State = not State
        self.ToggleStates[toggleKey] = State
        ToggleBtn.BackgroundColor3 = State and RED_BRIGHT or DARK_PANEL
        ToggleBtn.TextColor3 = State and WHITE or GRAY
        ToggleBtn.Text = State and "ON" or "OFF"
        ToggleStroke.Color = State and RED or BORDER
        if callback then callback(State) end
    end)

    return y + 42
end

function Gui:CreateSlider(label, min, max, default, callback, y)
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
    Label.TextColor3 = LIGHT
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
    ValueText.TextColor3 = RED_BRIGHT
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

    local TrackCorner = Instance.new("UICorner")
    TrackCorner.CornerRadius = UDim.new(0, 2)
    TrackCorner.Parent = Track

    local Fill = Instance.new("Frame")
    local range = max - min
    local startPos = range > 0 and (default - min) / range or 0
    Fill.Size = UDim2.new(startPos, 0, 1, 0)
    Fill.BackgroundColor3 = RED_BRIGHT
    Fill.BorderSizePixel = 0
    Fill.ZIndex = 5
    Fill.Parent = Track

    local FillCorner = Instance.new("UICorner")
    FillCorner.CornerRadius = UDim.new(0, 2)
    FillCorner.Parent = Fill

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.fromOffset(14, 14)
    Knob.Position = UDim2.new(startPos, -7, 0.5, -7)
    Knob.BackgroundColor3 = WHITE
    Knob.BorderSizePixel = 0
    Knob.ZIndex = 5
    Knob.Parent = Track

    local KnobCorner = Instance.new("UICorner")
    KnobCorner.CornerRadius = UDim.new(1, 0)
    KnobCorner.Parent = Knob

    local Dragging = false

    local function update(input)
        local pos = math.clamp((input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
        local value = math.floor(min + (pos * range))
        Fill.Size = UDim2.new(pos, 0, 1, 0)
        Knob.Position = UDim2.new(pos, -7, 0.5, -7)
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
    Label.TextColor3 = LIGHT
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = DropFrame

    local selected = default or options[1]

    local DropBtn = Instance.new("TextButton")
    DropBtn.Size = UDim2.fromOffset(150, 28)
    DropBtn.Position = UDim2.new(1, -174, 0, 4)
    DropBtn.BackgroundColor3 = DARK_PANEL
    DropBtn.BorderSizePixel = 0
    DropBtn.Text = selected .. " ▼"
    DropBtn.TextColor3 = WHITE
    DropBtn.TextSize = 11
    DropBtn.Font = Enum.Font.GothamMedium
    DropBtn.AutoButtonColor = false
    DropBtn.ZIndex = 4
    DropBtn.Parent = DropFrame

    local DropCorner = Instance.new("UICorner")
    DropCorner.CornerRadius = UDim.new(0, 6)
    DropCorner.Parent = DropBtn

    local DropStroke = Instance.new("UIStroke")
    DropStroke.Color = BORDER
    DropStroke.Thickness = 1
    DropStroke.Parent = DropBtn

    local Popup = Instance.new("Frame")
    Popup.Name = "DropdownPopup"
    Popup.Size = UDim2.fromOffset(150, math.min(#options * 26, 260))
    Popup.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    Popup.BorderSizePixel = 0
    Popup.Visible = false
    Popup.ZIndex = 100
    Popup.Parent = self.ScreenGui

    local PopupCorner = Instance.new("UICorner")
    PopupCorner.CornerRadius = UDim.new(0, 8)
    PopupCorner.Parent = Popup

    local PopupStroke = Instance.new("UIStroke")
    PopupStroke.Color = RED
    PopupStroke.Thickness = 1.5
    PopupStroke.Parent = Popup

    local PopupScroll = Instance.new("ScrollingFrame")
    PopupScroll.Size = UDim2.new(1, -4, 1, -4)
    PopupScroll.Position = UDim2.fromOffset(2, 2)
    PopupScroll.BackgroundTransparency = 1
    PopupScroll.BorderSizePixel = 0
    PopupScroll.ScrollBarThickness = 3
    PopupScroll.ScrollBarImageColor3 = RED_BRIGHT
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
        OptBtn.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
        OptBtn.BorderSizePixel = 0
        OptBtn.Text = "  " .. opt
        OptBtn.TextColor3 = opt == selected and RED_BRIGHT or LIGHT
        OptBtn.TextSize = 11
        OptBtn.Font = Enum.Font.GothamMedium
        OptBtn.TextXAlignment = Enum.TextXAlignment.Left
        OptBtn.AutoButtonColor = false
        OptBtn.ZIndex = 102
        OptBtn.Parent = PopupScroll

        OptBtn.MouseEnter:Connect(function()
            OptBtn.BackgroundColor3 = Color3.fromRGB(40, 22, 24)
        end)
        OptBtn.MouseLeave:Connect(function()
            OptBtn.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
        end)
        OptBtn.MouseButton1Click:Connect(function()
            selected = opt
            DropBtn.Text = opt .. " ▼"
            for _, child in ipairs(PopupScroll:GetChildren()) do
                if child:IsA("TextButton") then
                    local txt = child.Text:gsub("^%s+", "")
                    child.TextColor3 = txt == opt and RED_BRIGHT or LIGHT
                end
            end
            Popup.Visible = false
            if callback then callback(opt) end
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

    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and Popup.Visible then
            local mousePos = UserInputService:GetMouseLocation()
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

function Gui:CreateButton(label, callback, y)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 34)
    Btn.Position = UDim2.fromOffset(0, y)
    Btn.BackgroundColor3 = DARK_PANEL
    Btn.BorderSizePixel = 0
    Btn.Text = label
    Btn.TextColor3 = WHITE
    Btn.TextSize = 12
    Btn.Font = Enum.Font.GothamBold
    Btn.AutoButtonColor = false
    Btn.ZIndex = 3
    Btn.Parent = self.Content

    local BtnCorner = Instance.new("UICorner")
    BtnCorner.CornerRadius = UDim.new(0, 6)
    BtnCorner.Parent = Btn

    local BtnStroke = Instance.new("UIStroke")
    BtnStroke.Color = BORDER
    BtnStroke.Thickness = 1
    BtnStroke.Parent = Btn

    Btn.MouseEnter:Connect(function()
        Btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        BtnStroke.Color = RED
    end)
    Btn.MouseLeave:Connect(function()
        Btn.BackgroundColor3 = DARK_PANEL
        BtnStroke.Color = BORDER
    end)
    Btn.MouseButton1Click:Connect(function() if callback then callback() end end)

    return y + 40
end

function Gui:CreateKeybindSetting(y)
    local KeyLabel = Instance.new("TextLabel")
    KeyLabel.Size = UDim2.new(1, -140, 0, 28)
    KeyLabel.Position = UDim2.fromOffset(0, y)
    KeyLabel.BackgroundTransparency = 1
    KeyLabel.Text = "GUI Toggle Keybind"
    KeyLabel.TextColor3 = LIGHT
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

    local KeyCorner = Instance.new("UICorner")
    KeyCorner.CornerRadius = UDim.new(0, 7)
    KeyCorner.Parent = Keybind

    local KeyStroke = Instance.new("UIStroke")
    KeyStroke.Color = BORDER
    KeyStroke.Thickness = 1
    KeyStroke.Parent = Keybind

    Keybind.MouseEnter:Connect(function()
        if not WaitingForKey then Keybind.BackgroundColor3 = SELECTED KeyStroke.Color = RED end
    end)
    Keybind.MouseLeave:Connect(function()
        if not WaitingForKey then Keybind.BackgroundColor3 = DARK_PANEL KeyStroke.Color = BORDER end
    end)
    Keybind.MouseButton1Click:Connect(function()
        if WaitingForKey then return end
        WaitingForKey = true
        Keybind.Text = "Press a key..."
        Keybind.TextColor3 = RED_BRIGHT
        Keybind.BackgroundColor3 = RED_DARK
        KeyStroke.Color = RED_BRIGHT
    end)

    return y + 58
end

function Gui:CreateMouseUnlockToggle(y)
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
    Label.TextColor3 = LIGHT
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = ToggleFrame

    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Size = UDim2.fromOffset(46, 26)
    ToggleBtn.Position = UDim2.new(1, -70, 0, 5)
    ToggleBtn.BackgroundColor3 = State and RED_BRIGHT or DARK_PANEL
    ToggleBtn.BorderSizePixel = 0
    ToggleBtn.Text = State and "ON" or "OFF"
    ToggleBtn.TextColor3 = State and WHITE or GRAY
    ToggleBtn.TextSize = 10
    ToggleBtn.Font = Enum.Font.GothamBold
    ToggleBtn.AutoButtonColor = false
    ToggleBtn.ZIndex = 4
    ToggleBtn.Parent = ToggleFrame

    local ToggleCorner = Instance.new("UICorner")
    ToggleCorner.CornerRadius = UDim.new(0, 6)
    ToggleCorner.Parent = ToggleBtn

    local ToggleStroke = Instance.new("UIStroke")
    ToggleStroke.Color = State and RED or BORDER
    ToggleStroke.Thickness = 1
    ToggleStroke.Parent = ToggleBtn

    ToggleBtn.MouseEnter:Connect(function()
        ToggleBtn.BackgroundColor3 = State and Color3.fromRGB(215, 40, 45) or Color3.fromRGB(25, 25, 25)
    end)
    ToggleBtn.MouseLeave:Connect(function()
        ToggleBtn.BackgroundColor3 = State and RED_BRIGHT or DARK_PANEL
    end)
    ToggleBtn.MouseButton1Click:Connect(function()
        State = not State
        self.ToggleStates[toggleKey] = State
        UnlockMouseOnGUI = State
        ToggleBtn.BackgroundColor3 = State and RED_BRIGHT or DARK_PANEL
        ToggleBtn.TextColor3 = State and WHITE or GRAY
        ToggleBtn.Text = State and "ON" or "OFF"
        ToggleStroke.Color = State and RED or BORDER
    end)

    return y + 42
end

return Gui