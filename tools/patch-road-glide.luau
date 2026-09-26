--[[
	Cleans up and fixes the uploaded NCT: M bike "HD RG ST CVO" and writes
	ServerStorage/Vehicles.rbxm (a "Vehicles" folder containing the bike).

	  lune run tools/patch-road-glide.luau
	  lune run tools/patch-road-glide.luau -- --tree   (also dumps the touch buttons for the preview)

	Every source edit must match exactly once, otherwise the script stops, so
	a different version of the model can't be half-patched silently.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local dump = require("./lib/dump")

local Instance, Enum = roblox.Instance, roblox.Enum
local UDim, UDim2, Vector2, Color3 = roblox.UDim, roblox.UDim2, roblox.Vector2, roblox.Color3
local ColorSequence, NumberSequence, Font = roblox.ColorSequence, roblox.NumberSequence, roblox.Font

local SOURCE = "vehicles/original/HD_Road_Glide_ST_CVO.rbxm"
local OUTPUT = "ServerStorage/Vehicles.rbxm"
local BIKE_NAME = "HD Road Glide ST CVO"

local bike = roblox.deserializeModel(fs.readFile(SOURCE))[1]
bike.Name = BIKE_NAME

local changes = {}
local function log(message)
	table.insert(changes, message)
end

local function find(path)
	local node = bike
	for name in path:gmatch("[^/]+") do
		node = node:FindFirstChild(name)
		assert(node, `missing {path}`)
	end
	return node
end

local function remove(path, why)
	find(path):Destroy()
	log(`removed {path}: {why}`)
end

local function replace(script, old, new, why)
	local source = script.Source
	local first = source:find(old, 1, true)
	assert(first, `{script:GetFullName()}: text not found: {old}`)
	assert(not source:find(old, first + 1, true), `{script:GetFullName()}: text found more than once: {old}`)
	script.Source = source:sub(1, first - 1) .. new .. source:sub(first + #old)
	log(`{script:GetFullName()}: {why}`)
end

---------------------------------------------------------------------------
-- 1. Junk and broken scripts
---------------------------------------------------------------------------

remove("DeleteOnChat", "kill switch — destroyed the bike when user 'rezarezarezarezareza' chatted \"RG\" (and its Fix script re-enabled it)")
remove("DriveSeat/LocalScript", "LocalScripts don't run inside a vehicle; it also used an undefined variable")
remove("DriveSeat/AntiCollide", "deprecated PhysicsService API, errors when a second bike spawns (collisions are set by the spawner)")
remove("DriveSeat/AntiCollideCar", "deprecated PhysicsService API (collisions are set by the spawner)")
remove("DriveSeat/Filter", "car radio remote for parts this bike doesn't have; any player could call it")
remove("Tuner/Plugins/Kickstand", "the bike has no Body.Kickstand part, so all three kickstand scripts errored")

-- Lights GUI giver: rewrite (original errored on missing values and was
-- re-enabled by a "TheFix" script).
local giver = find("DriveSeat/Gui Giver")
giver.Name = "LightsGuiGiver"
giver.Source = fs.readFile("src/vehicle/LightsGuiGiver.server.luau")
giver.Disabled = false
giver:FindFirstChild("TheFix"):Destroy()
log("DriveSeat/Gui Giver: rewritten as LightsGuiGiver (gives the lights controls to the rider)")

replace(find("DriveSeat/horn"),
	"\t\t\tscript.Parent.Start.Pitch = 1\n\t\t\tscript.Parent.Start:Play()",
	"\t\t\tlocal start = script.Parent:FindFirstChild(\"Start\")\n\t\t\tif start then\n\t\t\t\tstart.Pitch = 1\n\t\t\t\tstart:Play()\n\t\t\tend",
	"only play the start sound if the bike has one (it doesn't, which errored on every ride)")

---------------------------------------------------------------------------
-- 2. Chassis settings for normal riding
---------------------------------------------------------------------------

local tuner = find("Tuner")
replace(tuner, "Tune.AutoUpdate\t= true", "Tune.AutoUpdate\t= false",
	"AutoUpdate off — it downloaded a replacement Drive script from an external asset at runtime")
replace(tuner, "Tune.AutoStart\t= false", "Tune.AutoStart\t= true",
	"AutoStart on — engine runs as soon as you sit (F still toggles it)")
replace(tuner, "Tune.Stall\t\t\t= true", "Tune.Stall\t\t\t= false",
	"stalling off")
replace(tuner, 'Tune.TransModes\t\t= {"DCT","Manual"}', 'Tune.TransModes\t\t= {"Auto","DCT","Manual"}',
	"automatic gearbox by default (M switches to DCT/Manual)")

replace(find("Tuner/Initialize"),
	'local JS = game:GetService("JointsService")',
	'local JS = Instance.new("Folder")\nJS.Name = "Welds"\nJS.Parent = script.Parent.Parent',
	"chassis welds go into a Welds folder inside the bike instead of the deprecated JointsService")

---------------------------------------------------------------------------
-- 3. Rider body (R6 / R15) and remote security
---------------------------------------------------------------------------

local animsPlugin = find("Tuner/Plugins/Anims")
replace(animsPlugin, "\thandler:FireServer(\"RemovePlayer\",C,child) \n", "",
	"stop asking the server to restore the body (the server does that itself now)")
replace(animsPlugin, "handler:FireServer(\"CreatePlayer\",C)\n", "",
	"stop asking the server to hide the body (the server does that itself now)")

local feAnims = find("Tuner/Plugins/Anims/Anims/FEAnims")
feAnims.Name = "RiderVisuals"
feAnims.Source = fs.readFile("src/vehicle/RiderVisuals.server.luau")
log("FEAnims: rewritten as RiderVisuals (server-side, driven by DriveSeat.Occupant, always restores the rider)")

local GUARD = [[
-- [Patched] Only the current rider (or whoever just got off, for a few
-- seconds) may use this remote, and only for functions that exist.
local __Players = game:GetService("Players")
local __seat = script:FindFirstAncestorWhichIsA("Model"):WaitForChild("DriveSeat")
local __rider, __leftAt = nil, 0
__seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local occupant = __seat.Occupant
	local rider = occupant and __Players:GetPlayerFromCharacter(occupant.Parent)
	if rider then
		__rider = rider
	else
		__leftAt = os.clock()
	end
end)
local function __allowed(caller)
	local occupant = __seat.Occupant
	if occupant then
		return __Players:GetPlayerFromCharacter(occupant.Parent) == caller
	end
	return caller == __rider and os.clock() - __leftAt < 5
end

script.Parent.OnServerEvent:Connect(function(pl, Fnc, ...)
	if not __allowed(pl) or type(Fnc) ~= "string" or type(F[Fnc]) ~= "function" then
		return
	end
%s	F[Fnc](...)
end)]]

replace(find("DriveSeat/FE_Lights/Handler"),
	"script.Parent.OnServerEvent:connect(function(pl,Fnc,...)\n\tplayer = pl\n\tF[Fnc](...)\nend)",
	GUARD:format("\tplayer = pl\n"),
	"lights remote: rider only")

replace(find("Tuner/Plugins/EPICLIGHTS_V4/LIGHTS/Handler"),
	"script.Parent.OnServerEvent:Connect(function(plr, Fnc, ...)\n\tF[Fnc](...)\nend)",
	GUARD:format(""),
	"light effects remote: rider only")

local sounds = find("Tuner/Plugins/AC6_Sounds/AC6_Sound/Handler")
replace(sounds,
	"script.Parent.OnServerEvent:connect(function(pl,Fnc,...) F[Fnc](...) end)",
	GUARD:format(""),
	"engine sound remote: rider only")
replace(sounds, "local F = {}\n",
	"local F = {}\n\nlocal function isOwnSound(sound)\n\treturn typeof(sound) == \"Instance\" and sound:IsA(\"Sound\") and sound:IsDescendantOf(car)\nend\n",
	"engine sound remote: only this bike's sounds")
replace(sounds, "F.updateSounds = function(tbl)\n\tfor _,i in pairs(tbl) do",
	"F.updateSounds = function(tbl)\n\tif type(tbl) ~= \"table\" then return end\n\tlocal valid = {}\n\tfor _,i in pairs(tbl) do\n\t\tif type(i) == \"table\" and isOwnSound(i[1]) and type(i[2]) == \"number\" and type(i[3]) == \"number\" then\n\t\t\ttable.insert(valid, i)\n\t\tend\n\tend\n\ttbl = valid\n\tfor _,i in pairs(tbl) do",
	"engine sound remote: validate sound updates")
replace(sounds, "F.playSound = function(snd) snd:Play() end",
	"F.playSound = function(snd) if isOwnSound(snd) then snd:Play() end end", "engine sound remote: validate play")
replace(sounds, "F.stopSound = function(snd) snd:Stop() end",
	"F.stopSound = function(snd) if isOwnSound(snd) then snd:Stop() end end", "engine sound remote: validate stop")

local smoke = find("Tuner/Plugins/Smoke [FE+]/Smoke_FE/Handler")
replace(smoke, "\t\tif GetPlayer.Name == pl.Name then", "\t\tif GetPlayer == pl then",
	"smoke remote: compare players, not names (an NPC rider made it error)")

---------------------------------------------------------------------------
-- 4. Touch controls. Drive waits for Interface.Buttons on touch devices and
--    the model didn't have it, so the engine loop never started on phones.
---------------------------------------------------------------------------

local interface = find("Tuner/Interface")
local FONT = "rbxasset://fonts/families/Montserrat.json"

local function new(className, parent, props)
	local inst = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local buttons = new("Frame", interface, {
	Name = "Buttons",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 10,
})

local function touchButton(name, size, anchor, position, style)
	local button = new("TextButton", buttons, {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = style.color or Color3.fromRGB(17, 20, 27),
		BackgroundTransparency = style.transparency or 0.3,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
		ZIndex = 10,
	})
	new("UIAspectRatioConstraint", button, {
		AspectRatio = 1,
		AspectType = Enum.AspectType.ScaleWithParentSize,
		DominantAxis = Enum.DominantAxis.Width,
	})
	new("UICorner", button, { CornerRadius = UDim.new(0.5, 0) })
	new("UIStroke", button, {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = style.stroke or Color3.new(1, 1, 1),
		Transparency = 0.7,
		Thickness = 1.5,
	})
	if style.gradient then
		new("UIGradient", button, { Color = ColorSequence.new(style.gradient[1], style.gradient[2]), Rotation = 45 })
	end
	if style.text then
		new("TextLabel", button, {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, style.textHeight or 0.26),
			BackgroundTransparency = 1,
			Text = style.text,
			TextColor3 = style.textColor or Color3.fromRGB(245, 246, 248),
			TextScaled = true,
			FontFace = Font.new(FONT, Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal),
			ZIndex = 11,
		})
	end
	return button
end

-- Chevron drawn from two rounded bars, so it doesn't depend on font glyphs.
local function chevron(button, pointsLeft)
	local tipX = pointsLeft and 0.38 or 0.62
	local midX = pointsLeft and 0.49 or 0.51
	for i, y in { 0.39, 0.61 } do
		local bar = new("Frame", button, {
			Name = "Chevron" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(midX, y),
			Size = UDim2.fromScale(0.31, 0.08),
			BackgroundColor3 = Color3.fromRGB(245, 246, 248),
			BorderSizePixel = 0,
			Rotation = ((i == 1) == pointsLeft) and -45 or 45,
			ZIndex = 11,
		})
		new("UICorner", bar, { CornerRadius = UDim.new(0.5, 0) })
	end
	return tipX
end

-- "+" / "-" drawn from bars too (the "-" glyph is tiny next to "+").
local function plusMinus(button, plus)
	for i, rotation in (if plus then { 0, 90 } else { 0 }) do
		local bar = new("Frame", button, {
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.36, 0.09),
			BackgroundColor3 = Color3.fromRGB(245, 246, 248),
			BorderSizePixel = 0,
			Rotation = rotation,
			ZIndex = 11,
		})
		new("UICorner", bar, { CornerRadius = UDim.new(0.5, 0) })
	end
end

local AMBER, ORANGE = Color3.fromRGB(255, 190, 56), Color3.fromRGB(255, 128, 31)
local BOTTOM, UPPER = 0.95, 0.68

chevron(touchButton("Left", 0.085, Vector2.new(0, 1), UDim2.fromScale(0.03, BOTTOM), {}), true)
chevron(touchButton("Right", 0.085, Vector2.new(0, 1), UDim2.fromScale(0.13, BOTTOM), {}), false)
touchButton("Exit", 0.06, Vector2.new(0, 1), UDim2.fromScale(0.03, UPPER), { text = "EXIT", textHeight = 0.24 })

touchButton("Gas", 0.095, Vector2.new(1, 1), UDim2.fromScale(0.97, BOTTOM), {
	color = Color3.new(1, 1, 1), transparency = 0, gradient = { AMBER, ORANGE },
	stroke = AMBER, text = "GAS", textColor = Color3.fromRGB(28, 19, 4),
})
touchButton("Brake", 0.085, Vector2.new(1, 1), UDim2.fromScale(0.86, BOTTOM), {
	color = Color3.fromRGB(255, 85, 102), transparency = 0.2, stroke = Color3.fromRGB(255, 85, 102), text = "BRAKE", textHeight = 0.22,
})
plusMinus(touchButton("Upshift", 0.055, Vector2.new(1, 1), UDim2.fromScale(0.97, UPPER), {}), true)
plusMinus(touchButton("Downshift", 0.055, Vector2.new(1, 1), UDim2.fromScale(0.903, UPPER), {}), false)
touchButton("Handbrake", 0.055, Vector2.new(1, 1), UDim2.fromScale(0.836, UPPER), { text = "P", textHeight = 0.42 })

new("LocalScript", interface, {
	Name = "MobileControls",
	Source = fs.readFile("src/vehicle/MobileControls.client.luau"),
})
log("Tuner/Interface: added touch Buttons (Left/Right/Gas/Brake/Upshift/Downshift/Handbrake/Exit) + MobileControls")

---------------------------------------------------------------------------
-- Write
---------------------------------------------------------------------------

local folder = Instance.new("Folder")
folder.Name = "Vehicles"
bike.Parent = folder

fs.writeDir("ServerStorage")
fs.writeFile(OUTPUT, roblox.serializeModel({ folder }))
for _, line in changes do
	print("  - " .. line)
end
print(`Wrote {OUTPUT} ({#changes} changes)`)

if table.find(process.args, "--tree") then
	-- Preview: the buttons frame as if on a touch device.
	local screen = Instance.new("ScreenGui")
	screen.Name = "TouchPreview"
	local copy = buttons:Clone()
	copy.Visible = true
	copy.Parent = screen
	fs.writeDir("build")
	fs.writeFile("build/touch-tree.json", serde.encode("json", dump(screen), true))
	print("Wrote build/touch-tree.json")
end
