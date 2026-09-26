--[[
	Rider visuals — replaces the NCT: M "FEAnims" handler.

	The bike carries its own animated body (Misc.Anims.R6 / R15). While someone
	rides, their real body is hidden and their look is copied onto that
	animated body: colours, clothes, the whole head (mesh + face, classic or
	dynamic) and accessories.

	  * Runs on the server from DriveSeat.Occupant, so the client can't pick
	    whose body gets hidden and nothing depends on the rider's GUI.
	  * Copies instead of moving things off the character, and restores the
	    rider when they get off, when the bike is despawned while they ride,
	    or when the bike leaves the workspace.
	  * Accessories are found whatever joins them to the body (Weld,
	    WeldConstraint, RigidConstraint, attachment name, nearest part) and
	    the original is always hidden. The real body sits higher than the
	    animated one, so a missed accessory would otherwise float above the
	    rider's head.
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
-- The animated R6 body is a uniformly scaled R6 (a normal R6 torso is 2 studs tall).
local R6_SCALE = R6_PARTS.Torso.Size.Y / 2

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

local function scaleFor(isR6, real, fake)
	return if isR6 then R6_SCALE else fake.Size.Y / real.Size.Y
end

-- Turns a copied body/accessory part into a weightless visual, scaled to the animated body.
local function prepareCopy(part, scale)
	for _, item in part:GetDescendants() do
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint")
			or item:IsA("Attachment") or item:IsA("LuaSourceContainer") or item:IsA("ValueBase") then
			item:Destroy()
		end
	end
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Size *= scale
	for _, mesh in part:GetChildren() do
		if mesh:IsA("SpecialMesh") then
			-- Head/Brick/Sphere meshes follow the part size; file meshes don't.
			if mesh.MeshType == Enum.MeshType.FileMesh then
				mesh.Scale *= scale
			end
			mesh.Offset *= scale
		end
	end
end

local function attachCopy(copy, target, offset)
	copy.CFrame = target.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = target
	weld.Part1 = copy
	weld.C0 = offset
	weld.Parent = copy
	keep(copy, target.Parent)
end

-- The body part an accessory hangs on, however it was joined.
local function attachedPart(handle, character, parts)
	local function bodyPart(part)
		if part and part ~= handle and part:IsA("BasePart") and part.Parent == character and parts[part.Name] then
			return part
		end
		return nil
	end
	for _, item in handle:GetChildren() do
		local found = nil
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") then
			found = bodyPart(item.Part0) or bodyPart(item.Part1)
		elseif item:IsA("Constraint") then
			found = bodyPart(item.Attachment0 and item.Attachment0.Parent)
				or bodyPart(item.Attachment1 and item.Attachment1.Parent)
		end
		if found then
			return found
		end
	end
	-- Humanoids attach accessories by attachment name (e.g. HairAttachment on the Head).
	for _, attachment in handle:GetChildren() do
		if attachment:IsA("Attachment") then
			for name in parts do
				local part = character:FindFirstChild(name)
				if part and part:FindFirstChild(attachment.Name) then
					return part
				end
			end
		end
	end
	local nearest, nearestDistance = nil, math.huge
	for name in parts do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local distance = (part.Position - handle.Position).Magnitude
			if distance < nearestDistance then
				nearest, nearestDistance = part, distance
			end
		end
	end
	return nearest
end

local function copyAccessory(accessory, character, parts, isR6)
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	-- Layered clothing can't be wrapped onto the animated body; it is only hidden.
	if not handle:FindFirstChildOfClass("WrapLayer") then
		local attachedTo = attachedPart(handle, character, parts)
		local target = attachedTo and parts[attachedTo.Name]
		if target then
			local scale = scaleFor(isR6, attachedTo, target)
			local offset = attachedTo.CFrame:ToObjectSpace(handle.CFrame)
			offset = offset - offset.Position + offset.Position * scale
			local copy = handle:Clone()
			copy.Name = accessory.Name
			prepareCopy(copy, scale)
			attachCopy(copy, target, offset)
		end
	end
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

	-- Everything is copied from the real body before any of it is hidden.

	-- Head: copy the real head as a whole (mesh, face decal or dynamic head,
	-- colour) onto the animated head, which itself stays invisible.
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") and parts.Head then
		local copy = head:Clone()
		copy.Name = "RiderHead"
		prepareCopy(copy, scaleFor(isR6, head, parts.Head))
		attachCopy(copy, parts.Head, CFrame.identity)
	end

	-- Accessories
	for _, item in character:GetChildren() do
		if item:IsA("Accessory") then
			copyAccessory(item, character, parts, isR6)
		end
	end

	-- Body: show the animated parts in the rider's colours, hide the real ones.
	for name, fake in parts do
		local real = character:FindFirstChild(name)
		if fake and real and real:IsA("BasePart") then
			if name ~= "Head" then
				fake.Color = real.Color
				fake.Transparency = 0
				table.insert(session.shown, fake)
			end
			hide(real, "Transparency")
		end
	end
	if head then
		for _, item in head:GetDescendants() do
			if item:IsA("Decal") then
				hide(item, "Transparency")
			end
		end
	end

	-- Clothing and R6 packages
	if isR6 then
		for name, fake in R6_PARTS do
			if name ~= "Head" then
				ensureHumanoid(fake.Parent, Enum.HumanoidRigType.R6)
			end
		end
	else
		ensureHumanoid(R15, Enum.HumanoidRigType.R15)
	end
	for _, item in character:GetChildren() do
		if isR6 and R6_CLOTHING[item.ClassName] then
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
