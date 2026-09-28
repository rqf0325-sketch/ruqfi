--[[
	Scooter — HUD (Tool > ScooterHud), built by ScooterClient while riding:

	  * bottom middle: theme button (colour dot, theme name, key) and speed
	  * bottom right: round horn button; on phones it sits left of Roblox's
	    jump button (70 px wide at 95 px from the right on small screens,
	    120 px wide at 170 px from the right and 210 px up on tablets)

	  local hud = Hud.new(settings, { keyboard = true, touchOnly = false, viewport = Vector2 }, hasHorn)
	  hud.gui.Parent = PlayerGui
	  hud:setTheme("NOCTIS", color); hud:setSpeed(24); hud:pulseHorn(); hud:destroy()
	  hud.themeButton / hud.hornButton  (nil when turned off)
]]

local Hud = {}
Hud.__index = Hud

local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
local PANEL = Color3.fromRGB(12, 14, 20)
local TEXT = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(150, 156, 170)

local function corner(parent, radius)
	local item = Instance.new("UICorner")
	item.CornerRadius = radius
	item.Parent = parent
end

local function label(parent, text, size, color, order)
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.AutomaticSize = Enum.AutomaticSize.X
	item.Size = UDim2.fromOffset(0, 40)
	item.FontFace = FONT
	item.TextSize = size
	item.TextColor3 = color
	item.Text = text
	item.LayoutOrder = order
	item.Parent = parent
	return item
end

local function row(parent, gap)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
end

local function keyBadge(parent, key)
	local badge = Instance.new("TextLabel")
	badge.Name = "Key"
	badge.Size = UDim2.fromOffset(20, 20)
	badge.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
	badge.FontFace = FONT
	badge.TextSize = 11
	badge.TextColor3 = Color3.fromRGB(220, 224, 232)
	badge.Text = key.Name
	badge.Parent = parent
	corner(badge, UDim.new(0, 5))
	return badge
end

function Hud.new(settings, device, hasHorn)
	local self = setmetatable({}, Hud)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ScooterHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.gui = gui

	-- Bottom middle: theme + speed
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -92)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.Size = UDim2.fromOffset(0, 40)
	bar.BackgroundColor3 = PANEL
	bar.BackgroundTransparency = 0.2
	bar.Parent = gui
	corner(bar, UDim.new(1, 0))
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEXT
	stroke.Transparency = 0.85
	stroke.Parent = bar
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = bar
	row(bar, 10)

	if settings.PlayersCanChangeTheme then
		local button = Instance.new("TextButton")
		button.Name = "Theme"
		button.BackgroundTransparency = 1
		button.AutomaticSize = Enum.AutomaticSize.X
		button.Size = UDim2.fromOffset(0, 40)
		button.Text = ""
		button.LayoutOrder = 1
		button.Parent = bar
		row(button, 8)
		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(16, 16)
		swatch.LayoutOrder = 1
		swatch.Parent = button
		corner(swatch, UDim.new(1, 0))
		self.themeName = label(button, "", 14, TEXT, 2)
		if settings.ThemeKey and device.keyboard then
			keyBadge(button, settings.ThemeKey).LayoutOrder = 3
		end
		label(bar, "|", 16, Color3.fromRGB(90, 96, 110), 2)
		self.themeButton, self.swatch = button, swatch
	end
	self.speed = label(bar, "0", 18, TEXT, 3)
	label(bar, "km/h", 11, MUTED, 4)

	-- Bottom right: horn
	if hasHorn then
		local size, position
		if not device.touchOnly then
			size, position = 72, UDim2.new(1, -24, 1, -24)
		elseif math.min(device.viewport.X, device.viewport.Y) <= 500 then
			size, position = 64, UDim2.new(1, -108, 1, -22)
		else
			size, position = 84, UDim2.new(1, -186, 1, -96)
		end
		local button = Instance.new("TextButton")
		button.Name = "Horn"
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = position
		button.Size = UDim2.fromOffset(size, size)
		button.BackgroundColor3 = PANEL
		button.BackgroundTransparency = 0.15
		button.AutoButtonColor = false
		button.Text = ""
		button.Parent = gui
		corner(button, UDim.new(1, 0))
		local ring = Instance.new("UIStroke")
		ring.Thickness = 2
		ring.Transparency = 0.2
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = button
		local scale = Instance.new("UIScale")
		scale.Parent = button

		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.4)
		icon.Size = UDim2.fromScale(0.5, 0.42)
		icon.TextScaled = true
		icon.FontFace = FONT
		icon.TextColor3 = TEXT
		icon.Text = "📢"
		icon.Parent = button
		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.BackgroundTransparency = 1
		caption.AnchorPoint = Vector2.new(0.5, 0.5)
		caption.Position = UDim2.fromScale(0.5, 0.77)
		caption.Size = UDim2.fromScale(0.62, 0.14)
		caption.TextScaled = true
		caption.FontFace = FONT
		caption.TextColor3 = Color3.fromRGB(220, 224, 232)
		caption.Text = "KLAKSON"
		caption.Parent = button
		if settings.HornKey and device.keyboard then
			local badge = keyBadge(button, settings.HornKey)
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 2, 0, -2)
		end

		-- Spreads out from the button each time the horn sounds.
		local wave = Instance.new("Frame")
		wave.Name = "Wave"
		wave.AnchorPoint = Vector2.new(0.5, 0.5)
		wave.Position = UDim2.fromScale(0.5, 0.5)
		wave.Size = UDim2.fromScale(1, 1)
		wave.BackgroundTransparency = 1
		wave.Parent = button
		corner(wave, UDim.new(1, 0))
		local waveStroke = Instance.new("UIStroke")
		waveStroke.Thickness = 3
		waveStroke.Transparency = 1
		waveStroke.Parent = wave

		self.hornButton, self.hornRing, self.hornScale = button, ring, scale
		self.wave, self.waveStroke = wave, waveStroke
	end
	return self
end

function Hud:setTheme(name, color)
	if self.themeName then
		self.themeName.Text = name
		self.swatch.BackgroundColor3 = color
	end
	if self.hornRing then
		self.hornRing.Color = color
		self.waveStroke.Color = color
	end
end

function Hud:setSpeed(speed)
	local shown = tostring(math.floor(speed + 0.5))
	if self.speed.Text ~= shown then
		self.speed.Text = shown
	end
end

-- Press feedback: the button bounces and a ring spreads out.
function Hud:pulseHorn()
	if not self.hornButton then
		return
	end
	local TweenService = game:GetService("TweenService")
	self.hornScale.Scale = 0.86
	TweenService:Create(self.hornScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	self.wave.Size = UDim2.fromScale(1, 1)
	self.waveStroke.Transparency = 0
	local spread = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self.wave, spread, { Size = UDim2.fromScale(1.8, 1.8) }):Play()
	TweenService:Create(self.waveStroke, spread, { Transparency = 1 }):Play()
end

function Hud:destroy()
	self.gui:Destroy()
end

return Hud
