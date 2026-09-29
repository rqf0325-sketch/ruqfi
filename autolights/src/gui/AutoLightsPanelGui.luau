--[[
	AutoLightsPanelGui — tampilan panel kontrol AutoLights (tanpa script).

	tools/build-autolights.luau menjalankan file ini, menambahkan LocalScript
	AutoLightsPanelClient, lalu menyimpan hasilnya ke
	StarterGui/AutoLightsPanel.rbxmx. File ini juga bisa di-paste ke Command
	Bar Studio untuk membuat tampilannya saja.

	Panel hanya muncul untuk operator (lihat AutoLightsAccess). Ukuran ditulis
	dalam "pixel desain" (panel 420 x 510); UIScale bernama ResponsiveScale diatur
	otomatis oleh AutoLightsPanelClient sesuai layar.

	Watermark: teks "PAUL" (ganti lewat CONTROL.Watermark di AutoLightsSyncConfig).
]]

local GUI_NAME = "AutoLightsPanel"
local FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"

local C = {
	Panel = Color3.fromRGB(6, 7, 12),
	Text = Color3.fromRGB(246, 247, 250),
	Muted = Color3.fromRGB(196, 200, 216),
	Dim = Color3.fromRGB(160, 165, 186),
	Cyan = Color3.fromRGB(56, 225, 255),
	Violet = Color3.fromRGB(139, 108, 255),
	Pink = Color3.fromRGB(255, 82, 150),
	Amber = Color3.fromRGB(255, 190, 56),
	Green = Color3.fromRGB(61, 220, 151),
	Red = Color3.fromRGB(255, 85, 102),
	White = Color3.new(1, 1, 1),
	Black = Color3.new(0, 0, 0),
}

local W = Enum.FontWeight
local Left, Center, Right = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right

local PANEL_W, PANEL_H = 420, 510
local GLASS = 0.9 -- transparency of tiles

-- Contoh isi untuk tampilan di Studio (diisi AutoLightsPanelClient saat game berjalan).
local SAMPLE = {
	pattern = "Ripple",
	patternText = "Ripple   3/12",
	bpm = "124 BPM",
	brightness = "80%",
	watermark = "PAUL",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function font(weight)
	return Font.new(FONT_FAMILY, weight or W.Bold, Enum.FontStyle.Normal)
end

local function apply(inst, props)
	if props then
		for key, value in props do
			inst[key] = value
		end
	end
	return inst
end

-- A node is { inst, w, h }: the Instance plus its size in design pixels.
local function place(className, parent, name, x, y, w, h, props)
	local inst = Instance.new(className)
	inst.Name = name
	inst.BorderSizePixel = 0
	inst.BackgroundColor3 = C.White
	inst.BackgroundTransparency = 1
	inst.Position = UDim2.fromScale(x / parent.w, y / parent.h)
	inst.Size = UDim2.fromScale(w / parent.w, h / parent.h)
	apply(inst, props)
	inst.Parent = parent.inst
	return { inst = inst, w = w, h = h }
end

local function add(className, parent, props)
	local inst = Instance.new(className)
	apply(inst, props)
	inst.Parent = if typeof(parent) == "Instance" then parent else parent.inst
	return inst
end

local function corner(node, radius)
	return add("UICorner", node, {
		CornerRadius = UDim.new(math.min(radius / math.min(node.w, node.h), 0.5), 0),
	})
end

local function circle(node)
	return add("UICorner", node, { CornerRadius = UDim.new(0.5, 0) })
end

local function stroke(node, color, transparency, thickness)
	return add("UIStroke", node, {
		Name = "Outline",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Transparency = transparency or 0,
		Thickness = thickness or 1,
	})
end

local function gradient(node, from, to, rotation, transparency)
	return add("UIGradient", node, {
		Color = ColorSequence.new(from, to),
		Rotation = rotation or 0,
		Transparency = transparency or NumberSequence.new(0),
	})
end

local function label(parent, name, text, x, y, w, h, size, color, weight, align, props)
	local node = place("TextLabel", parent, name, x, y, w, h, {
		Text = text,
		TextColor3 = color,
		FontFace = font(weight),
		TextSize = size,
		TextXAlignment = align or Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	apply(node.inst, props)
	return node
end

local function glassButton(parent, name, x, y, w, h, radius)
	local button = place("TextButton", parent, name, x, y, w, h, {
		BackgroundTransparency = GLASS,
		BackgroundColor3 = C.White,
		Text = "",
		AutoButtonColor = false,
	})
	corner(button, radius or 12)
	stroke(button, C.White, 0.85)
	return button
end

local function iconButton(parent, name, text, x, y, size, textSize)
	local button = place("TextButton", parent, name, x, y, size, size, {
		BackgroundTransparency = 0.92,
		BackgroundColor3 = C.White,
		Text = "",
		AutoButtonColor = false,
	})
	circle(button)
	stroke(button, C.White, 0.9)
	label(button, "Icon", text, 0, 0, size, size - 2, textSize, C.Muted, W.Bold, Center, { TextTruncate = Enum.TextTruncate.None })
	return button
end

local function sectionLabel(parent, name, text, x, y, w)
	return label(parent, name, text, x, y, w, 12, 10, C.Dim, W.ExtraBold)
end

-- Switch row: title + subtitle on the left, an on/off switch on the right.
local function toggleRow(parent, name, x, y, w, title, subtitle, on)
	local row = glassButton(parent, name, x, y, w, 44, 12)
	label(row, "Title", title, 12, 7, w - 70, 16, 12, C.Text, W.Bold)
	label(row, "Subtitle", subtitle, 12, 24, w - 70, 12, 9, C.Muted, W.Medium)
	local track = place("Frame", row, "Track", w - 52, 11, 40, 22, {
		BackgroundTransparency = if on then 0 else 0.7,
		BackgroundColor3 = if on then C.Green else C.White,
	})
	circle(track)
	local knob = place("Frame", track, "Knob", if on then 20 else 2, 3, 16, 16, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.White,
	})
	circle(knob)
	return row
end

local function actionButton(parent, name, icon, text, x, y, w, h, tint, textSize)
	local button = glassButton(parent, name, x, y, w, h, 12)
	if tint then
		button.inst.BackgroundColor3 = tint
		button.inst.BackgroundTransparency = 0.72
		button.inst.Outline.Color = tint
		button.inst.Outline.Transparency = 0.45
	end
	label(button, "Icon", icon, 6, 0, 24, h, 14, C.White, W.Regular, Center, { TextTruncate = Enum.TextTruncate.None })
	label(button, "Label", text, 32, 0, w - 36, h, textSize or 11, C.Text, W.ExtraBold)
	return button
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function build()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local screen = { inst = screenGui, w = 1, h = 1 }

	-- Floating button (only operators see it) -----------------------------------
	local open = place("TextButton", screen, "OpenButton", 1, 0.5, 60, 60, {
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = C.Panel,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 2,
	})
	open.inst.Position = UDim2.new(1, -16, 0.5, 0)
	open.inst.Size = UDim2.fromOffset(60, 60)
	add("UIScale", open, { Name = "ResponsiveScale", Scale = 1 })
	corner(open, 18)
	stroke(open, C.Cyan, 0.4, 1.5)
	label(open, "Emoji", "💡", 0, 8, 60, 28, 22, C.White, W.Regular, Center, { TextTruncate = Enum.TextTruncate.None })
	label(open, "Title", "LIGHTS", 0, 40, 60, 12, 9, C.Cyan, W.ExtraBold, Center, { TextTruncate = Enum.TextTruncate.None })

	-- Panel ----------------------------------------------------------------------
	local panel = place("Frame", screen, "Panel", 1, 0.5, PANEL_W, PANEL_H, {
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.3,
		ZIndex = 3,
	})
	panel.inst.Position = UDim2.new(1, -16, 0.5, 0)
	panel.inst.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	add("UIScale", panel, { Name = "ResponsiveScale", Scale = 1 })
	corner(panel, 22)
	stroke(panel, C.White, 0.7, 1.5)

	-- Big faint watermark behind everything
	label(panel, "WatermarkBig", SAMPLE.watermark, 0, 250, PANEL_W, 150, 120, C.White, W.ExtraBold, Center, {
		TextTransparency = 0.94,
		Rotation = -10,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 0,
	})

	-- Header
	label(panel, "Eyebrow", "CONTROL PANEL", 20, 16, 200, 12, 10, C.Cyan, W.ExtraBold)
	label(panel, "Title", "AutoLights", 20, 30, 220, 30, 24, C.Text, W.ExtraBold)
	iconButton(panel, "CloseButton", "×", 368, 16, 34, 22)

	local chip = place("Frame", panel, "SyncChip", 236, 24, 122, 26, {
		BackgroundTransparency = 0.84,
		BackgroundColor3 = C.Green,
	})
	circle(chip)
	stroke(chip, C.Green, 0.55)
	local chipDot = place("Frame", chip, "Dot", 12, 9, 8, 8, { BackgroundTransparency = 0, BackgroundColor3 = C.Green })
	circle(chipDot)
	label(chip, "Label", "SYNC ON", 26, 0, 92, 26, 10, C.Green, W.ExtraBold, Left, { TextTruncate = Enum.TextTruncate.None })

	-- Beat tile
	local beat = place("Frame", panel, "BeatTile", 18, 74, 384, 46, {
		BackgroundTransparency = GLASS,
		BackgroundColor3 = C.White,
	})
	corner(beat, 14)
	stroke(beat, C.White, 0.85)
	local beatDot = place("Frame", beat, "BeatDot", 16, 15, 16, 16, { BackgroundTransparency = 0.2, BackgroundColor3 = C.Pink })
	circle(beatDot)
	label(beat, "Bpm", SAMPLE.bpm, 44, 0, 110, 46, 15, C.Text, W.ExtraBold)
	label(beat, "PatternName", SAMPLE.pattern, 150, 0, 220, 46, 12, C.Muted, W.SemiBold, Right)

	-- Left column: SYNC -----------------------------------------------------------
	local left = place("Frame", panel, "Left", 18, 134, 184, 320)
	sectionLabel(left, "SyncLabel", "SYNC", 2, 0, 160)
	toggleRow(left, "Toggle_Sync", 0, 18, 184, "Beat Sync", "Lights follow the music", true)
	toggleRow(left, "Toggle_DanceFloor", 0, 70, 184, "Dance Floor", "Tiles on the floor", true)
	toggleRow(left, "Toggle_AutoPattern", 0, 122, 184, "Auto Pattern", "Changes every few bars", true)

	local patternRow = place("Frame", left, "PatternRow", 0, 174, 184, 40, {
		BackgroundTransparency = GLASS,
		BackgroundColor3 = C.White,
	})
	corner(patternRow, 12)
	stroke(patternRow, C.White, 0.85)
	iconButton(patternRow, "Prev", "‹", 5, 4, 32, 24)
	label(patternRow, "PatternText", SAMPLE.patternText, 40, 0, 104, 40, 11, C.Text, W.Bold, Center)
	iconButton(patternRow, "Next", "›", 147, 4, 32, 24)

	local brightnessRow = place("Frame", left, "BrightnessRow", 0, 222, 184, 40, {
		BackgroundTransparency = GLASS,
		BackgroundColor3 = C.White,
	})
	corner(brightnessRow, 12)
	stroke(brightnessRow, C.White, 0.85)
	iconButton(brightnessRow, "Minus", "−", 5, 4, 32, 20)
	local barTrack = place("Frame", brightnessRow, "Track", 44, 15, 68, 10, {
		BackgroundTransparency = 0.8,
		BackgroundColor3 = C.White,
	})
	circle(barTrack)
	local barFill = place("Frame", barTrack, "Fill", 0, 0, 54, 10, { BackgroundTransparency = 0, BackgroundColor3 = C.Cyan })
	circle(barFill)
	gradient(barFill, C.Cyan, C.Violet, 0)
	label(brightnessRow, "Value", SAMPLE.brightness, 114, 0, 30, 40, 10, C.Text, W.ExtraBold, Center, { TextTruncate = Enum.TextTruncate.None })
	iconButton(brightnessRow, "Plus", "+", 147, 4, 32, 20)

	actionButton(left, "Flash", "⚡", "FLASH TEST", 0, 270, 184, 38, C.Amber)

	-- Right column: EFFECTS + LIGHTS ------------------------------------------------
	local right = place("Frame", panel, "Right", 218, 134, 184, 320)
	sectionLabel(right, "EffectsLabel", "EFFECTS", 2, 0, 160)
	toggleRow(right, "Toggle_Pyro", 0, 18, 184, "Pyro", "Fire, CO2, smoke, confetti", true)
	actionButton(right, "Fire_CO2", "💨", "CO2", 0, 70, 88, 36, nil, 10)
	actionButton(right, "Fire_CONFETTI", "🎉", "CONFETTI", 96, 70, 88, 36, nil, 9)
	actionButton(right, "Fire_SMOKE", "🌫️", "SMOKE", 0, 114, 88, 36, nil, 10)
	actionButton(right, "StopPyro", "⛔", "STOP", 96, 114, 88, 36, C.Red, 10)

	sectionLabel(right, "LightsLabel", "LIGHTS", 2, 168, 160)
	actionButton(right, "Blackout", "🌑", "BLACKOUT", 0, 186, 184, 44, C.Red)
	actionButton(right, "Restore", "💡", "RESTORE", 0, 238, 184, 44, C.Green)

	-- Toast (result of the last action)
	local toast = place("Frame", panel, "Toast", 18, 458, 384, 26, {
		BackgroundTransparency = 0.9,
		BackgroundColor3 = C.White,
		Visible = false,
	})
	corner(toast, 13)
	local toastDot = place("Frame", toast, "Dot", 12, 9, 8, 8, { BackgroundTransparency = 0, BackgroundColor3 = C.Green })
	circle(toastDot)
	label(toast, "Message", "Sync OFF", 28, 0, 350, 26, 10, C.Text, W.SemiBold)

	-- Footer: credit + watermark
	label(panel, "Credit", "G-Lights Phantom  •  Jin Development", 20, 488, 240, 12, 9, C.Dim, W.Medium)
	label(panel, "Watermark", SAMPLE.watermark, 290, 484, 112, 18, 14, C.Cyan, W.ExtraBold, Right, {
		TextTruncate = Enum.TextTruncate.None,
	})

	return screenGui
end

---------------------------------------------------------------------------
-- Put it in StarterGui (replaces an older copy with the same name)
---------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local old = StarterGui:FindFirstChild(GUI_NAME)
if old then
	old:Destroy()
end

local gui = build()
gui.Parent = StarterGui

pcall(function()
	game:GetService("Selection"):Set({ gui })
end)
print("[AutoLightsPanel] Dibuat di StarterGui")

return gui
