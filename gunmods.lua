local GunMods = {}
GunMods.__index = GunMods

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

GunMods.Config = {
    NoRecoil = false,
    NoSpread = false,
    RapidFire = false,
    InfiniteAmmo = false,
    FastReload = false,
    AlwaysAuto = false,
    FireRate = 0.03,

    ChamsEnabled = false,
    ChamsMaterial = "ForceField",
    ChamsColor = Color3.fromRGB(19, 0, 255),
    ChamsRainbow = false,
    ChamsRainbowSpeed = 2,
    ChamsTransparency = 0,
    ChamsReflectance = 0,
    ChamArms = false,
    ArmsColor = Color3.fromRGB(19, 0, 255),
    ArmsTransparency = 0.5,
}

-- Gun mods state tracking
local ModStates = {
    NoRecoil = { Active = false, Modified = {} },
    NoSpread = { Active = false, Modified = {} },
    RapidFire = { Active = false, Modified = {} },
    FastReload = { Active = false, Modified = {} },
}

local ModsLoopRunning = false
local ModsLoopConnection = nil

local function AnyModActive()
    return GunMods.Config.NoRecoil or GunMods.Config.NoSpread 
        or GunMods.Config.RapidFire or GunMods.Config.FastReload
end

local function SnapshotValue(obj, modName)
    local state = ModStates[modName]
    if not state then return end
    if not state.Modified[obj] then
        state.Modified[obj] = obj.Value
    end
end

local function RestoreMod(modName)
    local state = ModStates[modName]
    if not state then return end
    for obj, originalValue in pairs(state.Modified) do
        if obj and obj.Parent then
            obj.Value = originalValue
        end
    end
    state.Modified = {}
    state.Active = false
end

local function ApplySingleMod(modName)
    local state = ModStates[modName]
    if not state or not state.Active then return end
    local weapons = ReplicatedStorage:FindFirstChild("Weapons")
    if not weapons then return end
    for _, weapon in ipairs(weapons:GetDescendants()) do
        if weapon:IsA("ValueBase") then
            local wname = weapon.Name
            if modName == "NoRecoil" and wname == "RecoilControl" then
                SnapshotValue(weapon, modName)
                weapon.Value = 0
            elseif modName == "NoSpread" then
                if wname == "Spread" or wname == "BSpread" then
                    SnapshotValue(weapon, modName)
                    weapon.Value = 0
                elseif wname == "Accuracy" or wname == "BAccuracy" then
                    SnapshotValue(weapon, modName)
                    weapon.Value = 100
                end
            elseif modName == "RapidFire" then
                if wname == "FireRate" or wname == "BFireRate" then
                    SnapshotValue(weapon, modName)
                    weapon.Value = GunMods.Config.FireRate
                elseif wname == "Auto" then
                    SnapshotValue(weapon, modName)
                    weapon.Value = true
                end
            elseif modName == "FastReload" then
                if wname == "ReloadTime" or wname == "Reload" or wname == "TacticalReload" then
                    SnapshotValue(weapon, modName)
                    weapon.Value = 0.01
                end
            end
        end
    end
end

local function StartModsLoop()
    if ModsLoopRunning then return end
    ModsLoopRunning = true
    ModsLoopConnection = task.spawn(function()
        while AnyModActive() do
            if GunMods.Config.NoRecoil then ApplySingleMod("NoRecoil") end
            if GunMods.Config.NoSpread then ApplySingleMod("NoSpread") end
            if GunMods.Config.RapidFire then ApplySingleMod("RapidFire") end
            if GunMods.Config.FastReload then ApplySingleMod("FastReload") end
            task.wait(2)
        end
        ModsLoopRunning = false
        ModsLoopConnection = nil
    end)
end

local function StopModsLoopIfIdle()
    if not AnyModActive() and ModsLoopConnection then
        -- Loop self-terminates
    end
end

--// ALWAYS AUTO
local originalAutoValues = {}

local function SetAlwaysAuto(enabled)
    GunMods.Config.AlwaysAuto = enabled
    for _, weapon in ipairs(ReplicatedStorage.Weapons:GetChildren()) do
        if weapon:FindFirstChild("Auto") then
            if enabled then
                if not originalAutoValues[weapon] then
                    originalAutoValues[weapon] = weapon.Auto.Value
                end
                weapon.Auto.Value = true
            else
                if originalAutoValues[weapon] then
                    weapon.Auto.Value = originalAutoValues[weapon]
                end
            end
        end
    end
end

--// Infinite Ammo
local function ApplyInfiniteAmmo()
    local weapons = ReplicatedStorage:FindFirstChild("Weapons")
    if not weapons then return end
    for _, w in ipairs(weapons:GetChildren()) do
        if w:FindFirstChild("FireRate") then
            if GunMods.Config.InfiniteAmmo then
                if w:FindFirstChild("Infinite") == nil then
                    pcall(function()
                        local f = Instance.new("Folder")
                        f.Name = "Infinite"
                        f.Parent = w
                    end)
                end
            else
                local inf = w:FindFirstChild("Infinite")
                if inf then
                    pcall(function() inf:Destroy() end)
                end
            end
        end
    end
end

--// Tool equip detection
local CurrentTool = nil

local function OnToolEquipped(tool)
    CurrentTool = tool
    task.wait(0.1)
    if GunMods.Config.NoRecoil then ApplySingleMod("NoRecoil") end
    if GunMods.Config.NoSpread then ApplySingleMod("NoSpread") end
    if GunMods.Config.RapidFire then ApplySingleMod("RapidFire") end
    if GunMods.Config.FastReload then ApplySingleMod("FastReload") end
    if GunMods.Config.InfiniteAmmo then
        pcall(function()
            if tool:FindFirstChild("Infinite") == nil then
                local f = Instance.new("Folder")
                f.Name = "Infinite"
                f.Parent = tool
            end
        end)
    end
end

local function SetupCharacter(char)
    if not char then return end
    local existing = char:FindFirstChildOfClass("Tool")
    if existing then task.spawn(OnToolEquipped, existing) end
    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then OnToolEquipped(child) end
    end)
    char.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") and child == CurrentTool then
            CurrentTool = nil
        end
    end)
end

--// ═══════════════════════════════════════════════════════════════
--//  VIEWMODEL CHAMS — Arsenal Specific
--//  Stores originals so both guns AND arms restore on toggle-off.
--// ═══════════════════════════════════════════════════════════════

local Viewmodel = {
    ChamConnection = nil,
    RainbowHue = 0,
    GunMarkerName = "ENI_GunChams",
    ArmMarkerName = "ENI_ArmChams",
    OriginalGunData = {},
    OriginalArmData = {},
}

local MaterialsList = {
    "ForceField", "Neon", "Glass", "Ice", "Metal",
    "Plastic", "SmoothPlastic"
}

local function GetMaterial()
    return Enum.Material[GunMods.Config.ChamsMaterial] or Enum.Material.ForceField
end

local function CleanupOriginalData()
    for part, _ in pairs(Viewmodel.OriginalGunData) do
        if not part or not part.Parent then Viewmodel.OriginalGunData[part] = nil end
    end
    for part, _ in pairs(Viewmodel.OriginalArmData) do
        if not part or not part.Parent then Viewmodel.OriginalArmData[part] = nil end
    end
end

--// Snapshot gun parts before modifying
local function SnapshotGunPart(part)
    if not part or Viewmodel.OriginalGunData[part] then return end
    if part:IsA("BasePart") then
        Viewmodel.OriginalGunData[part] = {
            Color = part.Color,
            Transparency = part.Transparency,
            Material = part.Material,
            Reflectance = part.Reflectance,
        }
    elseif part:IsA("MeshPart") then
        Viewmodel.OriginalGunData[part] = {
            Color = part.Color,
            Transparency = part.Transparency,
            Material = part.Material,
            Reflectance = part.Reflectance,
            TextureID = part.TextureID,
        }
    elseif part:IsA("SpecialMesh") then
        Viewmodel.OriginalGunData[part] = {
            TextureId = part.TextureId,
        }
    end
end

--// Snapshot arm parts before modifying
local function SnapshotArmPart(part)
    if not part or Viewmodel.OriginalArmData[part] then return end
    if part:IsA("BasePart") then
        Viewmodel.OriginalArmData[part] = {
            Color = part.Color,
            Transparency = part.Transparency,
            Material = part.Material,
        }
    elseif part:IsA("SpecialMesh") then
        Viewmodel.OriginalArmData[part] = {
            TextureId = part.TextureId,
        }
    elseif part:IsA("Decal") or part:IsA("Texture") then
        Viewmodel.OriginalArmData[part] = {
            Transparency = part.Transparency,
        }
    end
end

--// Apply gun chams
local function ApplyGunChams()
    local arms = Camera:FindFirstChild("Arms")
    if not arms then return end
    if arms:FindFirstChild(Viewmodel.GunMarkerName) then return end

    local marker = Instance.new("Folder")
    marker.Name = Viewmodel.GunMarkerName
    marker.Parent = arms

    local mat = GetMaterial()
    local col = GunMods.Config.ChamsColor
    local refl = GunMods.Config.ChamsReflectance
    local trans = GunMods.Config.ChamsTransparency

    for _, child in ipairs(arms:GetChildren()) do
        if child.Name ~= "CSSArms" then
            if child:IsA("BasePart") and child.Transparency ~= 1 then
                SnapshotGunPart(child)
                child.Color = col
                child.Reflectance = refl
                child.Transparency = trans
                child.Material = mat
            end
        end
        if child:IsA("MeshPart") then
            SnapshotGunPart(child)
            child.TextureID = ""
        end

        for _, desc in ipairs(child:GetDescendants()) do
            if desc:IsA("BasePart") then
                SnapshotGunPart(desc)
                desc.Color = col
                desc.Reflectance = refl
                desc.Transparency = trans
                desc.Material = mat
            end
            if desc:IsA("MeshPart") then
                SnapshotGunPart(desc)
                desc.TextureID = ""
            end
            if desc:IsA("SpecialMesh") then
                SnapshotGunPart(desc)
                desc.TextureId = ""
            end
        end
    end
end

--// Apply arm chams
local function ApplyArmChams()
    local arms = Camera:FindFirstChild("Arms")
    if not arms then return end
    local cssArms = arms:FindFirstChild("CSSArms")
    if not cssArms then return end
    if cssArms:FindFirstChild(Viewmodel.ArmMarkerName) then return end

    CleanupOriginalData()

    local marker = Instance.new("Folder")
    marker.Name = Viewmodel.ArmMarkerName
    marker.Parent = cssArms

    local col = GunMods.Config.ArmsColor
    local trans = GunMods.Config.ArmsTransparency

    for _, desc in ipairs(cssArms:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Transparency ~= 1 then
            SnapshotArmPart(desc)
            desc.Color = col
            desc.Transparency = trans
        elseif desc:IsA("SpecialMesh") then
            SnapshotArmPart(desc)
            desc.TextureId = ""
        elseif desc:IsA("Decal") or desc:IsA("Texture") then
            SnapshotArmPart(desc)
            desc.Transparency = 1
        end
    end
end

--// Restore gun parts
local function RestoreGunChams()
    local arms = Camera:FindFirstChild("Arms")
    if not arms then return end

    for part, data in pairs(Viewmodel.OriginalGunData) do
        if part and part.Parent then
            if part:IsA("BasePart") or part:IsA("MeshPart") then
                if data.Color then part.Color = data.Color end
                if data.Transparency ~= nil then part.Transparency = data.Transparency end
                if data.Material then part.Material = data.Material end
                if data.Reflectance ~= nil then part.Reflectance = data.Reflectance end
            end
            if part:IsA("MeshPart") and data.TextureID ~= nil then
                part.TextureID = data.TextureID
            end
            if part:IsA("SpecialMesh") and data.TextureId ~= nil then
                part.TextureId = data.TextureId
            end
        end
    end
    Viewmodel.OriginalGunData = {}
end

--// Restore arm parts
local function RestoreArmChams()
    local arms = Camera:FindFirstChild("Arms")
    if not arms then return end
    local cssArms = arms:FindFirstChild("CSSArms")
    if not cssArms then return end

    for part, data in pairs(Viewmodel.OriginalArmData) do
        if part and part.Parent then
            if part:IsA("BasePart") then
                if data.Color then part.Color = data.Color end
                if data.Transparency ~= nil then part.Transparency = data.Transparency end
                if data.Material then part.Material = data.Material end
            elseif part:IsA("SpecialMesh") then
                if data.TextureId ~= nil then part.TextureId = data.TextureId end
            elseif part:IsA("Decal") or part:IsA("Texture") then
                if data.Transparency ~= nil then part.Transparency = data.Transparency end
            end
        end
    end
    Viewmodel.OriginalArmData = {}
end

--// Marker management
local function ClearGunMarker()
    local arms = Camera:FindFirstChild("Arms")
    if arms then
        local gunMarker = arms:FindFirstChild(Viewmodel.GunMarkerName)
        if gunMarker then gunMarker:Destroy() end
    end
end

local function ClearArmMarker()
    local arms = Camera:FindFirstChild("Arms")
    if not arms then return end
    local cssArms = arms:FindFirstChild("CSSArms")
    if not cssArms then return end
    local armMarker = cssArms:FindFirstChild(Viewmodel.ArmMarkerName)
    if armMarker then armMarker:Destroy() end
end

local function ClearAllMarkers()
    ClearGunMarker()
    ClearArmMarker()
end

--// Main chams loop
local function StartChamsLoop()
    if Viewmodel.ChamConnection then return end

    Viewmodel.ChamConnection = RunService.RenderStepped:Connect(function(dt)
        if not GunMods.Config.ChamsEnabled and not GunMods.Config.ChamArms then
            return
        end

        if GunMods.Config.ChamsEnabled then
            ApplyGunChams()
        end

        if GunMods.Config.ChamArms then
            ApplyArmChams()
        end

        if GunMods.Config.ChamsRainbow and GunMods.Config.ChamsEnabled then
            Viewmodel.RainbowHue = (Viewmodel.RainbowHue + dt * GunMods.Config.ChamsRainbowSpeed) % 1
            GunMods.Config.ChamsColor = Color3.fromHSV(Viewmodel.RainbowHue, 1, 1)
            GunMods.Config.ArmsColor = GunMods.Config.ChamsColor
            ClearAllMarkers()
        end
    end)
end

local function StopChamsLoop()
    if Viewmodel.ChamConnection then
        Viewmodel.ChamConnection:Disconnect()
        Viewmodel.ChamConnection = nil
    end
    ClearAllMarkers()
    RestoreGunChams()
    RestoreArmChams()
    Viewmodel.RainbowHue = 0
end

--// GUI
function GunMods:Init(Gui)
    self.Gui = Gui

    Gui:SetTabRebuild("Weapon", function(g)
        local scroll = g:CreateScrollContent()
        local originalContent = g.Content
        g.Content = scroll

        local y = g:CreateSection("Weapon Modifications", 0)

        y = g:CreateToggle("No Recoil", false, function(state)
            GunMods.Config.NoRecoil = state
            if state then
                ModStates.NoRecoil.Active = true
                ApplySingleMod("NoRecoil")
                StartModsLoop()
            else
                RestoreMod("NoRecoil")
                StopModsLoopIfIdle()
            end
        end, y)

        y = g:CreateToggle("No Spread", false, function(state)
            GunMods.Config.NoSpread = state
            if state then
                ModStates.NoSpread.Active = true
                ApplySingleMod("NoSpread")
                StartModsLoop()
            else
                RestoreMod("NoSpread")
                StopModsLoopIfIdle()
            end
        end, y)

        y = g:CreateToggle("Rapid Fire", false, function(state)
            GunMods.Config.RapidFire = state
            if state then
                ModStates.RapidFire.Active = true
                ApplySingleMod("RapidFire")
                StartModsLoop()
            else
                RestoreMod("RapidFire")
                StopModsLoopIfIdle()
            end
        end, y)

        y = g:CreateToggle("Infinite Ammo", false, function(state)
            GunMods.Config.InfiniteAmmo = state
            ApplyInfiniteAmmo()
        end, y)

        y = g:CreateToggle("Fast Reload", false, function(state)
            GunMods.Config.FastReload = state
            if state then
                ModStates.FastReload.Active = true
                ApplySingleMod("FastReload")
                StartModsLoop()
            else
                RestoreMod("FastReload")
                StopModsLoopIfIdle()
            end
        end, y)

        y = g:CreateToggle("Always Auto", false, function(state)
            SetAlwaysAuto(state)
        end, y)

        y = g:CreateSlider("Fire Rate", 1, 200, math.floor(GunMods.Config.FireRate * 1000), function(val)
            GunMods.Config.FireRate = val / 1000
            if GunMods.Config.RapidFire then
                RestoreMod("RapidFire")
                ModStates.RapidFire.Active = true
                ApplySingleMod("RapidFire")
            end
        end, y)

        -- Viewmodel Chams
        y = g:CreateSection("Viewmodel Chams", y + 10)

        y = g:CreateToggle("Enabled", false, function(state)
            GunMods.Config.ChamsEnabled = state
            if state then
                StartChamsLoop()
            else
                ClearGunMarker()
                RestoreGunChams()
                if not GunMods.Config.ChamArms then
                    StopChamsLoop()
                end
            end
        end, y)

        y = g:CreateToggle("Rainbow Mode", false, function(state)
            GunMods.Config.ChamsRainbow = state
            if not state then
                GunMods.Config.ChamsColor = Color3.fromRGB(19, 0, 255)
                GunMods.Config.ArmsColor = Color3.fromRGB(19, 0, 255)
                ClearAllMarkers()
            end
        end, y)

        y = g:CreateToggle("Cham Arms", false, function(state)
            GunMods.Config.ChamArms = state
            if state then
                StartChamsLoop()
            else
                ClearArmMarker()
                RestoreArmChams()
                if not GunMods.Config.ChamsEnabled then
                    StopChamsLoop()
                end
            end
        end, y)

        y = g:CreateSlider("Rainbow Speed", 1, 10, GunMods.Config.ChamsRainbowSpeed, function(val)
            GunMods.Config.ChamsRainbowSpeed = val
        end, y)

        y = g:CreateSlider("Transparency", 0, 100, math.floor(GunMods.Config.ChamsTransparency * 100), function(val)
            GunMods.Config.ChamsTransparency = val / 100
            ClearAllMarkers()
        end, y)

        y = g:CreateSlider("Reflectance", 0, 100, math.floor(GunMods.Config.ChamsReflectance * 100), function(val)
            GunMods.Config.ChamsReflectance = val / 100
            ClearAllMarkers()
        end, y)

        y = g:CreateDropdown("Material", MaterialsList, GunMods.Config.ChamsMaterial, function(val)
            GunMods.Config.ChamsMaterial = val
            ClearAllMarkers()
        end, y)

        y = g:CreateSection("Cham Colors", y + 10)

        local ColorPresets = {
            {Name = "Red", Color = Color3.fromRGB(255, 0, 0)},
            {Name = "Blue", Color = Color3.fromRGB(0, 100, 255)},
            {Name = "Green", Color = Color3.fromRGB(0, 255, 0)},
            {Name = "Purple", Color = Color3.fromRGB(150, 0, 255)},
            {Name = "Pink", Color = Color3.fromRGB(255, 100, 200)},
            {Name = "Orange", Color = Color3.fromRGB(255, 150, 0)},
            {Name = "Yellow", Color = Color3.fromRGB(255, 255, 0)},
            {Name = "Cyan", Color = Color3.fromRGB(0, 255, 255)},
            {Name = "White", Color = Color3.fromRGB(255, 255, 255)},
            {Name = "Black", Color = Color3.fromRGB(20, 20, 20)},
        }

        for _, preset in ipairs(ColorPresets) do
            y = g:CreateButton(preset.Name, function()
                GunMods.Config.ChamsColor = preset.Color
                GunMods.Config.ArmsColor = preset.Color
                GunMods.Config.ChamsRainbow = false
                ClearAllMarkers()
            end, y)
        end

        g.Content = originalContent
    end)

    if LocalPlayer.Character then SetupCharacter(LocalPlayer.Character) end

    LocalPlayer.CharacterAdded:Connect(function(char)
        CurrentTool = nil
        task.wait(0.5)
        SetupCharacter(char)
        if GunMods.Config.NoRecoil then ModStates.NoRecoil.Active = true ApplySingleMod("NoRecoil") end
        if GunMods.Config.NoSpread then ModStates.NoSpread.Active = true ApplySingleMod("NoSpread") end
        if GunMods.Config.RapidFire then ModStates.RapidFire.Active = true ApplySingleMod("RapidFire") end
        if GunMods.Config.FastReload then ModStates.FastReload.Active = true ApplySingleMod("FastReload") end
        if GunMods.Config.InfiniteAmmo then ApplyInfiniteAmmo() end
        if GunMods.Config.ChamsEnabled or GunMods.Config.ChamArms then
            task.wait(1)
            StartChamsLoop()
        end
    end)

    
    return self
end

return GunMods