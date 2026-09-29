local PermissionService = {}
PermissionService.__index = PermissionService

function PermissionService.new(Logger)
	return setmetatable({
		Logger = Logger,
	}, PermissionService)
end

-- FULL PUBLIC ACCESS: semua player dianggap operator
function PermissionService:IsOperator(player)
	return player ~= nil
end

return PermissionService
