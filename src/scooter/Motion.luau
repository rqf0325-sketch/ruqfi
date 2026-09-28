--[[
	Scooter — ride motion (ScooterAnimator > Motion)

	Turns how a rider moves (velocity, turning, jumping) into the scooter's
	joint transforms and the targets for Pose: kicking while speeding up,
	cruising with both feet on the deck, one foot down when stopped, leaning
	into turns, and a tailwhip / 360 spin when jumping at speed. Pure maths,
	so every client computes the same thing from replicated movement, and it
	can be tested outside Roblox (tools/test-scooter-pose.luau).

	  local motion = Motion.new(scooter, settings, "R6")
	  local result = motion:update(dt, {
	      rootCFrame = HumanoidRootPart.CFrame,
	      velocity = HumanoidRootPart.AssemblyLinearVelocity,
	      airborne = true/false,
	      gravity = workspace.Gravity,
	      mountC0 = Mount.C0,
	  })
	  result.mount / .steer / .wheel   Transforms for Mount, Steer, FrontSpin + RearSpin
	  result.targets                   for Pose.solve
	  result.kicked / .landed          for sounds
]]

local Motion = {}
Motion.__index = Motion

local KICK_RATE = 1.5 -- kicks per second
local PUSH_SHARE = 0.5 -- part of each kick the foot spends pushing along the ground
local TRICK_TIME = 0.5 -- seconds for a full tailwhip / spin
local STOP_FOOT_Z = 0.1 -- where the free foot rests on the ground when stopped
-- R15 feet, relative to the ground under the rider's root part (R6 keeps its feet under its hips).
local R15_FRONT_FOOT = Vector3.new(-0.3, 0, -0.7)
local R15_BACK_FOOT = Vector3.new(0.3, 0, -0.05)

local function smooth(current, target, rate, dt)
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

-- scooter: deckHeight, wheelRadius, wheelbase, steerC0, steerC1, scale
-- (Model:GetScale() of the scooter; body-size distances are scaled with it),
-- anchors (Kick, KickEnd in Root space),
-- grips (Left, Right in SteerHub space). Can be swapped for a new table
-- (motion.scooter = ...) when the scooter is rescaled.
function Motion.new(scooter, settings, rigKind)
	return setmetatable({
		scooter = scooter,
		settings = settings,
		r6 = rigKind == "R6",
		speed = 0,
		accel = 0,
		yaw = nil,
		yawRate = 0,
		steer = 0,
		roll = 0,
		wheel = 0,
		push = 0,
		idle = 1,
		kickHold = 0,
		phase = 0,
		grounded = true,
		airTime = 0,
		land = 0,
		trick = nil,
		tricks = 0,
	}, Motion)
end

function Motion:update(dt, frame)
	local scooter, settings = self.scooter, self.settings
	dt = math.max(dt, 1e-3)

	-- How the rider moves
	local rootCFrame, velocity = frame.rootCFrame, frame.velocity
	local look = Vector3.new(rootCFrame.LookVector.X, 0, rootCFrame.LookVector.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	self.accel = smooth(self.accel, (speed - self.speed) / dt, 5, dt)
	self.speed = speed
	local yaw = math.atan2(-look.X, -look.Z)
	if self.yaw then
		local turned = (yaw - self.yaw + math.pi) % (2 * math.pi) - math.pi
		self.yawRate = smooth(self.yawRate, turned / dt, 10, dt) -- > 0 = turning left
	end
	self.yaw = yaw

	-- Jumps and tricks
	local airborne = frame.airborne
	local landed = false
	if airborne then
		if self.grounded then
			self.airTime = 0
		end
		self.airTime += dt
		-- Decide within the first moments of the jump: for other players the
		-- jump's velocity can arrive a frame after the jumping state.
		local airtime = 2 * math.max(velocity.Y, 0) / frame.gravity
		if not self.trick and self.airTime < 0.15 and settings.Tricks ~= false
			and speed >= (settings.TrickMinSpeed or 16) and airtime > 0.45 then
			self.tricks += 1
			self.trick = {
				kind = if self.tricks % 2 == 1 then "tailwhip" else "spin",
				direction = if self.yawRate < 0 then -1 else 1,
				t = 0,
				duration = math.min(TRICK_TIME, airtime * 0.8),
			}
		end
	elseif not self.grounded then
		self.land = 1
		landed = true
		if self.trick then
			-- Landed early: finish the trick quickly instead of snapping.
			self.trick.duration = math.min(self.trick.duration, self.trick.t + 0.08)
		end
	end
	self.grounded = not airborne
	self.land = math.max(0, self.land - dt / 0.25)

	local whip, spin, tuck = 0, 0, 0
	local trick = self.trick
	if trick then
		trick.t += dt
		local u = math.clamp(trick.t / trick.duration, 0, 1)
		local eased = u * u * (3 - 2 * u)
		if trick.kind == "tailwhip" then
			whip = eased * 2 * math.pi
			tuck = math.sin(math.pi * u)
		else
			spin = eased * 2 * math.pi * trick.direction
			tuck = 0.35 * math.sin(math.pi * u)
		end
		if u >= 1 then
			self.trick = nil
		end
	end

	-- Kicking: while speeding up on the ground
	local moving = speed > 1.5
	if self.grounded and moving and self.accel > 1.5 and not trick then
		self.kickHold = 0.3
	end
	self.kickHold -= dt
	self.push = smooth(self.push, if self.kickHold > 0 then 1 else 0, 8, dt)
	self.idle = smooth(self.idle, if moving or not self.grounded then 0 else 1, 5, dt)
	local before = self.phase
	self.phase = if self.push > 0.02 then (self.phase + dt * KICK_RATE) % 1 else 0
	local kicked = self.push > 0.3 and before < 0.02 and self.phase >= 0.02

	-- Handlebar and lean follow the turn
	local steerTarget = 0
	if speed > 1 then
		steerTarget = math.atan(scooter.wheelbase * self.yawRate / math.max(speed, 4))
	end
	self.steer = smooth(self.steer, math.clamp(steerTarget, -0.6, 0.6), 10, dt)
	local rollTarget = if self.grounded then math.clamp(self.yawRate * speed * 0.012, -0.3, 0.3) else 0
	self.roll = smooth(self.roll, rollTarget, 6, dt)
	self.wheel = (self.wheel + flat:Dot(look) / scooter.wheelRadius * dt) % (2 * math.pi)

	-- Scooter joints. Leaning pivots on the ground under the deck; the
	-- tailwhip turns the deck around the steering axis while the handlebar
	-- stays in the rider's hands.
	local ground = CFrame.new(0, -scooter.deckHeight, 0)
	local lean = ground * CFrame.Angles(0, 0, self.roll) * ground:Inverse()
	local facingTransform = CFrame.Angles(0, spin, 0) * lean
	local mount = facingTransform
	if whip ~= 0 then
		mount = mount * scooter.steerC0 * CFrame.Angles(0, whip, 0) * scooter.steerC0:Inverse()
	end
	local steer = CFrame.Angles(0, self.steer - whip, 0)

	-- Targets for Pose
	local deck = rootCFrame * frame.mountC0 * mount
	local facing = rootCFrame * frame.mountC0 * facingTransform
	local bar = deck * scooter.steerC0 * steer * scooter.steerC1:Inverse()

	-- R6 legs are rigid, so R6 feet stay under the hips (x = ±0.5) and Pose
	-- slides them forward/back to where the legs actually reach. An R6 foot
	-- can't reach the ground from the deck, so its kick swings wider and
	-- further out instead, to read as a push.
	local r6 = self.r6
	local size = scooter.scale or 1
	local anchors = scooter.anchors
	-- R15 stands with the front foot ahead, the back foot behind, around the
	-- point under its root part (which isn't under Root for R15, see Mount.C0).
	local under = Vector3.new(-frame.mountC0.X, 0, -frame.mountC0.Z)
	local left = if r6 then Vector3.new(-0.5, 0, 0) else under + R15_FRONT_FOOT * size
	local right = if r6 then Vector3.new(0.5, 0, 0) else under + R15_BACK_FOOT * size
	local kickStart, kickEnd, kickLift = anchors.Kick + under, anchors.KickEnd + under, 0.55 * size
	if r6 then
		kickStart = Vector3.new(1.15, anchors.Kick.Y, -0.45)
		kickEnd = Vector3.new(1.15, anchors.KickEnd.Y, 1.35)
		kickLift = 0.8
	end
	right = right:Lerp(Vector3.new(kickStart.X, kickStart.Y, STOP_FOOT_Z * size), self.idle)
	local strength = 0
	if self.push > 0.001 then
		local kick
		if self.phase < PUSH_SHARE then
			local u = self.phase / PUSH_SHARE
			kick = kickStart:Lerp(kickEnd, u)
			strength = math.sin(math.pi * u)
		else
			local u = (self.phase - PUSH_SHARE) / (1 - PUSH_SHARE)
			kick = kickEnd:Lerp(kickStart, u * u * (3 - 2 * u)) + Vector3.new(0, kickLift * math.sin(math.pi * u), 0)
		end
		right = right:Lerp(kick, self.push)
	end
	local lift = Vector3.new(0, 0.9 * size * tuck, 0)
	local pushing = self.push * strength

	return {
		mount = mount,
		steer = steer,
		wheel = CFrame.Angles(-self.wheel, 0, 0),
		kicked = kicked,
		landed = landed,
		speed = speed,
		targets = {
			-- R6 arms can't bend either, so R6 leans less to keep its hands on the grips.
			lean = if r6 then 0.1 + 0.08 * pushing + 0.05 * tuck else 0.1 + 0.12 * pushing - 0.08 * self.idle + 0.1 * tuck,
			roll = self.roll,
			twist = self.steer * 0.7,
			ground = (frame.mountC0 * ground).Position,
			-- R6 legs are rigid: a small dip lets them stand a little apart.
			-- R15 keeps its knees soft and bends the standing knee deep enough
			-- in each push for the other foot to reach the ground.
			dip = if r6 then 0.03 + 0.03 * self.land
				else (0.25 + 0.5 * pushing + 0.25 * self.land + 0.15 * tuck) * size,
			spin = spin,
			hands = { Left = bar * scooter.grips.Left, Right = bar * scooter.grips.Right },
			feet = { Left = facing * (left + lift), Right = facing * (right + lift) },
			slide = { Left = facing.LookVector, Right = -facing.LookVector },
			facing = facing,
			headPitch = 0.12,
		},
	}
end

return Motion
