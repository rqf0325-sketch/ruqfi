--[[
	Scooter — Settings
	(StarterPack > Scooter > Settings)

	Kecepatan dalam stud/detik. Di Roblox 1 stud/detik ≈ 1 km/jam, jadi
	MaxSpeed = 30 artinya sekitar 30 km/jam (jalan kaki biasa = 16).
]]

local Settings = {}

-- Tema warna bawaan. Pilih salah satu nama dari Settings.Themes di bawah.
Settings.Theme = "Noctis"
-- Pemain bisa ganti warna skuternya sendiri (tombol di layar, atau tombol T).
-- Pilihannya diingat sampai pemain keluar dari game.
Settings.PlayersCanChangeTheme = true
Settings.ThemeKey = Enum.KeyCode.T -- nil = tanpa tombol keyboard
Settings.ShowHud = true -- tampilkan tombol tema + speedometer saat skuter dipakai

-- Laju
Settings.MaxSpeed = 30 -- kecepatan maksimum
Settings.StartSpeed = 12 -- kecepatan tendangan pertama dari diam
Settings.Acceleration = 9 -- tambahan kecepatan per detik saat tombol jalan ditahan
Settings.Coast = true -- tetap meluncur saat tombol dilepas
Settings.CoastFriction = 8 -- pengurangan kecepatan per detik saat meluncur
Settings.BrakeForce = 45 -- pengereman per detik saat menekan arah berlawanan
Settings.TurnSpeed = 6 -- kecepatan belok saat pelan (radian/detik)
Settings.TurnSpeedAtMax = 3 -- kecepatan belok saat MaxSpeed (lebih kecil = belokan lebih lebar)
Settings.JumpBoost = 1.1 -- lompatan 10% lebih tinggi selama naik skuter

-- Trik: lompat saat melaju cepat untuk tailwhip (dek diputar) atau putaran 360°.
Settings.Tricks = true
Settings.TrickMinSpeed = 16

-- Lampu depan + lampu kolong (underglow)
Settings.Lights = "Auto" -- "Auto" = menyala saat malam (Lighting.ClockTime), true = selalu, false = mati
Settings.Underglow = true

-- Suara
Settings.Sounds = true
Settings.KickSound = "rbxasset://sounds/action_footsteps_plastic.mp3" -- saat kaki menendang
Settings.WindSound = "rbxasset://sounds/action_falling.mp3" -- desir angin saat cepat
Settings.RollSound = "" -- opsional: "rbxassetid://..." suara roda (loop), mis. dari Toolbox

--[[
	Tema. Setiap bagian skuter punya "Role" (lihat atribut Role di tiap part):

	  Paint   bodi utama: alas dek, leher, tabung kemudi, spakbor
	  Trim    warna kedua: tiang & setang, garpu roda, engsel
	  Grip    permukaan dek (grip tape)
	  Metal   baut, as roda, tuas
	  Accent  klem setang & klem tiang
	  Rubber  ban dan handgrip
	  Rim     jari-jari roda
	  Glow    strip di bawah dek
	  Light   warna cahaya lampu kolong + warna tema di tombol (nil = tanpa lampu kolong)

	Material yang bagus: SmoothPlastic (cat mengilap, pakai Reflectance),
	Plastic (doff), Metal, Foil (krom), Neon (menyala), Asphalt / Sand
	(grip tape), Rubber, Leather.
]]
local function look(r, g, b, material, reflectance)
	return { Color = Color3.fromRGB(r, g, b), Material = material, Reflectance = reflectance or 0 }
end

local M = Enum.Material

Settings.Themes = {
	Noctis = { -- biru malam + amber, senada dengan menu garasi
		Paint = look(32, 38, 56, M.SmoothPlastic, 0.12),
		Trim = look(22, 24, 30, M.Metal),
		Grip = look(28, 29, 34, M.Asphalt),
		Metal = look(190, 194, 204, M.Metal),
		Accent = look(255, 178, 48, M.SmoothPlastic, 0.05),
		Rubber = look(24, 24, 27, M.Rubber),
		Rim = look(255, 178, 48, M.Neon),
		Glow = look(255, 160, 40, M.Neon),
		Light = Color3.fromRGB(255, 170, 60),
	},
	Violet = { -- ungu neon
		Paint = look(28, 21, 46, M.SmoothPlastic, 0.12),
		Trim = look(16, 16, 22, M.Metal),
		Grip = look(26, 26, 32, M.Asphalt),
		Metal = look(180, 180, 195, M.Metal),
		Accent = look(150, 115, 255, M.SmoothPlastic, 0.05),
		Rubber = look(22, 20, 26, M.Rubber),
		Rim = look(140, 100, 255, M.Neon),
		Glow = look(130, 90, 255, M.Neon),
		Light = Color3.fromRGB(140, 100, 255),
	},
	Cyber = { -- grafit + biru muda
		Paint = look(42, 46, 56, M.SmoothPlastic, 0.15),
		Trim = look(20, 22, 28, M.Metal),
		Grip = look(26, 28, 32, M.Asphalt),
		Metal = look(196, 202, 212, M.Metal),
		Accent = look(0, 210, 255, M.SmoothPlastic, 0.05),
		Rubber = look(22, 24, 27, M.Rubber),
		Rim = look(0, 220, 255, M.Neon),
		Glow = look(0, 200, 255, M.Neon),
		Light = Color3.fromRGB(0, 190, 255),
	},
	Street = { -- merah + hitam, gaya kota
		Paint = look(196, 30, 38, M.SmoothPlastic, 0.12),
		Trim = look(26, 26, 28, M.Metal),
		Grip = look(30, 30, 32, M.Asphalt),
		Metal = look(205, 208, 215, M.Metal),
		Accent = look(240, 240, 240, M.SmoothPlastic, 0.05),
		Rubber = look(24, 24, 26, M.Rubber),
		Rim = look(225, 228, 235, M.Metal),
		Glow = look(255, 60, 50, M.Neon),
		Light = Color3.fromRGB(255, 70, 60),
	},
	Arctic = { -- putih bersih + biru
		Paint = look(236, 239, 244, M.SmoothPlastic, 0.08),
		Trim = look(48, 52, 60, M.Metal),
		Grip = look(40, 42, 48, M.Asphalt),
		Metal = look(200, 205, 215, M.Metal),
		Accent = look(0, 162, 255, M.SmoothPlastic, 0.05),
		Rubber = look(30, 30, 34, M.Rubber),
		Rim = look(215, 220, 228, M.Metal),
		Glow = look(90, 200, 255, M.Neon),
		Light = Color3.fromRGB(120, 200, 255),
	},
	Candy = { -- pastel pink + mint
		Paint = look(255, 176, 204, M.SmoothPlastic, 0.05),
		Trim = look(250, 248, 252, M.SmoothPlastic, 0.05),
		Grip = look(92, 80, 106, M.Sand),
		Metal = look(220, 220, 230, M.Metal),
		Accent = look(130, 222, 200, M.SmoothPlastic),
		Rubber = look(64, 56, 72, M.Rubber),
		Rim = look(130, 222, 200, M.SmoothPlastic),
		Glow = look(255, 150, 200, M.Neon),
		Light = Color3.fromRGB(255, 150, 210),
	},
	Gold = { -- hitam piano + emas
		Paint = look(14, 14, 16, M.SmoothPlastic, 0.2),
		Trim = look(20, 20, 22, M.Metal),
		Grip = look(24, 24, 26, M.Asphalt),
		Metal = look(218, 172, 60, M.Foil),
		Accent = look(230, 185, 70, M.Foil),
		Rubber = look(18, 18, 20, M.Rubber),
		Rim = look(218, 172, 60, M.Metal),
		Glow = look(255, 200, 90, M.Neon),
		Light = Color3.fromRGB(255, 200, 110),
	},
	Army = { -- hijau army doff, tanpa lampu kolong
		Paint = look(86, 98, 62, M.Plastic),
		Trim = look(44, 46, 38, M.Metal),
		Grip = look(46, 44, 40, M.Asphalt),
		Metal = look(150, 150, 140, M.Metal),
		Accent = look(196, 160, 98, M.Plastic),
		Rubber = look(30, 30, 28, M.Rubber),
		Rim = look(60, 62, 55, M.Metal),
		Glow = look(60, 62, 55, M.Metal),
		Light = nil,
	},
}

-- Urutan saat pemain menekan tombol ganti warna.
Settings.ThemeOrder = { "Noctis", "Violet", "Cyber", "Street", "Arctic", "Candy", "Gold", "Army" }

return Settings
