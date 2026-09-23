-- ============================================================
-- Arsenal Modular -- Combat (FIXED for new bullet system)
-- Legit aimbot, silent aim, ragebot, triggerbot
-- ============================================================

local Combat = {}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config, Utils, GUI, Core

-- State
local aimbotTarget = nil
local silentAimTarget = nil
local ragebotConn = nil
local triggerbotLastClick = 0

-- FOV circles
local aimbotFOVCircle = nil
local silentAimFOVCircle = nil

-- Keybind
local aimbotKeybind = nil
local aimbotKeyDown = false

-- Silent Aim State
local SilentAimRunning = false
local RaycastFunction = nil
local OriginalRaycast = nil

-- Helper functions
local function isKeybindPressed()
    if not aimbotKeybind then return false end
    if typeof(aimbotKeybind) == "EnumItem" then
        if aimbotKeybind.EnumType == Enum.UserInputType then
            return UserInputService:IsMouseButtonPressed(aimbotKeybind)
        elseif aimbotKeybind.EnumType == Enum.KeyCode then
            return UserInputService:IsKeyDown(aimbotKeybind)
        end
    end
    return false
end

local function formatKeybind(kb)
    if not kb then return "None" end
    if typeof(kb) == "EnumItem" then
        local str = tostring(kb)
        return str:match("%.(%w+)$") or str
    end
    return tostring(kb)
end

-- ------------------------------------------------------------
-- Silent Aim - Find and Hook Raycast
-- ------------------------------------------------------------

local function FindRaycastFunction()
    for _, v in pairs(getgc()) do
        if type(v) == "function" and islclosure(v) then
            local name = debug.info(v, "n")
            local consts = debug.getconstants(v)

            -- Look for Raycast function with Arsenal's signature
            if name == "Raycast" 
                and #consts == 7 
                and consts[1] == "FindPartOnRayWithIgnoreList" then
                return v
            end
        end
    end
    return nil
end

local function GetSilentAimTarget()
    local mousePos = UserInputService:GetMouseLocation()
    local closest = nil
    local closestDist = Config.Get("SilentAim_FOVSize") or 250

    local teamCheck = Config.Get("SilentAim_TeamCheck") ~= false
    local hitPart = Config.Get("SilentAim_HitPart") or "Head"

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            -- Team check
            if teamCheck and player.Team == LocalPlayer.Team then
                continue
            end

            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            local targetPart = player.Character:FindFirstChild(hitPart)

            if humanoid and humanoid.Health > 0 and targetPart then
                local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist < closestDist then
                        closest = targetPart
                        closestDist = dist
                    end
                end
            end
        end
    end

    return closest
end

local function HookRaycast()
    if not RaycastFunction then
        warn("[Combat] Raycast function not found!")
        return false
    end

    OriginalRaycast = RaycastFunction

    local newRaycast = function(ray, ignoreList, ...)
        -- Call original
        local hitPart, hitPos, hitNormal, hitMaterial = OriginalRaycast(ray, ignoreList, ...)

        -- If silent aim is enabled, redirect hit
        if Config.Get("SilentAim_Enabled") then
            local target = GetSilentAimTarget()
            if target then
                local targetPos = target.Position
                local direction = (targetPos - ray.Origin).Unit
                return target, targetPos, direction, hitMaterial
            end
        end

        return hitPart, hitPos, hitNormal, hitMaterial
    end

    -- Hook the function
    if hookfunction then
        local success, err = pcall(function()
            hookfunction(RaycastFunction, newRaycast)
        end)
        if success then
            print("[Combat] Silent aim hooked successfully!")
            return true
        else
            warn("[Combat] Failed to hook: " .. tostring(err))
            return false
        end
    else
        warn("[Combat] hookfunction not available!")
        return false
    end
end

-- ------------------------------------------------------------
-- Target selection
-- ------------------------------------------------------------

local function isValidTarget(player)
    if not player or player == LocalPlayer then return false end
    if not player.Character then return false end
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    return true
end

local function getAimbotTarget()
    local crosshair = UserInputService:GetMouseLocation()
    if not LocalPlayer.Character then return nil end
    local localRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not localRoot then return nil end

    local fovSize = Config.Get("Aimbot_FOVSize") or 250
    local wallCheck = Config.Get("Aimbot_WallCheck") == true
    local teamCheck = Config.Get("Aimbot_TeamCheck") ~= false
    local aimPart = Config.Get("Aimbot_AimPart") or "Head"

    -- Sticky aim
    if Config.Get("Aimbot_StickyAim") and aimbotTarget then
        if isValidTarget(aimbotTarget) then
            if teamCheck and aimbotTarget.Team == LocalPlayer.Team then
                aimbotTarget = nil
            else
                local part = aimbotTarget.Character:FindFirstChild(aimPart)
                if part then
                    if wallCheck then
                        -- Simple LOS check
                        local ray = Ray.new(Camera.CFrame.Position, (part.Position - Camera.CFrame.Position).Unit * 1000)
                        local hit, pos = Workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character, aimbotTarget.Character})
                        if not hit or hit:IsDescendantOf(aimbotTarget.Character) then
                            return aimbotTarget
                        else
                            aimbotTarget = nil
                        end
                    else
                        return aimbotTarget
                    end
                else
                    aimbotTarget = nil
                end
            end
        else
            aimbotTarget = nil
        end
    end

    local best = nil
    local bestDist = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if teamCheck and player.Team == LocalPlayer.Team then continue end
        if not isValidTarget(player) then continue end

        local part = player.Character:FindFirstChild(aimPart)
        if not part then continue end

        if wallCheck then
            local ray = Ray.new(Camera.CFrame.Position, (part.Position - Camera.CFrame.Position).Unit * 1000)
            local hit, pos = Workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character, player.Character})
            if hit and not hit:IsDescendantOf(player.Character) then continue end
        end

        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then continue end

        local dist2d = (Vector2.new(screenPos.X, screenPos.Y) - crosshair).Magnitude
        if dist2d <= fovSize and dist2d < bestDist then
            best = player
            bestDist = dist2d
        end
    end

    aimbotTarget = best
    return best
end

-- ------------------------------------------------------------
-- Aim application
-- ------------------------------------------------------------

local function applyAim(target)
    if not target or not target.Character then return end
    local aimPart = Config.Get("Aimbot_AimPart") or "Head"
    local part = target.Character:FindFirstChild(aimPart)
    if not part then return end

    local useSmooth = Config.Get("Aimbot_Smoothness") == true
    local smoothValue = Config.Get("Aimbot_SmoothValue") or 5

    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
    if not onScreen then return end

    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local delta = Vector2.new(screenPos.X, screenPos.Y) - center

    if useSmooth and smoothValue > 0 then
        delta = delta / (smoothValue + 1)
    end

    pcall(function()
        mousemoverel(delta.X, delta.Y)
    end)
end

-- ------------------------------------------------------------
-- Update loops
-- ------------------------------------------------------------

local function updateAimbot()
    if not Config.Get("Aimbot_Enabled") then
        if aimbotFOVCircle then aimbotFOVCircle.Visible = false end
        return
    end

    -- Show FOV circle
    if Config.Get("Aimbot_ShowFOV") then
        if not aimbotFOVCircle then
            aimbotFOVCircle = Drawing.new("Circle")
            aimbotFOVCircle.Thickness = 1
            aimbotFOVCircle.Color = Color3.fromRGB(124, 108, 255)
            aimbotFOVCircle.Transparency = 0.5
            aimbotFOVCircle.Filled = false
            aimbotFOVCircle.NumSides = 64
        end
        local mousePos = UserInputService:GetMouseLocation()
        aimbotFOVCircle.Position = mousePos
        aimbotFOVCircle.Radius = Config.Get("Aimbot_FOVSize") or 250
        aimbotFOVCircle.Visible = true
    elseif aimbotFOVCircle then
        aimbotFOVCircle.Visible = false
    end

    if not isKeybindPressed() then
        if not Config.Get("Aimbot_StickyAim") then
            aimbotTarget = nil
        end
        return
    end

    local target = getAimbotTarget()
    if target then
        applyAim(target)
    end
end

local function updateSilentAim()
    if not Config.Get("SilentAim_Enabled") then
        if silentAimFOVCircle then silentAimFOVCircle.Visible = false end
        return
    end

    -- Show FOV circle
    if Config.Get("SilentAim_UseFOV") then
        if not silentAimFOVCircle then
            silentAimFOVCircle = Drawing.new("Circle")
            silentAimFOVCircle.Thickness = 1
            silentAimFOVCircle.Color = Color3.fromRGB(255, 0, 0)
            silentAimFOVCircle.Transparency = 0.5
            silentAimFOVCircle.Filled = false
            silentAimFOVCircle.NumSides = 64
        end
        local mousePos = UserInputService:GetMouseLocation()
        silentAimFOVCircle.Position = mousePos
        silentAimFOVCircle.Radius = Config.Get("SilentAim_FOVSize") or 250
        silentAimFOVCircle.Visible = true
    elseif silentAimFOVCircle then
        silentAimFOVCircle.Visible = false
    end
end

local function updateRagebot()
    if not Config.Get("Ragebot_Enabled") then
        if ragebotConn then
            ragebotConn:Disconnect()
            ragebotConn = nil
        end
        return
    end

    if not ragebotConn then
        ragebotConn = RunService.RenderStepped:Connect(function()
            if not Config.Get("Ragebot_Enabled") then return end
            if not LocalPlayer.Character then return end

            -- Find closest target
            local closest = nil
            local closestDist = math.huge
            local localRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

            if not localRoot then return end

            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character and player.Team ~= LocalPlayer.Team then
                    local root = player.Character:FindFirstChild("HumanoidRootPart")
                    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                    if root and humanoid and humanoid.Health > 0 then
                        local dist = (root.Position - localRoot.Position).Magnitude
                        if dist < closestDist then
                            closest = player
                            closestDist = dist
                        end
                    end
                end
            end

            if closest then
                local head = closest.Character:FindFirstChild("Head")
                if head then
                    -- Check LOS
                    local ray = Ray.new(Camera.CFrame.Position, (head.Position - Camera.CFrame.Position).Unit * 1000)
                    local hit, pos = Workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character, closest.Character})
                    if not hit or hit:IsDescendantOf(closest.Character) then
                        pcall(function()
                            mouse1click()
                        end)
                    end
                end
            end
        end)
    end
end

local function updateTriggerbot()
    if not Config.Get("Triggerbot_Enabled") then return end

    local delay = Config.Get("Triggerbot_Delay") or 0
    local chance = Config.Get("Triggerbot_Chance") or 100
    local teamCheck = Config.Get("Triggerbot_TeamCheck") ~= false

    local now = tick()
    if delay > 0 and now - triggerbotLastClick < delay then return end

    local mouse = LocalPlayer:GetMouse()
    local target = mouse.Target
    if not target then return end

    local model = target:FindFirstAncestorWhichIsA("Model")
    if not model then return end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    if teamCheck then
        local player = Players:GetPlayerFromCharacter(model)
        if player and player.Team == LocalPlayer.Team then return end
    end

    if math.random(1, 100) > chance then return end

    pcall(function()
        mouse1click()
    end)
    triggerbotLastClick = now
end

-- ------------------------------------------------------------
-- Main Update
-- ------------------------------------------------------------

function Combat.Update()
    if Core.Unloaded then return end

    updateAimbot()
    updateSilentAim()
    updateRagebot()
    updateTriggerbot()
end

-- ------------------------------------------------------------
-- Initialize Silent Aim
-- ------------------------------------------------------------

local function InitSilentAim()
    print("[Combat] Initializing silent aim...")
    RaycastFunction = FindRaycastFunction()
    if RaycastFunction then
        print("[Combat] Found Raycast function")
        if HookRaycast() then
            SilentAimRunning = true
        end
    else
        warn("[Combat] Could not find Raycast function - silent aim disabled")
    end
end

-- ------------------------------------------------------------
-- Lifecycle
-- ------------------------------------------------------------

function Combat.Init(deps)
    Config = deps.Config
    Utils = deps.Utils
    GUI = deps.GUI
    Core = deps.Core

    -- Initialize silent aim
    task.spawn(function()
        task.wait(1) -- Wait for game to load
        InitSilentAim()
    end)

    -- Input handling
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if aimbotKeybind then
            if typeof(aimbotKeybind) == "EnumItem" then
                if aimbotKeybind.EnumType == Enum.UserInputType and input.UserInputType == aimbotKeybind then
                    aimbotKeyDown = true
                elseif aimbotKeybind.EnumType == Enum.KeyCode and input.KeyCode == aimbotKeybind then
                    aimbotKeyDown = true
                end
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if aimbotKeybind then
            if typeof(aimbotKeybind) == "EnumItem" then
                if aimbotKeybind.EnumType == Enum.UserInputType and input.UserInputType == aimbotKeybind then
                    aimbotKeyDown = false
                elseif aimbotKeybind.EnumType == Enum.KeyCode and input.KeyCode == aimbotKeybind then
                    aimbotKeyDown = false
                end
            end
        end
    end)

    -- Register GUI
    local page = GUI.GetPage and GUI.GetPage("Combat")
    if page then
        local C = GUI.Components

        -- AIMBOT MASTER SECTION
        local aimbotSection, setAimbotOpen = C.MasterSection(page, "Aimbot", 1, Config.Get("Aimbot_Enabled") or false)

        C.Toggle(aimbotSection, "Enabled", Config.Get("Aimbot_Enabled"), function(v) 
            Config.Set("Aimbot_Enabled", v) 
        end, 2)

        -- Hotkey
        local hotkeyFrame = Instance.new("Frame")
        hotkeyFrame.Size = UDim2.new(1, 0, 0, 32)
        hotkeyFrame.BackgroundTransparency = 1
        hotkeyFrame.LayoutOrder = 3
        hotkeyFrame.Parent = aimbotSection

        local hotkeyLbl = Instance.new("TextLabel")
        hotkeyLbl.Size = UDim2.new(0.4, 0, 1, 0)
        hotkeyLbl.BackgroundTransparency = 1
        hotkeyLbl.Text = "Hotkey"
        hotkeyLbl.TextColor3 = Color3.fromRGB(220, 220, 235)
        hotkeyLbl.Font = Enum.Font.GothamMedium
        hotkeyLbl.TextSize = 13
        hotkeyLbl.TextXAlignment = Enum.TextXAlignment.Left
        hotkeyLbl.Parent = hotkeyFrame

        local hotkeyBtn = Instance.new("TextButton")
        hotkeyBtn.Size = UDim2.new(0.35, -30, 0, 26)
        hotkeyBtn.Position = UDim2.new(0.45, 0, 0.5, -13)
        hotkeyBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
        hotkeyBtn.BorderSizePixel = 0
        hotkeyBtn.Text = formatKeybind(aimbotKeybind)
        hotkeyBtn.TextColor3 = Color3.fromRGB(80, 140, 255)
        hotkeyBtn.Font = Enum.Font.GothamBold
        hotkeyBtn.TextSize = 12
        hotkeyBtn.AutoButtonColor = false
        hotkeyBtn.Parent = hotkeyFrame

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = hotkeyBtn

        local clearBtn = Instance.new("TextButton")
        clearBtn.Size = UDim2.fromOffset(24, 24)
        clearBtn.Position = UDim2.new(1, -24, 0.5, -12)
        clearBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
        clearBtn.BorderSizePixel = 0
        clearBtn.Text = "×"
        clearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        clearBtn.Font = Enum.Font.GothamBold
        clearBtn.TextSize = 14
        clearBtn.AutoButtonColor = false
        clearBtn.Parent = hotkeyFrame

        local clearCorner = Instance.new("UICorner")
        clearCorner.CornerRadius = UDim.new(0, 4)
        clearCorner.Parent = clearBtn

        local listening = false
        hotkeyBtn.MouseButton1Click:Connect(function()
            if listening then return end
            listening = true
            hotkeyBtn.Text = "..."

            local conn
            conn = UserInputService.InputBegan:Connect(function(input, gp)
                if gp then return end
                if input.UserInputType == Enum.UserInputType.Keyboard then
                    aimbotKeybind = input.KeyCode
                    hotkeyBtn.Text = formatKeybind(input.KeyCode)
                    listening = false
                    conn:Disconnect()
                elseif input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.MouseButton2
                    or input.UserInputType == Enum.UserInputType.MouseButton3 then
                    aimbotKeybind = input.UserInputType
                    hotkeyBtn.Text = formatKeybind(input.UserInputType)
                    listening = false
                    conn:Disconnect()
                end
            end)
        end)

        clearBtn.MouseButton1Click:Connect(function()
            aimbotKeybind = nil
            hotkeyBtn.Text = "None"
            aimbotKeyDown = false
        end)

        C.Toggle(aimbotSection, "Wall Check", Config.Get("Aimbot_WallCheck"), function(v) Config.Set("Aimbot_WallCheck", v) end, 4)
        C.Toggle(aimbotSection, "Team Check", Config.Get("Aimbot_TeamCheck"), function(v) Config.Set("Aimbot_TeamCheck", v) end, 5)
        C.Toggle(aimbotSection, "Smoothness", Config.Get("Aimbot_Smoothness"), function(v) Config.Set("Aimbot_Smoothness", v) end, 6)
        C.Toggle(aimbotSection, "Sticky Aim", Config.Get("Aimbot_StickyAim"), function(v) Config.Set("Aimbot_StickyAim", v) end, 7)
        C.Dropdown(aimbotSection, "Aim Part", {"Head", "HumanoidRootPart", "Torso"}, Config.Get("Aimbot_AimPart"), function(v) Config.Set("Aimbot_AimPart", v) end, 8)
        C.Toggle(aimbotSection, "Show FOV", Config.Get("Aimbot_ShowFOV"), function(v) Config.Set("Aimbot_ShowFOV", v) end, 9)
        C.Slider(aimbotSection, "FOV Size", 0, 1000, Config.Get("Aimbot_FOVSize"), function(v) Config.Set("Aimbot_FOVSize", v) end, 10)
        C.Slider(aimbotSection, "Smooth Value", 0, 20, Config.Get("Aimbot_SmoothValue"), function(v) Config.Set("Aimbot_SmoothValue", v) end, 11)

        setAimbotOpen(Config.Get("Aimbot_Enabled") or false)

        -- SILENT AIM MASTER SECTION
        local silentSection, setSilentOpen = C.MasterSection(page, "Silent Aim", 20, Config.Get("SilentAim_Enabled") or false)

        C.Toggle(silentSection, "Enabled", Config.Get("SilentAim_Enabled"), function(v) Config.Set("SilentAim_Enabled", v) end, 21)
        C.Toggle(silentSection, "Team Check", Config.Get("SilentAim_TeamCheck"), function(v) Config.Set("SilentAim_TeamCheck", v) end, 22)
        C.Toggle(silentSection, "Use FOV", Config.Get("SilentAim_UseFOV"), function(v) Config.Set("SilentAim_UseFOV", v) end, 23)
        C.Slider(silentSection, "FOV Size", 50, 1000, Config.Get("SilentAim_FOVSize"), function(v) Config.Set("SilentAim_FOVSize", v) end, 24)
        C.Dropdown(silentSection, "Hit Part", {"Head", "HumanoidRootPart", "Torso"}, Config.Get("SilentAim_HitPart"), function(v) Config.Set("SilentAim_HitPart", v) end, 25)

        setSilentOpen(Config.Get("SilentAim_Enabled") or false)

        -- TRIGGERBOT MASTER SECTION
        local triggerSection, setTriggerOpen = C.MasterSection(page, "Triggerbot", 40, Config.Get("Triggerbot_Enabled") or false)

        C.Toggle(triggerSection, "Enabled", Config.Get("Triggerbot_Enabled"), function(v) Config.Set("Triggerbot_Enabled", v) end, 41)
        C.Toggle(triggerSection, "Team Check", Config.Get("Triggerbot_TeamCheck"), function(v) Config.Set("Triggerbot_TeamCheck", v) end, 42)
        C.Slider(triggerSection, "Chance %", 1, 100, Config.Get("Triggerbot_Chance"), function(v) Config.Set("Triggerbot_Chance", v) end, 43)
        C.Slider(triggerSection, "Delay", 0, 50, Config.Get("Triggerbot_Delay"), function(v) Config.Set("Triggerbot_Delay", v) end, 44)

        setTriggerOpen(Config.Get("Triggerbot_Enabled") or false)

        -- RAGEBOT MASTER SECTION
        local rageSection, setRageOpen = C.MasterSection(page, "Ragebot", 60, Config.Get("Ragebot_Enabled") or false)

        C.Toggle(rageSection, "Enabled", Config.Get("Ragebot_Enabled"), function(v) Config.Set("Ragebot_Enabled", v) end, 61)

        setRageOpen(Config.Get("Ragebot_Enabled") or false)
    end

    print("[Arsenal] Combat module initialized.")
end

function Combat.Cleanup()
    if aimbotFOVCircle then
        pcall(function() aimbotFOVCircle:Remove() end)
        aimbotFOVCircle = nil
    end
    if silentAimFOVCircle then
        pcall(function() silentAimFOVCircle:Remove() end)
        silentAimFOVCircle = nil
    end
    if ragebotConn then
        ragebotConn:Disconnect()
        ragebotConn = nil
    end
    aimbotTarget = nil
    silentAimTarget = nil
end

return Combat