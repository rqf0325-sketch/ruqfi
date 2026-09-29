--[[
	Smoke test for the Player Menu: runs the real scripts from the built model
	files (PlayerMenuServer, PlayerMenuClient, PlayerMenuNametags) inside a small
	fake Roblox world with two players, and drives them end to end: tap a
	player, Kiss, Follow, Carry (request / accept / put down), Private Chat,
	roles, saving, and the nametags.

	  lune run tools/build-player-menu.luau
	  lune run tools/test-player-menu.luau

	It is not Roblox: physics, rendering and tweens are stubbed. It catches
	mistakes in script logic and in object names between the GUI and its scripts.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local RealInstance = roblox.Instance
local realTypeof = typeof

---------------------------------------------------------------------------
-- Scheduler (task library) driven by the test
---------------------------------------------------------------------------

local errors = {}
local now = 0
local queue = {}

local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(errors, tostring(err) .. "\n" .. debug.traceback(co))
	end
end

local function schedule(delay, fn)
	table.insert(queue, { at = now + delay, fn = fn, n = #queue })
end

local task = {}
function task.spawn(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.delay(seconds, fn, ...)
	local args = table.pack(...)
	schedule(seconds, function()
		task.spawn(fn, table.unpack(args, 1, args.n))
	end)
end
function task.defer(fn, ...)
	local args = table.pack(...)
	schedule(0, function()
		task.spawn(fn, table.unpack(args, 1, args.n))
	end)
end
function task.wait(seconds)
	local co = coroutine.running()
	schedule(seconds or 0, function()
		resume(co)
	end)
	coroutine.yield()
	return seconds or 0
end

local function advance(seconds)
	local target = now + seconds
	while true do
		local best
		for index, item in queue do
			if item.at <= target and (not best or item.at < queue[best].at or (item.at == queue[best].at and item.n < queue[best].n)) then
				best = index
			end
		end
		if not best then
			break
		end
		local item = table.remove(queue, best)
		now = math.max(now, item.at)
		item.fn()
	end
	now = target
end

---------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end
function Signal:Connect(fn)
	local handler = { fn = fn, on = true }
	table.insert(self.handlers, handler)
	return {
		Disconnect = function()
			handler.on = false
		end,
	}
end
function Signal:Fire(...)
	for _, handler in table.clone(self.handlers) do
		if handler.on then
			task.spawn(handler.fn, ...)
		end
	end
end

---------------------------------------------------------------------------
-- Instance proxy: real Lune instances plus what Studio has and Lune lacks
-- (WaitForChild, events, a few properties and methods).
---------------------------------------------------------------------------

-- Lune hands out a new userdata for the same instance each time, so tables are keyed by GetDebugId().
local proxyToInst = {}
local instToProxy = {}
local extras = {}
local signalTable = {}

local function idOf(inst)
	return inst:GetDebugId()
end
local fakeObjects = {} -- Player fakes count as Instances for typeof()
local remoteInbox = {} -- [Player] = { {kind, data} } for players without a client here
local LOCAL_PLAYER

local EVENTS = {}
for _, name in {
	"Activated", "MouseEnter", "MouseLeave", "FocusLost", "OnClientEvent", "Died", "Seated",
	"AncestryChanged", "Destroying", "AttributeChanged", "Event",
} do
	EVENTS[name] = true
end

-- Members Studio has that Lune's database lacks; reading them gives the stored value or nil.
local OPTIONAL = { Interactable = true, Occupant = true, SeatPart = true, CurrentCamera = true, OnServerInvoke = true, AbsoluteCanvasSize = true }

local function signalFor(inst, name)
	local perInst = signalTable[idOf(inst)]
	if not perInst then
		perInst = {}
		signalTable[idOf(inst)] = perInst
	end
	local signal = perInst[name]
	if not signal then
		signal = Signal.new()
		perInst[name] = signal
	end
	return signal
end

local wrap, unwrap

function unwrap(value)
	return proxyToInst[value] or value
end

-- Results of Instance methods: Instances, or arrays of them (GetChildren, ...).
local function wrapAll(...)
	local packed = table.pack(...)
	for i = 1, packed.n do
		local value = packed[i]
		if type(value) == "table" and getmetatable(value) == nil then
			local copy = {}
			for key, item in value do
				copy[key] = wrap(item)
			end
			packed[i] = copy
		else
			packed[i] = wrap(value)
		end
	end
	return table.unpack(packed, 1, packed.n)
end

local function unwrapAll(...)
	local packed = table.pack(...)
	for i = 1, packed.n do
		packed[i] = unwrap(packed[i])
	end
	return packed
end

local meta = {}

function wrap(value)
	if realTypeof(value) ~= "Instance" then
		return value
	end
	local proxy = instToProxy[idOf(value)]
	if not proxy then
		proxy = setmetatable({}, meta)
		proxyToInst[proxy] = value
		instToProxy[idOf(value)] = proxy
	end
	return proxy
end

local function setExtra(inst, key, value)
	local bag = extras[idOf(inst)]
	if not bag then
		bag = {}
		extras[idOf(inst)] = bag
	end
	bag[key] = value
end

local function fireAttribute(inst, name)
	signalFor(inst, "AttributeChanged"):Fire(name)
end

local function destroySeat(inst)
	setExtra(inst, "Occupant", nil)
	signalFor(inst, "prop:Occupant"):Fire()
end

meta.__index = function(proxy, key)
	local inst = proxyToInst[proxy]
	if key == "WaitForChild" then
		return function(_, name)
			local child = inst:FindFirstChild(name)
			if not child then
				error(`WaitForChild: {inst:GetFullName()} has no child "{name}"`, 2)
			end
			return wrap(child)
		end
	elseif key == "GetPropertyChangedSignal" then
		return function(_, name)
			return signalFor(inst, "prop:" .. name)
		end
	elseif key == "SetAttribute" then
		return function(_, name, value)
			inst:SetAttribute(name, value)
			fireAttribute(inst, name)
		end
	elseif key == "Destroy" then
		return function()
			if inst.ClassName == "Seat" then
				destroySeat(inst)
			end
			inst:Destroy()
		end
	elseif key == "Sit" and inst.ClassName == "Seat" then
		return function(_, humanoid)
			setExtra(inst, "Occupant", humanoid)
			signalFor(inst, "prop:Occupant"):Fire()
		end
	elseif key == "CaptureFocus" or key == "Play" or key == "Stop" then
		return function() end
	elseif key == "Fire" and inst.ClassName == "BindableEvent" then
		return function(_, ...)
			signalFor(inst, "Event"):Fire(...)
		end
	elseif key == "FireClient" and inst.ClassName == "RemoteEvent" then
		return function(_, player, ...)
			if player == LOCAL_PLAYER then
				signalFor(inst, "OnClientEvent"):Fire(...)
			else
				remoteInbox[player] = remoteInbox[player] or {}
				table.insert(remoteInbox[player], table.pack(...))
			end
		end
	elseif key == "FireAllClients" and inst.ClassName == "RemoteEvent" then
		return function(_, ...)
			signalFor(inst, "OnClientEvent"):Fire(...)
		end
	elseif key == "InvokeServer" and inst.ClassName == "RemoteFunction" then
		return function(_, ...)
			local handler = extras[idOf(inst)] and extras[idOf(inst)].OnServerInvoke
			assert(handler, `{inst.Name} has no OnServerInvoke`)
			return handler(LOCAL_PLAYER, ...)
		end
	elseif EVENTS[key] then
		return signalFor(inst, key)
	end

	local bag = extras[idOf(inst)]
	if bag and bag[key] ~= nil then
		return bag[key]
	end
	if key == "AbsoluteSize" and inst.ClassName == "ScreenGui" then
		return roblox.Vector2.new(1280, 720)
	elseif key == "AbsoluteCanvasSize" then
		return roblox.Vector2.new(276, 400)
	elseif key == "Position" and inst:IsA("BasePart") then
		return inst.CFrame.Position
	end
	local ok, value = pcall(function()
		return inst[key]
	end)
	if ok then
		if type(value) == "function" then
			return function(_, ...)
				local args = unwrapAll(...)
				return wrapAll(value(inst, table.unpack(args, 1, args.n)))
			end
		end
		return wrap(value)
	end
	if OPTIONAL[key] then
		return nil
	end
	error(`{key} is not a valid member of {inst.ClassName} "{inst:GetFullName()}"`, 2)
end

meta.__newindex = function(proxy, key, value)
	local inst = proxyToInst[proxy]
	value = unwrap(value)
	local ok = pcall(function()
		inst[key] = value
	end)
	if not ok or OPTIONAL[key] then
		setExtra(inst, key, value)
	end
	signalFor(inst, "prop:" .. key):Fire()
end

meta.__tostring = function(proxy)
	return proxyToInst[proxy]:GetFullName()
end

---------------------------------------------------------------------------
-- Fake world: services, players, characters
---------------------------------------------------------------------------

local worldRoot = RealInstance.new("Folder")
worldRoot.Name = "Workspace"
local workspaceProxy = wrap(worldRoot)
local serverTimeBase = 1000
local raycastResult

local cameraStub = {
	ViewportSize = roblox.Vector2.new(1280, 720),
	CFrame = roblox.CFrame.new(0, 10, 20),
	FieldOfView = 70,
	ScreenPointToRay = function()
		return { Origin = roblox.Vector3.new(0, 10, 20), Direction = roblox.Vector3.new(0, 0, -1) }
	end,
}

extras[idOf(worldRoot)] = {
	GetServerTimeNow = function()
		return serverTimeBase + now
	end,
	CurrentCamera = cameraStub,
	Raycast = function()
		return raycastResult
	end,
}

local playersService
local players = {}

local function makeSignals()
	return {
		AttributeChanged = Signal.new(),
		CharacterAdded = Signal.new(),
		DisplayNameChanged = Signal.new(),
	}
end

local function makePlayer(userId, name, displayName)
	local player = { UserId = userId, Name = name, DisplayName = displayName, AccountAge = 800, Parent = nil }
	player.MembershipType = roblox.Enum.MembershipType.Premium
	local attributes = {}
	local signals = makeSignals()
	player.AttributeChanged = signals.AttributeChanged
	player.CharacterAdded = signals.CharacterAdded
	function player:GetAttribute(attribute)
		return attributes[attribute]
	end
	function player:SetAttribute(attribute, value)
		attributes[attribute] = value
		signals.AttributeChanged:Fire(attribute)
	end
	function player:IsA(className)
		return className == "Player" or className == "Instance"
	end
	function player:GetPropertyChangedSignal(property)
		return if property == "DisplayName" then signals.DisplayNameChanged else Signal.new()
	end
	function player:GetRankInGroup()
		return 0
	end
	function player:IsFriendsWith(otherId)
		return player.friends and player.friends[otherId] == true
	end
	fakeObjects[player] = true
	return player
end

local function makeCharacter(player, position)
	local model = RealInstance.new("Model")
	model.Name = player.Name
	local humanoid = RealInstance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = model
	local root = RealInstance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.CFrame = roblox.CFrame.new(position)
	root.Parent = model
	local head = RealInstance.new("Part")
	head.Name = "Head"
	head.Size = roblox.Vector3.new(2, 1, 1)
	head.CFrame = roblox.CFrame.new(position + roblox.Vector3.new(0, 1.5, 0))
	head.Parent = model
	model.Parent = worldRoot
	player.Character = wrap(model)
	player.CharacterAdded:Fire(player.Character)
	return model, humanoid, root, head
end

playersService = {
	PlayerAdded = Signal.new(),
	PlayerRemoving = Signal.new(),
	GetPlayers = function()
		return table.clone(players)
	end,
	GetPlayerByUserId = function(_, userId)
		for _, player in players do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end,
	GetPlayerFromCharacter = function(_, character)
		for _, player in players do
			if player.Character == character then
				return player
			end
		end
		return nil
	end,
	GetFriendsAsync = function(_, userId)
		local count = if userId == 1 then 329 else 3
		local page = {}
		for i = 1, count do
			page[i] = i
		end
		return { IsFinished = true, GetCurrentPage = function()
			return page
		end, AdvanceToNextPageAsync = function() end }
	end,
	GetUserThumbnailAsync = function(_, userId)
		return `rbxthumb://{userId}`, true
	end,
}

local function addPlayer(player)
	player.Parent = playersService
	table.insert(players, player)
	playersService.PlayerAdded:Fire(player)
end

local function removePlayer(player)
	playersService.PlayerRemoving:Fire(player)
	table.remove(players, table.find(players, player))
	player.Parent = nil
end

-- DataStore stub
local dataStoreData = {}
local dataStoreFails = false
local updateCalls = 0
local dataStore = {
	GetAsync = function(_, key)
		if dataStoreFails then
			error("DataStore unavailable")
		end
		return dataStoreData[key]
	end,
	UpdateAsync = function(_, key, callback)
		if dataStoreFails then
			error("DataStore unavailable")
		end
		updateCalls += 1
		dataStoreData[key] = callback(dataStoreData[key])
	end,
}

local closeCallbacks = {}
local starterGuiCalls = {}

local services = {
	Players = playersService,
	DataStoreService = { GetDataStore = function()
		return dataStore
	end },
	MarketplaceService = { UserOwnsGamePassAsync = function()
		return false
	end },
	TextChatService = { CanUsersDirectChatAsync = function(_, _, ids)
		return ids
	end },
	TextService = { FilterStringAsync = function(_, text)
		local filtered = string.gsub(text, "badword", "#######")
		return { GetChatForUserAsync = function()
			return filtered
		end }
	end },
	RunService = { RenderStepped = Signal.new(), Heartbeat = Signal.new() },
	StarterGui = { SetCore = function(_, name, value)
		table.insert(starterGuiCalls, { name, value })
	end },
	TweenService = { Create = function(_, inst, _, props)
		return { Play = function()
			for key, value in props do
				inst[key] = value
			end
		end }
	end },
	UserInputService = { InputBegan = Signal.new(), InputEnded = Signal.new(), TouchEnabled = false },
	Debris = { AddItem = function() end },
}

local shared = RealInstance.new("Folder")
shared.Name = "ReplicatedStorage"

local game = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then
			return wrap(shared)
		end
		return assert(services[name], `service {name} is not faked`)
	end,
	BindToClose = function(_, callback)
		table.insert(closeCallbacks, callback)
	end,
}

---------------------------------------------------------------------------
-- Load the real scripts from the built files
---------------------------------------------------------------------------

local function readModel(path)
	assert(fs.isFile(path), `{path} is missing; run lune run tools/build-player-menu.luau first`)
	return roblox.deserializeModel(fs.readFile(path))[1]
end

local guiModel = readModel("StarterGui/PlayerMenuGui.rbxmx")
local sharedModel = readModel("ReplicatedStorage/PlayerMenu.rbxmx")
local serverModel = readModel("ServerScriptService/PlayerMenuServer.rbxmx")
sharedModel.Parent = shared

local moduleCache = {}
local baseEnv = getfenv(1)

local function makeEnv(scriptInstance)
	local env = setmetatable({
		game = game,
		workspace = workspaceProxy,
		script = wrap(scriptInstance),
		task = task,
		os = setmetatable({ clock = function()
			return now
		end }, { __index = os }),
		typeof = function(value)
			if proxyToInst[value] or fakeObjects[value] then
				return "Instance"
			end
			return realTypeof(value)
		end,
		Instance = { new = function(className)
			return wrap(RealInstance.new(className))
		end },
		Enum = roblox.Enum,
		Font = roblox.Font,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		Color3 = roblox.Color3,
		CFrame = roblox.CFrame,
		ColorSequence = roblox.ColorSequence,
		NumberSequence = roblox.NumberSequence,
		TweenInfo = { new = function(...)
			return { ... }
		end },
		RaycastParams = { new = function()
			return {}
		end },
		warn = function(...)
			table.insert(errors, "warn: " .. table.concat(table.pack(...), " "))
		end,
	}, { __index = baseEnv })
	env.require = function(moduleScript)
		local inst = unwrap(moduleScript)
		if not moduleCache[idOf(inst)] then
			moduleCache[idOf(inst)] = luau.load(inst.Source, { debugName = inst.Name, environment = makeEnv(inst) })()
		end
		return moduleCache[idOf(inst)]
	end
	return env
end

local function run(scriptInstance)
	local chunk = luau.load(scriptInstance.Source, { debugName = scriptInstance.Name, environment = makeEnv(scriptInstance) })
	task.spawn(chunk)
end

---------------------------------------------------------------------------
-- Test helpers
---------------------------------------------------------------------------

local passed, failed = 0, 0

local function check(condition, message)
	if condition then
		passed += 1
	else
		failed += 1
		print(`FAIL: {message}`)
	end
end

local function checkEq(actual, expected, message)
	check(actual == expected, `{message} (expected {expected}, got {actual})`)
end

local function noErrors(stage)
	if #errors > 0 then
		failed += #errors
		print(`FAIL: errors during {stage}:`)
		for _, err in errors do
			print("  " .. err)
		end
		table.clear(errors)
	end
end

local function handlerOf(remote)
	return extras[idOf(unwrap(remote))].OnServerInvoke
end

local function fire(button)
	signalFor(unwrap(button), "Activated"):Fire()
end

---------------------------------------------------------------------------
-- The scenario
---------------------------------------------------------------------------

local function scenario()
	-- Config tweaks for the test: A is an administrator.
	local Config = makeEnv(serverModel).require(sharedModel:FindFirstChild("Config"))
	Config.Roles[1].UserIds = { 1 }
	Config.Titles[1] = "✨RAKYAT KECIL✨"
	Config.Settings.KissCooldown = 2

	local playerA = makePlayer(1, "SweetPie0325", "SweetPie")
	local playerB = makePlayer(2, "PaulTheVIP", "Paul")
	LOCAL_PLAYER = playerA
	playersService.LocalPlayer = playerA
	playerA.friends = {}
	local _ = makeCharacter(playerA, roblox.Vector3.new(0, 3, 0))
	local _, humanoidB, rootB = makeCharacter(playerB, roblox.Vector3.new(4, 3, 0))

	run(serverModel)
	addPlayer(playerA)
	addPlayer(playerB)
	advance(0.1)
	noErrors("server start")

	local remotes = wrap(sharedModel):FindFirstChild("Remotes")
	local kiss = remotes:FindFirstChild("Kiss")
	local carry = remotes:FindFirstChild("Carry")
	local chat = remotes:FindFirstChild("SendMessage")
	local notifyEvent = remotes:FindFirstChild("Notify")

	-- Attributes / roles -----------------------------------------------------
	checkEq(playerA:GetAttribute("PMRole"), "ADMINISTRATOR", "role from UserIds")
	checkEq(playerA:GetAttribute("PMTitle"), "✨RAKYAT KECIL✨", "title from Config.Titles")
	check(playerA:GetAttribute("PMRoleColor") ~= nil, "role color published")
	checkEq(playerB:GetAttribute("PMRole"), "", "no role for B")
	checkEq(playerA:GetAttribute("PMFriends"), 329, "friend count")
	checkEq(playerA:GetAttribute("PMKisses"), 0, "kisses start at 0")
	check(type(playerA:GetAttribute("PMJoined")) == "number", "join time published")

	-- Client start ------------------------------------------------------------
	local clientScript = unwrap(wrap(guiModel):FindFirstChild("PlayerMenuClient"))
	local nametagScript = unwrap(wrap(guiModel):FindFirstChild("PlayerMenuNametags"))
	run(clientScript)
	run(nametagScript)
	advance(0.1)
	noErrors("client start")

	local gui = wrap(guiModel)
	local card = gui.Card
	check(card.Visible == false, "card starts hidden")
	check(gui.Toast.Visible == false and gui.CarryBar.Visible == false and gui.CarryRequest.Visible == false, "popups start hidden")
	check(gui.Card.Home.RoleChip.AutomaticSize == roblox.Enum.AutomaticSize.X, "role chip autosizes")

	-- Nametags ------------------------------------------------------------------
	local characterB = wrap(worldRoot):FindFirstChild("PaulTheVIP")
	local tagB = characterB.Head:FindFirstChild("PlayerMenuNametag")
	check(tagB ~= nil, "B has a nametag")
	if tagB then
		checkEq(tagB.Stack.PlayerName.Text, "Paul", "nametag shows display name")
		check(tagB.Stack.RoleChip.Visible == false, "no role chip for B")
		check(tagB.Stack.Title.Visible == false, "no title for B")
		check(tagB.Enabled == true, "nametag enabled")
	end
	local ownHead = wrap(worldRoot):FindFirstChild("SweetPie0325").Head
	check(ownHead:FindFirstChild("PlayerMenuNametag") == nil, "no own nametag by default")
	playerA:SetAttribute("PMRole", "ADMINISTRATOR")
	advance(0.1)

	-- Tap B in the world ----------------------------------------------------------
	raycastResult = { Instance = wrap(worldRoot):FindFirstChild("PaulTheVIP").Head }
	local inputObject = { UserInputType = roblox.Enum.UserInputType.MouseButton1, Position = roblox.Vector3.new(400, 300, 0) }
	services.UserInputService.InputBegan:Fire(inputObject, false)
	advance(0.1)
	services.UserInputService.InputEnded:Fire(inputObject, false)
	advance(0.5)
	noErrors("tap")
	check(card.Visible == true, "tapping a player opens the card")
	local home = card.Home
	checkEq(home.DisplayName.Text, "Paul", "card display name")
	checkEq(home.Username.Text, "@PaulTheVIP", "card username")
	check(home.RoleChip.Visible == false, "no role chip for a member")
	checkEq(home.Stats.Friends.Value.Text, "3", "friends stat")
	checkEq(home.Stats.Followers.Value.Text, "0", "followers stat")
	checkEq(home.Stats.Kiss.Value.Text, "💋 0", "kiss stat")
	checkEq(home.Actions.Carry.Subtitle.Text, "Piggyback ride", "carry tile idle text")
	check(home.Actions.Follow.Title.Text == "Follow", "follow tile idle")
	check(card.ProfilePage.Visible == false and card.ChatPage.Visible == false, "pages hidden")
	check(card.Home.Avatar.Portrait.ModelView.Visible == true, "3D bust built from the character")

	-- Drag is not a tap
	card.Visible = true
	local drag = { UserInputType = roblox.Enum.UserInputType.MouseButton1, Position = roblox.Vector3.new(100, 100, 0) }
	local moved = { UserInputType = roblox.Enum.UserInputType.MouseButton1, Position = roblox.Vector3.new(200, 100, 0) }
	raycastResult = { Instance = wrap(worldRoot):FindFirstChild("SweetPie0325").Head }
	services.UserInputService.InputBegan:Fire(drag, false)
	services.UserInputService.InputEnded:Fire(moved, false)
	advance(0.1)
	checkEq(home.DisplayName.Text, "Paul", "a drag does not change the card")

	-- Kiss ---------------------------------------------------------------------------
	local kissesBefore = playerB:GetAttribute("PMKisses")
	fire(home.Stats.Kiss)
	advance(1.3)
	noErrors("kiss")
	checkEq(playerB:GetAttribute("PMKisses"), kissesBefore + 1, "kiss increments the count")
	checkEq(home.Stats.Kiss.Value.Text, "💋 1", "card shows the new kiss count")
	check(#card.FxLayer:GetChildren() > 0, "card hearts spawned")
	fire(home.Stats.Kiss)
	advance(0.5)
	checkEq(playerB:GetAttribute("PMKisses"), 1, "kiss cooldown blocks a second kiss")
	check(gui.Toast.Visible == true and string.find(gui.Toast.Message.Text, "Wait") ~= nil, "cooldown toast: " .. gui.Toast.Message.Text)
	advance(2.5)
	fire(home.Stats.Kiss)
	advance(0.5)
	checkEq(playerB:GetAttribute("PMKisses"), 2, "kiss works again after the cooldown")
	check(handlerOf(kiss)(playerA, 1).ok == false, "can't kiss yourself")
	check(handlerOf(kiss)(playerA, "x").ok == false, "bad target is rejected")

	-- Follow ------------------------------------------------------------------------------
	fire(home.Actions.Follow)
	advance(0.5)
	noErrors("follow")
	checkEq(playerB:GetAttribute("PMFollowers"), 1, "follow increments followers")
	checkEq(playerA:GetAttribute("PMFollowing"), 1, "follow increments following")
	checkEq(home.Actions.Follow.Title.Text, "Following", "follow tile shows Following")
	checkEq(home.Stats.Followers.Value.Text, "1", "followers stat updates")
	advance(1)
	fire(home.Actions.Follow)
	advance(0.5)
	checkEq(playerB:GetAttribute("PMFollowers"), 0, "unfollow decrements")
	checkEq(home.Actions.Follow.Title.Text, "Follow", "follow tile back to Follow")

	-- Add friend ----------------------------------------------------------------------------
	fire(home.Actions.AddFriend)
	check(starterGuiCalls[1] and starterGuiCalls[1][1] == "PromptSendFriendRequest" and starterGuiCalls[1][2] == playerB, "friend request prompt")

	-- Profile page ----------------------------------------------------------------------------
	fire(home.Actions.Profile)
	advance(0.4)
	noErrors("profile page")
	check(card.ProfilePage.Visible == true, "profile page opens")
	local rows = card.ProfilePage.Info
	checkEq(rows.Row_UserId.Value.Text, "2", "profile user id")
	checkEq(rows.Row_Membership.Value.Text, "Premium", "profile membership")
	checkEq(rows.Row_Role.Value.Text, "Member", "profile role")
	checkEq(rows.Row_Kisses.Value.Text, "2", "profile kisses")
	check(string.find(rows.Row_AccountAge.Value.Text, "yr") ~= nil, "profile account age: " .. rows.Row_AccountAge.Value.Text)
	fire(card.ProfilePage.BackButton)
	check(card.ProfilePage.Visible == false, "back from profile")

	-- Private chat -------------------------------------------------------------------------------
	fire(home.Actions.Chat)
	advance(0.4)
	check(card.ChatPage.Visible == true, "chat page opens")
	checkEq(card.ChatPage.PageTitle.Text, "Paul", "chat title")
	check(card.ChatPage.EmptyState.Visible == true, "empty chat state")
	local input = card.ChatPage.InputBar.Field.InputBox
	input.Text = "hello badword friend"
	signalFor(unwrap(input), "FocusLost"):Fire(true)
	advance(0.5)
	noErrors("chat send")
	checkEq(input.Text, "", "input cleared after sending")
	local sentBubbles = 0
	for _, child in card.ChatPage.Messages:GetChildren() do
		if child.Name == "Message" then
			sentBubbles += 1
			checkEq(child.Bubble.Text.Text, "hello ####### friend", "message is filtered")
		end
	end
	checkEq(sentBubbles, 1, "one bubble after sending")
	local delivered = remoteInbox[playerB] and remoteInbox[playerB][#remoteInbox[playerB]]
	check(delivered ~= nil and delivered[1] == "Chat" and delivered[2].text == "hello ####### friend", "B received the message")
	input.Text = ""
	signalFor(unwrap(input), "FocusLost"):Fire(true)
	advance(1)
	check(handlerOf(chat)(playerA, 2, "   ").ok == false, "empty message rejected")
	check(handlerOf(chat)(playerA, 2, string.rep("a", 500)).ok == false, "long message rejected")
	advance(1)
	-- B replies while the chat page is open
	notifyEvent:FireClient(playerA, "Chat", { from = 2, name = "Paul", text = "hi back" })
	advance(0.5)
	noErrors("chat receive")
	local bubbles = 0
	for _, child in card.ChatPage.Messages:GetChildren() do
		if child.Name == "Message" then
			bubbles += 1
		end
	end
	checkEq(bubbles, 2, "reply appears while chat is open")
	fire(card.ChatPage.BackButton)

	-- Carry: request, accept, put down -------------------------------------------------------------
	local carryRemote = handlerOf(carry)
	fire(home.Actions.Carry)
	advance(0.5)
	noErrors("carry request")
	local request = remoteInbox[playerB]
	local requestEvent
	for _, event in request do
		if event[1] == "CarryRequest" then
			requestEvent = event[2]
		end
	end
	check(requestEvent ~= nil and requestEvent.userId == 1, "B received a carry request from A")
	check(gui.Toast.Visible == true and string.find(gui.Toast.Message.Text, "Request sent") ~= nil, "request toast: " .. gui.Toast.Message.Text)
	local accepted = carryRemote(playerB, "Accept", 1)
	advance(0.5)
	noErrors("carry accept")
	check(accepted.ok == true, "B can accept: " .. tostring(accepted.message))
	local seat = wrap(worldRoot):FindFirstChild("SweetPie0325"):FindFirstChild("PlayerMenuCarrySeat")
	check(seat ~= nil, "carry seat exists on the carrier")
	if seat then
		check(seat.Occupant == humanoidB or unwrap(seat.Occupant) == humanoidB, "B sits in the seat")
	end
	check(gui.CarryBar.Visible == true, "carry bar visible for the carrier")
	check(string.find(gui.CarryBar.Message.Text, "Carrying Paul") ~= nil, "carry bar text: " .. gui.CarryBar.Message.Text)
	checkEq(home.Actions.Carry.Title.Text, "Put Down", "carry tile becomes Put Down")
	check(carryRemote(playerB, "Accept", 1).ok == false, "a second accept fails")
	check(carryRemote(playerA, "Request", 2).ok == false, "can't request while carrying")
	fire(gui.CarryBar.DropButton)
	advance(0.5)
	noErrors("carry drop")
	check(gui.CarryBar.Visible == false, "carry bar hidden after put down")
	check(wrap(worldRoot):FindFirstChild("SweetPie0325"):FindFirstChild("PlayerMenuCarrySeat") == nil, "seat removed")
	checkEq(home.Actions.Carry.Title.Text, "Carry", "carry tile back to Carry")

	-- Carry: B jumps off, decline, expiry, distance -----------------------------------------------------
	advance(5)
	local requestedAgain = carryRemote(playerA, "Request", 2)
	check(requestedAgain.ok == true, "request again")
	check(carryRemote(playerB, "Decline", 1).ok == true, "B declines")
	check(carryRemote(playerB, "Accept", 1).ok == false, "declined request can't be accepted")
	advance(1)
	check(carryRemote(playerA, "Request", 2).ok == true, "request for expiry")
	advance(16)
	check(carryRemote(playerB, "Accept", 1).ok == false, "expired request can't be accepted")
	advance(1)
	check(carryRemote(playerA, "Request", 2).ok == true, "request before jump test")
	check(carryRemote(playerB, "Accept", 1).ok == true, "accept before jump test")
	local seat2 = wrap(worldRoot):FindFirstChild("SweetPie0325"):FindFirstChild("PlayerMenuCarrySeat")
	seat2.Occupant = nil -- B jumped off
	advance(0.5)
	check(wrap(worldRoot):FindFirstChild("SweetPie0325"):FindFirstChild("PlayerMenuCarrySeat") == nil, "jumping off ends the carry")
	check(gui.CarryBar.Visible == false, "carry bar hidden after jump")
	rootB.CFrame = roblox.CFrame.new(50, 3, 0)
	advance(1)
	check(carryRemote(playerA, "Request", 2).ok == false, "too far to carry")
	rootB.CFrame = roblox.CFrame.new(4, 3, 0)

	-- Carry request popup on the client (B carries A) ----------------------------------------------------------
	advance(1)
	notifyEvent:FireClient(playerA, "CarryRequest", { userId = 2, name = "Paul", timeout = 15 })
	advance(0.5)
	check(gui.CarryRequest.Visible == true, "carry request popup shows")
	check(string.find(gui.CarryRequest.Message.Text, "Paul wants to carry you") ~= nil, "popup text: " .. gui.CarryRequest.Message.Text)
	-- pending on the server so Accept is valid
	local pendingOk = carryRemote(playerB, "Request", 1)
	check(pendingOk.ok == true, "B requests to carry A")
	fire(gui.CarryRequest.Accept)
	advance(0.5)
	noErrors("client accept")
	check(gui.CarryRequest.Visible == false, "popup hidden after accept")
	check(gui.CarryBar.Visible == true, "carried player sees the bar")
	check(string.find(gui.CarryBar.Message.Text, "back") ~= nil, "carried text: " .. gui.CarryBar.Message.Text)
	fire(gui.CarryBar.DropButton)
	advance(0.5)
	check(gui.CarryBar.Visible == false, "carried player can get down")

	-- Incoming chat while the card shows someone else ---------------------------------------------------------------
	notifyEvent:FireClient(playerA, "Chat", { from = 2, name = "Paul", text = "ping" })
	advance(0.5)
	noErrors("incoming chat")
	check(gui.Toast.Visible == true and string.find(gui.Toast.Message.Text, "ping") ~= nil, "chat toast: " .. gui.Toast.Message.Text)
	check(home.Actions.Chat.Badge.Visible == true, "unread badge on the chat tile")
	fire(gui.Toast)
	advance(0.5)
	check(card.ChatPage.Visible == true, "tapping the toast opens the chat")
	check(home.Actions.Chat.Badge.Visible == false, "unread cleared")
	fire(card.ChatPage.BackButton)

	-- Roles: title changes at runtime ---------------------------------------------------------------------------------
	playerB:SetAttribute("PMTitle", "Dancer")
	playerB:SetAttribute("PMRole", "VIP")
	playerB:SetAttribute("PMRoleColor", roblox.Color3.fromRGB(255, 208, 84))
	advance(0.2)
	checkEq(home.Title.Text, "Dancer", "card title updates live")
	check(home.RoleChip.Visible == true and home.RoleChip.Label.Text == "VIP", "card role chip updates live")
	if tagB then
		checkEq(tagB.Stack.Title.Text, "Dancer", "nametag title updates live")
		checkEq(tagB.Stack.RoleChip.Label.Text, "VIP", "nametag role updates live")
	end

	-- Tap yourself: excluded from the ray in the real game; opening via the event -------------------------------------------
	fire(home.CloseButton)
	advance(0.5)
	check(card.Visible == false, "close hides the card")
	gui.OpenPlayer:Fire(playerA, "Home")
	advance(0.5)
	noErrors("open own card")
	check(card.Visible == true and home.DisplayName.Text == "SweetPie", "OpenPlayer event opens a card")
	check(home.Stats.Kiss.Interactable == false, "can't kiss yourself")
	check(home.Actions.Carry.Interactable == false and home.Actions.Chat.Interactable == false, "own card disables social actions")
	check(home.RoleChip.Visible == true and home.RoleChip.Label.Text == "ADMINISTRATOR", "own role chip")
	fire(home.CloseButton)
	advance(0.5)

	-- Target leaves ---------------------------------------------------------------------------------------------------------
	gui.OpenPlayer:Fire(playerB)
	advance(0.5)
	check(card.Visible == true, "card open for B")
	removePlayer(playerB)
	advance(0.5)
	check(card.Visible == false, "card closes when its player leaves")
	check(gui.Toast.Visible == true and string.find(gui.Toast.Message.Text, "left") ~= nil, "leave toast: " .. gui.Toast.Message.Text)

	-- Saving ----------------------------------------------------------------------------------------------------------------
	advance(1)
	local saved = dataStoreData["u_2"]
	check(saved ~= nil and saved.Kisses == 2, "B's kisses were saved on leaving")
	local rejoined = makePlayer(2, "PaulTheVIP", "Paul")
	makeCharacter(rejoined, roblox.Vector3.new(4, 3, 0))
	addPlayer(rejoined)
	advance(0.5)
	checkEq(rejoined:GetAttribute("PMKisses"), 2, "kisses are loaded again on rejoin")
	dataStoreFails = true
	local unlucky = makePlayer(3, "Unlucky", "Unlucky")
	makeCharacter(unlucky, roblox.Vector3.new(8, 3, 0))
	addPlayer(unlucky)
	advance(10)
	dataStoreFails = false
	checkEq(unlucky:GetAttribute("PMKisses"), 0, "profile still works when the DataStore fails")
	local updatesBefore = updateCalls
	removePlayer(unlucky)
	advance(5)
	checkEq(updateCalls, updatesBefore, "a profile that failed to load is never saved")
	table.clear(errors) -- expected DataStore warnings

	for _, callback in closeCallbacks do
		task.spawn(callback)
	end
	advance(1)
	noErrors("shutdown")
end

task.spawn(scenario)
advance(0.01)

-- The scenario yields on task.wait; give it room to finish.
advance(5)
noErrors("end")

print(`{passed} checks passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
