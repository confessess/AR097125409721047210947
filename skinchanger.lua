
local SkinChanger = {}
SkinChanger.__index = SkinChanger

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

--// ARMS LIST
local Arms = {
    "Delinquent", "1x1x1x1", "Monky With Drip", "Da Monky With Drip", "Alien",
    "Alien In Disguise", "Rabblerouser", "Ace Pilot",
    "BrickBattle", "John", "Castlers", "Phoenix", "Punk", "Red Panda",
    "Magician", "Froggy", "Mechanic", "Pizza Boy", "Garcello", "Bigfoot",
    "Noob", "Bloxxer", "Farmer", "Paintballer", "Shedletsky", "Soldier",
    "Agent", "Hazmat", "Seeker of Hearts", "Segg with Drip", "Christmas Nomad"
}

--// Z3US DATA
local Data = LocalPlayer:WaitForChild("Data")
local AnnouncerValue = Data:WaitForChild("Announcer")
local EquippedValue = LocalPlayer:WaitForChild("Equipped")

local Z3USAnnouncerList = {"None"}
for _, child in ipairs(ReplicatedStorage:WaitForChild("ItemData"):WaitForChild("Images"):WaitForChild("Announcers"):GetChildren()) do
    table.insert(Z3USAnnouncerList, child.Name)
end

local Z3USMeleeList = {"None"}
for _, child in ipairs(ReplicatedStorage:WaitForChild("Melees"):GetChildren()) do
    table.insert(Z3USMeleeList, child.Name)
end

local Z3USCamoList = {"None"}
for _, child in ipairs(ReplicatedStorage:WaitForChild("Skins"):GetChildren()) do
    table.insert(Z3USCamoList, child.Name)
end

--// ARMS FUNCTIONS
local function CacheArmOriginalNames(armsFolder)
    for _, child in ipairs(armsFolder:GetChildren()) do
        if not child:GetAttribute("ENI_OriginalName") and child.Name ~= "Temp" and child.Name ~= "Delinquent" then
            child:SetAttribute("ENI_OriginalName", child.Name)
        end
    end
end

local function ApplyArms(arm)
    pcall(function()
        local arms = ReplicatedStorage:WaitForChild("Viewmodels").Arms
        CacheArmOriginalNames(arms)
        for _, child in ipairs(arms:GetChildren()) do
            local originalName = child:GetAttribute("ENI_OriginalName") or child.Name
            child.Name = (originalName == arm) and "Delinquent" or "Temp"
        end
    end)
end

local function RevertArms()
    pcall(function()
        local arms = ReplicatedStorage:WaitForChild("Viewmodels").Arms
        CacheArmOriginalNames(arms)
        for _, child in ipairs(arms:GetChildren()) do
            local originalName = child:GetAttribute("ENI_OriginalName")
            child.Name = originalName or "Delinquent"
        end
    end)
end

--// Z3US FUNCTIONS
local function Z3USChangeAnnouncer(name)
    AnnouncerValue.Value = (name == "None") and "Default" or name
end

local function Z3USReplaceKnife(knifeName)
    if knifeName == "None" then return end
    local Viewmodels = ReplicatedStorage:WaitForChild("Viewmodels")
    local Images = ReplicatedStorage:WaitForChild("ItemData"):WaitForChild("Images"):WaitForChild("Melees")
    local KillIcons = ReplicatedStorage:WaitForChild("KillIcons")

    if Viewmodels:FindFirstChild("v_" .. knifeName) then
        if Viewmodels:FindFirstChild("v_Dagger") then Viewmodels.v_Dagger:Destroy() end
        task.wait()
        local newKnife = Viewmodels["v_" .. knifeName]:Clone()
        newKnife.Parent = Viewmodels
        newKnife.Name = "v_Dagger"
        if Images:FindFirstChild("Dagger") and Images:FindFirstChild(knifeName) then
            Images.Dagger.Quality.Value = Images[knifeName].Quality.Value
            Images.Dagger.Value = Images[knifeName].Value
        end
        if KillIcons:FindFirstChild("Dagger") and KillIcons:FindFirstChild(knifeName) then
            KillIcons.Dagger.Value = KillIcons[knifeName].Value
        end
    end
end

local function Z3USChangeCamo(name)
    EquippedValue.Value = (name == "None") and "" or name
end

local function Z3USToggleChatTag(tagName, enabled)
    if enabled then
        if not LocalPlayer:FindFirstChild(tagName) then Instance.new("IntValue", LocalPlayer).Name = tagName end
    else
        if LocalPlayer:FindFirstChild(tagName) then LocalPlayer[tagName]:Destroy() end
    end
end

--// GUI
function SkinChanger:Init(Gui)
    self.Gui = Gui
    Gui:SetTabRebuild("Skin Changer", function(g)
        local scroll = g:CreateScrollContent()
        local originalContent = g.Content
        g.Content = scroll

        local y = g:CreateSection("Arms Changer", 0)
        y = g:CreateDropdown("Arm Model", Arms, "Delinquent", ApplyArms, y)
        y = g:CreateButton("Revert Arms", RevertArms, y)

        y = g:CreateSection("Skin Changer", y + 10)
        y = g:CreateDropdown("Announcer", Z3USAnnouncerList, "None", Z3USChangeAnnouncer, y)
        y = g:CreateDropdown("Replace Knife", Z3USMeleeList, "None", Z3USReplaceKnife, y)
        y = g:CreateDropdown("Weapon Camo", Z3USCamoList, "None", Z3USChangeCamo, y)

        y = g:CreateSection("Chat Tags", y + 10)
        y = g:CreateToggle("Chad", false, function(s) Z3USToggleChatTag("IsChad", s) end, y)
        y = g:CreateToggle("VIP", false, function(s) Z3USToggleChatTag("VIP", s) end, y)
        y = g:CreateToggle("OldVIP", false, function(s) Z3USToggleChatTag("OldVIP", s) end, y)
        y = g:CreateToggle("Romin", false, function(s) Z3USToggleChatTag("Romin", s) end, y)
        y = g:CreateToggle("Admin", false, function(s) Z3USToggleChatTag("IsAdmin", s) end, y)

        g.Content = originalContent
    end)
    return self
end

return SkinChanger