--[[
	Donate Alerts — Config
	(ReplicatedStorage > DonateAlerts > Config)

	Notifikasi donasi ala Saweria / Bagi-Bagi / SocialBuzz. Isi Config ini
	yang mengatur teks, mata uang, posisi, suara, dan warna tiap tingkat donasi.

	Cara mengirim donasi (dari server):
	  * Script lain  : ServerScriptService.DonateAlertsServer.Notify:Fire({ donor = "Budi", amount = 25000, message = "Semangat!" })
	  * Backend luar : publish ke MessagingService topic Settings.MessagingTopic (lihat README)
	  * Tes          : ketik /testdonate 25000 Halo di chat (hanya admin / Studio)
]]

local Config = {}

Config.Settings = {
	-- Tampilan uang -------------------------------------------------------------
	Currency = "Rp", -- "Rp", "R$", "Robux", ...
	CurrencyPosition = "Prefix", -- "Prefix" = Rp 25.000, "Suffix" = 25.000 Robux
	ThousandsSeparator = ".", -- "." untuk rupiah, "," untuk robux
	MinAmount = 1, -- donasi di bawah ini diabaikan

	-- Teks ----------------------------------------------------------------------
	Headline = "baru saja bagi-bagi", -- "<nama> baru saja bagi-bagi"
	TargetHeadline = "bagi-bagi ke", -- dipakai kalau donasi punya target: "<nama> bagi-bagi ke <target>"
	AnonymousName = "Anonim", -- kalau nama donatur kosong
	MaxNameLength = 20,
	MaxMessageLength = 120,

	-- Posisi & jumlah ---------------------------------------------------------------
	-- "TopCenter", "TopLeft", "TopRight", "BottomCenter", "BottomLeft", "BottomRight"
	Position = "TopCenter",
	MaxVisible = 3, -- notifikasi yang tampil bersamaan; sisanya antre (di layar pendek otomatis lebih sedikit)
	MaxQueue = 30, -- antrean terlalu panjang: yang paling lama dibuang
	RushQueueAt = 4, -- antrean sepanjang ini atau lebih = notifikasi tampil lebih singkat

	-- Efek ----------------------------------------------------------------------
	-- Border berputar, kilau, aura, cincin avatar, percikan, dan confetti.
	-- false = kartu tampil diam (lebih ringan untuk HP kentang).
	Effects = true,
	CountUp = true, -- angka donasi berhitung naik dari nol

	-- Suara (kosongkan Sound / set SoundEnabled = false untuk mematikan) ------------
	-- Ganti dengan "rbxassetid://ID" milikmu. Tiap tingkat bisa punya suara sendiri (Tier.Sound).
	SoundEnabled = true,
	Sound = "rbxasset://sounds/electronicpingshort.wav",
	Volume = 0.6,

	-- Keamanan teks -----------------------------------------------------------------
	-- Nama & pesan donatur difilter Roblox sebelum ditampilkan ke pemain lain.
	-- Difilter atas nama pemilik game; untuk game milik grup isi FilterUserId dengan UserId-mu.
	FilterText = true,
	FilterUserId = nil,

	-- Sumber donasi -------------------------------------------------------------------
	MessagingTopic = "DonateAlerts", -- topic MessagingService dari backend-mu ("" = mati)
	TestCommand = "/testdonate", -- perintah chat untuk tes ("" = mati)
	Admins = {}, -- UserId tambahan yang boleh tes, mis. { 123456789 }. Pemilik game & Studio selalu boleh.
}

--[[
	Tiap tingkat donasi punya warna, emoji, label, dan lama tampil sendiri.
	Diurutkan dari Min terkecil; donasi memakai tingkat tertinggi yang Min-nya
	tidak melebihi jumlahnya. Angka Min di bawah untuk rupiah; kalau memakai
	Robux, sesuaikan (mis. 10, 50, 100, 500).

	Min      : jumlah donasi minimum untuk tingkat ini
	Emoji    : ikon di lingkaran kiri (kalau donasi punya userId, diganti foto avatar)
	Color    : warna border, aura, jumlah donasi, cincin ikon, dan pita
	Tag      : pita kecil di sudut kanan atas kartu ("" = tanpa pita; usahakan maksimal 9 huruf)
	Duration : lama tampil (detik)
	Sparkles : jumlah percikan cahaya saat kartu muncul (0 = tanpa)
	Confetti : jumlah confetti yang jatuh di layar (0 = tanpa; makin besar donasi makin meriah)
	Sound    : suara khusus tingkat ini (opsional)
]]
Config.Tiers = {
	{ Min = 0, Emoji = "🎁", Color = Color3.fromRGB(61, 220, 151), Tag = "", Duration = 5, Sparkles = 6, Confetti = 0 },
	{ Min = 10000, Emoji = "💎", Color = Color3.fromRGB(56, 189, 248), Tag = "SUPPORTER", Duration = 6, Sparkles = 10, Confetti = 0 },
	{ Min = 50000, Emoji = "🔥", Color = Color3.fromRGB(139, 108, 255), Tag = "HYPE", Duration = 7, Sparkles = 14, Confetti = 24 },
	{ Min = 100000, Emoji = "👑", Color = Color3.fromRGB(255, 190, 56), Tag = "SULTAN", Duration = 8, Sparkles = 18, Confetti = 48 },
	{ Min = 500000, Emoji = "🚀", Color = Color3.fromRGB(255, 85, 102), Tag = "LEGEND", Duration = 10, Sparkles = 24, Confetti = 80 },
}

return Config
