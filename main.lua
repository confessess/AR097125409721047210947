local function loadModule(name)
    local candidates = {}
    if script then
        table.insert(candidates, script.Parent and script.Parent:FindFirstChild(name))
        table.insert(candidates, script.Parent and script.Parent.Parent and script.Parent.Parent:FindFirstChild(name))
    end

    local rep = game:GetService("ReplicatedStorage")
    local repoFolder = rep and rep:FindFirstChild("LightHub")
    if repoFolder then
        table.insert(candidates, repoFolder:FindFirstChild(name))
    end

    for _, candidate in ipairs(candidates) do
        if candidate and candidate:IsA("ModuleScript") then
            return require(candidate)
        end
    end

    local BASE = "https://raw.githubusercontent.com/confessess/AR097125409721047210947/main/"
    local ok, result = pcall(function()
        local source = game:HttpGet(BASE .. name .. ".lua")
        local compiled = loadstring(source)
        if not compiled then
            error("Remote source for " .. name .. " was empty or invalid")
        end
        return compiled()
    end)

    if not ok then
        error("Failed to load module " .. name .. ": " .. tostring(result))
    end

    return result
end

local GuiModule = loadModule("gui")
local CombatModule = loadModule("combat")
local ESPModule = loadModule("esp")
local GunModsModule = loadModule("gunmods")
local MovementModule = loadModule("movement")
local WorldModule = loadModule("world")
local SkinChangerModule = loadModule("skinchanger")

local Gui = GuiModule:Init()

Gui:CreateTab("Combat", "Aimbot, silent aim, hitbox, kill all.")
Gui:CreateTab("Visuals", "ESP and world rendering.")
Gui:CreateTab("Weapon", "No recoil, no spread, rapid fire, infinite ammo, fast reload, viewmodel chams.")
Gui:CreateTab("Movement", "Speed, jump, and fly settings.")
Gui:CreateTab("Skin Changer", "Announcers, arms, and melee skins.")
Gui:CreateTab("World", "World modifications.")
Gui:CreateTab("Settings", "GUI preferences, keybinds, configs.")

CombatModule:Init(Gui)
ESPModule:Init(Gui)
GunModsModule:Init(Gui)
MovementModule:Init(Gui)
WorldModule:Init(Gui)
SkinChangerModule:Init(Gui)

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