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
if ViewmodelCustomizerModule and type(ViewmodelCustomizerModule.Init) == "function" then
    ViewmodelCustomizerModule:Init(Gui)
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

local function BuildJson()
    local allConfigs = {
        Combat = SerializeConfig(CombatModule.Config),
        ESP = SerializeConfig(ESPModule.Config),
        GunMods = SerializeConfig(GunModsModule.Config),
        Movement = SerializeConfig(MovementModule.Config),
    }
    return game:GetService("HttpService"):JSONEncode(allConfigs)
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

    local okJson, json = pcall(BuildJson)
    if not okJson or not json then return false, "Could not build the config." end

    local okWrite = pcall(writefile, CONFIG_DIR .. "/" .. clean .. ".json", json)
    if not okWrite then return false, "Could not write the file." end

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

    if configs.Combat then DeserializeConfig(configs.Combat, CombatModule.Config) end
    if configs.ESP then DeserializeConfig(configs.ESP, ESPModule.Config) end
    if configs.GunMods then DeserializeConfig(configs.GunMods, GunModsModule.Config) end
    if configs.Movement then DeserializeConfig(configs.Movement, MovementModule.Config) end

    WriteLastPointer(clean)
    return true, "Loaded \"" .. clean .. "\"."
end

local function DeleteConfigNamed(name)
    local clean = SanitizeName(name)
    if not clean then return false, "Pick a config to delete." end
    if not delfile then return false, "Your executor has no delfile." end
    local ok = pcall(delfile, CONFIG_DIR .. "/" .. clean .. ".json")
    if not ok then return false, "Could not delete \"" .. clean .. "\"." end
    if ReadLastPointer() == clean then
        pcall(delfile, LAST_POINTER)
    end
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

--// restore the last used config on startup
task.spawn(function()
    task.wait(1)
    local last = ReadLastPointer()
    if last then
        LoadConfigNamed(last)
    elseif readfile then
        local ok, content = pcall(readfile, LEGACY_PATH)
        if ok and type(content) == "string" and #content > 10 then
            local okDecode, configs = pcall(function()
                return game:GetService("HttpService"):JSONDecode(content)
            end)
            if okDecode and type(configs) == "table" then
                if configs.Combat then DeserializeConfig(configs.Combat, CombatModule.Config) end
                if configs.ESP then DeserializeConfig(configs.ESP, ESPModule.Config) end
                if configs.GunMods then DeserializeConfig(configs.GunMods, GunModsModule.Config) end
                if configs.Movement then DeserializeConfig(configs.Movement, MovementModule.Config) end
            end
        end
    end
end)

--// Settings tab rebuild
Gui:SetTabRebuild("Settings", function(g)
    local scroll = g:CreateScrollContent()
    local originalContent = g.Content
    g.Content = scroll

    local y = g:CreateSection("GUI", 0)
    y = g:CreateKeybindSetting(y)
    y = g:CreateMouseUnlockToggle(y)
    y = g:CreateButton("Unload GUI", function()
        if GunModsModule.Config.ChamsEnabled then
            GunModsModule.Config.ChamsEnabled = false
        end
        Gui.ScreenGui:Destroy()
    end, y)

    y = g:CreateSection("Configs", y + 10)

    local saved = ListConfigs()
    if LoadedName and not table.find(saved, LoadedName) then
        LoadedName = nil
    end
    if not LoadedName and saved[1] then
        LoadedName = saved[1]
    end

    y = g:CreateTextInput("Config Name", ConfigName, "my config", function(value)
        ConfigName = value
    end, y)

    y = g:CreateButton("Save Config", function()
        local ok, message = SaveConfigNamed(ConfigName)
        RefreshSettings(message)
    end, y)

    if #saved > 0 then
        y = g:CreateDropdown("Saved Configs", saved, LoadedName, function(value)
            LoadedName = value
        end, y)

        y = g:CreateButton("Load Selected Config", function()
            local ok, message = LoadConfigNamed(LoadedName)
            RefreshSettings(message)
        end, y)

        y = g:CreateButton("Delete Selected Config", function()
            local ok, message = DeleteConfigNamed(LoadedName)
            if ok then LoadedName = nil end
            RefreshSettings(message)
        end, y)
    else
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 26)
        empty.Position = UDim2.fromOffset(0, y)
        empty.BackgroundTransparency = 1
        empty.Text = "No saved configs yet — name one above and hit Save."
        empty.TextColor3 = Color3.fromRGB(140, 165, 155)
        empty.TextSize = 11
        empty.Font = Enum.Font.Gotham
        empty.TextXAlignment = Enum.TextXAlignment.Left
        empty.ZIndex = 3
        empty.Parent = scroll
        y = y + 32
    end

    y = g:CreateButton("Refresh List", function()
        RefreshSettings(nil)
    end, y)

    if ConfigStatus then
        local status = Instance.new("TextLabel")
        status.Size = UDim2.new(1, 0, 0, 22)
        status.Position = UDim2.fromOffset(0, y)
        status.BackgroundTransparency = 1
        status.Text = ConfigStatus
        status.TextColor3 = Color3.fromRGB(111, 211, 162)
        status.TextSize = 11
        status.Font = Enum.Font.GothamMedium
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.ZIndex = 3
        status.Parent = scroll
    end

    g.Content = originalContent
end)
