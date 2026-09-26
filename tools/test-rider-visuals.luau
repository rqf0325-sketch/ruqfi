--[[
	Runs RiderVisuals' apply/restore against the real bike rig with a mock
	R6 rider (classic head + face, shirt, hair accessory) and checks the
	results. The hair is attached with a Weld in one run and a
	RigidConstraint in another.

	  lune run tools/patch-road-glide.luau && lune run tools/test-rider-visuals.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance, CFrame, Vector3, Enum = roblox.Instance, roblox.CFrame, roblox.Vector3, roblox.Enum

local SOURCE = "src/vehicle/RiderVisuals.server.luau"

local failures = 0
local function check(condition, message)
	print((condition and "  ok   " or "  FAIL ") .. message)
	if not condition then
		failures += 1
	end
end

local function near(a, b)
	return (a.Position - b.Position).Magnitude < 0.01
end

local function part(className, name, size, cframe, parent)
	local p = Instance.new(className)
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	return p
end

-- A seated R6 rider, placed well above the bike like the real (hidden) body.
local function makeRider(origin, jointKind)
	local character = Instance.new("Model")
	character.Name = "Rider"
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = character

	local torso = part("Part", "Torso", Vector3.new(2, 2, 1), origin, character)
	local head = part("Part", "Head", Vector3.new(2, 1, 1), origin * CFrame.new(0, 1.5, 0), character)
	for name, x in { ["Right Arm"] = 1.5, ["Left Arm"] = -1.5 } do
		part("Part", name, Vector3.new(1, 2, 1), origin * CFrame.new(x, 0, 0), character)
	end
	for name, x in { ["Right Leg"] = 0.5, ["Left Leg"] = -0.5 } do
		part("Part", name, Vector3.new(1, 2, 1), origin * CFrame.new(x, -2, 0), character)
	end
	torso.Color = roblox.Color3.fromRGB(10, 20, 30)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head
	local headAttachment = Instance.new("Attachment")
	headAttachment.Name = "HairAttachment"
	headAttachment.CFrame = CFrame.new(0, 0.6, 0)
	headAttachment.Parent = head

	local shirt = Instance.new("Shirt")
	shirt.Parent = character

	local hair = Instance.new("Accessory")
	hair.Name = "Hair"
	local handle = part("MeshPart", "Handle", Vector3.new(1.6, 1, 1.6), head.CFrame * CFrame.new(0, 0.7, 0.1), hair)
	local handleAttachment = Instance.new("Attachment")
	handleAttachment.Name = "HairAttachment"
	handleAttachment.CFrame = CFrame.new(0, -0.1, -0.1)
	handleAttachment.Parent = handle
	if jointKind == "Weld" then
		local weld = Instance.new("Weld")
		weld.Name = "AccessoryWeld"
		weld.Part0 = handle
		weld.Part1 = head
		weld.Parent = handle
	else
		local rigid = Instance.new("RigidConstraint")
		rigid.Name = "AccessoryWeld"
		rigid.Attachment0 = handleAttachment
		rigid.Attachment1 = headAttachment
		rigid.Parent = handle
	end
	hair.Parent = character

	-- 3D face accessory joined only by attachment name (no weld at all).
	local faceFront = Instance.new("Attachment")
	faceFront.Name = "FaceFrontAttachment"
	faceFront.CFrame = CFrame.new(0, 0, -0.6)
	faceFront.Parent = head
	local faceAccessory = Instance.new("Accessory")
	faceAccessory.Name = "FaceAccessory"
	local faceHandle = part("MeshPart", "Handle", Vector3.new(1, 0.8, 0.2), head.CFrame * CFrame.new(0, 0, -0.6), faceAccessory)
	local faceHandleAttachment = Instance.new("Attachment")
	faceHandleAttachment.Name = "FaceFrontAttachment"
	faceHandleAttachment.Parent = faceHandle
	faceAccessory.Parent = character
	return character
end

local function loadRiderVisuals(bike)
	local source = fs.readFile(SOURCE)
	-- No signals in Lune: expose apply/restore instead of connecting events.
	local cut = source:find('seat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)', 1, true)
	assert(cut, "event hookup not found")
	source = source:sub(1, cut - 1) .. "return { apply = apply, restore = restore, parts = R6_PARTS }\n"
	source = source:gsub(":WaitForChild%(", ":FindFirstChild(")
	local env = setmetatable({
		script = { Parent = { Parent = bike } },
		game = Instance.new("DataModel"),
		Instance = Instance,
		Enum = Enum,
		CFrame = CFrame,
		Vector3 = Vector3,
	}, { __index = getfenv(1) })
	return luau.load(source, { debugName = SOURCE, environment = env })()
end

for _, jointKind in { "Weld", "RigidConstraint" } do
	print(`R6 rider, hair attached with {jointKind}:`)
	local folder = roblox.deserializeModel(fs.readFile("ServerStorage/Vehicles.rbxm"))[1]
	local bike = folder:GetChildren()[1]
	local rider = loadRiderVisuals(bike)
	local newHead = rider.parts.Head

	local character = makeRider(newHead.CFrame * CFrame.new(0, 2.5, 0.4), jointKind)
	local head, handle = character.Head, character.Hair.Handle
	rider.apply(character)

	local riderHead = newHead.Parent:FindFirstChild("RiderHead")
	check(riderHead ~= nil, "head copied onto the bike's head")
	check(riderHead and near(riderHead.CFrame, newHead.CFrame), "head copy sits exactly on the bike's head")
	check(riderHead and riderHead:FindFirstChild("face") and riderHead.face.Transparency == 0, "face visible on the head copy")
	check(riderHead and riderHead:FindFirstChildOfClass("SpecialMesh") ~= nil, "head mesh copied")
	check(newHead.Transparency == 1, "bike's plain head block stays hidden")
	check(head.Transparency == 1 and head.face.Transparency == 1, "real head and face hidden")

	local hairCopy = newHead.Parent:FindFirstChild("Hair")
	check(hairCopy ~= nil, "hair copied onto the bike's head")
	local expected = newHead.CFrame * CFrame.new(0, 0.7 * 0.896, 0.1 * 0.896)
	check(hairCopy and (hairCopy.CFrame.Position - expected.Position).Magnitude < 0.05, "hair sits on the rider's head (not floating)")
	check(hairCopy and hairCopy:FindFirstChildOfClass("Weld") and hairCopy:FindFirstChildOfClass("Weld").Part0 == newHead, "hair welded to the bike's head")
	check(handle.Transparency == 1, "original hair hidden")
	local faceCopy = newHead.Parent:FindFirstChild("FaceAccessory")
	local faceExpected = newHead.CFrame * CFrame.new(0, 0, -0.6 * 0.896)
	check(faceCopy and (faceCopy.CFrame.Position - faceExpected.Position).Magnitude < 0.05, "3D face accessory copied onto the front of the head")
	check(character.FaceAccessory.Handle.Transparency == 1, "original 3D face hidden")
	check(bike.Misc.Anims.R6.Torso.Parts.Torso.Transparency == 0, "animated torso shown")
	check(bike.Misc.Anims.R6.Torso.Parts:FindFirstChildOfClass("Shirt") ~= nil, "shirt copied")
	check(character.Torso.Transparency == 1, "real torso hidden")

	rider.restore()
	check(head.Transparency == 0 and head.face.Transparency == 0, "restore: real head and face back")
	check(handle.Transparency == 0, "restore: hair back")
	check(character.FaceAccessory.Handle.Transparency == 0, "restore: 3D face back")
	check(character.Torso.Transparency == 0, "restore: torso back")
	check(newHead.Parent:FindFirstChild("RiderHead") == nil and newHead.Parent:FindFirstChild("Hair") == nil, "restore: copies removed")
	check(bike.Misc.Anims.R6.Torso.Parts.Torso.Transparency == 1, "restore: animated torso hidden")
end

print(failures == 0 and "All checks passed" or `{failures} checks failed`)
if failures > 0 then
	process.exit(1)
end
