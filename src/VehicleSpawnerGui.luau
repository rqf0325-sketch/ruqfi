--[[
	VehicleSpawnerGui — UI only (tanpa sistem spawn)

	Cara pakai (Roblox Studio):
	  1. View > Command Bar
	  2. Paste seluruh isi file ini, tekan Enter
	  3. ScreenGui "VehicleSpawnerGui" akan muncul di StarterGui

	Atau: klik kanan StarterGui > Insert from File... > StarterGui/VehicleSpawnerGui.rbxmx
	(file .rbxmx dibuat dari script ini lewat tools/build.luau).

	Semua ukuran memakai Scale + UIAspectRatioConstraint, jadi tampilannya
	sama di PC, tablet, dan HP. Angka-angka di bawah ditulis dalam "pixel desain"
	(panel utama 960 x 582) lalu diubah otomatis menjadi Scale.
]]

local GUI_NAME = "VehicleSpawnerGui"
local FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"

local C = {
	Backdrop = Color3.fromRGB(5, 6, 10),
	PanelTop = Color3.fromRGB(28, 33, 45),
	PanelBottom = Color3.fromRGB(11, 13, 18),
	Surface = Color3.fromRGB(26, 30, 41),
	Sidebar = Color3.fromRGB(21, 25, 34),
	Field = Color3.fromRGB(33, 38, 52),
	StageTop = Color3.fromRGB(48, 55, 74),
	StageBottom = Color3.fromRGB(17, 20, 28),
	Track = Color3.fromRGB(40, 45, 60),
	Text = Color3.fromRGB(245, 246, 248),
	Muted = Color3.fromRGB(140, 149, 166),
	Dim = Color3.fromRGB(96, 104, 121),
	Amber = Color3.fromRGB(255, 190, 56),
	Orange = Color3.fromRGB(255, 128, 31),
	OnAmber = Color3.fromRGB(28, 19, 4),
	Purple = Color3.fromRGB(139, 108, 255),
	PurpleLight = Color3.fromRGB(196, 181, 253),
	Green = Color3.fromRGB(61, 220, 151),
	Red = Color3.fromRGB(255, 85, 102),
	White = Color3.new(1, 1, 1),
	Black = Color3.new(0, 0, 0),
}

local W = Enum.FontWeight
local Left, Center, Right = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right

-- Contoh isi. Ganti/hapus sesuai kendaraan di game kamu.
local VEHICLES = {
	{ name = "Chopper Howlers", info = "Chopper", locked = true, new = true },
	{ name = "Bobber Howlers", info = "Bobber", locked = true, new = true },
	{ name = "BMW R 80", info = "Cafe Racer", new = true, selected = true },
	{ name = "Chicano Howlers", info = "Lowrider", new = true },
	{ name = "Scrambler 400", info = "Scrambler" },
	{ name = "Street Glide", info = "Touring" },
	{ name = "Ninja ZX-25R", info = "Sport" },
	{ name = "Vespa Sprint", info = "Scooter" },
}

local SELECTED = {
	name = "BMW R 80",
	info = "Cafe Racer  •  Motorcycle",
	stats = {
		{ "Top Speed", "165 km/h", 0.72 },
		{ "Acceleration", "4.8 s", 0.62 },
		{ "Handling", "8.4 / 10", 0.84 },
	},
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

-- A node is { inst, w, h }: the Instance plus its size in design pixels, so
-- children can be positioned in pixels and converted to Scale.
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
	inst.Parent = parent.inst
	return inst
end

local function corner(node, radius)
	return add("UICorner", node, {
		CornerRadius = UDim.new(math.min(radius / math.min(node.w, node.h), 0.5), 0),
	})
end

local function stroke(node, color, transparency, thickness)
	return add("UIStroke", node, {
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

local function fade(from, to)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from),
		NumberSequenceKeypoint.new(1, to),
	})
end

-- Text height in design pixels == text size (TextScaled keeps it proportional).
local function label(parent, name, text, x, y, w, h, color, weight, align, props)
	local node = place("TextLabel", parent, name, x, y, w, h, {
		Text = text,
		TextColor3 = color,
		FontFace = font(weight),
		TextSize = h,
		TextScaled = true,
		TextXAlignment = align or Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	apply(node.inst, props)
	return node
end

-- Gradient buttons keep their text in a child label, because a UIGradient
-- would also tint the button's own text.
local function amberButton(parent, name, text, x, y, w, h, textSize, radius)
	local button = place("TextButton", parent, name, x, y, w, h, {
		BackgroundTransparency = 0,
		Text = "",
		AutoButtonColor = true,
	})
	corner(button, radius)
	gradient(button, C.Amber, C.Orange, 20)
	label(button, "Label", text, 0, (h - textSize) / 2, w, textSize, C.OnAmber, W.ExtraBold, Center)
	return button
end

local function newBadge(parent, x, y, w, h, textSize, zIndex)
	local badge = place("Frame", parent, "NewBadge", x, y, w, h, { BackgroundTransparency = 0, ZIndex = zIndex or 1 })
	corner(badge, h * 0.3)
	gradient(badge, C.Amber, C.Orange, 20)
	label(badge, "Label", "NEW", 0, (h - textSize) / 2, w, textSize, C.OnAmber, W.ExtraBold, Center)
	return badge
end

-- Showroom backdrop for vehicle pictures. Put your image in VehicleImage.Image
-- and delete PlaceholderIcon.
local function stage(parent, x, y, w, h, radius, iconSize)
	local node = place("Frame", parent, "Stage", x, y, w, h, { BackgroundTransparency = 0 })
	corner(node, radius)
	gradient(node, C.StageTop, C.StageBottom, 90)

	local floor = place("Frame", node, "Floor", 0, h * 0.62, w, h * 0.38, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Black,
		ZIndex = 1,
	})
	corner(floor, radius)
	gradient(floor, C.Black, C.Black, 90, fade(1, 0.45))

	local lip = place("Frame", node, "FloorLine", w * 0.12, h * 0.62, w * 0.76, 1, {
		BackgroundTransparency = 0.9,
		ZIndex = 2,
	})
	lip.inst.Size = UDim2.new(0.76, 0, 0, 1)

	label(node, "PlaceholderIcon", "🏍️", 0, (h - iconSize) / 2, w, iconSize, C.White, W.Regular, Center, {
		TextTransparency = 0.15,
		ZIndex = 3,
	})
	place("ImageLabel", node, "VehicleImage", 0, 0, w, h, {
		Image = "",
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 4,
	})
	return node
end

---------------------------------------------------------------------------
-- Vehicle card (grid item)
---------------------------------------------------------------------------

local CARD_W, CARD_H = 142, 172
local CARD_GAP = 12
local SLOT_W, SLOT_H = CARD_W + CARD_GAP, CARD_H + CARD_GAP

-- Each grid cell is a transparent slot holding the visible card with half the
-- gap on every side. That keeps the spacing in Scale; an Offset CellPadding
-- would not shrink on phones.
local function vehicleCard(grid, index, data)
	local slot = { inst = Instance.new("Frame"), w = SLOT_W, h = SLOT_H }
	apply(slot.inst, {
		Name = "Card_" .. data.name:gsub("[^%w]", ""),
		LayoutOrder = index,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})

	local card = place("Frame", slot, "Card", CARD_GAP / 2, CARD_GAP / 2, CARD_W, CARD_H, {
		BackgroundTransparency = 0,
		BackgroundColor3 = data.selected and Color3.fromRGB(36, 33, 29) or C.Surface,
	})
	corner(card, 12)
	if data.selected then
		stroke(card, C.Amber, 0, 2)
	else
		stroke(card, C.White, 0.92)
	end

	stage(card, 7, 7, CARD_W - 14, 100, 9, 40)

	if data.locked then
		local overlay = place("Frame", card, "LockOverlay", 7, 7, CARD_W - 14, 100, {
			BackgroundTransparency = 0.18,
			BackgroundColor3 = Color3.fromRGB(10, 10, 16),
			ZIndex = 2,
		})
		corner(overlay, 9)

		local circle = place("Frame", overlay, "LockIcon", (overlay.w - 36) / 2, 13, 36, 36, {
			BackgroundTransparency = 0.72,
			BackgroundColor3 = C.Purple,
		})
		corner(circle, 18)
		stroke(circle, C.PurpleLight, 0.45)
		label(circle, "Icon", "🔒", 9, 9, 18, 18, C.White, W.Regular, Center)

		label(overlay, "Title", "LIMITED", 0, 57, overlay.w, 10, C.PurpleLight, W.ExtraBold, Center)
		label(overlay, "Subtitle", "Motorcycle Pass", 0, 71, overlay.w, 12, C.Text, W.Bold, Center)
	end

	if data.new then
		newBadge(card, 13, 13, 38, 17, 10, 3)
	end

	label(card, "VehicleName", data.name, 11, 116.5, CARD_W - 22, 13, C.Text, W.Bold)
	label(card, "Info", data.info, 11, 134, CARD_W - 22, 12, C.Muted, W.Medium)

	local statusColor, statusText = C.Green, "Available"
	if data.locked then
		statusColor, statusText = C.PurpleLight, "Gamepass"
	elseif data.selected then
		statusColor, statusText = C.Amber, "Selected"
	end
	local dot = place("Frame", card, "StatusDot", 11, 154, 6, 6, {
		BackgroundTransparency = 0,
		BackgroundColor3 = statusColor,
	})
	corner(dot, 3)
	label(card, "Status", statusText, 22, 151.5, CARD_W - 33, 11, statusColor, W.SemiBold)

	slot.inst.Parent = grid.inst
	return slot
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

	-- Floating button to open the menu --------------------------------------
	local open = place("TextButton", screen, "OpenButton", 0.015, 0.5, 0.05, 0.09, {
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 0.08,
		BackgroundColor3 = Color3.fromRGB(17, 20, 27),
		Text = "",
		AutoButtonColor = true,
		ZIndex = 1,
	})
	open.w, open.h = 64, 64
	add("UIAspectRatioConstraint", open, { AspectRatio = 1 })
	corner(open, 16)
	stroke(open, C.Amber, 0.45, 1.5)
	label(open, "Emoji", "🏍️", 0, 9, 64, 28, C.White, W.Regular, Center)
	label(open, "Title", "GARAGE", 0, 43, 64, 11, C.Amber, W.ExtraBold, Center)

	-- Dim the world behind the menu ------------------------------------------
	place("Frame", screen, "Backdrop", 0, 0, 1, 1, {
		BackgroundTransparency = 0.45,
		BackgroundColor3 = C.Backdrop,
		ZIndex = 2,
	})

	-- Main panel -------------------------------------------------------------
	local main = place("Frame", screen, "Main", 0.5, 0.5, 0.8, 0.88, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 0,
		ZIndex = 3,
	})
	main.w, main.h = 960, 582
	add("UIAspectRatioConstraint", main, { AspectRatio = 960 / 582 })
	corner(main, 18)
	stroke(main, C.White, 0.88, 1.5)
	gradient(main, C.PanelTop, C.PanelBottom, 90)

	local glow = place("Frame", main, "Glow", 0, 0, 960, 300, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Amber,
		ZIndex = 0,
	})
	corner(glow, 18)
	gradient(glow, C.White, C.White, 90, fade(0.9, 1))

	-- Header
	local header = place("Frame", main, "Header", 0, 0, 960, 80)

	local appIcon = place("Frame", header, "AppIcon", 24, 17, 46, 46, { BackgroundTransparency = 0 })
	corner(appIcon, 13)
	gradient(appIcon, C.Amber, C.Orange, 45)
	label(appIcon, "Emoji", "🏍️", 9, 9, 28, 28, C.White, W.Regular, Center)

	label(header, "Eyebrow", "VEHICLE SPAWNER", 84, 20, 300, 12, C.Amber, W.Bold)
	label(header, "Title", 'Welcome, <font color="#FFBE38">SweetPie0325</font>', 84, 36, 440, 26, C.Text, W.ExtraBold, Left, {
		RichText = true,
	})

	local close = place("TextButton", header, "CloseButton", 894, 19, 42, 42, {
		BackgroundTransparency = 0.84,
		BackgroundColor3 = C.Red,
		Text = "",
		AutoButtonColor = true,
	})
	corner(close, 12)
	stroke(close, C.Red, 0.5)
	label(close, "Icon", "×", 0, 5, 42, 30, C.Red, W.Bold, Center)

	amberButton(header, "InsertButton", "+  Insert Vehicle", 710, 19, 172, 42, 14, 12)

	local divider = place("Frame", main, "Divider", 24, 80, 912, 1, { BackgroundTransparency = 0.93 })
	divider.inst.Size = UDim2.new(912 / 960, 0, 0, 1)

	-- Left: browser ----------------------------------------------------------
	local browser = place("Frame", main, "Browser", 24, 96, 612, 462)

	local search = place("Frame", browser, "Search", 0, 0, 452, 42, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Field,
	})
	corner(search, 11)
	stroke(search, C.White, 0.92)
	label(search, "Icon", "🔍", 14, 12, 18, 18, C.White, W.Regular, Center, { TextTransparency = 0.2 })
	local searchBox = place("TextBox", search, "SearchBox", 42, 0, 398, 42, {
		Text = "",
		PlaceholderText = "Search vehicle...",
		PlaceholderColor3 = C.Dim,
		TextColor3 = C.Text,
		FontFace = font(W.Medium),
		TextSize = 14,
		TextScaled = true,
		TextXAlignment = Left,
		ClearTextOnFocus = false,
	})
	add("UIPadding", searchBox, {
		PaddingTop = UDim.new(14 / 42, 0),
		PaddingBottom = UDim.new(14 / 42, 0),
	})

	local sort = place("TextButton", browser, "SortButton", 464, 0, 148, 42, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Field,
		Text = "",
		AutoButtonColor = true,
	})
	corner(sort, 11)
	stroke(sort, C.White, 0.92)
	label(sort, "Label", '<font color="#8C95A6">Sort:</font>  Newest', 14, 14, 104, 14, C.Text, W.SemiBold, Left, {
		RichText = true,
	})
	label(sort, "Arrow", "▼", 120, 15, 14, 12, C.Amber, W.Bold, Center)

	-- Category tabs
	local tabs = place("Frame", browser, "Tabs", 0, 56, 440, 32)
	add("UIListLayout", tabs, {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(8 / 440, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	local TABS = { { "All", 52 }, { "Motorcycle", 106 }, { "Car", 58 }, { "Gamepass", 98 } }
	for i, tab in TABS do
		local active = i == 1
		local button = place("TextButton", tabs, "Tab_" .. tab[1], 0, 0, tab[2], 32, {
			LayoutOrder = i,
			BackgroundTransparency = 0,
			BackgroundColor3 = active and C.Amber or C.Field,
			Text = tab[1],
			TextColor3 = active and C.OnAmber or C.Muted,
			FontFace = font(active and W.ExtraBold or W.SemiBold),
			TextSize = 13,
			TextScaled = true,
			AutoButtonColor = true,
		})
		corner(button, 16)
		if not active then
			stroke(button, C.White, 0.92)
		end
		add("UIPadding", button, {
			PaddingTop = UDim.new(9.5 / 32, 0),
			PaddingBottom = UDim.new(9.5 / 32, 0),
		})
	end

	label(browser, "ResultCount", '<font color="#FFBE38">' .. #VEHICLES .. "</font>  vehicles", 412, 65, 200, 14, C.Muted, W.SemiBold, Right, {
		RichText = true,
	})

	-- Vehicle grid
	local grid = place("ScrollingFrame", browser, "Grid", -CARD_GAP / 2, 100 - CARD_GAP / 2, 612 + CARD_GAP / 2, 362 + CARD_GAP / 2, {
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Amber,
		ScrollBarImageTransparency = 0.35,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	})
	local gridLayout = add("UIGridLayout", grid, {
		CellSize = UDim2.new(SLOT_W / grid.w, 0, 0, SLOT_H),
		CellPadding = UDim2.new(),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	})
	-- Keeps every card at the same shape on any screen size.
	local cellAspect = Instance.new("UIAspectRatioConstraint")
	cellAspect.AspectRatio = SLOT_W / SLOT_H
	cellAspect.AspectType = Enum.AspectType.ScaleWithParentSize
	cellAspect.DominantAxis = Enum.DominantAxis.Width
	cellAspect.Parent = gridLayout

	for i, data in VEHICLES do
		vehicleCard(grid, i, data)
	end

	-- Right: selected vehicle details ---------------------------------------
	local details = place("Frame", main, "Details", 656, 96, 280, 462, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Sidebar,
	})
	corner(details, 16)
	stroke(details, C.White, 0.92)

	stage(details, 14, 14, 252, 172, 12, 68)
	newBadge(details, 24, 24, 44, 20, 11, 2)

	label(details, "VehicleName", SELECTED.name, 16, 200, 248, 24, C.Text, W.ExtraBold)
	label(details, "Info", SELECTED.info, 16, 229, 248, 13, C.Muted, W.Medium)

	local statsDivider = place("Frame", details, "Divider", 16, 254, 248, 1, { BackgroundTransparency = 0.93 })
	statsDivider.inst.Size = UDim2.new(248 / 280, 0, 0, 1)

	local stats = place("Frame", details, "Stats", 16, 268, 248, 102)
	for i, stat in SELECTED.stats do
		local row = place("Frame", stats, "Stat_" .. stat[1]:gsub("%s", ""), 0, (i - 1) * 38, 248, 26)
		label(row, "Name", stat[1], 0, 0, 150, 12, C.Muted, W.SemiBold)
		label(row, "Value", stat[2], 148, 0, 100, 12, C.Text, W.Bold, Right)
		local track = place("Frame", row, "Track", 0, 20, 248, 6, {
			BackgroundTransparency = 0,
			BackgroundColor3 = C.Track,
		})
		corner(track, 3)
		local fill = place("Frame", track, "Fill", 0, 0, 248 * stat[3], 6, { BackgroundTransparency = 0 })
		corner(fill, 3)
		gradient(fill, C.Orange, C.Amber, 0)
	end

	amberButton(details, "SpawnButton", "SPAWN VEHICLE", 16, 398, 248, 48, 15, 12)

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
print("[VehicleSpawnerGui] Dibuat di StarterGui")

return gui
