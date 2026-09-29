local Access = require(script.Parent:WaitForChild("AutoLightsAccess"))

local PermissionService = {}
PermissionService.__index = PermissionService

function PermissionService.new(Logger)
	return setmetatable({
		Logger = Logger,
	}, PermissionService)
end

-- Patch notes (PAUL): this used to return true for every player ("full public
-- access"). It now follows AutoLightsAccess (owner, CONTROL.UserIds, group rank);
-- set CONTROL.PublicAccess = true in AutoLightsSyncConfig to open it up again.
function PermissionService:IsOperator(player)
	return Access.IsOperator(player)
end

return PermissionService
