
local World = {}
World.__index = World

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

World.Config = {
    FullBright = false,
    NoFog = false,
    CustomTime = false,
    TimeOfDay = 12,
    ModCheck = false,
    CustomSkybox = false,
    SelectedSkybox = "None",
}

--//  SKYBOX DATA
local Skyboxes = {
    ["Purple Nebula"] = {
        SkyboxBk = "rbxassetid://159454299",
        SkyboxDn = "rbxassetid://159454296",
        SkyboxFt = "rbxassetid://159454293",
        SkyboxLf = "rbxassetid://159454286",
        SkyboxRt = "rbxassetid://159454300",
        SkyboxUp = "rbxassetid://159454288"
    },
    ["Night Sky"] = {
        SkyboxBk = "rbxassetid://12064107",
        SkyboxDn = "rbxassetid://12064152",
        SkyboxFt = "rbxassetid://12064121",
        SkyboxLf = "rbxassetid://12063984",
        SkyboxRt = "rbxassetid://12064115",
        SkyboxUp = "rbxassetid://12064131"
    },
    ["Pink Daylight"] = {
        SkyboxBk = "rbxassetid://271042516",
        SkyboxDn = "rbxassetid://271077243",
        SkyboxFt = "rbxassetid://271042556",
        SkyboxLf = "rbxassetid://271042310",
        SkyboxRt = "rbxassetid://271042467",
        SkyboxUp = "rbxassetid://271077958"
    },
    ["Morning Glow"] = {
        SkyboxBk = "rbxassetid://1417494030",
        SkyboxDn = "rbxassetid://1417494146",
        SkyboxFt = "rbxassetid://1417494253",
        SkyboxLf = "rbxassetid://1417494402",
        SkyboxRt = "rbxassetid://1417494499",
        SkyboxUp = "rbxassetid://1417494643"
    },
    ["Minecraft"] = {
        SkyboxBk = "rbxassetid://1876545003",
        SkyboxDn = "rbxassetid://1876544331",
        SkyboxFt = "rbxassetid://1876542941",
        SkyboxLf = "rbxassetid://1876543392",
        SkyboxRt = "rbxassetid://1876543764",
        SkyboxUp = "rbxassetid://1876544642"
    },
    ["Chill"] = {
        SkyboxBk = "rbxassetid://5084575798",
        SkyboxDn = "rbxassetid://5084575916",
        SkyboxFt = "rbxassetid://5103949679",
        SkyboxLf = "rbxassetid://5103948542",
        SkyboxRt = "rbxassetid://5103948784",
        SkyboxUp = "rbxassetid://5084576400"
    },
    ["Setting Sun"] = {
        SkyboxBk = "rbxassetid://626460377",
        SkyboxDn = "rbxassetid://626460216",
        SkyboxFt = "rbxassetid://626460513",
        SkyboxLf = "rbxassetid://626473032",
        SkyboxRt = "rbxassetid://626458639",
        SkyboxUp = "rbxassetid://626460625"
    },
    ["Fade Blue"] = {
        SkyboxBk = "rbxassetid://153695414",
        SkyboxDn = "rbxassetid://153695352",
        SkyboxFt = "rbxassetid://153695452",
        SkyboxLf = "rbxassetid://153695320",
        SkyboxRt = "rbxassetid://153695383",
        SkyboxUp = "rbxassetid://153695471"
    },
    ["Twilight"] = {
        SkyboxBk = "rbxassetid://264908339",
        SkyboxDn = "rbxassetid://264907909",
        SkyboxFt = "rbxassetid://264909420",
        SkyboxLf = "rbxassetid://264909758",
        SkyboxRt = "rbxassetid://264908886",
        SkyboxUp = "rbxassetid://264907379"
    },
    ["Elegant Morning"] = {
        SkyboxBk = "rbxassetid://153767241",
        SkyboxDn = "rbxassetid://153767216",
        SkyboxFt = "rbxassetid://153767266",
        SkyboxLf = "rbxassetid://153767200",
        SkyboxRt = "rbxassetid://153767231",
        SkyboxUp = "rbxassetid://153767288"
    },
    ["Neptune"] = {
        SkyboxBk = "rbxassetid://218955819",
        SkyboxDn = "rbxassetid://218953419",
        SkyboxFt = "rbxassetid://218954524",
        SkyboxLf = "rbxassetid://218958493",
        SkyboxRt = "rbxassetid://218957134",
        SkyboxUp = "rbxassetid://218950090"
    },
    ["Redshift"] = {
        SkyboxBk = "rbxassetid://401664839",
        SkyboxDn = "rbxassetid://401664862",
        SkyboxFt = "rbxassetid://401664960",
        SkyboxLf = "rbxassetid://401664881",
        SkyboxRt = "rbxassetid://401664901",
        SkyboxUp = "rbxassetid://401664936"
    },
    ["Aesthetic Night"] = {
        SkyboxBk = "rbxassetid://1045964490",
        SkyboxDn = "rbxassetid://1045964368",
        SkyboxFt = "rbxassetid://1045964655",
        SkyboxLf = "rbxassetid://1045964655",
        SkyboxRt = "rbxassetid://1045964655",
        SkyboxUp = "rbxassetid://1045962969"
    }
}

local skyboxConnection = nil

local function ApplySkybox(skyboxName)
    if skyboxConnection then
        skyboxConnection:Disconnect()
        skyboxConnection = nil
    end

    if skyboxName == "None" then
        -- Restore default skybox
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Sky") and child.Name == "override" then
                child:Destroy()
            end
        end
        return
    end

    local skyboxData = Skyboxes[skyboxName]
    if not skyboxData then return end

    skyboxConnection = RunService.Heartbeat:Connect(function()
        -- Remove existing override skyboxes
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Sky") and child.Name == "override" then
                child:Destroy()
            end
        end

        -- Create new skybox
        local sky = Instance.new("Sky")
        sky.Name = "override"
        sky.SkyboxBk = skyboxData.SkyboxBk
        sky.SkyboxDn = skyboxData.SkyboxDn
        sky.SkyboxFt = skyboxData.SkyboxFt
        sky.SkyboxLf = skyboxData.SkyboxLf
        sky.SkyboxRt = skyboxData.SkyboxRt
        sky.SkyboxUp = skyboxData.SkyboxUp
        sky.Parent = Lighting
    end)

    
end

--// FullBright
local function ApplyFullBright()
    if World.Config.FullBright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.FogStart = 100000
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    end
end

RunService.RenderStepped:Connect(function()
    if World.Config.FullBright then
        ApplyFullBright()
    end
end)

--//  REDEEM ALL CODES
local function RedeemAllCodes()
    local codes = {
        "POG", "BLOXY", "xonae", "JOHN", "POKE", "CBROX", "EPRIKA",
        "FLAMINGO", "PET", "ANNA", "Bandites", "F00LISH", "E",
        "GARCELLO", "KITTEN", "Enforcer"
    }
    for _, code in ipairs(codes) do
        pcall(function()
            ReplicatedStorage.Redeem:InvokeServer(code)
        end)
        task.wait(0.1)
    end
   
end

--//  MOD CHECK
local MOD_GROUP_ID = 2613928

Players.PlayerAdded:Connect(function(player)
    if World.Config.ModCheck and player:IsInGroup(MOD_GROUP_ID) then
        local role = player:GetRoleInGroup(MOD_GROUP_ID)
        if role == "Game Moderators" or role == "Moderator" or role == "Admin" then
            LocalPlayer:Kick("Moderator joined: " .. player.Name)
        end
    end
end)

--// GUI
function World:Init(Gui)
    self.Gui = Gui

    Gui:SetTabRebuild("World", function(g)
        local scroll = g:CreateScrollContent()
        local originalContent = g.Content
        g.Content = scroll

        local y = g:CreateSection("Lighting", 0)
        y = g:CreateToggle("FullBright", World.Config.FullBright, function(state)
            World.Config.FullBright = state
            if not state then
                Lighting.Brightness = 1
                Lighting.ClockTime = World.Config.TimeOfDay
                Lighting.FogEnd = 500
                Lighting.FogStart = 0
                Lighting.Ambient = Color3.fromRGB(70, 70, 70)
                Lighting.OutdoorAmbient = Color3.fromRGB(70, 70, 70)
            end
        end, y)
        y = g:CreateToggle("No Fog", World.Config.NoFog, function(state)
            World.Config.NoFog = state
            Lighting.FogEnd = state and 100000 or 500
        end, y)
        y = g:CreateToggle("Custom Time", World.Config.CustomTime, function(state)
            World.Config.CustomTime = state
        end, y)
        y = g:CreateSlider("Time of Day", 0, 24, World.Config.TimeOfDay, function(val)
            World.Config.TimeOfDay = val
            if World.Config.CustomTime then
                Lighting.ClockTime = val
            end
        end, y)

        --  Custom Skyboxes
        y = g:CreateSection("Custom Skybox", y + 10)

        local skyboxNames = {"None", "Purple Nebula", "Night Sky", "Pink Daylight", "Morning Glow", "Minecraft", "Chill", "Setting Sun", "Fade Blue", "Twilight", "Elegant Morning", "Neptune", "Redshift", "Aesthetic Night"}

        y = g:CreateDropdown("Skybox", skyboxNames, "None", function(val)
            World.Config.SelectedSkybox = val
            if World.Config.CustomSkybox then
                ApplySkybox(val)
            end
        end, y)

        y = g:CreateToggle("Enable Custom Skybox", false, function(state)
            World.Config.CustomSkybox = state
            if state then
                ApplySkybox(World.Config.SelectedSkybox)
            else
                ApplySkybox("None")
            end
        end, y)

        --  Misc Features
        y = g:CreateSection(" Misc", y + 10)

        y = g:CreateButton("Redeem All Codes", function()
            RedeemAllCodes()
        end, y)

        y = g:CreateToggle("Mod Check", false, function(state)
            World.Config.ModCheck = state
        end, y)

        g.Content = originalContent
    end)

    
    return self
end

return World
