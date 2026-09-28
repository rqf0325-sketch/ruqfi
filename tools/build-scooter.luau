--[[
	Turns the uploaded "scooter noctis" model into a rideable Tool:

	  StarterPack/Scooter.rbxm                  Tool (model, Settings, scripts)
	  StarterPlayerScripts/ScooterAnimator.rbxmx rider + wheel animation for every player

	  lune run tools/build-scooter.luau
	  lune run tools/build-scooter.luau -- --dump   (also writes build/scooter.json for tools/preview/scooter.cjs)

	The original is 40 grey MeshParts, all anchored, about twice the size of
	a character. This script:
	  * scales it to fit an R6/R15 rider (hands reach the grips, both feet fit
	    on the deck) and turns it to face the way the character faces (-Z)
	  * renames every part and gives it a Role for the colour themes
	  * joins it with Welds and Motor6Ds so the handlebar steers and the
	    wheels spin (Root -> Steer -> FrontSpin, Root -> RearSpin)
	  * adds a headlight, underglow and the rider's hand/foot anchors
	Every original part must be mapped exactly once, so a different version
	of the model can't be half-converted silently.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local rbxm = require("./lib/rbxm")

local Instance, Enum = roblox.Instance, roblox.Enum
local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3

local SOURCE = "vehicles/original/Scooter_Noctis.rbxm"
local TOOL_OUTPUT = "StarterPack/Scooter.rbxm"
local ANIMATOR_OUTPUT = "StarterPlayerScripts/ScooterAnimator.rbxmx"

-- Side profile scale (length and height). 0.36 puts the grips ~2.7 studs
-- above the deck: an R6 rider's arms point forward-down to reach them.
local SCALE = 0.36
-- Width scales (the original is 1.35 studs wide at the deck, 6 at the bar).
local DECK_WIDTH = 1.0 -- deck (1.35 studs): room for both feet
local WHEEL_WIDTH = 0.85 -- wheels, forks, fender
local BAR_WIDTH = 0.636 -- handlebar: grips 1.5 studs either side, where R6 hands are
-- The rider stands this far behind the middle of the deck.
local STAND_BACK = 0.2

-- Where the kicking foot goes, relative to Root (the deck surface under the rider).
local KICK_X = 1.05 -- the kicking foot passes this far right of the middle (under the deck edge)

---------------------------------------------------------------------------
-- Part map: original name -> new name, group, Role, width rule
--   group: Chassis (fixed) / Steering / FrontWheel / RearWheel
--   fit:   deck / wheel = that width, tube = round tube, bar = handlebar width
---------------------------------------------------------------------------

local MAP = {
	-- top level of the original model
	[""] = {
		Cube_9_2 = { "Deck", "Chassis", "Grip", "deck" },
		Cube_2 = { "DeckBase", "Chassis", "Paint", "deck" },
		Cube_7 = { "GlowStrip", "Chassis", "Glow", "deck" },
		Cube_3 = { "Neck", "Chassis", "Paint", "deck" },
		Cube_4 = { "Hinge", "Chassis", "Trim", "deck" },
		Tube_9 = { "HingeBoltLeft", "Chassis", "Metal", "deck" },
		Tube_8 = { "HingeBoltRight", "Chassis", "Metal", "deck" },
		Cube_6 = { "HeadTube", "Chassis", "Paint", "tube" },
		Tube_2_2 = { "HeadClamp", "Chassis", "Accent", "tube" },
		Tube_2 = { "ClampLever", "Chassis", "Metal", "tube" },
		Tube_5 = { "BoltRearLeft", "Chassis", "Metal", "deck" },
		Tube_4 = { "BoltRearRight", "Chassis", "Metal", "deck" },
		Tube_6 = { "BoltFrontLeft", "Chassis", "Metal", "deck" },
		Tube_7 = { "BoltFrontRight", "Chassis", "Metal", "deck" },
		Tube_4_2 = { "RearFender", "Chassis", "Paint", "wheel" },
		Cube_9 = { "FenderPlate", "Chassis", "Trim", "wheel" },
		Cylinder_1 = { "FenderPivot", "Chassis", "Metal", "wheel" },
		Cylinder_1_2 = { "RearForkLeft", "Chassis", "Trim", "wheel" },
		Cylinder = { "RearForkRight", "Chassis", "Trim", "wheel" },
		Cylinder_3 = { "RearAxle", "Chassis", "Metal", "wheel" },
		Cylinder_1_3 = { "ForkLeft", "Steering", "Trim", "wheel" },
		Cylinder_2 = { "ForkRight", "Steering", "Trim", "wheel" },
		Cylinder_4 = { "FrontAxle", "Steering", "Metal", "wheel" },
	},
	-- sub-models, recognised by the part named in [1]
	steering = {
		Cube_5 = { "Column", "Steering", "Trim", "tube" },
		Tube_3 = { "BarClamp", "Steering", "Accent", "tube" },
		Cube_8 = { "Handlebar", "Steering", "Trim", "bar" },
		Tube_1 = { "GripLeft", "Steering", "Rubber", "bar" },
		Tube = { "GripRight", "Steering", "Rubber", "bar" },
	},
	front = {
		Tube_4_3 = { "Tire", "FrontWheel", "Rubber", "wheel" },
		Cube_7_0_2 = { "Spoke1", "FrontWheel", "Rim", "wheel" },
		Cube_7_1_2 = { "Spoke2", "FrontWheel", "Rim", "wheel" },
		Cube_7_2_2 = { "Spoke3", "FrontWheel", "Rim", "wheel" },
		Cube_7_3_2 = { "Spoke4", "FrontWheel", "Rim", "wheel" },
		Cube_7_4_2 = { "Spoke5", "FrontWheel", "Rim", "wheel" },
	},
	rear = {
		Tube_3_2 = { "Tire", "RearWheel", "Rubber", "wheel" },
		Cube_7_0 = { "Spoke1", "RearWheel", "Rim", "wheel" },
		Cube_7_1 = { "Spoke2", "RearWheel", "Rim", "wheel" },
		Cube_7_2 = { "Spoke3", "RearWheel", "Rim", "wheel" },
		Cube_7_3 = { "Spoke4", "RearWheel", "Rim", "wheel" },
		Cube_7_4 = { "Spoke5", "RearWheel", "Rim", "wheel" },
	},
}
local SUBMODEL_KEYS = { steering = "Cube_5", front = "Tube_4_3", rear = "Tube_3_2" }

---------------------------------------------------------------------------
-- Load and sort the original parts
---------------------------------------------------------------------------

local clean, lostTags = rbxm.cleanForLune(fs.readFile(SOURCE))
assert(lostTags == 0, "the model has CollectionService tags that would be lost")
local original = roblox.deserializeModel(clean)[1]

local found = {} -- { part, name, group, role, fit }
local function take(part, section)
	local entry = MAP[section][part.Name]
	assert(entry, `unmapped part {section}/{part.Name}`)
	assert(not entry.used, `{section}/{part.Name} appears twice`)
	entry.used = true
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
	assert(math.abs(r00 - 1) + math.abs(r11 - 1) + math.abs(r22 - 1) + math.abs(r01) + math.abs(r02)
		+ math.abs(r10) + math.abs(r12) + math.abs(r20) + math.abs(r21) < 1e-3,
		`{part.Name} is rotated; the width rules assume axis-aligned parts`)
	table.insert(found, { part = part, name = entry[1], group = entry[2], role = entry[3], fit = entry[4] })
end

for _, child in original:GetChildren() do
	if child:IsA("BasePart") then
		take(child, "")
	elseif child:IsA("Model") then
		local section
		for key, marker in SUBMODEL_KEYS do
			if child:FindFirstChild(marker) then
				section = key
			end
		end
		assert(section, `unknown sub-model with {#child:GetChildren()} children`)
		for _, part in child:GetChildren() do
			assert(part:IsA("BasePart"), `unexpected {part.ClassName} in {section}`)
			take(part, section)
		end
	else
		error(`unexpected {child.ClassName} "{child.Name}"`)
	end
end
for section, entries in MAP do
	for name, entry in entries do
		assert(entry.used, `part {section}/{name} not found in the model`)
	end
end

---------------------------------------------------------------------------
-- Scale and turn
---------------------------------------------------------------------------

-- Original: front = +X, rider's right = +Z. New: front = -Z, right = +X.
local TURN = CFrame.Angles(0, math.rad(90), 0)

local function byName(name)
	for _, item in found do
		if item.name == name then
			return item
		end
	end
	error(`no part {name}`)
end

local deckPart = byName("Deck").part
local deckTop = deckPart.CFrame.Position.Y + deckPart.Size.Y / 2
local origin = Vector3.new(deckPart.CFrame.Position.X - STAND_BACK / SCALE, deckTop, deckPart.CFrame.Position.Z)

local tire = byName("Tire").part -- either wheel: both sit on the ground
local DECK_HEIGHT = (deckTop - (tire.CFrame.Position.Y - tire.Size.Y / 2)) * SCALE
local WHEEL_RADIUS = tire.Size.Y / 2 * SCALE

local POSITION_Z = { deck = DECK_WIDTH, wheel = WHEEL_WIDTH, tube = WHEEL_WIDTH, bar = BAR_WIDTH }
local SIZE_Z = { deck = DECK_WIDTH, wheel = WHEEL_WIDTH, tube = SCALE, bar = BAR_WIDTH }

-- Root sits on the deck surface; the file puts the wheels on y = 0.
local BASE = Vector3.new(0, DECK_HEIGHT, 0)
local function place(position, fit)
	local offset = position - origin
	return BASE + TURN * Vector3.new(offset.X * SCALE, offset.Y * SCALE, offset.Z * POSITION_Z[fit])
end

for _, item in found do
	local part = item.part
	item.cframe = CFrame.new(place(part.CFrame.Position, item.fit)) * TURN
	item.size = Vector3.new(part.Size.X * SCALE, part.Size.Y * SCALE, part.Size.Z * SIZE_Z[item.fit])
end

---------------------------------------------------------------------------
-- Build the Tool
---------------------------------------------------------------------------

local function new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function script(className, name, source, parent)
	return new(className, { Name = name, Source = fs.readFile(source) }, parent)
end

local tool = new("Tool", {
	Name = "Scooter",
	RequiresHandle = false,
	CanBeDropped = false,
	ToolTip = "Scooter",
}, nil)
tool:SetAttribute("Scooter", true)

script("ModuleScript", "Settings", "src/scooter/Settings.luau", tool)
script("ModuleScript", "ScooterShared", "src/scooter/ScooterShared.luau", tool)
script("ModuleScript", "ScooterHud", "src/scooter/ScooterHud.luau", tool)
script("Script", "ScooterServer", "src/scooter/ScooterServer.server.luau", tool)
script("LocalScript", "ScooterClient", "src/scooter/ScooterClient.client.luau", tool)
new("RemoteEvent", { Name = "SetTheme" }, tool)
new("RemoteEvent", { Name = "Horn" }, tool)

local body = new("Model", { Name = "Body" }, tool)
body:SetAttribute("DeckHeight", DECK_HEIGHT)
body:SetAttribute("WheelRadius", WHEEL_RADIUS)

-- Every part rides along with the character: no mass, no collisions, no touches.
local function passive(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function hub(name, cframe)
	local part = new("Part", {
		Name = name,
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = cframe,
		Transparency = 1,
		CastShadow = false,
	}, body)
	passive(part)
	return part
end

local function motor(name, part0, part1)
	return new("Motor6D", {
		Name = name,
		Part0 = part0,
		Part1 = part1,
		C0 = part0.CFrame:Inverse() * part1.CFrame,
		C1 = CFrame.new(),
	}, part0)
end

local root = hub("Root", CFrame.new(BASE))
body.PrimaryPart = root
-- Mount joins the scooter to the rider's HumanoidRootPart (Part0 is set when equipped).
new("Motor6D", { Name = "Mount", Part1 = root }, root)

-- Steering axis: along the column, from its bottom end to its top end.
local column = byName("Column")
local columnPart = column.part
local tubeRadius = columnPart.Size.Z / 2 -- the column is round; its depth is its diameter
local columnBottom = place(Vector3.new(
	columnPart.CFrame.Position.X + columnPart.Size.X / 2 - tubeRadius,
	columnPart.CFrame.Position.Y - columnPart.Size.Y / 2,
	columnPart.CFrame.Position.Z
), "tube")
local columnTop = place(Vector3.new(
	columnPart.CFrame.Position.X - columnPart.Size.X / 2 + tubeRadius,
	columnPart.CFrame.Position.Y + columnPart.Size.Y / 2,
	columnPart.CFrame.Position.Z
), "tube")
local steerAxis = (columnTop - columnBottom).Unit
local steerHub = hub("SteerHub", CFrame.fromMatrix(columnBottom, Vector3.new(1, 0, 0), steerAxis))
motor("Steer", root, steerHub)

local tires = {}
for _, item in found do
	if item.name == "Tire" then
		tires[item.group] = item
	end
end
local frontHub = hub("FrontHub", CFrame.new(tires.FrontWheel.cframe.Position))
local rearHub = hub("RearHub", CFrame.new(tires.RearWheel.cframe.Position))
motor("FrontSpin", steerHub, frontHub)
motor("RearSpin", root, rearHub)

local groups, hubs = {}, { Chassis = root, Steering = steerHub, FrontWheel = frontHub, RearWheel = rearHub }
for _, name in { "Chassis", "Steering", "FrontWheel", "RearWheel" } do
	groups[name] = new("Model", { Name = name }, body)
end

local function weld(part, group)
	local base = hubs[group]
	new("Weld", { Name = "Weld", Part0 = base, Part1 = part, C0 = base.CFrame:Inverse() * part.CFrame }, part)
end

local built = {}
for _, item in found do
	local part = item.part
	part.Name = item.name
	part.Size = item.size
	part.CFrame = item.cframe
	part:SetAttribute("Role", item.role)
	passive(part)
	part.Parent = groups[item.group]
	weld(part, item.group)
	built[item.group .. "/" .. item.name] = part
end

-- The deck's grip texture on the original is replaced by the Grip material.
local deck = built["Chassis/Deck"]
if roblox.Content then
	deck.TextureContent = roblox.Content.none
else
	deck.TextureID = ""
end

-- Headlight: a small lamp on the front of the column, turning with the bar.
local lampHeight = 0.85
local lampCenter = columnBottom:Lerp(columnTop, lampHeight)
local lamp = new("Part", {
	Name = "Headlamp",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.08, 0.24, 0.24),
	-- Cylinder axis (local X) points forward; tucked against the column.
	CFrame = CFrame.new(lampCenter + Vector3.new(0, 0, -(tubeRadius * SCALE + 0.03))) * TURN,
	Color = Color3.fromRGB(235, 235, 228),
	Material = Enum.Material.SmoothPlastic,
	Reflectance = 0.2,
}, groups.Steering)
passive(lamp)
lamp:SetAttribute("Role", "Lamp")
weld(lamp, "Steering")
new("SpotLight", {
	Name = "Beam",
	Face = Enum.NormalId.Right,
	Angle = 60,
	Range = 30,
	Brightness = 2,
	Color = Color3.fromRGB(255, 244, 214),
	Shadows = false,
	Enabled = false,
}, lamp)

-- Anchors the animator reads (in Root or SteerHub space). The standing feet
-- are placed by the animator itself (they differ between R6 and R15).
local function attachment(name, parent, position)
	return new("Attachment", { Name = name, CFrame = CFrame.new(position) }, parent)
end
local deckCenter = root.CFrame:PointToObjectSpace(deck.CFrame.Position)
attachment("Kick", root, Vector3.new(KICK_X, -DECK_HEIGHT, -0.1)) -- kick foot lands here...
attachment("KickEnd", root, Vector3.new(KICK_X, -DECK_HEIGHT, 0.9)) -- ...and pushes back to here
attachment("LeftGrip", steerHub, steerHub.CFrame:PointToObjectSpace(built["Steering/GripLeft"].CFrame.Position))
attachment("RightGrip", steerHub, steerHub.CFrame:PointToObjectSpace(built["Steering/GripRight"].CFrame.Position))

local glow = attachment("GlowAttachment", root, Vector3.new(0, -DECK_HEIGHT * 0.55, deckCenter.Z))
new("PointLight", {
	Name = "Underglow",
	Range = 8,
	Brightness = 2,
	Shadows = false,
	Enabled = false,
}, glow)

---------------------------------------------------------------------------
-- Default theme, with the same code the game runs
---------------------------------------------------------------------------

local env = setmetatable({
	Enum = Enum,
	Color3 = Color3,
	CFrame = CFrame,
	Vector3 = Vector3,
	Vector2 = roblox.Vector2,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Font = roblox.Font,
	Instance = Instance,
}, { __index = getfenv(1) })
local function module(path)
	return luau.load(fs.readFile(path), { debugName = path, environment = env })()
end
local settings = module("src/scooter/Settings.luau")
local Shared = module("src/scooter/ScooterShared.luau")
for _, name in settings.ThemeOrder do
	assert(settings.Themes[name], `ThemeOrder lists unknown theme {name}`)
end
local themeName = Shared.applyTheme(body, settings, settings.Theme)

---------------------------------------------------------------------------
-- Animator (StarterPlayerScripts)
---------------------------------------------------------------------------

local animator = script("LocalScript", "ScooterAnimator", "src/scooter/ScooterAnimator.client.luau", nil)
script("ModuleScript", "Pose", "src/scooter/Pose.luau", animator)
script("ModuleScript", "Motion", "src/scooter/Motion.luau", animator)

---------------------------------------------------------------------------
-- Write
---------------------------------------------------------------------------

local function count(instance)
	return #instance:GetDescendants() + 1
end

fs.writeDir("StarterPack")
local toolFile = rbxm.legacyContent(roblox.serializeModel({ tool }))
local types = rbxm.propertyTypes(toolFile, "MeshPart")
assert(types.MeshId == 0x01 and not types.MeshContent, "MeshPart.MeshId must be saved as a string")
fs.writeFile(TOOL_OUTPUT, toolFile)
print(`Wrote {TOOL_OUTPUT} ({count(tool)} instances, theme {themeName})`)

fs.writeDir("StarterPlayerScripts")
fs.writeFile(ANIMATOR_OUTPUT, roblox.serializeModel({ animator }, true))
print(`Wrote {ANIMATOR_OUTPUT} ({count(animator)} instances)`)

print(string.format("deck %.2f studs above the ground, wheels %.2f across, grips %.2f above the deck",
	DECK_HEIGHT, WHEEL_RADIUS * 2, (built["Steering/GripLeft"].CFrame.Position.Y - root.CFrame.Position.Y)))

-- Geometry for the pose test and the preview renderer.
if table.find(process.args, "--dump") then
	local parts = {}
	for _, part in body:GetDescendants() do
		if part:IsA("BasePart") then
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
			local p = part.CFrame.Position
			table.insert(parts, {
				name = part.Name,
				group = part.Parent.Name,
				role = part:GetAttribute("Role"),
				shape = if part:IsA("Part") then part.Shape.Name else "Mesh",
				size = { part.Size.X, part.Size.Y, part.Size.Z },
				cframe = { p.X, p.Y, p.Z, r00, r01, r02, r10, r11, r12, r20, r21, r22 },
				transparency = part.Transparency,
			})
		end
	end
	local themes = {}
	for name, theme in settings.Themes do
		local roles = {}
		for role, look in theme do
			if type(look) == "table" then
				roles[role] = { color = { look.Color.R, look.Color.G, look.Color.B }, material = look.Material.Name,
					reflectance = look.Reflectance }
			end
		end
		themes[name] = roles
	end
	-- HUD for tools/preview/render.cjs, as on a PC and on a phone. The jump
	-- button and hotbar slot are stand-ins for Roblox's own, for the preview only.
	local Hud = module("src/scooter/ScooterHud.luau")
	local dump = require("./lib/dump")
	local UDim2, Vector2 = roblox.UDim2, roblox.Vector2
	local theme = settings.Themes[settings.Theme]
	local function stand(className, props, parent)
		local item = new(className, props, parent)
		if className ~= "UICorner" and className ~= "UIStroke" then
			new("UICorner", { CornerRadius = roblox.UDim.new(if props.Name == "Slot" then 0 else 1, if props.Name == "Slot" then 8 else 0) }, item)
		end
		return item
	end
	for _, device in {
		{ file = "build/scooter-hud-pc.json", keyboard = true, touchOnly = false, viewport = Vector2.new(1280, 720) },
		{ file = "build/scooter-hud-phone.json", keyboard = false, touchOnly = true, viewport = Vector2.new(844, 390) },
	} do
		local hud = Hud.new(settings, device, settings.HornSound ~= "")
		hud:setTheme(string.upper(settings.Theme), theme.Light)
		hud:setSpeed(24)
		local slot = stand("TextLabel", {
			Name = "Slot", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.fromOffset(60, 60), BackgroundColor3 = Color3.fromRGB(30, 34, 44), BackgroundTransparency = 0.3,
			Text = "Scooter", TextSize = 11, TextColor3 = Color3.new(1, 1, 1),
			FontFace = roblox.Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold),
		}, hud.gui)
		new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.3 }, slot)
		if device.touchOnly then
			stand("TextLabel", {
				Name = "JumpButton (Roblox)", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(1, -95, 1, -90),
				Size = UDim2.fromOffset(70, 70), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.75,
				Text = "JUMP", TextSize = 11, TextColor3 = Color3.new(1, 1, 1),
				FontFace = roblox.Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
			}, hud.gui)
			stand("Frame", {
				Name = "Thumbstick (Roblox)", Position = UDim2.new(0, 60, 1, -150), Size = UDim2.fromOffset(110, 110),
				BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8,
			}, hud.gui)
		end
		fs.writeFile(device.file, serde.encode("json", dump(hud.gui)))
		print(`Wrote {device.file}`)
	end

	fs.writeDir("build")
	fs.writeFile("build/scooter.json", serde.encode("json", {
		parts = parts,
		themes = themes,
		themeOrder = settings.ThemeOrder,
		deckHeight = DECK_HEIGHT,
	}))
	print("Wrote build/scooter.json")
end
