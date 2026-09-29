--[[
	DonateAlertsGui — tampilan notifikasi donasi (tanpa script).

	tools/build.luau menjalankan file ini, menambahkan LocalScript
	src/client/DonateAlertsClient.luau, lalu menyimpan hasilnya ke
	StarterGui/DonateAlertsGui.rbxmx. File ini juga bisa di-paste ke
	Command Bar Studio untuk membuat tampilannya saja.

	Kartu Sample_* di bawah hanya untuk tampilan di Studio; saat game
	berjalan, DonateAlertsClient menghapusnya dan membuat notifikasi dari
	Stack.Template. Warna, emoji, label, dan efek tiap kartu diganti sesuai
	tingkat donasi di ReplicatedStorage.DonateAlerts.Config. Semua yang
	bergerak (border berputar, kilau, aura, cincin avatar, angka berhitung,
	percikan, confetti) dijalankan oleh DonateAlertsClient; di Studio kartu
	contoh tampil diam.

	Semua ukuran memakai Scale + UIAspectRatioConstraint, jadi tampilannya
	sama di PC, tablet, dan HP. Angka-angka di bawah ditulis dalam "pixel desain"
	(kartu 380 x 124) lalu diubah otomatis menjadi Scale.
]]

local GUI_NAME = "DonateAlertsGui"
local FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"

local C = {
	PanelTop = Color3.fromRGB(33, 38, 54),
	PanelBottom = Color3.fromRGB(9, 11, 17),
	Track = Color3.fromRGB(40, 45, 60),
	Text = Color3.fromRGB(245, 246, 248),
	Muted = Color3.fromRGB(150, 158, 175),
	OnTag = Color3.fromRGB(20, 14, 4),
	Green = Color3.fromRGB(61, 220, 151),
	Purple = Color3.fromRGB(139, 108, 255),
	Amber = Color3.fromRGB(255, 190, 56),
	White = Color3.new(1, 1, 1),
	Black = Color3.new(0, 0, 0),
}

local W = Enum.FontWeight
local Left, Center = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center

-- Contoh isi untuk tampilan di Studio (diganti Config saat game berjalan).
local SAMPLES = {
	{
		donor = "Budi Santoso",
		amount = "Rp 5.000",
		message = "“Semangat terus bang, gas!”",
		emoji = "🎁",
		color = C.Green,
		tag = "",
		progress = 0.9,
	},
	{
		donor = "Nadia",
		amount = "Rp 50.000",
		message = "“Buat beli kopi, jangan lupa istirahat ya”",
		emoji = "🔥",
		color = C.Purple,
		tag = "HYPE",
		progress = 0.6,
	},
	{
		donor = "Sultan Andi",
		amount = "Rp 100.000",
		message = "“Bagi-bagi rezeki buat semua!”",
		emoji = "👑",
		color = C.Amber,
		tag = "SULTAN",
		progress = 0.3,
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

-- Puts a node's center at (cx, cy) so UIScale grows it from the middle.
local function centerAt(node, parent, cx, cy)
	node.inst.AnchorPoint = Vector2.new(0.5, 0.5)
	node.inst.Position = UDim2.fromScale(cx / parent.w, cy / parent.h)
end

-- The color formulas below are repeated in DonateAlertsClient (per tier).
-- Border: a bright highlight travels around the edge while the gradient rotates.
local function borderColors(color)
	local bright = color:Lerp(C.White, 0.7)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, bright),
		ColorSequenceKeypoint.new(0.3, color),
		ColorSequenceKeypoint.new(0.55, color:Lerp(C.Black, 0.5)),
		ColorSequenceKeypoint.new(0.8, color),
		ColorSequenceKeypoint.new(1, bright),
	})
end

local function badgeColors(color)
	return ColorSequence.new(color:Lerp(C.White, 0.3), color:Lerp(C.Black, 0.3))
end

-- Gold-leaf look: lighter on top, full color at the bottom.
local function metalColors(color)
	return ColorSequence.new(color:Lerp(C.White, 0.5), color)
end

---------------------------------------------------------------------------
-- Alert card
---------------------------------------------------------------------------

local CARD_W, CARD_H = 380, 124
local SLOT_W, SLOT_H = CARD_W, CARD_H + 14
local RADIUS = 20

-- Every alert lives in a slot that reserves the room (card + gap) in the list.
-- Inside it, the Mover shifts to animate the other alerts up and down, and the
-- Card inside the Mover slides in and out.
local function alertSlot(stack, name, order, data)
	local slot = place("Frame", stack, name, 0, 0, SLOT_W, SLOT_H, { LayoutOrder = order })
	slot.inst.Position = UDim2.new()
	slot.inst.Size = UDim2.fromScale(1, 1)
	add("UIAspectRatioConstraint", slot, { AspectRatio = SLOT_W / SLOT_H })

	local mover = place("Frame", slot, "Mover", 0, 0, SLOT_W, SLOT_H)

	-- Aura: three soft rounded layers behind the card, in the tier color.
	local aura = place("Frame", mover, "Aura", 0, 0, CARD_W, CARD_H, { ZIndex = 0 })
	local AURA_SPREAD = { 5, 10, 17 }
	local AURA_TRANSPARENCY = { 0.84, 0.92, 0.965 }
	for i, spread in AURA_SPREAD do
		local layer = place("Frame", aura, "Layer" .. i, -spread, -spread, CARD_W + spread * 2, CARD_H + spread * 2, {
			BackgroundTransparency = AURA_TRANSPARENCY[i],
			BackgroundColor3 = data.color,
		})
		corner(layer, RADIUS + spread)
	end

	local card = place("Frame", mover, "Card", 0, 0, CARD_W, CARD_H, {
		BackgroundTransparency = 0.02,
		ZIndex = 1,
	})
	corner(card, RADIUS)
	gradient(card, C.PanelTop, C.PanelBottom, 90)

	-- Border: white stroke tinted by the gradient inside it.
	local border = stroke(card, C.White, 0, 2)
	add("UIGradient", { inst = border }, { Color = borderColors(data.color), Rotation = 30 })

	-- Soft tint from the left edge
	local glow = place("Frame", card, "Glow", 0, 0, CARD_W, CARD_H, {
		BackgroundTransparency = 0,
		BackgroundColor3 = data.color,
		ZIndex = 0,
	})
	corner(glow, RADIUS)
	gradient(glow, C.White, C.White, 0, fade(0.8, 1))

	-- Glass highlight along the top edge
	local topLight = place("Frame", card, "TopLight", 28, 1.5, CARD_W - 56, 1, {
		BackgroundTransparency = 0,
		ZIndex = 1,
	})
	gradient(
		topLight,
		C.White,
		C.White,
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
	)

	-- Shine: a diagonal band of light that sweeps over the card (Offset is animated).
	local shine = place("Frame", card, "Shine", 0, 0, CARD_W, CARD_H, {
		BackgroundTransparency = 0,
		ZIndex = 5,
	})
	corner(shine, RADIUS)
	gradient(
		shine,
		C.White,
		C.White,
		20,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.8),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	)

	-- Icon: an emoji (or the donor's avatar) inside a rotating ring
	local ring = place("Frame", card, "Ring", 0, 0, 78, 78, { ZIndex = 2 })
	centerAt(ring, card, 52, 62)
	corner(ring, 39)
	local ringStroke = stroke(ring, C.White, 0, 2.5)
	add("UIGradient", { inst = ringStroke }, { Color = borderColors(data.color), Rotation = 0 })
	add("UIScale", ring, { Scale = 1 })

	local badge = place("Frame", card, "IconBadge", 0, 0, 64, 64, {
		BackgroundTransparency = 0,
		ZIndex = 2,
	})
	centerAt(badge, card, 52, 62)
	corner(badge, 32)
	add("UIGradient", badge, { Color = badgeColors(data.color), Rotation = 45 })
	stroke(badge, C.White, 0.8)
	add("UIScale", badge, { Scale = 1 })
	label(badge, "Emoji", data.emoji, 15, 13, 34, 38, C.White, W.Regular, Center)
	local avatar = place("ImageLabel", badge, "Avatar", 0, 0, 64, 64, {
		Image = "",
		ZIndex = 2,
		Visible = false,
	})
	corner(avatar, 32)

	-- Texts
	local body = place("Frame", card, "Body", 104, 0, 260, CARD_H, { ZIndex = 2 })
	label(body, "Donor", data.donor, 0, 14, 260, 17, C.Text, W.ExtraBold)
	label(body, "Headline", "baru saja bagi-bagi", 0, 33, 260, 11, C.Muted, W.Medium, Left, { RichText = true })

	local amount = label(body, "Amount", data.amount, 0, 48, 260, 32, C.White, W.ExtraBold)
	amount.inst.AnchorPoint = Vector2.new(0, 0.5)
	amount.inst.Position = UDim2.fromScale(0, (48 + 16) / body.h)
	add("UIGradient", amount, { Color = metalColors(data.color), Rotation = 90 })
	add("UIScale", amount, { Scale = 1 })

	-- Two lines at most; DonateAlertsClient keeps MaxTextSize at 12 design pixels.
	local message = label(body, "Message", data.message, 0, 84, 260, 24, C.Muted, W.Medium, Left, {
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	add("UITextSizeConstraint", message, { MaxTextSize = 12, MinTextSize = 1 })

	-- Tier ribbon, pinned across the top-right border
	local tag = place("Frame", card, "Tag", CARD_W - 108, -6, 92, 20, {
		BackgroundTransparency = 0,
		ZIndex = 7,
		Visible = data.tag ~= "",
	})
	corner(tag, 7)
	gradient(tag, data.color:Lerp(C.White, 0.35), data.color, 90)
	stroke(tag, C.Black, 0.65)
	label(tag, "Label", data.tag, 0, 5, 92, 10, C.OnTag, W.ExtraBold, Center)

	-- Countdown bar
	local track = place("Frame", card, "Progress", 18, 113, CARD_W - 36, 3, {
		BackgroundTransparency = 0.88,
		ZIndex = 2,
	})
	corner(track, 1.5)
	local fill = place("Frame", track, "Fill", 0, 0, (CARD_W - 36) * data.progress, 3, {
		BackgroundTransparency = 0,
		BackgroundColor3 = data.color,
	})
	corner(fill, 1.5)

	-- Sparkles are created here at runtime by DonateAlertsClient.
	place("Frame", card, "Fx", 0, 0, CARD_W, CARD_H, { ZIndex = 6 })

	return slot
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function build()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10
	screenGui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local screen = { inst = screenGui, w = 1, h = 1 }

	-- Column that holds the alerts. DonateAlertsClient moves it to
	-- Config.Settings.Position; TopCenter is the default shown here.
	local stack = place("Frame", screen, "Stack", 0.5, 0, 0.34, 1)
	stack.w, stack.h = SLOT_W, 1000
	stack.inst.AnchorPoint = Vector2.new(0.5, 0)
	stack.inst.Position = UDim2.new(0.5, 0, 0, 14)
	stack.inst.Size = UDim2.new(0.34, 0, 1, -28)
	add("UISizeConstraint", stack, { MinSize = Vector2.new(320, 0), MaxSize = Vector2.new(440, 100000) })
	add("UIListLayout", stack, {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(),
	})

	for i, data in SAMPLES do
		alertSlot(stack, "Sample_" .. i, -i, data)
	end

	-- Cloned by DonateAlertsClient for every donation.
	local template = alertSlot(stack, "Template", 0, {
		donor = "Donatur",
		amount = "Rp 0",
		message = "",
		emoji = "🎁",
		color = C.Green,
		tag = "",
		progress = 1,
	})
	template.inst.Visible = false

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
print("[DonateAlertsGui] Dibuat di StarterGui")

return gui
