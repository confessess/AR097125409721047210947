local function debugLog(prefix, ...)
    local args = { ... }
    local text = ""
    for i, v in ipairs(args) do
        if i > 1 then text = text .. " " end
        text = text .. tostring(v)
    end
    print("[" .. prefix .. "] " .. text)
end

local function loadModule(name)
    debugLog("BOOT", "Loading module:", name)

    if script and script.Parent then
        local moduleObject = script.Parent:FindFirstChild(name)
        if moduleObject then
            debugLog("BOOT", "Using local module:", name, "@", moduleObject:GetFullName())
            return require(moduleObject)
        end
    end

    local BASE = "https://raw.githubusercontent.com/confessess/AR097125409721047210947/main/"
    local source = game:HttpGet(BASE .. name .. ".lua")
    if type(source) ~= "string" or source == "" then
        error("Failed to fetch remote module " .. name .. ": empty or invalid source")
    end

    local compiler = loadstring or load
    if type(compiler) ~= "function" then
        error("Failed to load module " .. name .. ": no supported compiler available")
    end

    local chunk = compiler(source)
    if type(chunk) ~= "function" then
        error("Failed to compile remote module " .. name .. ": compiler returned nil")
    end

    local ok, result = pcall(function()
        return chunk()
    end)

    if not ok then
        error("Failed to execute remote module " .. name .. ": " .. tostring(result))
    end

    debugLog("BOOT", "Loaded remote module:", name)
    return result
end

print("[BOOT] Starting bootstrap")
local GuiModule = loadModule("gui")
local CombatModule = loadModule("combat")
local ESPModule = loadModule("esp")
local GunModsModule = loadModule("gunmods")
local MovementModule = loadModule("movement")
local WorldModule = loadModule("world")
local SkinChangerModule = loadModule("skinchanger")

print("[BOOT] Module states:", type(GuiModule), type(CombatModule), type(ESPModule), type(GunModsModule), type(MovementModule), type(WorldModule), type(SkinChangerModule))
if not GuiModule then error("GuiModule is nil after loadModule('gui')") end
if not CombatModule then error("CombatModule is nil after loadModule('combat')") end
if not ESPModule then error("ESPModule is nil after loadModule('esp')") end
if not GunModsModule then error("GunModsModule is nil after loadModule('gunmods')") end
if not MovementModule then error("MovementModule is nil after loadModule('movement')") end
if not WorldModule then error("WorldModule is nil after loadModule('world')") end
if not SkinChangerModule then error("SkinChangerModule is nil after loadModule('skinchanger')") end

local Gui = GuiModule:Init()
print("[BOOT] GUI created")

Gui:CreateTab("Combat", "Aimbot, silent aim, hitbox, kill all.")
Gui:CreateTab("Visuals", "ESP and world rendering.")
Gui:CreateTab("Weapon", "No recoil, no spread, rapid fire, infinite ammo, fast reload, viewmodel chams.")
Gui:CreateTab("Movement", "Speed, jump, and fly settings.")
Gui:CreateTab("Skin Changer", "Announcers, arms, and melee skins.")
Gui:CreateTab("World", "World modifications.")
Gui:CreateTab("Settings", "GUI preferences, keybinds, configs.")
print("[BOOT] Modules initialized")

print("[BOOT] Initializing modules")
CombatModule:Init(Gui)
ESPModule:Init(Gui)
GunModsModule:Init(Gui)
MovementModule:Init(Gui)
WorldModule:Init(Gui)
SkinChangerModule:Init(Gui)
print("[BOOT] Modules initialized")

--// CONFIG SYSTEM — automatic save/load
local CONFIG_PATH = "blackout_config.json"

local function SerializeConfig(config)
    local result = {}
    for k, v in pairs(config) do
        if typeof(v) == "EnumItem" then
            result[k] = {__enum = true, type = tostring(v.EnumType), name = v.Name}
        elseif typeof(v) == "Color3" then
            result[k] = {__color = true, r = v.R, g = v.G, b = v.B}
        elseif typeof(v) == "Vector3" then
            result[k] = {__vector = true, x = v.X, y = v.Y, z = v.Z}
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

local function SaveConfig()
    local allConfigs = {
        Combat = SerializeConfig(CombatModule.Config),
        ESP = SerializeConfig(ESPModule.Config),
        GunMods = SerializeConfig(GunModsModule.Config),
        Movement = SerializeConfig(MovementModule.Config),
    }

    local json = game:GetService("HttpService"):JSONEncode(allConfigs)

    if writefile then
        pcall(function()
            writefile(CONFIG_PATH, json)
        end)
    else
        if setclipboard then
            setclipboard(json)
        end
    end
end

local function LoadConfig()
    local json = nil

    if readfile then
        local success, content = pcall(function()
            return readfile(CONFIG_PATH)
        end)
        if success and content and #content > 0 then
            json = content
        end
    end

    if not json and getclipboard then
        local success, content = pcall(function()
            return getclipboard()
        end)
        if success and content and #content > 10 and content:find("{") then
            json = content
        end
    end

    if not json then
        return false
    end

    local success, configs = pcall(function()
        return game:GetService("HttpService"):JSONDecode(json)
    end)

    if not success or type(configs) ~= "table" then
        warn("[ENI] Invalid config data")
        return false
    end

    if configs.Combat then DeserializeConfig(configs.Combat, CombatModule.Config) end
    if configs.ESP then DeserializeConfig(configs.ESP, ESPModule.Config) end
    if configs.GunMods then DeserializeConfig(configs.GunMods, GunModsModule.Config) end
    if configs.Movement then DeserializeConfig(configs.Movement, MovementModule.Config) end

    return true
end

--// AUTO-LOAD config on startup
task.spawn(function()
    task.wait(1)
    LoadConfig()
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
        -- Clean shutdown: restore everything before destroying
        if GunModsModule.Config.ChamsEnabled then
            GunModsModule.Config.ChamsEnabled = false
        end
        Gui.ScreenGui:Destroy()
    end, y)

    y = g:CreateSection("Config", y + 10)
    y = g:CreateButton("Save Config", function()
        SaveConfig()
    end, y)
    y = g:CreateButton("Load Config", function()
        LoadConfig()
    end, y)

    g.Content = originalContent
end)