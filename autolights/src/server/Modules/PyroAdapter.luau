-- ServerScriptService/AutoLightsServer/Modules/PyroAdapter.lua
local State = require(script.Parent:WaitForChild("AutoLightsState"))

local PyroAdapter = {}
PyroAdapter.__index = PyroAdapter

function PyroAdapter.new(Logger, PyroServiceInstance)
	return setmetatable({
		Logger = Logger,
		PyroService = PyroServiceInstance, -- NEW: wajib diinject dari Main.server
	}, PyroAdapter)
end

local function mapLegacy(device, pattern, args)
	args = args or {}

	if device == "FPA" then
		-- UI legacy
		if pattern == "Burst" then
			return "AllHold", { duration = args.duration or 0.25 }
		end
		if pattern == "Left" then
			return "WaveL2R", { interval = args.interval or 0.08 }
		end
		if pattern == "Right" then
			return "WaveR2L", { interval = args.interval or 0.08 }
		end
	end

	return pattern, args
end

function PyroAdapter:Fire(device, pattern, args)
	if not self.PyroService then
		self.Logger:Log("PYRO", "Pyro skipped (no PyroService)", {device=device, pattern=pattern})
		return
	end

	-- Patch notes (PAUL): the Control Panel's Pyro switch.
	if not State.PyroEnabled() then
		return
	end

	local pat, a = mapLegacy(device, pattern, args)

	local ok, why = self.PyroService:Fire(device, pat, a, true, nil)
	if not ok then
		self.Logger:Log("PYRO_FAIL", "Pyro blocked", {device=device, pattern=pat, why=why})
	end
end

return PyroAdapter
