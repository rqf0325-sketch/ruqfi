-- ServerScriptService/AutoLightsServer/Modules/RhythmRunner.lua
--
-- Patch notes (PAUL):
--   • sys "Delay" (used twice by RhythmLibrary) is now run; it used to be ignored
--   • the "circleAccelIdleSpeed" step (speed back to idle after a beat) now exists
--   • level names accept both "Med" and "Medium" (BeatSync sends "Med")
--   • "branch" no longer takes the wrong side when ifTrue is empty
--   • sys "HardResetAll" is handled
--   • OnBeat / OnBar stop while the Control Panel's Sync switch is OFF
local State = require(script.Parent:WaitForChild("AutoLightsState"))

local RhythmRunner = {}
RhythmRunner.__index = RhythmRunner

local LEVEL_RANK = { Low = 1, Med = 2, Medium = 2, High = 3, Insane = 4, Nuclear = 5 }
local function levelRank(name)
	return LEVEL_RANK[tostring(name)] or 1
end

function RhythmRunner.new(Logger, GLAdapter, PyroAdapter)
	return setmetatable({
		Logger = Logger,
		GL = GLAdapter,
		Pyro = PyroAdapter,

		_running = false,
		_current = nil,
		_vars = {},
		_level = "Medium",
		_armed = false,
		_token = 0, -- changes on every Play/Stop so delayed steps of an old preset are dropped

		beatIndex = 0,
		barIndex = 0,
	}, RhythmRunner)
end

function RhythmRunner:SetArmed(v)
	self._armed = v and true or false
end

function RhythmRunner:SetLevel(level)
	self._level = level or self._level
end

function RhythmRunner:IsRunning()
	return self._running
end

function RhythmRunner:Stop()
	self._running = false
	self._current = nil
	self._vars = {}
	self._token += 1
end

function RhythmRunner:_getVar(k)
	return self._vars[k]
end

function RhythmRunner:_setVar(k,v)
	self._vars[k] = v
end

function RhythmRunner:_incVar(k,delta)
	self._vars[k] = (self._vars[k] or 0) + (delta or 1)
end

function RhythmRunner:_toggle(k)
	self._vars[k] = not self._vars[k]
end

function RhythmRunner:_execStep(step)
	if type(step) ~= "table" then return end

	if step.type == "sys" then
		if step.fn == "CleanupPreset" then
			self.GL:CleanupPreset()
		elseif step.fn == "EnsureAllOnBaseline" then
			self.GL:EnsureAllOnBaseline(step.args and step.args[1])
		elseif step.fn == "HardResetAll" then
			self.GL:HardResetAll()
		elseif step.fn == "Delay" then
			-- args = { seconds, step }: run `step` after `seconds`, unless the preset changed
			local seconds = tonumber(step.args and step.args[1]) or 0
			local inner = step.args and step.args[2]
			local token = self._token
			task.delay(seconds, function()
				if self._running and self._token == token then
					self:_execStep(inner)
				end
			end)
		end

	elseif step.type == "gl" then
		self.GL:Run(step.folder, step.fn, step.args)

	elseif step.type == "set" then
		self:_setVar(step.key, step.value)

	elseif step.type == "inc" then
		self:_incVar(step.key, step.delta or 1)

	elseif step.type == "toggle" then
		self:_toggle(step.key)

	elseif step.type == "branch" then
		local list
		if self:_getVar(step.key) then
			list = step.ifTrue
		else
			list = step.ifFalse
		end
		for _,s in ipairs(list or {}) do
			self:_execStep(s)
		end

	elseif step.type == "neonRippleLEDs" then
		-- ripple simple: rotate color per beat
		local colors = step.colors or {}
		local idx = (self:_getVar("_ripple") or 0) + 1
		if #colors == 0 then return end
		if idx > #colors then idx = 1 end
		self:_setVar("_ripple", idx)
		self.GL:Run("LEDs","Color",{colors[idx]})

	elseif step.type == "circleAccelGoboHeads" then
		-- CUSTOM kamu
		local speedSeq = self:_getVar("speedSeq") or {0.006,0.010,0.016,0.024}
		local spreadSeq= self:_getVar("spreadSeq") or {0.12,0.25,0.45,0.65}
		local colorSeq = self:_getVar("colorSeq") or {Color3.new(1,1,1)}

		local si = self:_getVar("speedIndex") or 1
		local gi = self:_getVar("spreadIndex") or 1
		local ci = self:_getVar("colorIndex") or 1

		local spd = speedSeq[si] or speedSeq[#speedSeq]
		local spr = spreadSeq[gi] or spreadSeq[#spreadSeq]
		local col = colorSeq[ci] or colorSeq[#colorSeq]

		self.GL:Run("Heads","MotorSpeed",{spd})
		self.GL:Run("Heads","GoboSpread",{spr})
		self.GL:Run("ALL","Color",{col})

		si += 1; if si > #speedSeq then si = #speedSeq end
		gi += 1; if gi > #spreadSeq then gi = 1 end
		ci += 1; if ci > #colorSeq then ci = 1 end

		self:_setVar("speedIndex", si)
		self:_setVar("spreadIndex", gi)
		self:_setVar("colorIndex", ci)

	elseif step.type == "circleAccelIdleSpeed" then
		-- after a beat the heads slow back down to the idle speed (first entry of speedSeq)
		local speedSeq = self:_getVar("speedSeq") or {0.006}
		self.GL:Run("Heads","MotorSpeed",{speedSeq[1] or 0.006})

	elseif step.type == "pyro" then
		if not self.Pyro then return end
		if step.requireArmed and not self._armed then return end

		local gate = step.gate or {}
		local needLevel = gate.levelAtLeast
		if needLevel and levelRank(self._level) < levelRank(needLevel) then
			return
		end

		-- everyNBeats / everyNBars gate
		if gate.everyNBeats then
			if (self.beatIndex % gate.everyNBeats) ~= 0 then
				return
			end
		end
		if gate.everyNBars then
			if (self.barIndex % gate.everyNBars) ~= 0 then
				return
			end
		end

		-- Fire pyro (optional)
		self.Pyro:Fire(step.device, step.pattern, step.args)

	end
end

function RhythmRunner:Play(preset)
	self:Stop()
	self._running = true
	self._current = preset
	self._vars = {}
	self.beatIndex = 0
	self.barIndex = 0

	-- onEnter
	for _,s in ipairs(preset.onEnter or {}) do
		self:_execStep(s)
	end
end

function RhythmRunner:OnBeat(beatEvent)
	if not self._running or not self._current then return end
	if not State.SyncEnabled() then return end
	beatEvent = beatEvent or {}

	-- NEW: ikut level dari beat event (biar gate levelAtLeast kepake)
	if beatEvent.level then
		self._level = tostring(beatEvent.level)
	end

	self.beatIndex = beatEvent.beatIndex or (self.beatIndex + 1)
	self.barIndex = beatEvent.barIndex or self.barIndex

	for _,s in ipairs(self._current.onBeat or {}) do
		self:_execStep(s)
	end
end

function RhythmRunner:OnBar(barIndex)
	if not self._running or not self._current then return end
	if not State.SyncEnabled() then return end
	self.barIndex = barIndex or self.barIndex
	for _,s in ipairs(self._current.onBar or {}) do
		self:_execStep(s)
	end
end

function RhythmRunner:Exit()
	if not self._running or not self._current then return end
	for _,s in ipairs(self._current.onExit or {}) do
		self:_execStep(s)
	end
	self:Stop()
end

return RhythmRunner
