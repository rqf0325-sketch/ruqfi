--[[
	DonateAlertsClient (LocalScript inside StarterGui.DonateAlertsGui)

	Menampilkan notifikasi donasi yang dikirim server (DonateAlertsServer):
	antrean, animasi masuk/keluar, warna per tingkat donasi dari
	ReplicatedStorage.DonateAlerts.Config, suara, dan foto avatar donatur.
	Efek "mewah": border berputar, kilau yang menyapu kartu, aura cahaya,
	cincin avatar berdenyut, angka donasi berhitung naik, percikan, dan confetti
	untuk donasi besar (Settings.Effects = false mematikan semuanya kecuali
	animasi masuk/keluar). Juga memasang perintah chat tes (/testdonate) untuk admin.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")
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
	Gold = Color3.fromRGB(255, 214, 102),
}

local DESIGN_W, DESIGN_H = 380, 124 -- ukuran kartu di GUI (pixel desain)
local DESIGN_SLOT_H = DESIGN_H + 14 -- kartu + jarak ke kartu berikutnya
local AMOUNT_SIZE = 32 -- tinggi teks jumlah di GUI (pixel desain)
local ENTER_TIME = 0.5
local LEAVE_TIME = 0.35
local SHIFT_TIME = 0.3
local RUSH_FACTOR = 0.55 -- lama tampil dikalikan ini kalau antrean panjang
local MARGIN = 14 -- jarak stack ke tepi layar (pixel)
local SIDE_MARGIN = 12
local MAX_PARTICLES = 160 -- percikan + confetti yang boleh hidup bersamaan
local EFFECTS = Settings.Effects ~= false

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

-- Rumus warna yang sama dengan src/gui/DonateAlertsGui.luau.
local function borderColors(color)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(COLORS.White, 0.7)),
		ColorSequenceKeypoint.new(0.3, color),
		ColorSequenceKeypoint.new(0.55, color:Lerp(COLORS.Black, 0.5)),
		ColorSequenceKeypoint.new(0.8, color),
		ColorSequenceKeypoint.new(1, color:Lerp(COLORS.White, 0.7)),
	})
end

local tiers = table.clone(Config.Tiers)
table.sort(tiers, function(a, b)
	return a.Min < b.Min
end)

local function tierFor(amount)
	local found, rank = tiers[1], 1
	for index, tier in tiers do
		if amount >= tier.Min then
			found, rank = tier, index
		end
	end
	return found, rank
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
-- Percikan cahaya (di dalam kartu) dan confetti (di seluruh layar)
---------------------------------------------------------------------------

local liveParticles = 0
local confettiLayer = Instance.new("Frame")
confettiLayer.Name = "Confetti"
confettiLayer.BackgroundTransparency = 1
confettiLayer.BorderSizePixel = 0
confettiLayer.Size = UDim2.fromScale(1, 1)
confettiLayer.ZIndex = 100
confettiLayer.Parent = gui

-- Wajib dipanggil setiap membuat partikel; melepas jatahnya dan menghapus partikel
-- setelah `lifetime` detik, apa pun yang terjadi pada kartunya.
local function reserveParticle(piece, lifetime)
	liveParticles += 1
	task.delay(lifetime, function()
		liveParticles -= 1
		piece:Destroy()
	end)
end

-- Berlian kecil yang muncul lalu naik sambil mengecil.
local function sparkle(entry, color)
	if liveParticles >= MAX_PARTICLES then
		return
	end
	local size = 0.014 + math.random() * 0.018 -- lebar sebagai bagian dari lebar kartu
	local x, y = 0.04 + math.random() * 0.92, 0.1 + math.random() * 0.8
	local lifetime = 0.8 + math.random() * 0.5

	local piece = Instance.new("Frame")
	piece.AnchorPoint = Vector2.new(0.5, 0.5)
	piece.BorderSizePixel = 0
	piece.BackgroundColor3 = if math.random() < 0.5 then COLORS.White else color:Lerp(COLORS.White, 0.55)
	piece.Rotation = 45
	piece.Size = UDim2.fromScale(size, size * DESIGN_W / DESIGN_H) -- persegi (bukan persegi panjang) di layar
	piece.Position = UDim2.fromScale(x, y)
	piece.Parent = entry.fx
	reserveParticle(piece, lifetime + 0.1)

	tween(piece, lifetime, {
		Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.06, y - 0.3),
		Size = UDim2.new(),
		BackgroundTransparency = 1,
		Rotation = 135,
	})
end

local function confetti(color, count)
	local centerX = if placement.side == 0 then 0.5 elseif placement.side < 0 then 0.2 else 0.8
	local spread = if placement.side == 0 then 0.3 else 0.2
	local palette = {
		color,
		color:Lerp(COLORS.White, 0.5),
		COLORS.White,
		COLORS.Gold,
		color:Lerp(COLORS.Black, 0.2),
	}
	for _ = 1, count do
		if liveParticles >= MAX_PARTICLES then
			return
		end
		local x = math.clamp(centerX + (math.random() - 0.5) * 2 * spread, 0.02, 0.98)
		local duration = 2.2 + math.random() * 1.4
		local delay = math.random() * 0.6
		local spin = (if math.random() < 0.5 then -1 else 1) * math.random(360, 900)

		local piece = Instance.new("Frame")
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = palette[math.random(#palette)]
		piece.Size = UDim2.fromOffset(math.random(5, 9), math.random(9, 15))
		piece.Position = UDim2.fromScale(x, -0.06)
		piece.Rotation = math.random(0, 360)
		piece.Visible = false
		piece.Parent = confettiLayer
		reserveParticle(piece, duration + delay + 0.2)

		task.delay(delay, function()
			piece.Visible = true
			tween(piece, duration, {
				Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.14, 1.08),
				Rotation = piece.Rotation + spin,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
	end
end

---------------------------------------------------------------------------
-- Angka donasi berhitung naik
---------------------------------------------------------------------------

-- Ukuran teks terbesar yang masih muat di label untuk teks akhir. Dikunci selama
-- angka berhitung supaya hurufnya tidak berubah ukuran setiap kali digitnya bertambah.
local function fitAmountSize(card, label, finalText)
	local maxSize = math.floor(AMOUNT_SIZE * card.AbsoluteSize.X / DESIGN_W + 0.5)
	local boxWidth = label.AbsoluteSize.X
	if maxSize < 6 or boxWidth <= 0 then
		return nil
	end
	local ok, bounds = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = finalText
		params.Font = label.FontFace
		params.Size = maxSize
		params.Width = 10000
		return TextService:GetTextBoundsAsync(params)
	end)
	local width = if ok then bounds.X else #finalText * maxSize * 0.65
	if width <= boxWidth then
		return maxSize
	end
	return math.max(6, math.floor(maxSize * boxWidth / width))
end

local function countUp(entry, label, scale, target, duration)
	local finalText = formatAmount(target)
	local size = fitAmountSize(entry.card, label, finalText)
	if not entry.alive then
		return
	end
	if size then
		label.TextScaled = false
		label.TextSize = size
	end

	local start = os.clock()
	while entry.alive do
		local alpha = math.min((os.clock() - start) / duration, 1)
		label.Text = formatAmount(target * (1 - (1 - alpha) ^ 3))
		if alpha >= 1 then
			break
		end
		task.wait()
	end
	if not entry.alive then
		return
	end

	-- Selesai: angka "membal" sedikit.
	label.Text = finalText
	tween(scale, 0.12, { Scale = 1.1 }).Completed:Once(function()
		if entry.alive then
			tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end)
end

---------------------------------------------------------------------------
-- Satu notifikasi
---------------------------------------------------------------------------

local visible = {} -- alert yang sedang di layar, paling lama dulu
local queue = {}
local counter = 0
local pump

-- Tween yang berulang selamanya; dihentikan saat kartunya dihapus.
local function loop(entry, instance, seconds, props, style, reverses)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, reverses or false),
		props
	)
	t:Play()
	table.insert(entry.loops, t)
end

local function destroyEntry(entry)
	entry.alive = false
	for _, t in entry.loops do
		t:Cancel()
	end
	entry.slot:Destroy()
end

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
		destroyEntry(entry)
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
	if ok and image ~= "" and entry.alive then
		entry.avatar.Image = image
		entry.avatar.Visible = true
		entry.emoji.Visible = false
	end
end

-- Animasi yang berjalan selama kartu tampil.
local function startEffects(entry, tier, parts)
	local color = tier.Color
	local ringGradient = parts.ringGradient

	-- Border dan cincin avatar berputar, aura berdenyut.
	loop(entry, parts.borderGradient, 4, { Rotation = parts.borderGradient.Rotation + 360 })
	loop(entry, ringGradient, 3, { Rotation = ringGradient.Rotation - 360 })
	loop(entry, parts.pulse, 1.2, { Scale = 1.07 }, Enum.EasingStyle.Sine, true)
	for _, layer in parts.auraLayers do
		loop(entry, layer, 1.4, { BackgroundTransparency = layer.BackgroundTransparency * 0.7 }, Enum.EasingStyle.Sine, true)
	end

	-- Kilau menyapu kartu setiap beberapa detik.
	task.spawn(function()
		task.wait(0.7)
		while entry.alive do
			parts.shineGradient.Offset = Vector2.new(-1, 0)
			tween(parts.shineGradient, 1.1, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(3)
		end
	end)

	-- Percikan: semburan saat muncul, lalu sesekali.
	local sparkles = tier.Sparkles or 0
	if sparkles > 0 then
		task.spawn(function()
			task.wait(0.35)
			for _ = 1, sparkles do
				if not entry.alive then
					return
				end
				sparkle(entry, color)
				task.wait(0.03)
			end
			while entry.alive do
				task.wait(0.35 + math.random() * 0.4)
				sparkle(entry, color)
			end
		end)
	end

	-- Confetti untuk donasi besar.
	local pieces = tier.Confetti or 0
	if pieces > 0 then
		task.delay(0.3, function()
			if entry.alive then
				confetti(color, pieces)
			end
		end)
	end
end

local function show(alert)
	counter += 1
	local tier, rank = tierFor(alert.amount)
	local color = tier.Color

	local slot = template:Clone()
	slot.Name = "Alert"
	-- Yang terbaru selalu paling dekat dengan tepi layar.
	slot.LayoutOrder = if placement.top then -counter else counter
	-- Kartu lama tampil di atas aura kartu yang lebih baru.
	slot.ZIndex = math.max(1, 1000000 - counter)
	slot.Visible = true
	local mover = slot:WaitForChild("Mover")
	local card = mover:WaitForChild("Card")
	local body = card:WaitForChild("Body")
	local badge = card:WaitForChild("IconBadge")
	local ring = card:WaitForChild("Ring")
	local aura = mover:WaitForChild("Aura")
	local border = card:FindFirstChildOfClass("UIStroke")
	local ringStroke = ring:FindFirstChildOfClass("UIStroke")
	local amountLabel = body:WaitForChild("Amount")
	local messageLabel = body:WaitForChild("Message")

	local entry = {
		slot = slot,
		mover = mover,
		card = card,
		fx = card:WaitForChild("Fx"),
		avatar = badge:WaitForChild("Avatar"),
		emoji = badge:WaitForChild("Emoji"),
		alive = true,
		loops = {},
	}

	-- Warna sesuai tingkat donasi
	local edgeColors = borderColors(color)
	local borderGradient = border:FindFirstChildOfClass("UIGradient")
	local ringGradient = ringStroke:FindFirstChildOfClass("UIGradient")
	borderGradient.Color = edgeColors
	ringGradient.Color = edgeColors
	card:WaitForChild("Glow").BackgroundColor3 = color
	badge:FindFirstChildOfClass("UIGradient").Color =
		ColorSequence.new(color:Lerp(COLORS.White, 0.3), color:Lerp(COLORS.Black, 0.3))
	local auraLayers = aura:GetChildren()
	for _, layer in auraLayers do
		layer.BackgroundColor3 = color
	end
	entry.emoji.Text = tier.Emoji
	amountLabel:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(color:Lerp(COLORS.White, 0.5), color)

	local tag = card:WaitForChild("Tag")
	local hasTag = tier.Tag ~= nil and tier.Tag ~= ""
	tag.Visible = hasTag
	if hasTag then
		tag:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(color:Lerp(COLORS.White, 0.35), color)
		tag:WaitForChild("Label").Text = tier.Tag
	end

	-- Nama, lalu "baru saja bagi-bagi" atau "bagi-bagi ke <target>"
	body:WaitForChild("Donor").Text = alert.donor
	local headline = if alert.target ~= ""
		then `{escape(Settings.TargetHeadline)} <font color="{hex(color)}">{escape(alert.target)}</font>`
		else escape(Settings.Headline)
	body:WaitForChild("Headline").Text = headline

	-- Pesan (maksimal 2 baris); tanpa pesan, teks digeser ke tengah kartu.
	local hasMessage = alert.message ~= ""
	messageLabel.Visible = hasMessage
	messageLabel.Text = `“{alert.message}”`
	body.Position = UDim2.fromScale(body.Position.X.Scale, if hasMessage then 0 else 0.08)
	local sizeLimit = messageLabel:FindFirstChildOfClass("UITextSizeConstraint")
	local function fitMessage()
		local height = card.AbsoluteSize.Y
		if sizeLimit and height > 0 then
			sizeLimit.MaxTextSize = math.max(6, math.floor(height * 12 / DESIGN_H + 0.5))
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

	-- Ikon "muncul" dengan membal setelah kartu hampir sampai.
	local pop = badge:FindFirstChildOfClass("UIScale")
	local amountScale = amountLabel:FindFirstChildOfClass("UIScale")
	pop.Scale = 0
	task.delay(0.2, function()
		if entry.alive then
			tween(pop, 0.5, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end)

	-- Angka donasi
	if Settings.CountUp ~= false then
		amountLabel.Text = formatAmount(0)
		task.delay(0.3, countUp, entry, amountLabel, amountScale, alert.amount, math.min(0.7 + 0.15 * rank, 1.6))
	else
		amountLabel.Text = formatAmount(alert.amount)
	end

	local duration = tier.Duration or 5
	if #queue >= Settings.RushQueueAt then
		duration *= RUSH_FACTOR
	end
	local fill = card:WaitForChild("Progress"):WaitForChild("Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	tween(fill, duration, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	task.delay(duration, dismiss, entry)

	if EFFECTS then
		startEffects(entry, tier, {
			borderGradient = borderGradient,
			ringGradient = ringGradient,
			pulse = ring:FindFirstChildOfClass("UIScale"),
			shineGradient = card:WaitForChild("Shine"):FindFirstChildOfClass("UIGradient"),
			auraLayers = auraLayers,
		})
	else
		card:WaitForChild("Shine").Visible = false
	end

	playSound(tier.Sound or Settings.Sound)
	if alert.userId then
		task.spawn(loadAvatar, entry, alert.userId)
	end
end

-- Layar pendek (HP landscape) memuat lebih sedikit kartu daripada Settings.MaxVisible.
local function capacity()
	local slotHeight = stack.AbsoluteSize.X * DESIGN_SLOT_H / DESIGN_W
	if slotHeight <= 0 then
		return Settings.MaxVisible
	end
	return math.max(1, math.min(Settings.MaxVisible, math.floor(stack.AbsoluteSize.Y / slotHeight)))
end

function pump()
	while #visible < capacity() and #queue > 0 do
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
