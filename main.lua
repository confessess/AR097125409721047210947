local BASE = "https://raw.githubusercontent.com/confessess/88888asnd09an7ds0a897nwd0a8d7a208d7a2809d7aw98d79n8sa7nw982d7san98d7/main/"

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