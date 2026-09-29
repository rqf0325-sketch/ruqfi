--[[
	DonateAlertsClient (LocalScript inside StarterGui.DonateAlertsGui)

	Menampilkan notifikasi donasi yang dikirim server (DonateAlertsServer):
	antrean, animasi masuk/keluar, warna per tingkat donasi dari
	ReplicatedStorage.DonateAlerts.Config, suara, dan foto avatar donatur.
	Juga memasang perintah chat tes (/testdonate) untuk admin.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = script.Parent

local shared = ReplicatedStorage:WaitForChild("DonateAlerts")
local Config = require(shared:WaitForChild("Config"))
local Settings = Config.Settings
local remotes = shared:WaitForChild("Remotes")
local alertRemote = remotes:WaitForChild("DonateAlert")
local testRemote = remotes:WaitForChild("TestAlert")

local stack = gui:WaitForChild("Stack")
local template = stack:WaitForChild("Template")
local layout = stack:FindFirstChildOfClass("UIListLayout")

local COLORS = {
	White = Color3.new(1, 1, 1),
	Black = Color3.new(0, 0, 0),
	Muted = Color3.fromRGB(140, 149, 166),
}

local ENTER_TIME = 0.45
local LEAVE_TIME = 0.35
local SHIFT_TIME = 0.3
local RUSH_FACTOR = 0.55 -- lama tampil dikalikan ini kalau antrean panjang
local MARGIN = 8 -- jarak stack ke tepi layar (pixel)
local SIDE_MARGIN = 12

-- Kartu contoh dari Studio tidak dipakai saat game berjalan.
for _, child in stack:GetChildren() do
	if string.sub(child.Name, 1, 7) == "Sample_" then
		child:Destroy()
	end
end

---------------------------------------------------------------------------
-- Posisi: stack dipindah ke Settings.Position
---------------------------------------------------------------------------

-- side: sisi layar tempat kartu meluncur masuk (0 = dari atas / bawah)
local PLACEMENTS = {
	TopCenter = { x = 0.5, top = true, side = 0 },
	TopLeft = { x = 0, top = true, side = -1 },
	TopRight = { x = 1, top = true, side = 1 },
	BottomCenter = { x = 0.5, top = false, side = 0 },
	BottomLeft = { x = 0, top = false, side = -1 },
	BottomRight = { x = 1, top = false, side = 1 },
}

local placement = PLACEMENTS[Settings.Position]
if not placement then
	warn(`[DonateAlerts] Settings.Position "{tostring(Settings.Position)}" tidak dikenal, memakai TopCenter`)
	placement = PLACEMENTS.TopCenter
end

local edgeY = if placement.top then 0 else 1
stack.AnchorPoint = Vector2.new(placement.x, edgeY)
stack.Position = UDim2.new(placement.x, placement.side * -SIDE_MARGIN, edgeY, if placement.top then MARGIN else -MARGIN)
if layout then
	layout.VerticalAlignment = if placement.top then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
end

-- Posisi kartu (dalam ukuran slot) saat belum / sudah tidak terlihat.
local HIDDEN = if placement.side ~= 0
	then UDim2.fromScale(placement.side * 1.3, 0)
	else UDim2.fromScale(0, if placement.top then -1.6 else 1.6)
-- Alert lama bergeser satu slot ke arah ini saat alert baru masuk; kebalikannya saat ada yang hilang.
local INSERT_SHIFT = if placement.top then -1 else 1

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function tween(instance, time, props, style, direction)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function hex(color)
	return "#" .. color:ToHex()
end

-- 25000 -> "Rp 25.000"
local function formatAmount(amount)
	local digits = string.format("%.0f", math.floor(amount))
	local parts = {}
	while #digits > 3 do
		table.insert(parts, 1, string.sub(digits, -3))
		digits = string.sub(digits, 1, -4)
	end
	table.insert(parts, 1, digits)
	local number = table.concat(parts, Settings.ThousandsSeparator)
	if Settings.CurrencyPosition == "Suffix" then
		return `{number} {Settings.Currency}`
	end
	return `{Settings.Currency} {number}`
end

local tiers = table.clone(Config.Tiers)
table.sort(tiers, function(a, b)
	return a.Min < b.Min
end)

local function tierFor(amount)
	local found = tiers[1]
	for _, tier in tiers do
		if amount >= tier.Min then
			found = tier
		end
	end
	return found
end

local sounds = {}
local function playSound(id)
	if not Settings.SoundEnabled or not id or id == "" then
		return
	end
	local sound = sounds[id]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Volume = Settings.Volume
		sound.Parent = gui
		sounds[id] = sound
	end
	sound:Play()
end

---------------------------------------------------------------------------
-- Satu notifikasi
---------------------------------------------------------------------------

local visible = {} -- alert yang sedang di layar, paling lama dulu
local queue = {}
local counter = 0
local pump

-- Pindahkan alert satu slot dari posisinya sekarang lalu geser kembali,
-- supaya alert lain tidak "melompat" saat susunan list berubah.
local function shift(entry, slots)
	if entry.shiftTween then
		entry.shiftTween:Cancel()
	end
	local position = entry.mover.Position
	entry.mover.Position = UDim2.fromScale(position.X.Scale, position.Y.Scale + slots)
	entry.shiftTween = tween(entry.mover, SHIFT_TIME, { Position = UDim2.new() })
end

local function dismiss(entry)
	if entry.closing then
		return
	end
	entry.closing = true

	local leave = tween(entry.card, LEAVE_TIME, { Position = HIDDEN }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	leave.Completed:Once(function()
		local index = table.find(visible, entry)
		if index then
			table.remove(visible, index)
		end
		entry.slot:Destroy()
		if index then
			for i = 1, index - 1 do
				shift(visible[i], -INSERT_SHIFT)
			end
		end
		pump()
	end)
end

local function loadAvatar(entry, userId)
	local ok, image = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	if ok and image ~= "" and entry.avatar.Parent then
		entry.avatar.Image = image
		entry.avatar.Visible = true
		entry.emoji.Visible = false
	end
end

local function show(alert)
	counter += 1
	local tier = tierFor(alert.amount)
	local color = tier.Color

	local slot = template:Clone()
	slot.Name = "Alert"
	-- Yang terbaru selalu paling dekat dengan tepi layar.
	slot.LayoutOrder = if placement.top then -counter else counter
	slot.Visible = true
	local mover = slot:WaitForChild("Mover")
	local card = mover:WaitForChild("Card")
	local body = card:WaitForChild("Body")
	local badge = card:WaitForChild("IconBadge")
	local messageLabel = body:WaitForChild("Message")

	local entry = {
		slot = slot,
		mover = mover,
		card = card,
		avatar = badge:WaitForChild("Avatar"),
		emoji = badge:WaitForChild("Emoji"),
	}

	-- Warna sesuai tingkat donasi
	card:FindFirstChildOfClass("UIStroke").Color = color
	card:WaitForChild("Glow").BackgroundColor3 = color
	badge:FindFirstChildOfClass("UIGradient").Color =
		ColorSequence.new(color:Lerp(COLORS.White, 0.25), color:Lerp(COLORS.Black, 0.25))
	entry.emoji.Text = tier.Emoji
	local amountLabel = body:WaitForChild("Amount")
	amountLabel.Text = formatAmount(alert.amount)
	amountLabel.TextColor3 = color

	local tag = body:WaitForChild("Tag")
	local hasTag = tier.Tag ~= nil and tier.Tag ~= ""
	tag.Visible = hasTag
	if hasTag then
		tag.BackgroundColor3 = color
		tag:FindFirstChildOfClass("UIStroke").Color = color
		local tagLabel = tag:WaitForChild("Label")
		tagLabel.Text = tier.Tag
		tagLabel.TextColor3 = color
	end

	-- Judul: "<nama> baru saja bagi-bagi" atau "<nama> bagi-bagi ke <target>"
	local title = `<font color="{hex(COLORS.White)}">{escape(alert.donor)}</font> `
	if alert.target ~= "" then
		title ..= `<font color="{hex(COLORS.Muted)}">{escape(Settings.TargetHeadline)}</font> <font color="{hex(color)}">{escape(alert.target)}</font>`
	else
		title ..= `<font color="{hex(COLORS.Muted)}">{escape(Settings.Headline)}</font>`
	end
	body:WaitForChild("Title").Text = title

	-- Pesan (maksimal 2 baris); tanpa pesan, teks digeser ke tengah kartu.
	local hasMessage = alert.message ~= ""
	messageLabel.Visible = hasMessage
	messageLabel.Text = `“{alert.message}”`
	body.Position = UDim2.fromScale(body.Position.X.Scale, if hasMessage then 0 else 0.09)
	local sizeLimit = messageLabel:FindFirstChildOfClass("UITextSizeConstraint")
	local function fitMessage()
		local height = card.AbsoluteSize.Y
		if sizeLimit and height > 0 then
			sizeLimit.MaxTextSize = math.max(6, math.floor(height * 12 / 100 + 0.5))
		end
	end
	fitMessage()
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitMessage)

	-- Alert yang sudah ada bergeser satu slot; alert baru meluncur masuk.
	for _, other in visible do
		shift(other, INSERT_SHIFT)
	end
	table.insert(visible, entry)

	card.Position = HIDDEN
	slot.Parent = stack
	tween(card, ENTER_TIME, { Position = UDim2.new() }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local duration = tier.Duration or 5
	if #queue >= Settings.RushQueueAt then
		duration *= RUSH_FACTOR
	end
	local fill = card:WaitForChild("Progress"):WaitForChild("Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	tween(fill, duration, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	task.delay(duration, dismiss, entry)

	playSound(tier.Sound or Settings.Sound)
	if alert.userId then
		task.spawn(loadAvatar, entry, alert.userId)
	end
end

function pump()
	while #visible < Settings.MaxVisible and #queue > 0 do
		show(table.remove(queue, 1))
	end
end

---------------------------------------------------------------------------
-- Alert dari server
---------------------------------------------------------------------------

local function text(value)
	return if typeof(value) == "string" then value else ""
end

alertRemote.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" or typeof(data.amount) ~= "number" or data.amount ~= data.amount then
		return
	end
	local donor = text(data.donor)
	local alert = {
		donor = if donor ~= "" then donor else Settings.AnonymousName,
		amount = math.max(0, data.amount),
		message = text(data.message),
		target = text(data.target),
		userId = if typeof(data.userId) == "number" and data.userId > 0 then data.userId else nil,
	}
	if #queue >= Settings.MaxQueue then
		table.remove(queue, 1)
	end
	table.insert(queue, alert)
	pump()
end)

---------------------------------------------------------------------------
-- Perintah chat tes: "/testdonate 25000 Semangat!" (server memeriksa admin)
---------------------------------------------------------------------------

local function runTest(message)
	local rest = string.gsub(message, "^%s*%S+%s*", "")
	local amount, note = string.match(rest, "^(%d+)%s*(.*)$")
	testRemote:FireServer(tonumber(amount), note or rest)
end

local commandReady = false
local function setupTestCommand()
	local alias = Settings.TestCommand
	if commandReady or not alias or alias == "" then
		return
	end
	commandReady = true

	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local command = Instance.new("TextChatCommand")
		command.Name = "DonateAlertsTest"
		command.PrimaryAlias = alias
		command.Triggered:Connect(function(_, message)
			runTest(message)
		end)
		command.Parent = TextChatService
	else
		player.Chatted:Connect(function(message)
			local first = string.match(message, "^%s*(%S+)")
			if first and string.lower(first) == string.lower(alias) then
				runTest(message)
			end
		end)
	end
end

-- Server menandai admin lewat attribute.
if player:GetAttribute("DonateAdmin") then
	setupTestCommand()
end
player:GetAttributeChangedSignal("DonateAdmin"):Connect(function()
	if player:GetAttribute("DonateAdmin") then
		setupTestCommand()
	end
end)
