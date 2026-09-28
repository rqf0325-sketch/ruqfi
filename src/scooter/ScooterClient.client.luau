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
local body = tool:WaitForChild("Body")
local mount = body:WaitForChild("Root"):WaitForChild("Mount")
local setTheme = tool:WaitForChild("SetTheme")

local STEP = "ScooterControl"
local STOP_SPEED = 3

local ride = nil

-- This player's colour, shown at once (the server paints it for everyone
-- the first time the scooter is equipped).
Shared.applyTheme(body, settings,
	if settings.PlayersCanChangeTheme then player:GetAttribute("ScooterTheme") or settings.Theme else settings.Theme)

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

local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)

local function themeColor()
	local theme = Shared.theme(settings, body:GetAttribute("Theme"))
	return theme.Light or (theme.Accent and theme.Accent.Color) or Color3.new(1, 1, 1)
end

local function makeHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ScooterHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -92)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.Size = UDim2.fromOffset(0, 40)
	bar.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
	bar.BackgroundTransparency = 0.2
	bar.Parent = gui
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke", bar)
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.85
	local padding = Instance.new("UIPadding", bar)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 16)
	local layout = Instance.new("UIListLayout", bar)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local function label(text, size, color, order)
		local item = Instance.new("TextLabel")
		item.BackgroundTransparency = 1
		item.AutomaticSize = Enum.AutomaticSize.X
		item.Size = UDim2.fromOffset(0, 40)
		item.FontFace = FONT
		item.TextSize = size
		item.TextColor3 = color
		item.Text = text
		item.LayoutOrder = order
		item.Parent = bar
		return item
	end

	local hud = { gui = gui }
	if settings.PlayersCanChangeTheme then
		local button = Instance.new("TextButton")
		button.Name = "Theme"
		button.BackgroundTransparency = 1
		button.AutomaticSize = Enum.AutomaticSize.X
		button.Size = UDim2.fromOffset(0, 40)
		button.Text = ""
		button.LayoutOrder = 1
		button.Parent = bar
		local row = Instance.new("UIListLayout", button)
		row.FillDirection = Enum.FillDirection.Horizontal
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.Padding = UDim.new(0, 8)
		row.SortOrder = Enum.SortOrder.LayoutOrder

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(16, 16)
		swatch.LayoutOrder = 1
		swatch.Parent = button
		Instance.new("UICorner", swatch).CornerRadius = UDim.new(1, 0)
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.AutomaticSize = Enum.AutomaticSize.X
		name.Size = UDim2.fromOffset(0, 40)
		name.FontFace = FONT
		name.TextSize = 14
		name.TextColor3 = Color3.new(1, 1, 1)
		name.LayoutOrder = 2
		name.Parent = button
		if settings.ThemeKey and UserInputService.KeyboardEnabled then
			local key = Instance.new("TextLabel")
			key.Size = UDim2.fromOffset(20, 20)
			key.BackgroundColor3 = Color3.new(1, 1, 1)
			key.BackgroundTransparency = 0.85
			key.FontFace = FONT
			key.TextSize = 11
			key.TextColor3 = Color3.fromRGB(200, 204, 214)
			key.Text = settings.ThemeKey.Name
			key.LayoutOrder = 3
			key.Parent = button
			Instance.new("UICorner", key).CornerRadius = UDim.new(0, 5)
		end
		label("|", 16, Color3.fromRGB(90, 96, 110), 2)
		hud.button, hud.swatch, hud.name = button, swatch, name
	end
	hud.speed = label("0", 18, Color3.new(1, 1, 1), 3)
	label("km/h", 11, Color3.fromRGB(150, 156, 170), 4)
	gui.Parent = player:WaitForChild("PlayerGui")
	return hud
end

local function showTheme(hud)
	if hud and hud.name then
		hud.name.Text = string.upper(body:GetAttribute("Theme") or "")
		hud.swatch.BackgroundColor3 = themeColor()
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
	if ride then
		showTheme(ride.hud)
	end
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
	if r.hud and r.hud.speed then
		local shown = tostring(math.floor(actual + 0.5))
		if r.hud.speed.Text ~= shown then
			r.hud.speed.Text = shown
		end
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
		r.hud.gui:Destroy()
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

	mount.C0 = Shared.mountOffset(humanoid, rootPart, ride.hipHeight)
	mount.Part0 = rootPart
	humanoid.HipHeight = ride.hipHeight + (body:GetAttribute("DeckHeight") or 0.5)
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
		if not processed and settings.ThemeKey and input.KeyCode == settings.ThemeKey then
			nextTheme()
		end
	end))

	if settings.ShowHud then
		ride.hud = makeHud()
		showTheme(ride.hud)
		if ride.hud.button then
			table.insert(ride.connections, ride.hud.button.Activated:Connect(nextTheme))
		end
		table.insert(ride.connections, body:GetAttributeChangedSignal("Theme"):Connect(function()
			if ride then
				showTheme(ride.hud)
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
