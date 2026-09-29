--[[
	Builds the AutoLights Studio model files:

	  ServerScriptService/AutoLightsServer.rbxmx                        the whole AutoLightsServer folder
	  StarterPlayer/StarterPlayerScripts/AutoLightsTelemetry.rbxmx      LocalScript (telemetry client)
	  StarterGui/AutoLightsPanel.rbxmx                                  control panel GUI + LocalScript

	  lune run tools/build-autolights.luau
	  lune run tools/build-autolights.luau -- --tree   (also writes build/ap-*.json for tools/preview)

	The server folder is put together from autolights/vendor/server (the original scripts,
	including the obfuscated ones, used byte for byte, with their original Disabled flags) and
	autolights/src/server (fixed and new scripts, which replace the vendor file of the same
	name). The vendor files were extracted from the original .rbxm with tools/autolights/extract.py.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local dump = require("./lib/dump")

local Instance = roblox.Instance
local UDim2, Color3 = roblox.UDim2, roblox.Color3

local VENDOR = "autolights/vendor/server"
local SRC = "autolights/src"

local function write(path, instance)
	fs.writeFile(path, roblox.serializeModel({ instance }, true))
	print(`Wrote {path} ({#instance:GetDescendants() + 1} instances)`)
end

local function ensureDir(path)
	if not fs.isDir(path) then
		fs.writeDir(path)
	end
end

local function script(className, name, source, parent)
	local instance = Instance.new(className)
	instance.Name = name
	instance.Source = fs.readFile(source)
	instance.Parent = parent
	return instance
end

---------------------------------------------------------------------------
-- ServerScriptService/AutoLightsServer
---------------------------------------------------------------------------

-- Scripts that exist only in autolights/src (not in the original model): { parent path, name, class }
local NEW_SERVER_SCRIPTS = {
	{ path = {}, name = "AutoLightsControl", class = "Script" },
	{ path = { "Modules" }, name = "AutoLightsAccess", class = "ModuleScript" },
	{ path = { "Modules" }, name = "AutoLightsState", class = "ModuleScript" },
}

local function srcFor(pathParts, name)
	local relative = if #pathParts > 0 then table.concat(pathParts, "/") .. "/" .. name else name
	return `{SRC}/server/{relative}.luau`
end

local replaced, kept = {}, {}

local function buildNode(node, pathParts, parent)
	local instance
	if node.file then
		local sourcePath = srcFor({ table.unpack(pathParts, 2) }, node.name)
		local fromSrc = fs.isFile(sourcePath)
		local file = if fromSrc then sourcePath else `{VENDOR}/{node.file}`
		instance = Instance.new(node.class)
		instance.Name = node.name
		instance.Source = fs.readFile(file)
		if node.disabled then
			instance.Disabled = true
		end
		table.insert(if fromSrc then replaced else kept, node.name)
	else
		instance = Instance.new(node.class)
		instance.Name = node.name
	end
	instance.Parent = parent
	for _, child in node.children or {} do
		local nextPath = table.clone(pathParts)
		table.insert(nextPath, node.name)
		buildNode(child, nextPath, instance)
	end
	return instance
end

local manifest = serde.decode("json", fs.readFile(`{VENDOR}/manifest.json`))
local serverRoot = buildNode(manifest[1], {}, nil)

for _, new in NEW_SERVER_SCRIPTS do
	local parent = serverRoot
	for _, part in new.path do
		parent = parent:FindFirstChild(part)
	end
	script(new.class, new.name, srcFor(new.path, new.name), parent)
end

table.sort(replaced)
table.sort(kept)
print("Fixed / replaced: " .. table.concat(replaced, ", "))
print("Original, unchanged: " .. table.concat(kept, ", "))

ensureDir("ServerScriptService")
write("ServerScriptService/AutoLightsServer.rbxmx", serverRoot)

---------------------------------------------------------------------------
-- StarterPlayerScripts/AutoLightsTelemetry
---------------------------------------------------------------------------

ensureDir("StarterPlayer")
ensureDir("StarterPlayer/StarterPlayerScripts")
write("StarterPlayer/StarterPlayerScripts/AutoLightsTelemetry.rbxmx",
	script("LocalScript", "AutoLightsTelemetry", `{SRC}/client/AutoLightsTelemetry.luau`, nil))

---------------------------------------------------------------------------
-- StarterGui/AutoLightsPanel
---------------------------------------------------------------------------

-- Run the GUI builder with Lune's Roblox types standing in for Studio's.
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

local GUI_SOURCE = `{SRC}/gui/AutoLightsPanelGui.luau`
local gui = luau.load(fs.readFile(GUI_SOURCE), { debugName = GUI_SOURCE, environment = env })()
gui.Parent = nil
script("LocalScript", "AutoLightsPanelClient", `{SRC}/client/AutoLightsPanelClient.luau`, gui)

ensureDir("StarterGui")
write("StarterGui/AutoLightsPanel.rbxmx", gui)

---------------------------------------------------------------------------
-- Preview trees (tools/preview/render.cjs)
---------------------------------------------------------------------------

if not table.find(process.args, "--tree") then
	return
end

ensureDir("build")

-- Same formulas as AutoLightsPanelClient (keep in sync).
local function panelScale(width, height)
	return math.clamp(math.min(width * 0.94 / 420, height * 0.92 / 510), 0.55, 1.1)
end

local function emit(file)
	fs.writeFile(`build/{file}.json`, serde.encode("json", dump(gui), true))
	print(`Wrote build/{file}.json`)
end

local panel = gui.Panel
panel.ResponsiveScale.Scale = panelScale(960, 540)
panel.Visible = true
gui.OpenButton.Visible = false
emit("ap-panel")

-- Sync OFF: amber chip, switches off, dimmed BPM
local AMBER = Color3.fromRGB(255, 190, 56)
local function setToggle(row, on)
	row.Track.BackgroundTransparency = if on then 0 else 0.7
	row.Track.BackgroundColor3 = if on then Color3.fromRGB(61, 220, 151) else Color3.new(1, 1, 1)
	row.Track.Knob.Position = UDim2.fromScale(if on then 0.5 else 0.05, 3 / 22)
end
panel.SyncChip.Label.Text = "SYNC OFF"
panel.SyncChip.Label.TextColor3 = AMBER
panel.SyncChip.Dot.BackgroundColor3 = AMBER
panel.SyncChip.BackgroundColor3 = AMBER
panel.SyncChip.Outline.Color = AMBER
setToggle(panel.Left.Toggle_Sync, false)
setToggle(panel.Left.Toggle_AutoPattern, false)
setToggle(panel.Right.Toggle_Pyro, false)
panel.BeatTile.Bpm.TextTransparency = 0.6
panel.Toast.Visible = true
panel.Toast.Message.Text = "Sync OFF"
emit("ap-off")
