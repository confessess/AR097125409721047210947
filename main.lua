local BASE = "https://raw.githubusercontent.com/confessess/AR097125409721047210947/main/"

local function LoadModule(fileName)
    local url = BASE .. fileName
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)

    if not ok or result == nil then
        warn("[ENI] Failed to load module: " .. fileName)
        return nil
    end

    return result
end

local GuiModule = LoadModule("gui.lua")
if not GuiModule or type(GuiModule.Init) ~= "function" then
    warn("[ENI] gui.lua did not return a valid module. Aborting hub init.")
    return
end

local CombatModule = LoadModule("combat.lua")
local ESPModule = LoadModule("esp.lua")
local GunModsModule = LoadModule("gunmods.lua")
local MovementModule = LoadModule("movement.lua")
local WorldModule = LoadModule("world.lua")
local SkinChangerModule = LoadModule("skinchanger.lua")
local ViewmodelCustomizerModule = LoadModule("weaponchanger.lua")

local Gui = GuiModule:Init()
if not Gui or type(Gui.CreateTab) ~= "function" then
    warn("[ENI] GUI failed to initialize. Aborting hub init.")
    return
end

Gui:CreateTab("Combat", "Aimbot, silent aim, hitbox, kill all.")
Gui:CreateTab("Visuals", "ESP and world rendering.")
Gui:CreateTab("Weapon", "No recoil, no spread, rapid fire, infinite ammo, fast reload, viewmodel chams.")
Gui:CreateTab("Movement", "Speed, jump, and fly settings.")
Gui:CreateTab("Skin Changer", "Announcers, arms, and melee skins.")
Gui:CreateTab("World", "World modifications.")
Gui:CreateTab("Settings", "GUI preferences, keybinds, configs.")

if CombatModule and type(CombatModule.Init) == "function" then
    CombatModule:Init(Gui)
end
if ESPModule and type(ESPModule.Init) == "function" then
    ESPModule:Init(Gui)
end
if GunModsModule and type(GunModsModule.Init) == "function" then
    GunModsModule:Init(Gui)
end
if MovementModule and type(MovementModule.Init) == "function" then
    MovementModule:Init(Gui)
end
if WorldModule and type(WorldModule.Init) == "function" then
    WorldModule:Init(Gui)
end
if SkinChangerModule and type(SkinChangerModule.Init) == "function" then
    SkinChangerModule:Init(Gui)
end

--// weaponchanger.lua registers its own "Viewmodel" tab; it is loaded but its
--// tab is removed here so the sidebar stays the original seven.
if ViewmodelCustomizerModule and type(ViewmodelCustomizerModule.Init) == "function" then
    ViewmodelCustomizerModule:Init(Gui)

    local vmTab = Gui:GetTab("Viewmodel")
    if vmTab then
        local button = Gui.TabButtons["Viewmodel"]
        if button and button.Button then button.Button:Destroy() end
        Gui.TabButtons["Viewmodel"] = nil
        for index, tab in ipairs(Gui.Tabs) do
            if tab == vmTab then
                table.remove(Gui.Tabs, index)
                break
            end
        end
        Gui:SwitchTab("Combat")
    end
end

--// ═══════════════════════════════════════════════════════════════
--//  CONFIG SYSTEM — named files in a folder
--// ═══════════════════════════════════════════════════════════════
local CONFIG_DIR = "blackout_configs"
local LAST_POINTER = CONFIG_DIR .. "/last.txt"
local LEGACY_PATH = "blackout_config.json"

local ConfigName = ""
local LoadedName = nil
local ConfigStatus = nil

local function ConfigOf(module)
    if module and type(module.Config) == "table" then return module.Config end
    return nil
end

local function EnsureConfigDir()
    if makefolder then pcall(makefolder, CONFIG_DIR) end
end

local function SanitizeName(name)
    local clean = tostring(name or "")
    clean = clean:gsub("^%s+", ""):gsub("%s+$", "")
    clean = clean:gsub("[^%w%-_ ]", "")
    clean = clean:gsub("%s+", " ")
    if clean == "" then return nil end
    if #clean > 40 then clean = clean:sub(1, 40) end
    return clean
end

local function ListConfigs()
    local names = {}
    if not listfiles then return names end
    EnsureConfigDir()
    local ok, files = pcall(listfiles, CONFIG_DIR)
    if ok and type(files) == "table" then
        for _, path in ipairs(files) do
            local base = tostring(path):match("([^/\\]+)%.json$")
            if base then table.insert(names, base) end
        end
    end
    table.sort(names)
    return names
end

local function SerializeConfig(config)
    local result = {}
    if type(config) ~= "table" then return result end
    for k, v in pairs(config) do
        if typeof(v) == "EnumItem" then
            result[k] = { __enum = true, type = tostring(v.EnumType), name = v.Name }
        elseif typeof(v) == "Color3" then
            result[k] = { __color = true, r = v.R, g = v.G, b = v.B }
        elseif typeof(v) == "Vector3" then
            result[k] = { __vector = true, x = v.X, y = v.Y, z = v.Z }
        else
            result[k] = v
        end
    end
    return result
end

local function DeserializeConfig(data, targetConfig)
    if type(data) ~= "table" or type(targetConfig) ~= "table" then return end
    for k, v in pairs(data) do
        if type(v) == "table" then
            if v.__enum then
                pcall(function() targetConfig[k] = Enum[v.type][v.name] end)
            elseif v.__color then
                targetConfig[k] = Color3.new(v.r, v.g, v.b)
            elseif v.__vector then
                targetConfig[k] = Vector3.new(v.x, v.y, v.z)
            else
                targetConfig[k] = v
            end
        else
            targetConfig[k] = v
        end
    end
end

local function ApplyConfigs(configs)
    if type(configs) ~= "table" then return false end
    local combat = ConfigOf(CombatModule)
    local esp = ConfigOf(ESPModule)
    local gunmods = ConfigOf(GunModsModule)
    local movement = ConfigOf(MovementModule)
    if combat and configs.Combat then DeserializeConfig(configs.Combat, combat) end
    if esp and configs.ESP then DeserializeConfig(configs.ESP, esp) end
    if gunmods and configs.GunMods then DeserializeConfig(configs.GunMods, gunmods) end
    if movement and configs.Movement then DeserializeConfig(configs.Movement, movement) end
    return true
end

local function WriteLastPointer(name)
    if not writefile then return end
    pcall(writefile, LAST_POINTER, name)
end

local function ReadLastPointer()
    if not readfile then return nil end
    local ok, content = pcall(readfile, LAST_POINTER)
    if ok and type(content) == "string" and content ~= "" then
        return SanitizeName(content)
    end
    return nil
end

local function SaveConfigNamed(name)
    local clean = SanitizeName(name)
    if not clean then return false, "Enter a config name first." end
    if not writefile then return false, "Your executor has no writefile." end

    EnsureConfigDir()

    local okBuild, json = pcall(function()
        return game:GetService("HttpService"):JSONEncode({
            Combat = SerializeConfig(ConfigOf(CombatModule)),
            ESP = SerializeConfig(ConfigOf(ESPModule)),
            GunMods = SerializeConfig(ConfigOf(GunModsModule)),
            Movement = SerializeConfig(ConfigOf(MovementModule)),
        })
    end)
    if not okBuild or type(json) ~= "string" then return false, "Could not build the config." end

    if not pcall(writefile, CONFIG_DIR .. "/" .. clean .. ".json", json) then
        return false, "Could not write the file."
    end

    WriteLastPointer(clean)
    return true, "Saved \"" .. clean .. "\"."
end

local function LoadConfigNamed(name)
    local clean = SanitizeName(name)
    if not clean then return false, "Pick a config to load." end
    if not readfile then return false, "Your executor has no readfile." end

    local okRead, content = pcall(readfile, CONFIG_DIR .. "/" .. clean .. ".json")
    if not okRead or type(content) ~= "string" or content == "" then
        return false, "\"" .. clean .. "\" was not found."
    end

    local okDecode, configs = pcall(function()
        return game:GetService("HttpService"):JSONDecode(content)
    end)
    if not okDecode or type(configs) ~= "table" then return false, "That file is not a valid config." end

    if not ApplyConfigs(configs) then return false, "That file is not a valid config." end

    WriteLastPointer(clean)
    return true, "Loaded \"" .. clean .. "\"."
end

local function DeleteConfigNamed(name)
    local clean = SanitizeName(name)
    if not clean then return false, "Pick a config to delete." end
    if not delfile then return false, "Your executor has no delfile." end
    if not pcall(delfile, CONFIG_DIR .. "/" .. clean .. ".json") then
        return false, "Could not delete \"" .. clean .. "\"."
    end
    if ReadLastPointer() == clean then pcall(delfile, LAST_POINTER) end
    return true, "Deleted \"" .. clean .. "\"."
end

local function RefreshSettings(status)
    ConfigStatus = status
    task.defer(function()
        if Gui.CurrentTab == "Settings" then
            Gui:SwitchTab("Settings")
        end
    end)
end

--// Name field, built inline so it does not depend on gui.lua having it
local ACCENT_GREEN = Color3.fromRGB(111, 211, 162)
local PANEL_DARK = Color3.fromRGB(19, 32, 27)
local TEXT_GRAY = Color3.fromRGB(140, 165, 155)

local function MakeNameField(parent, y, default, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.Position = UDim2.fromOffset(0, y)
    row.BackgroundTransparency = 1
    row.ZIndex = 3
    row.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -174, 0, 36)
    label.BackgroundTransparency = 1
    label.Text = "Config Name"
    label.TextColor3 = Color3.fromRGB(196, 226, 212)
    label.TextSize = 13
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 4
    label.Parent = row

    local box = Instance.new("TextBox")
    box.Size = UDim2.fromOffset(150, 28)
    box.Position = UDim2.new(1, -174, 0, 4)
    box.BackgroundColor3 = PANEL_DARK
    box.BorderSizePixel = 0
    box.Text = default or ""
    box.PlaceholderText = "my config"
    box.PlaceholderColor3 = Color3.fromRGB(96, 122, 110)
    box.TextColor3 = Color3.fromRGB(213, 233, 224)
    box.TextSize = 11
    box.Font = Enum.Font.GothamMedium
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.ZIndex = 4
    box.Parent = row

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(40, 78, 65)
    stroke.Thickness = 1
    stroke.Parent = box

    box.Focused:Connect(function()
        stroke.Color = ACCENT_GREEN
    end)
    box.FocusLost:Connect(function()
        stroke.Color = Color3.fromRGB(40, 78, 65)
        if onChange then onChange(box.Text) end
    end)
    box:GetPropertyChangedSignal("Text"):Connect(function()
        if onChange then onChange(box.Text) end
    end)

    return y + 42
end

local function MakeNote(parent, y, text, color)
    local note = Instance.new("TextLabel")
    note.Size = UDim2.new(1, 0, 0, 22)
    note.Position = UDim2.fromOffset(0, y)
    note.BackgroundTransparency = 1
    note.Text = text
    note.TextColor3 = color or TEXT_GRAY
    note.TextSize = 11
    note.Font = Enum.Font.Gotham
    note.TextXAlignment = Enum.TextXAlignment.Left
    note.TextWrapped = true
    note.ZIndex = 3
    note.Parent = parent
    return y + 26
end

--// restore the last used config on startup
task.spawn(function()
    task.wait(1)
    local last = ReadLastPointer()
    if last then
        pcall(LoadConfigNamed, last)
    elseif readfile then
        local ok, content = pcall(readfile, LEGACY_PATH)
        if ok and type(content) == "string" and #content > 10 then
            local okDecode, configs = pcall(function()
                return game:GetService("HttpService"):JSONDecode(content)
            end)
            if okDecode then pcall(ApplyConfigs, configs) end
        end
    end
end)

--// Settings tab rebuild
Gui:SetTabRebuild("Settings", function(g)
    local scroll = g:CreateScrollContent()
    local originalContent = g.Content
    g.Content = scroll

    local ok, err = pcall(function()
        local y = g:CreateSection("GUI", 0)
        y = g:CreateKeybindSetting(y)
        y = g:CreateMouseUnlockToggle(y)
        y = g:CreateButton("Unload GUI", function()
            if GunModsModule and GunModsModule.Config then
                GunModsModule.Config.ChamsEnabled = false
            end
            if Gui.ScreenGui then Gui.ScreenGui:Destroy() end
        end, y)

        y = g:CreateSection("Configs", y + 10)

        local saved = ListConfigs()
        if LoadedName and not table.find(saved, LoadedName) then
            LoadedName = nil
        end
        if not LoadedName and saved[1] then
            LoadedName = saved[1]
        end

        y = MakeNameField(scroll, y, ConfigName, function(value)
            ConfigName = value
        end)

        y = g:CreateButton("Save Config", function()
            local success, message = SaveConfigNamed(ConfigName)
            RefreshSettings(message)
        end, y)

        if #saved > 0 then
            y = g:CreateDropdown("Saved Configs", saved, LoadedName, function(value)
                LoadedName = value
            end, y)

            y = g:CreateButton("Load Selected Config", function()
                local success, message = LoadConfigNamed(LoadedName)
                RefreshSettings(message)
            end, y)

            y = g:CreateButton("Delete Selected Config", function()
                local success, message = DeleteConfigNamed(LoadedName)
                if success then LoadedName = nil end
                RefreshSettings(message)
            end, y)
        else
            y = MakeNote(scroll, y, "No saved configs yet — name one above and hit Save.")
        end

        y = g:CreateButton("Refresh List", function()
            RefreshSettings(nil)
        end, y)

        if ConfigStatus then
            MakeNote(scroll, y, ConfigStatus, ACCENT_GREEN)
        end
    end)

    if not ok then
        warn("[ENI] Settings tab build error: " .. tostring(err))
        local fallback = Instance.new("TextLabel")
        fallback.Size = UDim2.new(1, 0, 0, 22)
        fallback.Position = UDim2.fromOffset(0, 60)
        fallback.BackgroundTransparency = 1
        fallback.Text = "Settings failed to build — check the console."
        fallback.TextColor3 = Color3.fromRGB(255, 120, 120)
        fallback.TextSize = 11
        fallback.Font = Enum.Font.Gotham
        fallback.TextXAlignment = Enum.TextXAlignment.Left
        fallback.ZIndex = 3
        fallback.Parent = scroll
    end

    g.Content = originalContent
end)
