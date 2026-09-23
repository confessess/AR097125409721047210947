

local ViewmodelCustomizer = {}
ViewmodelCustomizer.__index = ViewmodelCustomizer

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

ViewmodelCustomizer.Config = {
    Enabled = false,
    CloneTransparency = 0.5,
    CloneColor = Color3.fromRGB(255, 0, 0),
    CloneMaterial = "Neon",
    HideOriginal = false,
}

local State = {
    OriginalVM = nil,
    CloneVM = nil,
    Connections = {},
}

local function FindViewmodel()
    for _, child in ipairs(Camera:GetChildren()) do
        if child:IsA("Model") and child.Name ~= "ENI_CustomVM" then
            -- Check if it looks like a viewmodel (has MeshParts)
            for _, desc in ipairs(child:GetDescendants()) do
                if desc:IsA("MeshPart") then
                    return child
                end
            end
        end
    end
    return nil
end

local function DestroyClone()
    if State.CloneVM and State.CloneVM.Parent then
        State.CloneVM:Destroy()
    end
    State.CloneVM = nil

    if State.OriginalVM and State.OriginalVM.Parent then
        -- Restore original visibility
        for _, desc in ipairs(State.OriginalVM:GetDescendants()) do
            if desc:IsA("BasePart") and desc:GetAttribute("ENI_Hidden") then
                desc.LocalTransparencyModifier = 0
                desc:SetAttribute("ENI_Hidden", nil)
            end
        end
    end

    for _, conn in ipairs(State.Connections) do
        conn:Disconnect()
    end
    State.Connections = {}
    State.OriginalVM = nil
end

local function CreateCustomViewmodel()
    DestroyClone()

    local vm = FindViewmodel()
    if not vm then
        warn("[ENI] No viewmodel found in camera")
        return
    end

    State.OriginalVM = vm

    -- Clone the viewmodel
    local clone = vm:Clone()
    clone.Name = "ENI_CustomVM"

    -- Apply customizations to clone
    local material = Enum.Material[ViewmodelCustomizer.Config.CloneMaterial] or Enum.Material.Neon

    for _, desc in ipairs(clone:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("MeshPart") or desc:IsA("UnionOperation") then
            desc.Material = material
            desc.Color = ViewmodelCustomizer.Config.CloneColor
            desc.Transparency = ViewmodelCustomizer.Config.CloneTransparency
            desc.CanCollide = false
            desc.CastShadow = false
        elseif desc:IsA("Decal") or desc:IsA("Texture") then
            desc.Transparency = 1
        elseif desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
            desc:Destroy()
        end
    end

    -- Remove animate scripts from clone — we want it static/posed
    local animate = clone:FindFirstChild("Animate")
    if animate then animate:Destroy() end

    -- Parent to camera
    clone.Parent = Camera
    State.CloneVM = clone

    -- Optionally hide original
    if ViewmodelCustomizer.Config.HideOriginal then
        for _, desc in ipairs(vm:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc:SetAttribute("ENI_Hidden", true)
                desc.LocalTransparencyModifier = 1
            end
        end
    end

    -- Weld clone parts to corresponding original parts so it follows animations
    for _, origDesc in ipairs(vm:GetDescendants()) do
        if origDesc:IsA("BasePart") then
            local clonePart = clone:FindFirstChild(origDesc.Name, true)
            if clonePart and clonePart:IsA("BasePart") then
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = origDesc
                weld.Part1 = clonePart
                weld.Parent = clonePart

                clonePart.CFrame = origDesc.CFrame
            end
        end
    end

    print("[ENI] Custom viewmodel created from: " .. vm.Name)
end

local function StartWatcher()
    -- Watch for weapon switches
    table.insert(State.Connections, Camera.ChildAdded:Connect(function(child)
        task.wait(0.1)
        if ViewmodelCustomizer.Config.Enabled then
            if child:IsA("Model") and child.Name ~= "ENI_CustomVM" then
                CreateCustomViewmodel()
            end
        end
    end))

    table.insert(State.Connections, Camera.ChildRemoved:Connect(function(child)
        if child == State.OriginalVM then
            DestroyClone()
        end
    end))

    -- Initial
    CreateCustomViewmodel()
end

local function StopWatcher()
    DestroyClone()
end

function ViewmodelCustomizer:Init(Gui)
    self.Gui = Gui

    Gui:CreateTab("Viewmodel", "Clone and customize your current viewmodel.")

    Gui:SetTabRebuild("Viewmodel", function(g)
        local scroll = g:CreateScrollContent()
        local originalContent = g.Content
        g.Content = scroll

        local y = g:CreateSection("Custom Viewmodel", 0)

        y = g:CreateToggle("Enabled", ViewmodelCustomizer.Config.Enabled, function(state)
            ViewmodelCustomizer.Config.Enabled = state
            if state then StartWatcher() else StopWatcher() end
        end, y)

        y = g:CreateToggle("Hide Original", ViewmodelCustomizer.Config.HideOriginal, function(state)
            ViewmodelCustomizer.Config.HideOriginal = state
            if ViewmodelCustomizer.Config.Enabled then
                CreateCustomViewmodel()
            end
        end, y)

        y = g:CreateSlider("Transparency", 0, 90, math.floor(ViewmodelCustomizer.Config.CloneTransparency * 100), function(val)
            ViewmodelCustomizer.Config.CloneTransparency = val / 100
            if State.CloneVM then
                for _, desc in ipairs(State.CloneVM:GetDescendants()) do
                    if desc:IsA("BasePart") then
                        desc.Transparency = ViewmodelCustomizer.Config.CloneTransparency
                    end
                end
            end
        end, y)

        local Materials = {
            "Neon", "ForceField", "Glass", "SmoothPlastic", "Metal",
            "Ice", "Gold", "DiamondPlate", "Foil", "CorrodedMetal"
        }

        y = g:CreateDropdown("Material", Materials, ViewmodelCustomizer.Config.CloneMaterial, function(val)
            ViewmodelCustomizer.Config.CloneMaterial = val
            if State.CloneVM then
                local mat = Enum.Material[val] or Enum.Material.Neon
                for _, desc in ipairs(State.CloneVM:GetDescendants()) do
                    if desc:IsA("BasePart") then
                        desc.Material = mat
                    end
                end
            end
        end, y)

        y = g:CreateSection("Colors", y + 10)

        local ColorPresets = {
            {Name = "Red", Color = Color3.fromRGB(255, 0, 0)},
            {Name = "Blue", Color = Color3.fromRGB(0, 100, 255)},
            {Name = "Green", Color = Color3.fromRGB(0, 255, 0)},
            {Name = "Purple", Color = Color3.fromRGB(150, 0, 255)},
            {Name = "Cyan", Color = Color3.fromRGB(0, 255, 255)},
            {Name = "White", Color = Color3.fromRGB(255, 255, 255)},
        }

        for _, preset in ipairs(ColorPresets) do
            y = g:CreateButton(preset.Name, function()
                ViewmodelCustomizer.Config.CloneColor = preset.Color
                if State.CloneVM then
                    for _, desc in ipairs(State.CloneVM:GetDescendants()) do
                        if desc:IsA("BasePart") then
                            desc.Color = preset.Color
                        end
                    end
                end
            end, y)
        end

        g.Content = originalContent
    end)

    print("[ENI] Viewmodel Customizer loaded")
    return self
end

return ViewmodelCustomizer