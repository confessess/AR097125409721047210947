local Combat = {}
Combat.__index = Combat

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

Combat.Config = {
    AimbotEnabled = false,
    AimbotToggleMode = false,
    AimbotToggleKey = Enum.KeyCode.X,
    AimbotActive = false,
    SilentAimEnabled = false,
    SilentAimFOV = 150,
    SilentAimHitPart = "Head",
    SilentAimPrediction = false,
    HitboxEnabled = false,
    TeamCheck = true,
    WallCheck = false,
    FOV = 25,
    HitPart = "Head",
    HitboxSize = 13,
    HeadHBSize = 20,
    AimKey = Enum.UserInputType.MouseButton2,
    KillAll = false,
    HitsoundsEnabled = false,
    Hitsound = "Skeet.cc",
    HitsoundVolume = 1,
    BodyHitEnabled = false,
    BodyHitChance = 30,
}

local FOV_Circle = Drawing.new("Circle")
FOV_Circle.Color = Color3.fromRGB(255, 255, 255)
FOV_Circle.Thickness = 1
FOV_Circle.Filled = false
FOV_Circle.NumSides = 100
FOV_Circle.Transparency = 1
FOV_Circle.Radius = 25
FOV_Circle.Visible = false

local SilentFOV_Circle = Drawing.new("Circle")
SilentFOV_Circle.Color = Color3.fromRGB(255, 60, 60)
SilentFOV_Circle.Thickness = 1
SilentFOV_Circle.Filled = false
SilentFOV_Circle.NumSides = 100
SilentFOV_Circle.Transparency = 0.5
SilentFOV_Circle.Radius = 150
SilentFOV_Circle.Visible = false

local function IsVisible(targetPart)
    if not Combat.Config.WallCheck then return true end
    if not targetPart then return false end
    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, targetPart.Parent}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.IgnoreWater = true
    local result = Workspace:Raycast(origin, direction, raycastParams)
    if result == nil then return true end
    if result.Instance and result.Instance:IsDescendantOf(targetPart.Parent) then
        return true
    end
    return false
end

local IsAiming = false

local function IsValidTarget(plr)
    if plr == LocalPlayer then return false end
    if not plr.Character then return false end
    local char = plr.Character
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    local spawned = char:FindFirstChild("Spawned")
    if spawned and not spawned.Value then return false end
    local status = char:FindFirstChild("Status")
    if status then
        local alive = status:FindFirstChild("Alive")
        if alive and not alive.Value then return false end
    end
    local wkspc = ReplicatedStorage:FindFirstChild("wkspc")
    local ffa = wkspc and wkspc:FindFirstChild("FFA")
    local isFFA = ffa and ffa.Value
    if Combat.Config.TeamCheck and not isFFA then
        if plr.Team == LocalPlayer.Team then return false end
    end
    return true
end

local function GetClosestEnemy()
    local closestDist = Combat.Config.FOV
    local closestTarget = nil
    local mousePos = UserInputService:GetMouseLocation()
    for _, plr in ipairs(Players:GetPlayers()) do
        if not IsValidTarget(plr) then continue end
        local char = plr.Character
        local targetPart = char:FindFirstChild(Combat.Config.HitPart)
        if not targetPart then targetPart = char:FindFirstChild("Head") end
        if not targetPart then continue end
        if not IsVisible(targetPart) then continue end
        local pos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then continue end
        local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
        if dist < closestDist then
            closestDist = dist
            closestTarget = plr
        end
    end
    return closestTarget
end

--// ═══════════════════════════════════════════════════════════════
--//  SILENT AIM — Original Z3US method (strict signature)
--// ═══════════════════════════════════════════════════════════════
local SilentAimRunning = false

local function StartSilentAim()
    if SilentAimRunning then return end
    SilentAimRunning = true

    print("[ENI] Starting silent aim with FULL DEBUG...")

    -- Use Combat.Config directly
    local config = {
        Enabled = Combat.Config.SilentAimEnabled or false,
        TeamCheck = Combat.Config.TeamCheck ~= false,
        FOV = Combat.Config.SilentAimFOV or 150,
        HitPart = Combat.Config.SilentAimHitPart or "Head",
        Prediction = Combat.Config.SilentAimPrediction == true,
        BodyHitEnabled = Combat.Config.BodyHitEnabled == true,
        BodyHitChance = Combat.Config.BodyHitChance or 0,
    }

    -- Update config every frame from Combat.Config
    local function UpdateConfig()
        config.Enabled = Combat.Config.SilentAimEnabled or false
        config.TeamCheck = Combat.Config.TeamCheck ~= false
        config.FOV = Combat.Config.SilentAimFOV or 150
        config.HitPart = Combat.Config.SilentAimHitPart or "Head"
        config.Prediction = Combat.Config.SilentAimPrediction == true
        config.BodyHitEnabled = Combat.Config.BodyHitEnabled == true
        config.BodyHitChance = Combat.Config.BodyHitChance or 0
    end

    -- Helper functions with DEBUG
    local function IsValidTarget(plr)
        if plr == LocalPlayer then 
            return false 
        end
        if not plr.Character then 
            print("[ENI DEBUG] " .. plr.Name .. " has no character")
            return false 
        end
        local char = plr.Character
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid then 
            print("[ENI DEBUG] " .. plr.Name .. " has no humanoid")
            return false 
        end
        if humanoid.Health <= 0 then 
            print("[ENI DEBUG] " .. plr.Name .. " is dead")
            return false 
        end

        -- Team check
        if config.TeamCheck ~= false then
            local wkspc = ReplicatedStorage:FindFirstChild("wkspc")
            local ffa = wkspc and wkspc:FindFirstChild("FFA")
            if not (ffa and ffa.Value) then
                if plr.Team == LocalPlayer.Team then 
                    print("[ENI DEBUG] " .. plr.Name .. " is teammate")
                    return false 
                end
            end
        end

        print("[ENI DEBUG] " .. plr.Name .. " is VALID target")
        return true
    end

    local function GetClosestPlayer()
        local closestDistance = math.huge
        local closest = nil
        local viewportCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        local fov = config.FOV or 150
        local hitPartName = config.HitPart or "Head"

        print("[ENI SCAN] Starting scan... FOV: " .. fov .. " | HitPart: " .. hitPartName)

        for _, v in pairs(Players:GetPlayers()) do
            print("[ENI SCAN] Checking player: " .. v.Name)
            if not IsValidTarget(v) then continue end

            local char = v.Character
            local targetPart = char:FindFirstChild(hitPartName)
            if not targetPart then 
                print("[ENI SCAN] " .. v.Name .. " has no " .. hitPartName)
                targetPart = char:FindFirstChild("Head") 
            end
            if not targetPart then 
                print("[ENI SCAN] " .. v.Name .. " has no Head either")
                continue 
            end

            print("[ENI SCAN] Found part: " .. targetPart.Name)

            -- Skip LOS check for now (too strict)
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            if not onScreen then 
                print("[ENI SCAN] " .. targetPart.Name .. " not on screen")
                continue 
            end

            local dist = (Vector2.new(screenPos.X, screenPos.Y) - viewportCenter).Magnitude
            print("[ENI SCAN] Distance: " .. dist .. " | FOV: " .. fov)

            if dist < closestDistance and dist < fov then
                closestDistance = dist
                closest = targetPart
                print("[ENI SCAN] New closest: " .. targetPart.Name .. " at " .. dist)
            end
        end

        print("[ENI SCAN] Result: " .. tostring(closest))

        return closest
    end

    -- Update target every frame with HEAVY debug
    local target = nil
    local frameCount = 0
    local hasPrintedInitial = false

    RunService.RenderStepped:Connect(function()
        frameCount = frameCount + 1

        -- Update config from main Config every frame
        UpdateConfig()

        -- Print first frame to show it's working
        if not hasPrintedInitial then
            print("[ENI FRAME] RenderStepped connected! Frame: " .. frameCount)
            print("[ENI FRAME] Config.Enabled: " .. tostring(config.Enabled))
            hasPrintedInitial = true
        end

        if config.Enabled == false then
            if frameCount % 60 == 0 then
                print("[ENI FRAME] Silent aim DISABLED (frame " .. frameCount .. ") | Config.Enabled: " .. tostring(config.Enabled))
            end
            target = nil
            return
        end

        -- Scan every 60 frames (1 second)
        if frameCount % 60 == 0 then
            print("[ENI FRAME] ========================================")
            print("[ENI FRAME] Scanning for targets... (frame " .. frameCount .. ")")
            print("[ENI FRAME] Config.Enabled: " .. tostring(config.Enabled))
            print("[ENI FRAME] Config.FOV: " .. tostring(config.FOV))
            print("[ENI FRAME] Config.HitPart: " .. tostring(config.HitPart))
            target = GetClosestPlayer()
            print("[ENI FRAME] Target result: " .. tostring(target))
            print("[ENI FRAME] ========================================")
        end
    end)

    -- Hook getCollisionPoint to redirect bullets
    local getCollisionPointFunc = nil
    for _, v in pairs(getgc()) do
        if type(v) == "function" and islclosure(v) then
            local name = debug.info(v, "n")
            if name == "getCollisionPoint" then
                getCollisionPointFunc = v
                break
            end
        end
    end

    if getCollisionPointFunc then
        print("[ENI] Found getCollisionPoint, hooking...")

        local old
        old = hookfunction(getCollisionPointFunc, function(arg1, arg2, ...)
            -- Debug when called with target
            if target and config.Enabled ~= false then
                print("[ENI HOOK] getCollisionPoint called with target!")
                print("[ENI HOOK] Target: " .. tostring(target))
                print("[ENI HOOK] Arg1: " .. typeof(arg1))
                print("[ENI HOOK] Arg2: " .. typeof(arg2))
            end

            -- If we have a target, return target hit instead
            if target and target.Position and config.Enabled ~= false then
                print("[ENI HOOK] Redirecting to target!")
                return target, target.Position
            end

            return old(arg1, arg2, ...)
        end)

        print("[ENI] getCollisionPoint hooked successfully!")
    else
        warn("[ENI] getCollisionPoint not found!")
    end

    print("[ENI] Silent aim initialization complete - WAITING FOR TARGET...")
end

local function StopSilentAim()
    SilentAimRunning = false
    getgenv().__SilentAimConfig = getgenv().__SilentAimConfig or {}
    getgenv().__SilentAimConfig.Enabled = false
end

--// Input handlers
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Combat.Config.AimKey then
        IsAiming = true
    end
    if Combat.Config.AimbotToggleMode then
        local key = Combat.Config.AimbotToggleKey
        if typeof(key) == "EnumItem" then
            if key.EnumType == Enum.KeyCode and input.KeyCode == key then
                Combat.Config.AimbotActive = not Combat.Config.AimbotActive
            elseif key.EnumType == Enum.UserInputType and input.UserInputType == key then
                Combat.Config.AimbotActive = not Combat.Config.AimbotActive
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Combat.Config.AimKey then
        IsAiming = false
    end
end)

--// Main render loop
RunService.RenderStepped:Connect(function()
    local mousePos = UserInputService:GetMouseLocation()
    FOV_Circle.Position = Vector2.new(mousePos.X, mousePos.Y)
    FOV_Circle.Radius = Combat.Config.FOV
    FOV_Circle.Visible = Combat.Config.AimbotEnabled
    SilentFOV_Circle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    SilentFOV_Circle.Radius = Combat.Config.SilentAimFOV
    SilentFOV_Circle.Visible = Combat.Config.SilentAimEnabled

    getgenv().__SilentAimConfig = {
        Enabled = Combat.Config.SilentAimEnabled,
        FOV = Combat.Config.SilentAimFOV,
        TeamCheck = Combat.Config.TeamCheck,
        BodyHitEnabled = Combat.Config.BodyHitEnabled,
        BodyHitChance = Combat.Config.BodyHitChance,
        HitPart = Combat.Config.SilentAimHitPart,
        Prediction = Combat.Config.SilentAimPrediction,
    }

    local shouldAim = false
    if Combat.Config.AimbotEnabled then
        if Combat.Config.AimbotToggleMode then
            shouldAim = Combat.Config.AimbotActive
        else
            shouldAim = IsAiming
        end
    end

    if shouldAim then
        local target = GetClosestEnemy()
        if target and target.Character then
            local targetPart = target.Character:FindFirstChild(Combat.Config.HitPart)
            if not targetPart then targetPart = target.Character:FindFirstChild("Head") end
            if targetPart then
                Camera.CFrame = CFrame.new(Camera.CFrame.Position, targetPart.Position)
            end
        end
    end

end)

--// Hitbox Expander
local OriginalData = {}

local function ExpandHitboxes()
    if not Combat.Config.HitboxEnabled then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if Combat.Config.TeamCheck and plr.Team == LocalPlayer.Team then continue end
        local char = plr.Character
        if not char then continue end
        local partsToExpand = {"RightUpperLeg", "LeftUpperLeg", "HeadHB", "HumanoidRootPart"}
        for _, partName in ipairs(partsToExpand) do
            local part = char:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                if not OriginalData[part] then
                    OriginalData[part] = {Size = part.Size, Transparency = part.Transparency}
                end
                local targetSize = (partName == "HeadHB") and
                    Vector3.new(Combat.Config.HeadHBSize, Combat.Config.HeadHBSize, Combat.Config.HeadHBSize) or
                    Vector3.new(Combat.Config.HitboxSize, Combat.Config.HitboxSize, Combat.Config.HitboxSize)
                part.Size = targetSize
                part.Transparency = 1
            end
        end
    end
end

local function RestoreHitboxes()
    for part, data in pairs(OriginalData) do
        if part and part.Parent then
            part.Size = data.Size
            part.Transparency = data.Transparency
        end
    end
    OriginalData = {}
end

RunService.RenderStepped:Connect(function()
    if Combat.Config.HitboxEnabled then
        ExpandHitboxes()
    else
        RestoreHitboxes()
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    if plr.Character then
        for _, part in ipairs(plr.Character:GetDescendants()) do
            if OriginalData[part] then OriginalData[part] = nil end
        end
    end
end)

--// HITSOUNDS
local HitsoundList = {
    ["None"] = "", ["Skeet.cc"] = "rbxassetid://5447626464", ["Neverlose"] = "rbxassetid://6607204501",
    ["Baimware"] = "rbxassetid://6607339542", ["Old Fatality"] = "rbxassetid://6607142036",
    ["Rust"] = "rbxassetid://5043539486", ["Bell"] = "rbxassetid://6534947240",
    ["TF2"] = "rbxassetid://2868331684", ["Among Us"] = "rbxassetid://5700183626",
    ["Fortnite Headshot"] = "rbxassetid://2513174484", ["Minecraft"] = "rbxassetid://4018616850",
    ["Osu"] = "rbxassetid://7149255551", ["TF2 Critical"] = "rbxassetid://296102734",
    ["Bat"] = "rbxassetid://3333907347", ["Call of Duty"] = "rbxassetid://5952120301",
    ["Bruh"] = "rbxassetid://4275842574", ["Crowbar"] = "rbxassetid://546410481",
    ["Weeb"] = "rbxassetid://6442965016", ["Steve"] = "rbxassetid://4965083997"
}

local function PlayHitsound()
    if not Combat.Config.HitsoundsEnabled then return end
    local soundId = HitsoundList[Combat.Config.Hitsound]
    if not soundId or soundId == "" then return end
    local sound = Instance.new("Sound")
    sound.SoundId = soundId
    sound.Volume = Combat.Config.HitsoundVolume
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Connect(function() sound:Destroy() end)
end

local function SetupHitsounds()
    local scoreFolder = LocalPlayer:WaitForChild("ScoreFolder")
    local damageValue = scoreFolder:WaitForChild("Damage")
    damageValue:GetPropertyChangedSignal("Value"):Connect(function(newValue)
        if newValue == 0 then return end
        PlayHitsound()
    end)
    LocalPlayer.ChildRemoved:Connect(function(child)
        if child.Name == "ScoreFolder" then
            task.wait(3)
            pcall(SetupHitsounds)
        end
    end)
end

task.spawn(function()
    local success = pcall(SetupHitsounds)
    if not success then
        task.wait(5)
        pcall(SetupHitsounds)
    end
end)

--// KILL ALL
local killAllConnection = nil
local killAllActive = false

local function GetClosestEnemyForKillAll()
    local closest = nil
    local closestDist = math.huge
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Team ~= LocalPlayer.Team then
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if root and humanoid and humanoid.Health > 0 then
                local dist = (root.Position - myRoot.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = player
                end
            end
        end
    end
    return closest
end

local function KillAllTick()
    if not killAllActive then return end
    local target = GetClosestEnemyForKillAll()
    if target and target.Character then
        local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if targetRoot and myRoot then
            myRoot.CFrame = CFrame.new(targetRoot.Position - targetRoot.CFrame.LookVector * 5)
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, targetRoot.Position)
        end
    end
end

local function SetKillAll(enabled)
    killAllActive = enabled
    Combat.Config.KillAll = enabled
    if enabled then
        if killAllConnection then killAllConnection:Disconnect() end
        killAllConnection = RunService.Heartbeat:Connect(KillAllTick)
    else
        if killAllConnection then
            killAllConnection:Disconnect()
            killAllConnection = nil
        end
    end
end

--// GUI KEYBIND CAPTURE
local DARK_PANEL = Color3.fromRGB(14, 14, 14)
local BORDER = Color3.fromRGB(65, 25, 27)
local RED = Color3.fromRGB(145, 20, 25)
local RED_BRIGHT = Color3.fromRGB(195, 28, 35)
local WHITE = Color3.fromRGB(255, 255, 255)
local LIGHT = Color3.fromRGB(225, 225, 225)
local GRAY = Color3.fromRGB(150, 150, 150)
local HOVER = Color3.fromRGB(18, 7, 8)
local SELECTED = Color3.fromRGB(45, 15, 17)

local WaitingForAimKey = false
local AimKeyButton = nil

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

local function UpdateAimKeyButtonText()
    if not AimKeyButton then return end
    AimKeyButton.Text = "Bind: " .. GetKeyDisplayName(Combat.Config.AimbotToggleKey)
end

local function CreateKeybindCapture(g, y)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 36)
    Frame.Position = UDim2.fromOffset(0, y)
    Frame.BackgroundTransparency = 1
    Frame.ZIndex = 3
    Frame.Parent = g.Content

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -140, 0, 36)
    Label.BackgroundTransparency = 1
    Label.Text = "Aimbot Toggle Key"
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
    Btn.Text = "Bind: X"
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

    AimKeyButton = Btn
    UpdateAimKeyButtonText()

    Btn.MouseEnter:Connect(function()
        if not WaitingForAimKey then
            Btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
            Stroke.Color = RED
        end
    end)
    Btn.MouseLeave:Connect(function()
        if not WaitingForAimKey then
            Btn.BackgroundColor3 = DARK_PANEL
            Stroke.Color = BORDER
        end
    end)

    Btn.MouseButton1Click:Connect(function()
        if WaitingForAimKey then return end
        WaitingForAimKey = true
        Btn.Text = "Press a key..."
        Btn.TextColor3 = RED_BRIGHT
        Btn.BackgroundColor3 = SELECTED
        Stroke.Color = RED_BRIGHT
    end)

    return y + 42
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not WaitingForAimKey then return end
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
        Combat.Config.AimbotToggleKey = captured
        WaitingForAimKey = false
        UpdateAimKeyButtonText()
        if AimKeyButton then
            AimKeyButton.TextColor3 = WHITE
            AimKeyButton.BackgroundColor3 = DARK_PANEL
            local stroke = AimKeyButton:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = BORDER end
        end
    end
end)

function Combat:Init(Gui)
    self.Gui = Gui
    Gui:SetTabRebuild("Combat", function(g)
        local scroll = g:CreateScrollContent()
        local originalContent = g.Content
        g.Content = scroll

        local y = g:CreateSection("Aimbot", 0)
        y = g:CreateToggle("Aimbot", Combat.Config.AimbotEnabled, function(state)
            Combat.Config.AimbotEnabled = state
        end, y)
        y = g:CreateToggle("Toggle Mode", false, function(state)
            Combat.Config.AimbotToggleMode = state
        end, y)
        y = CreateKeybindCapture(g, y)
        y = g:CreateToggle("Team Check", Combat.Config.TeamCheck, function(state)
            Combat.Config.TeamCheck = state
        end, y)
        y = g:CreateToggle("Wall Check", Combat.Config.WallCheck, function(state)
            Combat.Config.WallCheck = state
        end, y)
        y = g:CreateSlider("FOV Radius", 10, 200, Combat.Config.FOV, function(val)
            Combat.Config.FOV = val
        end, y)

        y = g:CreateSection("Silent Aim", y + 10)
        y = g:CreateToggle("Silent Aim", Combat.Config.SilentAimEnabled, function(state)
            Combat.Config.SilentAimEnabled = state
            if state then
                StartSilentAim()
            else
                StopSilentAim()
            end
        end, y)
        y = g:CreateSlider("Silent Aim FOV", 50, 500, Combat.Config.SilentAimFOV, function(val)
            Combat.Config.SilentAimFOV = val
        end, y)
        y = g:CreateDropdown("Hit Part", {"Head", "HumanoidRootPart"}, Combat.Config.SilentAimHitPart, function(val)
            Combat.Config.SilentAimHitPart = val
        end, y)
        y = g:CreateToggle("Prediction", Combat.Config.SilentAimPrediction, function(state)
            Combat.Config.SilentAimPrediction = state
        end, y)
        y = g:CreateToggle("Body Hit Redirection", Combat.Config.BodyHitEnabled, function(state)
            Combat.Config.BodyHitEnabled = state
        end, y)
        y = g:CreateSlider("Body Hit Chance %", 0, 100, Combat.Config.BodyHitChance, function(val)
            Combat.Config.BodyHitChance = val
        end, y)

        y = g:CreateSection("Hitbox Expander", y + 10)
        y = g:CreateToggle("Hitbox Expander", Combat.Config.HitboxEnabled, function(state)
            Combat.Config.HitboxEnabled = state
            if not state then RestoreHitboxes() end
        end, y)
        y = g:CreateSlider("Body Hitbox Size", 5, 25, Combat.Config.HitboxSize, function(val)
            Combat.Config.HitboxSize = val
        end, y)
        y = g:CreateSlider("HeadHB Size", 10, 30, Combat.Config.HeadHBSize, function(val)
            Combat.Config.HeadHBSize = val
        end, y)

        y = g:CreateSection("Kill All", y + 10)
        y = g:CreateToggle("Kill All", false, function(state)
            SetKillAll(state)
        end, y)

        y = g:CreateSection("Hitsounds", y + 10)
        y = g:CreateToggle("Enabled", false, function(state)
            Combat.Config.HitsoundsEnabled = state
        end, y)
        local hitsoundNames = {"None", "Skeet.cc", "Neverlose", "Baimware", "Old Fatality", "Rust", "Bell", "TF2", "Among Us", "Fortnite Headshot", "Minecraft", "Osu", "TF2 Critical", "Bat", "Call of Duty", "Bruh", "Crowbar", "Weeb", "Steve"}
        y = g:CreateDropdown("Sound", hitsoundNames, "Skeet.cc", function(val)
            Combat.Config.Hitsound = val
        end, y)
        y = g:CreateSlider("Volume", 0, 10, 1, function(val)
            Combat.Config.HitsoundVolume = val
        end, y)

        g.Content = originalContent
    end)
    return self
end

return Combat