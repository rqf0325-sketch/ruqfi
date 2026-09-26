--[[
	Vehicle Spawner — Config
	(ReplicatedStorage > VehicleSpawner > Config)

	Menambah kendaraan:
	  1. Taruh model kendaraan di ServerStorage > Vehicles
	  2. Tambahkan entri di Config.Vehicles dengan Name yang SAMA PERSIS
	     dengan nama model tersebut.
	Kendaraan yang modelnya belum ada di ServerStorage otomatis disembunyikan
	dari menu (dan muncul peringatan di Output).
]]

local Config = {}

Config.Settings = {
	VehiclesFolder = "Vehicles", -- folder di ServerStorage berisi model kendaraan
	SpawnDistance = 10, -- jarak spawn di depan pemain (stud)
	SpawnHeight = 0.5, -- jarak dari tanah saat muncul (stud)
	SpawnRotation = 0, -- putar kendaraan (derajat) kalau muncul menghadap arah yang salah
	SpawnCooldown = 5, -- detik antar spawn per pemain
	AutoSit = true, -- pemain langsung duduk di kendaraan setelah spawn
	CloseMenuOnSpawn = true,
	OpenOnJoin = false, -- menu langsung terbuka saat masuk game
	ToggleKey = Enum.KeyCode.V, -- tombol keyboard buka/tutup menu (nil = tidak ada)
	VehiclesCollideWithEachOther = false, -- kendaraan saling tembus (mencegah tabrakan iseng)
	DespawnWhenLeaving = true, -- hapus kendaraan saat pemain keluar dari game

	-- Batas bar statistik di panel detail (hanya tampilan)
	StatMax = {
		TopSpeed = 300, -- km/h
		AccelerationBest = 2, -- detik 0-100 tercepat (bar penuh)
		AccelerationWorst = 12, -- detik 0-100 terlambat (bar kosong)
		Handling = 10,
	},
}

--[[
	Name         : nama model di ServerStorage.Vehicles (wajib sama persis)
	DisplayName  : nama yang tampil di menu (opsional, default = Name)
	Category     : "Motorcycle" / "Car" (harus cocok dengan tab Tab_<Category>)
	Type         : keterangan kecil, mis. "Touring", "Chopper"
	Image        : "rbxassetid://123..." gambar kendaraan (kosong = ikon placeholder)
	New          : true = badge NEW dan muncul paling atas di sort "Newest"
	GamepassId   : 0 = gratis; isi ID gamepass untuk mengunci kendaraan
	GamepassName : teks di kartu yang terkunci
	Stats        : TopSpeed (km/h), Acceleration (detik 0-100), Handling (0-10) — hanya tampilan
]]
Config.Vehicles = {
	{
		Name = "HD Road Glide ST CVO",
		DisplayName = "Road Glide ST CVO",
		Category = "Motorcycle",
		Type = "Touring",
		Image = "",
		New = true,
		GamepassId = 0,
		Stats = { TopSpeed = 190, Acceleration = 3.9, Handling = 7.5 },
	},

	-- Motor dari menu lama. Muncul otomatis setelah modelnya ada di ServerStorage.Vehicles.
	{
		Name = "Chopper Howlers",
		Category = "Motorcycle",
		Type = "Chopper",
		New = true,
		GamepassId = 0, -- isi ID gamepass "Limited Motorcycle Pass"
		GamepassName = "Motorcycle Pass",
		Stats = { TopSpeed = 150, Acceleration = 5.5, Handling = 6 },
	},
	{
		Name = "Bobber Howlers",
		Category = "Motorcycle",
		Type = "Bobber",
		New = true,
		GamepassId = 0, -- isi ID gamepass "Limited Motorcycle Pass"
		GamepassName = "Motorcycle Pass",
		Stats = { TopSpeed = 145, Acceleration = 5.8, Handling = 6.5 },
	},
	{
		Name = "BMW R 80",
		Category = "Motorcycle",
		Type = "Cafe Racer",
		New = true,
		Stats = { TopSpeed = 165, Acceleration = 4.8, Handling = 8.4 },
	},
	{
		Name = "Chicano Howlers",
		Category = "Motorcycle",
		Type = "Lowrider",
		New = true,
		Stats = { TopSpeed = 155, Acceleration = 5.2, Handling = 6.8 },
	},
}

return Config
