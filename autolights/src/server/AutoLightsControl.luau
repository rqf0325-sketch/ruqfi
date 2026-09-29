-- AutoLightsControl.server.lua  —  AutoLights Control Panel (server side)
-- Place in: ServerScriptService > AutoLightsServer
-- by PAUL
--
-- Runs the switches and buttons of the AutoLightsPanel GUI:
--   Sync ON/OFF, Dance Floor ON/OFF, Auto pattern, Pattern / Brightness / Test flash,
--   Pyro ON/OFF + CO2 / Confetti / Smoke bursts + Stop pyro, Blackout / Restore.
--
-- How it works
--   • The switches are attributes on ReplicatedStorage.AutoLights (see AutoLightsState and the
--     header of DanceFloorSync). Only this script writes them, so a player cannot flip a
--     switch on his own; the panel just calls the Control remote.
--   • Every call is checked on the server: the player must be an operator (AutoLightsAccess:
--     owner, CONTROL.UserIds, CONTROL.GroupId, or anybody in Roblox Studio) and is rate limited.
--   • The Sync and Dance Floor switches work by themselves (DanceFloorSync obeys them).
--     Pyro and the GLights Blackout/Restore reach the G-Lights modules through a "bridge":
--     the vendor classes are wrapped so the Pyro switch and the Sync switch also apply to
--     them, and Blackout/Restore use their GLightsAdapter. If those modules are not
--     available the bridge stays off (HasLights / HasPyro = false) and the panel greys the
--     buttons out; nothing else is affected.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoLightsServer = script.Parent
local Modules          = AutoLightsServer:WaitForChild("Modules")
local Access           = require(Modules:WaitForChild("AutoLightsAccess"))
local State            = require(Modules:WaitForChild("AutoLightsState"))
local LoggerService    = require(Modules:WaitForChild("LoggerService"))
local Logger           = LoggerService.new()

local okConfig, SyncCFG = pcall(function()
	return require(AutoLightsServer:WaitForChild("AutoLightsSyncConfig", 5))
end)
local CONTROL = (okConfig and type(SyncCFG) == "table" and SyncCFG.CONTROL) or {}

-- ─────────────────────────────────────────────────────────────────
-- Folders and remotes
-- ─────────────────────────────────────────────────────────────────
local function getOrCreate(parent, className, name)
	local instance = parent:FindFirstChild(name)
	if not instance then
		instance = Instance.new(className)
		instance.Name = name
		instance.Parent = parent
	end
	return instance
end

local autoRoot      = getOrCreate(ReplicatedStorage, "Folder", "AutoLights")
local remotes       = getOrCreate(autoRoot, "Folder", "Remotes")
local controlRemote = getOrCreate(remotes, "RemoteFunction", "Control")

local function initAttribute(name, value)
	if autoRoot:GetAttribute(name) == nil then
		autoRoot:SetAttribute(name, value)
	end
end

initAttribute("SyncEnabled", CONTROL.SyncOnAtStart ~= false)
initAttribute("DanceFloorEnabled", CONTROL.DanceFloorOnAtStart ~= false)
initAttribute("PyroEnabled", CONTROL.PyroOnAtStart ~= false)
initAttribute("DFAutoPattern", true)
initAttribute("DFBrightness", 1)
initAttribute("Blackout", false)
initAttribute("HasLights", false)
initAttribute("HasPyro", false)
autoRoot:SetAttribute("Watermark", tostring(CONTROL.Watermark or "PAUL"))
autoRoot:SetAttribute("ControlReady", true)

-- ─────────────────────────────────────────────────────────────────
-- Bridge to the G-Lights modules (best effort, never fatal)
-- ─────────────────────────────────────────────────────────────────
local bridge = { GLClass = nil, PyroClass = nil, gl = nil, pyro = nil }

local function capture(kind, self)
	if bridge[kind] == nil and type(self) == "table" then
		bridge[kind] = self
	end
end

-- Replaces class[name] by a wrapper; `wrapper(original, self, ...)` decides what happens.
local function patch(class, name, wrapper)
	local original = class[name]
	if type(original) ~= "function" then
		return false
	end
	class[name] = function(self, ...)
		return wrapper(original, self, ...)
	end
	return true
end

local function installBridge()
	-- The vendor modules refuse to load until the license folder exists.
	if not ReplicatedStorage:WaitForChild("GLightsPhantomLicense", 30) then
		warn("[AutoLightsControl] license folder not found; Pyro / GLights buttons are off")
		return
	end

	local okBeat, BeatService = pcall(function() return require(Modules:WaitForChild("BeatService")) end)
	if okBeat and type(BeatService) == "table" then
		-- the Sync switch also silences every BeatService in the game (AutoSync included)
		patch(BeatService, "StepFromRms", function(original, self, ...)
			if not State.SyncEnabled() then return nil end
			return original(self, ...)
		end)
		patch(BeatService, "ForceBeat", function(original, self, ...)
			if not State.SyncEnabled() then return nil end
			return original(self, ...)
		end)
	end

	local okGL, GLightsAdapter = pcall(function() return require(Modules:WaitForChild("GLightsAdapter")) end)
	if okGL and type(GLightsAdapter) == "table" then
		bridge.GLClass = GLightsAdapter
		for _, name in { "Run", "CleanupPreset", "EnsureAllOnBaseline", "HardResetAll" } do
			patch(GLightsAdapter, name, function(original, self, ...)
				capture("gl", self)
				return original(self, ...)
			end)
		end
		autoRoot:SetAttribute("HasLights", true)
	end

	local okPyro, PyroService = pcall(function() return require(Modules:WaitForChild("PyroService")) end)
	if okPyro and type(PyroService) == "table" then
		bridge.PyroClass = PyroService
		patch(PyroService, "Fire", function(original, self, ...)
			capture("pyro", self)
			if not State.PyroEnabled() then
				return false, "pyro switch is off"
			end
			return original(self, ...)
		end)
		autoRoot:SetAttribute("HasPyro", true)
	end
end

task.spawn(function()
	local ok, err = pcall(installBridge)
	if not ok then
		warn("[AutoLightsControl] bridge failed: " .. tostring(err))
	end
end)

local function getGL()
	if bridge.gl then return bridge.gl end
	if bridge.GLClass then
		local ok, obj = pcall(function() return bridge.GLClass.new(Logger) end)
		if ok and obj then bridge.gl = obj end
	end
	return bridge.gl
end

local function getPyro()
	if bridge.pyro then return bridge.pyro end
	if bridge.PyroClass then
		local ok, obj = pcall(function() return bridge.PyroClass.new(Logger, getGL()) end)
		if not ok or not obj then
			ok, obj = pcall(function() return bridge.PyroClass.new(Logger) end)
		end
		if ok and obj then bridge.pyro = obj end
	end
	return bridge.pyro
end

local function warmWhite()
	local ok, color = pcall(function()
		local shared = autoRoot:FindFirstChild("Shared")
		local palette = shared and shared:FindFirstChild("Palette") and require(shared.Palette)
		return palette and palette.WARM_WHITE
	end)
	return if ok and typeof(color) == "Color3" then color else Color3.fromRGB(255, 214, 170)
end

-- ─────────────────────────────────────────────────────────────────
-- State snapshot
-- ─────────────────────────────────────────────────────────────────
local function patternCount()
	return math.max(1, math.floor(tonumber(autoRoot:GetAttribute("DFPatternCount")) or 12))
end

local function snapshot()
	return {
		sync         = State.SyncEnabled(),
		danceFloor   = State.DanceFloorEnabled(),
		pyro         = State.PyroEnabled(),
		blackout     = autoRoot:GetAttribute("Blackout") == true,
		autoPattern  = autoRoot:GetAttribute("DFAutoPattern") ~= false,
		brightness   = tonumber(autoRoot:GetAttribute("DFBrightness")) or 1,
		pattern      = tonumber(autoRoot:GetAttribute("DFPatternNow")) or 1,
		patternName  = tostring(autoRoot:GetAttribute("DFPatternName") or ""),
		patternCount = patternCount(),
		hasLights    = autoRoot:GetAttribute("HasLights") == true,
		hasPyro      = autoRoot:GetAttribute("HasPyro") == true,
	}
end

-- ─────────────────────────────────────────────────────────────────
-- Actions
-- ─────────────────────────────────────────────────────────────────
local function fail(message)
	return { ok = false, message = message, state = snapshot() }
end

local function done(message)
	return { ok = true, message = message, state = snapshot() }
end

local PYRO_BURSTS = {
	CO2      = { "FPA", "AllHold", { duration = 0.25 } },
	CONFETTI = { "CONFETTI", "Burst", { duration = 1.2 } },
	SMOKE    = { "SMOKE", "Burst", { duration = 1.0 } },
}

local function pyroAllOff()
	local pyro = bridge.pyro or (bridge.PyroClass and getPyro())
	if pyro then
		pcall(function() pyro:AllOff() end)
	end
end

local function setPyro(on)
	State.Set("PyroEnabled", on)
	local pyro = getPyro()
	if pyro then
		pcall(function() pyro:SetArmed(on) end)
		if not on then pyroAllOff() end
	end
end

local ACTIONS = {}

function ACTIONS.Sync(value)
	State.Set("SyncEnabled", value == true)
	return done(if value == true then "Sync ON" else "Sync OFF")
end

function ACTIONS.DanceFloor(value)
	State.Set("DanceFloorEnabled", value == true)
	return done(if value == true then "Dance floor ON" else "Dance floor OFF")
end

function ACTIONS.Pyro(value)
	setPyro(value == true)
	return done(if value == true then "Pyro ON" else "Pyro OFF")
end

function ACTIONS.AutoPattern(value)
	autoRoot:SetAttribute("DFAutoPattern", value == true)
	return done(if value == true then "Auto pattern ON" else "Pattern locked")
end

function ACTIONS.Brightness(value)
	local number = tonumber(value)
	if not number or number ~= number then return fail("Invalid brightness") end
	autoRoot:SetAttribute("DFBrightness", math.clamp(number, 0.1, 1))
	return done("Brightness set")
end

local function stepPattern(delta)
	local count = patternCount()
	local current = math.floor(tonumber(autoRoot:GetAttribute("DFPatternNow")) or 1)
	autoRoot:SetAttribute("DFPattern", ((current - 1 + delta) % count) + 1)
	autoRoot:SetAttribute("DFAutoPattern", false) -- picking a pattern pins it
	return done("Pattern locked")
end

function ACTIONS.NextPattern() return stepPattern(1) end
function ACTIONS.PrevPattern() return stepPattern(-1) end

function ACTIONS.Pattern(value)
	local index = tonumber(value)
	if not index or index ~= index then return fail("Invalid pattern") end
	autoRoot:SetAttribute("DFPattern", math.clamp(math.floor(index), 1, patternCount()))
	autoRoot:SetAttribute("DFAutoPattern", false)
	return done("Pattern locked")
end

function ACTIONS.Pulse()
	if not State.DanceFloorEnabled() then return fail("Dance floor is OFF") end
	autoRoot:SetAttribute("DFPulse", (tonumber(autoRoot:GetAttribute("DFPulse")) or 0) + 1)
	return done("Flash")
end

function ACTIONS.StopPyro()
	pyroAllOff()
	return done("Pyro stopped")
end

function ACTIONS.Fire(kind)
	local burst = type(kind) == "string" and PYRO_BURSTS[kind]
	if not burst then return fail("Unknown effect") end
	if not State.PyroEnabled() then return fail("Pyro is OFF") end
	local pyro = getPyro()
	if not pyro then return fail("Pyro system not found") end
	-- The Pyro switch is the arm switch: PyroService only fires when armed.
	pcall(function() pyro:SetArmed(true) end)
	local ok, fired, why = pcall(function() return pyro:Fire(burst[1], burst[2], table.clone(burst[3]), true, nil) end)
	if not ok then return fail("Pyro error") end
	if fired == false then return fail(tostring(why or "Pyro blocked")) end
	return done(kind .. " fired")
end

function ACTIONS.Blackout()
	autoRoot:SetAttribute("Blackout", true)
	State.Set("SyncEnabled", false)
	State.Set("DanceFloorEnabled", false)
	pyroAllOff()
	local gl = getGL()
	if gl then
		pcall(function() gl:CleanupPreset() end)
		pcall(function() gl:Run("ALL", "FadeOff", {}, nil, nil, "preset") end)
	end
	return done("Blackout")
end

function ACTIONS.Restore()
	autoRoot:SetAttribute("Blackout", false)
	State.Set("SyncEnabled", true)
	State.Set("DanceFloorEnabled", true)
	local gl = getGL()
	if gl then
		pcall(function() gl:EnsureAllOnBaseline(warmWhite()) end)
	end
	return done("Restored")
end

-- ─────────────────────────────────────────────────────────────────
-- Remote
-- ─────────────────────────────────────────────────────────────────
local lastCall = {} -- [Player] = { start, count }

local function allowed(player)
	local now = os.clock()
	local slot = lastCall[player]
	if not slot or now - slot.start >= 1 then
		slot = { start = now, count = 0 }
		lastCall[player] = slot
	end
	slot.count += 1
	return slot.count <= 12
end

controlRemote.OnServerInvoke = function(player, action, value)
	if not Access.IsOperator(player) then
		return { ok = false, message = "Not allowed" }
	end
	if not allowed(player) then
		return fail("Slow down")
	end
	if action == "Get" then
		return { ok = true, state = snapshot() }
	end
	local handler = type(action) == "string" and ACTIONS[action]
	if not handler then
		return fail("Unknown action")
	end
	return handler(value)
end

-- ─────────────────────────────────────────────────────────────────
-- Who sees the panel
-- ─────────────────────────────────────────────────────────────────
local function markOperator(player)
	task.spawn(function()
		local isOperator = Access.IsOperator(player)
		if player.Parent == Players then
			player:SetAttribute("AutoLightsOperator", isOperator)
		end
	end)
end

Players.PlayerAdded:Connect(markOperator)
for _, player in Players:GetPlayers() do
	markOperator(player)
end
Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
end)
