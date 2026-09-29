--[[
	DonateAlertsGui — tampilan notifikasi donasi (tanpa script).

	tools/build.luau menjalankan file ini, menambahkan LocalScript
	src/client/DonateAlertsClient.luau, lalu menyimpan hasilnya ke
	StarterGui/DonateAlertsGui.rbxmx. File ini juga bisa di-paste ke
	Command Bar Studio untuk membuat tampilannya saja.

	Kartu Sample_* di bawah hanya untuk tampilan di Studio; saat game
	berjalan, DonateAlertsClient menghapusnya dan membuat notifikasi dari
	Stack.Template. Warna, emoji, dan label tiap kartu diganti sesuai
	tingkat donasi di ReplicatedStorage.DonateAlerts.Config.

	Semua ukuran memakai Scale + UIAspectRatioConstraint, jadi tampilannya
	sama di PC, tablet, dan HP. Angka-angka di bawah ditulis dalam "pixel desain"
	(kartu 340 x 100) lalu diubah otomatis menjadi Scale.
]]

local GUI_NAME = "DonateAlertsGui"
local FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"

local C = {
	PanelTop = Color3.fromRGB(28, 33, 45),
	PanelBottom = Color3.fromRGB(11, 13, 18),
	Track = Color3.fromRGB(40, 45, 60),
	Text = Color3.fromRGB(245, 246, 248),
	Muted = Color3.fromRGB(140, 149, 166),
	Green = Color3.fromRGB(61, 220, 151),
	Purple = Color3.fromRGB(139, 108, 255),
	Amber = Color3.fromRGB(255, 190, 56),
	White = Color3.new(1, 1, 1),
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

local function hex(color)
	return "#" .. color:ToHex():upper()
end

---------------------------------------------------------------------------
-- Alert card
---------------------------------------------------------------------------

local CARD_W, CARD_H = 340, 100
local SLOT_W, SLOT_H = CARD_W, CARD_H + 8

-- Every alert lives in a slot that reserves the room (card + gap) in the list.
-- The card inside it is what slides in and out.
local function alertSlot(stack, name, order, data)
	local slot = place("Frame", stack, name, 0, 0, SLOT_W, SLOT_H, { LayoutOrder = order })
	slot.inst.Position = UDim2.new()
	slot.inst.Size = UDim2.fromScale(1, 1)
	add("UIAspectRatioConstraint", slot, { AspectRatio = SLOT_W / SLOT_H })

	-- DonateAlertsClient moves the Mover to animate the other alerts up and
	-- down, and the Card inside it to slide in and out.
	local mover = place("Frame", slot, "Mover", 0, 0, SLOT_W, SLOT_H)

	local card = place("Frame", mover, "Card", 0, 0, CARD_W, CARD_H, {
		BackgroundTransparency = 0.03,
	})
	corner(card, 16)
	stroke(card, data.color, 0.35, 1.5)
	gradient(card, C.PanelTop, C.PanelBottom, 90)

	-- Soft tint from the left edge; DonateAlertsClient recolors it per tier.
	local glow = place("Frame", card, "Glow", 0, 0, CARD_W, CARD_H, {
		BackgroundTransparency = 0,
		BackgroundColor3 = data.color,
		ZIndex = 0,
	})
	corner(glow, 16)
	gradient(glow, C.White, C.White, 0, fade(0.82, 1))

	-- Icon (emoji, or the donor's avatar when the alert has a userId)
	local badge = place("Frame", card, "IconBadge", 16, 22, 56, 56, { BackgroundTransparency = 0 })
	corner(badge, 28)
	gradient(badge, data.color:Lerp(C.White, 0.25), data.color:Lerp(Color3.new(0, 0, 0), 0.25), 45)
	stroke(badge, C.White, 0.8)
	label(badge, "Emoji", data.emoji, 14, 12, 28, 32, C.White, W.Regular, Center)
	local avatar = place("ImageLabel", badge, "Avatar", 0, 0, 56, 56, {
		Image = "",
		ZIndex = 2,
		Visible = false,
	})
	corner(avatar, 28)

	-- Texts
	local body = place("Frame", card, "Body", 84, 0, 242, CARD_H)
	label(
		body,
		"Title",
		`<font color="{hex(C.White)}">{data.donor}</font> <font color="{hex(C.Muted)}">baru saja bagi-bagi</font>`,
		0,
		14,
		242,
		14,
		C.Text,
		W.Bold,
		Left,
		{ RichText = true }
	)
	label(body, "Amount", data.amount, 0, 32, 172, 24, data.color, W.ExtraBold)

	local tag = place("Frame", body, "Tag", 180, 36, 62, 18, {
		BackgroundTransparency = 0.82,
		BackgroundColor3 = data.color,
		Visible = data.tag ~= "",
	})
	corner(tag, 6)
	stroke(tag, data.color, 0.6)
	label(tag, "Label", data.tag, 0, 4, 62, 10, data.color, W.ExtraBold, Center)

	-- Two lines at most; DonateAlertsClient keeps MaxTextSize at 12 design pixels.
	local message = label(body, "Message", data.message, 0, 62, 242, 26, C.Muted, W.Medium, Left, {
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	add("UITextSizeConstraint", message, { MaxTextSize = 12, MinTextSize = 1 })

	-- Countdown bar
	local track = place("Frame", card, "Progress", 16, 92, 308, 3, {
		BackgroundTransparency = 0.9,
	})
	corner(track, 1.5)
	local fill = place("Frame", track, "Fill", 0, 0, 308 * data.progress, 3, {
		BackgroundTransparency = 0,
		BackgroundColor3 = data.color,
	})
	corner(fill, 1.5)

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
	local stack = place("Frame", screen, "Stack", 0.5, 0, 0.32, 1)
	stack.w, stack.h = SLOT_W, 1000
	stack.inst.AnchorPoint = Vector2.new(0.5, 0)
	stack.inst.Position = UDim2.new(0.5, 0, 0, 8)
	stack.inst.Size = UDim2.new(0.32, 0, 1, -16)
	add("UISizeConstraint", stack, { MinSize = Vector2.new(300, 0), MaxSize = Vector2.new(400, 100000) })
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
