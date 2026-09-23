local Movement = {}
Movement.__index = Movement

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

Movement.Config = {
    -- Master switches (GUI toggles) -- these gate the hotkeys
    SpeedEnabled = false,
    FlyEnabled = false,
    NoclipEnabled = false,
    BhopEnabled = false,
    ThirdPersonEnabled = false,

    -- Active states (controlled by hotkeys) -- these control actual functionality
    SpeedActive = false,
    FlyActive = false,
    NoclipActive = false,
    BhopActive = false,
    ThirdPersonActive = false,

    -- Settings
    WalkSpeed = 50,
    FlySpeed = 50,
    BhopSpeed = 40,
    BhopNormalSpeed = 22,
    BhopRayStartOffset = -3,
    BhopRayLength = 1,

    -- Toggle keys
    SpeedToggleKey = Enum.KeyCode.LeftShift,
    FlyToggleKey = Enum.KeyCode.F,
    NoclipToggleKey = Enum.KeyCode.N,
    BhopToggleKey = Enum.KeyCode.B,
}

--// Store GUI reference
Movement.Gui = nil

--// Speed logic
local function SetSpeed(speed)
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = speed
    end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    if Movement.Config.SpeedEnabled and Movement.Config.SpeedActive then
        char:WaitForChild("Humanoid")
        SetSpeed(Movement.Config.WalkSpeed)
    end
    if Movement.Config.FlyEnabled and Movement.Config.FlyActive then
        task.wait(0.3)
        Movement:StartFlying()
    end
    if Movement.Config.NoclipEnabled and Movement.Config.NoclipActive then
        task.wait(0.5)
        Movement:StartNoclip()
    end
    if Movement.Config.ThirdPersonEnabled then
        task.wait(0.5)
        Movement:EnableThirdPerson()
    end
    if Movement.Config.BhopEnabled and Movement.Config.BhopActive then
        task.wait(0.3)
        Movement:StartBhop()
    end
end)

RunService.RenderStepped:Connect(function()
    if Movement.Config.SpeedEnabled and Movement.Config.SpeedActive and not Movement.Config.BhopActive then
        local char = LocalPlayer.Character
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.WalkSpeed ~= Movement.Config.WalkSpeed then
            humanoid.WalkSpeed = Movement.Config.WalkSpeed
        end
    end
end)

--// Bhop logic
local BhopConnection = nil

function Movement:StartBhop()
    if BhopConnection then return end
    BhopConnection = RunService.Heartbeat:Connect(function()
        if not Movement.Config.BhopEnabled or not Movement.Config.BhopActive then return end

        local char = LocalPlayer.Character
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end

        local holdingSpace = UserInputService:IsKeyDown(Enum.KeyCode.Space)

        if holdingSpace then
            if humanoid.WalkSpeed ~= Movement.Config.BhopSpeed then
                humanoid.WalkSpeed = Movement.Config.BhopSpeed
            end

            local rootPart = char:FindFirstChild("HumanoidRootPart")
            if rootPart then
                local rayOrigin = rootPart.Position + Vector3.new(0, Movement.Config.BhopRayStartOffset, 0)
                local rayDirection = Vector3.new(0, -Movement.Config.BhopRayLength, 0)

                local raycastParams = RaycastParams.new()
                raycastParams.FilterDescendantsInstances = {char}
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.IgnoreWater = true

                local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

                if raycastResult then
                    humanoid.Jump = true
                end
            end
        else
            if humanoid.WalkSpeed ~= Movement.Config.BhopNormalSpeed then
                humanoid.WalkSpeed = Movement.Config.BhopNormalSpeed
            end
        end
    end)
end

function Movement:StopBhop()
    if BhopConnection then
        BhopConnection:Disconnect()
        BhopConnection = nil
    end
    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = Movement.Config.BhopNormalSpeed
        end
    end
end

function Movement:SetBhopEnabled(state)
    Movement.Config.BhopEnabled = state
    if Movement.Gui then
        Movement.Gui:SetToggleState("Movement", "Bhop", state)
    end
    if not state then
        -- Master switch turned off -- force active off too
        Movement.Config.BhopActive = false
        Movement:StopBhop()
    elseif state and Movement.Config.BhopActive then
        -- Master switch turned on and was already active -- start it
        Movement:StartBhop()
    end
end

function Movement:ToggleBhopActive()
    -- Hotkey only works if master switch is ON
    if not Movement.Config.BhopEnabled then return end
    Movement.Config.BhopActive = not Movement.Config.BhopActive
    if Movement.Config.BhopActive then
        Movement:StartBhop()
    else
        Movement:StopBhop()
    end
end

--// Fly logic (CFrame-based)
local FlyConnection = nil
local BodyVelocity = nil
local BodyGyro = nil

function Movement:StartFlying()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then return end

    humanoid.PlatformStand = true

    BodyGyro = Instance.new("BodyGyro")
    BodyGyro.MaxTorque = Vector3.new(400000, 400000, 400000)
    BodyGyro.P = 10000
    BodyGyro.CFrame = hrp.CFrame
    BodyGyro.Parent = hrp

    BodyVelocity = Instance.new("BodyVelocity")
    BodyVelocity.MaxForce = Vector3.new(400000, 400000, 400000)
    BodyVelocity.Velocity = Vector3.zero
    BodyVelocity.Parent = hrp

    FlyConnection = RunService.Heartbeat:Connect(function()
        if not Movement.Config.FlyEnabled or not Movement.Config.FlyActive then
            Movement:StopFlying()
            return
        end

        local currentChar = LocalPlayer.Character
        if not currentChar then return end
        local currentHrp = currentChar:FindFirstChild("HumanoidRootPart")
        local currentHumanoid = currentChar:FindFirstChildOfClass("Humanoid")
        if not currentHrp or not currentHumanoid then return end

        local moveDir = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveDir = moveDir + Camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDir = moveDir - Camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveDir = moveDir - Camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDir = moveDir + Camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            moveDir = moveDir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            moveDir = moveDir - Vector3.new(0, 1, 0)
        end

        if moveDir.Magnitude > 0 then
            moveDir = moveDir.Unit * Movement.Config.FlySpeed
            local newCFrame = currentHrp.CFrame + (moveDir * RunService.Heartbeat:Wait())
            currentHrp.CFrame = newCFrame
        end

        if BodyGyro and BodyGyro.Parent then
            BodyGyro.CFrame = Camera.CFrame
        end
    end)
end

function Movement:StopFlying()
    if FlyConnection then
        FlyConnection:Disconnect()
        FlyConnection = nil
    end

    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, child in ipairs(hrp:GetChildren()) do
                if child:IsA("BodyGyro") or child:IsA("BodyVelocity") then
                    child:Destroy()
                end
            end
        end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.PlatformStand = false
        end
    end

    BodyVelocity = nil
    BodyGyro = nil
end

function Movement:SetFlyEnabled(state)
    Movement.Config.FlyEnabled = state
    if Movement.Gui then
        Movement.Gui:SetToggleState("Movement", "Fly", state)
    end
    if not state then
        Movement.Config.FlyActive = false
        Movement:StopFlying()
    elseif state and Movement.Config.FlyActive then
        Movement:StartFlying()
    end
end

function Movement:ToggleFlyActive()
    if not Movement.Config.FlyEnabled then return end
    Movement.Config.FlyActive = not Movement.Config.FlyActive
    if Movement.Config.FlyActive then
        Movement:StartFlying()
    else
        Movement:StopFlying()
    end
end

--//  3RD PERSON CAMERA
local thirdPersonConnection = nil
local thirdPersonPropConnection = nil

function Movement:EnableThirdPerson()
    local function ForceThirdPerson()
        if LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
            LocalPlayer.CameraMode = Enum.CameraMode.Classic
        end
    end

    ForceThirdPerson()

    if thirdPersonConnection then thirdPersonConnection:Disconnect() end
    thirdPersonConnection = RunService.RenderStepped:Connect(ForceThirdPerson)

    if thirdPersonPropConnection then thirdPersonPropConnection:Disconnect() end
    thirdPersonPropConnection = LocalPlayer:GetPropertyChangedSignal("CameraMode"):Connect(ForceThirdPerson)
end

function Movement:DisableThirdPerson()
    if thirdPersonConnection then
        thirdPersonConnection:Disconnect()
        thirdPersonConnection = nil
    end

    if thirdPersonPropConnection then
        thirdPersonPropConnection:Disconnect()
        thirdPersonPropConnection = nil
    end

    LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
end

function Movement:SetThirdPersonEnabled(state)
    Movement.Config.ThirdPersonEnabled = state
    Movement.Config.ThirdPersonActive = state
    if Movement.Gui then
        Movement.Gui:SetToggleState("Movement", "3rd Person", state)
    end
    if state then
        Movement:EnableThirdPerson()
    else
        Movement:DisableThirdPerson()
    end
end

--//  NOCLIP
local NoclipConnection = nil

function Movement:StartNoclip()
    if NoclipConnection then NoclipConnection:Disconnect() end
    NoclipConnection = RunService.Stepped:Connect(function()
        if not Movement.Config.NoclipEnabled or not Movement.Config.NoclipActive then return end
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end)
end

function Movement:StopNoclip()
    if NoclipConnection then
        NoclipConnection:Disconnect()
        NoclipConnection = nil
    end
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

function Movement:SetNoclipEnabled(state)
    Movement.Config.NoclipEnabled = state
    if Movement.Gui then
        Movement.Gui:SetToggleState("Movement", "Noclip", state)
    end
    if not state then
        Movement.Config.NoclipActive = false
        Movement:StopNoclip()
    elseif state and Movement.Config.NoclipActive then
        Movement:StartNoclip()
    end
end

function Movement:ToggleNoclipActive()
    if not Movement.Config.NoclipEnabled then return end
    Movement.Config.NoclipActive = not Movement.Config.NoclipActive
    if Movement.Config.NoclipActive then
        Movement:StartNoclip()
    else
        Movement:StopNoclip()
    end
end

--// SPEED
function Movement:SetSpeedEnabled(state)
    Movement.Config.SpeedEnabled = state
    if Movement.Gui then
        Movement.Gui:SetToggleState("Movement", "Speed", state)
    end
    if not state then
        Movement.Config.SpeedActive = false
        local char = LocalPlayer.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.WalkSpeed = 16 end
        end
    elseif state and Movement.Config.SpeedActive then
        SetSpeed(Movement.Config.WalkSpeed)
    end
end

function Movement:ToggleSpeedActive()
    if not Movement.Config.SpeedEnabled then return end
    Movement.Config.SpeedActive = not Movement.Config.SpeedActive
    if Movement.Config.SpeedActive then
        SetSpeed(Movement.Config.WalkSpeed)
    else
        local char = LocalPlayer.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.WalkSpeed = 16 end
        end
    end
end

--// ═══════════════════════════════════════════════════════════════
--//  KEYBIND CAPTURE HELPERS
--// ═══════════════════════════════════════════════════════════════

local DARK_PANEL = Color3.fromRGB(14, 14, 14)
local BORDER = Color3.fromRGB(65, 25, 27)
local RED = Color3.fromRGB(145, 20, 25)
local RED_BRIGHT = Color3.fromRGB(195, 28, 35)
local WHITE = Color3.fromRGB(255, 255, 255)
local LIGHT = Color3.fromRGB(225, 225, 225)
local GRAY = Color3.fromRGB(150, 150, 150)
local SELECTED = Color3.fromRGB(45, 15, 17)

local WaitingForKey = nil
local KeybindButtons = {}

local function GetKeyDisplayName(key)
    if not key then return "None" end
    if typeof(key) == "EnumItem" then
        if key.EnumType == Enum.KeyCode then
            return key.Name
        elseif key.EnumType == Enum.UserInputType then
            if key == Enum.UserInputType.MouseButton1 then return "LMB" end
            if key == Enum.UserInputType.MouseButton2 then return "RMB" end
            if key == Enum.UserInputType.MouseButton3 then return "MMB" end
            return key.Name
        end
    end
    return tostring(key)
end

local function UpdateKeybindButton(name)
    local btn = KeybindButtons[name]
    if not btn then return end
    local key = nil
    if name == "Speed" then key = Movement.Config.SpeedToggleKey
    elseif name == "Fly" then key = Movement.Config.FlyToggleKey
    elseif name == "Noclip" then key = Movement.Config.NoclipToggleKey
    elseif name == "Bhop" then key = Movement.Config.BhopToggleKey end
    btn.Text = "Bind: " .. GetKeyDisplayName(key)
end

local function CreateKeybindCapture(g, y, name, configKey)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 36)
    Frame.Position = UDim2.fromOffset(0, y)
    Frame.BackgroundTransparency = 1
    Frame.ZIndex = 3
    Frame.Parent = g.Content

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -140, 0, 36)
    Label.BackgroundTransparency = 1
    Label.Text = name .. " Toggle Key"
    Label.TextColor3 = LIGHT
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.ZIndex = 4
    Label.Parent = Frame

    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.fromOffset(120, 28)
    Btn.Position = UDim2.new(1, -140, 0, 4)
    Btn.BackgroundColor3 = DARK_PANEL
    Btn.BorderSizePixel = 0
    Btn.Text = "Bind: " .. GetKeyDisplayName(Movement.Config[configKey])
    Btn.TextColor3 = WHITE
    Btn.TextSize = 11
    Btn.Font = Enum.Font.GothamMedium
    Btn.AutoButtonColor = false
    Btn.ZIndex = 4
    Btn.Parent = Frame

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Btn

    local Stroke = Instance.new("UIStroke")
    Stroke.Color = BORDER
    Stroke.Thickness = 1
    Stroke.Parent = Btn

    KeybindButtons[name] = Btn

    Btn.MouseEnter:Connect(function()
        if WaitingForKey ~= name then
            Btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
            Stroke.Color = RED
        end
    end)
    Btn.MouseLeave:Connect(function()
        if WaitingForKey ~= name then
            Btn.BackgroundColor3 = DARK_PANEL
            Stroke.Color = BORDER
        end
    end)

    Btn.MouseButton1Click:Connect(function()
        if WaitingForKey then return end
        WaitingForKey = name
        Btn.Text = "Press a key..."
        Btn.TextColor3 = RED_BRIGHT
        Btn.BackgroundColor3 = SELECTED
        Stroke.Color = RED_BRIGHT
    end)

    return y + 42
end

-- Global input listener for keybind capture
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not WaitingForKey then return end
    if gameProcessed then return end

    local captured = nil
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
        captured = input.KeyCode
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        captured = Enum.UserInputType.MouseButton1
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        captured = Enum.UserInputType.MouseButton2
    elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
        captured = Enum.UserInputType.MouseButton3
    end

    if captured then
        local name = WaitingForKey
        WaitingForKey = nil

        if name == "Speed" then Movement.Config.SpeedToggleKey = captured
        elseif name == "Fly" then Movement.Config.FlyToggleKey = captured
        elseif name == "Noclip" then Movement.Config.NoclipToggleKey = captured
        elseif name == "Bhop" then Movement.Config.BhopToggleKey = captured end

        UpdateKeybindButton(name)
        local btn = KeybindButtons[name]
        if btn then
            btn.TextColor3 = WHITE
            btn.BackgroundColor3 = DARK_PANEL
            local stroke = btn:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = BORDER end
        end
    end
end)

-- Hotkey handlers -- ONLY work when the corresponding master switch is ON
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    local function matches(key)
        if typeof(key) ~= "EnumItem" then return false end
        if key.EnumType == Enum.KeyCode then
            return input.KeyCode == key
        elseif key.EnumType == Enum.UserInputType then
            return input.UserInputType == key
        end
        return false
    end

    -- Speed hotkey -- only works if SpeedEnabled (master switch) is ON
    if matches(Movement.Config.SpeedToggleKey) then
        Movement:ToggleSpeedActive()
    end

    -- Fly hotkey -- only works if FlyEnabled (master switch) is ON
    if matches(Movement.Config.FlyToggleKey) then
        Movement:ToggleFlyActive()
    end

    -- Noclip hotkey -- only works if NoclipEnabled (master switch) is ON
    if matches(Movement.Config.NoclipToggleKey) then
        Movement:ToggleNoclipActive()
    end

    -- Bhop hotkey -- only works if BhopEnabled (master switch) is ON
    if matches(Movement.Config.BhopToggleKey) then
        Movement:ToggleBhopActive()
    end
end)

--// GUI
function Movement:Init(Gui)
    self.Gui = Gui

    Gui:SetTabRebuild("Movement", function(g)
        local scroll = g:CreateScrollContent()
        local originalContent = g.Content
        g.Content = scroll

        local y = g:CreateSection("Character Movement", 0)
        y = g:CreateToggle("Speed", Movement.Config.SpeedEnabled, function(state)
            Movement:SetSpeedEnabled(state)
        end, y)
        y = g:CreateSlider("Walk Speed", 16, 100, Movement.Config.WalkSpeed, function(val)
            Movement.Config.WalkSpeed = val
            if Movement.Config.SpeedEnabled and Movement.Config.SpeedActive then SetSpeed(val) end
        end, y)
        y = CreateKeybindCapture(g, y, "Speed", "SpeedToggleKey")

        y = g:CreateSection("Bunny Hop", y + 16)
        y = g:CreateToggle("Bhop", Movement.Config.BhopEnabled, function(state)
            Movement:SetBhopEnabled(state)
        end, y)
        y = g:CreateSlider("Bhop Speed", 16, 100, Movement.Config.BhopSpeed, function(val)
            Movement.Config.BhopSpeed = val
        end, y)
        y = CreateKeybindCapture(g, y, "Bhop", "BhopToggleKey")

        y = g:CreateSection("Flight", y + 16)
        y = g:CreateToggle("Fly", Movement.Config.FlyEnabled, function(state)
            Movement:SetFlyEnabled(state)
        end, y)
        y = g:CreateSlider("Fly Speed", 10, 200, Movement.Config.FlySpeed, function(val)
            Movement.Config.FlySpeed = val
        end, y)
        y = CreateKeybindCapture(g, y, "Fly", "FlyToggleKey")

        y = g:CreateSection("Camera", y + 16)
        y = g:CreateToggle("3rd Person", Movement.Config.ThirdPersonEnabled, function(state)
            Movement:SetThirdPersonEnabled(state)
        end, y)

        y = g:CreateSection("Movement", y + 16)
        y = g:CreateToggle("Noclip", Movement.Config.NoclipEnabled, function(state)
            Movement:SetNoclipEnabled(state)
        end, y)
        y = CreateKeybindCapture(g, y, "Noclip", "NoclipToggleKey")

        g.Content = originalContent
    end)

    return self
end

return Movement