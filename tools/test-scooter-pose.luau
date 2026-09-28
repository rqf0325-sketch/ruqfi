--[[
	Rides the built scooter through a scripted run (standing, kicking up to
	speed, cruising, a left turn, a tailwhip, a 360 spin, coasting to a stop)
	with a standard R6 and an R15 rig, using the real Motion and Pose
	modules, and checks the body where it matters:

	  * hands on the grips (R15 exactly; R6 arms can't bend, so within a
	    small margin)
	  * the front foot on the deck (not floating, not sinking in)
	  * the resting foot on the deck while cruising

	  lune run tools/build-scooter.luau && lune run tools/test-scooter-pose.luau
	  lune run tools/test-scooter-pose.luau -- --dump   (writes build/scooter-poses.json for the preview)
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance, Enum = roblox.Instance, roblox.Enum
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local env = setmetatable({ Enum = Enum, CFrame = CFrame, Vector3 = Vector3, Color3 = roblox.Color3 }, { __index = getfenv(1) })
local function module(path)
	return luau.load(fs.readFile(path), { debugName = path, environment = env })()
end
local Pose = module("src/scooter/Pose.luau")
local Motion = module("src/scooter/Motion.luau")
local Shared = module("src/scooter/ScooterShared.luau")
local settings = module("src/scooter/Settings.luau")

---------------------------------------------------------------------------
-- The scooter, read the way ScooterAnimator reads it
---------------------------------------------------------------------------

local tool = roblox.deserializeModel(fs.readFile("StarterPack/Scooter.rbxm"))[1]
local body = tool:FindFirstChild("Body")
local root = body:FindFirstChild("Root")
local steerHub = body:FindFirstChild("SteerHub")
local steer, rearSpin = root:FindFirstChild("Steer"), root:FindFirstChild("RearSpin")
local frontSpin = steerHub:FindFirstChild("FrontSpin")
local function at(parent, name)
	return parent:FindFirstChild(name).CFrame.Position
end
local scooter = {
	deckHeight = body:GetAttribute("DeckHeight"),
	wheelRadius = body:GetAttribute("WheelRadius"),
	wheelbase = ((steer.C0 * steer.C1:Inverse() * frontSpin.C0).Position - rearSpin.C0.Position).Magnitude,
	steerC0 = steer.C0,
	steerC1 = steer.C1,
	anchors = {
		LeftFoot = at(root, "LeftFoot"),
		RightFoot = at(root, "RightFoot"),
		Kick = at(root, "Kick"),
		KickEnd = at(root, "KickEnd"),
	},
	grips = { Left = at(steerHub, "LeftGrip"), Right = at(steerHub, "RightGrip") },
}

---------------------------------------------------------------------------
-- Rigs
---------------------------------------------------------------------------

local function rigBuilder(kind, hipHeight)
	local character = Instance.new("Model")
	character.Name = kind
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType[kind]
	humanoid.HipHeight = hipHeight
	humanoid.Parent = character
	local parts, joints = {}, {}
	local function part(name, size)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Parent = character
		parts[name] = p
		return p
	end
	local function joint(name, part0, part1, c0, c1)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = parts[part0]
		m.Part1 = parts[part1]
		m.C0 = c0
		m.C1 = c1
		m.Parent = parts[part1 == "Torso" and part0 or part1]
		table.insert(joints, m)
		return m
	end
	return character, humanoid, parts, joints, part, joint
end

local function r6()
	local character, humanoid, parts, joints, part, joint = rigBuilder("R6", 0)
	local V = Vector3.new
	part("HumanoidRootPart", V(2, 2, 1))
	part("Torso", V(2, 2, 1))
	part("Head", V(2, 1, 1))
	for _, name in { "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		part(name, V(1, 2, 1))
	end
	local R = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	joint("RootJoint", "HumanoidRootPart", "Torso", R, R).Parent = parts.HumanoidRootPart
	joint("Neck", "Torso", "Head", CFrame.new(0, 1, 0) * R, CFrame.new(0, -0.5, 0) * R).Parent = parts.Torso
	local right = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	local left = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	joint("Right Shoulder", "Torso", "Right Arm", CFrame.new(1, 0.5, 0) * right, CFrame.new(-0.5, 0.5, 0) * right).Parent = parts.Torso
	joint("Left Shoulder", "Torso", "Left Arm", CFrame.new(-1, 0.5, 0) * left, CFrame.new(0.5, 0.5, 0) * left).Parent = parts.Torso
	joint("Right Hip", "Torso", "Right Leg", CFrame.new(1, -1, 0) * right, CFrame.new(0.5, 1, 0) * right).Parent = parts.Torso
	joint("Left Hip", "Torso", "Left Leg", CFrame.new(-1, -1, 0) * left, CFrame.new(-0.5, 1, 0) * left).Parent = parts.Torso
	return {
		character = character, humanoid = humanoid, parts = parts, joints = joints,
		hands = { Left = { "Left Arm", V(0, -0.6, 0) }, Right = { "Right Arm", V(0, -0.6, 0) } },
		soles = { Left = { "Left Leg", V(0, -1, 0) }, Right = { "Right Leg", V(0, -1, 0) } },
		rest = { ["Right Arm"] = V(1.5, 0, 0), ["Left Leg"] = V(-0.5, -2, 0), Head = V(0, 1.5, 0) },
	}
end

-- A blocky R15 (legs 2.15 studs, arms 2 studs from shoulder to grip).
local function r15()
	local character, humanoid, parts, joints, part, joint = rigBuilder("R15", 2.15)
	local V, C = Vector3.new, CFrame.new
	part("HumanoidRootPart", V(2, 2, 1))
	part("LowerTorso", V(2, 0.4, 1))
	part("UpperTorso", V(2, 1.6, 1))
	part("Head", V(2, 1, 1))
	joint("Root", "HumanoidRootPart", "LowerTorso", C(0, -1, 0), C(0, -0.2, 0))
	joint("Waist", "LowerTorso", "UpperTorso", C(0, 0.2, 0), C(0, -0.8, 0))
	joint("Neck", "UpperTorso", "Head", C(0, 0.8, 0), C(0, -0.5, 0))
	for side, x in { Left = -1, Right = 1 } do
		part(side .. "UpperArm", V(1, 1.2, 1))
		part(side .. "LowerArm", V(1, 1.1, 1))
		part(side .. "Hand", V(1, 0.3, 1))
		part(side .. "UpperLeg", V(1, 1.2, 1))
		part(side .. "LowerLeg", V(1, 1.2, 1))
		part(side .. "Foot", V(1, 0.3, 1))
		joint(side .. "Shoulder", "UpperTorso", side .. "UpperArm", C(x, 0.56, 0), C(-x * 0.5, 0.4, 0))
		joint(side .. "Elbow", side .. "UpperArm", side .. "LowerArm", C(0, -0.5, 0), C(0, 0.4, 0))
		joint(side .. "Wrist", side .. "LowerArm", side .. "Hand", C(0, -0.5, 0), C(0, 0.1, 0))
		joint(side .. "Hip", "LowerTorso", side .. "UpperLeg", C(x * 0.5, -0.2, 0), C(0, 0.5, 0))
		joint(side .. "Knee", side .. "UpperLeg", side .. "LowerLeg", C(0, -0.5, 0), C(0, 0.4, 0))
		joint(side .. "Ankle", side .. "LowerLeg", side .. "Foot", C(0, -0.5, 0), C(0, 0.1, 0))
		local grip = Instance.new("Attachment")
		grip.Name = side .. "GripAttachment"
		grip.CFrame = C(0, -0.1, 0)
		grip.Parent = parts[side .. "Hand"]
	end
	return {
		character = character, humanoid = humanoid, parts = parts, joints = joints,
		hands = { Left = { "LeftHand", V(0, -0.1, 0) }, Right = { "RightHand", V(0, -0.1, 0) } },
		soles = { Left = { "LeftFoot", V(0, -0.15, 0) }, Right = { "RightFoot", V(0, -0.15, 0) } },
		rest = { RightHand = V(1.5, -1.14, 0), LeftFoot = V(-0.5, -3, 0), Head = V(0, 1.5, 0) },
	}
end

-- Lune hands out a new userdata for every lookup of an Instance, so the
-- joint -> transform table from Pose is re-keyed by joint name here.
local function byName(transforms)
	local result = {}
	for joint, transform in transforms do
		result[joint.Parent.Name .. "." .. joint.Name] = transform
	end
	return result
end

-- Part CFrames from the root part's CFrame and the joint transforms.
local function forward(rig, rootCFrame, transforms)
	transforms = byName(transforms)
	local frames = { HumanoidRootPart = rootCFrame }
	local pending = table.clone(rig.joints)
	while #pending > 0 do
		local progress = false
		for i = #pending, 1, -1 do
			local m = pending[i]
			local base = frames[m.Part0.Name]
			if base then
				local transform = transforms[m.Parent.Name .. "." .. m.Name] or CFrame.new()
				frames[m.Part1.Name] = base * m.C0 * transform * m.C1:Inverse()
				table.remove(pending, i)
				progress = true
			end
		end
		assert(progress, "rig joints don't connect to the root part")
	end
	return frames
end

---------------------------------------------------------------------------
-- The run
---------------------------------------------------------------------------

local DT = 1 / 60
local GRAVITY = 196.2
local JUMP = 53 -- JumpHeight 7.2 * 1.1

-- {until time, label, speed at the end, yaw rate, jump at start}
local SCRIPT = {
	{ 1.0, "standing", 0, 0 },
	{ 3.0, "kicking", 30, 0 },
	{ 4.0, "cruising", 30, 0 },
	{ 5.5, "turning left", 26, 1.8 },
	{ 6.5, "tailwhip", 26, 0, true },
	{ 7.5, "spin", 26, 0, "late" }, -- the jump's velocity arrives a frame late, as for other players
	{ 11.0, "coasting to a stop", 0, 0 },
	{ 12.0, "stopped", 0, 0 },
}

local failures = 0
local function check(condition, message)
	print((if condition then "  ok   " else "  FAIL ") .. message)
	if not condition then
		failures += 1
	end
end

local dumpFrames = {}
local DUMP_AT = {
	{ 0.9, "standing" },
	{ 3.9, "cruising" },
	{ 5.4, "turning" },
	{ 5.72, "tailwhip" },
	{ 6.72, "spin" },
}
-- Kick poses: taken in the second kick, when the kick phase passes these points.
local DUMP_KICK = { { 0.25, "kick-push" }, { 0.75, "kick-return" } }

local function ride(rig)
	local kind = rig.humanoid.RigType.Name
	local rigData = Pose.rig(rig.character)
	assert(rigData, `{kind}: Pose.rig found no rig`)

	-- The mock must match the real rig at rest.
	local rest = forward(rig, CFrame.new(), {})
	for name, expected in rig.rest do
		assert((rest[name].Position - expected).Magnitude < 1e-3, `{kind} mock rig: {name} at {rest[name].Position}`)
	end

	local hrp = rig.parts.HumanoidRootPart
	local hipHeight = rig.humanoid.HipHeight
	local mountC0 = Shared.mountOffset(rig.humanoid, hrp, hipHeight)
	local motion = Motion.new(scooter, settings, kind)

	local position = Vector3.new(0, 0, 0) -- the ground is y = feet level of the raised rider
	local yaw, speed, vy, airborne = 0, 0, 0, false
	local stats = {}
	local t, segment = 0, 1
	local jumped = {}
	local kickCycle, lastPhase
	while segment <= #SCRIPT do
		local s = SCRIPT[segment]
		local from = if segment > 1 then SCRIPT[segment - 1] else { 0, "", 0, 0 }
		if t >= s[1] then
			segment += 1
			continue
		end
		-- speed: straight line to the segment's end speed (kicking starts at 12)
		local target = s[3]
		local u = (t - from[1]) / (s[1] - from[1])
		if s[2] == "kicking" then
			speed = math.min(30, 12 + 9 * (t - from[1]))
		elseif s[2] == "coasting to a stop" then
			speed = math.max(0, speed - 6 * DT)
			if speed < 3 then
				speed = 0
			end
		else
			speed = from[3] + (target - from[3]) * math.min(1, u * 4)
		end
		if s[5] and not jumped[segment] then
			jumped[segment] = true
			vy, airborne = JUMP, true
		end
		yaw += s[4] * DT
		if airborne then
			vy -= GRAVITY * DT
			position += Vector3.new(0, vy * DT, 0)
			if position.Y <= 0 then
				position = Vector3.new(position.X, 0, position.Z)
				airborne, vy = false, 0
			end
		end
		local facing = CFrame.Angles(0, yaw, 0)
		local velocity = facing.LookVector * speed + Vector3.new(0, vy, 0)
		if s[5] == "late" and vy == JUMP then
			velocity = facing.LookVector * speed
		end
		position += Vector3.new(velocity.X, 0, velocity.Z) * DT
		local rootCFrame = CFrame.new(position + Vector3.new(0, -mountC0.Position.Y, 0)) * facing

		local result = motion:update(DT, {
			rootCFrame = rootCFrame,
			velocity = velocity,
			airborne = airborne,
			gravity = GRAVITY,
			mountC0 = mountC0,
		})
		local transforms = Pose.solve(rigData, rootCFrame, result.targets)
		local frames = forward(rig, rootCFrame, transforms)

		local label = s[2]
		local entry = stats[label] or { hand = 0, frontFoot = 0, frontSink = 0, backFoot = 0, frames = 0, kickLow = math.huge }
		stats[label] = entry
		entry.frames += 1
		if motion.trick then
			entry.trick = motion.trick.kind
		end
		for side, spec in rig.hands do
			local hand = frames[spec[1]] * spec[2]
			entry.hand = math.max(entry.hand, (hand - result.targets.hands[side]).Magnitude)
		end
		local deck = rootCFrame * mountC0 * result.mount
		local function sole(side)
			local spec = rig.soles[side]
			return deck:PointToObjectSpace(frames[spec[1]] * spec[2]), deck:PointToObjectSpace(result.targets.feet[side])
		end
		local left, leftTarget = sole("Left")
		if label ~= "tailwhip" and label ~= "spin" then
			entry.frontFoot = math.max(entry.frontFoot, math.abs(left.Y - leftTarget.Y))
			entry.frontSink = math.max(entry.frontSink, -left.Y)
		end
		if motion.push < 0.05 and motion.idle < 0.05 and not airborne then
			local right, rightTarget = sole("Right")
			entry.backFoot = math.max(entry.backFoot, math.abs(right.Y - rightTarget.Y))
		end
		if label == "kicking" then
			entry.kickLow = math.min(entry.kickLow, (sole("Right")).Y)
		end

		-- Directions: in the left turn the front wheel points left, rider and
		-- scooter lean left; moving forward, the top of the wheels rolls forward.
		if label == "turning left" and t > 4.5 then
			local facingFrame = rootCFrame * mountC0
			local wheelFront = facingFrame:PointToObjectSpace(deck * scooter.steerC0 * result.steer * scooter.steerC0:Inverse() * Vector3.new(0, 0, -1.7))
			entry.steersLeft = (entry.steersLeft or true) and wheelFront.X < -0.05
			local headPart = if kind == "R6" then "Head" else "Head"
			entry.leansLeft = (entry.leansLeft or true) and facingFrame:PointToObjectSpace(frames[headPart].Position).X < -0.05
		end
		if label == "cruising" and entry.lastWheel then
			local step = entry.lastWheel:Inverse() * result.wheel
			entry.rollsForward = (entry.rollsForward ~= false) and (step * Vector3.new(0, 1, 0)).Z < 0
		end
		entry.lastWheel = result.wheel

		local dumpLabel
		for _, dump in DUMP_AT do
			if math.abs(t - dump[1]) < DT / 2 then
				dumpLabel = dump[2]
			end
		end
		if label == "kicking" then
			kickCycle = kickCycle or 0
			if lastPhase and motion.phase < lastPhase then
				kickCycle += 1
			end
			for _, dump in DUMP_KICK do
				if kickCycle == 1 and lastPhase and lastPhase < dump[1] and motion.phase >= dump[1] then
					dumpLabel = dump[2]
				end
			end
			lastPhase = motion.phase
		end
		if dumpLabel then
			local bodyParts = {}
			for name, cframe in frames do
				if name ~= "HumanoidRootPart" then
					local p = rig.parts[name]
					table.insert(bodyParts, { name = name, size = { p.Size.X, p.Size.Y, p.Size.Z }, cframe = { cframe:GetComponents() } })
				end
			end
			table.insert(dumpFrames, {
				rig = kind,
				label = dumpLabel,
				body = bodyParts,
				root = { (rootCFrame * mountC0 * result.mount):GetComponents() },
				-- the ground under the rider, facing the way they face
				origin = { (rootCFrame * mountC0 * CFrame.new(0, -scooter.deckHeight, 0)):GetComponents() },
				steer = { result.steer:GetComponents() },
				wheel = { result.wheel:GetComponents() },
			})
		end
		t += DT
	end
	return stats
end

local LIMITS = {
	R6 = { hand = 0.12, frontFoot = 0.05, backFoot = 0.05 },
	R15 = { hand = 0.02, frontFoot = 0.02, backFoot = 0.02 },
}

for _, make in { r6, r15 } do
	local rig = make()
	local kind = rig.humanoid.RigType.Name
	print(`{kind}:`)
	local stats = ride(rig)
	local limit = LIMITS[kind]
	for _, s in SCRIPT do
		local e = stats[s[2]]
		if e then
			print(string.format("    %-20s hands off grips %.3f   front foot off deck %.3f (sunk %.3f)   back foot %.3f",
				s[2], e.hand, e.frontFoot, math.max(0, e.frontSink), e.backFoot))
		end
	end
	local turning, cruising, kicking = stats["turning left"], stats.cruising, stats.kicking
	check(turning.steersLeft == true, `{kind} handlebar turns left in a left turn`)
	check(turning.leansLeft == true, `{kind} rider leans into a left turn`)
	check(cruising.rollsForward == true, `{kind} wheels roll forward`)
	check(stats.tailwhip.trick == "tailwhip", `{kind} first jump at speed does a tailwhip`)
	check(stats.spin.trick == "spin", `{kind} second jump does a 360 spin (jump velocity arriving a frame late)`)
	print(string.format("    kicking foot lowest %.2f below the deck (ground is %.2f below)", -kicking.kickLow, scooter.deckHeight))
	if kind == "R15" then
		check(math.abs(kicking.kickLow + scooter.deckHeight) < 0.05, "R15 kicking foot touches the ground")
	end
	local worstHand, worstFront, worstBack = 0, 0, 0
	for _, e in stats do
		worstHand = math.max(worstHand, e.hand)
		worstFront = math.max(worstFront, e.frontFoot)
		worstBack = math.max(worstBack, e.backFoot)
	end
	check(worstHand <= limit.hand, string.format("%s hands stay on the grips (worst %.3f, limit %.2f)", kind, worstHand, limit.hand))
	check(worstFront <= limit.frontFoot, string.format("%s front foot stays on the deck (worst %.3f, limit %.2f)", kind, worstFront, limit.frontFoot))
	check(worstBack <= limit.backFoot, string.format("%s back foot on the deck while rolling (worst %.3f, limit %.2f)", kind, worstBack, limit.backFoot))
end

if table.find(process.args, "--dump") then
	fs.writeDir("build")
	fs.writeFile("build/scooter-poses.json", serde.encode("json", dumpFrames))
	print(`Wrote build/scooter-poses.json ({#dumpFrames} poses)`)
end

print(if failures == 0 then "all checks passed" else `{failures} check(s) failed`)
if failures > 0 then
	process.exit(1)
end
