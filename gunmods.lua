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

    MuzzleBlock = false,
    MuzzleHideMesh = false,
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
--//  MUZZLE FLASH BLOCK
--//  Flash lives at Workspace.HWRAP_<build>.Gun.Flash.P_ThirdPerson.Muzzle
--//  Wrapper name is build-specific so matching is structural.
--//  Emitters are neutralised three ways: Enabled off, Rate 0, Lifetime 0,0.
--//  Lifetime matters because :Emit() fires particles even while disabled.
--// ═══════════════════════════════════════════════════════════════

local MuzzleBlock = {
    Active = false,
    AddedConn = nil,
    Heartbeat = nil,
    Locked = {},
    Names = { Muzzle = true, MuzzleFlash = true, MuzzleFlash2 = true },
}

local function UnderFlashPart(inst)
    local p = inst.Parent
    local depth = 0
    while p and p ~= Workspace and depth < 6 do
        if p.Name == "Flash" or p.Name == "MuzzleFlash" then return true end
        p = p.Parent
        depth = depth + 1
    end
    return false
end

local function IsFlashEmitter(inst)
    return MuzzleBlock.Names[inst.Name] == true or UnderFlashPart(inst)
end

local function LockParticle(pe)
    if MuzzleBlock.Locked[pe] then return end
    local entry = {
        restore = { Enabled = pe.Enabled, Rate = pe.Rate, Lifetime = pe.Lifetime },
        conns = {},
    }
    MuzzleBlock.Locked[pe] = entry

    pe.Enabled = false
    pe.Rate = 0
    pe.Lifetime = NumberRange.new(0, 0)

    entry.conns[#entry.conns + 1] = pe:GetPropertyChangedSignal("Enabled"):Connect(function()
        if pe.Enabled then pe.Enabled = false end
    end)
    entry.conns[#entry.conns + 1] = pe:GetPropertyChangedSignal("Rate"):Connect(function()
        if pe.Rate ~= 0 then pe.Rate = 0 end
    end)
    entry.conns[#entry.conns + 1] = pe:GetPropertyChangedSignal("Lifetime"):Connect(function()
        if pe.Lifetime.Min ~= 0 or pe.Lifetime.Max ~= 0 then
            pe.Lifetime = NumberRange.new(0, 0)
        end
    end)
end

local function LockLight(light)
    if MuzzleBlock.Locked[light] then return end
    local entry = {
        restore = { Enabled = light.Enabled, Brightness = light.Brightness },
        conns = {},
    }
    MuzzleBlock.Locked[light] = entry

    light.Enabled = false
    light.Brightness = 0

    entry.conns[#entry.conns + 1] = light:GetPropertyChangedSignal("Enabled"):Connect(function()
        if light.Enabled then light.Enabled = false end
    end)
end

local function LockMesh(part)
    if MuzzleBlock.Locked[part] then return end
    MuzzleBlock.Locked[part] = {
        restore = {
            Transparency = part.Transparency,
            LocalTransparencyModifier = part.LocalTransparencyModifier,
        },
        conns = {},
    }
    part.LocalTransparencyModifier = 1
end

local function MuzzleProcess(inst)
    if not MuzzleBlock.Active then return end
    if inst:IsA("ParticleEmitter") then
        if IsFlashEmitter(inst) then LockParticle(inst) end
    elseif inst:IsA("PointLight") or inst:IsA("SpotLight") then
        if UnderFlashPart(inst) then LockLight(inst) end
    elseif GunMods.Config.MuzzleHideMesh and inst:IsA("BasePart") then
        if inst.Name == "Flash" or inst.Name == "MuzzleFlash" then LockMesh(inst) end
    end
end

local function MuzzleSweep()
    if not MuzzleBlock.Active then return end
    for _, inst in ipairs(Workspace:GetDescendants()) do
        MuzzleProcess(inst)
    end
end

local function MuzzleEnable()
    if MuzzleBlock.Active then return end
    MuzzleBlock.Active = true

    MuzzleSweep()
    MuzzleBlock.AddedConn = Workspace.DescendantAdded:Connect(MuzzleProcess)

    MuzzleBlock.Heartbeat = RunService.Heartbeat:Connect(function()
        if not MuzzleBlock.Active then return end
        for inst, entry in pairs(MuzzleBlock.Locked) do
            if not inst.Parent then
                for _, c in ipairs(entry.conns) do c:Disconnect() end
                MuzzleBlock.Locked[inst] = nil
            elseif inst:IsA("ParticleEmitter") then
                if inst.Enabled then inst.Enabled = false end
                if inst.Rate ~= 0 then inst.Rate = 0 end
            elseif inst:IsA("Light") then
                if inst.Enabled then inst.Enabled = false end
            elseif inst:IsA("BasePart") and GunMods.Config.MuzzleHideMesh then
                inst.LocalTransparencyModifier = 1
            end
        end
    end)
end

local function MuzzleDisable()
    if not MuzzleBlock.Active then return end
    MuzzleBlock.Active = false

    if MuzzleBlock.AddedConn then
        MuzzleBlock.AddedConn:Disconnect()
        MuzzleBlock.AddedConn = nil
    end
    if MuzzleBlock.Heartbeat then
        MuzzleBlock.Heartbeat:Disconnect()
        MuzzleBlock.Heartbeat = nil
    end

    for inst, entry in pairs(MuzzleBlock.Locked) do
        for _, c in ipairs(entry.conns) do pcall(c.Disconnect, c) end
        pcall(function()
            for prop, value in pairs(entry.restore) do inst[prop] = value end
        end)
    end
    MuzzleBlock.Locked = {}
end

--// ═══════════════════════════════════════════════════════════════
--//  VIEWMODEL CHAMS — Arsenal Specific
--//  Applies to the real viewmodel AND any clone, so the two systems
--//  don't mask each other. Generation counter replaces the marker gate
--//  because a clone inherits the marker and would skip itself forever.
--// ═══════════════════════════════════════════════════════════════

local Viewmodel = {
    ChamConnection = nil,
    RainbowHue = 0,
    GunMarkerName = "ENI_GunChams",
    ArmMarkerName = "ENI_ArmChams",
    OriginalGunData = {},
    OriginalArmData = {},
}

local ChamsGen = 0
local AppliedGen = setmetatable({}, { __mode = "k" })

local MaterialsList = {
    "ForceField", "Neon", "Glass", "Ice", "Metal",
    "Plastic", "SmoothPlastic"
}

local function GetMaterial()
    return Enum.Material[GunMods.Config.ChamsMaterial] or Enum.Material.ForceField
end

local function GetContainers()
    local list = {}
    local arms = Camera:FindFirstChild("Arms")
    if arms then table.insert(list, arms) end
    local clone = Camera:FindFirstChild("ENI_CustomVM")
    if clone then table.insert(list, clone) end
    return list
end

local function CleanupOriginalData()
    for part, _ in pairs(Viewmodel.OriginalGunData) do
        if not part or not part.Parent then Viewmodel.OriginalGunData[part] = nil end
    end
    for part, _ in pairs(Viewmodel.OriginalArmData) do
        if not part or not part.Parent then Viewmodel.OriginalArmData[part] = nil end
    end
end

--// Snapshot gun parts before modifying.
--// MeshPart is tested FIRST — it inherits BasePart, so a BasePart-first
--// check would lose TextureID and the gun would stay untextured forever.
local function SnapshotGunPart(part)
    if not part or Viewmodel.OriginalGunData[part] then return end
    if part:IsA("MeshPart") then
        Viewmodel.OriginalGunData[part] = {
            Transparency = part.Transparency,
            Color = part.Color,
            Material = part.Material,
            Reflectance = part.Reflectance,
            TextureID = part.TextureID,
        }
    elseif part:IsA("BasePart") then
        Viewmodel.OriginalGunData[part] = {
            Transparency = part.Transparency,
            Color = part.Color,
            Material = part.Material,
            Reflectance = part.Reflectance,
        }
    elseif part:IsA("SpecialMesh") then
        Viewmodel.OriginalGunData[part] = {
            TextureId = part.TextureId,
        }
    end
end

local function SnapshotArmPart(part)
    if not part or Viewmodel.OriginalArmData[part] then return end
    if part:IsA("BasePart") then
        Viewmodel.OriginalArmData[part] = {
            Transparency = part.Transparency,
            Color = part.Color,
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

local function ApplyGunChamsTo(container)
    if not container then return end
    if AppliedGen[container] == ChamsGen then return end
    AppliedGen[container] = ChamsGen

    local mat = GetMaterial()
    local col = GunMods.Config.ChamsColor
    local refl = GunMods.Config.ChamsReflectance
    local trans = GunMods.Config.ChamsTransparency

    local function handle(part)
        if not part then return end
        SnapshotGunPart(part)
        local data = Viewmodel.OriginalGunData[part]
        if not data then return end

        --// parts that were already invisible stay invisible
        if data.Transparency and data.Transparency >= 1 then return end

        if part:IsA("BasePart") then
            part.Color = col
            part.Reflectance = refl
            part.Transparency = trans
            part.Material = mat
        end
        if part:IsA("MeshPart") then
            part.TextureID = ""
        end
        if part:IsA("SpecialMesh") then
            part.TextureId = ""
        end
    end

    for _, child in ipairs(container:GetChildren()) do
        if child.Name ~= "CSSArms" and child.Name ~= Viewmodel.GunMarkerName then
            handle(child)
            for _, desc in ipairs(child:GetDescendants()) do
                handle(desc)
            end
        end
    end
end

local function ApplyArmChamsTo(container)
    if not container then return end
    local cssArms = container:FindFirstChild("CSSArms")
    if not cssArms then return end
    if AppliedGen[cssArms] == ChamsGen then return end
    AppliedGen[cssArms] = ChamsGen

    local col = GunMods.Config.ArmsColor
    local trans = GunMods.Config.ArmsTransparency

    for _, desc in ipairs(cssArms:GetDescendants()) do
        SnapshotArmPart(desc)
        local data = Viewmodel.OriginalArmData[desc]
        if data and not (data.Transparency and data.Transparency >= 1) then
            if desc:IsA("BasePart") then
                desc.Color = col
                desc.Transparency = trans
            elseif desc:IsA("SpecialMesh") then
                desc.TextureId = ""
            elseif desc:IsA("Decal") or desc:IsA("Texture") then
                desc.Transparency = 1
            end
        end
    end
end

local function ApplyGunChams()
    for _, container in ipairs(GetContainers()) do
        ApplyGunChamsTo(container)
    end
end

local function ApplyArmChams()
    for _, container in ipairs(GetContainers()) do
        ApplyArmChamsTo(container)
    end
end

--// Restore gun parts (no dependency on Arms existing)
local function RestoreGunChams()
    for part, data in pairs(Viewmodel.OriginalGunData) do
        if part and part.Parent then
            if part:IsA("BasePart") then
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

--// Marker management — bump the generation so everything re-applies
local function ClearGunMarker()
    ChamsGen = ChamsGen + 1
    for _, container in ipairs(GetContainers()) do
        local marker = container:FindFirstChild(Viewmodel.GunMarkerName)
        if marker then marker:Destroy() end
    end
end

local function ClearArmMarker()
    ChamsGen = ChamsGen + 1
    for _, container in ipairs(GetContainers()) do
        local cssArms = container:FindFirstChild("CSSArms")
        if cssArms then
            local marker = cssArms:FindFirstChild(Viewmodel.ArmMarkerName)
            if marker then marker:Destroy() end
        end
    end
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

        CleanupOriginalData()

        if GunMods.Config.ChamsEnabled then
            ApplyGunChams()
        end

        if GunMods.Config.ChamArms then
            ApplyArmChams()
        end

        if GunMods.Config.ChamsRainbow and GunMods.Config.ChamsEnabled then
            Viewmodel.RainbowHue = (Viewmodel.RainbowHue + dt * GunMods.Config.ChamsRainbowSpeed) % 1
            local hueColor = Color3.fromHSV(Viewmodel.RainbowHue, 1, 1)
            GunMods.Config.ChamsColor = hueColor
            GunMods.Config.ArmsColor = hueColor
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

        -- Muzzle flash
        y = g:CreateSection("Muzzle Flash", y + 10)

        y = g:CreateToggle("Block Muzzle Flash", false, function(state)
            GunMods.Config.MuzzleBlock = state
            if state then
                MuzzleEnable()
            else
                MuzzleDisable()
            end
        end, y)

        y = g:CreateToggle("Hide Flash Mesh", false, function(state)
            GunMods.Config.MuzzleHideMesh = state
            if state and GunMods.Config.MuzzleBlock then
                MuzzleSweep()
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

        -- Color wheel instead of preset buttons
        y = g:CreateSection("Cham Color", y + 10)

        y = g:CreateColorPicker("Color", GunMods.Config.ChamsColor, function(c)
            GunMods.Config.ChamsColor = c
            GunMods.Config.ArmsColor = c
            GunMods.Config.ChamsRainbow = false
            ClearAllMarkers()
        end, y)

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
        if GunMods.Config.MuzzleBlock then MuzzleSweep() end
        if GunMods.Config.ChamsEnabled or GunMods.Config.ChamArms then
            task.wait(1)
            StartChamsLoop()
        end
    end)

    return self
end

return GunMods
