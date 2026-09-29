--[[
	PlayerMenuGui — tampilan kartu pemain (tanpa script).

	tools/build-player-menu.luau menjalankan file ini, menambahkan
	LocalScript PlayerMenuClient dan PlayerMenuNametags, lalu menyimpan hasilnya
	ke StarterGui/PlayerMenuGui.rbxmx. File ini juga bisa di-paste ke Command
	Bar Studio untuk membuat tampilannya saja.

	Isi contoh di bawah (nama, angka, pesan chat) hanya untuk tampilan di
	Studio; saat game berjalan, PlayerMenuClient menggantinya dengan data
	pemain yang diketuk.

	Ukuran ditulis dalam "pixel desain": kartu 312 x 458. Setiap UIScale bernama
	ResponsiveScale diatur otomatis oleh PlayerMenuClient sesuai ukuran layar,
	jadi tampilannya sama di PC, tablet, dan HP.

	Halaman kartu: Home (aksi), ProfilePage (detail), ChatPage (private chat).

	Latar kartu transparan (kaca gelap tipis), dunia game tetap terlihat.
	CommunityBackground diisi PlayerMenuClient dengan ikon komunitas pemain
	kalau dia punya; kalau tidak, kartu polos transparan.
]]

local GUI_NAME = "PlayerMenuGui"
local FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"

local C = {
	Panel = Color3.fromRGB(6, 7, 12),
	Text = Color3.fromRGB(246, 247, 250),
	Muted = Color3.fromRGB(196, 200, 216),
	Dim = Color3.fromRGB(160, 165, 186),
	Pink = Color3.fromRGB(255, 82, 150),
	Coral = Color3.fromRGB(255, 132, 96),
	Violet = Color3.fromRGB(139, 108, 255),
	Blue = Color3.fromRGB(77, 171, 255),
	Amber = Color3.fromRGB(255, 190, 56),
	Orange = Color3.fromRGB(255, 128, 31),
	Green = Color3.fromRGB(61, 220, 151),
	Red = Color3.fromRGB(255, 85, 102),
	White = Color3.new(1, 1, 1),
	Black = Color3.new(0, 0, 0),
}

local W = Enum.FontWeight
local Left, Center, Right = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right

local CARD_W, CARD_H = 312, 458

-- Transparency of the card and of the tiles on it: the world shows through.
local CARD_TRANSPARENCY = 0.36
local GLASS = 0.9
local COMMUNITY_IMAGE_TRANSPARENCY = 0.6 -- PlayerMenuClient uses Config.Settings.Community.ImageTransparency

-- Contoh isi untuk tampilan di Studio (diganti data pemain saat game berjalan).
local SAMPLE = {
	name = "SweetPie",
	username = "@SweetPie0325",
	role = "ADMINISTRATOR",
	roleColor = C.Orange,
	friends = "329",
	followers = "0",
	likes = "174",
	community = "Community",
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
	inst.Parent = if typeof(parent) == "Instance" then parent else parent.inst
	return inst
end

local function corner(node, radius)
	return add("UICorner", node, {
		CornerRadius = UDim.new(math.min(radius / math.min(node.w, node.h), 0.5), 0),
	})
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

local function fade(from, to)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from),
		NumberSequenceKeypoint.new(1, to),
	})
end

-- Text uses a fixed size (design pixels); UIScale scales it with the card.
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

local function circle(node)
	return add("UICorner", node, { CornerRadius = UDim.new(0.5, 0) })
end

-- Pill with a label. PlayerMenuClient switches it to AutomaticSize so it fits
-- any text; the fixed size here is only for the Studio preview.
local function chip(parent, name, text, x, y, w, h, size, color, tint)
	local node = place("Frame", parent, name, x, y, w, h, {
		BackgroundTransparency = tint or 0.84,
		BackgroundColor3 = color,
	})
	circle(node)
	stroke(node, color, 0.55)
	label(node, "Label", text, 0, 0, w, h, size, color, W.ExtraBold, Center, { TextTruncate = Enum.TextTruncate.None })
	return node
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

---------------------------------------------------------------------------
-- Home page pieces
---------------------------------------------------------------------------

local function statTile(parent, name, x, w, value, caption, like)
	local tile = place(like and "TextButton" or "Frame", parent, name, x, 0, w, 62, {
		BackgroundTransparency = if like then 0 else GLASS,
		BackgroundColor3 = C.White,
	})
	if like then
		apply(tile.inst, { Text = "", AutoButtonColor = false })
		gradient(tile, C.Pink, C.Coral, 25)
		add("UIScale", tile, { Name = "Pulse", Scale = 1 })
	else
		stroke(tile, C.White, 0.85)
	end
	corner(tile, 14)
	label(tile, "Value", value, 0, 9, w, 26, 21, C.White, W.ExtraBold, Center)
	label(tile, "Caption", caption, 0, 37, w, 14, 9, like and C.White or C.Muted, W.Bold, Center, {
		TextTransparency = like and 0.1 or 0,
	})
	return tile
end

local function actionTile(parent, name, x, y, w, icon, tint, title, subtitle, wide)
	local tile = place("TextButton", parent, name, x, y, w, 52, {
		BackgroundTransparency = GLASS,
		BackgroundColor3 = C.White,
		Text = "",
		AutoButtonColor = false,
	})
	corner(tile, 14)
	stroke(tile, C.White, 0.85)
	local iconChip = place("Frame", tile, "IconChip", 10, 11, 30, 30, {
		BackgroundTransparency = 0.75,
		BackgroundColor3 = tint,
	})
	corner(iconChip, 9)
	label(iconChip, "Icon", icon, 0, 0, 30, 30, 15, C.White, W.Regular, Center, { TextTruncate = Enum.TextTruncate.None })
	local textWidth = w - 48 - (wide and 60 or 8)
	label(tile, "Title", title, 48, 10, textWidth, 16, 12, C.Text, W.Bold)
	label(tile, "Subtitle", subtitle, 48, 27, textWidth, 13, 10, C.Muted, W.Medium)
	if wide then
		local badge = place("Frame", tile, "Badge", w - 58, 16, 20, 20, {
			BackgroundTransparency = 0,
			BackgroundColor3 = C.Red,
			Visible = false,
		})
		circle(badge)
		label(badge, "Count", "1", 0, 0, 20, 20, 10, C.White, W.ExtraBold, Center, { TextTruncate = Enum.TextTruncate.None })
		label(tile, "Chevron", "›", w - 30, 10, 18, 30, 22, C.Dim, W.Bold, Center, { TextTruncate = Enum.TextTruncate.None })
	end
	return tile
end

local INFO_ROWS = {
	{ "UserId", "User ID", "1234567890" },
	{ "AccountAge", "Account age", "3 yr 4 mo" },
	{ "Membership", "Membership", "Premium" },
	{ "Role", "Role", "ADMINISTRATOR" },
	{ "Community", "Community", "Community" },
	{ "InServer", "In this server", "12 min" },
	{ "Followers", "Followers", "0" },
	{ "Following", "Following", "12" },
	{ "Likes", "Likes received", "174" },
}

local function pageHeader(page, title)
	local back = iconButton(page, "BackButton", "‹", 18, 14, 34, 24)
	label(page, "PageTitle", title, 62, 14, 188, 34, 13, C.Text, W.ExtraBold, Center)
	iconButton(page, "CloseButton", "×", 260, 14, 34, 22)
	return back
end

local function bubbleSample(list, order, mine, text, width)
	local row = place("Frame", list, "Sample" .. order, 0, 0, 276, 34, { LayoutOrder = order })
	local x = if mine then 276 - width else 0
	local bubble = place("Frame", row, "Bubble", x, 0, width, 34, {
		BackgroundTransparency = if mine then 0 else 0.86,
		BackgroundColor3 = C.White,
	})
	corner(bubble, 15)
	if mine then
		gradient(bubble, C.Pink, C.Violet, 25)
	end
	label(bubble, "Text", text, 0, 0, width, 34, 12, C.Text, W.Medium, Center, { TextTruncate = Enum.TextTruncate.None })
	return row
end

-- Chat bubble templates: AutomaticSize grows the bubble with its text.
local function bubbleTemplate(list, name, mine)
	local row = Instance.new("Frame")
	apply(row, {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	add("UIListLayout", row, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = if mine then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local bubble = Instance.new("Frame")
	apply(bubble, {
		Name = "Bubble",
		BorderSizePixel = 0,
		BackgroundColor3 = C.White,
		BackgroundTransparency = if mine then 0 else 0.86,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(0, 0, 0, 0),
	})
	bubble.Parent = row
	add("UICorner", bubble, { CornerRadius = UDim.new(0, 15) })
	if mine then
		add("UIGradient", bubble, { Color = ColorSequence.new(C.Pink, C.Violet), Rotation = 25 })
	end
	add("UIPadding", bubble, {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	})
	local text = Instance.new("TextLabel")
	apply(text, {
		Name = "Text",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(0, 0, 0, 0),
		Text = "",
		TextColor3 = C.Text,
		FontFace = font(W.Medium),
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = if mine then Right else Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	text.Parent = bubble
	add("UISizeConstraint", text, { MaxSize = Vector2.new(180, 10000) })
	row.Parent = list.inst
	return row
end

---------------------------------------------------------------------------
-- Overhead nametag: name / role. PlayerMenuNametags clones this
-- for every character, so you can restyle it in Studio.
---------------------------------------------------------------------------

local function nametag()
	local tag = Instance.new("BillboardGui")
	apply(tag, {
		Name = "NametagTemplate",
		Size = UDim2.fromOffset(240, 56),
		StudsOffset = Vector3.new(0, 2.2, 0),
		ExtentsOffset = Vector3.new(0, 0.5, 0), -- the bottom edge sits at StudsOffset at any distance
		LightInfluence = 0,
		MaxDistance = 90,
		ResetOnSpawn = false,
		AlwaysOnTop = false,
		Enabled = false,
	})
	local root = { inst = tag, w = 240, h = 56 }
	local stack = place("Frame", root, "Stack", 0, 0, 240, 56)
	add("UIListLayout", stack, {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})

	local function textStroke(node, transparency, thickness)
		add("UIStroke", node, {
			Name = "TextStroke",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Color = C.Black,
			Transparency = transparency,
			Thickness = thickness,
		})
	end

	local name = label(stack, "PlayerName", SAMPLE.name, 0, 0, 240, 24, 20, C.White, W.ExtraBold, Center, {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 24),
	})
	gradient(name, Color3.fromRGB(255, 88, 168), Color3.fromRGB(255, 176, 222), 0)
	textStroke(name.inst, 0.2, 1.4)

	local role = chip(stack, "RoleChip", SAMPLE.role, 0, 0, 108, 17, 9, SAMPLE.roleColor, 0.3)
	apply(role.inst, { LayoutOrder = 2, Size = UDim2.fromOffset(108, 17) })
	role.inst.Label.TextColor3 = C.White
	role.inst.Label.Size = UDim2.new(1, 0, 1, 0)
	role.inst.Outline.Transparency = 0.2
	return tag
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

	-- Card --------------------------------------------------------------------
	local card = place("Frame", screen, "Card", 0, 0.5, CARD_W, CARD_H, {
		AnchorPoint = Vector2.new(0, 0.5),
		Visible = true,
		ZIndex = 3,
	})
	card.inst.Position = UDim2.new(0, 20, 0.5, 0)
	card.inst.Size = UDim2.fromOffset(CARD_W, CARD_H)
	add("UIScale", card, { Name = "ResponsiveScale", Scale = 1 })
	card.inst.BackgroundColor3 = C.Panel
	card.inst.BackgroundTransparency = CARD_TRANSPARENCY
	corner(card, 24)
	stroke(card, C.White, 0.7, 1.5)

	-- The player's community icon (PlayerMenuClient sets Image), dimmed, with a
	-- soft dark scrim so the text stays readable on top of it.
	local community = place("ImageLabel", card, "CommunityBackground", 0, 0, CARD_W, CARD_H, {
		Image = "",
		ImageTransparency = COMMUNITY_IMAGE_TRANSPARENCY,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 0,
	})
	corner(community, 24)
	local scrim = place("Frame", card, "CommunityScrim", 0, 0, CARD_W, CARD_H, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Black,
		ZIndex = 0,
	})
	corner(scrim, 24)
	gradient(scrim, C.White, C.White, 90, fade(0.8, 0.35))

	-- Home --------------------------------------------------------------------
	local home = place("Frame", card, "Home", 0, 0, CARD_W, CARD_H)

	local status = place("Frame", home, "StatusChip", 18, 17, 96, 24, {
		BackgroundTransparency = 0.86,
		BackgroundColor3 = C.Green,
	})
	circle(status)
	stroke(status, C.Green, 0.65)
	local statusDot = place("Frame", status, "Dot", 11, 8, 8, 8, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Green,
	})
	circle(statusDot)
	label(status, "Label", "IN SERVER", 25, 0, 68, 24, 9, C.Green, W.ExtraBold, Left, { TextTruncate = Enum.TextTruncate.None })

	local communityChip = place("Frame", home, "CommunityChip", 122, 17, 112, 24, {
		BackgroundTransparency = 0.86,
		BackgroundColor3 = C.White,
	})
	circle(communityChip)
	stroke(communityChip, C.White, 0.8)
	label(communityChip, "Label", SAMPLE.community, 0, 0, 112, 24, 9, C.Muted, W.Bold, Center, { TextTruncate = Enum.TextTruncate.None })

	iconButton(home, "CloseButton", "×", 260, 12, 34, 22)

	-- Avatar
	local avatar = place("Frame", home, "Avatar", 18, 58, 96, 96)
	local ring = place("Frame", avatar, "Ring", 0, 0, 96, 96)
	circle(ring)
	stroke(ring, SAMPLE.roleColor, 0, 3)
	local portrait = place("Frame", avatar, "Portrait", 7, 7, 82, 82, {
		BackgroundTransparency = 0.5,
		BackgroundColor3 = C.Black,
		ClipsDescendants = true,
	})
	circle(portrait)
	label(portrait, "Silhouette", "👤", 0, 0, 82, 82, 36, C.White, W.Regular, Center, {
		TextTransparency = 0.5,
		TextTruncate = Enum.TextTruncate.None,
	})
	place("ImageLabel", portrait, "Headshot", 0, 0, 82, 82, {
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 2,
	})
	place("ViewportFrame", portrait, "ModelView", 0, 0, 82, 82, {
		Ambient = Color3.fromRGB(170, 172, 190),
		LightColor = Color3.fromRGB(255, 248, 235),
		LightDirection = Vector3.new(-0.4, -0.6, -1),
		ZIndex = 3,
		Visible = false,
	})
	local onlineDot = place("Frame", avatar, "OnlineDot", 72, 72, 20, 20, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Green,
		ZIndex = 4,
	})
	circle(onlineDot)
	add("UIStroke", onlineDot, {
		Name = "Outline",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = C.Panel,
		Thickness = 3,
	})

	-- Identity
	local name = label(home, "DisplayName", SAMPLE.name, 128, 68, 166, 28, 23, C.Text, W.ExtraBold)
	apply(name.inst, { TextScaled = true })
	add("UITextSizeConstraint", name, { MaxTextSize = 23, MinTextSize = 11 })
	label(home, "Username", SAMPLE.username, 128, 98, 166, 16, 12, C.Muted, W.Medium)
	chip(home, "RoleChip", SAMPLE.role, 128, 122, 112, 24, 10, SAMPLE.roleColor)

	-- Stats
	local stats = place("Frame", home, "Stats", 18, 174, 276, 62)
	statTile(stats, "Friends", 0, 86, SAMPLE.friends, "FRIENDS")
	statTile(stats, "Followers", 95, 86, SAMPLE.followers, "FOLLOWERS")
	statTile(stats, "Like", 190, 86, "❤️ " .. SAMPLE.likes, "LIKES", true)

	-- Actions
	label(home, "ActionsLabel", "ACTIONS", 20, 252, 200, 12, 10, C.Dim, W.ExtraBold)
	local actions = place("Frame", home, "Actions", 18, 270, 276, 172)
	actionTile(actions, "Profile", 0, 0, 134, "👤", C.Violet, "Profile", "View details")
	actionTile(actions, "Carry", 142, 0, 134, "🤗", C.Amber, "Carry", "Piggyback ride")
	actionTile(actions, "AddFriend", 0, 60, 134, "➕", C.Green, "Add Friend", "Send request")
	actionTile(actions, "Follow", 142, 60, 134, "⭐", C.Pink, "Follow", "Follow player")
	actionTile(actions, "Chat", 0, 120, 276, "💬", C.Blue, "Private Chat", "Send a message", true)

	-- Profile page -------------------------------------------------------------
	local profile = place("Frame", card, "ProfilePage", 0, 0, CARD_W, CARD_H, { ZIndex = 2, Visible = false })
	pageHeader(profile, "PROFILE")
	local miniAvatar = place("ImageLabel", profile, "MiniAvatar", 18, 62, 56, 56, {
		BackgroundTransparency = 0.5,
		BackgroundColor3 = C.Black,
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
	})
	circle(miniAvatar)
	stroke(miniAvatar, SAMPLE.roleColor, 0, 2)
	label(miniAvatar, "Silhouette", "👤", 0, 0, 56, 56, 24, C.White, W.Regular, Center, {
		TextTransparency = 0.5,
		TextTruncate = Enum.TextTruncate.None,
	})
	label(profile, "MiniName", SAMPLE.name, 84, 68, 210, 24, 18, C.Text, W.ExtraBold)
	label(profile, "MiniUser", SAMPLE.username, 84, 94, 210, 16, 12, C.Muted, W.Medium)

	local rowHeight = 34
	local info = place("Frame", profile, "Info", 18, 136, 276, #INFO_ROWS * rowHeight, {
		BackgroundTransparency = GLASS,
		BackgroundColor3 = C.White,
	})
	corner(info, 16)
	stroke(info, C.White, 0.85)
	for i, row in INFO_ROWS do
		local line = place("Frame", info, "Row_" .. row[1], 0, (i - 1) * rowHeight, 276, rowHeight)
		label(line, "Key", row[2], 16, 0, 110, rowHeight, 11, C.Muted, W.SemiBold)
		label(line, "Value", row[3], 120, 0, 140, rowHeight, 12, C.Text, W.Bold, Right)
		if i > 1 then
			local rule = place("Frame", line, "Rule", 14, 0, 248, 1, { BackgroundTransparency = 0.88 })
			rule.inst.Size = UDim2.new(248 / 276, 0, 0, 1)
		end
	end

	-- Chat page ----------------------------------------------------------------
	local chat = place("Frame", card, "ChatPage", 0, 0, CARD_W, CARD_H, { ZIndex = 2, Visible = false })
	pageHeader(chat, SAMPLE.name)

	local messages = place("ScrollingFrame", chat, "Messages", 18, 62, 276, 326, {
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Pink,
		ScrollBarImageTransparency = 0.3,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	})
	add("UIListLayout", messages, {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	})
	bubbleSample(messages, 1, false, "Hey! Nice hat 😄", 120)
	bubbleSample(messages, 2, true, "Thanks! Want a ride?", 142)
	bubbleSample(messages, 3, false, "Yes please 🤗", 100)
	bubbleTemplate(messages, "BubbleTheirs", false)
	bubbleTemplate(messages, "BubbleMine", true)

	label(chat, "EmptyState", "Say hi 👋", 18, 190, 276, 20, 13, C.Muted, W.SemiBold, Center, {
		Visible = false,
		TextTruncate = Enum.TextTruncate.None,
	})

	local inputBar = place("Frame", chat, "InputBar", 18, 398, 276, 42)
	local field = place("Frame", inputBar, "Field", 0, 0, 228, 42, {
		BackgroundTransparency = 0.55,
		BackgroundColor3 = C.Black,
	})
	corner(field, 21)
	stroke(field, C.White, 0.85)
	local inputBox = place("TextBox", field, "InputBox", 16, 0, 200, 42, {
		Text = "",
		PlaceholderText = "Message...",
		PlaceholderColor3 = C.Dim,
		TextColor3 = C.Text,
		FontFace = font(W.Medium),
		TextSize = 12,
		TextXAlignment = Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
	})
	inputBox.inst.TextTruncate = Enum.TextTruncate.None
	local send = place("TextButton", inputBar, "SendButton", 234, 0, 42, 42, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.White,
		Text = "",
		AutoButtonColor = true,
	})
	circle(send)
	gradient(send, C.Pink, C.Violet, 25)
	label(send, "Label", "↑", 0, 0, 42, 40, 20, C.White, W.ExtraBold, Center, { TextTruncate = Enum.TextTruncate.None })

	-- Hearts float here (above every page)
	place("Frame", card, "FxLayer", 0, 0, CARD_W, CARD_H, { ZIndex = 20 })

	-- Toast -------------------------------------------------------------------
	local toast = place("TextButton", screen, "Toast", 0.5, 1, 330, 46, {
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 0.3,
		BackgroundColor3 = C.Panel,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 10,
		Visible = false,
	})
	toast.inst.Position = UDim2.new(0.5, 0, 1, -22)
	toast.inst.Size = UDim2.fromOffset(330, 46)
	add("UIScale", toast, { Name = "ResponsiveScale", Scale = 1 })
	corner(toast, 23)
	stroke(toast, C.White, 0.86)
	local toastDot = place("Frame", toast, "Dot", 20, 19, 8, 8, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Green,
	})
	circle(toastDot)
	label(toast, "Message", "You liked SweetPie ❤️", 40, 0, 276, 46, 13, C.Text, W.SemiBold)

	-- Carry request -------------------------------------------------------------
	local request = place("Frame", screen, "CarryRequest", 0.5, 0, 340, 104, {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 0.3,
		BackgroundColor3 = C.Panel,
		ZIndex = 9,
		Visible = false,
		ClipsDescendants = true,
	})
	request.inst.Position = UDim2.new(0.5, 0, 0, 16)
	request.inst.Size = UDim2.fromOffset(340, 104)
	add("UIScale", request, { Name = "ResponsiveScale", Scale = 1 })
	corner(request, 20)
	stroke(request, C.White, 0.86)
	local requestIcon = place("Frame", request, "Icon", 16, 14, 34, 34, {
		BackgroundTransparency = 0.8,
		BackgroundColor3 = C.Amber,
	})
	corner(requestIcon, 11)
	label(requestIcon, "Emoji", "🤗", 0, 0, 34, 34, 17, C.White, W.Regular, Center, { TextTruncate = Enum.TextTruncate.None })
	label(request, "Message", "SweetPie wants to carry you", 60, 12, 264, 20, 13, C.Text, W.Bold)
	label(request, "Detail", "Piggyback ride  •  15s", 60, 32, 264, 14, 10, C.Muted, W.Medium)
	local accept = place("TextButton", request, "Accept", 16, 58, 150, 34, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Green,
		Text = "",
		AutoButtonColor = true,
	})
	corner(accept, 17)
	label(accept, "Label", "ACCEPT", 0, 0, 150, 34, 12, Color3.fromRGB(6, 32, 20), W.ExtraBold, Center)
	local decline = place("TextButton", request, "Decline", 174, 58, 150, 34, {
		BackgroundTransparency = 0.9,
		BackgroundColor3 = C.White,
		Text = "",
		AutoButtonColor = true,
	})
	corner(decline, 17)
	stroke(decline, C.White, 0.88)
	label(decline, "Label", "DECLINE", 0, 0, 150, 34, 12, C.Muted, W.ExtraBold, Center)
	local timer = place("Frame", request, "Timer", 0, 101, 340, 3, {
		BackgroundTransparency = 0.9,
		BackgroundColor3 = C.White,
	})
	place("Frame", timer, "Fill", 0, 0, 340, 3, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Amber,
	})

	-- Carry bar (while carrying / being carried) ---------------------------------
	local bar = place("Frame", screen, "CarryBar", 0.5, 1, 300, 46, {
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 0.3,
		BackgroundColor3 = C.Panel,
		ZIndex = 8,
		Visible = false,
	})
	bar.inst.Position = UDim2.new(0.5, 0, 1, -78)
	bar.inst.Size = UDim2.fromOffset(300, 46)
	add("UIScale", bar, { Name = "ResponsiveScale", Scale = 1 })
	corner(bar, 23)
	stroke(bar, C.Amber, 0.55)
	label(bar, "Message", "🤗  Carrying SweetPie", 20, 0, 170, 46, 12, C.Text, W.Bold, Left, {
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local drop = place("TextButton", bar, "DropButton", 196, 7, 96, 32, {
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Amber,
		Text = "",
		AutoButtonColor = true,
	})
	corner(drop, 16)
	label(drop, "Label", "PUT DOWN", 0, 0, 96, 32, 11, Color3.fromRGB(38, 25, 4), W.ExtraBold, Center)

	-- Nametag + open event --------------------------------------------------------
	nametag().Parent = screenGui
	local openEvent = Instance.new("BindableEvent")
	openEvent.Name = "OpenPlayer"
	openEvent.Parent = screenGui

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
print("[PlayerMenuGui] Dibuat di StarterGui")

return gui
