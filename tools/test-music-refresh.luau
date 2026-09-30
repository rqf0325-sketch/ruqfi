--[[
	Runs the MusicRefreshClient LocalScript from StarterGui/MusicRefreshGui.rbxmx
	against a small fake Roblox (Sounds, GUI objects, signals) and checks:

	  - stuck music is reloaded and continues from the same second
	  - vehicle, character and short UI sounds are left alone
	  - the same song playing twice is cut down to one
	  - silence starts music, moves on when a song ends, and steps aside when
	    the game's own music comes back
	  - a song switch by the game during a refresh is not undone
	  - the button sits next to the Donate button and follows it around

	  lune run tools/build.luau && lune run tools/test-music-refresh.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local UDim2, Vector2, Color3, Enum = roblox.UDim2, roblox.Vector2, roblox.Color3, roblox.Enum

local MODEL = "StarterGui/MusicRefreshGui.rbxmx"

local failures = 0
local function check(condition, message)
	print((condition and "  ok   " or "  FAIL ") .. message)
	if not condition then
		failures += 1
	end
end

---------------------------------------------------------------------------
-- Fake Roblox
---------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handler = { fn = fn, connected = true }
	table.insert(self.handlers, handler)
	return {
		Disconnect = function()
			handler.connected = false
		end,
	}
end

function Signal:Fire(...)
	for _, handler in table.clone(self.handlers) do
		if handler.connected then
			task.spawn(handler.fn, ...)
		end
	end
end

local SUPER = {
	DataModel = "Instance",
	Workspace = "Instance",
	SoundService = "Instance",
	Players = "Instance",
	RunService = "Instance",
	TweenService = "Instance",
	ContentProvider = "Instance",
	Folder = "Instance",
	Model = "Instance",
	Player = "Instance",
	PlayerGui = "Instance",
	PlayerScripts = "Instance",
	BasePart = "Instance",
	Part = "BasePart",
	Attachment = "Instance",
	Sound = "Instance",
	LayerCollector = "Instance",
	ScreenGui = "LayerCollector",
	GuiObject = "Instance",
	Frame = "GuiObject",
	TextLabel = "GuiObject",
	ImageLabel = "GuiObject",
	GuiButton = "GuiObject",
	TextButton = "GuiButton",
	ImageButton = "GuiButton",
	UICorner = "Instance",
	UIStroke = "Instance",
	LocalScript = "Instance",
}

local NIL = newproxy(false)

local function defaults(className)
	local props = {}
	local function isA(name)
		local class = className
		while class do
			if class == name then
				return true
			end
			class = SUPER[class]
		end
		return false
	end
	if isA("GuiObject") then
		props.Visible = true
		props.Position = UDim2.new(0, 0, 0, 0)
		props.Size = UDim2.new(0, 0, 0, 0)
		props.AnchorPoint = Vector2.new(0, 0)
		props.AbsolutePosition = Vector2.new(0, 0)
		props.AbsoluteSize = Vector2.new(0, 0)
		props.Rotation = 0
		props.BackgroundColor3 = Color3.new(1, 1, 1)
	end
	if className == "TextLabel" or className == "TextButton" then
		props.Text = ""
		props.TextTransparency = 0
	end
	if isA("LayerCollector") then
		props.Enabled = true
		props.IgnoreGuiInset = false
		props.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		props.AbsoluteSize = Vector2.new(1280, 720)
	end
	if className == "Sound" then
		props.SoundId = ""
		props.Looped = false
		props.Playing = false
		props.IsLoaded = false
		props.TimeLength = 0
		props.TimePosition = 0
	end
	if className == "Player" then
		props.Character = NIL
	end
	return props
end

local EVENTS = { Activated = true, Ended = true, RenderStepped = true }
local LENGTHS = {} -- SoundId -> seconds once loaded

local Fake = {}
local Methods = {}

local function new(className, name, parent, props)
	local self = setmetatable({
		_class = className,
		_name = name or className,
		_parent = nil,
		_children = {},
		_props = defaults(className),
		_events = {},
		_changed = {},
		plays = 0,
		stops = 0,
	}, Fake)
	for key, value in props or {} do
		self[key] = value
	end
	if parent then
		self.Parent = parent
	end
	return self
end

Fake.__index = function(self, key)
	if key == "Name" then
		return rawget(self, "_name")
	elseif key == "ClassName" then
		return rawget(self, "_class")
	elseif key == "Parent" then
		return rawget(self, "_parent")
	end
	if Methods[key] then
		return Methods[key]
	end
	local value = rawget(self, "_props")[key]
	if value ~= nil then
		if value == NIL then
			return nil
		end
		return value
	end
	if key == "IsPlaying" and rawget(self, "_class") == "Sound" then
		return self.Playing and self.IsLoaded
	end
	if EVENTS[key] then
		local events = rawget(self, "_events")
		events[key] = events[key] or Signal.new()
		return events[key]
	end
	for _, child in rawget(self, "_children") do
		if rawget(child, "_name") == key then
			return child
		end
	end
	error(`{key} is not a valid member of {rawget(self, "_class")} "{rawget(self, "_name")}"`, 2)
end

Fake.__newindex = function(self, key, value)
	if key == "Name" then
		rawset(self, "_name", value)
		return
	elseif key == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local siblings = rawget(old, "_children")
			local index = table.find(siblings, self)
			if index then
				table.remove(siblings, index)
			end
		end
		rawset(self, "_parent", value)
		if value then
			table.insert(rawget(value, "_children"), self)
		end
		return
	end
	local props = rawget(self, "_props")
	local old = props[key]
	props[key] = if value == nil then NIL else value

	-- Changing SoundId reloads the file (a short moment later).
	if key == "SoundId" and rawget(self, "_class") == "Sound" and value ~= old then
		props.IsLoaded = false
		if value ~= "" then
			task.delay(0.05, function()
				if props.SoundId == value then
					props.IsLoaded = true
					props.TimeLength = LENGTHS[value] or 120
				end
			end)
		end
	end
	if old ~= props[key] then
		local signal = rawget(self, "_changed")[key]
		if signal then
			signal:Fire()
		end
	end
end

Fake.__tostring = function(self)
	return rawget(self, "_name")
end

function Methods:GetChildren()
	return table.clone(rawget(self, "_children"))
end

function Methods:GetDescendants()
	local out = {}
	local function walk(node)
		for _, child in rawget(node, "_children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function Methods:FindFirstChild(name)
	for _, child in rawget(self, "_children") do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function Methods:WaitForChild(name)
	local deadline = os.clock() + 5
	local child = self:FindFirstChild(name)
	while not child and os.clock() < deadline do
		task.wait(0.01)
		child = self:FindFirstChild(name)
	end
	assert(child, `WaitForChild timed out: {self.Name}.{name}`)
	return child
end

function Methods:IsA(className)
	local class = rawget(self, "_class")
	while class do
		if class == className then
			return true
		end
		class = SUPER[class]
	end
	return className == "Instance"
end

function Methods:IsDescendantOf(ancestor)
	local node = self.Parent
	while node do
		if node == ancestor then
			return true
		end
		node = node.Parent
	end
	return false
end

function Methods:FindFirstAncestorWhichIsA(className)
	local node = self.Parent
	while node do
		if node:IsA(className) then
			return node
		end
		node = node.Parent
	end
	return nil
end

function Methods:GetFullName()
	local parts = {}
	local node = self
	while node and node.ClassName ~= "DataModel" do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

function Methods:GetPropertyChangedSignal(key)
	local changed = rawget(self, "_changed")
	changed[key] = changed[key] or Signal.new()
	return changed[key]
end

function Methods:Destroy()
	self.Parent = nil
end

function Methods:Play()
	rawset(self, "plays", self.plays + 1)
	self.Playing = true
end

function Methods:Stop()
	rawset(self, "stops", self.stops + 1)
	self.Playing = false
	self.TimePosition = 0
end

function Methods:GetService(name)
	local service = self:FindFirstChild(name)
	assert(service, `no service {name}`)
	return service
end

function Methods:GetPlayers()
	local out = {}
	for _, child in self:GetChildren() do
		if child.ClassName == "Player" then
			table.insert(out, child)
		end
	end
	return out
end

function Methods:Create()
	return {
		Play = function() end,
		Cancel = function() end,
	}
end

function Methods:PreloadAsync()
	task.wait(0.02)
end

-- Copies the built GUI (real Lune instances) into fake instances.
local COPY = {
	"Position", "Size", "AnchorPoint", "Visible", "Text", "TextTransparency", "Rotation",
	"BackgroundColor3", "Enabled", "IgnoreGuiInset", "ScreenInsets", "Source",
}
local function copyTree(real, parent)
	local className = if SUPER[real.ClassName] then real.ClassName else "Folder"
	local fake = new(className, real.Name, parent)
	for _, key in COPY do
		local ok, value = pcall(function()
			return real[key]
		end)
		if ok and value ~= nil then
			rawget(fake, "_props")[key] = value
		end
	end
	for _, child in real:GetChildren() do
		copyTree(child, fake)
	end
	return fake
end

---------------------------------------------------------------------------
-- A world with one local player and the GUI installed
---------------------------------------------------------------------------

local built = roblox.deserializeModel(fs.readFile(MODEL))[1]

local function makeWorld(patches)
	local game = new("DataModel", "Game")
	local w = {
		game = game,
		workspace = new("Workspace", "Workspace", game),
		soundService = new("SoundService", "SoundService", game),
		players = new("Players", "Players", game),
		runService = new("RunService", "RunService", game),
		warnings = {},
	}
	new("TweenService", "TweenService", game)
	new("ContentProvider", "ContentProvider", game)
	w.player = new("Player", "Tester", w.players)
	w.players.LocalPlayer = w.player
	w.playerGui = new("PlayerGui", "PlayerGui", w.player)
	w.playerScripts = new("PlayerScripts", "PlayerScripts", w.player)

	w.gui = copyTree(built, w.playerGui)
	w.button = w.gui.RefreshButton
	w.toast = w.button.Toast
	local script = w.gui.MusicRefreshClient

	local source = script.Source
	source = string.gsub(source, "Cooldown = 3,", "Cooldown = 0.05,")
	source = string.gsub(source, "SEARCH_INTERVAL = 1.5", "SEARCH_INTERVAL = 0")
	for from, to in patches or {} do
		local count
		source, count = string.gsub(source, from, to, 1)
		assert(count == 1, `patch not found: {from}`)
	end

	local env = setmetatable({
		game = game,
		workspace = w.workspace,
		script = script,
		task = task,
		Enum = Enum,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Color3 = Color3,
		TweenInfo = {
			new = function(...)
				return { ... }
			end,
		},
		math = setmetatable({
			random = function()
				return 1
			end,
		}, { __index = math }),
		warn = function(...)
			table.insert(w.warnings, table.concat({ ... }, " "))
		end,
	}, { __index = getfenv(1) })
	w.start = function()
		task.spawn(luau.load(source, { debugName = "MusicRefreshClient", environment = env }))
		task.wait(0.05)
	end
	return w
end

local function sound(parent, name, id, props)
	local s = new("Sound", name, parent, { SoundId = id })
	-- Start from a known state without going through the "reload" above.
	local p = rawget(s, "_props")
	p.IsLoaded = true
	p.TimeLength = LENGTHS[id] or 120
	for key, value in props or {} do
		p[key] = value
	end
	return s
end

-- Presses the button and waits for the toast message.
local function press(w)
	local message = w.toast.Message
	message.Text = ""
	w.button.Activated:Fire()
	local deadline = os.clock() + 12
	while message.Text == "" and os.clock() < deadline do
		task.wait(0.02)
	end
	task.wait(0.1) -- cooldown ends
	return message.Text, w.toast.Dot.BackgroundColor3
end

local GREEN = Color3.fromRGB(61, 220, 151)
local RED = Color3.fromRGB(255, 85, 102)

local function untouched(s)
	return s.plays == 0 and s.stops == 0
end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------

print("GUI")
do
	check(built.ClassName == "ScreenGui" and built.ResetOnSpawn == false, "ScreenGui that survives respawn")
	local button = built:FindFirstChild("RefreshButton")
	check(button and button:IsA("TextButton"), "RefreshButton is a TextButton")
	check(button and button.Label.Text == "MUSIC" and button.Icon.Text == "🔄", "button shows 🔄 MUSIC")
	check(built:FindFirstChild("MusicRefreshClient") and built.MusicRefreshClient.ClassName == "LocalScript", "has the LocalScript")
end

print("Stuck music is reloaded; other sounds are left alone")
do
	local w = makeWorld()
	-- A server music Sound that failed to load on this client, 42 s in.
	local music = sound(w.workspace, "Sound", "rbxassetid://111", {
		Looped = true, Playing = true, IsLoaded = false, TimeLength = 0, TimePosition = 42,
	})
	local bike = new("Model", "HD Road Glide ST CVO", w.workspace)
	local body = new("Part", "Body", bike)
	local engine = sound(body, "Engine", "rbxassetid://500", { Looped = true, Playing = true })
	local radio = sound(body, "Radio", "rbxassetid://501", { Looped = true, Playing = true, TimeLength = 200 })
	local character = new("Model", "Tester", w.workspace)
	w.player.Character = character
	local boombox = sound(character, "BoomboxMusic", "rbxassetid://502", { Looped = true, Playing = true })
	local click = sound(w.soundService, "Click", "rbxassetid://503", { TimeLength = 0.3 })
	w.start()

	local text, color = press(w)
	check(text == "Music refreshed" and color == GREEN, `toast says "Music refreshed" ({text})`)
	check(music.Playing and music.IsLoaded, "music is loaded and playing again")
	check(music.plays == 1 and music.stops == 1, "music was stopped and played once")
	check(music.TimePosition == 42, `music continues from 42 s ({music.TimePosition})`)
	check(music.SoundId == "rbxassetid://111", "music keeps its SoundId")
	check(untouched(engine) and engine.Playing, "bike engine (inside a Part) left alone")
	check(untouched(radio), "bike radio (inside a Part, named like music) left alone")
	check(untouched(boombox), "sound on a character left alone")
	check(untouched(click), "short UI sound left alone")
	check(#w.warnings == 0, "no warnings")
end

print("The same song playing twice")
do
	local w = makeWorld()
	local folder = new("Folder", "Music", w.soundService)
	local a = sound(folder, "Track", "rbxassetid://222", { Playing = true, TimePosition = 10 })
	local b = sound(folder, "Track", "rbxassetid://222", { Playing = true, TimePosition = 11 })
	w.start()

	local text = press(w)
	check(text == "Music refreshed", `toast says "Music refreshed" ({text})`)
	check(a.Playing and not b.Playing, "one copy plays, the other is stopped")
	check(a.TimePosition == 10, "the kept copy continues where it was")
end

print("Silence starts music, moves on, and steps aside")
do
	local w = makeWorld()
	local songs = new("Folder", "Songs", w.workspace)
	local first = sound(songs, "Song1", "rbxassetid://301", { TimeLength = 100 })
	local second = sound(songs, "Song2", "rbxassetid://302", { TimeLength = 100 })
	w.start()

	local text, color = press(w)
	check(text == "Music started" and color == GREEN, `toast says "Music started" ({text})`)
	check(first.Playing and not second.Playing, "the first song plays")

	-- The song ends by itself.
	first.Playing = false
	first.Ended:Fire()
	task.wait(0.4)
	check(second.Playing and not first.Playing, "the next song plays after it ends")

	-- Pressing again keeps the current song going.
	text = press(w)
	check(text == "Music refreshed" and second.Playing, "pressing again refreshes the current song")

	-- The game's own music starts again.
	first.Playing = true
	task.wait(0.1)
	check(first.Playing and not second.Playing, "the started song stops when the game's music is back")
end

print("The game switches songs during a refresh")
do
	local w = makeWorld()
	local music = sound(w.soundService, "Music", "rbxassetid://401", { Playing = true, TimePosition = 5 })
	-- A playlist script that loads the next song as soon as the Sound is cleared.
	music:GetPropertyChangedSignal("SoundId"):Connect(function()
		if music.SoundId == "" then
			music.SoundId = "rbxassetid://402"
			music:Play()
		end
	end)
	w.start()
	press(w)
	check(music.SoundId == "rbxassetid://402", `the game's new song is kept ({music.SoundId})`)
	check(music.Playing, "and it is playing")
end

print("Nothing to refresh")
do
	local w = makeWorld()
	sound(w.soundService, "Click", "rbxassetid://503", { TimeLength = 0.3 })
	w.start()
	local text, color = press(w)
	check(text == "No music found" and color == RED, `toast says "No music found" ({text})`)
end

do
	local w = makeWorld({ ["PlayWhenSilent = true"] = "PlayWhenSilent = false" })
	local music = sound(w.soundService, "Music", "rbxassetid://601", { Looped = true })
	w.start()
	local text, color = press(w)
	check(text == "No music is playing" and color == RED, `PlayWhenSilent = false: "No music is playing" ({text})`)
	check(untouched(music), "PlayWhenSilent = false: music not started")
end

print("MusicPaths")
do
	local w = makeWorld({ ["MusicPaths = {}"] = 'MusicPaths = { "Workspace.Speaker", "Workspace.Missing" }' })
	local speaker = new("Part", "Speaker", w.workspace)
	local music = sound(speaker, "Sound", "rbxassetid://701", { Playing = true, IsLoaded = false, TimePosition = 3 })
	local other = sound(w.soundService, "Music", "rbxassetid://702", { Playing = true })
	w.start()
	local text = press(w)
	check(text == "Music refreshed" and music.plays == 1 and music.TimePosition == 3, "a Sound in a Part is refreshed when listed")
	check(untouched(other), "unlisted sounds are left alone")
	check(#w.warnings == 1 and string.find(w.warnings[1], "Workspace.Missing", 1, true) ~= nil, "a missing path is reported")
end

print("Next to the Donate button")
do
	local w = makeWorld()
	w.start()
	local button = w.button

	w.runService.RenderStepped:Fire(1 / 60)
	check(button.Position == UDim2.new(1, -12, 0, 11) and button.AnchorPoint == Vector2.new(1, 0),
		"stays in the top-right corner while there is no Donate button")

	local donateGui = new("ScreenGui", "DonateGui", w.playerGui, {
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
	})
	-- Decoys: a donate board on the left, and an icon button without the word.
	local board = new("ScreenGui", "Board", w.playerGui)
	new("TextButton", "Give", board, {
		Text = "Donate 100",
		AbsolutePosition = Vector2.new(40, 600),
		AbsoluteSize = Vector2.new(120, 40),
	})
	local icon = new("ImageButton", "Icon", donateGui, {
		AbsolutePosition = Vector2.new(1200, 60),
		AbsoluteSize = Vector2.new(40, 40),
	})
	new("TextLabel", "Caption", icon, { Text = "Donasi" })
	local donate = new("TextButton", "Button", donateGui, {
		Text = "DONATE",
		AbsolutePosition = Vector2.new(1150, 10),
		AbsoluteSize = Vector2.new(110, 40),
	})

	w.runService.RenderStepped:Fire(1 / 60)
	-- The button saying DONATE wins over the icon with a "Donasi" caption.
	-- 100 x 36 design -> 111 x 40 at the Donate button's height, 8 px to its left.
	check(button.Size == UDim2.fromOffset(111, 40), `same height as Donate ({button.Size})`)
	check(button.Position == UDim2.fromOffset(1150 - 8 - 111, 10), `left of Donate ({button.Position})`)
	check(button.AnchorPoint == Vector2.new(0, 0), "anchored top-left while following")
	check(w.gui.IgnoreGuiInset == true and w.gui.ScreenInsets == Enum.ScreenInsets.None,
		"uses the Donate ScreenGui's inset settings")

	donate.AbsolutePosition = Vector2.new(1100, 20)
	w.runService.RenderStepped:Fire(1 / 60)
	check(button.Position == UDim2.fromOffset(1100 - 8 - 111, 20), "follows when Donate moves")

	icon:Destroy()

	donate.Visible = false
	w.runService.RenderStepped:Fire(1 / 60)
	check(button.Position == UDim2.fromOffset(1100 - 8 - 111, 20), "keeps its spot while Donate is hidden")

	-- Respawn rebuilds the Donate GUI (ResetOnSpawn).
	donateGui:Destroy()
	local rebuilt = new("ScreenGui", "DonateGui", w.playerGui, { IgnoreGuiInset = true })
	new("TextButton", "Button", rebuilt, {
		Text = "DONATE",
		AbsolutePosition = Vector2.new(1160, 70),
		AbsoluteSize = Vector2.new(100, 30),
	})
	w.runService.RenderStepped:Fire(1 / 60)
	check(button.Size == UDim2.fromOffset(83, 30) and button.Position == UDim2.fromOffset(1160 - 8 - 83, 70),
		`finds the rebuilt Donate button ({button.Position}, {button.Size})`)
end

do
	local w = makeWorld({ ['DonateButtonName = ""'] = 'DonateButtonName = "Support"' })
	local sg = new("ScreenGui", "TopBar", w.playerGui)
	new("ImageButton", "Support", sg, {
		AbsolutePosition = Vector2.new(20, 20),
		AbsoluteSize = Vector2.new(36, 36),
	})
	w.start()
	w.runService.RenderStepped:Fire(1 / 60)
	check(w.button.Position == UDim2.fromOffset(20 - 8 - 100, 20),
		`DonateButtonName finds a button with any name, anywhere ({w.button.Position})`)
end

do
	local w = makeWorld({ ['Side = "Left"'] = 'Side = "Below"' })
	local sg = new("ScreenGui", "DonateGui", w.playerGui)
	new("TextButton", "DonateButton", sg, {
		AbsolutePosition = Vector2.new(1150, 10),
		AbsoluteSize = Vector2.new(110, 36),
	})
	w.start()
	w.runService.RenderStepped:Fire(1 / 60)
	check(w.button.Position == UDim2.fromOffset(1150 + 110 - 100, 10 + 36 + 8), `Side = "Below" ({w.button.Position})`)
end

do
	local w = makeWorld({ ["FollowDonateButton = true"] = "FollowDonateButton = false" })
	local sg = new("ScreenGui", "DonateGui", w.playerGui)
	new("TextButton", "DonateButton", sg, {
		AbsolutePosition = Vector2.new(1150, 10),
		AbsoluteSize = Vector2.new(110, 36),
	})
	w.start()
	w.runService.RenderStepped:Fire(1 / 60)
	check(w.button.Position == UDim2.new(1, -12, 0, 11), "FollowDonateButton = false keeps the Studio position")
end

print(if failures == 0 then "All checks passed" else `{failures} check(s) failed`)
if failures > 0 then
	process.exit(1)
end
