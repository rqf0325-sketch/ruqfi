--[[
	VehicleSpawnerServer (ServerScriptService)

	Spawns vehicles from ServerStorage.<Settings.VehiclesFolder> for the
	VehicleSpawnerGui. Everything the client asks for is checked here:
	the vehicle must be in the Config, its model must exist, the player must
	be alive, own the gamepass (if any) and respect the cooldown.
	Each player has at most one spawned vehicle.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local shared = ReplicatedStorage:WaitForChild("VehicleSpawner")
local Config = require(shared:WaitForChild("Config"))
local Settings = Config.Settings

local COLLISION_GROUP = "SpawnedVehicles"

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
local spawnRemote = getOrCreate(remotes, "RemoteFunction", "SpawnVehicle")
local despawnRemote = getOrCreate(remotes, "RemoteFunction", "DespawnVehicle")
local available = getOrCreate(shared, "Folder", "Available")
local spawnedFolder = getOrCreate(workspace, "Folder", "SpawnedVehicles")

local vehicleFolder = ServerStorage:FindFirstChild(Settings.VehiclesFolder)
if not vehicleFolder then
	vehicleFolder = getOrCreate(ServerStorage, "Folder", Settings.VehiclesFolder)
	warn(`[VehicleSpawner] ServerStorage.{Settings.VehiclesFolder} was missing; created an empty folder. Put your vehicle models in it.`)
end

if not PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP) then
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
end
PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, Settings.VehiclesCollideWithEachOther == true)

local vehiclesByName = {}
for _, vehicle in Config.Vehicles do
	vehiclesByName[vehicle.Name] = vehicle
end

---------------------------------------------------------------------------
-- Which Config vehicles actually have a model (the menu hides the rest)
---------------------------------------------------------------------------

local function refreshAvailable()
	for name in vehiclesByName do
		local model = vehicleFolder:FindFirstChild(name)
		local exists = model ~= nil and model:IsA("Model")
		local flag = available:FindFirstChild(name)
		if exists and not flag then
			flag = Instance.new("BoolValue")
			flag.Name = name
			flag.Value = true
			flag.Parent = available
		elseif not exists and flag then
			flag:Destroy()
		end
	end
end

refreshAvailable()
vehicleFolder.ChildAdded:Connect(refreshAvailable)
vehicleFolder.ChildRemoved:Connect(refreshAvailable)
for name in vehiclesByName do
	if not available:FindFirstChild(name) then
		warn(`[VehicleSpawner] No model named "{name}" in ServerStorage.{Settings.VehiclesFolder}; it is hidden from the menu.`)
	end
end

---------------------------------------------------------------------------
-- Gamepasses
---------------------------------------------------------------------------

local passCache = {}

local function ownsPass(player, passId)
	if not passId or passId == 0 then
		return true
	end
	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	if cache[passId] == nil then
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if not ok then
			warn("[VehicleSpawner] Gamepass check failed:", owns)
			return false
		end
		cache[passId] = owns
	end
	return cache[passId]
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if purchased then
		passCache[player] = passCache[player] or {}
		passCache[player][passId] = true
	end
end)

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------

local function flatLook(cframe)
	local look = cframe.LookVector * Vector3.new(1, 0, 1)
	return if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
end

local function yaw(direction)
	return math.atan2(-direction.X, -direction.Z)
end

-- Lowest world-space point of the parts you can see or bump into.
local function lowestPoint(model)
	local lowest = math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and (part.CanCollide or part.Transparency < 1) then
			local cframe, half = part.CFrame, part.Size / 2
			local extent = math.abs(cframe.RightVector.Y) * half.X
				+ math.abs(cframe.UpVector.Y) * half.Y
				+ math.abs(cframe.LookVector.Y) * half.Z
			lowest = math.min(lowest, cframe.Position.Y - extent)
		end
	end
	return lowest
end

-- Puts the vehicle in front of the player, facing the same way, resting on the ground.
local function placeVehicle(model, root, ignore)
	local look = flatLook(root.CFrame)
	local target = root.Position + look * Settings.SpawnDistance

	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	local forward = flatLook(if seat then seat.CFrame else model:GetPivot())
	local turn = yaw(look) - yaw(forward) + math.rad(Settings.SpawnRotation or 0)
	local center = model:GetBoundingBox().Position
	model:PivotTo(CFrame.new(center) * CFrame.Angles(0, turn, 0) * CFrame.new(-center) * model:GetPivot())

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(target + Vector3.new(0, 8, 0), Vector3.new(0, -60, 0), params)
	local groundY = if hit then hit.Position.Y else root.Position.Y - 3

	center = model:GetBoundingBox().Position
	model:PivotTo(model:GetPivot() + Vector3.new(
		target.X - center.X,
		groundY + Settings.SpawnHeight - lowestPoint(model),
		target.Z - center.Z
	))
end

local function setCollisionGroup(model)
	local function apply(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP
		end
	end
	for _, part in model:GetDescendants() do
		apply(part)
	end
	-- Chassis scripts create more parts (tyres, axles) while initialising.
	model.DescendantAdded:Connect(apply)
end

-- A-Chassis / NCT vehicles are anchored until their Initialize script has
-- welded them, and remove Tuner.Plugins once the seat is ready for a driver.
local function waitUntilDrivable(model, seat, timeout)
	local tuner = model:FindFirstChild("Tuner")
	local deadline = os.clock() + timeout
	while model.Parent and os.clock() < deadline
		and (seat.Anchored or (tuner and tuner:FindFirstChild("Plugins"))) do
		task.wait(0.1)
	end
	task.wait(0.1)
	return model.Parent ~= nil and not seat.Anchored
end

local function autoSit(model, humanoid, root)
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	if not seat or not waitUntilDrivable(model, seat, 15) then
		return
	end
	if humanoid.Health > 0 and not humanoid.SeatPart and root.Parent
		and (root.Position - seat.Position).Magnitude < Settings.SpawnDistance + 40 then
		seat:Sit(humanoid)
	end
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------

local spawned = {}
local lastSpawn = {}

local function despawn(player)
	local model = spawned[player]
	spawned[player] = nil
	if not model or not model.Parent then
		return false
	end
	-- Get riders off first so the bike can give them their body back.
	for _, seat in model:GetDescendants() do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
		end
	end
	task.delay(0.25, function()
		model:Destroy()
	end)
	return true
end

spawnRemote.OnServerInvoke = function(player, name)
	if type(name) ~= "string" then
		return false, "Invalid vehicle."
	end
	local vehicle = vehiclesByName[name]
	if not vehicle then
		return false, "Unknown vehicle."
	end

	local now = os.clock()
	local remaining = Settings.SpawnCooldown - (now - (lastSpawn[player] or -math.huge))
	if remaining > 0 then
		return false, `Please wait {math.ceil(remaining)}s before spawning again.`
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return false, "You need to be alive to spawn a vehicle."
	end
	if not ownsPass(player, vehicle.GamepassId) then
		return false, "This vehicle needs a gamepass."
	end
	local template = vehicleFolder:FindFirstChild(vehicle.Name)
	if not template or not template:IsA("Model") then
		return false, "This vehicle isn't available right now."
	end

	lastSpawn[player] = now
	despawn(player)

	local model = template:Clone()
	model:SetAttribute("OwnerUserId", player.UserId)
	setCollisionGroup(model)
	placeVehicle(model, root, { character, spawnedFolder })
	model.Parent = spawnedFolder
	spawned[player] = model
	model.Destroying:Connect(function()
		if spawned[player] == model then
			spawned[player] = nil
		end
	end)

	if Settings.AutoSit then
		task.spawn(autoSit, model, humanoid, root)
	end
	return true, `{vehicle.DisplayName or vehicle.Name} spawned!`
end

despawnRemote.OnServerInvoke = function(player)
	if despawn(player) then
		return true, "Vehicle despawned."
	end
	return false, "You don't have a vehicle out."
end

Players.PlayerRemoving:Connect(function(player)
	if Settings.DespawnWhenLeaving then
		despawn(player)
	end
	spawned[player] = nil
	lastSpawn[player] = nil
	passCache[player] = nil
end)
