--[[
	Smoke test for the Donate Alerts client, without Roblox Studio.

	Loads StarterGui/DonateAlertsGui.rbxmx, runs the real DonateAlertsClient script
	against it with a small mock of the Roblox API (instances, signals, tweens,
	services), fires a few donations, and checks what the client did: the alerts
	show up (limited by screen height), the amount counts up to its final text,
	confetti appears for big tiers, alerts leave in order and clean up after
	themselves. It cannot judge how anything looks or moves; that needs Studio.

	  lune run tools/test-donate-alerts.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Vector2 = roblox.Vector2

local failures = 0
local function check(ok, message)
	if not ok then
		failures += 1
		print(`FAIL {message}`)
	end
end

---------------------------------------------------------------------------
-- Mock instances: plain tables with the parts of the Instance API the client uses
---------------------------------------------------------------------------

local PROPS = {
	"Name", "Position", "Size", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex",
	"LayoutOrder", "Text", "TextColor3", "TextScaled", "TextSize", "TextWrapped", "RichText", "Image", "Color",
	"Transparency", "Rotation", "Offset", "Thickness", "Scale", "MaxTextSize", "MinTextSize", "AspectRatio",
	"VerticalAlignment", "FontFace", "Enabled", "DisplayOrder",
}

local function signal()
	local handlers = {}
	local self = {}
	function self.Connect(_, fn)
		table.insert(handlers, fn)
		return { Disconnect = function() end }
	end
	function self.Once(_, fn)
		local done = false
		table.insert(handlers, function(...)
			if not done then
				done = true
				fn(...)
			end
		end)
	end
	function self.Fire(_, ...)
		for _, fn in handlers do
			task.spawn(fn, ...)
		end
	end
	return self
end

local Node = {}
local nodeMeta = {}

local function newNode(className, props)
	local node = { _children = {}, _signals = {}, _attributes = {}, _props = props or {} }
	node._props.ClassName = className
	if node._props.Name == nil then
		node._props.Name = className
	end
	return setmetatable(node, nodeMeta)
end

local function detach(node)
	local parent = rawget(node, "_parent")
	if parent then
		table.remove(parent._children, table.find(parent._children, node))
		rawset(node, "_parent", nil)
	end
end

function nodeMeta.__index(self, key)
	local method = Node[key]
	if method then
		return method
	end
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	local value = self._props[key]
	if value ~= nil then
		return value
	end
	for _, child in self._children do
		if child._props.Name == key then
			return child
		end
	end
	return nil
end

function nodeMeta.__newindex(self, key, value)
	if key == "Parent" then
		detach(self)
		if value then
			rawset(self, "_parent", value)
			table.insert(value._children, self)
		end
		return
	end
	self._props[key] = value
	local changed = self._signals[key]
	if changed then
		changed:Fire()
	end
end

function Node.WaitForChild(self, name)
	local child = self:FindFirstChild(name)
	if not child then
		error(`WaitForChild: {self._props.Name} has no child {name}`, 2)
	end
	return child
end

function Node.FindFirstChild(self, name)
	for _, child in self._children do
		if child._props.Name == name then
			return child
		end
	end
	return nil
end

function Node.FindFirstChildOfClass(self, className)
	for _, child in self._children do
		if child._props.ClassName == className then
			return child
		end
	end
	return nil
end

function Node.GetChildren(self)
	return table.clone(self._children)
end

function Node.Destroy(self)
	self._props.Destroyed = true
	detach(self)
end

function Node.Clone(self)
	local copy = newNode(self._props.ClassName, table.clone(self._props))
	for _, child in self._children do
		child:Clone().Parent = copy
	end
	return copy
end

function Node.GetPropertyChangedSignal(self, name)
	self._signals[name] = self._signals[name] or signal()
	return self._signals[name]
end

function Node.GetAttribute(self, name)
	return self._attributes[name]
end

function Node.GetAttributeChangedSignal(self, name)
	self._signals["attr:" .. name] = self._signals["attr:" .. name] or signal()
	return self._signals["attr:" .. name]
end

function Node.Play(self)
	self._props.Played = (self._props.Played or 0) + 1
end

function Node.FireServer(self, ...)
	table.insert(self._props.Fired, { ... })
end

-- A Roblox instance loaded by Lune -> mock node tree
local function fromInstance(inst)
	local props = {}
	for _, name in PROPS do
		local ok, value = pcall(function()
			return inst[name]
		end)
		if ok and value ~= nil then
			props[name] = value
		end
	end
	props.ClassName = inst.ClassName
	local node = newNode(inst.ClassName, props)
	for _, child in inst:GetChildren() do
		fromInstance(child).Parent = node
	end
	return node
end

---------------------------------------------------------------------------
-- Mock services
---------------------------------------------------------------------------

local tweenCount = 0
local TweenService = {}
function TweenService.Create(_, instance, info, props)
	tweenCount += 1
	local completed = signal()
	local cancelled = false
	local tween = { Completed = completed }
	function tween.Play(_)
		for key, value in props do
			instance[key] = value
		end
		if info.RepeatCount == 0 then
			task.delay(info.Time + (info.DelayTime or 0), function()
				if not cancelled then
					completed:Fire()
				end
			end)
		end
	end
	function tween.Cancel(_)
		cancelled = true
	end
	return tween
end

local confettiLayer
local shared = newNode("Folder", { Name = "DonateAlerts" })
local remotes = newNode("Folder", { Name = "Remotes" })
remotes.Parent = shared
local alertRemote = newNode("RemoteEvent", { Name = "DonateAlert", OnClientEvent = signal() })
alertRemote.Parent = remotes
local testRemote = newNode("RemoteEvent", { Name = "TestAlert", Fired = {} })
testRemote.Parent = remotes

local localPlayer = newNode("Player", { Name = "Tester", Chatted = signal() })
localPlayer._attributes.DonateAdmin = true

local textChat = newNode("TextChatService", { ChatVersion = roblox.Enum.ChatVersion.TextChatService })

local services = {
	Players = {
		LocalPlayer = localPlayer,
		GetUserThumbnailAsync = function()
			return "rbxthumb://avatar", true
		end,
	},
	ReplicatedStorage = newNode("ReplicatedStorage"),
	TextChatService = textChat,
	TextService = {
		GetTextBoundsAsync = function(_, params)
			return Vector2.new(#params.Text * params.Size * 0.6, params.Size)
		end,
	},
	TweenService = TweenService,
}
shared.Parent = services.ReplicatedStorage

---------------------------------------------------------------------------
-- Run the client
---------------------------------------------------------------------------

-- Config (real file), with short durations so the test is quick
local baseEnv = {
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	setmetatable = setmetatable,
}
local config = luau.load(fs.readFile("src/shared/DonateConfig.luau"), {
	debugName = "DonateConfig",
	environment = setmetatable(baseEnv, { __index = getfenv(1) }),
})()
for _, tier in config.Tiers do
	tier.Duration = 3
end
config.Settings.MaxVisible = 3
local configModule = newNode("ModuleScript", { Name = "Config", Loaded = config })
configModule.Parent = shared

local guiModel = roblox.deserializeModel(fs.readFile("StarterGui/DonateAlertsGui.rbxmx"))[1]
local gui = fromInstance(guiModel)
local stack = gui:FindFirstChild("Stack")
-- Layout sizes the mock cannot compute
stack._props.AbsoluteSize = Vector2.new(410, 640)
local function withSizes(node)
	local name = node._props.Name
	if name == "Card" then
		node._props.AbsoluteSize = Vector2.new(410, 134)
	elseif name == "Amount" then
		node._props.AbsoluteSize = Vector2.new(280, 34)
	end
	for _, child in node._children do
		withSizes(child)
	end
end
withSizes(gui)

local env = {
	game = {
		GetService = function(_, name)
			return services[name] or error(`unmocked service {name}`)
		end,
	},
	script = { Parent = gui },
	require = function(module)
		return module._props.Loaded
	end,
	task = task,
	warn = function(...)
		print("WARN", ...)
	end,
	Instance = {
		new = function(className)
			if className == "Frame" and confettiLayer == nil then
				-- first Frame the client creates is the confetti layer
				confettiLayer = newNode(className)
				return confettiLayer
			end
			local node = newNode(className)
			if className == "TextChatCommand" then
				node._props.Triggered = signal()
			end
			return node
		end,
	},
	TweenInfo = {
		new = function(time, style, direction, repeatCount, reverses, delayTime)
			return { Time = time, RepeatCount = repeatCount or 0, DelayTime = delayTime or 0 }
		end,
	},
	Vector2 = roblox.Vector2,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	Enum = roblox.Enum,
}
local source = fs.readFile("src/client/DonateAlertsClient.luau")
local client = luau.load(source, {
	debugName = "DonateAlertsClient",
	environment = setmetatable(env, { __index = getfenv(1) }),
})
task.spawn(client)

---------------------------------------------------------------------------
-- Scenario
---------------------------------------------------------------------------

local function alerts()
	local list = {}
	for _, child in stack:GetChildren() do
		if child._props.Name == "Alert" then
			table.insert(list, child)
		end
	end
	return list
end

local function text(slot, name)
	return slot:FindFirstChild("Mover"):FindFirstChild("Card"):FindFirstChild("Body"):FindFirstChild(name)._props.Text
end

check(#alerts() == 0, "no alerts before any donation")
check(stack:FindFirstChild("Sample_1") == nil, "Studio sample cards are removed at startup")

local function donate(data)
	alertRemote.OnClientEvent:Fire(data)
end

donate({ donor = "Budi", amount = 5000, message = "Semangat!", userId = 1 })
donate({ donor = "Nadia", amount = 50000, message = "", target = "RuqFi <b>" })
donate({ donor = "", amount = 100000, message = "Buat kopi" })
donate({ donor = "Legend", amount = 750000, message = "Wow" })
donate({ donor = "Bad", amount = 0 / 0 }) -- NaN: ignored
donate({ donor = "Bad", amount = "5" }) -- not a number: ignored
donate("garbage") -- not a table: ignored

task.wait(0.1)
local shown = alerts()
check(#shown == 3, `3 alerts visible at first (screen fits 3), got {#shown}`)
if #shown == 3 then
	check(text(shown[1], "Donor") == "Budi", "first alert shows the donor name")
	check(string.lower(text(shown[2], "Headline")) == 'bagi-bagi ke <font color="#8b6cff">ruqfi &lt;b&gt;</font>', `target headline is escaped: {text(shown[2], "Headline")}`)
	check(text(shown[3], "Donor") == "Anonim", "empty donor becomes Anonim")
	local badge = shown[1]:FindFirstChild("Mover"):FindFirstChild("Card"):FindFirstChild("IconBadge")
	task.wait(0.05)
	check(badge:FindFirstChild("Avatar")._props.Visible == true, "avatar shown when userId is given")
end

-- The amount counts up and ends on the final text (first three alerts)
local FINAL = { Budi = "Rp 5.000", Nadia = "Rp 50.000", Anonim = "Rp 100.000", Legend = "Rp 750.000" }
local function checkAmounts(slots)
	for _, slot in slots do
		local donor = text(slot, "Donor")
		local amount = text(slot, "Amount")
		check(amount == FINAL[donor], `{donor}'s amount counted up to {FINAL[donor]}, got {amount}`)
	end
end

task.wait(2.2)
checkAmounts(alerts())
check(#confettiLayer._children > 0, "confetti falls for big donations")

-- The queued 4th alert gets its turn once the first ones leave (they last 3 s)
task.wait(3.2)
local second = alerts()
check(#second == 1 and text(second[1], "Donor") == "Legend", `the queued alert appears after the first ones leave, {#second} visible`)
task.wait(2)
checkAmounts(alerts())

-- Everything eventually leaves and cleans up after itself
task.wait(5)
check(#alerts() == 0, `all alerts left, {#alerts()} remain`)
check(#confettiLayer._children == 0, `confetti cleaned up, {#confettiLayer._children} pieces remain`)
check(tweenCount > 20, "tweens were created")

-- Admin test command: registered once, and it sends amount + message to the server
local command = textChat:FindFirstChild("DonateAlertsTest")
check(command ~= nil, "test command registered for admins")
if command then
	check(command._props.PrimaryAlias == "/testdonate", "test command alias comes from the Config")
	command.Triggered:Fire(nil, "/testdonate 25000 Halo dunia")
	task.wait(0.05)
	local fired = testRemote._props.Fired
	check(#fired == 1 and fired[1][1] == 25000 and fired[1][2] == "Halo dunia", "test command sends amount and message")
	command.Triggered:Fire(nil, "/testdonate cuma pesan")
	task.wait(0.05)
	check(fired[2] ~= nil and fired[2][1] == nil and fired[2][2] == "cuma pesan", "test command without an amount sends only the message")
end

print(failures == 0 and "donate alerts smoke test passed" or `{failures} check(s) failed`)
if failures > 0 then
	process.exit(1)
end
