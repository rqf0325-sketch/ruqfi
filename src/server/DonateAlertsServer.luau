--[[
	DonateAlertsServer (ServerScriptService)

	Menerima donasi lalu menampilkannya ke semua pemain lewat DonateAlertsGui.
	Sumbernya ada tiga:

	  1. Script lain di server:
	       game.ServerScriptService.DonateAlertsServer.Notify:Fire({
	           donor = "Budi", amount = 25000, message = "Semangat!", target = "RuqFi", userId = 1234,
	       })
	  2. Backend luar (Saweria / Bagi-Bagi / SocialBuzz / webhook-mu) lewat
	     MessagingService topic Settings.MessagingTopic. Isi pesan: JSON dengan
	     field yang sama, mis. {"donor":"Budi","amount":25000,"message":"Semangat!"}
	  3. Perintah chat /testdonate <jumlah> <pesan> untuk admin (dan siapa saja di Studio)

	Semua data dibersihkan di sini (panjang, karakter kontrol, filter teks Roblox,
	jumlah) sebelum dikirim ke client. Client tidak pernah menentukan isi donasi;
	hanya admin yang bisa memicu notifikasi tes.
]]

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local shared = ReplicatedStorage:WaitForChild("DonateAlerts")
local Config = require(shared:WaitForChild("Config"))
local Settings = Config.Settings

local MAX_AMOUNT = 1e12
local TEST_COOLDOWN = 1 -- detik antar tes per admin
local TEST_AMOUNTS = { 5000, 15000, 50000, 150000, 750000 }
local TEST_MESSAGES = {
	"Semangat terus bang!",
	"Buat beli kopi ya",
	"Bagi-bagi rezeki, gas!",
	"Keren banget gamenya",
}

local function getOrCreate(parent, className, name)
	local instance = parent:FindFirstChild(name)
	if not instance then
		instance = Instance.new(className)
		instance.Name = name
		instance.Parent = parent
	end
	return instance
end

local remotes = getOrCreate(shared, "Folder", "Remotes")
local alertRemote = getOrCreate(remotes, "RemoteEvent", "DonateAlert")
local testRemote = getOrCreate(remotes, "RemoteEvent", "TestAlert")
local notifyEvent = getOrCreate(script, "BindableEvent", "Notify")

---------------------------------------------------------------------------
-- Membersihkan data
---------------------------------------------------------------------------

-- Satu baris, tanpa karakter kontrol, maksimal `maxLength` huruf.
local function clean(value, maxLength)
	if typeof(value) ~= "string" then
		return ""
	end
	value = string.gsub(value, "%c", " ")
	value = string.gsub(value, "%s+", " ")
	value = string.match(value, "^%s*(.-)%s*$")
	local length = utf8.len(value)
	if not length then
		return "" -- bukan UTF-8 yang valid
	end
	if length > maxLength then
		value = string.sub(value, 1, utf8.offset(value, maxLength + 1) - 1) .. "…"
	end
	return value
end

local function isUser(userId)
	return typeof(userId) == "number" and userId > 0 and userId == math.floor(userId)
end

local function defaultFilterUserId()
	if isUser(Settings.FilterUserId) then
		return Settings.FilterUserId
	end
	if game.CreatorType == Enum.CreatorType.User and isUser(game.CreatorId) then
		return game.CreatorId
	end
	return nil
end

-- Filter teks Roblox untuk ditampilkan ke semua pemain. Gagal difilter = teks dibuang
-- (kecuali di Studio, supaya bisa dites di game yang belum dipublish).
local function filterText(value, userId)
	if value == "" or not Settings.FilterText then
		return value
	end
	userId = userId or defaultFilterUserId()
	if not userId then
		warn("[DonateAlerts] Tidak ada UserId untuk memfilter teks (game milik grup?). Isi Settings.FilterUserId.")
		return if RunService:IsStudio() then value else ""
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(value, userId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	warn(`[DonateAlerts] Gagal memfilter teks: {result}`)
	return if RunService:IsStudio() then value else ""
end

---------------------------------------------------------------------------
-- Kirim ke semua pemain
---------------------------------------------------------------------------

-- data: { donor, amount, message?, target?, userId? }. filterUserId = pemilik teks
-- (pemain yang mengetik tes); kosong = pemilik game.
local function broadcast(data, filterUserId)
	if typeof(data) ~= "table" then
		return false
	end

	local amount = tonumber(data.amount)
	if not amount or amount ~= amount or amount < Settings.MinAmount then
		return false
	end
	amount = math.min(math.floor(amount), MAX_AMOUNT)

	local donor = filterText(clean(data.donor or data.name, Settings.MaxNameLength), filterUserId)
	if donor == "" then
		donor = Settings.AnonymousName
	end

	alertRemote:FireAllClients({
		donor = donor,
		amount = amount,
		message = filterText(clean(data.message, Settings.MaxMessageLength), filterUserId),
		target = filterText(clean(data.target, Settings.MaxNameLength), filterUserId),
		userId = if isUser(data.userId) then data.userId else nil,
	})
	return true
end

notifyEvent.Event:Connect(function(data)
	task.spawn(broadcast, data)
end)

---------------------------------------------------------------------------
-- Dari backend luar (MessagingService)
---------------------------------------------------------------------------

local topic = Settings.MessagingTopic
if typeof(topic) == "string" and topic ~= "" then
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(topic, function(message)
				local data = message.Data
				if typeof(data) == "string" then
					local decoded, result = pcall(HttpService.JSONDecode, HttpService, data)
					data = if decoded then result else nil
				end
				task.spawn(broadcast, data)
			end)
		end)
		if not ok then
			-- Normal di Studio kalau game belum dipublish / API belum diaktifkan.
			warn(`[DonateAlerts] Tidak bisa subscribe ke topic "{topic}": {err}`)
		end
	end)
end

---------------------------------------------------------------------------
-- Tes (admin)
---------------------------------------------------------------------------

local function isAdmin(player)
	if RunService:IsStudio() then
		return true
	end
	if table.find(Settings.Admins, player.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local lastTest = {}

testRemote.OnServerEvent:Connect(function(player, amount, message)
	if not isAdmin(player) then
		return
	end
	local now = os.clock()
	if lastTest[player] and now - lastTest[player] < TEST_COOLDOWN then
		return
	end
	lastTest[player] = now

	if typeof(amount) ~= "number" then
		amount = TEST_AMOUNTS[math.random(#TEST_AMOUNTS)]
	end
	if typeof(message) ~= "string" or message == "" then
		message = TEST_MESSAGES[math.random(#TEST_MESSAGES)]
	end
	broadcast({
		donor = player.DisplayName,
		amount = amount,
		message = message,
		userId = player.UserId,
	}, player.UserId)
end)

local function onPlayerAdded(player)
	if isAdmin(player) then
		player:SetAttribute("DonateAdmin", true)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastTest[player] = nil
end)
