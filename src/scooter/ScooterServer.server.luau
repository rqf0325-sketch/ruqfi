--[[
	Scooter — server (Tool > ScooterServer)

	  * Joins the scooter to the rider's HumanoidRootPart when the tool is
	    equipped (Body.Root.Mount), so every player sees it under the rider's
	    feet. The owner's ScooterClient does the same locally right away.
	  * Paints the scooter in the owner's theme and handles SetTheme: only
	    the owner, only theme names listed in Settings.Themes.

	A Script in a Tool starts the first time the tool is equipped (not while
	it sits in the Backpack), so the first equip is handled at startup too.
]]

local Players = game:GetService("Players")

local tool = script.Parent
local settings = require(tool:WaitForChild("Settings"))
local Shared = require(tool:WaitForChild("ScooterShared"))
local body = tool:WaitForChild("Body")
local mount = body:WaitForChild("Root"):WaitForChild("Mount")
local setTheme = tool:WaitForChild("SetTheme")

local function owner()
	local parent = tool.Parent
	if parent and parent:IsA("Backpack") then
		return parent.Parent
	end
	return parent and Players:GetPlayerFromCharacter(parent)
end

local function paint(name)
	if body:GetAttribute("Theme") ~= name or not settings.Themes[name] then
		Shared.applyTheme(body, settings, name)
	end
end

local function attach()
	local character = tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if not rootPart then
		return
	end
	mount.C0 = Shared.mountOffset(humanoid, rootPart, humanoid.HipHeight)
	mount.Part0 = rootPart
end

tool.Equipped:Connect(attach)
tool.Unequipped:Connect(function()
	mount.Part0 = nil
end)

local lastChange = 0
setTheme.OnServerEvent:Connect(function(player, name)
	if not settings.PlayersCanChangeTheme or player ~= owner() then
		return
	end
	if type(name) ~= "string" or not settings.Themes[name] or os.clock() - lastChange < 0.2 then
		return
	end
	lastChange = os.clock()
	player:SetAttribute("ScooterTheme", name) -- remembered for the next scooter after respawning
	paint(name)
end)

local player = owner()
paint(settings.PlayersCanChangeTheme and player and player:GetAttribute("ScooterTheme") or settings.Theme)
if tool.Parent and tool.Parent:FindFirstChildOfClass("Humanoid") then
	attach()
end
