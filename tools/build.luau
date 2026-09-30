--[[
	Builds the Studio model files from src/:

	  StarterGui/VehicleSpawnerGui.rbxmx          GUI + VehicleSpawnerClient (LocalScript)
	  StarterGui/MusicRefreshGui.rbxmx            refresh-music button + MusicRefreshClient
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

local function buildGui(source)
	local gui = luau.load(fs.readFile(source), { debugName = source, environment = env })()
	gui.Parent = nil
	return gui
end

local gui = buildGui("src/gui/VehicleSpawnerGui.luau")
script("LocalScript", "VehicleSpawnerClient", "src/client/VehicleSpawnerClient.luau", gui)

fs.writeDir("StarterGui")
write("StarterGui/VehicleSpawnerGui.rbxmx", gui)

local musicGui = buildGui("src/gui/MusicRefreshGui.luau")
script("LocalScript", "MusicRefreshClient", "src/client/MusicRefreshClient.luau", musicGui)
write("StarterGui/MusicRefreshGui.rbxmx", musicGui)

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

if table.find(process.args, "--tree") then
	fs.writeDir("build")
	fs.writeFile("build/tree.json", serde.encode("json", dump(gui), true))
	print("Wrote build/tree.json")

	-- Music button where MusicRefreshClient puts it: left of a stand-in
	-- Donate button (100 x 36 at the Donate button's 36 px height), toast showing.
	local preview = musicGui:Clone()
	local button = preview.RefreshButton
	button.Position = roblox.UDim2.new(1, -12 - 110 - 8, 0, 11)
	button.Toast.Visible = true
	local donate = Instance.new("TextButton")
	donate.Name = "Donate (stand-in)"
	donate.AnchorPoint = roblox.Vector2.new(1, 0)
	donate.Position = roblox.UDim2.new(1, -12, 0, 11)
	donate.Size = roblox.UDim2.fromOffset(110, 36)
	donate.BackgroundColor3 = roblox.Color3.fromRGB(46, 160, 90)
	donate.BackgroundTransparency = 0
	donate.Text = ""
	donate.Parent = preview
	local round = Instance.new("UICorner")
	round.CornerRadius = roblox.UDim.new(0.5, 0)
	round.Parent = donate
	local text = button.Label:Clone()
	text.Text = "DONATE"
	text.Position = roblox.UDim2.fromScale(0, 11.5 / 36)
	text.Size = roblox.UDim2.fromScale(1, 13 / 36)
	text.TextXAlignment = roblox.Enum.TextXAlignment.Center
	text.Parent = donate
	fs.writeFile("build/music-tree.json", serde.encode("json", dump(preview), true))
	print("Wrote build/music-tree.json")
end
