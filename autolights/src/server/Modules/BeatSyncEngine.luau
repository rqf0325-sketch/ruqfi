-- ServerScriptService/AutoLightsServer/Modules/BeatSyncEngine.lua
local BeatService = require(script.Parent.BeatService)

local BeatSyncEngine = {}
BeatSyncEngine.__index = BeatSyncEngine

-- Patch notes (PAUL): removed the unused LEVELS list; the default threshold now
-- matches AutoLightsSyncConfig.BEAT_THRESHOLD (150) instead of 526.
local function now() return os.clock() end

local function clamp(x,a,b) return math.max(a, math.min(b, x)) end

local function levelFromEnvelope(env, thresholds)
	thresholds = thresholds or {100,250,450,650,850}
	env = tonumber(env) or 0

	if env >= (thresholds[5] or 850) then return "Nuclear" end
	if env >= (thresholds[4] or 650) then return "Insane" end
	if env >= (thresholds[3] or 450) then return "High" end
	if env >= (thresholds[2] or 250) then return "Med" end
	return "Low"
end

function BeatSyncEngine.new(Logger, PermissionService, BeatEventRemote)
	return setmetatable({
		Logger=Logger,
		Perm=PermissionService,
		BeatEvent=BeatEventRemote,

		beat = BeatService.new(Logger),

		lastTelemetryT=now(),
		lastRmsNonZeroT=now(),

		lastFallbackBeatT=-1e9,

		-- state mirror
		bpm=120,

		_onBeat=nil,
		_running=false,
	}, BeatSyncEngine)
end

function BeatSyncEngine:SetMinBeatGap(player, v)
	if player and not self.Perm:IsOperator(player) then return end
	local n = tonumber(v)
	if not n then return end
	self.beat:SetConfig({minBeatGap = clamp(n, 0.06, 0.35)})
end

function BeatSyncEngine:SetBpm(player, bpm)
	if player and not self.Perm:IsOperator(player) then return end
	local b = tonumber(bpm)
	if not b then return end
	self.bpm = clamp(b, 40, 240)
	self.Logger:Log("BEAT","BPM set", {bpm=self.bpm})
end

function BeatSyncEngine:TapTempo(player)
	if player and not self.Perm:IsOperator(player) then return end
	self.beat:TapTempo(now())
	self.bpm = self.beat:GetState().bpm
end

function BeatSyncEngine:SetAudioPath(player, path)
	if player and not self.Perm:IsOperator(player) then return end
	self.beat:SetConfig({soundPath = tostring(path or "")})
end

function BeatSyncEngine:SetBaseThreshold(player, thr)
	if player and not self.Perm:IsOperator(player) then return end
	self.beat:SetConfig({baseThreshold = tonumber(thr) or 150})
end

function BeatSyncEngine:SetSmoothing(player, s)
	if player and not self.Perm:IsOperator(player) then return end
	self.beat:SetConfig({smoothing = tonumber(s) or 0.35})
end

function BeatSyncEngine:GetState()
	local st = self.beat:GetState()
	self.bpm = st.bpm
	return st
end

function BeatSyncEngine:TelemetryAge(t)
	return self.beat:TelemetryAge(t)
end

function BeatSyncEngine:_emit(payload)
	-- publish to clients
	self.BeatEvent:FireAllClients(payload)

	-- callback to show engine
	if self._onBeat then
		self._onBeat(payload)
	end
end

-- payload from client: {rms=number}
function BeatSyncEngine:OnAudioTelemetry(player, payload, state)
	if not self.Perm:IsOperator(player) then return end
	if type(payload) ~= "table" then return end

	local t = now()
	self.lastTelemetryT = t

	local rms = tonumber(payload.rms) or 0
	if rms > 1 then self.lastRmsNonZeroT = t end

	-- update beat cfg from state
	if state and state.rhythm then
		local r = state.rhythm
		if r.minBeatGap then
			self.beat:SetConfig({minBeatGap = r.minBeatGap})
		end
		if r.audioPath then
			self.beat:SetConfig({soundPath = r.audioPath})
		end
	end

	-- dt estimate: kita pakai interval 20Hz -> 0.05
	local dt = tonumber(payload.dt) or 0.05
	dt = clamp(dt, 0.01, 0.2)

	local ev = self.beat:StepFromRms(dt, t, rms)
	if ev then
		local thresholds = (state and state.rhythm and state.rhythm.thresholds) or {100,250,450,650,850}
		ev.level = levelFromEnvelope(ev.envelope, thresholds)
		ev.source = ev.source or "telemetry"
		self.bpm = self.beat:GetState().bpm
		ev.bpm = self.bpm
		self:_emit(ev)
	end
end

function BeatSyncEngine:Start(getStateFn, onBeatFn)
	if self._running then return end
	self._running = true
	self._onBeat = onBeatFn

	task.spawn(function()
		while self._running do
			task.wait(0.05)

			local st = getStateFn and getStateFn() or nil
			local rhythmOn = st and st.rhythm and st.rhythm.enabled == true

			-- decay kalau telemetry ngilang
			local t = now()
			if self.beat:TelemetryAge(t) > 0.25 then
				self.beat:Decay(0.05)
			end

			if rhythmOn then
				local telemetryMissing = self.beat:TelemetryAge(t) > 2.0
				local rmsZeroTooLong = (t - self.lastRmsNonZeroT) > 2.0

				if telemetryMissing or rmsZeroTooLong then
					-- fallback gap dari bpm
					local bpm = tonumber(self.beat:GetState().bpm) or (st.rhythm.bpm or 120)
					local gap = 60 / math.max(1, bpm)

					if (t - self.lastFallbackBeatT) >= gap then
						self.lastFallbackBeatT = t
						local ev = self.beat:ForceBeat(t)
						if ev then
							local thresholds = st.rhythm.thresholds or {100,250,450,650,850}
							ev.level = levelFromEnvelope(ev.envelope, thresholds)
							ev.source = "fallback"
							ev.bpm = bpm
							self:_emit(ev)
						end
					end
				end
			end
		end
	end)
end

function BeatSyncEngine:Stop()
	self._running = false
end

return BeatSyncEngine
