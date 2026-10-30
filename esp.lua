--// ═══════════════════════════════════════════════════════════════
--//  MODULE: esp.lua
--//  Bounding box + full-body material chams + Billboard labels
--// ═══════════════════════════════════════════════════════════════
local ESP = {}
ESP.__index = ESP

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

ESP.Config = {
    Enabled = false,
    Boxes = false,
    Chams = false,
    Fill = false,
    Names = false,
    Health = false,
    Distance = false,
    Weapon = false,
    Tracers = false,
    TeamCheck = false,
    RenderDistance = 1000,
    Color = Color3.fromRGB(255, 0, 45),
    ChamsTransparency = 0,
    ChamsMaterial = "Neon",
    Debug = true,
}

local METERS_PER_STUD = 0.28

local Visuals = {}
local TracerFolder = nil
local ESPGui = nil

local Debug = { nextAt = 0, errors = {}, dumped = {} }

local function dbg(...)
    if not ESP.Config.Debug then return end
    print("[ENI ESP]", ...)
end

local function dbgError(key, err)
    if Debug.errors[key] then return end
    Debug.errors[key] = true
    warn("[ENI ESP] error in " .. key .. ": " .. tostring(err))
end

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

--// ── health ─────────────────────────────────────────────────────
--// The Humanoid is pinned at 100 in MM2, so real health has to come from the
--// replicated value objects. First container that has a usable value wins;
--// the humanoid is only a fallback.
local function healthContainers(player, character)
    local list = {}
    local function add(container, deep)
        if container then list[#list + 1] = { container = container, deep = deep } end
    end
    add(player:FindFirstChild("NRPBS"), true)
    add(character:FindFirstChild("NRPBS"), true)
    add(character:FindFirstChild("Status"), true)
    add(character:FindFirstChild("Health"), false)
    add(character, false)
    add(player:FindFirstChild("ScoreFolder"), true)
    add(player, false)
    return list
end

local function findNumberValue(container, names, deep)
    local function match(holder)
        for _, name in ipairs(names) do
            local v = holder:FindFirstChild(name)
            if v and v:IsA("ValueBase") and typeof(v.Value) == "number" then
                return v
            end
        end
        return nil
    end

    local direct = match(container)
    if direct then return direct end
    if not deep then return nil end

    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") then
            local nested = match(child)
            if nested then return nested end
        end
    end
    return nil
end

local function readHealth(player, character, humanoid)
    local containers = healthContainers(player, character)

    local maxValue, curValue
    for _, entry in ipairs(containers) do
        maxValue = findNumberValue(entry.container, { "MaxHealth", "OMaxHealth" }, entry.deep)
        if maxValue then break end
    end
    for _, entry in ipairs(containers) do
        curValue = findNumberValue(entry.container, { "Health", "OMaxHealth" }, entry.deep)
        if curValue then break end
    end

    local max = (maxValue and maxValue.Value)
        or (humanoid and humanoid.MaxHealth)
        or (character:GetAttribute("MaxHealth"))
        or 100
    max = math.max(1, max)

    local current = (curValue and curValue.Value)
        or character:GetAttribute("Health")
        or (humanoid and humanoid.Health)
        or max

    if current > max then max = current end

    return math.clamp(current, 0, max), max
end

--// remote weapons are not always a Tool child; walk every plausible holder
local function readWeapon(player, character)
    local tool = character:FindFirstChildOfClass("Tool")
    if tool then return tool.Name end

    local gun = character:FindFirstChild("Gun")
    if gun then
        if gun:IsA("Model") then return gun.Name end
        local parentModel = gun.Parent
        if parentModel and parentModel:IsA("Model") and parentModel.Name ~= player.Name then
            return parentModel.Name
        end
        return "Gun"
    end

    for _, child in ipairs(character:GetChildren()) do
        if child.Name:sub(1, 6) == "HWRAP_" then
            local g = child:FindFirstChild("Gun")
            return g and g.Name or child.Name
        end
    end

    for _, name in ipairs({ "Backpack", "PlayerGui" }) do
        local holder = player:FindFirstChild(name)
        if holder then
            local t = holder:FindFirstChildOfClass("Tool")
            if t then return t.Name end
        end
    end

    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name:sub(1, 6) == "HWRAP_" then
            local g = obj:FindFirstChild("Gun")
            if g then return g.Name end
        end
    end

    return nil
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
    if not Drawing then return nil end
    local ok, d = pcall(function()
        local s = Drawing.new("Square")
        s.Filled = filled
        s.Thickness = 1
        s.Transparency = 1
        s.Color = ESP.Config.Color
        s.Visible = false
        return s
    end)
    return ok and d or nil
end

local function destroyVisual(player)
    local v = Visuals[player]
    if not v then return end
    Visuals[player] = nil
    if v.billboard then pcall(function() v.billboard:Destroy() end) end
    if v.tracer then pcall(function() v.tracer:Destroy() end) end
    if v.tracerAttachment then pcall(function() v.tracerAttachment:Destroy() end) end
    if v.box then pcall(function() v.box:Remove() end) end
    if v.fill then pcall(function() v.fill:Remove() end) end
end

local function clearAll()
    for player in pairs(Visuals) do destroyVisual(player) end
    clearSourceAttachment()
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
        box = newSquare(false),
        fill = newSquare(true),
        chamData = {},
        chamCharacter = nil,
        billboard = billboard,
        label = label,
        tracer = tracer,
        tracerAttachment = nil,
        tracerCharacter = nil,
    }
    Visuals[player] = v
    return v
end

--// ── single bounding box for the whole character ────────────────
local function characterScreenRect(character, cam)
    local cf, size
    local ok = pcall(function()
        local c, s = character:GetBoundingBox()
        cf, size = c, s
    end)
    if not ok or not cf then return nil end

    local top = cf.Position + Vector3.new(0, size.Y * 0.5, 0)
    local bottom = cf.Position - Vector3.new(0, size.Y * 0.5, 0)

    local topScreen = cam:WorldToViewportPoint(top)
    local bottomScreen = cam:WorldToViewportPoint(bottom)
    if topScreen.Z <= 0 or bottomScreen.Z <= 0 then return nil end

    local height = math.abs(bottomScreen.Y - topScreen.Y)
    if height < 4 then return nil end
    local width = height * 0.5
    local centerX = (topScreen.X + bottomScreen.X) * 0.5

    return Vector2.new(centerX - width * 0.5, math.min(topScreen.Y, bottomScreen.Y)),
        Vector2.new(width, height)
end

--// ── chams over every body part ─────────────────────────────────
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
    for decal, transparency in pairs(v.chamDecals or {}) do
        if decal and decal.Parent then
            pcall(function() decal.Transparency = transparency end)
        end
    end
    for appearance, data in pairs(v.chamAppearances or {}) do
        if appearance and appearance.Parent then
            pcall(function()
                appearance.Color = data.Color
                appearance.Transparency = data.Transparency
            end)
        end
    end
    v.chamData = {}
    v.chamDecals = {}
    v.chamAppearances = {}
    v.chamCharacter = nil
end

local function collectChamTargets(character)
    local parts, decals, appearances = {}, {}, {}
    for _, obj in ipairs(character:GetDescendants()) do
        if obj:IsA("BasePart") then
            parts[#parts + 1] = obj
        elseif obj:IsA("Decal") or obj:IsA("Texture") then
            decals[#decals + 1] = obj
        elseif obj:IsA("SurfaceAppearance") then
            appearances[#appearances + 1] = obj
        end
    end
    return parts, decals, appearances
end

local function applyChamMaterial(part, mat)
    part.Material = mat
    part.Color = ESP.Config.Color
    part.Transparency = ESP.Config.ChamsTransparency
    --// LTM composes on top of Transparency, so it must be cleared or the
    --// part stays see-through regardless of the slider
    part.LocalTransparencyModifier = 0
end

local function syncChams(v, character, enabled)
    v.chamDecals = v.chamDecals or {}
    v.chamAppearances = v.chamAppearances or {}

    if v.chamCharacter ~= character then
        clearChams(v)
        if enabled and character then
            v.chamCharacter = character
            local mat = Enum.Material[ESP.Config.ChamsMaterial] or Enum.Material.Neon
            local parts, decals, appearances = collectChamTargets(character)

            for _, part in ipairs(parts) do
                v.chamData[part] = {
                    Material = part.Material,
                    Color = part.Color,
                    Transparency = part.Transparency,
                    LocalTransparencyModifier = part.LocalTransparencyModifier,
                }
                applyChamMaterial(part, mat)
            end

            --// SurfaceAppearance overrides Material/Color, so tint it too
            for _, appearance in ipairs(appearances) do
                v.chamAppearances[appearance] = {
                    Color = appearance.Color,
                    Transparency = appearance.Transparency,
                }
                pcall(function()
                    appearance.Color = ESP.Config.Color
                    appearance.Transparency = 0
                end)
            end

            --// faces / textures sit on top of the body, hide them for clean chams
            for _, decal in ipairs(decals) do
                v.chamDecals[decal] = decal.Transparency
                pcall(function() decal.Transparency = 1 end)
            end
        end
        return
    end

    if not enabled then
        if next(v.chamData) or next(v.chamDecals) or next(v.chamAppearances) then
            clearChams(v)
        end
        return
    end

    local mat = Enum.Material[ESP.Config.ChamsMaterial] or Enum.Material.Neon
    for part in pairs(v.chamData) do
        if part.Parent then
            if part.Material ~= mat
                or part.Color ~= ESP.Config.Color
                or part.Transparency ~= ESP.Config.ChamsTransparency
                or part.LocalTransparencyModifier ~= 0 then
                applyChamMaterial(part, mat)
            end
        else
            v.chamData[part] = nil
        end
    end
    for appearance in pairs(v.chamAppearances) do
        if not appearance.Parent then
            v.chamAppearances[appearance] = nil
        end
    end
    for decal in pairs(v.chamDecals) do
        if not decal.Parent then
            v.chamDecals[decal] = nil
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
        for _, v in pairs(Visuals) do
            if v.box then v.box.Visible = false end
            if v.fill then v.fill.Visible = false end
            if v.billboard then v.billboard.Enabled = false; v.billboard.Adornee = nil end
            if v.tracer then v.tracer.Enabled = false end
            if next(v.chamData) then clearChams(v) end
        end
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

    local wkspc = ReplicatedStorage:FindFirstChild("wkspc")
    local ffa = wkspc and wkspc:FindFirstChild("FFA")
    local isFFA = ffa and ffa.Value

    local hex = colorHex(cfg.Color)
    local readyCount = 0
    local report = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local v = createVisual(player)
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local head = character and character:FindFirstChild("Head")
            local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")

            local reason = nil
            if not character then
                reason = "no character"
            elseif not root then
                reason = "no root"
            elseif not humanoid then
                reason = "no humanoid"
            elseif humanoid.Health <= 0 then
                reason = "dead"
            end

            local studs = math.huge
            if not reason then
                if localRoot then
                    studs = (root.Position - localRoot.Position).Magnitude
                else
                    reason = "no local root"
                end
            end
            if not reason and cfg.TeamCheck and not isFFA
                and LocalPlayer.Team ~= nil
                and player.Team == LocalPlayer.Team then
                reason = "same team"
            end
            if not reason and studs > cfg.RenderDistance then
                reason = string.format("too far (%.0f)", studs)
            end

            local ready = reason == nil
            if ready then readyCount = readyCount + 1 end
            report[#report + 1] = string.format("%s: %s", player.Name, reason or "READY")

            if ready then
                local rect, size = nil, nil
                if cfg.Boxes or cfg.Fill then
                    local okRect, r, s = pcall(characterScreenRect, character, cam)
                    if okRect then rect, size = r, s end
                end

                if v.box then
                    if rect and cfg.Boxes then
                        v.box.Position = rect
                        v.box.Size = size
                        v.box.Color = cfg.Color
                        v.box.Visible = true
                    else
                        v.box.Visible = false
                    end
                end
                if v.fill then
                    if rect and cfg.Fill then
                        v.fill.Position = rect
                        v.fill.Size = size
                        v.fill.Color = cfg.Color
                        v.fill.Transparency = 0.6
                        v.fill.Visible = true
                    else
                        v.fill.Visible = false
                    end
                end

                local okChams, chamsErr = pcall(syncChams, v, character, cfg.Chams)
                if not okChams then dbgError("syncChams", chamsErr) end

                v.billboard.Adornee = head

                local meters = studs * METERS_PER_STUD
                local lines = {}
                if cfg.Names then
                    lines[#lines + 1] = '<font color="' .. hex .. '"><b>'
                        .. escapeRichText(player.DisplayName) .. '</b></font>'
                end
                if cfg.Health then
                    local cur, max = readHealth(player, character, humanoid)
                    local ratio = math.clamp(cur / max, 0, 1)
                    lines[#lines + 1] = '<font color="#AEB9C2">HP </font>'
                        .. '<font color="' .. healthColor(ratio) .. '"><b>'
                        .. math.floor(cur + 0.5) .. '</b></font>'
                        .. '<font color="#AEB9C2">/</font>'
                        .. '<font color="#55DDFF"><b>' .. math.floor(max + 0.5) .. '</b></font>'
                end
                if cfg.Weapon then
                    local weapon = readWeapon(player, character)
                    if not weapon and cfg.Debug and not Debug.dumped[player] then
                        Debug.dumped[player] = true
                        local names = {}
                        for _, c in ipairs(character:GetChildren()) do
                            names[#names + 1] = c.Name .. "(" .. c.ClassName .. ")"
                        end
                        dbg("children of " .. player.Name .. ": " .. table.concat(names, ", "))
                    end
                    lines[#lines + 1] = '<font color="#E7EDF2">'
                        .. escapeRichText(weapon or "None") .. '</font>'
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
                if v.box then v.box.Visible = false end
                if v.fill then v.fill.Visible = false end
                if next(v.chamData) then clearChams(v) end
                v.billboard.Enabled = false
                v.tracer.Enabled = false
            end
        end
    end

    local now = os.clock()
    if cfg.Debug and now >= Debug.nextAt then
        Debug.nextAt = now + 2
        dbg(string.format("players=%d ready=%d drawing=%s ffa=%s",
            #Players:GetPlayers() - 1, readyCount, tostring(Drawing ~= nil), tostring(isFFA)))
        for i = 1, math.min(#report, 8) do dbg("  " .. report[i]) end
        local self = LocalPlayer:FindFirstChild("NRPBS")
        local h = self and self:FindFirstChild("Health")
        dbg("  self NRPBS.Health = " .. tostring(h and h.Value))
    end
end

RunService.RenderStepped:Connect(function()
    local ok, err = pcall(step)
    if not ok then dbgError("step", err) end
end)

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
        if v.box then v.box.Color = c end
        if v.fill then v.fill.Color = c end
    end
end

local CHAM_MATERIALS = {
    "Neon", "ForceField", "Glass", "SmoothPlastic", "Metal", "Plastic",
    "Marble", "Granite", "Foil", "Ice", "DiamondPlate", "CorrodedMetal",
}

function ESP:Init(Gui)
    self.Gui = Gui
    Gui:SetTabRebuild("Visuals", function(g)
        local scroll = g:CreateScrollContent()
        local originalContent = g.Content
        g.Content = scroll

        local ok, err = pcall(function()
            local y = g:CreateSection("ESP", 0)
            y = g:CreateToggle("Enabled", ESP.Config.Enabled, function(s)
                ESP.Config.Enabled = s
                if not s then clearAll() end
            end, y)
            y = g:CreateToggle("Boxes", ESP.Config.Boxes, function(s) ESP.Config.Boxes = s end, y)
            y = g:CreateToggle("Fill", ESP.Config.Fill, function(s) ESP.Config.Fill = s end, y)
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
            y = g:CreateToggle("Debug", ESP.Config.Debug, function(s) ESP.Config.Debug = s end, y)

            y = g:CreateSection("Chams", y + 10)
            y = g:CreateDropdown("Material", CHAM_MATERIALS, ESP.Config.ChamsMaterial, function(v)
                ESP.Config.ChamsMaterial = v
            end, y)
            y = g:CreateSlider("Chams Transparency", 0, 90, math.floor(ESP.Config.ChamsTransparency * 100), function(v)
                ESP.Config.ChamsTransparency = v / 100
            end, y)

            y = g:CreateSection("ESP Color", y + 10)
            y = g:CreateColorPicker("Color", ESP.Config.Color, function(c) ESP.SetColor(c) end, y)
        end)

        if not ok then
            warn("[ENI ESP] Visuals tab build error: " .. tostring(err))
        end

        g.Content = originalContent
    end)
    return self
end

return ESP
