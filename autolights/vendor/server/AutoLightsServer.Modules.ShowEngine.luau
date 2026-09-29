-- ServerScriptService/AutoLightsServer/Modules/ShowEngine.lua
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShowEngine = {}
ShowEngine.__index = ShowEngine

local AutoLights = ReplicatedStorage:WaitForChild("AutoLights")
local Shared = AutoLights:WaitForChild("Shared")
local PresetLibrary = require(Shared:WaitForChild("PresetLibrary"))
local RhythmLibrary = require(Shared:WaitForChild("RhythmLibrary"))
local Palette = require(Shared:WaitForChild("Palette"))

local function now() return os.clock() end

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k,v in pairs(t) do o[k] = deepCopy(v) end
	return o
end

local function exportPalette()
	local out = {}
	for k,v in pairs(Palette) do
		if typeof(v) == "Color3" then
			out[k] = v
		end
	end
	return out
end

local function colorFromAny(x)
	if typeof(x) == "Color3" then return x end
	if type(x) == "string" then
		return Palette[x] or Palette.WARM_WHITE
	end
	if type(x) == "table" and x.r and x.g and x.b then
		return Color3.new(tonumber(x.r) or 1, tonumber(x.g) or 1, tonumber(x.b) or 1)
	end
	return Palette.WARM_WHITE
end

local function colorToSerializable(c)
	if typeof(c) == "Color3" then
		return {r=c.R, g=c.G, b=c.B}
	end
	return nil
end

-- ===== Pyro preset list (10) =====
local PYRO_PRESETS = {
	-- non-beat sequences
	{ id="PY_01_CO2_BURST",     name="CO2 BURST",        category="CO2",      mode="sequence",
		steps={{device="FPA",pattern="AllHold",args={duration=0.25}}} },

	{ id="PY_02_CO2_WAVE",      name="CO2 WAVE",         category="CO2",      mode="sequence",
		steps={{device="FPA",pattern="WaveL2R",args={interval=0.07}}} },

	{ id="PY_03_FIRE_WALK_L2R", name="FIRE WALK L2R",    category="FIRE",     mode="sequence",
		steps={{device="FPA",pattern="WaveL2R",args={interval=0.09}},
			{wait=0.25},
			{device="FPA",pattern="WaveL2R",args={interval=0.09}} } },

	{ id="PY_04_FIRE_INOUT",    name="FIRE INOUT",       category="FIRE",     mode="sequence",
		steps={{device="FPA",pattern="CenterOut",args={interval=0.10}},
			{wait=0.20},
			{device="FPA",pattern="EdgeIn",args={interval=0.10}} } },

	{ id="PY_05_CONFETTI_BURST",name="CONFETTI BURST",   category="CONFETTI", mode="sequence",
		steps={{device="CONFETTI",pattern="Burst",args={duration=1.2}}} },

	-- beat synced
	{ id="PY_06_CO2_ON_EVERY_BEAT", name="CO2 EVERY BEAT", category="CO2", mode="beat",
		onBeat={device="FPA",pattern="AllHold",args={duration=0.08}, everyNBeats=1} },

	{ id="PY_07_FIRE_ON_BEAT",  name="FIRE ON BEAT",     category="FIRE", mode="beat",
		onBeat={device="FPA",pattern="CenterPunch",args={duration=0.10}, everyNBeats=1} },

	{ id="PY_08_CONFETTI_ON_BAR", name="CONFETTI ON BAR", category="CONFETTI", mode="beat",
		onBar={device="CONFETTI",pattern="Burst",args={duration=1.0}, everyNBars=1} },

	{ id="PY_09_SMOKE_ON_2BEAT", name="SMOKE ON 2BEAT",   category="SMOKE", mode="beat",
		onBeat={device="SMOKE",pattern="Burst",args={duration=1.0}, everyNBeats=2} },

	{ id="PY_10_MEGA_COMBO",    name="MEGA COMBO",       category="MEGA", mode="beat",
		onBar={device="FPA",pattern="CenterOut",args={interval=0.09}, everyNBars=1},
		onBeat={device="SMOKE",pattern="Burst",args={duration=0.8}, everyNBeats=4},
	},
}

local PYRO_BY_ID = {}
for _,p in ipairs(PYRO_PRESETS) do PYRO_BY_ID[p.id] = p end

function ShowEngine.new(deps)
	local self = setmetatable({
		Logger = deps.LoggerService,
		Perm = deps.PermissionService,
		Throttle = deps.ThrottleService,
		GL = deps.GLightsAdapter,
		Pyro = deps.PyroService,      -- PyroService (armed inside)
		Beat = deps.BeatSyncEngine,   -- BeatSyncEngine
		StateUpdate = deps.StateUpdate,

		_stopCinematic = false,
		_stopRhythm = false,

		-- manual target inference for color
		_lastTargetByUserId = {},

		-- pyro runner
		_pyroRunToken = 0,
		_activePyroBeatId = nil,
	}, ShowEngine)

	self.state = {
		status = "Idle",    -- Idle/Running/Blackout/Emergency
		mode = "IDLE",      -- IDLE/CINEMATIC/RHYTHM/MANUAL
		activePresetId = nil,
		activeRhythmId = nil,

		-- baseline 24/7 global
		baseline = {
			enabled = true,
			colorName = "WARM_WHITE",
		},

		-- force night
		forceNight = true,

		-- pyro
		pyroArmed = false,
		activePyroId = nil,

		-- run cancellation
		lockUntil = 0,
		runToken = 0,

		-- rhythm state
		rhythm = {
			enabled = false,
			bpm = 120,
			beatIndex = 0,
			barIndex = 0,
			level = "Low",
			audioPath = "SoundService.ServerMusic",
			thresholds = {100, 250, 450, 650, 850},
			minBeatGap = 0.12,
		},

		lastError = nil,
	}

	return self
end

function ShowEngine:Boot()
	self:_applyNightIfNeeded(true)
	self:_applyBaselineIfNeeded(true)
	self:_broadcast()
end

function ShowEngine:GetState()
	return self.state
end

function ShowEngine:GetSnapshot(player)
	local isOp = self.Perm:IsOperator(player)
	return {
		state = deepCopy(self.state),
		isOperator = isOp,
		logs = self.Logger:GetLast(60),
		cinematicPresets = PresetLibrary.list,
		rhythmPresets = RhythmLibrary.list,
		pyroPresets = PYRO_PRESETS,
		palette = exportPalette(),
	}
end

function ShowEngine:_broadcast()
	self.StateUpdate:FireAllClients({
		state = deepCopy(self.state),
		logs = self.Logger:GetLast(60)
	})
end

function ShowEngine:_locked()
	return now() < (self.state.lockUntil or 0)
end

function ShowEngine:_reject(player, reason)
	self.Logger:Log("REJECT", reason, {userId=player.UserId})
end

function ShowEngine:_applyNightIfNeeded(force)
	if not (self.state.forceNight == true) and not force then return end
	pcall(function()
		Lighting.ClockTime = 0
		Lighting.TimeOfDay = "00:00:00"
	end)
end

function ShowEngine:_applyBaselineIfNeeded(force)
	if not (self.state.baseline and self.state.baseline.enabled) and not force then return end
	local col = Palette[self.state.baseline.colorName] or Palette.WARM_WHITE
	self.GL:EnsureAllOnBaseline(col)
end

function ShowEngine:_bumpTokenAndStopAll()
	self.state.runToken += 1
	self._stopCinematic = true
	self._stopRhythm = true
	self.state.rhythm.enabled = false
end

-- serialize config for DataStore
function ShowEngine:ExportGlobalConfig()
	return {
		baselineEnabled = self.state.baseline.enabled == true,
		baselineColorName = tostring(self.state.baseline.colorName or "WARM_WHITE"),
		forceNight = self.state.forceNight == true,

		lastMode = self.state.mode,
		lastPresetId = self.state.activePresetId,
		lastRhythmId = self.state.activeRhythmId,

		rhythm = {
			audioPath = tostring(self.state.rhythm.audioPath or "SoundService.ServerMusic"),
			thresholds = deepCopy(self.state.rhythm.thresholds),
			minBeatGap = tonumber(self.state.rhythm.minBeatGap) or 0.12,
		},

		pyroArmed = self.state.pyroArmed == true,
	}
end

function ShowEngine:ApplyGlobalConfig(cfg, sourceTag)
	if type(cfg) ~= "table" then return end

	if cfg.baselineEnabled ~= nil then
		self.state.baseline.enabled = cfg.baselineEnabled == true
	end
	if cfg.baselineColorName ~= nil then
		self.state.baseline.colorName = tostring(cfg.baselineColorName)
	end
	if cfg.forceNight ~= nil then
		self.state.forceNight = cfg.forceNight == true
	end

	if cfg.rhythm and type(cfg.rhythm) == "table" then
		if cfg.rhythm.audioPath then self.state.rhythm.audioPath = tostring(cfg.rhythm.audioPath) end
		if type(cfg.rhythm.thresholds) == "table" and #cfg.rhythm.thresholds == 5 then
			self.state.rhythm.thresholds = {
				tonumber(cfg.rhythm.thresholds[1]) or 100,
				tonumber(cfg.rhythm.thresholds[2]) or 250,
				tonumber(cfg.rhythm.thresholds[3]) or 450,
				tonumber(cfg.rhythm.thresholds[4]) or 650,
				tonumber(cfg.rhythm.thresholds[5]) or 850,
			}
		end
		if cfg.rhythm.minBeatGap then
			self.state.rhythm.minBeatGap = math.clamp(tonumber(cfg.rhythm.minBeatGap) or 0.12, 0.06, 0.35)
		end
	end

	-- SAFETY: pyroArmed selalu false saat apply dari global
	self.state.pyroArmed = false
	self.Pyro:SetArmed(false)

	self:_applyNightIfNeeded(true)
	self:_applyBaselineIfNeeded(true)

	self.Logger:Log("GLOBAL","Applied config", {src=sourceTag or "unknown"})
	self:_broadcast()
end

-- ===== Commands =====
function ShowEngine:OnShowCommand(player, payload)
	if type(payload) ~= "table" then return end
	if self:_locked() then self:_reject(player, "LockedDuringEmergency"); return end

	local cmd = payload.cmd
	if type(cmd) ~= "string" then return end

	if not self.Perm:IsOperator(player) then
		self:_reject(player, "NotOperator:"..cmd)
		return
	end

	if not self.Throttle:Allow(player, "ShowCommand", 18) then
		return
	end

	-- Global / Safety
	if cmd == "EMERGENCY" then self:Emergency(player); return end
	if cmd == "BLACKOUT" then self:Blackout(player); return end
	if cmd == "STOP_ALL" then self:StopAll(player); return end

	-- Baseline 24/7
	if cmd == "BASELINE_SET" then
		local enabled = payload.enabled == true
		local colorName = payload.colorName
		self.state.baseline.enabled = enabled
		if type(colorName) == "string" and Palette[colorName] then
			self.state.baseline.colorName = colorName
		end
		self.state.mode = "IDLE"
		self.state.status = "Idle"
		self:_bumpTokenAndStopAll()

		self.GL:CleanupPreset()
		self:_applyNightIfNeeded(true)
		if enabled then self:_applyBaselineIfNeeded(true) end

		self.Logger:Log("BASELINE","Set",{enabled=enabled, color=self.state.baseline.colorName})
		self:_broadcast()
		return
	end

	if cmd == "FORCE_NIGHT" then
		self.state.forceNight = payload.value == true
		self:_applyNightIfNeeded(true)
		self.Logger:Log("LIGHTING","forceNight",{value=self.state.forceNight})
		self:_broadcast()
		return
	end

	-- Pyro arm
	if cmd == "ARM_PYRO" then
		local v = payload.value == true
		self.state.pyroArmed = v
		self.Pyro:SetArmed(v)
		self.Logger:Log("PYRO","ArmedSet",{value=v, by=player.UserId})
		self:_broadcast()
		return
	end

	-- Beat / Rhythm settings
	if cmd == "SET_AUDIO_PATH" then
		local s = tostring(payload.path or "")
		if #s > 0 then
			self.state.rhythm.audioPath = s
			self.Logger:Log("BEAT","AudioPath", {path=s})
			self:_broadcast()
		end
		return
	end

	if cmd == "SET_THRESHOLDS" then
		local th = payload.thresholds
		if type(th) == "table" and #th == 5 then
			self.state.rhythm.thresholds = {
				tonumber(th[1]) or 100,
				tonumber(th[2]) or 250,
				tonumber(th[3]) or 450,
				tonumber(th[4]) or 650,
				tonumber(th[5]) or 850,
			}
			self.Logger:Log("BEAT","Thresholds",{})
			self:_broadcast()
		end
		return
	end

	if cmd == "SET_MIN_BEAT_GAP" then
		local g = tonumber(payload.value)
		if g then
			self.state.rhythm.minBeatGap = math.clamp(g, 0.06, 0.35)
			self.Beat:SetMinBeatGap(player, self.state.rhythm.minBeatGap)
			self:_broadcast()
		end
		return
	end

	if cmd == "TAP_TEMPO" then
		self.Beat:TapTempo(player)
		self.state.rhythm.bpm = self.Beat:GetState().bpm
		self:_broadcast()
		return
	end

	-- Play cinematic / rhythm
	if cmd == "PLAY_CINEMATIC" then self:PlayCinematic(payload.presetId); return end
	if cmd == "PLAY_RHYTHM" then self:PlayRhythm(payload.rhythmId); return end

	-- Manual (fix: stop preset/rhythm, manual stays)
	if cmd == "MANUAL" then
		self:EnterManual(player, payload)
		return
	end

	-- Pyro presets
	if cmd == "PYRO_RUN" then
		self:RunPyroPreset(player, payload.id)
		return
	end

	if cmd == "PYRO_STOP" then
		self:StopPyro(player)
		return
	end
end

function ShowEngine:StopAll(player)
	self.Logger:Log("SHOW","StopAll",{by=player and player.UserId})

	self:_bumpTokenAndStopAll()
	self.state.mode = "IDLE"
	self.state.status = "Idle"
	self.state.activePresetId = nil
	self.state.activeRhythmId = nil
	self.state.activePyroId = nil
	self._activePyroBeatId = nil

	self.Pyro:AllOff()
	self.GL:CleanupPreset()
	-- manual cues boleh tetap? STOP_ALL biasanya harus bersih total
	self.GL:CleanupManual()
	self:_applyBaselineIfNeeded(true)

	self:_broadcast()
end

function ShowEngine:Emergency(player)
	self.state.runToken += 1
	self.state.status = "Emergency"
	self.state.lockUntil = now() + 2.0
	self.state.lastError = nil

	self.Logger:Log("EMERGENCY","Triggered",{by=player and player.UserId})
	self.Pyro:AllOff()
	self.GL:HardResetAll()

	self._stopCinematic = true
	self._stopRhythm = true

	self.state.mode = "IDLE"
	self.state.activePresetId = nil
	self.state.activeRhythmId = nil
	self.state.rhythm.enabled = false
	self.state.activePyroId = nil
	self._activePyroBeatId = nil

	self:_broadcast()

	task.delay(2.0, function()
		if self.state.status == "Emergency" then
			self.state.status = "Idle"
			self:_applyBaselineIfNeeded(true)
			self:_broadcast()
		end
	end)
end

function ShowEngine:Blackout(player)
	self.Logger:Log("SHOW","Blackout",{by=player and player.UserId})

	self:_bumpTokenAndStopAll()
	self.state.status = "Blackout"
	self.state.mode = "IDLE"
	self.state.activePresetId = nil
	self.state.activeRhythmId = nil
	self.state.activePyroId = nil
	self._activePyroBeatId = nil

	self.Pyro:AllOff()
	self.GL:CleanupAll()
	self.GL:Run("ALL","FadeOff",{},nil,nil,"preset")

	self:_broadcast()
end

-- ===== MANUAL MODE =====
function ShowEngine:EnterManual(player, payload)
	-- cancel running show
	self:_bumpTokenAndStopAll()
	self.state.status = "Running"
	self.state.mode = "MANUAL"
	self.state.activePresetId = nil
	self.state.activeRhythmId = nil
	self.state.rhythm.enabled = false

	-- stop preset cues only, keep manual
	self.GL:CleanupPreset()

	local folder = tostring(payload.folder or "ALL")
	local fn = tostring(payload.fn or "")
	local args = payload.args

	-- remember last target (for color inference)
	if folder ~= "ALL" then
		self._lastTargetByUserId[player.UserId] = folder
	end

	-- server-side inference: jika UI kirim Color ke ALL, map ke last target
	if fn == "Color" and folder == "ALL" then
		local last = self._lastTargetByUserId[player.UserId]
		if last and last ~= "ALL" then
			folder = last
		end
	end

	self.Logger:Log("MANUAL","Run",{folder=folder, fn=fn})

	-- execute as manual owner
	self.GL:Run(folder, fn, args or {}, payload.selector, nil, "manual")

	-- baseline tetap ON kalau enabled (tapi manual boleh menimpa sementara)
	self:_applyNightIfNeeded(false)

	self:_broadcast()
end

-- ===== Cinematic execution (runToken cancel) =====
function ShowEngine:_waitSeconds(seconds, token)
	local start = now()
	while (now() - start) < seconds do
		if self.state.runToken ~= token then return false end
		task.wait(0.02)
		if self._stopCinematic and self.state.mode=="CINEMATIC" then
			return false
		end
	end
	return true
end

function ShowEngine:_execStep(step, token)
	if self.state.runToken ~= token then return false end
	if self.state.status == "Emergency" then return false end
	if type(step) ~= "table" then return true end

	if step.type == "wait" then
		return self:_waitSeconds(step.seconds or 0, token)
	end

	if step.type == "sys" then
		if step.fn == "CleanupPreset" then
			self.GL:CleanupPreset()
		elseif step.fn == "EnsureAllOnBaseline" then
			self.GL:EnsureAllOnBaseline(step.args and step.args[1])
		end
		return true
	end

	if step.type == "gl" then
		self.GL:Run(step.folder, step.fn, step.args, step.selector, nil, "preset")
		return true
	end

	if step.type == "pyro" then
		local requireArmed = step.requireArmed == true
		self.Pyro:Fire(step.device, step.pattern, step.args, requireArmed, function()
			return (self.state.runToken == token) and (self.state.status ~= "Emergency")
		end)
		return true
	end

	return true
end

function ShowEngine:PlayCinematic(presetId)
	local preset = PresetLibrary.byId[presetId]
	if not preset then return end

	self._stopCinematic = false
	self._stopRhythm = true
	self.state.runToken += 1
	local token = self.state.runToken

	self.state.status = "Running"
	self.state.mode = "CINEMATIC"
	self.state.activePresetId = presetId
	self.state.activeRhythmId = nil
	self.state.rhythm.enabled = false
	self.state.lastError = nil

	-- ensure baseline on start (but presets can override)
	self:_applyNightIfNeeded(false)
	self:_applyBaselineIfNeeded(false)

	self:_broadcast()

	task.spawn(function()
		local ok, err = pcall(function()
			for _,step in ipairs((preset.phases and preset.phases.setup) or {}) do
				if self.state.runToken ~= token then return end
				self:_execStep(step, token)
			end

			for _,step in ipairs((preset.phases and preset.phases.intro) or {}) do
				if self.state.runToken ~= token then return end
				self:_execStep(step, token)
			end

			local segOrder = {"A","B","C"}
			local idx = 1

			while self.state.runToken == token and (not self._stopCinematic) do
				local seg = segOrder[idx]
				local loop = preset.phases and preset.phases.loop and preset.phases.loop[seg]
				for _,step in ipairs(loop or {}) do
					if self.state.runToken ~= token then return end
					local cont = self:_execStep(step, token)
					if cont == false then break end
				end

				idx += 1
				if idx > #segOrder then idx = 1 end
			end

			for _,step in ipairs((preset.phases and preset.phases.outro) or {}) do
				if self.state.runToken ~= token then return end
				self:_execStep(step, token)
			end

			if self.state.runToken == token then
				self.state.status = "Idle"
				self.state.activePresetId = nil
				self.state.mode = "IDLE"
				self.GL:CleanupPreset()
				self:_applyBaselineIfNeeded(true)
				self:_broadcast()
			end
		end)

		if not ok then
			self.state.lastError = tostring(err)
			self.Logger:Log("ERROR","Cinematic error",{err=tostring(err)})
			self.state.status = "Blackout"
			self.GL:CleanupPreset()
			self.GL:Run("ALL","FadeOff",{},nil,nil,"preset")
			self:_broadcast()
		end
	end)
end

-- ===== Rhythm execution (beat-driven) =====
function ShowEngine:PlayRhythm(rhythmId)
	local rp = RhythmLibrary.byId[rhythmId]
	if not rp then return end

	self._stopCinematic = true
	self.state.runToken += 1
	local token = self.state.runToken

	self.state.status = "Running"
	self.state.mode = "RHYTHM"
	self.state.activeRhythmId = rhythmId
	self.state.activePresetId = nil
	self.state.rhythm.enabled = true
	self._stopRhythm = false
	self.state.lastError = nil

	self.state.rhythm.beatIndex = 0
	self.state.rhythm.barIndex = 0
	self.state.rhythm.level = "Low"

	self:_applyNightIfNeeded(false)
	self:_applyBaselineIfNeeded(false)

	self:_broadcast()

	task.spawn(function()
		local ok, err = pcall(function()
			for _,cmd in ipairs(rp.onEnter or {}) do
				if self.state.runToken ~= token then return end
				self:_execRhythmCmd(cmd, token, rp)
			end

			-- idle loop just to keep override/night/baseline
			while self.state.runToken == token and (not self._stopRhythm) and self.state.mode=="RHYTHM" do
				task.wait(0.25)
				self:_applyNightIfNeeded(false)
			end

			for _,cmd in ipairs(rp.onExit or {}) do
				if self.state.runToken ~= token then return end
				self:_execRhythmCmd(cmd, token, rp)
			end

			if self.state.runToken == token then
				self.state.status = "Idle"
				self.state.activeRhythmId = nil
				self.state.rhythm.enabled = false
				self.state.mode = "IDLE"
				self.GL:CleanupPreset()
				self:_applyBaselineIfNeeded(true)
				self:_broadcast()
			end
		end)

		if not ok then
			self.state.lastError = tostring(err)
			self.Logger:Log("ERROR","Rhythm error",{err=tostring(err)})
			self.state.status = "Blackout"
			self.GL:CleanupPreset()
			self.GL:Run("ALL","FadeOff",{},nil,nil,"preset")
			self:_broadcast()
		end
	end)
end

local function levelRank(name)
	local map = {Low=1, Med=2, Medium=2, High=3, Insane=4, Nuclear=5}
	return map[tostring(name)] or 1
end

function ShowEngine:_execRhythmCmd(cmd, token, rp)
	if self.state.runToken ~= token then return end
	if type(cmd) ~= "table" then return end

	if cmd.type == "sys" then
		if cmd.fn=="CleanupPreset" then self.GL:CleanupPreset() end
		if cmd.fn=="EnsureAllOnBaseline" then
			local c = cmd.args and cmd.args[1]
			self.GL:EnsureAllOnBaseline(c)
		end
		return
	end

	if cmd.type == "gl" then
		self.GL:Run(cmd.folder, cmd.fn, cmd.args, cmd.selector, nil, "preset")
		return
	end

	if cmd.type == "set" then
		self.state.rhythmState = self.state.rhythmState or {}
		self.state.rhythmState[cmd.key] = cmd.value
		return
	end

	if cmd.type == "toggle" then
		self.state.rhythmState = self.state.rhythmState or {}
		local v = self.state.rhythmState[cmd.key] == true
		self.state.rhythmState[cmd.key] = (not v)
		return
	end

	if cmd.type == "inc" then
		self.state.rhythmState = self.state.rhythmState or {}
		local v = tonumber(self.state.rhythmState[cmd.key] or 0) or 0
		self.state.rhythmState[cmd.key] = v + (cmd.delta or 1)
		return
	end

	if cmd.type == "branch" then
		self.state.rhythmState = self.state.rhythmState or {}
		local v = self.state.rhythmState[cmd.key] == true
		local list = v and cmd.ifTrue or cmd.ifFalse
		for _,c in ipairs(list or {}) do self:_execRhythmCmd(c, token, rp) end
		return
	end

	if cmd.type == "altByParity" then
		self.state.rhythmState = self.state.rhythmState or {}
		local v = tonumber(self.state.rhythmState[cmd.key] or 0) or 0
		local list = ((v % 2)==0) and cmd.even or cmd.odd
		for _,c in ipairs(list or {}) do self:_execRhythmCmd(c, token, rp) end
		return
	end

	if cmd.type == "levelColor" then
		local map = cmd.map or {}
		local lvl = tostring(self.state.rhythm.level or "Low")
		local col = map[lvl] or map.Med or Palette.WARM_WHITE
		self.GL:Run(cmd.folder or "ALL", "Color", {col}, cmd.selector, nil, "preset")
		return
	end

	if cmd.type == "pyro" then
		local pol = rp.pyroPolicy or {}
		if cmd.device=="FPA" and pol.allowFPA==false then return end
		if cmd.device=="CONFETTI" and pol.allowConfetti==false then return end
		if cmd.device=="SMOKE" and pol.allowSmoke==false then return end

		local g = cmd.gate or {}
		if g.levelAtLeast and levelRank(self.state.rhythm.level) < levelRank(g.levelAtLeast) then return end
		if g.everyNBeats and ((self.state.rhythm.beatIndex % g.everyNBeats) ~= 0) then return end
		if g.everyNBars and ((self.state.rhythm.barIndex % g.everyNBars) ~= 0) then return end

		self.Pyro:Fire(cmd.device, cmd.pattern, cmd.args, true, function()
			return (self.state.runToken == token) and (self.state.status ~= "Emergency")
		end)
		return
	end
end

-- Called by BeatSyncEngine
function ShowEngine:OnBeat(beatPayload)
	-- always update night if forced
	self:_applyNightIfNeeded(false)

	-- run beat-synced pyro preset even outside RHYTHM
	self:_pyroBeatDispatch(beatPayload)

	if self.state.mode ~= "RHYTHM" then return end
	if not self.state.rhythm.enabled then return end
	if self.state.status == "Emergency" then return end
	if self._stopRhythm then return end

	local rp = RhythmLibrary.byId[self.state.activeRhythmId]
	if not rp then return end

	self.state.rhythm.beatIndex = beatPayload.beatIndex or (self.state.rhythm.beatIndex + 1)
	self.state.rhythm.barIndex = beatPayload.barIndex or self.state.rhythm.barIndex
	self.state.rhythm.level = beatPayload.level or self.state.rhythm.level
	self.state.rhythm.bpm = beatPayload.bpm or self.state.rhythm.bpm

	local token = self.state.runToken

	for _,cmd in ipairs(rp.onBeat or {}) do
		self:_execRhythmCmd(cmd, token, rp)
	end

	-- onBar tiap beatsInBar
	local bib = tonumber(self.Beat:GetState().beatsInBar) or 4
	if (self.state.rhythm.beatIndex % bib) == 0 then
		for _,cmd in ipairs(rp.onBar or {}) do
			self:_execRhythmCmd(cmd, token, rp)
		end
	end

	self:_broadcast()
end

-- ===== Pyro presets runner =====
function ShowEngine:StopPyro(player)
	self._pyroRunToken += 1
	self.state.activePyroId = nil
	self._activePyroBeatId = nil
	self.Pyro:AllOff()
	self.Logger:Log("PYRO","StopPreset",{by=player and player.UserId})
	self:_broadcast()
end

function ShowEngine:RunPyroPreset(player, presetId)
	local p = PYRO_BY_ID[presetId]
	if not p then return end

	-- must be armed
	if not self.state.pyroArmed then
		self.Logger:Log("PYRO_FAIL","Run blocked (not armed)",{id=presetId})
		self:_broadcast()
		return
	end

	self.state.activePyroId = presetId
	self.Logger:Log("PYRO","RunPreset",{id=presetId, mode=p.mode})

	if p.mode == "sequence" then
		self._pyroRunToken += 1
		local myTok = self._pyroRunToken

		task.spawn(function()
			for _,s in ipairs(p.steps or {}) do
				if myTok ~= self._pyroRunToken then return end
				if s.wait then
					task.wait(tonumber(s.wait) or 0.1)
				else
					self.Pyro:Fire(s.device, s.pattern, s.args, true, function()
						return (myTok == self._pyroRunToken) and (self.state.status ~= "Emergency")
					end)
				end
			end
			if myTok == self._pyroRunToken then
				-- sequence selesai tapi status preset tetap ditandai (biar UI tahu terakhir)
				self:_broadcast()
			end
		end)
	else
		-- beat synced
		self._activePyroBeatId = presetId
		self:_broadcast()
	end
end

function ShowEngine:_pyroBeatDispatch(beatPayload)
	local id = self._activePyroBeatId
	if not id then return end

	local p = PYRO_BY_ID[id]
	if not p then return end
	if not self.state.pyroArmed then return end

	-- everyNBeats
	if p.onBeat and p.onBeat.everyNBeats then
		local n = tonumber(p.onBeat.everyNBeats) or 1
		if (beatPayload.beatIndex % n) == 0 then
			self.Pyro:Fire(p.onBeat.device, p.onBeat.pattern, p.onBeat.args, true, function()
				return (self.state.status ~= "Emergency") and (self._activePyroBeatId == id)
			end)
		end
	end

	-- everyNBars
	local bib = tonumber(self.Beat:GetState().beatsInBar) or 4
	if p.onBar and (beatPayload.beatIndex % bib) == 0 then
		local barIdx = beatPayload.barIndex or 0
		local n = tonumber(p.onBar.everyNBars) or 1
		if (barIdx % n) == 0 then
			self.Pyro:Fire(p.onBar.device, p.onBar.pattern, p.onBar.args, true, function()
				return (self.state.status ~= "Emergency") and (self._activePyroBeatId == id)
			end)
		end
	end
end

return ShowEngine
