--[[
	Rider visuals — replaces the NCT: M "FEAnims" handler.

	The bike carries its own animated body (Misc.Anims.R6 / R15). While someone
	rides, their real body is hidden and their look (colours, clothes, face,
	head mesh, accessories) is copied onto that animated body.

	Differences from the original:
	  * Runs on the server from DriveSeat.Occupant. The client can no longer
	    pick whose body gets hidden, and nothing depends on the rider's GUI
	    still existing when they get off.
	  * Copies instead of moving things off the character, and restores the
	    rider when they get off, when the bike is despawned while they ride,
	    or when the bike leaves the workspace. The rider never ends up
	    invisible, faceless or without accessories.
	  * R6: also copies T-shirts, R6 package meshes (CharacterMesh) and scales
	    accessories to the slightly smaller rider body.
]]

local Players = game:GetService("Players")

local bike = script.Parent.Parent
local seat = bike:WaitForChild("DriveSeat")
local rigs = bike:WaitForChild("Misc"):WaitForChild("Anims")
local R6 = rigs:WaitForChild("R6")
local R15 = rigs:WaitForChild("R15")

-- The R15 animation plugin expects the body parts directly under Misc.Anims.R15.
for _, path in {
	"RightArm.UpperArm.Parts.RightUpperArm", "RightArm.LowerArm.Parts.RightLowerArm", "RightArm.Hand.Parts.RightHand",
	"RightLeg.UpperLeg.Parts.RightUpperLeg", "RightLeg.LowerLeg.Parts.RightLowerLeg", "RightLeg.Foot.Parts.RightFoot",
	"LeftArm.UpperArm.Parts.LeftUpperArm", "LeftArm.LowerArm.Parts.LeftLowerArm", "LeftArm.Hand.Parts.LeftHand",
	"LeftLeg.UpperLeg.Parts.LeftUpperLeg", "LeftLeg.LowerLeg.Parts.LeftLowerLeg", "LeftLeg.Foot.Parts.LeftFoot",
	"Torso.LowerTorso.Parts.LowerTorso", "Torso.UpperTorso.Parts.UpperTorso", "Torso.Head.Parts.NewHead",
} do
	local node = R15
	for name in path:gmatch("[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	if node then
		node.Parent = R15
	end
end

-- Character part name -> animated part on the bike.
local R6_PARTS = {
	Head = R6.Head.Parts.NewHead,
	Torso = R6.Torso.Parts.Torso,
	["Right Arm"] = R6.RightArm.Parts["Right Arm"],
	["Left Arm"] = R6.LeftArm.Parts["Left Arm"],
	["Right Leg"] = R6.RightLeg.Parts["Right Leg"],
	["Left Leg"] = R6.LeftLeg.Parts["Left Leg"],
}

local R15_PARTS = {}
for _, name in {
	"UpperTorso", "LowerTorso",
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
} do
	R15_PARTS[name] = R15:FindFirstChild(name)
end
R15_PARTS.Head = R15:FindFirstChild("NewHead")

-- Where R6 clothing / package meshes go (each needs a Humanoid in its model).
local R6_CLOTHING = {
	Shirt = { "Torso", "Right Arm", "Left Arm" },
	Pants = { "Torso", "Right Leg", "Left Leg" },
	ShirtGraphic = { "Torso" },
}
local R6_BODYPART = {
	[Enum.BodyPart.Torso] = "Torso",
	[Enum.BodyPart.RightArm] = "Right Arm",
	[Enum.BodyPart.LeftArm] = "Left Arm",
	[Enum.BodyPart.RightLeg] = "Right Leg",
	[Enum.BodyPart.LeftLeg] = "Left Leg",
}

local session = nil

local function ensureHumanoid(model, rigType)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.RigType = rigType
		humanoid.AutoJumpEnabled = false
		humanoid.AutoRotate = false
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.Parent = model
	end
	return humanoid
end

local function hide(instance, property)
	table.insert(session.hidden, { instance, property, instance[property] })
	instance[property] = 1
end

local function keep(clone, parent)
	clone.Parent = parent
	table.insert(session.clones, clone)
	return clone
end

local function restore()
	local current = session
	session = nil
	if not current then
		return
	end
	for _, entry in current.hidden do
		local instance, property, value = entry[1], entry[2], entry[3]
		if instance.Parent then
			pcall(function()
				instance[property] = value
			end)
		end
	end
	for _, clone in current.clones do
		clone:Destroy()
	end
	for _, part in current.shown do
		part.Transparency = 1
	end
end

-- Copies an accessory onto the animated body at the same offset, scaled to
-- the animated part's size. The original stays on the character, hidden.
local function copyAccessory(accessory, parts)
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	local joint = handle:FindFirstChild("AccessoryWeld")
	local attachedTo = nil
	if joint and (joint:IsA("JointInstance") or joint:IsA("WeldConstraint")) then
		attachedTo = joint.Part1 ~= handle and joint.Part1 or joint.Part0
	end
	local target = attachedTo and parts[attachedTo.Name]
	if not target then
		return
	end

	local scale = target.Size.Y / attachedTo.Size.Y
	local offset = attachedTo.CFrame:ToObjectSpace(handle.CFrame)
	offset = offset - offset.Position + offset.Position * scale

	local clone = handle:Clone()
	for _, item in clone:GetDescendants() do
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then
			item:Destroy()
		end
	end
	clone.Name = accessory.Name
	clone.Anchored = false
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.Massless = true
	clone.Size *= scale
	local mesh = clone:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.Scale *= scale
		mesh.Offset *= scale
	end
	clone.CFrame = target.CFrame * offset

	local weld = Instance.new("Weld")
	weld.Part0 = target
	weld.Part1 = clone
	weld.C0 = offset
	weld.Parent = clone

	keep(clone, target.Parent)
	hide(handle, "Transparency")
end

local function apply(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local isR6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local parts = isR6 and R6_PARTS or R15_PARTS
	session = { hidden = {}, clones = {}, shown = {} }

	-- Body: show the animated part in the rider's colour, hide the real one.
	for name, fake in parts do
		local real = character:FindFirstChild(name)
		if fake and real and real:IsA("BasePart") then
			fake.Color = real.Color
			fake.Transparency = 0
			table.insert(session.shown, fake)
			hide(real, "Transparency")
		end
	end

	-- Head mesh and face
	local head = character:FindFirstChild("Head")
	if head and parts.Head then
		for _, item in head:GetChildren() do
			if item:IsA("SpecialMesh") then
				keep(item:Clone(), parts.Head)
			elseif item:IsA("Decal") then
				keep(item:Clone(), parts.Head)
				hide(item, "Transparency")
			end
		end
	end

	-- Clothing, R6 packages, accessories
	if isR6 then
		for _, name in R6_CLOTHING.Shirt do
			ensureHumanoid(R6_PARTS[name].Parent, Enum.HumanoidRigType.R6)
		end
		ensureHumanoid(R6_PARTS["Right Leg"].Parent, Enum.HumanoidRigType.R6)
		ensureHumanoid(R6_PARTS["Left Leg"].Parent, Enum.HumanoidRigType.R6)
	else
		ensureHumanoid(R15, Enum.HumanoidRigType.R15)
	end

	for _, item in character:GetChildren() do
		if item:IsA("Accessory") then
			copyAccessory(item, parts)
		elseif isR6 and R6_CLOTHING[item.ClassName] then
			for _, name in R6_CLOTHING[item.ClassName] do
				keep(item:Clone(), R6_PARTS[name].Parent)
			end
		elseif isR6 and item:IsA("CharacterMesh") and R6_BODYPART[item.BodyPart] then
			keep(item:Clone(), R6_PARTS[R6_BODYPART[item.BodyPart]].Parent)
		elseif not isR6 and (item:IsA("Shirt") or item:IsA("Pants") or item:IsA("ShirtGraphic")) then
			keep(item:Clone(), R15)
		end
	end
end

local function onOccupantChanged()
	restore()
	local humanoid = seat.Occupant
	local character = humanoid and humanoid.Parent
	if character and Players:GetPlayerFromCharacter(character) then
		local ok, err = pcall(apply, character)
		if not ok then
			warn("[RiderVisuals]", err)
			restore()
		end
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)
bike.Destroying:Connect(restore)
bike.AncestryChanged:Connect(function()
	if not bike:IsDescendantOf(workspace) then
		restore()
	end
end)

if seat.Occupant then
	onOccupantChanged()
end
