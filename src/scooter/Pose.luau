--[[
	Scooter — rider pose (ScooterAnimator > Pose)

	Works out Motor6D.Transform for a rider's joints so the hands hold the
	grips and the feet stand on the deck (or kick the ground), for R6 and
	R15 rigs of any size. Pure maths on the rig's own C0/C1 values: nothing
	is read from part positions, so it doesn't lag a frame behind, and it
	can be tested outside Roblox (tools/test-scooter-pose.luau).

	  local rig = Pose.rig(character)                  -- nil if the rig isn't R6/R15
	  local transforms = Pose.solve(rig, rootCFrame, targets[, reuse])
	  for motor, transform in transforms do motor.Transform = transform end

	targets:
	  lean, roll, dip, spin    body posture (radians / studs)
	  ground                   point the body rolls around, in the root part's space
	  twist                    radians the shoulders turn with the handlebar
	  hands.Left/Right         world positions of the grips
	  feet.Left/Right          world positions for the soles
	  slide.Left/Right         R6 only: rigid legs reach the deck by sliding the
	                           foot along this direction instead of floating
	  facing                   world CFrame whose rotation the feet and head follow
	  headPitch                radians the head looks down
]]

local Pose = {}

local IDENTITY = CFrame.new()
local DOWN = Vector3.new(0, -1, 0)

local function rotation(cframe)
	return cframe - cframe.Position
end

-- Smallest rotation turning unit vector a into unit vector b.
local function between(a, b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		if dot > 0 then
			return IDENTITY
		end
		local other = if math.abs(a.X) < 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
		return CFrame.fromAxisAngle(a:Cross(other).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Part1 = parent * C0 * Transform * C1^-1

-- Moves Part1 by `offset`, given in Part0's space (a rigid transform).
local function shift(out, motor, parent, offset)
	out[motor] = motor.C0:Inverse() * offset * motor.C0
	return parent * offset * motor.C0 * motor.C1:Inverse()
end

-- Turns the joint so `point` (in Part1's space) points at `target`.
local function aim(out, motor, parent, point, target)
	local frame = parent * motor.C0
	local c1Inverse = motor.C1:Inverse()
	local from = c1Inverse * point
	local to = frame:PointToObjectSpace(target)
	local transform = IDENTITY
	if from.Magnitude > 1e-4 and to.Magnitude > 1e-4 then
		transform = between(from.Unit, to.Unit)
	end
	out[motor] = transform
	return frame * transform * c1Inverse
end

-- Turns the joint so Part1 has the rotation of `goal` (blended by `weight`).
local function orient(out, motor, parent, goal, weight)
	local transform = rotation(parent * motor.C0):Inverse() * rotation(goal) * rotation(motor.C1)
	if weight < 1 then
		transform = IDENTITY:Lerp(transform, weight)
	end
	out[motor] = transform
	return parent * motor.C0 * transform * motor.C1:Inverse()
end

-- Two joints (shoulder + elbow, hip + knee): `point` in the lower part's
-- space reaches `target`, the middle joint bends towards `pole`.
local function twoBone(out, upper, lower, parent, point, target, pole)
	local start = (parent * upper.C0).Position
	local middle = lower.C0.Position -- middle joint, in the upper part's space
	local a = (middle - upper.C1.Position).Magnitude
	local b = (point - lower.C1.Position).Magnitude
	local toTarget = target - start
	local direction = if toTarget.Magnitude > 1e-4 then toTarget.Unit else DOWN
	local distance = math.clamp(toTarget.Magnitude, math.abs(a - b) + 1e-3, a + b - 1e-3)
	local cosine = math.clamp((a * a + distance * distance - b * b) / (2 * a * distance), -1, 1)
	local bend = pole - direction * pole:Dot(direction)
	if bend.Magnitude < 1e-4 then
		bend = direction:Cross(Vector3.new(1, 0, 0))
	end
	bend = bend.Unit
	local joint = start + direction * (a * cosine) + bend * (a * math.sqrt(1 - cosine * cosine))
	local upperFrame = aim(out, upper, parent, middle, joint)
	local lowerFrame = aim(out, lower, upperFrame, point, start + direction * distance)
	return upperFrame, lowerFrame
end

-- A rigid limb (R6) can't shorten, so a target closer than the limb's
-- length is moved along `slide` until the limb exactly reaches it.
local function reach(pivot, target, length, slide)
	local offset = target - pivot
	if offset.Magnitude >= length or not slide then
		return target
	end
	local along = offset:Dot(slide)
	local distance = -along + math.sqrt(math.max(0, along * along - (offset:Dot(offset) - length * length)))
	return target + slide * distance
end

local function motorIn(character, partName, jointName)
	local part = character:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	return if joint and joint:IsA("Motor6D") then joint else nil
end

-- Reads the rig's joints. Returns nil if anything the pose needs is missing.
function Pose.rig(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local rig = {
			kind = "R6",
			root = motorIn(character, "HumanoidRootPart", "RootJoint"),
			neck = motorIn(character, "Torso", "Neck"),
			arms = {},
			legs = {},
		}
		if not (rig.root and rig.neck) then
			return nil
		end
		for _, side in { "Left", "Right" } do
			local arm = character:FindFirstChild(side .. " Arm")
			local leg = character:FindFirstChild(side .. " Leg")
			local shoulder = motorIn(character, "Torso", side .. " Shoulder")
			local hip = motorIn(character, "Torso", side .. " Hip")
			if not (arm and leg and shoulder and hip) then
				return nil
			end
			-- The bar sits in the lower part of the arm block (its "fist").
			rig.arms[side] = { joint = shoulder, point = Vector3.new(0, -arm.Size.Y * 0.3, 0) }
			rig.legs[side] = { joint = hip, point = Vector3.new(0, -leg.Size.Y / 2, 0) }
		end
		-- Hips (Torso space) -> the pivot the body leans around (root space).
		local hips = (rig.legs.Left.joint.C0.Position + rig.legs.Right.joint.C0.Position) / 2
		rig.pivot = rig.root.C0 * rig.root.C1:Inverse() * hips
		return rig
	end

	local rig = {
		kind = "R15",
		root = motorIn(character, "LowerTorso", "Root"),
		waist = motorIn(character, "UpperTorso", "Waist"),
		neck = motorIn(character, "Head", "Neck"),
		arms = {},
		legs = {},
	}
	if not (rig.root and rig.waist and rig.neck) then
		return nil
	end
	for _, side in { "Left", "Right" } do
		local hand = character:FindFirstChild(side .. "Hand")
		local foot = character:FindFirstChild(side .. "Foot")
		local arm = {
			upper = motorIn(character, side .. "UpperArm", side .. "Shoulder"),
			lower = motorIn(character, side .. "LowerArm", side .. "Elbow"),
			wrist = motorIn(character, side .. "Hand", side .. "Wrist"),
		}
		local leg = {
			upper = motorIn(character, side .. "UpperLeg", side .. "Hip"),
			lower = motorIn(character, side .. "LowerLeg", side .. "Knee"),
			ankle = motorIn(character, side .. "Foot", side .. "Ankle"),
		}
		if not (hand and foot and arm.upper and arm.lower and arm.wrist and leg.upper and leg.lower and leg.ankle) then
			return nil
		end
		-- Grip point of the hand and sole of the foot, in the lower arm / lower leg's space.
		local grip = hand:FindFirstChild(side .. "GripAttachment")
		local gripPosition = if grip and grip:IsA("Attachment") then grip.CFrame.Position else Vector3.new()
		arm.point = arm.wrist.C0 * arm.wrist.C1:Inverse() * gripPosition
		-- The leg's IK moves the ankle; the foot is then turned flat, so the
		-- ankle goes where the sole's target is plus the ankle's height above the sole.
		leg.point = leg.ankle.C0.Position
		leg.ankleAboveSole = leg.ankle.C1.Position - Vector3.new(0, -foot.Size.Y / 2, 0)
		rig.arms[side] = arm
		rig.legs[side] = leg
	end
	local hips = (rig.legs.Left.upper.C0.Position + rig.legs.Right.upper.C0.Position) / 2
	rig.pivot = rig.root.C0 * rig.root.C1:Inverse() * hips
	return rig
end

-- Body posture in root space: dip down, spin and roll around the ground
-- under the rider (like the scooter), then lean around the hips.
local function posture(rig, targets, leanShare, twist)
	local ground = CFrame.new(targets.ground or Vector3.new())
	local hips = CFrame.new(rig.pivot)
	return CFrame.new(0, -(targets.dip or 0), 0)
		* ground
		* CFrame.Angles(0, targets.spin or 0, 0)
		* CFrame.Angles(0, 0, targets.roll or 0)
		* ground:Inverse()
		* hips
		* CFrame.Angles(0, twist, 0)
		* CFrame.Angles(-(targets.lean or 0) * leanShare, 0, 0)
		* hips:Inverse()
end

local SIDES = { Left = -1, Right = 1 }

-- `out` (optional) is reused between frames to save allocating a table:
-- every call writes the same joints.
function Pose.solve(rig, rootCFrame, targets, out)
	out = out or {}
	local facing = rotation(targets.facing or rootCFrame)
	local head = facing * CFrame.Angles(-(targets.headPitch or 0), 0, 0)

	if rig.kind == "R6" then
		local torso = shift(out, rig.root, rootCFrame, posture(rig, targets, 1, targets.twist or 0))
		for side, arm in rig.arms do
			aim(out, arm.joint, torso, arm.point, targets.hands[side])
		end
		for side, leg in rig.legs do
			local pivot = (torso * leg.joint.C0).Position
			local length = (leg.joint.C1:Inverse() * leg.point).Magnitude
			local target = reach(pivot, targets.feet[side], length, targets.slide and targets.slide[side])
			aim(out, leg.joint, torso, leg.point, target)
		end
		orient(out, rig.neck, torso, head, 0.7)
		return out
	end

	-- R15: lean split between the hips and the waist for a rounder back.
	local lowerTorso = shift(out, rig.root, rootCFrame, posture(rig, targets, 0.55, 0))
	local waistPivot = CFrame.new(rig.waist.C0.Position)
	local bend = waistPivot
		* CFrame.Angles(0, targets.twist or 0, 0)
		* CFrame.Angles(-(targets.lean or 0) * 0.45, 0, 0)
		* waistPivot:Inverse()
	local upperTorso = shift(out, rig.waist, lowerTorso, bend)

	for side, arm in rig.arms do
		-- Elbows bend outwards, backwards and a little down.
		local pole = facing:VectorToWorldSpace(Vector3.new(SIDES[side] * 0.6, -0.4, 1))
		twoBone(out, arm.upper, arm.lower, upperTorso, arm.point, targets.hands[side], pole)
		out[arm.wrist] = IDENTITY
	end
	for side, leg in rig.legs do
		-- Knees bend forwards and slightly outwards.
		local pole = facing:VectorToWorldSpace(Vector3.new(SIDES[side] * 0.25, 0, -1))
		local ankle = targets.feet[side] + facing:VectorToWorldSpace(leg.ankleAboveSole)
		local _, lowerLeg = twoBone(out, leg.upper, leg.lower, lowerTorso, leg.point, ankle, pole)
		orient(out, leg.ankle, lowerLeg, facing, 1)
	end
	orient(out, rig.neck, upperTorso, head, 0.7)
	return out
end

return Pose
