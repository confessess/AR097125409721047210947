--// ═══════════════════════════════════════════════════════════════
--//  MODULE: esp.lua
--//  Drawing boxes + material chams + Billboard labels + Beam tracers
--// ═══════════════════════════════════════════════════════════════
local ESP = {}
ESP.__index = ESP

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

ESP.Config = {
    Enabled = false,
    Boxes = false,
    Chams = false,
    Names = false,
    Health = false,
    Distance = false,
    Weapon = false,
    Tracers = false,
    TeamCheck = true,
    RenderDistance = 1000,
    Color = Color3.fromRGB(255, 0, 45),
    ChamsTransparency = 0,
    ChamsMaterial = "ForceField",
}

local METERS_PER_STUD = 0.28
local BOX_SLOTS = 6

local Visuals = {}
local TracerFolder = nil
local ESPGui = nil

local PART_ALIASES = {
    { "Head" },
    { "UpperTorso", "Torso" },
    { "LeftUpperArm", "LeftArm" },
    { "RightUpperArm", "RightArm" },
    { "LeftUpperLeg", "LeftLeg" },
    { "RightUpperLeg", "RightLeg" },
}

--// ── helpers ────────────────────────────────────────────────────
local function colorHex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5))
end

local function escapeRichText(value)
    return tostring(value or "")
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
end

local function formatMeters(meters)
    if meters < 100 then
        return (string.format("%.1f", meters):gsub("%.0$", "")) .. " m"
    end
    return tostring(math.floor(meters + 0.5)) .. " m"
end

local function healthColor(ratio)
    if ratio <= 0.25 then return "#FF405B" end
    if ratio <= 0.65 then return "#FFD34D" end
    return "#55DDFF"
end

--// Arsenal stores live health on Player.NRPBS, not on the Humanoid
local function readHealth(player, humanoid)
    local folder = player:FindFirstChild("NRPBS")
    if folder then
        local cur = folder:FindFirstChild("Health")
        if cur and cur:IsA("ValueBase") and typeof(cur.Value) == "number" then
            local maxValue = folder:FindFirstChild("MaxHealth")
                or folder:FindFirstChild("OMaxHealth")
            local max = (maxValue and maxValue:IsA("ValueBase")
                and typeof(maxValue.Value) == "number" and maxValue.Value) or 100
            max = math.max(1, max)
            return math.clamp(cur.Value, 0, max), max
        end
    end
    local max = math.max(1, humanoid.MaxHealth)
    return math.clamp(humanoid.Health, 0, max), max
end

local function ensureGui()
    if ESPGui and ESPGui.Parent then return ESPGui end
    local gui = Instance.new("ScreenGui")
    gui.Name = "ENI_ESP"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok or not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    ESPGui = gui
    return gui
end

local function ensureTracerFolder()
    if TracerFolder and TracerFolder.Parent then return TracerFolder end
    local existing = Workspace:FindFirstChild("ENI_Tracers")
    if existing then existing:Destroy() end
    TracerFolder = Instance.new("Folder")
    TracerFolder.Name = "ENI_Tracers"
    TracerFolder.Parent = Workspace
    return TracerFolder
end

local function chestPart(character)
    if not character then return nil end
    return character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
end

local function createChestAttachment(character, name)
    local chest = chestPart(character)
    if not chest or not chest:IsA("BasePart") then return nil end
    local attachment = Instance.new("Attachment")
    attachment.Name = name
    attachment.Position = (chest.Name == "HumanoidRootPart")
        and Vector3.new(0, math.max(1.2, chest.Size.Y * 0.6), 0)
        or Vector3.zero
    attachment.Parent = chest
    return attachment
end

local LocalSourceAttachment = nil

local function ensureSourceAttachment(character)
    local chest = chestPart(character)
    if not chest then return nil end
    if LocalSourceAttachment and LocalSourceAttachment.Parent == chest then
        return LocalSourceAttachment
    end
    if LocalSourceAttachment then pcall(function() LocalSourceAttachment:Destroy() end) end
    LocalSourceAttachment = createChestAttachment(character, "ENI_TracerSource")
    return LocalSourceAttachment
end

local function clearSourceAttachment()
    if LocalSourceAttachment then
        pcall(function() LocalSourceAttachment:Destroy() end)
        LocalSourceAttachment = nil
    end
end

--// ── object lifecycle ───────────────────────────────────────────
local function newSquare(filled)
    local d = Drawing.new("Square")
    d.Filled = filled
    d.Thickness = 1
    d.Transparency = 1
    d.Color = ESP.Config.Color
    d.Visible = false
    return d
end

local function destroyVisual(player)
    local v = Visuals[player]
    if not v then return end
    Visuals[player] = nil
    if v.billboard then pcall(function() v.billboard:Destroy() end) end
    if v.tracer then pcall(function() v.tracer:Destroy() end) end
    if v.tracerAttachment then pcall(function() v.tracerAttachment:Destroy() end) end
    for _, d in pairs(v.boxes or {}) do pcall(function() d:Remove() end) end
    for _, d in pairs(v.fills or {}) do pcall(function() d:Remove() end) end
end

local function clearAll()
    for player in pairs(Visuals) do destroyVisual(player) end
    clearSourceAttachment()
end

local function hideVisual(v)
    if v.billboard then v.billboard.Enabled = false; v.billboard.Adornee = nil end
    if v.tracer then v.tracer.Enabled = false end
    for _, d in pairs(v.boxes or {}) do d.Visible = false end
    for _, d in pairs(v.fills or {}) do d.Visible = false end
end

local function createVisual(player)
    local v = Visuals[player]
    if v then return v end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ENI_Label_" .. player.Name
    billboard.Size = UDim2.fromOffset(320, 90)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 2500
    billboard.Enabled = false
    billboard.Parent = ensureGui()

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = ESP.Config.Color
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextWrapped = true
    label.RichText = true
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ZIndex = 3
    label.Parent = billboard

    local tracer = Instance.new("Beam")
    tracer.Name = "ENI_Tracer_" .. player.Name
    tracer.Color = ColorSequence.new(ESP.Config.Color)
    tracer.Transparency = NumberSequence.new(0)
    tracer.Width0 = 0.1
    tracer.Width1 = 0.1
    tracer.FaceCamera = true
    tracer.LightEmission = 1
    tracer.LightInfluence = 0
    tracer.Segments = 1
    tracer.Enabled = false
    tracer.Parent = ensureTracerFolder()

    v = {
        boxes = {},
        fills = {},
        chamData = {},
        chamCharacter = nil,
        billboard = billboard,
        label = label,
        tracer = tracer,
        tracerAttachment = nil,
        tracerCharacter = nil,
    }
    for i = 1, BOX_SLOTS do
        v.boxes[i] = newSquare(false)
        v.fills[i] = newSquare(true)
    end
    Visuals[player] = v
    return v
end

--// ── parts + screen projection ──────────────────────────────────
local function resolveParts(character)
    local parts = {}
    for _, alias in ipairs(PART_ALIASES) do
        for _, name in ipairs(alias) do
            local part = character:FindFirstChild(name)
            if part and part:IsA("BasePart") then
                parts[#parts + 1] = part
                break
            end
        end
    end
    return parts
end

--// projects the 8 corners of a part and returns its screen rect
local function partScreenRect(part, cam)
    local cf = part.CFrame
    local half = part.Size * 0.5
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for xi = -1, 1, 2 do
        for yi = -1, 1, 2 do
            for zi = -1, 1, 2 do
                local world = cf * Vector3.new(half.X * xi, half.Y * yi, half.Z * zi)
                local sp, onScreen = cam:WorldToViewportPoint(world)
                if sp.Z <= 0 then return nil end
                if sp.X < minX then minX = sp.X end
                if sp.X > maxX then maxX = sp.X end
                if sp.Y < minY then minY = sp.Y end
                if sp.Y > maxY then maxY = sp.Y end
                _ = onScreen
            end
        end
    end

    local w, h = maxX - minX, maxY - minY
    if w < 1 or h < 1 then return nil end
    return Vector2.new(minX, minY), Vector2.new(w, h)
end

--// ── chams (material override) ──────────────────────────────────
local function clearChams(v)
    for part, data in pairs(v.chamData) do
        if part and part.Parent then
            pcall(function()
                part.Material = data.Material
                part.Color = data.Color
                part.Transparency = data.Transparency
                part.LocalTransparencyModifier = data.LocalTransparencyModifier
            end)
        end
    end
    v.chamData = {}
    v.chamCharacter = nil
end

local function syncChams(v, character, enabled)
    if v.chamCharacter ~= character then
        clearChams(v)
        if enabled and character then
            v.chamCharacter = character
            local mat = Enum.Material[ESP.Config.ChamsMaterial] or Enum.Material.ForceField
            for _, part in ipairs(resolveParts(character)) do
                v.chamData[part] = {
                    Material = part.Material,
                    Color = part.Color,
                    Transparency = part.Transparency,
                    LocalTransparencyModifier = part.LocalTransparencyModifier,
                }
                part.Material = mat
                part.Color = ESP.Config.Color
                part.Transparency = ESP.Config.ChamsTransparency
                part.LocalTransparencyModifier = ESP.Config.ChamsTransparency
            end
        end
        return
    end

    if not enabled then
        if next(v.chamData) then clearChams(v) end
        return
    end

    --// re-assert, the game rewrites materials on respawn/cosmetic changes
    local mat = Enum.Material[ESP.Config.ChamsMaterial] or Enum.Material.ForceField
    for part in pairs(v.chamData) do
        if part.Parent then
            if part.Material ~= mat then part.Material = mat end
            if part.Color ~= ESP.Config.Color then part.Color = ESP.Config.Color end
        else
            v.chamData[part] = nil
        end
    end
end

--// ── main loop ──────────────────────────────────────────────────
local function step()
    local cfg = ESP.Config

    for player in pairs(Visuals) do
        if player.Parent ~= Players then destroyVisual(player) end
    end

    if not cfg.Enabled then
        for _, v in pairs(Visuals) do hideVisual(v) end
        return
    end

    local cam = Workspace.CurrentCamera
    if not cam then return end

    local localChar = LocalPlayer.Character
    local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")
    local sourceAttachment = nil
    if cfg.Tracers and localChar and localRoot then
        sourceAttachment = ensureSourceAttachment(localChar)
    elseif not cfg.Tracers then
        clearSourceAttachment()
    end

    local hex = colorHex(cfg.Color)

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local v = createVisual(player)
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local head = character and character:FindFirstChild("Head")
            local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")

            local alive = root and humanoid and humanoid.Health > 0
            local sameTeam = cfg.TeamCheck
                and LocalPlayer.Team ~= nil
                and player.Team == LocalPlayer.Team
            local studs = (alive and localRoot)
                and (root.Position - localRoot.Position).Magnitude or math.huge
            local ready = alive and not sameTeam and studs <= cfg.RenderDistance

            --// boxes + fill
            local parts = (ready and (cfg.Boxes or cfg.Chams)) and resolveParts(character) or {}
            for i = 1, BOX_SLOTS do
                local box, fill = v.boxes[i], v.fills[i]
                local part = parts[i]
                local rect, size = nil, nil
                if part then rect, size = partScreenRect(part, cam) end

                if rect and cfg.Boxes then
                    box.Position = rect
                    box.Size = size
                    box.Color = cfg.Color
                    box.Visible = true
                else
                    box.Visible = false
                end

                if rect and cfg.Chams then
                    fill.Position = rect
                    fill.Size = size
                    fill.Color = cfg.Color
                    fill.Transparency = 0.55
                    fill.Visible = true
                else
                    fill.Visible = false
                end
            end

            syncChams(v, character, ready and cfg.Chams)

            v.billboard.Adornee = (ready and head) or nil

            if ready then
                local meters = studs * METERS_PER_STUD
                local lines = {}
                if cfg.Names then
                    lines[#lines + 1] = '<font color="' .. hex .. '"><b>'
                        .. escapeRichText(player.DisplayName) .. '</b></font>'
                end
                if cfg.Health then
                    local cur, max = readHealth(player, humanoid)
                    local ratio = math.clamp(cur / max, 0, 1)
                    lines[#lines + 1] = '<font color="#AEB9C2">HP </font>'
                        .. '<font color="' .. healthColor(ratio) .. '"><b>'
                        .. math.floor(cur + 0.5) .. '</b></font>'
                        .. '<font color="#AEB9C2">/</font>'
                        .. '<font color="#55DDFF"><b>' .. math.floor(max + 0.5) .. '</b></font>'
                end
                if cfg.Weapon then
                    local tool = character:FindFirstChildOfClass("Tool")
                    lines[#lines + 1] = '<font color="#E7EDF2">'
                        .. escapeRichText(tool and tool.Name or "None") .. '</font>'
                end
                if cfg.Distance and meters >= 10 then
                    lines[#lines + 1] = '<font color="#E7EDF2">' .. formatMeters(meters) .. '</font>'
                end

                v.label.Text = table.concat(lines, "\n")
                v.label.TextColor3 = cfg.Color
                v.billboard.Enabled = #lines > 0

                if v.tracerCharacter ~= character
                    or not v.tracerAttachment
                    or not v.tracerAttachment.Parent then
                    if v.tracerAttachment then
                        pcall(function() v.tracerAttachment:Destroy() end)
                    end
                    v.tracerAttachment = createChestAttachment(character, "ENI_TracerTarget")
                    v.tracerCharacter = character
                end

                if cfg.Tracers and meters >= 10 and sourceAttachment and v.tracerAttachment then
                    v.tracer.Color = ColorSequence.new(cfg.Color)
                    v.tracer.Attachment0 = sourceAttachment
                    v.tracer.Attachment1 = v.tracerAttachment
                    v.tracer.Enabled = true
                else
                    v.tracer.Enabled = false
                end
            else
                v.billboard.Enabled = false
                v.tracer.Enabled = false
            end
        end
    end
end

RunService.RenderStepped:Connect(step)

Players.PlayerRemoving:Connect(destroyVisual)

--// ── public API ─────────────────────────────────────────────────
function ESP.IsValidPlayer(player)
    if not player or player == LocalPlayer or player.Parent ~= Players then return false end
    local character = player.Character
    if not character or not character:IsDescendantOf(Workspace) then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
        and character:FindFirstChild("HumanoidRootPart") ~= nil
end

function ESP.GetValidPlayers()
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if ESP.IsValidPlayer(player) then table.insert(list, player) end
    end
    return list
end

function ESP.SetColor(c)
    ESP.Config.Color = c
    for _, v in pairs(Visuals) do
        v.tracer.Color = ColorSequence.new(c)
        v.label.TextColor3 = c
        for _, d in pairs(v.boxes) do d.Color = c end
        for _, d in pairs(v.fills) do d.Color = c end
    end
end

function ESP:Init(Gui)
    self.Gui = Gui
    Gui:SetTabRebuild("Visuals", function(g)
        local scroll = g:CreateScrollContent()
        local originalContent = g.Content
        g.Content = scroll

        local y = g:CreateSection("ESP", 0)
        y = g:CreateToggle("Enabled", ESP.Config.Enabled, function(s)
            ESP.Config.Enabled = s
            if not s then clearAll() end
        end, y)
        y = g:CreateToggle("Boxes", ESP.Config.Boxes, function(s) ESP.Config.Boxes = s end, y)
        y = g:CreateToggle("Chams", ESP.Config.Chams, function(s) ESP.Config.Chams = s end, y)
        y = g:CreateToggle("Names", ESP.Config.Names, function(s) ESP.Config.Names = s end, y)
        y = g:CreateToggle("Health", ESP.Config.Health, function(s) ESP.Config.Health = s end, y)
        y = g:CreateToggle("Weapon", ESP.Config.Weapon, function(s) ESP.Config.Weapon = s end, y)
        y = g:CreateToggle("Distance", ESP.Config.Distance, function(s) ESP.Config.Distance = s end, y)
        y = g:CreateToggle("Tracers", ESP.Config.Tracers, function(s)
            ESP.Config.Tracers = s
            if not s then clearSourceAttachment() end
        end, y)
        y = g:CreateToggle("Team Check", ESP.Config.TeamCheck, function(s) ESP.Config.TeamCheck = s end, y)
        y = g:CreateSlider("Render Distance", 10, 2500, ESP.Config.RenderDistance, function(v)
            ESP.Config.RenderDistance = v
        end, y)

        y = g:CreateSection("ESP Color", y + 10)
        y = g:CreateColorPicker("Color", ESP.Config.Color, function(c) ESP.SetColor(c) end, y)

        g.Content = originalContent
    end)
    return self
end

return ESP
