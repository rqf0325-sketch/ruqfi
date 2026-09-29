--[[
	Builds the Player Menu model files from src/:

	  StarterGui/PlayerMenuGui.rbxmx              GUI + PlayerMenuClient + PlayerMenuNametags (LocalScripts)
	  ReplicatedStorage/PlayerMenu.rbxmx          Config (ModuleScript) + Remotes
	  ServerScriptService/PlayerMenuServer.rbxmx

	  lune run tools/build-player-menu.luau
	  lune run tools/build-player-menu.luau -- --tree   (also writes build/pm-*.json for tools/preview)
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local dump = require("./lib/dump")

local Instance = roblox.Instance
local UDim2, Vector2, Color3 = roblox.UDim2, roblox.Vector2, roblox.Color3

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

local GUI_SOURCE = "src/gui/PlayerMenuGui.luau"
local gui = luau.load(fs.readFile(GUI_SOURCE), { debugName = GUI_SOURCE, environment = env })()
gui.Parent = nil
script("LocalScript", "PlayerMenuClient", "src/client/PlayerMenuClient.luau", gui)
script("LocalScript", "PlayerMenuNametags", "src/client/PlayerMenuNametags.luau", gui)

fs.writeDir("StarterGui")
write("StarterGui/PlayerMenuGui.rbxmx", gui)

-- ReplicatedStorage.PlayerMenu
local shared = Instance.new("Folder")
shared.Name = "PlayerMenu"
script("ModuleScript", "Config", "src/shared/PlayerMenuConfig.luau", shared)
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = shared
for _, name in { "Like", "Follow", "Carry", "SendMessage" } do
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = remotes
end
local notify = Instance.new("RemoteEvent")
notify.Name = "Notify"
notify.Parent = remotes

fs.writeDir("ReplicatedStorage")
write("ReplicatedStorage/PlayerMenu.rbxmx", shared)

-- ServerScriptService.PlayerMenuServer
fs.writeDir("ServerScriptService")
write("ServerScriptService/PlayerMenuServer.rbxmx",
	script("Script", "PlayerMenuServer", "src/server/PlayerMenuServer.luau", nil))

---------------------------------------------------------------------------
-- Preview trees (tools/preview/render.cjs)
---------------------------------------------------------------------------

if not table.find(process.args, "--tree") then
	return
end

fs.writeDir("build")

-- Same formulas as PlayerMenuClient (keep in sync).
local function cardScale(width, height)
	return math.clamp(math.min(width * 0.94 / 312, height * 0.88 / 458), 0.5, 1.1)
end
local function hudScale(height)
	return math.clamp(height / 720, 0.75, 1.1)
end

local function setLayout(width, height)
	gui.Card.ResponsiveScale.Scale = cardScale(width, height)
	for _, name in { "Toast", "CarryRequest", "CarryBar" } do
		gui[name].ResponsiveScale.Scale = hudScale(height)
	end
end

local function setPage(page)
	gui.Card.Home.Visible = page == "Home"
	gui.Card.ProfilePage.Visible = page == "Profile"
	gui.Card.ChatPage.Visible = page == "Chat"
end

local function setHud(visible)
	gui.Toast.Visible = visible
	gui.CarryRequest.Visible = visible
	gui.CarryBar.Visible = visible
end

local function emit(file, root)
	fs.writeFile(`build/{file}.json`, serde.encode("json", dump(root), true))
	print(`Wrote build/{file}.json`)
end

-- A sample community icon for the previews (Roblox images are not fetched).
local card = gui.Card
card.CommunityBackground.Image = "preview:sample-community.svg"

setLayout(960, 540)
setPage("Home")
emit("pm-desktop", gui)
setPage("Profile")
emit("pm-profile", gui)
setPage("Chat")
emit("pm-chat", gui)

setPage("Home")
setHud(true)
emit("pm-hud", gui)
setHud(false)

-- A player without a community: plain transparent card.
local communityParts = { card.CommunityBackground, card.CommunityScrim, card.Home.CommunityChip }
for _, part in communityParts do
	part.Visible = false
end
emit("pm-plain", gui)
for _, part in communityParts do
	part.Visible = true
end

setLayout(844, 390)
emit("pm-phone", gui)

-- Nametags: three examples side by side.
local template = gui.NametagTemplate
local sheet = Instance.new("Frame")
sheet.Name = "NametagSheet"
sheet.Size = UDim2.fromScale(1, 1)
sheet.BackgroundTransparency = 1

local examples = {
	{ name = "SweetPie", role = "ADMINISTRATOR", color = Color3.fromRGB(255, 128, 31), gradient = true },
	{ name = "Paul", role = "VIP", color = Color3.fromRGB(255, 208, 84), gradient = false },
	{ name = "Rika", role = "", color = Color3.new(1, 1, 1), gradient = false },
}
for i, example in examples do
	local holder = Instance.new("Frame")
	holder.Name = `Tag{i}`
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new((i - 0.5) / #examples, 0, 1, -14)
	holder.Size = UDim2.fromOffset(240, 56)
	holder.BackgroundTransparency = 1
	holder.Parent = sheet
	local stack = template.Stack:Clone()
	stack.Size = UDim2.fromScale(1, 1)
	stack.Parent = holder
	stack.PlayerName.Text = example.name
	stack.PlayerName.UIGradient.Enabled = example.gradient
	stack.RoleChip.Visible = example.role ~= ""
	stack.RoleChip.Label.Text = example.role
	stack.RoleChip.Size = UDim2.fromOffset(24 + #example.role * 7, 17) -- runtime chips size themselves to the text
	stack.RoleChip.BackgroundColor3 = example.color
	stack.RoleChip.Outline.Color = example.color
end
emit("pm-nametag", sheet)
