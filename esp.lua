--// ═══════════════════════════════════════════════════════════════
--//  MODULE: esp.lua
--//  Highlight / Billboard / Beam ESP
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
}

local METERS_PER_STUD = 0.28
-- Roblox renders ~31 Highlights at once; 6 parts x 4 players stays under it
local MAX_HIGHLIGHT_PLAYERS = 4

local Visuals = {}
local TracerFolder = nil
local HighlightFolder = nil
local ESPGui = nil

-- one box per body region, resolved to whichever rig variant exists
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

-- Highlights go in Workspace, not a ScreenGui — that is the reliable parent
local function ensureHighlightFolder()
    if HighlightFolder and HighlightFolder.Parent then return HighlightFolder end
    local existing = Workspace:FindFirstChild("ENI_ESP_Highlights")
    if existing then existing:Destroy() end
    HighlightFolder = Instance.new("Folder")
    HighlightFolder.Name = "ENI_ESP_Highlights"
    HighlightFolder.Parent = Workspace
    return HighlightFolder
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
local function destroyVisual(player)
    local v = Visuals[player]
    if not v then return end
    Visuals[player] = nil
    if v.billboard then pcall(function() v.billboard:Destroy() end) end
    if v.tracer then pcall(function() v.tracer:Destroy() end) end
    if v.tracerAttachment then pcall(function() v.tracerAttachment:Destroy() end) end
    for _, hl in pairs(v.highlights or {}) do pcall(function() hl:Destroy() end) end
end

local function clearAll()
    for player in pairs(Visuals) do destroyVisual(player) end
    clearSourceAttachment()
end

local function hideVisual(v)
    if v.billboard then v.billboard.Enabled = false; v.billboard.Adornee = nil end
    if v.tracer then v.tracer.Enabled = false end
    for _, hl in pairs(v.highlights or {}) do hl.Enabled = false end
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
        highlights = {},
        highlightCharacter = nil,
        modeKey = nil,
        billboard = billboard,
        label = label,
        tracer = tracer,
        tracerAttachment = nil,
        tracerCharacter = nil,
    }
    Visuals[player] = v
    return v
end

--// ── highlights (boxes + chams share one set) ───────────────────
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

local function applyHighlightStyle(v, boxes, chams)
    local key = (boxes and "b" or "") .. (chams and "c" or "")
    if v.modeKey == key then return end
    v.modeKey = key

    local fill, outline
    if boxes and chams then
        fill, outline = 0.45, 0
    elseif boxes then
        fill, outline = 0.9, 0
    else
        fill, outline = 0.4, 1
    end

    local col = ESP.Config.Color
    for _, hl in pairs(v.highlights) do
        hl.FillColor = col
        hl.OutlineColor = col
        hl.FillTransparency = fill
        hl.OutlineTransparency = outline
    end
end

local function syncHighlights(v, character, enabled, boxes, chams)
    if v.highlightCharacter ~= character then
        for _, hl in pairs(v.highlights) do pcall(function() hl:Destroy() end) end
        v.highlights = {}
        v.highlightCharacter = character
        v.modeKey = nil

        if character then
            local folder = ensureHighlightFolder()
            for _, part in ipairs(resolveParts(character)) do
                local hl = Instance.new("Highlight")
                hl.Name = "ENI_Body_" .. part.Name
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Adornee = part
                hl.Enabled = false
                hl.Parent = folder
                v.highlights[part] = hl
            end
        end
    end

    if not enabled then
        for _, hl in pairs(v.highlights) do hl.Enabled = false end
        return
    end

    applyHighlightStyle(v, boxes, chams)
    for part, hl in pairs(v.highlights) do
        if not part.Parent then
            pcall(function() hl:Destroy() end)
            v.highlights[part] = nil
        else
            hl.Enabled = true
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
    local candidates = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local head = character and character:FindFirstChild("Head")
            local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")

            local alive = root and humanoid and humanoid.Health > 0
            -- Arsenal is FFA: Team is nil for everyone, so nil must not match
            local sameTeam = cfg.TeamCheck
                and LocalPlayer.Team ~= nil
                and player.Team == LocalPlayer.Team
            local studs = (alive and localRoot)
                and (root.Position - localRoot.Position).Magnitude or math.huge
            local ready = alive and not sameTeam and studs <= cfg.RenderDistance

            candidates[#candidates + 1] = {
                player = player,
                character = character,
                head = head,
                humanoid = humanoid,
                studs = studs,
                ready = ready,
            }
        end
    end

    table.sort(candidates, function(a, b) return a.studs < b.studs end)

    local highlightBudget = MAX_HIGHLIGHT_PLAYERS

    for _, c in ipairs(candidates) do
        local v = createVisual(c.player)
        local ready = c.ready
        local highlightOn = false

        if ready and (cfg.Boxes or cfg.Chams) and highlightBudget > 0 then
            highlightBudget = highlightBudget - 1
            highlightOn = true
        end

        syncHighlights(v, c.character, highlightOn, cfg.Boxes, cfg.Chams)
        v.billboard.Adornee = (ready and c.head) or nil

        if ready then
            local meters = c.studs * METERS_PER_STUD
            local lines = {}
            if cfg.Names then
                lines[#lines + 1] = '<font color="' .. hex .. '"><b>'
                    .. escapeRichText(c.player.DisplayName) .. '</b></font>'
            end
            if cfg.Health then
                local cur = math.max(0, c.humanoid.Health)
                local max = math.max(1, c.humanoid.MaxHealth)
                local ratio = math.clamp(cur / max, 0, 1)
                lines[#lines + 1] = '<font color="#AEB9C2">HP </font>'
                    .. '<font color="' .. healthColor(ratio) .. '"><b>'
                    .. math.floor(cur + 0.5) .. '</b></font>'
                    .. '<font color="#AEB9C2">/</font>'
                    .. '<font color="#55DDFF"><b>' .. math.floor(max + 0.5) .. '</b></font>'
            end
            if cfg.Weapon then
                local tool = c.character:FindFirstChildOfClass("Tool")
                lines[#lines + 1] = '<font color="#E7EDF2">'
                    .. escapeRichText(tool and tool.Name or "None") .. '</font>'
            end
            if cfg.Distance and meters >= 10 then
                lines[#lines + 1] = '<font color="#E7EDF2">' .. formatMeters(meters) .. '</font>'
            end

            v.label.Text = table.concat(lines, "\n")
            v.label.TextColor3 = cfg.Color
            v.billboard.Enabled = #lines > 0

            if v.tracerCharacter ~= c.character
                or not v.tracerAttachment
                or not v.tracerAttachment.Parent then
                if v.tracerAttachment then
                    pcall(function() v.tracerAttachment:Destroy() end)
                end
                v.tracerAttachment = createChestAttachment(c.character, "ENI_TracerTarget")
                v.tracerCharacter = c.character
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

RunService.RenderStepped:Connect(step)

Players.PlayerRemoving:Connect(destroyVisual)

--// ── public API (used by combat.lua kill all) ───────────────────
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
        for _, hl in pairs(v.highlights) do
            hl.FillColor = c
            hl.OutlineColor = c
        end
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
