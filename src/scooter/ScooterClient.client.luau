--[[
	Scooter — rider's controls (Tool > ScooterClient)

	While the tool is equipped:
	  * the scooter goes under the feet right away (the server does it for
	    everyone else) and the rider is lifted by the deck's height
	  * speed builds up while a direction is held (up to MaxSpeed), the
	    scooter keeps rolling when it's let go, pulling the other way brakes,
	    and turning at speed is gradual; all through Humanoid:Move, so it
	    works the same with keyboard, thumbstick and gamepad
	  * a small HUD shows the speed and a button (or T) to change colour
	  * a horn button (or H): the rider hears it at once, everyone else
	    through the server (ScooterServer -> ScooterAnimator)
	  * the scooter is sized to the rider (Settings.FitRiderSize)
	Everything is put back when the tool is unequipped, and the tool is put
	away when the rider sits down (e.g. on a bike) or swims.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local tool = script.Parent
local settings = require(tool:WaitForChild("Settings"))
local Shared = require(tool:WaitForChild("ScooterShared"))
local Hud = require(tool:WaitForChild("ScooterHud"))
local body = tool:WaitForChild("Body")
local root = body:WaitForChild("Root")
local mount = root:WaitForChild("Mount")
local setTheme = tool:WaitForChild("SetTheme")
local hornRemote = tool:WaitForChild("Horn")

local STEP = "ScooterControl"
local STOP_SPEED = 3

local ride = nil

-- This player's colour, shown at once (the server paints it for everyone
-- the first time the scooter is equipped).
Shared.applyTheme(body, settings,
	if settings.PlayersCanChangeTheme then player:GetAttribute("ScooterTheme") or settings.Theme else settings.Theme)

-- The rider's own horn, local so it plays without waiting for the server.
local hornSound = nil
if type(settings.HornSound) == "string" and settings.HornSound ~= "" then
	hornSound = Instance.new("Sound")
	hornSound.Name = "HornLocal"
	hornSound.SoundId = settings.HornSound
	hornSound.Volume = settings.HornVolume or 1
	hornSound.RollOffMaxDistance = 150
	hornSound.Parent = root
end

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Turns horizontal unit vector `from` towards `to` by at most `maxAngle` radians.
local function turnTowards(from, to, maxAngle)
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxAngle then
		return to
	end
	local sign = if from:Cross(to).Y >= 0 then 1 else -1
	return CFrame.Angles(0, sign * maxAngle, 0):VectorToWorldSpace(from)
end

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------

local function themeColor()
	local theme = Shared.theme(settings, body:GetAttribute("Theme"))
	return theme.Light or (theme.Accent and theme.Accent.Color) or Color3.new(1, 1, 1)
end

local function showTheme()
	if ride and ride.hud then
		ride.hud:setTheme(string.upper(body:GetAttribute("Theme") or ""), themeColor())
	end
end

local lastHonk = 0
local function honk()
	if not ride or not hornSound or os.clock() - lastHonk < (settings.HornCooldown or 0) then
		return
	end
	lastHonk = os.clock()
	hornSound.TimePosition = 0
	hornSound:Play()
	hornRemote:FireServer()
	if ride.hud then
		ride.hud:pulseHorn()
	end
end

local function nextTheme()
	if not settings.PlayersCanChangeTheme then
		return
	end
	local order = settings.ThemeOrder
	local index = table.find(order, body:GetAttribute("Theme")) or 0
	local name = order[index % #order + 1]
	Shared.applyTheme(body, settings, name)
	setTheme:FireServer(name)
	showTheme()
end

---------------------------------------------------------------------------
-- Riding
---------------------------------------------------------------------------

local function step(dt)
	local r = ride
	if not r then
		return
	end
	local humanoid, rootPart = r.humanoid, r.rootPart
	if humanoid.Health <= 0 or not rootPart:IsDescendantOf(workspace) then
		return
	end
	local velocity = rootPart.AssemblyLinearVelocity
	local actual = flat(velocity).Magnitude
	if r.hud then
		r.hud:setSpeed(actual)
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Climbing then
		r.speed = 0
		humanoid.WalkSpeed = r.walkSpeed
		return
	end

	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local input = flat(humanoid.MoveDirection)
	if grounded then
		-- Don't keep speed that isn't there (a wall, a steep slope).
		r.speed = math.min(r.speed, actual + 8)
	end

	if input.Magnitude > 0.1 then
		local want = input.Unit
		local braking = false
		if r.speed <= settings.StartSpeed then
			r.direction = want
		elseif r.direction:Dot(want) < -0.3 then
			braking = true
			r.speed = math.max(0, r.speed - settings.BrakeForce * dt)
		else
			local t = math.clamp(r.speed / settings.MaxSpeed, 0, 1)
			local rate = settings.TurnSpeed + (settings.TurnSpeedAtMax - settings.TurnSpeed) * t
			r.direction = turnTowards(r.direction, want, rate * dt * (if grounded then 1 else 0.5))
		end
		if grounded and not braking then
			r.speed = math.min(settings.MaxSpeed, math.max(r.speed, settings.StartSpeed) + settings.Acceleration * dt)
		end
	elseif not settings.Coast then
		r.speed = 0
	elseif grounded then
		r.speed = math.max(0, r.speed - settings.CoastFriction * dt)
		if r.speed < STOP_SPEED then
			r.speed = 0
		end
	end

	if r.speed > 0 then
		humanoid.WalkSpeed = r.speed
		humanoid:Move(r.direction, false) -- after the control script's Move this frame
	else
		humanoid.WalkSpeed = settings.StartSpeed
	end
end

local function stopRiding()
	local r = ride
	if not r then
		return
	end
	ride = nil
	RunService:UnbindFromRenderStep(STEP)
	for _, connection in r.connections do
		connection:Disconnect()
	end
	if r.hud then
		r.hud:destroy()
	end
	local humanoid = r.humanoid
	if humanoid.Parent then
		humanoid.WalkSpeed = r.walkSpeed
		humanoid.HipHeight = r.hipHeight
		humanoid.JumpPower = r.jumpPower
		humanoid.JumpHeight = r.jumpHeight
	end
	if mount.Part0 == r.rootPart then
		mount.Part0 = nil
	end
end

local function startRiding()
	stopRiding()
	local character = tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if not rootPart or humanoid.Health <= 0 then
		return
	end
	if humanoid.Sit then
		humanoid:UnequipTools()
		return
	end

	local look = flat(rootPart.CFrame.LookVector)
	ride = {
		humanoid = humanoid,
		rootPart = rootPart,
		walkSpeed = humanoid.WalkSpeed,
		hipHeight = humanoid.HipHeight,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		speed = 0,
		direction = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1),
		connections = {},
	}

	local scale = Shared.riderScale(settings, humanoid, rootPart, ride.hipHeight)
	mount.Part0 = nil
	Shared.fit(body, scale)
	mount.C0 = Shared.mountOffset(humanoid, rootPart, ride.hipHeight)
	mount.Part0 = rootPart
	humanoid.HipHeight = ride.hipHeight + (body:GetAttribute("DeckHeight") or 0.5) * scale
	-- JumpHeight grows with the square of JumpPower.
	humanoid.JumpHeight = ride.jumpHeight * settings.JumpBoost
	humanoid.JumpPower = ride.jumpPower * math.sqrt(settings.JumpBoost)

	local function putAway()
		if tool.Parent == character then
			humanoid:UnequipTools()
		end
	end
	table.insert(ride.connections, humanoid.Seated:Connect(function(active)
		if active then
			putAway()
		end
	end))
	table.insert(ride.connections, humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Swimming then
			putAway()
		end
	end))
	table.insert(ride.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if settings.ThemeKey and input.KeyCode == settings.ThemeKey then
			nextTheme()
		elseif settings.HornKey and input.KeyCode == settings.HornKey then
			honk()
		end
	end))

	if settings.ShowHud then
		local camera = workspace.CurrentCamera
		ride.hud = Hud.new(settings, {
			keyboard = UserInputService.KeyboardEnabled,
			touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
			viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720),
		}, hornSound ~= nil)
		ride.hud.gui.Parent = player:WaitForChild("PlayerGui")
		showTheme()
		if ride.hud.themeButton then
			table.insert(ride.connections, ride.hud.themeButton.Activated:Connect(nextTheme))
		end
		if ride.hud.hornButton then
			-- On press, not on release: a horn should sound the moment it's touched.
			table.insert(ride.connections, ride.hud.hornButton.MouseButton1Down:Connect(honk))
		end
		table.insert(ride.connections, body:GetAttributeChangedSignal("Theme"):Connect(function()
			if ride then
				showTheme()
			end
		end))
	end

	-- Runs after the control script (Input priority) has called Move for this frame.
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Input.Value + 1, step)
end

tool.Equipped:Connect(startRiding)
tool.Unequipped:Connect(stopRiding)
tool.AncestryChanged:Connect(function()
	if not tool:IsDescendantOf(game) then
		stopRiding()
	end
end)
