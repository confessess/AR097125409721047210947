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

local ENV = (getgenv and getgenv()) or _G

--// Re-execution guard: kill loops from any previous run, restore their parts
local RUN_ID = tick()
ENV.__MM2HubRun = RUN_ID
if ENV.__MM2HubCleanup then
	pcall(ENV.__MM2HubCleanup)
	ENV.__MM2HubCleanup = nil
end

Combat.Config = {
    AimbotEnabled = false,
    AimbotToggleMode = false,
    AimbotToggleKey = Enum.KeyCode.X,
    AimbotActive = false,
    AimbotFOVVisible = true,
    SilentAimEnabled = false,
    SilentAimFOV = 150,
    SilentAimFOVVisible = true,
    SilentAimWallCheck = true,
    SilentAimMode = "Head", -- "Head" | "Body" | "Random"
    SilentAimPrediction = false,
    HitboxEnabled = false,
    HitboxPartMode = "Body",
    TeamCheck = true,
    WallCheck = false,
    FOV = 25,
    HitPart = "HeadHB",
    HitboxSize = 13,
    HeadHBSize = 20,
    AimKey = Enum.UserInputType.MouseButton2,
    KillAll = false,
    HitsoundsEnabled = false,
    Hitsound = "Skeet.cc",
    HitsoundVolume = 1,
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

local function UpdateFOVCircle()
    if not FOV_Circle or not SilentFOV_Circle then return end

    local mousePos = UserInputService:GetMouseLocation()
    FOV_Circle.Position = Vector2.new(mousePos.X, mousePos.Y)
    FOV_Circle.Radius = Combat.Config.FOV
    FOV_Circle.Visible = Combat.Config.AimbotEnabled and (Combat.Config.AimbotFOVVisible ~= false)

    if Camera and Camera.ViewportSize then
        SilentFOV_Circle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    end
    SilentFOV_Circle.Radius = Combat.Config.SilentAimFOV
    SilentFOV_Circle.Visible = Combat.Config.SilentAimEnabled and (Combat.Config.SilentAimFOVVisible ~= false)
end

local function IsVisible(targetPart, override)
    local enabled
    if override ~= nil then
        enabled = override
    else
        enabled = Combat.Config.WallCheck
    end
    if not enabled then return true end
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
local GetProjectedHitboxRadius
local CurrentSilentTargetPlr = nil
local CurrentSilentTargetPart = nil

--// Silent aim mode resolver ("Head" / "Body" / "Random")
local randomChoice = "Head"
local randomNext = 0
local function ResolveSilentAimMode()
    local mode = Combat.Config.SilentAimMode
    if mode ~= "Random" then return mode end
    local now = tick()
    if now >= randomNext then
        randomChoice = (math.random() < 0.5) and "Head" or "Body"
        randomNext = now + math.random(20, 60) / 100 -- 0.2s - 0.6s
    end
    return randomChoice
end

local function GetSilentAimPart(char, mode)
    if not char then return nil end
    if mode == "Body" then
        for _, name in ipairs({"UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart"}) do
            local p = char:FindFirstChild(name)
            if p and p:IsA("BasePart") then return p end
        end
        return nil
    end
    local head = char:FindFirstChild("HeadHB") or char:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head end
    return nil
end

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
        local targetPart = GetSilentAimPart(char, "Head")
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

--// ============================================================
--// SILENT AIM (hook-based) — replaces the old fake silent aim
--// ============================================================
ENV.__SilentAimConfig = ENV.__SilentAimConfig or {}
local SilentAimConfig = ENV.__SilentAimConfig
SilentAimConfig.Enabled = false
SilentAimConfig.TargetPlayer = nil
SilentAimConfig.TargetPart = nil
SilentAimConfig.Prediction = false

local function InstallSilentAimHook()
    if ENV.__MM2SilentAimInstalled then return end
    ENV.__MM2SilentAimInstalled = true

    for _, v in pairs(getgc()) do
        if type(v) == "function" and islclosure(v) then

            local success, isMatch = pcall(function()
                local infoName = debug.info(v, "n")
                local nameLen = type(infoName) == "string" and #infoName or 0
                return debug.info(v, "a") == 2
                    and #debug.getupvalues(v) == 2
                    and #debug.getconstants(v) == 17
                    and nameLen <= 10
            end)

            if success and isMatch then
                local old
                old = hookfunction(v, function(...)
                    local args = table.pack(...)
                    local p1 = args[1]

                    local cfg = ENV.__SilentAimConfig
                    local target = cfg and cfg.TargetPart

                    if cfg and cfg.Enabled and target and target.Parent then
                        local myChar = LocalPlayer.Character
                        local myHead = myChar and myChar:FindFirstChild("Head")

                        if myHead then
                            local aimPos = target.Position
                            if cfg.Prediction then
                                aimPos = aimPos + target.AssemblyLinearVelocity * 0.15
                            end

                            local direction = (aimPos - myHead.Position)

                            if typeof(p1) == "Ray" then
                                args[1] = Ray.new(myHead.Position, direction)
                            elseif typeof(p1) == "CFrame" then
                                args[1] = CFrame.new(myHead.Position, aimPos)
                            end
                        end
                    end

                    return old(table.unpack(args, 1, args.n))
                end)
            end
        end
    end
end

InstallSilentAimHook()

local function GetSilentAimTarget()
    local mode = ResolveSilentAimMode()
    local closestDistance = math.huge
    local closestPlr, closestPart = nil, nil
    local center = Camera.ViewportSize / 2

    for _, v in pairs(Players:GetPlayers()) do
        if not IsValidTarget(v) then continue end

        local char = v.Character
        if not char then continue end

        local part = GetSilentAimPart(char, mode)
        if not part then continue end

        if Combat.Config.SilentAimWallCheck and not IsVisible(part, true) then continue end

        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if onScreen then
            local distance = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
            if distance <= Combat.Config.SilentAimFOV and distance < closestDistance then
                closestDistance = distance
                closestPlr = v
                closestPart = part
            end
        end
    end
    return closestPlr, closestPart
end

--// Dynamic hitbox expansion (silent aim driven)
local SilentAimOriginalData = {}
local SilentAimExpandedNow = {}

local function SilentAimRestorePart(part)
    local data = SilentAimOriginalData[part]
    if not data then return end
    if part and part.Parent then
        part.Size = data.Size
        part.Transparency = data.Transparency
        if data.LocalTransparencyModifier ~= nil then
            part.LocalTransparencyModifier = data.LocalTransparencyModifier
        end
        if data.CanCollide ~= nil then
            part.CanCollide = data.CanCollide
        end
        if data.Massless ~= nil then
            part.Massless = data.Massless
        end
    end
    SilentAimOriginalData[part] = nil
    SilentAimExpandedNow[part] = nil
end

local function SilentAimRestoreAll()
    for part, _ in pairs(SilentAimOriginalData) do
        SilentAimRestorePart(part)
    end
    SilentAimOriginalData = {}
    SilentAimExpandedNow = {}
end

local function GetSilentAimDynamicParts(char)
    if not char then return {} end
    if ResolveSilentAimMode() == "Head" then
        local head = char:FindFirstChild("HeadHB") or char:FindFirstChild("Head")
        return head and {head} or {}
    end
    return {
        char:FindFirstChild("RightUpperLeg"),
        char:FindFirstChild("LeftUpperLeg"),
        char:FindFirstChild("HumanoidRootPart"),
    }
end

local function ApplyDynamicSilentAimExpansion()
    if not Combat.Config.SilentAimEnabled then
        if next(SilentAimOriginalData) then
            SilentAimRestoreAll()
        end
        return
    end

    local plr = CurrentSilentTargetPlr
    local part = CurrentSilentTargetPart
    local desired = {}

    if plr and part and part.Parent and IsValidTarget(plr) then
        local centerPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        local screenPos, onScreen = Camera.WorldToViewportPoint(part.Position)
        if onScreen then
            local dist = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
            local radius = GetProjectedHitboxRadius(part)
            if dist <= Combat.Config.SilentAimFOV + radius then
                local proximity = 1 - math.clamp(dist / Combat.Config.SilentAimFOV, 0, 1)
                for _, p in ipairs(GetSilentAimDynamicParts(plr.Character)) do
                    if p and p:IsA("BasePart") then
                        desired[p] = proximity
                    end
                end
            end
        end
    end

    for p, _ in pairs(SilentAimExpandedNow) do
        if not desired[p] then
            SilentAimRestorePart(p)
        end
    end

    local mode = ResolveSilentAimMode()
    local maxSize = (mode == "Head")
        and Combat.Config.HeadHBSize
        or Combat.Config.HitboxSize

    for p, proximity in pairs(desired) do
        if not SilentAimOriginalData[p] then
            SilentAimOriginalData[p] = {
                Size = p.Size,
                Transparency = p.Transparency,
                LocalTransparencyModifier = p.LocalTransparencyModifier,
                CanCollide = p.CanCollide,
                Massless = p.Massless,
            }
        end
        local orig = SilentAimOriginalData[p].Size
        p.Size = Vector3.new(
            orig.X + (maxSize - orig.X) * proximity,
            orig.Y + (maxSize - orig.Y) * proximity,
            orig.Z + (maxSize - orig.Z) * proximity
        )
        p.Transparency = 1
        p.LocalTransparencyModifier = 1
        p.CanCollide = false
        p.Massless = true
        SilentAimExpandedNow[p] = true
    end
end

task.spawn(function()
    while true do
        if ENV.__MM2HubRun ~= RUN_ID then break end
        ApplyDynamicSilentAimExpansion()
        task.wait(0.1)
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    if plr.Character then
        for _, p in ipairs(plr.Character:GetDescendants()) do
            if SilentAimOriginalData[p] then
                SilentAimRestorePart(p)
            end
        end
    end
    if plr == CurrentSilentTargetPlr then
        CurrentSilentTargetPlr = nil
        CurrentSilentTargetPart = nil
    end
end)

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
    UpdateFOVCircle()

    --// Silent aim target update
    if Combat.Config.SilentAimEnabled then
        local plr, part = GetSilentAimTarget()
        SilentAimConfig.Enabled = true
        SilentAimConfig.TargetPlayer = plr
        SilentAimConfig.TargetPart = part
        SilentAimConfig.Prediction = Combat.Config.SilentAimPrediction
        CurrentSilentTargetPlr = plr
        CurrentSilentTargetPart = part
    else
        if SilentAimConfig.Enabled then
            SilentAimConfig.Enabled = false
            SilentAimConfig.TargetPlayer = nil
            SilentAimConfig.TargetPart = nil
        end
        CurrentSilentTargetPlr = nil
        CurrentSilentTargetPart = nil
    end

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

local function RestoreHitboxes()
    for part, data in pairs(OriginalData) do
        if part and part.Parent then
            part.Size = data.Size
            part.Transparency = data.Transparency
            if data.LocalTransparencyModifier ~= nil then
                part.LocalTransparencyModifier = data.LocalTransparencyModifier
            end
            if data.CanCollide ~= nil then
                part.CanCollide = data.CanCollide
            end
            if data.Massless ~= nil then
                part.Massless = data.Massless
            end
        end
    end
    OriginalData = {}
end

GetProjectedHitboxRadius = function(part)
    if not part or not part:IsA("BasePart") then return 0 end

    local size = part.Size
    local radiusWorld = math.max(size.X, size.Y, size.Z) * 0.5
    local cameraPos = Camera.CFrame.Position
    local distance = (part.Position - cameraPos).Magnitude
    if distance <= 0.0001 then return 0 end

    local fovRadians = math.rad(Camera.FieldOfView)
    local worldHeight = 2 * math.tan(fovRadians / 2) * distance
    local viewportScale = Camera.ViewportSize.Y / worldHeight
    return radiusWorld * viewportScale
end

local function NormalizeHitboxPartMode(value)
    local mode = tostring(value or "Body")
    if mode:lower() == "headhb" then
        return "HeadHB"
    end
    return "Body"
end

local function GetExpanderParts(char)
    if not char then return {} end

    local mode = NormalizeHitboxPartMode(Combat.Config.HitboxPartMode)
    if mode == "HeadHB" then
        local headHitbox = char:FindFirstChild("HeadHB") or char:FindFirstChild("Head")
        local parts = {
            char:FindFirstChild("RightUpperLeg"),
            char:FindFirstChild("LeftUpperLeg"),
            char:FindFirstChild("HumanoidRootPart"),
        }
        if headHitbox then
            table.insert(parts, headHitbox)
        end
        return parts
    end

    return {
        char:FindFirstChild("RightUpperLeg"),
        char:FindFirstChild("LeftUpperLeg"),
        char:FindFirstChild("HumanoidRootPart"),
    }
end

local function ApplySimpleHitboxExpander()
    if not Combat.Config.HitboxEnabled then
        RestoreHitboxes()
        return
    end

    local desiredParts = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and IsValidTarget(plr) and plr.Character then
            for _, part in ipairs(GetExpanderParts(plr.Character)) do
                if part and part:IsA("BasePart") then
                    desiredParts[part] = true
                end
            end
        end
    end

    for part, data in pairs(OriginalData) do
        if not desiredParts[part] then
            if part and part.Parent then
                part.Size = data.Size
                part.Transparency = data.Transparency
                if data.LocalTransparencyModifier ~= nil then
                    part.LocalTransparencyModifier = data.LocalTransparencyModifier
                end
                part.CanCollide = data.CanCollide
            end
            OriginalData[part] = nil
        end
    end

    local mode = NormalizeHitboxPartMode(Combat.Config.HitboxPartMode)
    local headSize = Combat.Config.HeadHBSize
    local bodySize = mode == "HeadHB"
        and math.max(1, Combat.Config.HeadHBSize - 1)
        or Combat.Config.HitboxSize

    for part in pairs(desiredParts) do
        if not OriginalData[part] then
            OriginalData[part] = {
                Size = part.Size,
                Transparency = part.Transparency,
                LocalTransparencyModifier = part.LocalTransparencyModifier,
                CanCollide = part.CanCollide,
                Massless = part.Massless,
            }
        end

        if mode == "HeadHB" then
            local isHead = part.Name == "HeadHB" or part.Name == "Head"
            local size = isHead and headSize or bodySize
            local expandedSize = Vector3.new(size, size, size)
            part.CanCollide = false
            if isHead then
                part.Massless = true
            elseif OriginalData[part].Massless ~= nil then
                part.Massless = OriginalData[part].Massless
            end
            part.Transparency = 1
            part.LocalTransparencyModifier = 1
            if part.Size ~= expandedSize then
                part.Size = expandedSize
            end
        else
            local expandedSize = Vector3.new(bodySize, bodySize, bodySize)
            part.CanCollide = false
            if OriginalData[part].Massless ~= nil then
                part.Massless = OriginalData[part].Massless
            end
            part.Transparency = 1
            part.LocalTransparencyModifier = 1
            if part.Size ~= expandedSize then
                part.Size = expandedSize
            end
        end
    end
end

task.spawn(function()
    while true do
        if ENV.__MM2HubRun ~= RUN_ID then break end
        if Combat.Config.HitboxEnabled then
            ApplySimpleHitboxExpander()
        else
            RestoreHitboxes()
        end
        task.wait(1)
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
        if player ~= LocalPlayer and player.Parent == Players and player.Team ~= LocalPlayer.Team then
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if root and humanoid and humanoid.Health > 0 and char:IsDescendantOf(workspace) and not char:FindFirstChildOfClass("ForceField") then
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
            UpdateFOVCircle()
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
            UpdateFOVCircle()
        end, y)
        y = g:CreateToggle("Show Aimbot FOV", Combat.Config.AimbotFOVVisible, function(state)
            Combat.Config.AimbotFOVVisible = state
            UpdateFOVCircle()
        end, y)

        y = g:CreateSection("Silent Aim", y + 10)
        y = g:CreateToggle("Silent Aim", Combat.Config.SilentAimEnabled, function(state)
            Combat.Config.SilentAimEnabled = state
            if not state then
                SilentAimConfig.Enabled = false
                SilentAimConfig.TargetPlayer = nil
                SilentAimConfig.TargetPart = nil
                CurrentSilentTargetPlr = nil
                CurrentSilentTargetPart = nil
            end
            UpdateFOVCircle()
        end, y)
        y = g:CreateToggle("Silent Aim Wall Check", Combat.Config.SilentAimWallCheck, function(state)
            Combat.Config.SilentAimWallCheck = state
        end, y)
        y = g:CreateSlider("Silent Aim FOV", 50, 500, Combat.Config.SilentAimFOV, function(val)
            Combat.Config.SilentAimFOV = val
            UpdateFOVCircle()
        end, y)
        y = g:CreateDropdown("Hit Part", {"Head", "Body", "Random"}, Combat.Config.SilentAimMode, function(val)
            Combat.Config.SilentAimMode = val
        end, y)
        y = g:CreateToggle("Prediction", Combat.Config.SilentAimPrediction, function(state)
            Combat.Config.SilentAimPrediction = state
        end, y)
        y = g:CreateToggle("Show Silent FOV", Combat.Config.SilentAimFOVVisible, function(state)
            Combat.Config.SilentAimFOVVisible = state
            UpdateFOVCircle()
        end, y)

        y = g:CreateSection("Hitbox Expander", y + 10)
        y = g:CreateToggle("Hitbox Expander", Combat.Config.HitboxEnabled, function(state)
            Combat.Config.HitboxEnabled = state
            if not state then RestoreHitboxes() end
        end, y)
        y = g:CreateDropdown("Expand Part", {"Body", "HeadHB"}, Combat.Config.HitboxPartMode, function(val)
            Combat.Config.HitboxPartMode = val
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
        y = g:CreateToggle("Enabled", Combat.Config.HitsoundsEnabled, function(state)
            Combat.Config.HitsoundsEnabled = state
        end, y)
        local hitsoundNames = {"None", "Skeet.cc", "Neverlose", "Baimware", "Old Fatality", "Rust", "Bell", "TF2", "Among Us", "Fortnite Headshot", "Minecraft", "Osu", "TF2 Critical", "Bat", "Call of Duty", "Bruh", "Crowbar", "Weeb", "Steve"}
        y = g:CreateDropdown("Sound", hitsoundNames, Combat.Config.Hitsound, function(val)
            Combat.Config.Hitsound = val
        end, y)
        y = g:CreateSlider("Volume", 0, 10, Combat.Config.HitsoundVolume, function(val)
            Combat.Config.HitsoundVolume = val
        end, y)

        g.Content = originalContent
    end)
    return self
end

--// Cleanup for next re-execution: restore every part we touched
ENV.__MM2HubCleanup = function()
    for part, data in pairs(OriginalData) do
        if part and part.Parent then
            part.Size = data.Size
            part.Transparency = data.Transparency
            if data.LocalTransparencyModifier ~= nil then part.LocalTransparencyModifier = data.LocalTransparencyModifier end
            if data.CanCollide ~= nil then part.CanCollide = data.CanCollide end
            if data.Massless ~= nil then part.Massless = data.Massless end
        end
    end
    for part, data in pairs(SilentAimOriginalData) do
        if part and part.Parent then
            part.Size = data.Size
            part.Transparency = data.Transparency
            if data.LocalTransparencyModifier ~= nil then part.LocalTransparencyModifier = data.LocalTransparencyModifier end
            if data.CanCollide ~= nil then part.CanCollide = data.CanCollide end
            if data.Massless ~= nil then part.Massless = data.Massless end
        end
    end
    if killAllConnection then
        pcall(function() killAllConnection:Disconnect() end)
    end
    if ENV.__SilentAimConfig then
        ENV.__SilentAimConfig.Enabled = false
        ENV.__SilentAimConfig.TargetPart = nil
        ENV.__SilentAimConfig.TargetPlayer = nil
    end
end

return Combat
