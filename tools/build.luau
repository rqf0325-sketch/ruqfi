--[[
	Builds the Studio model files from src/:

	  StarterGui/VehicleSpawnerGui.rbxmx          GUI + VehicleSpawnerClient (LocalScript)
	  ReplicatedStorage/VehicleSpawner.rbxmx      Config (ModuleScript) + Remotes
	  ServerScriptService/VehicleSpawnerServer.rbxmx

	  lune run tools/build.luau
	  lune run tools/build.luau -- --tree   (also writes build/tree.json for tools/preview)

	The bike model is built separately by tools/patch-road-glide.luau.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local dump = require("./lib/dump")

local Instance = roblox.Instance

local function write(path, instance)
	fs.writeFile(path, roblox.serializeModel({ instance }, true))
	print(`Wrote {path} ({#instance:GetDescendants() + 1} instances)`)
end

local function script(className, name, source, parent)
	local instance = Instance.new(className)
	instance.Name = name
	instance.Source = fs.readFile(source)
	instance.Parent = parent
	return instance
end

-- GUI: run the builder with Lune's Roblox types standing in for Studio's.
local env = setmetatable({
	game = Instance.new("DataModel"),
	Instance = Instance,
	Enum = roblox.Enum,
	Font = roblox.Font,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
}, { __index = getfenv(1) })

-- Runs a GUI builder from src/gui and attaches its LocalScript.
local function buildGui(source, clientName, clientSource)
	local gui = luau.load(fs.readFile(source), { debugName = source, environment = env })()
	gui.Parent = nil
	script("LocalScript", clientName, clientSource, gui)
	return gui
end

local gui = buildGui("src/gui/VehicleSpawnerGui.luau", "VehicleSpawnerClient", "src/client/VehicleSpawnerClient.luau")

fs.writeDir("StarterGui")
write("StarterGui/VehicleSpawnerGui.rbxmx", gui)

-- ReplicatedStorage.VehicleSpawner
local shared = Instance.new("Folder")
shared.Name = "VehicleSpawner"
script("ModuleScript", "Config", "src/shared/Config.luau", shared)
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = shared
for _, name in { "SpawnVehicle", "DespawnVehicle" } do
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = remotes
end

fs.writeDir("ReplicatedStorage")
write("ReplicatedStorage/VehicleSpawner.rbxmx", shared)

-- ServerScriptService.VehicleSpawnerServer
fs.writeDir("ServerScriptService")
write("ServerScriptService/VehicleSpawnerServer.rbxmx",
	script("Script", "VehicleSpawnerServer", "src/server/VehicleSpawnerServer.luau", nil))

-- Donate alerts
local donateGui = buildGui("src/gui/DonateAlertsGui.luau", "DonateAlertsClient", "src/client/DonateAlertsClient.luau")
write("StarterGui/DonateAlertsGui.rbxmx", donateGui)

local donateShared = Instance.new("Folder")
donateShared.Name = "DonateAlerts"
script("ModuleScript", "Config", "src/shared/DonateConfig.luau", donateShared)
local donateRemotes = Instance.new("Folder")
donateRemotes.Name = "Remotes"
donateRemotes.Parent = donateShared
for _, name in { "DonateAlert", "TestAlert" } do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = donateRemotes
end
write("ReplicatedStorage/DonateAlerts.rbxmx", donateShared)

local donateServer = script("Script", "DonateAlertsServer", "src/server/DonateAlertsServer.luau", nil)
local notify = Instance.new("BindableEvent")
notify.Name = "Notify"
notify.Parent = donateServer
write("ServerScriptService/DonateAlertsServer.rbxmx", donateServer)

if table.find(process.args, "--tree") then
	fs.writeDir("build")
	fs.writeFile("build/tree.json", serde.encode("json", dump(gui), true))
	fs.writeFile("build/donate-tree.json", serde.encode("json", dump(donateGui), true))
	print("Wrote build/tree.json, build/donate-tree.json")
end
