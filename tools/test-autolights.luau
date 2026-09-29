--[[
	Smoke test for AutoLights: runs the real scripts from the built model files
	(AutoLightsServer, AutoLightsTelemetry, AutoLightsPanel) inside a small fake
	Roblox world and drives them end to end: operator access rules, the Control
	remote, DanceFloorSync (beats, rate limiting, sender takeover, switches,
	patterns, brightness), the bridge into the vendor scripts (stand-ins for the
	obfuscated BeatService / GLightsAdapter / PyroService), the fixed modules
	(RhythmRunner, PresetRunner, ShowEngine, Permission/Throttle), the telemetry
	client and the panel client.

	  lune run tools/build-autolights.luau
	  lune run tools/test-autolights.luau

	It is not Roblox: physics, rendering and tweens are stubbed. It catches mistakes
	in script logic and in object names between the GUI and its scripts. The vendor
	scripts are obfuscated and are replaced by small stand-ins here.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local RealInstance = roblox.Instance
local realTypeof = typeof

---------------------------------------------------------------------------
-- Scheduler (task library) driven by the test
---------------------------------------------------------------------------

local errors = {}
local now = 0
local queue = {}

local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(errors, tostring(err) .. "\n" .. debug.traceback(co))
	end
end

local function schedule(delay, fn)
	table.insert(queue, { at = now + delay, fn = fn, n = #queue })
end

local task = {}
function task.spawn(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.delay(seconds, fn, ...)
	local args = table.pack(...)
	schedule(seconds, function()
		task.spawn(fn, table.unpack(args, 1, args.n))
	end)
end
function task.defer(fn, ...)
	local args = table.pack(...)
	schedule(0, function()
		task.spawn(fn, table.unpack(args, 1, args.n))
	end)
end
function task.wait(seconds)
	local co = coroutine.running()
	schedule(math.max(seconds or 0, 1 / 60), function()
		resume(co)
	end)
	coroutine.yield()
	return seconds or 0
end

local function advance(seconds)
	local target = now + seconds
	while true do
		local best
		for index, item in queue do
			if item.at <= target and (not best or item.at < queue[best].at or (item.at == queue[best].at and item.n < queue[best].n)) then
				best = index
			end
		end
		if not best then
			break
		end
		local item = table.remove(queue, best)
		now = math.max(now, item.at)
		item.fn()
	end
	now = target
end

---------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end
function Signal:Connect(fn)
	local handler = { fn = fn, on = true }
	table.insert(self.handlers, handler)
	return {
		Disconnect = function()
			handler.on = false
		end,
	}
end
function Signal:Fire(...)
	for _, handler in table.clone(self.handlers) do
		if handler.on then
			task.spawn(handler.fn, ...)
		end
	end
end

---------------------------------------------------------------------------
-- Instance proxy: real Lune instances plus what Studio has and Lune lacks
-- (WaitForChild, events, a few properties and methods).
---------------------------------------------------------------------------

-- Lune hands out a new userdata for the same instance each time, so tables are keyed by GetDebugId().
local proxyToInst = {}
local instToProxy = {}
local extras = {}
local signalTable = {}

local function idOf(inst)
	return inst:GetDebugId()
end
local fakeObjects = {} -- Player fakes count as Instances for typeof()
local remoteInbox = {} -- [Player] = { {kind, data} } for players without a client here
local LOCAL_PLAYER
local fireServerLog = {} -- what the local client sent with FireServer

local EVENTS = {}
for _, name in {
	"Activated", "MouseEnter", "MouseLeave", "FocusLost", "OnClientEvent", "Died", "Seated",
	"AncestryChanged", "Destroying", "AttributeChanged", "Event", "OnServerEvent", "ChildAdded", "ChildRemoved",
} do
	EVENTS[name] = true
end

-- Members Studio has that Lune's database lacks; reading them gives the stored value or nil.
local OPTIONAL = { IsPlaying = true, PlaybackLoudness = true, Image = true, Interactable = true, Occupant = true, SeatPart = true, CurrentCamera = true, OnServerInvoke = true, AbsoluteCanvasSize = true }

local function signalFor(inst, name)
	local perInst = signalTable[idOf(inst)]
	if not perInst then
		perInst = {}
		signalTable[idOf(inst)] = perInst
	end
	local signal = perInst[name]
	if not signal then
		signal = Signal.new()
		perInst[name] = signal
	end
	return signal
end

local wrap, unwrap

function unwrap(value)
	return proxyToInst[value] or value
end

-- Results of Instance methods: Instances, or arrays of them (GetChildren, ...).
local function wrapAll(...)
	local packed = table.pack(...)
	for i = 1, packed.n do
		local value = packed[i]
		if type(value) == "table" and getmetatable(value) == nil then
			local copy = {}
			for key, item in value do
				copy[key] = wrap(item)
			end
			packed[i] = copy
		else
			packed[i] = wrap(value)
		end
	end
	return table.unpack(packed, 1, packed.n)
end

local function unwrapAll(...)
	local packed = table.pack(...)
	for i = 1, packed.n do
		packed[i] = unwrap(packed[i])
	end
	return packed
end

local meta = {}

function wrap(value)
	if realTypeof(value) ~= "Instance" then
		return value
	end
	local proxy = instToProxy[idOf(value)]
	if not proxy then
		proxy = setmetatable({}, meta)
		proxyToInst[proxy] = value
		instToProxy[idOf(value)] = proxy
	end
	return proxy
end

local function setExtra(inst, key, value)
	local bag = extras[idOf(inst)]
	if not bag then
		bag = {}
		extras[idOf(inst)] = bag
	end
	bag[key] = value
end

local function fireAttribute(inst, name)
	signalFor(inst, "AttributeChanged"):Fire(name)
	signalFor(inst, "attr:" .. name):Fire()
end

local function destroySeat(inst)
	setExtra(inst, "Occupant", nil)
	signalFor(inst, "prop:Occupant"):Fire()
end

meta.__index = function(proxy, key)
	local inst = proxyToInst[proxy]
	if key == "WaitForChild" then
		return function(_, name, timeout)
			local child = inst:FindFirstChild(name)
			if not child then
				if timeout then
					return nil
				end
				error(`WaitForChild: {inst:GetFullName()} has no child "{name}"`, 2)
			end
			return wrap(child)
		end
	elseif key == "GetAttributeChangedSignal" then
		return function(_, name)
			return signalFor(inst, "attr:" .. name)
		end
	elseif key == "GetPropertyChangedSignal" then
		return function(_, name)
			return signalFor(inst, "prop:" .. name)
		end
	elseif key == "SetAttribute" then
		return function(_, name, value)
			inst:SetAttribute(name, value)
			fireAttribute(inst, name)
		end
	elseif key == "Destroy" then
		return function()
			if inst.ClassName == "Seat" then
				destroySeat(inst)
			end
			inst:Destroy()
		end
	elseif key == "Sit" and inst.ClassName == "Seat" then
		return function(_, humanoid)
			setExtra(inst, "Occupant", humanoid)
			signalFor(inst, "prop:Occupant"):Fire()
		end
	elseif key == "CaptureFocus" or key == "Play" or key == "Stop" then
		return function() end
	elseif key == "Fire" and inst.ClassName == "BindableEvent" then
		return function(_, ...)
			signalFor(inst, "Event"):Fire(...)
		end
	elseif key == "FireClient" and inst.ClassName == "RemoteEvent" then
		return function(_, player, ...)
			if player == LOCAL_PLAYER then
				signalFor(inst, "OnClientEvent"):Fire(...)
			else
				remoteInbox[player] = remoteInbox[player] or {}
				table.insert(remoteInbox[player], table.pack(...))
			end
		end
	elseif key == "FireServer" and inst.ClassName == "RemoteEvent" then
		return function(_, ...)
			table.insert(fireServerLog, table.pack(inst.Name, ...))
			signalFor(inst, "OnServerEvent"):Fire(LOCAL_PLAYER, ...)
		end
	elseif key == "FireAllClients" and inst.ClassName == "RemoteEvent" then
		return function(_, ...)
			signalFor(inst, "OnClientEvent"):Fire(...)
		end
	elseif key == "InvokeServer" and inst.ClassName == "RemoteFunction" then
		return function(_, ...)
			local handler = extras[idOf(inst)] and extras[idOf(inst)].OnServerInvoke
			assert(handler, `{inst.Name} has no OnServerInvoke`)
			return handler(LOCAL_PLAYER, ...)
		end
	elseif EVENTS[key] then
		return signalFor(inst, key)
	end

	local bag = extras[idOf(inst)]
	if bag and bag[key] ~= nil then
		return bag[key]
	end
	if key == "AbsoluteSize" and inst.ClassName == "ScreenGui" then
		return roblox.Vector2.new(1280, 720)
	elseif key == "AbsoluteCanvasSize" then
		return roblox.Vector2.new(276, 400)
	elseif key == "Position" and inst:IsA("BasePart") then
		return inst.CFrame.Position
	end
	local ok, value = pcall(function()
		return inst[key]
	end)
	if ok then
		if type(value) == "function" then
			return function(_, ...)
				local args = unwrapAll(...)
				return wrapAll(value(inst, table.unpack(args, 1, args.n)))
			end
		end
		return wrap(value)
	end
	if OPTIONAL[key] then
		return nil
	end
	error(`{key} is not a valid member of {inst.ClassName} "{inst:GetFullName()}"`, 2)
end

meta.__newindex = function(proxy, key, value)
	local inst = proxyToInst[proxy]
	value = unwrap(value)
	local ok = pcall(function()
		inst[key] = value
	end)
	if not ok or OPTIONAL[key] then
		setExtra(inst, key, value)
	end
	signalFor(inst, "prop:" .. key):Fire()
end

meta.__tostring = function(proxy)
	return proxyToInst[proxy]:GetFullName()
end


---------------------------------------------------------------------------
-- Fake world: services, players, floors
---------------------------------------------------------------------------

local warnings = {}
local studioMode = false
local creator = { id = 1, isGroup = false }
local groupInfo = {}

local worldRoot = RealInstance.new("Folder")
worldRoot.Name = "Workspace"
local workspaceProxy = wrap(worldRoot)
extras[idOf(worldRoot)] = { GetServerTimeNow = function()
	return 1000 + now
end }

local replicated = RealInstance.new("Folder")
replicated.Name = "ReplicatedStorage"
local soundFolder = RealInstance.new("Folder")
soundFolder.Name = "SoundService"
local scriptService = RealInstance.new("Folder")
scriptService.Name = "ServerScriptService"

local players = {}
local playersService = {
	PlayerAdded = Signal.new(),
	PlayerRemoving = Signal.new(),
	GetPlayers = function()
		return table.clone(players)
	end,
}

local function makePlayer(userId, name)
	local player = { UserId = userId, Name = name, DisplayName = name, Parent = nil, rank = 0 }
	local attributes = {}
	local attributeSignals = {}
	player.AttributeChanged = Signal.new()
	function player:GetAttribute(attribute)
		return attributes[attribute]
	end
	function player:SetAttribute(attribute, value)
		attributes[attribute] = value
		player.AttributeChanged:Fire(attribute)
		if attributeSignals[attribute] then
			attributeSignals[attribute]:Fire()
		end
	end
	function player:GetAttributeChangedSignal(attribute)
		attributeSignals[attribute] = attributeSignals[attribute] or Signal.new()
		return attributeSignals[attribute]
	end
	function player:IsA(className)
		return className == "Player" or className == "Instance"
	end
	function player:GetRankInGroup()
		return player.rank
	end
	local playerGui = RealInstance.new("Folder")
	playerGui.Name = "PlayerGui"
	function player:WaitForChild(name)
		return if name == "PlayerGui" then wrap(playerGui) else nil
	end
	fakeObjects[player] = true
	return player
end

local function addPlayer(player)
	player.Parent = playersService
	table.insert(players, player)
	playersService.PlayerAdded:Fire(player)
end

local services = {
	Players = playersService,
	RunService = { Heartbeat = Signal.new(), IsStudio = function()
		return studioMode
	end },
	GroupService = { GetGroupInfoAsync = function(_, groupId)
		return groupInfo[groupId] or error("no such group")
	end },
	TweenService = { Create = function(_, inst, _, props)
		return { Play = function()
			for key, value in props do
				inst[key] = value
			end
		end }
	end },
	UserInputService = { InputBegan = Signal.new() },
	SoundService = wrap(soundFolder),
	Lighting = { ClockTime = 12, TimeOfDay = "12:00:00" },
}

local game = setmetatable({
	GetService = function(_, name)
		if name == "ReplicatedStorage" then
			return wrap(replicated)
		end
		return assert(services[name], `service {name} is not faked`)
	end,
	FindFirstChild = function(_, name)
		if name == "SoundService" then
			return wrap(soundFolder)
		end
		return nil
	end,
	BindToClose = function() end,
}, { __index = function(_, key)
	if key == "CreatorId" then
		return creator.id
	elseif key == "CreatorType" then
		return if creator.isGroup then roblox.Enum.CreatorType.Group else roblox.Enum.CreatorType.User
	end
	return nil
end })

local moduleCache = {}
local baseEnv = getfenv(1)

local function makeEnv(scriptInstance)
	local env = setmetatable({
		game = game,
		workspace = workspaceProxy,
		script = wrap(scriptInstance),
		task = task,
		os = setmetatable({ clock = function()
			return now
		end }, { __index = os }),
		tick = function()
			return 1000000 + now
		end,
		typeof = function(value)
			if proxyToInst[value] or fakeObjects[value] then
				return "Instance"
			end
			return realTypeof(value)
		end,
		Instance = { new = function(className)
			return wrap(RealInstance.new(className))
		end },
		Enum = roblox.Enum,
		Font = roblox.Font,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		Color3 = roblox.Color3,
		CFrame = roblox.CFrame,
		ColorSequence = roblox.ColorSequence,
		NumberSequence = roblox.NumberSequence,
		TweenInfo = { new = function(...)
			return { ... }
		end },
		print = function() end,
		warn = function(...)
			local parts = {}
			for _, part in { ... } do
				table.insert(parts, tostring(part))
			end
			table.insert(warnings, table.concat(parts, " "))
		end,
	}, { __index = baseEnv })
	env.require = function(moduleScript)
		local inst = unwrap(moduleScript)
		if not moduleCache[idOf(inst)] then
			moduleCache[idOf(inst)] = luau.load(inst.Source, { debugName = inst.Name, environment = makeEnv(inst) })()
		end
		return moduleCache[idOf(inst)]
	end
	return env
end

local function run(scriptInstance)
	local chunk = luau.load(scriptInstance.Source, { debugName = scriptInstance.Name, environment = makeEnv(scriptInstance) })
	task.spawn(chunk)
end

-- fs and model loading yield in Lune, and the scenario must not: do it all up front.
local files = {}
local models = {}
for _, path in {
	"ServerScriptService/AutoLightsServer.rbxmx",
	"StarterPlayer/StarterPlayerScripts/AutoLightsTelemetry.rbxmx",
	"StarterGui/AutoLightsPanel.rbxmx",
} do
	assert(fs.isFile(path), `{path} is missing; run lune run tools/build-autolights.luau first`)
	models[path] = roblox.deserializeModel(fs.readFile(path))[1]
end
for _, name in { "Palette", "PresetLibrary", "RhythmLibrary" } do
	local path = `autolights/vendor/shared/AutoLights.Shared.{name}.luau`
	files[path] = fs.readFile(path)
end

local function readModel(path)
	return models[path]:Clone()
end

---------------------------------------------------------------------------
-- Fake versions of the obfuscated G-Lights modules (same public API)
---------------------------------------------------------------------------

local FAKE_BEAT = [[
local B = {}
B.__index = B
B.calls = { step = 0, force = 0 }
function B.new(logger)
	return setmetatable({ t = 0, thr = 150, beat = 0, lastBeat = -1e9, bpm = 120 }, B)
end
function B:SetConfig(c) if c.baseThreshold then self.thr = c.baseThreshold end end
function B:StepFromRms(dt, now, rms)
	B.calls.step += 1
	self.t = now
	if rms > self.thr and now - self.lastBeat > 0.12 then
		self.lastBeat = now
		self.beat += 1
		return { beatIndex = self.beat, barIndex = self.beat // 4, bpm = self.bpm, level = "Med" }
	end
	return nil
end
function B:ForceBeat(now)
	B.calls.force += 1
	self.beat += 1
	return { beatIndex = self.beat, barIndex = self.beat // 4, bpm = self.bpm }
end
function B:TelemetryAge(now) return now - self.t end
function B:Decay() end
function B:GetState() return { bpm = self.bpm, beatsInBar = 4 } end
return B
]]

local FAKE_GL = [[
local G = {}
G.__index = G
G.log = {}
function G.new(logger) return setmetatable({}, G) end
function G:Run(folder, fn, args, selector, extra, owner) table.insert(G.log, { "Run", folder, fn, args and args[1] }) end
function G:CleanupPreset() table.insert(G.log, { "CleanupPreset" }) end
function G:EnsureAllOnBaseline(color) table.insert(G.log, { "Baseline", typeof(color) }) end
function G:HardResetAll() table.insert(G.log, { "HardReset" }) end
return G
]]

local FAKE_PYRO = [[
local P = {}
P.__index = P
P.log = {}
function P.new(logger, gl) return setmetatable({ armed = false }, P) end
function P:Fire(device, pattern, args, requireArmed, gate)
	if requireArmed and not self.armed then return false, "not armed" end
	table.insert(P.log, { device, pattern })
	return true
end
function P:SetArmed(v) self.armed = v end
function P:GetArmed() return self.armed end
function P:AllOff() table.insert(P.log, { "AllOff" }) end
return P
]]

---------------------------------------------------------------------------
-- Test helpers
---------------------------------------------------------------------------

local passed, failed = 0, 0

local function check(condition, message)
	if condition then
		passed += 1
	else
		failed += 1
		print(`FAIL: {message}`)
	end
end

local function checkEq(actual, expected, message)
	check(actual == expected, `{message} (expected {expected}, got {actual})`)
end

local function noErrors(stage)
	if #errors > 0 then
		failed += #errors
		print(`FAIL: errors during {stage}:`)
		for _, err in errors do
			print("  " .. err)
		end
		table.clear(errors)
	end
end

local function fire(button)
	signalFor(unwrap(button), "Activated"):Fire()
end

local function handlerOf(remote)
	return extras[idOf(unwrap(remote))].OnServerInvoke
end

local function heartbeats(count, dt)
	for _ = 1, count do
		services.RunService.Heartbeat:Fire(dt or 1 / 60)
		advance(dt or 1 / 60)
	end
end

local function tilesOf(floorModel)
	local folder = floorModel:FindFirstChild("_Tiles")
	return if folder then folder:GetChildren() else {}
end

local function maxChannel(tiles)
	local best = 0
	for _, tile in tiles do
		local color = tile.Color
		best = math.max(best, color.R, color.G, color.B)
	end
	return best
end

local function makeFloor(name)
	local model = RealInstance.new("Model")
	model.Name = name
	local part = RealInstance.new("Part")
	part.Name = "DF"
	part.Size = roblox.Vector3.new(16, 1, 16)
	part.CFrame = roblox.CFrame.new(0, 0, 0)
	part.Parent = model
	model.Parent = worldRoot
	return model
end

---------------------------------------------------------------------------
-- The scenario
---------------------------------------------------------------------------

local function scenario()
	local owner = makePlayer(1, "Owner")
	local visitor = makePlayer(2, "Visitor")
	local dj = makePlayer(3, "DJ")
	LOCAL_PLAYER = owner
	playersService.LocalPlayer = owner
	addPlayer(owner)
	addPlayer(visitor)
	addPlayer(dj)

	-- Shared modules + license folder (as in the game) -------------------------------------------
	local autoRoot = RealInstance.new("Folder")
	autoRoot.Name = "AutoLights"
	autoRoot.Parent = replicated
	local shared = RealInstance.new("Folder")
	shared.Name = "Shared"
	shared.Parent = autoRoot
	for _, name in { "Palette", "PresetLibrary", "RhythmLibrary" } do
		local module = RealInstance.new("ModuleScript")
		module.Name = name
		module.Source = files[`autolights/vendor/shared/AutoLights.Shared.{name}.luau`]
		module.Parent = shared
	end
	local license = RealInstance.new("Folder")
	license.Name = "GLightsPhantomLicense"
	license.Parent = replicated
	for _, item in { { "ShowWarning", "RemoteEvent" }, { "Heartbeat", "RemoteEvent" }, { "TamperAlert", "RemoteEvent" }, { "ValidateLicense", "RemoteFunction" } } do
		local remote = RealInstance.new(item[2])
		remote.Name = item[1]
		remote.Parent = license
	end

	-- The built server folder, with the obfuscated modules swapped for fakes -----------------------
	local serverRoot = readModel("ServerScriptService/AutoLightsServer.rbxmx")
	serverRoot.Parent = scriptService
	local modules = serverRoot:FindFirstChild("Modules")
	modules:FindFirstChild("BeatService").Source = FAKE_BEAT
	modules:FindFirstChild("GLightsAdapter").Source = FAKE_GL
	modules:FindFirstChild("PyroService").Source = FAKE_PYRO

	local function requireModule(name)
		return makeEnv(serverRoot).require(modules:FindFirstChild(name))
	end
	local function requireConfig()
		return makeEnv(serverRoot).require(serverRoot:FindFirstChild("AutoLightsSyncConfig"))
	end

	-- Access ------------------------------------------------------------------------------------------
	local Access = requireModule("AutoLightsAccess")
	local CONTROL = requireConfig().CONTROL
	check(Access.IsOperator(owner) == true, "the game owner is an operator")
	check(Access.IsOperator(visitor) == false, "a visitor is not an operator")
	check(Access.IsOperator(nil) == false and Access.IsOperator({}) == false, "garbage is not an operator")
	CONTROL.UserIds = { 3 }
	Access.Forget(dj)
	check(Access.IsOperator(dj) == true, "CONTROL.UserIds grants access")
	CONTROL.UserIds = {}
	Access.Forget(dj)
	check(Access.IsOperator(dj) == false, "access is gone after removing the id")
	CONTROL.GroupId, CONTROL.MinRank = 555, 2
	visitor.rank = 1
	Access.Forget(visitor)
	check(Access.IsOperator(visitor) == false, "group rank below MinRank is refused")
	visitor.rank = 3
	Access.Forget(visitor)
	check(Access.IsOperator(visitor) == true, "group rank >= MinRank is allowed")
	CONTROL.GroupId = 0
	visitor.rank = 0
	Access.Forget(visitor)
	CONTROL.PublicAccess = true
	check(Access.IsOperator(visitor) == true, "PublicAccess opens it up")
	CONTROL.PublicAccess = false
	Access.Forget(visitor)
	studioMode = true
	check(Access.IsOperator(visitor) == true, "in Studio everybody is allowed")
	studioMode = false
	Access.Forget(visitor)
	creator.isGroup, creator.id = true, 777
	groupInfo[777] = { Owner = { Id = 2 } }
	Access.Forget(owner)
	check(Access.IsOperator(visitor) == true and Access.IsOperator(owner) == false, "for a group game the group owner is the owner")
	creator.isGroup, creator.id = false, 1
	Access.Forget(visitor)
	Access.Forget(owner)
	noErrors("access")

	-- Start the server scripts ---------------------------------------------------------------------------
	local floorModel = makeFloor("DanceFloorJin1")
	run(serverRoot:FindFirstChild("DanceFloorSync"))
	run(serverRoot:FindFirstChild("AutoLightsControl"))
	advance(0.5)
	noErrors("server start")

	local root = wrap(replicated):FindFirstChild("AutoLights")
	local remotes = root:FindFirstChild("Remotes")
	local audio = remotes:FindFirstChild("AudioTelemetry")
	local controlRemote = remotes:FindFirstChild("Control")
	local function attr(name)
		return root:GetAttribute(name)
	end
	local function controlRaw(player, action, value)
		return handlerOf(controlRemote)(player, action, value)
	end
	-- a person cannot press faster than the server's limit; let a moment pass between calls
	local function control(player, action, value)
		advance(0.1)
		return controlRaw(player, action, value)
	end
	local function sendTelemetry(player, payload)
		signalFor(unwrap(audio), "OnServerEvent"):Fire(player, payload)
	end

	checkEq(#tilesOf(floorModel), 64, "the floor is split into 8 x 8 tiles (from the config)")
	checkEq(floorModel:FindFirstChild("DF").Transparency, 1, "the DF part is hidden")
	checkEq(attr("SyncEnabled"), true, "sync starts ON")
	checkEq(attr("DanceFloorEnabled"), true, "dance floor starts ON")
	checkEq(attr("PyroEnabled"), true, "pyro starts ON")
	checkEq(attr("DFPatternCount"), 12, "12 patterns are published")
	checkEq(attr("Watermark"), "PAUL", "watermark attribute")
	check(attr("ControlReady") == true, "control ready")
	checkEq(owner:GetAttribute("AutoLightsOperator"), true, "owner is marked as operator")
	checkEq(visitor:GetAttribute("AutoLightsOperator"), false, "visitor is not marked")

	-- Control remote ----------------------------------------------------------------------------------------
	local denied = control(visitor, "Sync", false)
	check(denied.ok == false and denied.message == "Not allowed", "a visitor cannot use the panel")
	checkEq(attr("SyncEnabled"), true, "a refused call changes nothing")
	local result = control(owner, "Sync", false)
	check(result.ok == true and result.state.sync == false, "owner turns Sync off")
	checkEq(attr("SyncEnabled"), false, "SyncEnabled attribute follows")
	control(owner, "Sync", true)
	check(control(owner, "Nope").ok == false, "unknown action")
	check(control(owner, "Brightness", "x").ok == false, "brightness must be a number")
	check(control(owner, "Brightness", 0 / 0).ok == false, "NaN brightness refused")
	control(owner, "Brightness", 0.01)
	checkEq(attr("DFBrightness"), 0.1, "brightness is clamped to 0.1")
	control(owner, "Brightness", 1)
	check(control(owner, "Pattern", "x").ok == false, "pattern must be a number")
	local get = control(owner, "Get")
	check(get.ok == true and get.state.patternCount == 12, "Get returns the state")
	advance(2)
	local slow = 0
	for _ = 1, 20 do
		if controlRaw(owner, "Get").message == "Slow down" then
			slow += 1
		end
	end
	check(slow >= 6, `rate limit: {slow} of 20 rapid calls were refused`)
	advance(2)
	noErrors("control remote")

	-- Dance floor: beats -------------------------------------------------------------------------------------------
	local Beat = requireModule("BeatService")
	local before = attr("BeatCount") or 0
	sendTelemetry(owner, { rms = 300, dt = 0.05 })
	checkEq(attr("BeatCount"), before + 1, "a loud sample makes a beat")
	checkEq(attr("Bpm"), 120, "BPM is published")
	local peak = 0
	for _ = 1, 40 do
		heartbeats(1)
		peak = math.max(peak, maxChannel(tilesOf(floorModel)))
	end
	check(peak > 0.3, `tiles light up on a beat (peak {peak})`)
	noErrors("beat")

	advance(1)
	local beatsNow = attr("BeatCount")
	sendTelemetry(owner, { rms = 0 / 0 })
	sendTelemetry(owner, { rms = "loud" })
	sendTelemetry(owner, { rms = math.huge })
	sendTelemetry(owner, "junk")
	sendTelemetry(owner, {})
	checkEq(attr("BeatCount"), beatsNow, "invalid telemetry is ignored")
	noErrors("bad telemetry")

	advance(3)
	local stepsBefore = Beat.calls.step
	for _ = 1, 100 do
		sendTelemetry(owner, { rms = 1, dt = 0.05 })
	end
	check(Beat.calls.step - stepsBefore <= 40, `telemetry is rate limited ({Beat.calls.step - stepsBefore} of 100 processed)`)

	-- a muted owner must not freeze the show: the sender whose audio moves takes over
	advance(3)
	local baseline = attr("BeatCount")
	sendTelemetry(owner, { rms = 400 }) -- owner becomes the active sender and hears sound
	advance(0.2)
	for i = 1, 12 do
		sendTelemetry(owner, { rms = 0 }) -- ...then goes silent (muted)
		sendTelemetry(dj, { rms = 400 }) -- while the DJ still hears the music
		advance(0.2)
		if i == 3 then
			check(attr("BeatCount") <= baseline + 1, "a second sender does not take over right away")
		end
	end
	check(attr("BeatCount") >= baseline + 2, "a muted sender no longer blocks the beats")
	noErrors("telemetry owner")

	-- Sync / Dance Floor switches --------------------------------------------------------------------------------
	advance(2)
	control(owner, "Sync", false)
	local count = attr("BeatCount")
	local steps = Beat.calls.step
	sendTelemetry(owner, { rms = 500 })
	sendTelemetry(dj, { rms = 500 })
	checkEq(attr("BeatCount"), count, "no beats while Sync is OFF")
	checkEq(Beat.calls.step, steps, "the detector is not even fed while Sync is OFF")
	control(owner, "Sync", true)

	control(owner, "Pulse")
	heartbeats(2)
	check(maxChannel(tilesOf(floorModel)) > 0.3, "FLASH TEST lights the floor")
	control(owner, "DanceFloor", false)
	check(control(owner, "Pulse").ok == false, "FLASH TEST is refused while the floor is OFF")
	heartbeats(150)
	check(maxChannel(tilesOf(floorModel)) < 0.02, "the floor fades to black when Dance Floor is OFF")
	control(owner, "DanceFloor", true)
	advance(2)
	sendTelemetry(owner, { rms = 500 })
	check((attr("BeatCount") or 0) > count, "beats work again after switching back ON")

	-- pattern + brightness --------------------------------------------------------------------------------------
	local startPattern = attr("DFPatternNow")
	check(type(startPattern) == "number" and attr("DFPatternName") ~= "", "the current pattern is published")
	control(owner, "NextPattern")
	checkEq(attr("DFAutoPattern"), false, "picking a pattern pins it")
	local nextPattern = attr("DFPatternNow")
	checkEq(nextPattern, (startPattern % 12) + 1, "NextPattern moves to the next one")
	control(owner, "PrevPattern")
	checkEq(attr("DFPatternNow"), startPattern, "PrevPattern goes back")
	control(owner, "Pattern", 5)
	checkEq(attr("DFPatternNow"), 5, "a pattern can be picked by number")
	control(owner, "Pattern", 99)
	checkEq(attr("DFPatternNow"), 12, "an out-of-range pattern is clamped")
	control(owner, "AutoPattern", true)
	checkEq(attr("DFAutoPattern"), true, "auto pattern back ON")

	heartbeats(150)
	control(owner, "Brightness", 0.5)
	control(owner, "Pulse")
	heartbeats(1)
	local dim = maxChannel(tilesOf(floorModel))
	check(dim > 0.05 and dim <= 0.51, `brightness 50% caps the flash ({dim})`)
	control(owner, "Brightness", 1)
	noErrors("switches")

	-- floors that come and go -----------------------------------------------------------------------------------------
	floorModel:Destroy()
	heartbeats(5)
	local second = makeFloor("DanceFloorJin2")
	signalFor(worldRoot, "ChildAdded"):Fire(wrap(second))
	advance(1)
	heartbeats(3)
	checkEq(#tilesOf(second), 64, "a floor added later gets its tiles")
	noErrors("floors")

	-- Bridge to the G-Lights modules -----------------------------------------------------------------------------------
	check(attr("HasLights") == true and attr("HasPyro") == true, "the bridge finds the G-Lights modules")
	local GL = requireModule("GLightsAdapter")
	local Pyro = requireModule("PyroService")

	local detector = Beat.new()
	check(detector:StepFromRms(0.05, 100, 400) ~= nil, "BeatService works while Sync is ON")
	control(owner, "Sync", false)
	local stepsSeen = Beat.calls.step
	check(detector:StepFromRms(0.05, 200, 400) == nil and detector:ForceBeat(200) == nil, "BeatService (every instance) is silent while Sync is OFF")
	checkEq(Beat.calls.step, stepsSeen, "the original was not called")
	control(owner, "Sync", true)

	local fired = control(owner, "Fire", "CO2")
	check(fired.ok == true, "CO2 fires: " .. tostring(fired.message))
	local last = Pyro.log[#Pyro.log]
	check(last ~= nil and last[1] == "FPA" and last[2] == "AllHold", "CO2 = FPA AllHold")
	check(control(owner, "Fire", "CONFETTI").ok == true and control(owner, "Fire", "SMOKE").ok == true, "confetti and smoke fire")
	check(control(owner, "Fire", "LASER").ok == false, "unknown effect refused")
	control(owner, "StopPyro")
	check(Pyro.log[#Pyro.log][1] == "AllOff", "STOP sends AllOff")
	control(owner, "Pyro", false)
	check(control(owner, "Fire", "CO2").ok == false, "no bursts while Pyro is OFF")
	local direct = Pyro.new()
	local okDirect, why = direct:Fire("FPA", "AllHold", {}, false, nil)
	check(okDirect == false and why == "pyro switch is off", "PyroService (every instance) obeys the Pyro switch")
	control(owner, "Pyro", true)
	check(direct:Fire("FPA", "AllHold", {}, false, nil) == true, "and works again when switched ON")

	control(owner, "Blackout")
	checkEq(attr("Blackout"), true, "Blackout flag")
	check(attr("SyncEnabled") == false and attr("DanceFloorEnabled") == false, "Blackout stops sync and the floor")
	local sawFade, sawCleanup = false, false
	for _, entry in GL.log do
		if entry[1] == "Run" and entry[2] == "ALL" and entry[3] == "FadeOff" then sawFade = true end
		if entry[1] == "CleanupPreset" then sawCleanup = true end
	end
	check(sawFade and sawCleanup, "Blackout fades every light off")
	control(owner, "Restore")
	checkEq(attr("Blackout"), false, "Restore clears the flag")
	check(attr("SyncEnabled") == true and attr("DanceFloorEnabled") == true, "Restore turns sync and the floor back on")
	check(GL.log[#GL.log][1] == "Baseline" and GL.log[#GL.log][2] == "Color3", "Restore puts the lights back on the baseline")
	noErrors("bridge")

	-- RhythmRunner -----------------------------------------------------------------------------------------------------------
	local RhythmRunner = requireModule("RhythmRunner")
	local RhythmLibrary = makeEnv(serverRoot).require(shared:FindFirstChild("RhythmLibrary"))
	local rlog = {}
	local fakeGL = {
		Run = function(_, folder, fn, args) table.insert(rlog, { folder, fn, args and args[1] }) end,
		CleanupPreset = function() table.insert(rlog, { "CleanupPreset" }) end,
		EnsureAllOnBaseline = function() end,
		HardResetAll = function() table.insert(rlog, { "HardReset" }) end,
	}
	local plog = {}
	local fakePyro = { Fire = function(_, device, pattern) table.insert(plog, device .. "/" .. pattern) end }
	local runner = RhythmRunner.new({ Log = function() end }, fakeGL, fakePyro)
	local circle
	for _, preset in RhythmLibrary.list do
		local text = ""
		for _, step in preset.onBeat or {} do
			if step.fn == "Delay" then text = "delay" end
		end
		if text == "delay" then circle = preset break end
	end
	check(circle ~= nil, "found a rhythm preset that uses sys Delay")
	runner:Play(circle)
	rlog = {}
	runner:OnBeat({ beatIndex = 1, barIndex = 0, level = "Med" })
	local speedsAtBeat = 0
	for _, entry in rlog do if entry[2] == "MotorSpeed" then speedsAtBeat += 1 end end
	checkEq(speedsAtBeat, 1, "the beat sets the head speed once")
	advance(0.3)
	local speeds = 0
	local idle
	for _, entry in rlog do if entry[2] == "MotorSpeed" then speeds += 1 idle = entry[3] end end
	checkEq(speeds, 2, "the Delay step runs: heads slow down after the beat")
	check(idle ~= nil and math.abs(idle - 0.006) < 1e-6, "back to the idle speed (0.006)")
	rlog = {}
	runner:OnBeat({ beatIndex = 2, barIndex = 0 })
	runner:Stop()
	advance(0.3)
	local late = 0
	for _, entry in rlog do if entry[2] == "MotorSpeed" then late += 1 end end
	checkEq(late, 1, "a Delay of a stopped preset is dropped")
	runner:Play(circle)
	rlog = {}
	control(owner, "Sync", false)
	runner:OnBeat({ beatIndex = 3 })
	checkEq(#rlog, 0, "RhythmRunner does nothing while Sync is OFF")
	control(owner, "Sync", true)
	runner:Stop()
	-- branch, level names, sys HardResetAll
	local branchLog = {}
	local branchRunner = RhythmRunner.new({ Log = function() end }, {
		Run = function(_, _, fn) table.insert(branchLog, fn) end, CleanupPreset = function() end, EnsureAllOnBaseline = function() end,
		HardResetAll = function() table.insert(branchLog, "HardReset") end,
	}, fakePyro)
	branchRunner:Play({ onBeat = {
		{ type = "branch", key = "flag", ifTrue = nil, ifFalse = { { type = "gl", folder = "ALL", fn = "False" } } },
		{ type = "set", key = "flag", value = true },
		{ type = "branch", key = "flag", ifTrue = { { type = "gl", folder = "ALL", fn = "True" } }, ifFalse = { { type = "gl", folder = "ALL", fn = "False" } } },
		{ type = "sys", fn = "HardResetAll" },
		{ type = "pyro", device = "FPA", pattern = "AllHold", gate = { levelAtLeast = "Medium" } },
	} })
	branchRunner:OnBeat({ beatIndex = 1, level = "Med" })
	checkEq(table.concat(branchLog, ","), "False,True,HardReset", "branch picks the right side; HardResetAll is handled")
	checkEq(plog[#plog], "FPA/AllHold", "level 'Med' satisfies 'Medium'")
	branchRunner:Stop()
	noErrors("rhythm runner")

	-- PresetRunner -------------------------------------------------------------------------------------------------------------
	local PresetRunner = requireModule("PresetRunner")
	local pgl = {}
	local presetRunner = PresetRunner.new({ Log = function() end }, {
		Run = function(_, _, fn) table.insert(pgl, fn) end, CleanupPreset = function() end, EnsureAllOnBaseline = function() end, HardResetAll = function() end,
	})
	local function looper(name)
		return { id = name, phases = { loop = { A = { { type = "gl", folder = "ALL", fn = name, args = {} }, { type = "wait", seconds = 0.1 } } } } }
	end
	local function countOf(name)
		local n = 0
		for _, fn in pgl do if fn == name then n += 1 end end
		return n
	end
	presetRunner:Play(looper("A"))
	advance(0.55)
	local aSoFar = countOf("A")
	check(aSoFar >= 3, `preset A runs ({aSoFar} steps)`)
	presetRunner:Play(looper("B"))
	advance(0.7)
	check(countOf("B") >= 4, "preset B runs")
	checkEq(countOf("A"), aSoFar + 0, "the old preset stops when a new one starts (used to keep running)")
	check(presetRunner:IsRunning() == true, "the runner reports the new preset as running")
	presetRunner:Stop()
	advance(0.3)
	check(presetRunner:IsRunning() == false, "Stop stops")
	presetRunner:Play({ id = "empty", phases = {} }) -- no loop at all: used to spin forever
	advance(1)
	check(presetRunner:IsRunning() == true, "a preset without a loop does not freeze the server")
	presetRunner:Stop()
	advance(0.2)
	noErrors("preset runner")

	-- ShowEngine + friends (not wired by any script, but fixed) -------------------------------------------------------------------
	local Logger = requireModule("LoggerService").new()
	local Permission = requireModule("PermissionService").new(Logger)
	check(Permission:IsOperator(owner) == true and Permission:IsOperator(visitor) == false, "PermissionService follows the access rules")
	local Throttle = requireModule("ThrottleService").new(Logger)
	check(Throttle:Allow(owner, "x", 2) and Throttle:Allow(owner, "x", 2) and not Throttle:Allow(owner, "x", 2), "ThrottleService limits per second")
	playersService.PlayerRemoving:Fire(owner)
	check(next(Throttle.perPlayer) == nil, "ThrottleService forgets players who leave")

	local slog = {}
	local showGL = setmetatable({}, { __index = function(_, key)
		return function(_, ...) table.insert(slog, { key, ... }) end
	end })
	local showPyro = { SetArmed = function() end, AllOff = function() end, Fire = function() end }
	local updates = 0
	local ShowEngine = requireModule("ShowEngine")
	local engine = ShowEngine.new({
		LoggerService = Logger, PermissionService = Permission, ThrottleService = Throttle,
		GLightsAdapter = showGL, PyroService = showPyro,
		BeatSyncEngine = { GetState = function() return { beatsInBar = 4, bpm = 120 } end, SetMinBeatGap = function() end, TapTempo = function() end },
		StateUpdate = { FireAllClients = function() updates += 1 end },
	})
	engine:OnShowCommand(visitor, { cmd = "BLACKOUT" })
	checkEq(#slog, 0, "ShowEngine refuses commands from a visitor")
	engine:OnShowCommand(owner, { cmd = "MANUAL", folder = "ALL", fn = "Color", args = "not a table" })
	local ran = false
	for _, entry in slog do if entry[1] == "Run" then ran = true end end
	check(not ran, "MANUAL with non-table args is ignored")
	advance(1)
	engine:OnShowCommand(owner, { cmd = "MANUAL", folder = "ALL", fn = "Color", args = {} })
	ran = false
	for _, entry in slog do if entry[1] == "Run" then ran = true end end
	check(ran, "a valid MANUAL command runs")
	engine:OnShowCommand(owner, { cmd = "PLAY_CINEMATIC", presetId = 42 })
	check(engine.state.mode ~= "CINEMATIC", "a non-string preset id is ignored")

	-- a cinematic whose loop has no wait must not freeze the server
	local PresetLibrary = makeEnv(serverRoot).require(shared:FindFirstChild("PresetLibrary"))
	PresetLibrary.byId._spin = { id = "_spin", phases = { setup = {}, intro = {}, loop = { A = {}, B = {}, C = {} }, outro = {} } }
	advance(2)
	engine:PlayCinematic("_spin")
	advance(1)
	checkEq(engine.state.mode, "CINEMATIC", "a cinematic without waits keeps yielding")
	engine:StopAll(owner)
	engine._activePyroBeatId = "PY_06_CO2_ON_EVERY_BEAT"
	engine.state.pyroArmed = true
	engine:OnBeat({}) -- no beatIndex
	noErrors("show engine")

	-- Client: telemetry ------------------------------------------------------------------------------------------------------------
	local music = RealInstance.new("Sound")
	music.Name = "ServerMusic"
	music.Parent = soundFolder
	extras[idOf(music)] = { IsPlaying = true, PlaybackLoudness = 300 }
	local telemetry = readModel("StarterPlayer/StarterPlayerScripts/AutoLightsTelemetry.rbxmx")
	table.clear(fireServerLog)
	control(owner, "Sync", true)
	license.Parent = nil -- no license folder: the license check waits in the background, telemetry does not
	run(telemetry)
	advance(1.1)
	noErrors("telemetry start")
	local sent = 0
	local lastRms
	for _, entry in fireServerLog do
		if entry[1] == "AudioTelemetry" then
			sent += 1
			lastRms = entry[2].rms
		end
	end
	check(sent >= 15 and sent <= 22, `telemetry starts at once (license folder missing) and sends about 20 per second ({sent})`)
	checkEq(lastRms, 300, "it reports the loudness of the playing sound")
	license.Parent = replicated -- the background license check finds the folder and goes on
	advance(1)
	noErrors("license check")
	control(owner, "Sync", false)
	table.clear(fireServerLog)
	advance(1)
	checkEq(#fireServerLog, 0, "no telemetry while Sync is OFF")
	control(owner, "Sync", true)
	advance(0.5)
	check(#fireServerLog > 5, "telemetry resumes when Sync is ON again")
	advance(30) -- the license monitor gives up quietly for visitors
	noErrors("telemetry loop")

	-- Client: control panel ----------------------------------------------------------------------------------------------------------
	extras[idOf(music)].IsPlaying = false -- stop feeding beats from the telemetry client
	local gui = readModel("StarterGui/AutoLightsPanel.rbxmx")
	owner:SetAttribute("AutoLightsOperator", false)
	run(gui:FindFirstChild("AutoLightsPanelClient"))
	advance(0.2)
	noErrors("panel start")
	local ui = wrap(gui)
	local panel = ui.Panel
	check(panel.Visible == false and ui.OpenButton.Visible == false, "the panel is hidden for a non-operator")
	owner:SetAttribute("AutoLightsOperator", true)
	advance(0.1)
	check(ui.OpenButton.Visible == true, "the LIGHTS button shows for an operator")
	fire(ui.OpenButton)
	advance(0.5)
	check(panel.Visible == true, "the button opens the panel")
	checkEq(panel.Watermark.Text, "PAUL", "watermark on the panel")
	checkEq(panel.WatermarkBig.Text, "PAUL", "big watermark on the panel")
	checkEq(panel.SyncChip.Label.Text, "SYNC ON", "status chip shows SYNC ON")

	fire(panel.Left.Toggle_Sync)
	advance(0.3)
	checkEq(attr("SyncEnabled"), false, "the Sync switch reaches the server")
	checkEq(panel.SyncChip.Label.Text, "SYNC OFF", "status chip follows")
	check(math.abs(panel.Left.Toggle_Sync.Track.Knob.Position.X.Scale - 0.05) < 1e-3, "the switch knob moves left")
	checkEq(panel.Toast.Message.Text, "Sync OFF", "toast shows the result")
	fire(panel.Left.Toggle_Sync)
	advance(0.3)
	checkEq(panel.SyncChip.Label.Text, "SYNC ON", "and back ON")

	fire(panel.Left.Toggle_DanceFloor)
	advance(0.3)
	checkEq(attr("DanceFloorEnabled"), false, "Dance Floor switch")
	check(panel.Left.Flash.Interactable == false, "FLASH TEST is greyed out while the floor is OFF")
	fire(panel.Left.Toggle_DanceFloor)
	advance(0.3)
	check(panel.Left.Flash.Interactable == true, "FLASH TEST is usable again")

	fire(panel.Left.PatternRow.Next)
	advance(0.3)
	checkEq(attr("DFAutoPattern"), false, "the pattern arrows pin a pattern")
	check(string.find(panel.Left.PatternRow.PatternText.Text, "/12", 1, true) ~= nil, "pattern label: " .. panel.Left.PatternRow.PatternText.Text)
	fire(panel.Left.Toggle_AutoPattern)
	advance(0.3)
	checkEq(attr("DFAutoPattern"), true, "Auto Pattern switch")

	fire(panel.Left.BrightnessRow.Minus)
	advance(0.3)
	checkEq(attr("DFBrightness"), 0.9, "brightness minus")
	checkEq(panel.Left.BrightnessRow.Value.Text, "90%", "brightness label")
	fire(panel.Left.BrightnessRow.Plus)
	advance(0.3)
	checkEq(attr("DFBrightness"), 1, "brightness plus")

	fire(panel.Left.Flash)
	advance(0.3)
	check(panel.Toast.Message.Text == "Flash", "FLASH TEST button: " .. panel.Toast.Message.Text)

	check(panel.Right.Fire_CO2.Interactable == true, "pyro buttons are usable when the pyro system exists")
	fire(panel.Right.Fire_CO2)
	advance(0.3)
	check(panel.Toast.Message.Text == "CO2 fired", "CO2 button: " .. panel.Toast.Message.Text)
	fire(panel.Right.Toggle_Pyro)
	advance(0.3)
	checkEq(attr("PyroEnabled"), false, "Pyro switch")
	check(panel.Right.Fire_CO2.Interactable == false and panel.Right.StopPyro.Interactable == true, "bursts are greyed out with Pyro OFF, STOP stays usable")
	fire(panel.Right.Toggle_Pyro)
	advance(0.3)
	root:SetAttribute("HasPyro", false)
	advance(0.1)
	check(panel.Right.Fire_CO2.Interactable == false and panel.Right.Toggle_Pyro.Interactable == false, "pyro controls are greyed out when the system is missing")
	check(string.find(panel.Right.Toggle_Pyro.Subtitle.Text, "not detected", 1, true) ~= nil, "and say why")
	root:SetAttribute("HasPyro", true)

	fire(panel.Right.Blackout)
	advance(0.3)
	checkEq(panel.SyncChip.Label.Text, "BLACKOUT", "BLACKOUT button")
	fire(panel.Right.Restore)
	advance(0.3)
	checkEq(panel.SyncChip.Label.Text, "SYNC ON", "RESTORE button")

	local dotBefore = panel.BeatTile.BeatDot.BackgroundTransparency
	root:SetAttribute("BeatCount", (attr("BeatCount") or 0) + 1)
	advance(0.1)
	check(panel.BeatTile.BeatDot.BackgroundTransparency ~= nil and dotBefore ~= nil, "the beat dot reacts to beats")

	services.UserInputService.InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.K }, false)
	advance(0.5)
	check(panel.Visible == false, "K closes the panel")
	services.UserInputService.InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.K }, false)
	advance(0.5)
	check(panel.Visible == true, "K opens the panel")
	owner:SetAttribute("AutoLightsOperator", false)
	advance(0.5)
	check(panel.Visible == false and ui.OpenButton.Visible == false, "losing operator rights closes the panel")
	noErrors("panel")
end

task.spawn(scenario)
advance(0.01)
advance(5)
noErrors("end")

-- warn() calls the scripts made on purpose (none expected in a healthy setup)
local unexpected = {}
for _, text in warnings do
	if not string.find(text, "GLightsLicense", 1, true) then
		table.insert(unexpected, text)
	end
end
check(#unexpected == 0, "no warnings from the scripts: " .. table.concat(unexpected, " | "))

print(`{passed} checks passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
