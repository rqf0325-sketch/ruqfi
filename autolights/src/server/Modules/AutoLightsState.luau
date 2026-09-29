-- ServerScriptService/AutoLightsServer/Modules/AutoLightsState.lua
-- The on/off switches of the AutoLights Control Panel. They live as attributes on
-- ReplicatedStorage.AutoLights, so every script (and every client) reads the same value:
--   SyncEnabled       beat sync drives the lights            (default true)
--   DanceFloorEnabled the dance floor tiles are active       (default true)
--   PyroEnabled       pyro / smoke / confetti may fire       (default true)
-- A switch that was never set counts as ON.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = {}

function State.Root()
	return ReplicatedStorage:FindFirstChild("AutoLights")
end

function State.Get(key, default)
	local root = State.Root()
	local value = root and root:GetAttribute(key)
	if value == nil then
		return default
	end
	return value
end

function State.Set(key, value)
	local root = State.Root()
	if root then
		root:SetAttribute(key, value)
	end
end

function State.SyncEnabled()
	return State.Get("SyncEnabled", true) ~= false
end

function State.DanceFloorEnabled()
	return State.Get("DanceFloorEnabled", true) ~= false
end

function State.PyroEnabled()
	return State.Get("PyroEnabled", true) ~= false
end

return State
