local ThrottleService = {}
ThrottleService.__index = ThrottleService

function ThrottleService.new(Logger)
	local self = setmetatable({
		Logger = Logger,
		perPlayer = {},
	}, ThrottleService)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		self:Forget(player)
	end)
	return self
end

local function now()
	return os.clock()
end

function ThrottleService:_slot(userId, key)
	self.perPlayer[userId] = self.perPlayer[userId] or {}
	self.perPlayer[userId][key] = self.perPlayer[userId][key] or {
		windowStart = now(),
		count = 0
	}
	return self.perPlayer[userId][key]
end

function ThrottleService:Allow(player, key, limitPerSec)
	limitPerSec = limitPerSec or 8

	local s = self:_slot(player.UserId, key)
	local t = now()

	-- Reset window every second
	if (t - s.windowStart) >= 1.0 then
		s.windowStart = t
		s.count = 0
	end

	s.count = s.count + 1

	-- Check limit
	if s.count > limitPerSec then
		self.Logger:Log("THROTTLE", "Rejected spam", {
			userId = player.UserId,
			key = key,
			count = s.count
		})
		return false
	end

	return true
end

-- Patch notes (PAUL): drop a player's counters when they leave (they used to pile up).
function ThrottleService:Forget(player)
	self.perPlayer[player.UserId] = nil
end

return ThrottleService
