-- ServerScriptService/AutoLightsServer/Modules/LoggerService.lua
-- ★ SILENT EDITION — all logging suppressed
-- Replace the original LoggerService with this to clean up output.

local LoggerService = {}
LoggerService.__index = LoggerService

function LoggerService.new()
	return setmetatable({ _logs = {} }, LoggerService)
end

-- All log calls are silently discarded
function LoggerService:Log(_kind, _msg, _data) end

-- Returns empty log list (UI/boot data won't break)
function LoggerService:GetLast(_n)
	return {}
end

return LoggerService