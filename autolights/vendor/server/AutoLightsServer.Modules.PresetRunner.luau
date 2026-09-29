-- ServerScriptService/AutoLightsServer/Modules/PresetRunner.lua
local PresetRunner = {}
PresetRunner.__index = PresetRunner

function PresetRunner.new(Logger, GLAdapter)
	return setmetatable({
		Logger = Logger,
		GL = GLAdapter,
		_running = false,
		_currentId = nil,
		_stopFlag = false,
		_speedMul = 1.0, -- NEW
	}, PresetRunner)
end

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k,v in pairs(t) do
		o[k] = deepCopy(v)
	end
	return o
end

function PresetRunner:SetSpeedMultiplier(m)
	m = tonumber(m) or 1.0
	self._speedMul = math.clamp(m, 0.25, 3.0)
end

function PresetRunner:IsRunning()
	return self._running
end

function PresetRunner:Stop()
	self._stopFlag = true
	self._running = false
	self._currentId = nil
end

function PresetRunner:_runSteps(steps)
	for _,step in ipairs(steps or {}) do
		if self._stopFlag then return false end

		if step.type == "wait" then
			local t0 = os.clock()
			local dur = (step.seconds or 0) * (self._speedMul or 1.0)
			while (os.clock() - t0) < dur do
				if self._stopFlag then return false end
				task.wait(0.05)
			end

		elseif step.type == "gl" then
			self.GL:Run(step.folder, step.fn, deepCopy(step.args))

		elseif step.type == "sys" then
			if step.fn == "CleanupPreset" then
				self.GL:CleanupPreset()
			elseif step.fn == "EnsureAllOnBaseline" then
				local color = step.args and step.args[1]
				self.GL:EnsureAllOnBaseline(color)
			elseif step.fn == "HardResetAll" then
				self.GL:HardResetAll()
			end
		end
	end
	return true
end

function PresetRunner:Play(preset)
	self:Stop()
	self._stopFlag = false
	self._running = true
	self._currentId = preset.id

	task.spawn(function()
		local ok = pcall(function()
			local phases = preset.phases or {}
			self:_runSteps(phases.setup)
			self:_runSteps(phases.intro)

			while not self._stopFlag do
				local loop = phases.loop or {}
				for _,key in ipairs({"A","B","C"}) do
					if self._stopFlag then break end
					self:_runSteps(loop[key])
				end
			end

			self:_runSteps(phases.outro)
		end)

		if not ok then
			self.Logger:Log("PRESET_ERR","Preset crashed",{id=preset.id})
		end
		self._running = false
	end)
end

return PresetRunner
