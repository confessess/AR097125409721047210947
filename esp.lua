

local ESP = {}
ESP.__index = ESP

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

ESP.Config = {
    Enabled = false,
    Boxes = false,
    Names = false,
    Health = false,
    Distance = false,
    Weapon = false,
    Chams = false,
    TeamCheck = true,
    RenderDistance = 1000,
    Color = Color3.fromRGB(255, 0, 0),
}

local ESPObjects = {}
local Highlights = {}

local function HideAllESP()
    for _, esp in pairs(ESPObjects) do
        esp.Box.Visible = false
        esp.BoxOutline.Visible = false
        esp.Name.Visible = false
        esp.HealthBar.Visible = false
        esp.HealthBarOutline.Visible = false
        esp.HealthText.Visible = false
        esp.Distance.Visible = false
        esp.Weapon.Visible = false
    end
end

local function HideAllChams()
    for _, hl in pairs(Highlights) do
        if hl then
            hl.Enabled = false
            hl.Parent = nil
        end
    end
end

local function CreateESP(player)
    if player == LocalPlayer then return end

    local esp = {
        Player = player,
        Box = Drawing.new("Square"),
        BoxOutline = Drawing.new("Square"),
        Name = Drawing.new("Text"),
        HealthBar = Drawing.new("Square"),
        HealthBarOutline = Drawing.new("Square"),
        HealthText = Drawing.new("Text"),
        Distance = Drawing.new("Text"),
        Weapon = Drawing.new("Text"),
    }

    esp.Box.Thickness = 1
    esp.Box.Filled = false
    esp.Box.Color = ESP.Config.Color
    esp.Box.Visible = false

    esp.BoxOutline.Thickness = 3
    esp.BoxOutline.Filled = false
    esp.BoxOutline.Color = Color3.new(0, 0, 0)
    esp.BoxOutline.Visible = false

    esp.Name.Size = 14
    esp.Name.Center = true
    esp.Name.Outline = true
    esp.Name.Color = ESP.Config.Color
    esp.Name.Visible = false

    esp.HealthBar.Filled = true
    esp.HealthBar.Visible = false

    esp.HealthBarOutline.Filled = true
    esp.HealthBarOutline.Color = Color3.new(0, 0, 0)
    esp.HealthBarOutline.Visible = false

    esp.HealthText.Size = 12
    esp.HealthText.Center = true
    esp.HealthText.Outline = true
    esp.HealthText.Visible = false

    esp.Distance.Size = 12
    esp.Distance.Center = true
    esp.Distance.Outline = true
    esp.Distance.Color = ESP.Config.Color
    esp.Distance.Visible = false

    esp.Weapon.Size = 12
    esp.Weapon.Center = true
    esp.Weapon.Outline = true
    esp.Weapon.Color = ESP.Config.Color
    esp.Weapon.Visible = false

    ESPObjects[player] = esp

    if not Highlights[player] then
        local hl = Instance.new("Highlight")
        hl.Name = "ESPChams"
        hl.FillColor = ESP.Config.Color
        hl.OutlineColor = ESP.Config.Color
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.Enabled = false
        Highlights[player] = hl
    end

    return esp
end

local function RemoveESP(player)
    local esp = ESPObjects[player]
    if esp then
        for _, obj in pairs(esp) do
            if type(obj) == "table" and obj.Remove then obj:Remove() end
        end
        ESPObjects[player] = nil
    end
    local hl = Highlights[player]
    if hl then
        hl.Enabled = false
        hl.Parent = nil
        hl:Destroy()
        Highlights[player] = nil
    end
end

local function UpdateESP()
    local camera = Workspace.CurrentCamera
    if not camera then
        HideAllESP()
        HideAllChams()
        return
    end

    if not ESP.Config.Enabled then
        HideAllESP()
        HideAllChams()
        return
    end

    for player, esp in pairs(ESPObjects) do
        if not player or not player.Parent then
            RemoveESP(player)
        else
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")

            if not character or not humanoid or not rootPart then
                if esp then
                    esp.Box.Visible = false
                    esp.BoxOutline.Visible = false
                    esp.Name.Visible = false
                    esp.HealthBar.Visible = false
                    esp.HealthBarOutline.Visible = false
                    esp.HealthText.Visible = false
                    esp.Distance.Visible = false
                    esp.Weapon.Visible = false
                end
                local hl = Highlights[player]
                if hl then
                    hl.Enabled = false
                    hl.Parent = nil
                end
            elseif character and humanoid and rootPart and humanoid.Health > 0 then
            local showESP = true
            if ESP.Config.TeamCheck and player.Team == LocalPlayer.Team then
                showESP = false
            end

            local distance = (rootPart.Position - camera.CFrame.Position).Magnitude
            if distance > ESP.Config.RenderDistance then
                showESP = false
            end

            if showESP then
                local pos, onScreen = camera:WorldToViewportPoint(rootPart.Position)
                if onScreen then
                    local upperPos = camera:WorldToViewportPoint(rootPart.Position + Vector3.new(0, 3, 0))
                    local lowerPos = camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0))
                    local height = math.max(1, math.abs(upperPos.Y - lowerPos.Y))
                    local width = height / 2

                    if ESP.Config.Boxes then
                        esp.Box.Size = Vector2.new(width, height)
                        esp.Box.Position = Vector2.new(pos.X - width / 2, pos.Y - height / 2)
                        esp.Box.Color = ESP.Config.Color
                        esp.Box.Visible = true
                        esp.BoxOutline.Size = Vector2.new(width, height)
                        esp.BoxOutline.Position = Vector2.new(pos.X - width / 2, pos.Y - height / 2)
                        esp.BoxOutline.Visible = true
                    else
                        esp.Box.Visible = false
                        esp.BoxOutline.Visible = false
                    end

                    if ESP.Config.Names then
                        esp.Name.Text = player.Name
                        esp.Name.Position = Vector2.new(pos.X, pos.Y - height / 2 - 15)
                        esp.Name.Color = ESP.Config.Color
                        esp.Name.Visible = true
                    else
                        esp.Name.Visible = false
                    end

                    if ESP.Config.Health then
                        local healthPercent = clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
                        local r = clamp(255 * (1 - healthPercent), 0, 255)
                        local g = clamp(255 * healthPercent, 0, 255)
                        local barHeight = math.max(2, height * healthPercent)

                        esp.HealthBar.Size = Vector2.new(4, barHeight)
                        esp.HealthBar.Position = Vector2.new(pos.X - width / 2 - 6, pos.Y + height / 2 - barHeight)
                        esp.HealthBar.Color = Color3.fromRGB(r, g, 0)
                        esp.HealthBar.Visible = true

                        esp.HealthBarOutline.Size = Vector2.new(6, height)
                        esp.HealthBarOutline.Position = Vector2.new(pos.X - width / 2 - 7, pos.Y - height / 2)
                        esp.HealthBarOutline.Visible = true

                        esp.HealthText.Text = tostring(math.floor(humanoid.Health))
                        esp.HealthText.Position = Vector2.new(pos.X - width / 2 - 20, pos.Y)
                        esp.HealthText.Color = esp.HealthBar.Color
                        esp.HealthText.Visible = true
                    else
                        esp.HealthBar.Visible = false
                        esp.HealthBarOutline.Visible = false
                        esp.HealthText.Visible = false
                    end

                    if ESP.Config.Distance then
                        esp.Distance.Text = math.floor(distance) .. "m"
                        esp.Distance.Position = Vector2.new(pos.X, pos.Y + height / 2 + 5)
                        esp.Distance.Color = ESP.Config.Color
                        esp.Distance.Visible = true
                    else
                        esp.Distance.Visible = false
                    end

                    if ESP.Config.Weapon then
                        local tool = character:FindFirstChildOfClass("Tool")
                        esp.Weapon.Text = tool and tool.Name or "None"
                        esp.Weapon.Position = Vector2.new(pos.X, pos.Y + height / 2 + 20)
                        esp.Weapon.Color = ESP.Config.Color
                        esp.Weapon.Visible = true
                    else
                        esp.Weapon.Visible = false
                    end
                else
                    esp.Box.Visible = false
                    esp.BoxOutline.Visible = false
                    esp.Name.Visible = false
                    esp.HealthBar.Visible = false
                    esp.HealthBarOutline.Visible = false
                    esp.HealthText.Visible = false
                    esp.Distance.Visible = false
                    esp.Weapon.Visible = false
                end
            else
                esp.Box.Visible = false
                esp.BoxOutline.Visible = false
                esp.Name.Visible = false
                esp.HealthBar.Visible = false
                esp.HealthBarOutline.Visible = false
                esp.HealthText.Visible = false
                esp.Distance.Visible = false
                esp.Weapon.Visible = false
            end
        else
            esp.Box.Visible = false
            esp.BoxOutline.Visible = false
            esp.Name.Visible = false
            esp.HealthBar.Visible = false
            esp.HealthBarOutline.Visible = false
            esp.HealthText.Visible = false
            esp.Distance.Visible = false
            esp.Weapon.Visible = false
        end
    end

    for player, hl in pairs(Highlights) do
        local character = player.Character
        local showChams = false
        if character and ESP.Config.Chams and ESP.Config.Enabled then
            if not ESP.Config.TeamCheck or player.Team ~= LocalPlayer.Team then
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local distance = (rootPart.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude
                    if distance <= ESP.Config.RenderDistance then
                        showChams = true
                        hl.Parent = character
                    end
                end
            end
        end

        if showChams then
            hl.Enabled = true
            hl.FillColor = ESP.Config.Color
            hl.OutlineColor = ESP.Config.Color
        else
            hl.Enabled = false
            hl.Parent = nil
        end
    end

end

RunService.RenderStepped:Connect(UpdateESP)

for _, player in ipairs(Players:GetPlayers()) do if player ~= LocalPlayer then CreateESP(player) end end
Players.PlayerAdded:Connect(function(p) task.wait(1) CreateESP(p) end)
Players.PlayerRemoving:Connect(RemoveESP)

function ESP:Init(Gui)
    self.Gui = Gui
    Gui:SetTabRebuild("Visuals", function(g)
        local scroll = g:CreateScrollContent()
        local originalContent = g.Content
        g.Content = scroll

        local y = g:CreateSection("ESP", 0)
        y = g:CreateToggle("Enabled", false, function(s) 
            ESP.Config.Enabled = s
            if not s then
                HideAllESP()
                HideAllChams()
            end
        end, y)
        y = g:CreateToggle("Boxes", false, function(s) ESP.Config.Boxes = s end, y)
        y = g:CreateToggle("Names", false, function(s) ESP.Config.Names = s end, y)
        y = g:CreateToggle("Health", false, function(s) ESP.Config.Health = s end, y)
        y = g:CreateToggle("Distance", false, function(s) ESP.Config.Distance = s end, y)
        y = g:CreateToggle("Weapon", false, function(s) ESP.Config.Weapon = s end, y)
        y = g:CreateToggle("Chams", false, function(s) 
            ESP.Config.Chams = s
            if not s then HideAllChams() end
        end, y)
        y = g:CreateToggle("Team Check", true, function(s) ESP.Config.TeamCheck = s end, y)
        y = g:CreateSlider("Render Distance", 10, 2500, 1000, function(v) ESP.Config.RenderDistance = v end, y)

        -- Color Picker
        y = g:CreateSection("ESP Color", y + 10)

        local colorPresets = {
            {Name = "Red", Color = Color3.fromRGB(255, 0, 0)},
            {Name = "Blue", Color = Color3.fromRGB(0, 100, 255)},
            {Name = "Green", Color = Color3.fromRGB(0, 255, 0)},
            {Name = "Purple", Color = Color3.fromRGB(150, 0, 255)},
            {Name = "Pink", Color = Color3.fromRGB(255, 100, 200)},
            {Name = "Orange", Color = Color3.fromRGB(255, 150, 0)},
            {Name = "Yellow", Color = Color3.fromRGB(255, 255, 0)},
            {Name = "Cyan", Color = Color3.fromRGB(0, 255, 255)},
            {Name = "White", Color = Color3.fromRGB(255, 255, 255)},
        }

        for _, preset in ipairs(colorPresets) do
            y = g:CreateButton(preset.Name, function()
                ESP.Config.Color = preset.Color
                
            end, y)
        end

        g.Content = originalContent
    end)
    return self
end

return ESP