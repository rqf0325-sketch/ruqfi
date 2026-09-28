--[[
	Scooter — animator (StarterPlayer > StarterPlayerScripts > ScooterAnimator)

	Animates every player riding a scooter, on this client: the rider's
	body (Pose), the scooter's steering, wheels, lean and tricks (Motion),
	the lights and the sounds. No uploaded animations are needed.

	Motor6D.Transform doesn't replicate, so every client animates everyone
	from what does replicate (position, velocity, humanoid state). Written in
	PreSimulation, after Roblox's own animations, so it replaces the walk
	animation while riding and hands the body back as soon as it stops.

	Also plays other riders' horns (the tool's "Honk" attribute, set by
	ScooterServer; the rider's own client plays theirs itself).

	Cost: the body pose is only worked out for riders on screen and within
	CULL_DISTANCE (plus this player's own). The rest still get the cheap
	part: wheels, steering, lights and sounds.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Motion = require(script:WaitForChild("Motion"))
local Pose = require(script:WaitForChild("Pose"))

local CULL_DISTANCE = 250 -- riders further away keep the scooter but not the pose
local SCREEN_MARGIN = 0.25 -- share of the screen size a rider may be outside it and still get posed

local localPlayer = Players.LocalPlayer
local IDENTITY = CFrame.new()

local OFF_STATES = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Physics] = true,
}
local AIR_STATES = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local riders = {} -- character -> rider

local function scooterOf(character)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("Scooter") then
			return child
		end
	end
	return nil
end

local function motor(parent, name)
	local joint = parent and parent:FindFirstChild(name)
	return if joint and joint:IsA("Motor6D") then joint else nil
end

local function position(parent, name)
	local attachment = parent:FindFirstChild(name)
	return if attachment and attachment:IsA("Attachment") then attachment.Position else nil
end

local function makeSound(parent, id, looped, volume, reach)
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = looped
	sound.Volume = volume
	sound.RollOffMaxDistance = reach or 80
	sound.Parent = parent
	if looped then
		sound:Play()
	end
	return sound
end

-- The scooter's measurements, as it is scaled right now (joints and
-- attachments scale with Model:ScaleTo, attributes don't).
local function readScooter(body)
	local root = body:FindFirstChild("Root")
	local steerHub = body:FindFirstChild("SteerHub")
	local steer, rearSpin = motor(root, "Steer"), motor(root, "RearSpin")
	local frontSpin = motor(steerHub, "FrontSpin")
	if not (steer and rearSpin and frontSpin) then
		return nil
	end
	local anchors, grips = {}, {}
	for _, name in { "Kick", "KickEnd" } do
		anchors[name] = position(root, name)
		if not anchors[name] then
			return nil
		end
	end
	grips.Left, grips.Right = position(steerHub, "LeftGrip"), position(steerHub, "RightGrip")
	if not (grips.Left and grips.Right) then
		return nil
	end
	local scale = body:GetScale()
	return {
		scale = scale,
		deckHeight = (body:GetAttribute("DeckHeight") or 0.5) * scale,
		wheelRadius = (body:GetAttribute("WheelRadius") or 0.34) * scale,
		wheelbase = ((steer.C0 * steer.C1:Inverse() * frontSpin.C0).Position - rearSpin.C0.Position).Magnitude,
		steerC0 = steer.C0,
		steerC1 = steer.C1,
		anchors = anchors,
		grips = grips,
	}
end

local function start(character, tool)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	local body = tool:FindFirstChild("Body")
	local root = body and body:FindFirstChild("Root")
	local steerHub = body and body:FindFirstChild("SteerHub")
	if not (rootPart and root and steerHub) then
		return nil
	end
	local mount, steer = motor(root, "Mount"), motor(root, "Steer")
	local frontSpin, rearSpin = motor(steerHub, "FrontSpin"), motor(root, "RearSpin")
	local scooter = readScooter(body)
	if not (mount and scooter) then
		return nil
	end

	local settingsModule = tool:FindFirstChild("Settings")
	local ok, settings = pcall(require, settingsModule)
	if not ok or type(settings) ~= "table" then
		settings = {}
	end

	local rig = Pose.rig(character)
	local parts = {}
	for _, part in body:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	local lamp = body:FindFirstChild("Headlamp", true)

	local rider = {
		character = character,
		tool = tool,
		body = body,
		humanoid = humanoid,
		rootPart = rootPart,
		settings = settings,
		rig = rig,
		motion = Motion.new(scooter, settings, rig and rig.kind),
		mount = mount,
		steer = steer,
		frontSpin = frontSpin,
		rearSpin = rearSpin,
		parts = parts,
		lamp = lamp,
		beam = lamp and lamp:FindFirstChildWhichIsA("SpotLight"),
		underglow = body:FindFirstChild("Underglow", true),
		hidden = false,
		lights = nil,
		isLocal = character == localPlayer.Character,
		honk = tool:GetAttribute("Honk"),
		pose = {},
	}
	if settings.Sounds ~= false then
		rider.windSound = makeSound(root, settings.WindSound, true, 0)
		rider.rollSound = makeSound(root, settings.RollSound, true, 0)
		rider.kickSound = makeSound(root, settings.KickSound, false, 0.35)
	end
	if not rider.isLocal then
		rider.hornSound = makeSound(root, settings.HornSound, false, settings.HornVolume or 1, 150)
	end
	return rider
end

local function setHidden(rider, hidden)
	if rider.hidden == hidden then
		return
	end
	rider.hidden = hidden
	for _, part in rider.parts do
		part.LocalTransparencyModifier = if hidden then 1 else 0
	end
	rider.lights = nil -- re-check
end

local function lightsWanted(rider)
	if rider.hidden then
		return false
	end
	local mode = rider.settings.Lights
	if mode == nil or mode == "Auto" then
		local time = Lighting.ClockTime
		return time < 6.3 or time > 17.7
	end
	return mode == true
end

local function updateLights(rider)
	local on = lightsWanted(rider)
	local glow = on and rider.settings.Underglow ~= false and rider.body:GetAttribute("HasUnderglow") ~= false
	local key = (if on then 1 else 0) + (if glow then 2 else 0)
	if rider.lights == key then
		return
	end
	rider.lights = key
	if rider.beam then
		rider.beam.Enabled = on
	end
	if rider.lamp then
		rider.lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	if rider.underglow then
		rider.underglow.Enabled = glow
	end
end

-- The default footstep loop would keep playing while rolling.
local function muteFootsteps(rider, muted)
	local running = rider.rootPart:FindFirstChild("Running")
	if not (running and running:IsA("Sound")) then
		return
	end
	if muted then
		if rider.footsteps == nil then
			rider.footsteps = { sound = running, volume = running.Volume }
		end
		running.Volume = 0
	elseif rider.footsteps then
		rider.footsteps.sound.Volume = rider.footsteps.volume
		rider.footsteps = nil
	end
end

local function quiet(rider)
	for _, sound in { rider.windSound, rider.rollSound } do
		sound.Volume = 0
	end
end

local function finish(rider)
	muteFootsteps(rider, false)
	for _, sound in { rider.windSound, rider.rollSound, rider.kickSound, rider.hornSound } do
		sound:Destroy()
	end
	setHidden(rider, false)
	for _, joint in { rider.mount, rider.steer, rider.frontSpin, rider.rearSpin } do
		joint.Transform = IDENTITY
	end
	if rider.beam then
		rider.beam.Enabled = false
	end
	if rider.underglow then
		rider.underglow.Enabled = false
	end
end

-- Worth working out the pose: on screen (with a margin) and not too far away.
local function inView(camera, point)
	if not camera then
		return true
	end
	local offset = camera.CFrame.Position - point
	if offset.Magnitude > CULL_DISTANCE then
		return false
	end
	if offset.Magnitude < 12 then
		return true
	end
	local onScreen = camera:WorldToViewportPoint(point)
	local size = camera.ViewportSize
	local margin = SCREEN_MARGIN * math.max(size.X, size.Y)
	return onScreen.Z > 0 and onScreen.X > -margin and onScreen.X < size.X + margin
		and onScreen.Y > -margin and onScreen.Y < size.Y + margin
end

local function update(rider, dt, camera)
	local humanoid, rootPart = rider.humanoid, rider.rootPart
	if rider.mount.Part0 ~= rootPart then
		return -- equipped, but not joined to the rider yet
	end

	local honk = rider.tool:GetAttribute("Honk")
	if honk ~= rider.honk then
		rider.honk = honk
		if rider.hornSound then
			rider.hornSound.TimePosition = 0
			rider.hornSound:Play()
		end
	end

	-- Rescaled for a new rider size (the server's ScaleTo can arrive after this rider started).
	if math.abs(rider.body:GetScale() - rider.motion.scooter.scale) > 1e-3 then
		local scooter = readScooter(rider.body)
		if scooter then
			rider.motion.scooter = scooter
		end
	end

	local state = humanoid:GetState()
	local off = OFF_STATES[state] or humanoid.Sit
	setHidden(rider, off)
	updateLights(rider)
	if off then
		quiet(rider)
		muteFootsteps(rider, false)
		return
	end
	muteFootsteps(rider, true)

	local result = rider.motion:update(dt, {
		rootCFrame = rootPart.CFrame,
		velocity = rootPart.AssemblyLinearVelocity,
		airborne = AIR_STATES[state] == true,
		gravity = workspace.Gravity,
		mountC0 = rider.mount.C0,
	})
	rider.mount.Transform = result.mount
	rider.steer.Transform = result.steer
	rider.frontSpin.Transform = result.wheel
	rider.rearSpin.Transform = result.wheel

	-- Avatar changes (e.g. a new HumanoidDescription) rebuild the joints.
	if rider.rig and not rider.rig.root.Parent then
		rider.rig = Pose.rig(rider.character)
	end
	if rider.rig and (rider.isLocal or inView(camera, rootPart.Position)) then
		for joint, transform in Pose.solve(rider.rig, rootPart.CFrame, result.targets, rider.pose) do
			joint.Transform = transform
		end
	end

	local speed = result.speed
	local grounded = rider.motion.grounded
	if rider.windSound then
		rider.windSound.Volume = math.clamp((speed - 10) / 25, 0, 1) * 0.3
		rider.windSound.PlaybackSpeed = 0.8 + speed / 80
	end
	if rider.rollSound then
		rider.rollSound.Volume = if grounded then math.clamp(speed / 20, 0, 1) * 0.5 else 0
		rider.rollSound.PlaybackSpeed = 0.7 + speed / 60
	end
	if rider.kickSound and (result.kicked or result.landed) then
		rider.kickSound.PlaybackSpeed = if result.landed then 0.8 else 1 + (math.random() - 0.5) * 0.15
		rider.kickSound:Play()
	end
end

RunService.PreSimulation:Connect(function(dt)
	local camera = workspace.CurrentCamera
	local seen = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local tool = character and scooterOf(character)
		if not tool then
			continue
		end
		local rider = riders[character]
		if rider and rider.tool ~= tool then
			finish(rider)
			rider = nil
		end
		if not rider then
			rider = start(character, tool)
			riders[character] = rider
		end
		if rider and not rider.broken then
			seen[character] = true
			local ok, err = pcall(update, rider, dt, camera)
			if not ok then
				rider.broken = true
				warn(`ScooterAnimator: stopped animating {character.Name}: {err}`)
			end
		elseif rider then
			seen[character] = true
		end
	end
	for character, rider in riders do
		if not seen[character] then
			finish(rider)
			riders[character] = nil
		end
	end
end)
