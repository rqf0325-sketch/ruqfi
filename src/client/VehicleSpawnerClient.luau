--[[
	VehicleSpawnerClient (LocalScript inside StarterGui.VehicleSpawnerGui)

	Builds the vehicle cards from ReplicatedStorage.VehicleSpawner.Config and
	runs the menu: open/close, search, category tabs, sorting, selection,
	gamepass prompts, spawn and despawn. The server re-checks everything.
]]

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = script.Parent

local shared = ReplicatedStorage:WaitForChild("VehicleSpawner")
local Config = require(shared:WaitForChild("Config"))
local Settings = Config.Settings
local remotes = shared:WaitForChild("Remotes")
local spawnRemote = remotes:WaitForChild("SpawnVehicle")
local despawnRemote = remotes:WaitForChild("DespawnVehicle")
local available = shared:WaitForChild("Available", 10)

local main = gui:WaitForChild("Main")
local backdrop = gui:WaitForChild("Backdrop")
local openButton = gui:WaitForChild("OpenButton")
local toast = gui:WaitForChild("Toast")
local header = main:WaitForChild("Header")
local browser = main:WaitForChild("Browser")
local details = main:WaitForChild("Details")
local grid = browser:WaitForChild("Grid")
local template = grid:WaitForChild("CardTemplate")
local tabs = browser:WaitForChild("Tabs")
local searchBox = browser:WaitForChild("Search"):WaitForChild("SearchBox")
local sortButton = browser:WaitForChild("SortButton")
local sortLabel = sortButton:WaitForChild("Label")
local resultCount = browser:WaitForChild("ResultCount")
local emptyState = browser:WaitForChild("EmptyState")
local spawnButton = details:WaitForChild("SpawnButton")
local spawnLabel = spawnButton:WaitForChild("Label")
local spawnGradient = spawnButton:FindFirstChildOfClass("UIGradient")
local toastMessage = toast:WaitForChild("Message")
local toastDot = toast:WaitForChild("Dot")
local uiScale = main:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", main)

local FONT = "rbxasset://fonts/families/Montserrat.json"
local COLORS = {
	Surface = Color3.fromRGB(26, 30, 41),
	Selected = Color3.fromRGB(36, 33, 29),
	Field = Color3.fromRGB(33, 38, 52),
	Muted = Color3.fromRGB(140, 149, 166),
	Amber = Color3.fromRGB(255, 190, 56),
	Orange = Color3.fromRGB(255, 128, 31),
	OnAmber = Color3.fromRGB(28, 19, 4),
	Purple = Color3.fromRGB(139, 108, 255),
	PurpleDark = Color3.fromRGB(104, 72, 230),
	PurpleLight = Color3.fromRGB(196, 181, 253),
	Green = Color3.fromRGB(61, 220, 151),
	Red = Color3.fromRGB(255, 85, 102),
	White = Color3.new(1, 1, 1),
}

local state = {
	open = false,
	busy = false,
	category = "All",
	query = "",
	sort = 1,
	selected = nil,
}
local entries = {}
local owned = {}

local function tween(instance, time, props, style, direction)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function displayName(vehicle)
	return vehicle.DisplayName or vehicle.Name
end

local function isUnlocked(vehicle)
	local passId = vehicle.GamepassId
	return not passId or passId == 0 or owned[passId] == true
end

local function isAvailable(vehicle)
	return available == nil or available:FindFirstChild(vehicle.Name) ~= nil
end

local function setImage(stage, image)
	if type(image) == "number" then
		image = "rbxassetid://" .. image
	end
	local hasImage = type(image) == "string" and image ~= ""
	local picture = stage:FindFirstChild("VehicleImage")
	local placeholder = stage:FindFirstChild("PlaceholderIcon")
	if picture then
		picture.Image = if hasImage then image else ""
	end
	if placeholder then
		placeholder.Visible = not hasImage
	end
end

---------------------------------------------------------------------------
-- Toast
---------------------------------------------------------------------------

local toastToken = 0
local toastHome = toast.Position

local function notify(text, ok)
	toastToken += 1
	local token = toastToken
	toastMessage.Text = text
	toastDot.BackgroundColor3 = if ok then COLORS.Green else COLORS.Red
	toast.Position = toastHome + UDim2.fromScale(0, 0.03)
	toast.Visible = true
	tween(toast, 0.2, { Position = toastHome })
	task.delay(2.5, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

---------------------------------------------------------------------------
-- Cards and details
---------------------------------------------------------------------------

local STATS = {
	{
		row = "Stat_TopSpeed",
		key = "TopSpeed",
		text = function(v)
			return `{math.floor(v + 0.5)} km/h`
		end,
		fill = function(v)
			return v / Settings.StatMax.TopSpeed
		end,
	},
	{
		row = "Stat_Acceleration",
		key = "Acceleration",
		text = function(v)
			return string.format("%.1f s", v)
		end,
		fill = function(v)
			local max = Settings.StatMax
			return (max.AccelerationWorst - v) / (max.AccelerationWorst - max.AccelerationBest)
		end,
	},
	{
		row = "Stat_Handling",
		key = "Handling",
		text = function(v)
			return string.format("%.1f / %d", v, Settings.StatMax.Handling)
		end,
		fill = function(v)
			return v / Settings.StatMax.Handling
		end,
	},
}

local function styleCard(entry)
	local card = entry.card
	local selected = state.selected == entry
	local unlocked = isUnlocked(entry.vehicle)

	card.LockOverlay.Visible = not unlocked
	card.BackgroundColor3 = if selected then COLORS.Selected else COLORS.Surface
	if entry.stroke then
		entry.stroke.Color = if selected then COLORS.Amber else COLORS.White
		entry.stroke.Thickness = if selected then 2 else 1
		entry.stroke.Transparency = if selected then 0 elseif entry.hovered then 0.7 else 0.92
	end

	local color, text = COLORS.Green, "Available"
	if not unlocked then
		color, text = COLORS.PurpleLight, "Gamepass"
	elseif selected then
		color, text = COLORS.Amber, "Selected"
	end
	card.Status.Text = text
	card.Status.TextColor3 = color
	card.StatusDot.BackgroundColor3 = color
end

local function updateSpawnButton(text)
	local entry = state.selected
	local locked = entry ~= nil and not isUnlocked(entry.vehicle)
	if spawnGradient then
		spawnGradient.Color = if locked
			then ColorSequence.new(COLORS.Purple, COLORS.PurpleDark)
			else ColorSequence.new(COLORS.Amber, COLORS.Orange)
	end
	spawnLabel.TextColor3 = if locked then COLORS.White else COLORS.OnAmber
	spawnLabel.Text = text
		or (not entry and "SELECT A VEHICLE")
		or (locked and "UNLOCK WITH GAMEPASS")
		or "SPAWN VEHICLE"
end

local function updateDetails()
	local entry = state.selected
	local vehicle = entry and entry.vehicle
	details.VehicleName.Text = if vehicle then displayName(vehicle) else "No vehicle"
	local info = {}
	if vehicle and vehicle.Type then
		table.insert(info, vehicle.Type)
	end
	if vehicle and vehicle.Category then
		table.insert(info, vehicle.Category)
	end
	details.Info.Text = table.concat(info, "  •  ")
	setImage(details.Stage, vehicle and vehicle.Image)
	details.NewBadge.Visible = vehicle ~= nil and vehicle.New == true

	local stats = vehicle and vehicle.Stats or {}
	for _, spec in STATS do
		local row = details.Stats:FindFirstChild(spec.row)
		if row then
			local value = stats[spec.key]
			row.Value.Text = if value then spec.text(value) else "-"
			local fill = if value then math.clamp(spec.fill(value), 0, 1) else 0
			tween(row.Track.Fill, 0.35, { Size = UDim2.fromScale(fill, 1) })
		end
	end
	updateSpawnButton()
end

local function selectEntry(entry)
	state.selected = entry
	for _, other in entries do
		styleCard(other)
	end
	updateDetails()
end

local function refreshCards()
	for _, entry in entries do
		styleCard(entry)
	end
	updateDetails()
end

---------------------------------------------------------------------------
-- Filtering and sorting
---------------------------------------------------------------------------

local function byIndex(a, b)
	return a.index < b.index
end

local SORTS = {
	{
		name = "Newest",
		less = function(a, b)
			local aNew, bNew = a.vehicle.New == true, b.vehicle.New == true
			if aNew ~= bNew then
				return aNew
			end
			return byIndex(a, b)
		end,
	},
	{
		name = "A - Z",
		less = function(a, b)
			local aName, bName = displayName(a.vehicle):lower(), displayName(b.vehicle):lower()
			if aName ~= bName then
				return aName < bName
			end
			return byIndex(a, b)
		end,
	},
	{
		name = "Fastest",
		less = function(a, b)
			local aSpeed = a.vehicle.Stats and a.vehicle.Stats.TopSpeed or 0
			local bSpeed = b.vehicle.Stats and b.vehicle.Stats.TopSpeed or 0
			if aSpeed ~= bSpeed then
				return aSpeed > bSpeed
			end
			return byIndex(a, b)
		end,
	},
}

local function matches(entry)
	local vehicle = entry.vehicle
	if not isAvailable(vehicle) then
		return false
	end
	if state.category == "Gamepass" then
		if not vehicle.GamepassId or vehicle.GamepassId == 0 then
			return false
		end
	elseif state.category ~= "All" and vehicle.Category ~= state.category then
		return false
	end
	if state.query ~= "" then
		local haystack = `{displayName(vehicle)} {vehicle.Name} {vehicle.Type or ""} {vehicle.Category or ""}`
		if not haystack:lower():find(state.query, 1, true) then
			return false
		end
	end
	return true
end

local function refreshList()
	local shown = {}
	for _, entry in entries do
		local visible = matches(entry)
		entry.slot.Visible = visible
		if visible then
			table.insert(shown, entry)
		end
	end
	table.sort(shown, SORTS[state.sort].less)
	for order, entry in shown do
		entry.slot.LayoutOrder = order
	end

	resultCount.Text = `<font color="#FFBE38">{#shown}</font>  {if #shown == 1 then "vehicle" else "vehicles"}`
	emptyState.Visible = #shown == 0
	grid.CanvasPosition = Vector2.zero

	if not state.selected or not table.find(shown, state.selected) then
		selectEntry(shown[1])
	end
end

local function styleTabs()
	for _, tab in tabs:GetChildren() do
		if tab:IsA("TextButton") then
			local active = tab.Name == "Tab_" .. state.category
			tab.BackgroundColor3 = if active then COLORS.Amber else COLORS.Field
			tab.TextColor3 = if active then COLORS.OnAmber else COLORS.Muted
			tab.FontFace = Font.new(FONT, if active then Enum.FontWeight.ExtraBold else Enum.FontWeight.SemiBold)
			local stroke = tab:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = not active
			end
		end
	end
end

local function styleSort()
	sortLabel.Text = `<font color="#8C95A6">Sort:</font>  {SORTS[state.sort].name}`
end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------

local backdropTransparency = backdrop.BackgroundTransparency

local function setOpen(open)
	if state.open == open then
		return
	end
	state.open = open
	if open then
		main.Visible = true
		backdrop.Visible = true
		uiScale.Scale = 0.9
		backdrop.BackgroundTransparency = 1
		tween(uiScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(backdrop, 0.2, { BackgroundTransparency = backdropTransparency })
	else
		tween(uiScale, 0.15, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(backdrop, 0.15, { BackgroundTransparency = 1 })
		task.delay(0.15, function()
			if not state.open then
				main.Visible = false
				backdrop.Visible = false
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Build the cards
---------------------------------------------------------------------------

for _, child in grid:GetChildren() do
	if child:IsA("GuiObject") and child ~= template then
		child:Destroy() -- example cards from the design
	end
end

for index, vehicle in Config.Vehicles do
	local slot = template:Clone()
	slot.Name = "Card_" .. vehicle.Name
	slot.Visible = false
	local card = slot.Card
	card.VehicleName.Text = displayName(vehicle)
	card.Info.Text = vehicle.Type or vehicle.Category or ""
	card.NewBadge.Visible = vehicle.New == true
	card.LockOverlay.Subtitle.Text = vehicle.GamepassName or "Gamepass"
	setImage(card.Stage, vehicle.Image)
	slot.Parent = grid

	local entry = {
		vehicle = vehicle,
		index = index,
		slot = slot,
		card = card,
		stroke = card:FindFirstChildOfClass("UIStroke"),
		hovered = false,
	}
	table.insert(entries, entry)

	card.Activated:Connect(function()
		selectEntry(entry)
	end)
	card.MouseEnter:Connect(function()
		entry.hovered = true
		styleCard(entry)
	end)
	card.MouseLeave:Connect(function()
		entry.hovered = false
		styleCard(entry)
	end)
end

-- Gamepass ownership (display only; the server checks again when spawning).
for _, vehicle in Config.Vehicles do
	local passId = vehicle.GamepassId
	if passId and passId ~= 0 and owned[passId] == nil then
		owned[passId] = false
		task.spawn(function()
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
			if ok and result then
				owned[passId] = true
				refreshCards()
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

header:WaitForChild("Title").Text = `Welcome, <font color="#FFBE38">{escape(player.DisplayName)}</font>`

for _, tab in tabs:GetChildren() do
	if tab:IsA("TextButton") and tab.Name:sub(1, 4) == "Tab_" then
		tab.Activated:Connect(function()
			state.category = tab.Name:sub(5)
			styleTabs()
			refreshList()
		end)
	end
end

sortButton.Activated:Connect(function()
	state.sort = state.sort % #SORTS + 1
	styleSort()
	refreshList()
end)

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	state.query = searchBox.Text:lower():match("^%s*(.-)%s*$")
	refreshList()
end)

openButton.Activated:Connect(function()
	setOpen(not state.open)
end)
header:WaitForChild("CloseButton").Activated:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and Settings.ToggleKey and input.KeyCode == Settings.ToggleKey then
		setOpen(not state.open)
	end
end)

spawnButton.Activated:Connect(function()
	local entry = state.selected
	if not entry or state.busy then
		return
	end
	local vehicle = entry.vehicle
	if not isUnlocked(vehicle) then
		MarketplaceService:PromptGamePassPurchase(player, vehicle.GamepassId)
		return
	end

	state.busy = true
	updateSpawnButton("SPAWNING...")
	local ok, success, message = pcall(spawnRemote.InvokeServer, spawnRemote, vehicle.Name)
	state.busy = false
	updateSpawnButton()

	if not ok then
		notify("Couldn't reach the server. Try again.", false)
	else
		notify(message or (if success then "Vehicle spawned!" else "Couldn't spawn the vehicle."), success)
		if success and Settings.CloseMenuOnSpawn then
			setOpen(false)
		end
	end
end)

header:WaitForChild("DespawnButton").Activated:Connect(function()
	if state.busy then
		return
	end
	state.busy = true
	local ok, success, message = pcall(despawnRemote.InvokeServer, despawnRemote)
	state.busy = false
	if ok then
		notify(message, success)
	else
		notify("Couldn't reach the server. Try again.", false)
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who, passId, purchased)
	if who == player and purchased then
		owned[passId] = true
		refreshCards()
		notify("Gamepass unlocked!", true)
	end
end)

if available then
	available.ChildAdded:Connect(refreshList)
	available.ChildRemoved:Connect(refreshList)
end

-- Vehicles may hide Roblox's touch controls while riding (their own touch
-- buttons replace them). Make sure they come back once the player is off.
local function restoreTouchControls()
	if player:GetAttribute("VehicleTouchControlsHidden") then
		player:SetAttribute("VehicleTouchControlsHidden", nil)
		GuiService.TouchControlsEnabled = true
	end
end

local function watchCharacter(character)
	restoreTouchControls()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if not humanoid.SeatPart then
				restoreTouchControls()
			end
		end)
	end
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

styleTabs()
styleSort()
refreshList()

state.open = Settings.OpenOnJoin == true
main.Visible = state.open
backdrop.Visible = state.open
