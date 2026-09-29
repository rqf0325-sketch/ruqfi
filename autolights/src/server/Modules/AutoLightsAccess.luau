-- ServerScriptService/AutoLightsServer/Modules/AutoLightsAccess.lua
-- Who may operate the show (AutoLights Control Panel, ShowEngine commands).
-- Rules, checked once per player and then cached:
--   • Roblox Studio: everyone (so you can test alone)
--   • CONTROL.PublicAccess = true: everyone
--   • the game owner (user, or the owner of the group that owns the game)
--   • CONTROL.UserIds, and members of CONTROL.GroupId with rank >= CONTROL.MinRank
-- Everything else is refused on the server; the panel only hides itself.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Access = {}

local cache = {} -- [Player] = boolean

local function controlSettings()
	local config = script.Parent.Parent:FindFirstChild("AutoLightsSyncConfig")
	local ok, settings = pcall(function()
		return config and require(config).CONTROL
	end)
	return if ok and type(settings) == "table" then settings else {}
end

local function isOwner(player)
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, info = pcall(GroupService.GetGroupInfoAsync, GroupService, game.CreatorId)
		return ok and type(info) == "table" and info.Owner ~= nil and info.Owner.Id == player.UserId
	end
	return game.CreatorId ~= 0 and player.UserId == game.CreatorId
end

local function compute(player)
	if RunService:IsStudio() then
		return true
	end
	local settings = controlSettings()
	if settings.PublicAccess == true then
		return true
	end
	if isOwner(player) then
		return true
	end
	if type(settings.UserIds) == "table" and table.find(settings.UserIds, player.UserId) then
		return true
	end
	local groupId = tonumber(settings.GroupId) or 0
	if groupId ~= 0 then
		local ok, rank = pcall(player.GetRankInGroup, player, groupId)
		if ok and rank >= (tonumber(settings.MinRank) or 1) then
			return true
		end
	end
	return false
end

-- May yield (group lookups).
function Access.IsOperator(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if cache[player] == nil then
		cache[player] = compute(player)
	end
	return cache[player]
end

function Access.Forget(player)
	cache[player] = nil
end

Players.PlayerRemoving:Connect(Access.Forget)

return Access
