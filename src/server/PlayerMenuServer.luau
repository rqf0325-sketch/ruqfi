--[[
	PlayerMenuServer (ServerScriptService)

	Server side of PlayerMenuGui. Everything the client asks for is checked
	here: the target must be in this server, cooldowns and distances are
	enforced, chat is filtered, and carrying needs the other player's consent.

	What it publishes on every Player (attributes), read by the GUI:
	  PMKisses, PMFollowers, PMFollowing, PMFriends   numbers
	  PMRole, PMTitle                                 strings
	  PMRoleColor, PMNameColorA, PMNameColorB         Color3
	  PMJoined                                        server time the player joined
	Other scripts may change the role / title attributes at any time.

	Kiss and Follow counts live in a DataStore (Settings.DataStoreName).
	Without Studio API access the counts work but are not saved.
]]

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local shared = ReplicatedStorage:WaitForChild("PlayerMenu")
local Config = require(shared:WaitForChild("Config"))
local Settings = Config.Settings

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
local kissRemote = getOrCreate(remotes, "RemoteFunction", "Kiss")
local followRemote = getOrCreate(remotes, "RemoteFunction", "Follow")
local carryRemote = getOrCreate(remotes, "RemoteFunction", "Carry")
local chatRemote = getOrCreate(remotes, "RemoteFunction", "SendMessage")
local notifyRemote = getOrCreate(remotes, "RemoteEvent", "Notify")

local function fail(message, extra)
	local result = { ok = false, message = message }
	if extra then
		for key, value in extra do
			result[key] = value
		end
	end
	return result
end

local function notify(player, kind, data)
	if player.Parent == Players then
		notifyRemote:FireClient(player, kind, data)
	end
end

local function findTarget(player, targetUserId)
	if typeof(targetUserId) ~= "number" then
		return nil
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if target == nil or target == player then
		return nil
	end
	return target
end

-- Character, Humanoid and root part of a living player.
local function characterParts(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil
end

local function distanceBetween(a, b)
	local _, _, rootA = characterParts(a)
	local _, _, rootB = characterParts(b)
	if not rootA or not rootB then
		return math.huge
	end
	return (rootA.Position - rootB.Position).Magnitude
end

-- One call per `interval` seconds per player and action.
local lastCall = {}

local function throttled(player, key, interval)
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local now = os.clock()
	if calls[key] and now - calls[key] < interval then
		return true
	end
	calls[key] = now
	return false
end

---------------------------------------------------------------------------
-- Profiles: kisses, followers and who each player follows
---------------------------------------------------------------------------

local profiles = {} -- [Player] = { kisses, followers, following, loaded, volatile, dirty }
local saving = 0

local store
if Settings.SaveData then
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, Settings.DataStoreName)
	if ok then
		store = result
	else
		warn("[PlayerMenu] DataStore is not available:", result)
	end
end

local function withRetry(callback)
	local lastError
	for attempt = 1, 3 do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < 3 then
			task.wait(attempt)
		end
	end
	return false, lastError
end

local function dataKey(userId)
	return "u_" .. userId
end

local function followingCount(profile)
	local count = 0
	for _ in profile.following do
		count += 1
	end
	return count
end

local function publish(player, profile)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute("PMKisses", profile.kisses)
	player:SetAttribute("PMFollowers", profile.followers)
	player:SetAttribute("PMFollowing", followingCount(profile))
end

local function loadProfile(player)
	local profile = { kisses = 0, followers = 0, following = {}, loaded = false, volatile = false, dirty = false }
	profiles[player] = profile

	if store then
		local ok, data = withRetry(function()
			return store:GetAsync(dataKey(player.UserId))
		end)
		if not ok then
			-- Never overwrite saved data with an empty profile.
			profile.volatile = true
			warn(`[PlayerMenu] Could not load data for {player.Name}; their counts will not be saved this session: {data}`)
		elseif type(data) == "table" then
			profile.kisses = tonumber(data.Kisses) or 0
			profile.followers = tonumber(data.Followers) or 0
			if type(data.Following) == "table" then
				for _, userId in data.Following do
					if type(userId) == "number" then
						profile.following[userId] = true
					end
				end
			end
		end
	else
		profile.volatile = true
	end

	if profiles[player] ~= profile then
		return -- left while loading
	end
	profile.loaded = true
	publish(player, profile)
end

local function saveProfile(userId, profile)
	if profile.volatile or not store or not profile.loaded or not profile.dirty then
		return
	end
	profile.dirty = false
	local following = {}
	for followedId in profile.following do
		table.insert(following, followedId)
	end
	saving += 1
	local ok, err = withRetry(function()
		store:UpdateAsync(dataKey(userId), function(old)
			old = if type(old) == "table" then old else {}
			old.Kisses = profile.kisses
			old.Followers = profile.followers
			old.Following = following
			return old
		end)
	end)
	saving -= 1
	if not ok then
		profile.dirty = true
		warn(`[PlayerMenu] Could not save data for user {userId}: {err}`)
	end
end

---------------------------------------------------------------------------
-- Roles, titles and friend count
---------------------------------------------------------------------------

local passCache = {}

local function ownsPass(player, passId)
	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	if cache[passId] == nil then
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if not ok then
			warn("[PlayerMenu] Gamepass check failed:", owns)
			return false
		end
		cache[passId] = owns
	end
	return cache[passId]
end

local function roleMatches(player, role)
	if role.UserIds and table.find(role.UserIds, player.UserId) then
		return true
	end
	if role.GroupId and role.GroupId ~= 0 then
		local ok, rank = pcall(player.GetRankInGroup, player, role.GroupId)
		if ok and rank >= (role.MinRank or 1) then
			return true
		end
	end
	if role.GamepassId and role.GamepassId ~= 0 and ownsPass(player, role.GamepassId) then
		return true
	end
	return false
end

local function applyRole(player)
	local matched
	for _, role in Config.Roles do
		if roleMatches(player, role) then
			matched = role
			break
		end
	end
	if player.Parent ~= Players then
		return
	end
	local title = Config.Titles[player.UserId] or (matched and matched.Title) or Config.DefaultTitle or ""
	local nameColors = matched and matched.NameColors
	player:SetAttribute("PMRole", matched and matched.Name or "")
	player:SetAttribute("PMRoleColor", matched and matched.Color or nil)
	player:SetAttribute("PMNameColorA", nameColors and nameColors[1] or nil)
	player:SetAttribute("PMNameColorB", nameColors and nameColors[2] or nil)
	player:SetAttribute("PMTitle", title)
end

local function loadFriendCount(player)
	local ok, pages = pcall(Players.GetFriendsAsync, Players, player.UserId)
	if not ok then
		return
	end
	local count = 0
	for _ = 1, 20 do
		count += #pages:GetCurrentPage()
		if pages.IsFinished or not pcall(pages.AdvanceToNextPageAsync, pages) then
			break
		end
	end
	if player.Parent == Players then
		player:SetAttribute("PMFriends", count)
	end
end

---------------------------------------------------------------------------
-- Kiss
---------------------------------------------------------------------------

local kissClock = {} -- [giver] = { [targetUserId] = os.clock() }

kissRemote.OnServerInvoke = function(player, targetUserId)
	if throttled(player, "Kiss", 0.25) then
		return fail("Slow down")
	end
	local target = findTarget(player, targetUserId)
	if not target then
		return fail("Player not found")
	end
	local profile = profiles[target]
	if not profile or not profile.loaded then
		return fail("Profile is still loading")
	end

	local given = kissClock[player]
	if not given then
		given = {}
		kissClock[player] = given
	end
	local remaining = (given[target.UserId] or -math.huge) + Settings.KissCooldown - os.clock()
	if remaining > 0 then
		return fail(`Wait {math.ceil(remaining)}s to kiss {target.DisplayName} again`, { wait = remaining })
	end
	if Settings.KissMaxDistance > 0 and distanceBetween(player, target) > Settings.KissMaxDistance then
		return fail(`{target.DisplayName} is too far away`)
	end

	given[target.UserId] = os.clock()
	profile.kisses += 1
	profile.dirty = true
	publish(target, profile)
	notifyRemote:FireAllClients("Kissed", { from = player.UserId, to = target.UserId })
	return { ok = true, count = profile.kisses }
end

---------------------------------------------------------------------------
-- Follow
---------------------------------------------------------------------------

followRemote.OnServerInvoke = function(player, action, targetUserId)
	local mine = profiles[player]
	if not mine or not mine.loaded then
		return fail("Profile is still loading")
	end

	if action == "List" then
		local ids = {}
		for userId in mine.following do
			table.insert(ids, userId)
		end
		return { ok = true, ids = ids }
	end

	if action ~= "Toggle" or not Settings.FollowEnabled then
		return fail("Follow is not available")
	end
	if throttled(player, "Follow", 0.6) then
		return fail("Slow down")
	end
	local target = findTarget(player, targetUserId)
	local theirs = target and profiles[target]
	if not target or not theirs or not theirs.loaded then
		return fail("Player not found")
	end

	local nowFollowing = mine.following[target.UserId] == nil
	if nowFollowing then
		mine.following[target.UserId] = true
		theirs.followers += 1
	else
		mine.following[target.UserId] = nil
		theirs.followers = math.max(0, theirs.followers - 1)
	end
	mine.dirty = true
	theirs.dirty = true
	publish(player, mine)
	publish(target, theirs)

	if nowFollowing then
		notify(target, "Toast", { text = `{player.DisplayName} started following you`, ok = true })
	end
	return { ok = true, following = nowFollowing, followers = theirs.followers }
end

---------------------------------------------------------------------------
-- Carry: the carried player sits on an invisible seat welded to the
-- carrier's back. They leave by jumping; the carrier puts them down.
---------------------------------------------------------------------------

local carrying = {} -- [carrier] = { target, seat, seated, connections }
local carriedBy = {} -- [target] = carrier
local pendingCarry = {} -- [target] = { from, expires }

local function isBusy(player)
	return carrying[player] ~= nil or carriedBy[player] ~= nil
end

local function endCarry(carrier)
	local info = carrying[carrier]
	if not info then
		return
	end
	carrying[carrier] = nil
	if carriedBy[info.target] == carrier then
		carriedBy[info.target] = nil
	end
	for _, connection in info.connections do
		connection:Disconnect()
	end

	local targetCharacter = info.target.Character
	local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
	if info.seat.Parent then
		info.seat:Destroy()
	end
	if humanoid then
		humanoid.Sit = false
	end
	notify(carrier, "CarryEnded", {})
	notify(info.target, "CarryEnded", {})
end

local function startCarry(carrier, target)
	local carrierCharacter, carrierHumanoid, carrierRoot = characterParts(carrier)
	local targetCharacter, targetHumanoid = characterParts(target)
	if not carrierCharacter or not targetCharacter then
		return false, "Player is not available"
	end
	if carrierHumanoid.SeatPart or targetHumanoid.SeatPart then
		return false, "Can't carry while someone is sitting"
	end

	local seat = Instance.new("Seat")
	seat.Name = "PlayerMenuCarrySeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CanQuery = false
	seat.Massless = true
	seat.CFrame = carrierRoot.CFrame * Settings.CarryOffset
	local weld = Instance.new("Weld")
	weld.Part0 = carrierRoot
	weld.Part1 = seat
	weld.C0 = Settings.CarryOffset
	weld.Parent = seat
	seat.Parent = carrierCharacter

	local info = { target = target, seat = seat, seated = false, connections = {} }
	carrying[carrier] = info
	carriedBy[target] = carrier

	local function watch(signal, callback)
		table.insert(info.connections, signal:Connect(callback))
	end
	watch(seat:GetPropertyChangedSignal("Occupant"), function()
		if seat.Occupant ~= nil then
			info.seated = true
		elseif info.seated then
			endCarry(carrier) -- the carried player jumped off
		end
	end)
	watch(carrierHumanoid.Died, function()
		endCarry(carrier)
	end)
	watch(targetHumanoid.Died, function()
		endCarry(carrier)
	end)
	watch(carrierCharacter.AncestryChanged, function()
		if not carrierCharacter:IsDescendantOf(workspace) then
			endCarry(carrier)
		end
	end)
	watch(targetCharacter.AncestryChanged, function()
		if not targetCharacter:IsDescendantOf(workspace) then
			endCarry(carrier)
		end
	end)

	seat:Sit(targetHumanoid)
	task.delay(3, function()
		if carrying[carrier] == info and not info.seated then
			endCarry(carrier) -- seating never worked
		end
	end)

	notify(carrier, "CarryStarted", { role = "carrier", userId = target.UserId, name = target.DisplayName })
	notify(target, "CarryStarted", { role = "carried", userId = carrier.UserId, name = carrier.DisplayName })
	return true
end

local function canCarry(carrier, target)
	if isBusy(carrier) then
		return false, "You are already carrying or being carried"
	end
	if isBusy(target) then
		return false, `{target.DisplayName} is busy`
	end
	if distanceBetween(carrier, target) > Settings.CarryMaxDistance then
		return false, `Get closer to {target.DisplayName}`
	end
	return true
end

carryRemote.OnServerInvoke = function(player, action, otherUserId)
	if not Settings.CarryEnabled then
		return fail("Carry is turned off")
	end

	if action == "Drop" then
		if carrying[player] then
			endCarry(player)
			return { ok = true }
		elseif carriedBy[player] then
			endCarry(carriedBy[player])
			return { ok = true }
		end
		return fail("Nobody to put down")
	end

	if action == "Request" then
		if throttled(player, "CarryRequest", 0.5) then
			return fail("Slow down")
		end
		local target = findTarget(player, otherUserId)
		if not target then
			return fail("Player not found")
		end
		local allowed, reason = canCarry(player, target)
		if not allowed then
			return fail(reason)
		end
		if not Settings.CarryRequiresConsent then
			local started, message = startCarry(player, target)
			if not started then
				return fail(message)
			end
			return { ok = true, message = `Carrying {target.DisplayName}` }
		end

		local existing = pendingCarry[target]
		if existing and existing.from ~= player and existing.expires > os.clock() then
			return fail(`{target.DisplayName} already has a request`)
		end
		local entry = { from = player, expires = os.clock() + Settings.CarryRequestTimeout }
		pendingCarry[target] = entry
		notify(target, "CarryRequest", {
			userId = player.UserId,
			name = player.DisplayName,
			timeout = Settings.CarryRequestTimeout,
		})
		task.delay(Settings.CarryRequestTimeout, function()
			if pendingCarry[target] == entry then
				pendingCarry[target] = nil
				notify(target, "CarryRequestEnded", { userId = player.UserId })
				notify(player, "Toast", { text = `{target.DisplayName} did not answer`, ok = false })
			end
		end)
		return { ok = true, message = `Request sent to {target.DisplayName}` }
	end

	if action == "Accept" or action == "Decline" then
		local entry = pendingCarry[player]
		if not entry or entry.expires < os.clock() or entry.from.UserId ~= otherUserId or entry.from.Parent ~= Players then
			pendingCarry[player] = nil
			return fail("That request has expired")
		end
		pendingCarry[player] = nil
		if action == "Decline" then
			notify(entry.from, "Toast", { text = `{player.DisplayName} declined`, ok = false })
			return { ok = true }
		end
		local allowed, reason = canCarry(entry.from, player)
		if not allowed then
			return fail(reason)
		end
		local started, message = startCarry(entry.from, player)
		if not started then
			return fail(message)
		end
		return { ok = true }
	end

	return fail("Unknown action")
end

---------------------------------------------------------------------------
-- Private chat (filtered by Roblox for the person who reads it)
---------------------------------------------------------------------------

chatRemote.OnServerInvoke = function(player, targetUserId, text)
	if not Settings.PrivateChatEnabled then
		return fail("Private chat is turned off")
	end
	if typeof(text) ~= "string" then
		return fail("Invalid message")
	end
	if throttled(player, "Chat", 0.6) then
		return fail("Slow down")
	end
	local target = findTarget(player, targetUserId)
	if not target then
		return fail("Player not found")
	end

	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	local length = utf8.len(text)
	if text == "" or not length then
		return fail("Invalid message")
	end
	if length > Settings.ChatMaxLength then
		return fail(`Message is too long (max {Settings.ChatMaxLength})`)
	end

	local canChat, allowed = pcall(TextChatService.CanUsersDirectChatAsync, TextChatService, player.UserId, { target.UserId })
	if canChat and type(allowed) == "table" and not table.find(allowed, target.UserId) then
		return fail("You can't chat with this player")
	end

	local filtered, result = pcall(TextService.FilterStringAsync, TextService, text, player.UserId, Enum.TextFilterContext.PrivateChat)
	if not filtered then
		return fail("Message could not be sent")
	end
	local okTarget, forTarget = pcall(result.GetChatForUserAsync, result, target.UserId)
	local okSelf, forSelf = pcall(result.GetChatForUserAsync, result, player.UserId)
	if not okTarget or not okSelf then
		return fail("Message could not be sent")
	end

	notify(target, "Chat", { from = player.UserId, name = player.DisplayName, text = forTarget })
	return { ok = true, text = forSelf }
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function onPlayerAdded(player)
	player:SetAttribute("PMJoined", workspace:GetServerTimeNow())
	task.spawn(loadProfile, player)
	task.spawn(applyRole, player)
	if Settings.ShowFriendCount then
		task.spawn(loadFriendCount, player)
	end
end

local function onPlayerRemoving(player)
	endCarry(player)
	if carriedBy[player] then
		endCarry(carriedBy[player])
	end
	pendingCarry[player] = nil
	for target, entry in pendingCarry do
		if entry.from == player then
			pendingCarry[target] = nil
		end
	end
	kissClock[player] = nil
	lastCall[player] = nil
	passCache[player] = nil

	local profile = profiles[player]
	profiles[player] = nil
	if profile then
		task.spawn(saveProfile, player.UserId, profile)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Autosave
task.spawn(function()
	while true do
		task.wait(120)
		for player, profile in profiles do
			task.spawn(saveProfile, player.UserId, profile)
		end
	end
end)

game:BindToClose(function()
	for player, profile in profiles do
		task.spawn(saveProfile, player.UserId, profile)
	end
	local deadline = os.clock() + 25
	task.wait()
	while saving > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
