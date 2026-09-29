--[[
	PlayerMenuClient (LocalScript inside StarterGui.PlayerMenuGui)

	Tap / click another player to open their card: name, stats, Like, and the
	actions Profile, Carry, Add Friend, Follow and Private Chat. Also runs the
	carry request popup, the toast, and the hearts that float up when someone is liked.
	The server re-checks everything the buttons ask for.

	Other scripts can open a card with the OpenPlayer BindableEvent:
	  gui.OpenPlayer:Fire(player)          -- Player or UserId
	  gui.OpenPlayer:Fire(player, "Chat")  -- "Home", "Profile" or "Chat"
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = script.Parent

local shared = ReplicatedStorage:WaitForChild("PlayerMenu")
local Config = require(shared:WaitForChild("Config"))
local Settings = Config.Settings
local remotes = shared:WaitForChild("Remotes")
local likeRemote = remotes:WaitForChild("Like")
local followRemote = remotes:WaitForChild("Follow")
local carryRemote = remotes:WaitForChild("Carry")
local chatRemote = remotes:WaitForChild("SendMessage")
local notifyRemote = remotes:WaitForChild("Notify")

local card = gui:WaitForChild("Card")
local home = card:WaitForChild("Home")
local profilePage = card:WaitForChild("ProfilePage")
local chatPage = card:WaitForChild("ChatPage")
local fxLayer = card:WaitForChild("FxLayer")
local communityBackground = card:WaitForChild("CommunityBackground")
local communityScrim = card:WaitForChild("CommunityScrim")
local toast = gui:WaitForChild("Toast")
local carryRequest = gui:WaitForChild("CarryRequest")
local carryBar = gui:WaitForChild("CarryBar")
local openEvent = gui:WaitForChild("OpenPlayer")

local portrait = home:WaitForChild("Avatar"):WaitForChild("Portrait")
local ring = home.Avatar:WaitForChild("Ring")
local viewport = portrait:WaitForChild("ModelView")
local communityChip = home:WaitForChild("CommunityChip")
local stats = home:WaitForChild("Stats")
local actions = home:WaitForChild("Actions")
local likeTile = stats:WaitForChild("Like")
local messages = chatPage:WaitForChild("Messages")
local chatInput = chatPage:WaitForChild("InputBar"):WaitForChild("Field"):WaitForChild("InputBox")
local sendButton = chatPage.InputBar:WaitForChild("SendButton")
local info = profilePage:WaitForChild("Info")

local TILE_TRANSPARENCY = 0.9 -- keep in sync with GLASS in PlayerMenuGui
local TILE_HOVER_TRANSPARENCY = 0.8
local COLORS = {
	Pink = Color3.fromRGB(255, 82, 150),
	Green = Color3.fromRGB(61, 220, 151),
	Red = Color3.fromRGB(255, 85, 102),
	Blue = Color3.fromRGB(77, 171, 255),
}
local HEARTS = { "❤️", "💖", "💕", "💗", "💓" }

local state = {
	target = nil, -- Player shown on the card
	page = "Home",
	following = {}, -- [userId] = true
	friends = {}, -- [userId] = true / false
	conversations = {}, -- [userId] = { { mine, text } }
	unread = {}, -- [userId] = number
	carry = nil, -- { role = "carrier" | "carried", userId, name }
	request = nil, -- { userId, token }
	busy = {} :: { [string]: boolean }, -- actions waiting for the server
	cooldown = {} :: { [string]: number }, -- [action] = os.clock() until which the tile stays disabled
}
local targetConnections = {}

local function tween(instance, time, props, style, direction)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function formatCount(value)
	if type(value) ~= "number" then
		return "–"
	end
	if value >= 1000000 then
		return (string.format("%.1fM", value / 1000000):gsub("%.0M", "M"))
	elseif value >= 10000 then
		return (string.format("%.1fK", value / 1000):gsub("%.0K", "K"))
	end
	return tostring(math.floor(value))
end

local function formatAge(days)
	local years = days // 365
	local months = (days % 365) // 30
	if years > 0 then
		return string.format("%d yr %d mo", years, months)
	elseif months > 0 then
		return string.format("%d mo", months)
	end
	return string.format("%d days", days)
end

local function formatDuration(seconds)
	if seconds < 60 then
		return "< 1 min"
	elseif seconds < 3600 then
		return string.format("%d min", seconds // 60)
	end
	return string.format("%d h %d min", seconds // 3600, (seconds % 3600) // 60)
end

-- Grows a pill (Frame + "Label") with its text. The GUI ships with fixed sizes
-- so it looks right in the Studio preview.
local function fitChip(chip, height)
	local label = chip:WaitForChild("Label")
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = chip
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, 0, 1, 0)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, height)
end

---------------------------------------------------------------------------
-- Layout: one scale for the card, one for the popups, from the screen size.
-- (tools/build-player-menu.luau uses the same formulas for the previews.)
---------------------------------------------------------------------------

local function layout()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	card.ResponsiveScale.Scale = math.clamp(math.min(size.X * 0.94 / 312, size.Y * 0.88 / 458), 0.5, 1.1)
	local hud = math.clamp(size.Y / 720, 0.75, 1.1)
	toast.ResponsiveScale.Scale = hud
	carryRequest.ResponsiveScale.Scale = hud
	carryBar.ResponsiveScale.Scale = hud
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

---------------------------------------------------------------------------
-- Toast
---------------------------------------------------------------------------

local toastToken = 0
local toastHome = toast.Position

-- kind: true = green, false = red, "chat" = blue
local function showToast(text, kind, openUserId)
	toastToken += 1
	local token = toastToken
	toast.Message.Text = text
	toast.Dot.BackgroundColor3 = if kind == "chat" then COLORS.Blue elseif kind then COLORS.Green else COLORS.Red
	toast:SetAttribute("OpenUserId", openUserId)
	toast.Position = toastHome + UDim2.fromOffset(0, 14)
	toast.Visible = true
	tween(toast, 0.22, { Position = toastHome }, Enum.EasingStyle.Back)
	task.delay(if openUserId then 4.5 else 3, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

---------------------------------------------------------------------------
-- Hearts
---------------------------------------------------------------------------

local function spawnHeart(parent, size, position, rise, drift, duration, delay)
	local heart = Instance.new("TextLabel")
	heart.AnchorPoint = Vector2.new(0.5, 0.5)
	heart.BackgroundTransparency = 1
	heart.Size = UDim2.fromOffset(size * 1.5, size * 1.5)
	heart.Position = position
	heart.Rotation = math.random(-20, 20)
	heart.Text = HEARTS[math.random(#HEARTS)]
	heart.TextSize = size
	heart.TextTransparency = 1
	heart.Parent = parent
	task.delay(delay, function()
		heart.TextTransparency = 0
		tween(heart, duration, {
			Position = position + drift + rise,
			TextTransparency = 1,
			Rotation = math.random(-35, 35),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
	Debris:AddItem(heart, delay + duration + 0.1)
end

local function cardHearts()
	for i = 1, 7 do
		spawnHeart(
			fxLayer,
			math.random(18, 28),
			UDim2.fromScale(0.8 + (math.random() - 0.5) * 0.1, 0.45),
			UDim2.fromScale(0, -0.22 - math.random() * 0.08),
			UDim2.fromScale((math.random() - 0.5) * 0.14, 0),
			1 + math.random() * 0.4,
			(i - 1) * 0.05
		)
	end
end

local function worldHearts(target)
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - head.Position).Magnitude > 120 then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlayerMenuHearts"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(200, 220)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = head
	for i = 1, 8 do
		spawnHeart(
			billboard,
			math.random(24, 38),
			UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.45, 0.85),
			UDim2.fromScale(0, -0.55 - math.random() * 0.2),
			UDim2.fromScale((math.random() - 0.5) * 0.25, 0),
			1.2 + math.random() * 0.5,
			(i - 1) * 0.06
		)
	end
	Debris:AddItem(billboard, 2.6)

	if Settings.LikeSoundId ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = Settings.LikeSoundId
		sound.RollOffMaxDistance = 60
		sound.Parent = head
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end

local function pulse(scale)
	scale.Scale = 0.9
	tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

---------------------------------------------------------------------------
-- Avatar: headshot right away, 3D bust when the character can be copied.
---------------------------------------------------------------------------

local avatarToken = 0
local bust = nil -- { camera, center, forward, distance }

local function clearBust()
	bust = nil
	viewport:ClearAllChildren()
	viewport.Visible = false
	portrait.Headshot.Visible = true
end

local REMOVED_FROM_BUST = { "LuaSourceContainer", "Sound", "BillboardGui", "SurfaceGui", "ParticleEmitter", "Highlight", "ForceField", "ProximityPrompt", "Seat" }

local function buildBust(target, token)
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	if not character or not head or not head:IsA("BasePart") then
		return
	end

	local clone
	local wasArchivable = character.Archivable
	character.Archivable = true
	pcall(function()
		clone = character:Clone()
	end)
	character.Archivable = wasArchivable
	if not clone or token ~= avatarToken then
		return
	end

	for _, item in clone:GetDescendants() do
		local unwanted = false
		for _, className in REMOVED_FROM_BUST do
			if item:IsA(className) then
				unwanted = true
				break
			end
		end
		if unwanted then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		elseif item:IsA("Humanoid") then
			item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			item.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end

	local root = clone:FindFirstChild("HumanoidRootPart")
	if not root then
		clone:Destroy()
		return
	end
	local forward = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.new(0, 0, -1)
	local headSize = math.max(head.Size.Y, 1)
	local center = head.Position - Vector3.new(0, 0.7 * headSize, 0)

	clearBust()
	clone.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	bust = {
		camera = camera,
		center = center,
		forward = forward,
		distance = 1.8 * headSize / math.tan(math.rad(camera.FieldOfView / 2)),
	}
	camera.CFrame = CFrame.lookAt(center + forward * bust.distance, center)
	viewport.Visible = true
	portrait.Headshot.Visible = false
end

local function loadAvatar(target)
	avatarToken += 1
	local token = avatarToken
	clearBust()
	portrait.Headshot.Image = ""
	profilePage.MiniAvatar.Image = ""
	portrait.Silhouette.Visible = true
	profilePage.MiniAvatar.Silhouette.Visible = true

	task.spawn(function()
		local ok, content = pcall(Players.GetUserThumbnailAsync, Players, target.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ok and token == avatarToken then
			portrait.Headshot.Image = content
			profilePage.MiniAvatar.Image = content
			portrait.Silhouette.Visible = false
			profilePage.MiniAvatar.Silhouette.Visible = false
		end
	end)
	task.spawn(function()
		local ok = pcall(buildBust, target, token)
		if not ok and token == avatarToken then
			clearBust()
		end
	end)
end

RunService.RenderStepped:Connect(function()
	if bust and card.Visible and state.page == "Home" then
		local angle = math.sin(os.clock() * 0.9) * 0.3
		local direction = CFrame.Angles(0, angle, 0):VectorToWorldSpace(bust.forward)
		bust.camera.CFrame = CFrame.lookAt(bust.center + direction * bust.distance, bust.center)
	end
end)

---------------------------------------------------------------------------
-- Card content
---------------------------------------------------------------------------

local function targetRole(target)
	local name = target:GetAttribute("PMRole") or ""
	local color = target:GetAttribute("PMRoleColor") or COLORS.Pink
	return name, color
end

local function refreshIdentity()
	local target = state.target
	if not target then
		return
	end
	local role, color = targetRole(target)

	home.DisplayName.Text = target.DisplayName
	home.Username.Text = "@" .. target.Name
	home.RoleChip.Visible = role ~= ""
	home.RoleChip.Label.Text = role
	home.RoleChip.Label.TextColor3 = color
	home.RoleChip.BackgroundColor3 = color
	home.RoleChip.Outline.Color = color
	ring.Outline.Color = color
	profilePage.MiniAvatar.Outline.Color = color
	profilePage.MiniName.Text = target.DisplayName
	profilePage.MiniUser.Text = "@" .. target.Name
	chatPage.PageTitle.Text = target.DisplayName
end

-- The community icon is the card's background; its name is a chip on the card.
local function refreshCommunity()
	local target = state.target
	if not target then
		return
	end
	local groupId = target:GetAttribute("PMCommunityId")
	local name = target:GetAttribute("PMCommunityName")
	local show = Settings.Community.Enabled and type(groupId) == "number" and type(name) == "string"

	communityBackground.Visible = show
	communityScrim.Visible = show
	communityChip.Visible = show
	if show then
		local image = string.format("rbxthumb://type=GroupIcon&id=%d&w=420&h=420", groupId)
		if communityBackground.Image ~= image then
			communityBackground.Image = image
		end
		communityBackground.ImageTransparency = Settings.Community.ImageTransparency
		local shown = name
		local length = utf8.len(name)
		local cut = if length and length > 16 then utf8.offset(name, 16) else nil
		if cut then
			shown = string.sub(name, 1, cut - 1) .. "…"
		end
		communityChip.Label.Text = shown
	else
		communityBackground.Image = ""
	end
end

local function refreshStats()
	local target = state.target
	if not target then
		return
	end
	stats.Friends.Value.Text = if Settings.ShowFriendCount then formatCount(target:GetAttribute("PMFriends")) else "–"
	stats.Followers.Value.Text = formatCount(target:GetAttribute("PMFollowers"))
	likeTile.Value.Text = "❤️ " .. formatCount(target:GetAttribute("PMLikes"))
end

local function refreshProfile()
	local target = state.target
	if not target then
		return
	end
	local role = targetRole(target)
	local community = target:GetAttribute("PMCommunityName")
	local joined = target:GetAttribute("PMJoined")
	local rows = {
		UserId = tostring(target.UserId),
		AccountAge = formatAge(target.AccountAge),
		Membership = if target.MembershipType == Enum.MembershipType.Premium then "Premium" else "Standard",
		Role = if role ~= "" then role else "Member",
		Community = if type(community) == "string" then community else "None",
		InServer = if type(joined) == "number" then formatDuration(math.max(0, workspace:GetServerTimeNow() - joined)) else "–",
		Followers = formatCount(target:GetAttribute("PMFollowers")),
		Following = formatCount(target:GetAttribute("PMFollowing")),
		Likes = formatCount(target:GetAttribute("PMLikes")),
	}
	for key, text in rows do
		local row = info:FindFirstChild("Row_" .. key)
		if row then
			row.Value.Text = text
		end
	end
end

-- Shows or dims an action tile.
local function setTile(tile, title, subtitle, enabled)
	tile.Title.Text = title
	tile.Subtitle.Text = subtitle
	tile.Interactable = enabled
	local dim = if enabled then 0 else 0.55
	tile.Title.TextTransparency = dim
	tile.Subtitle.TextTransparency = dim
	tile.IconChip.Icon.TextTransparency = dim
	tile.IconChip.BackgroundTransparency = if enabled then 0.75 else 0.9
end

local function coolingDown(action)
	return (state.cooldown[action] or 0) > os.clock()
end

local function refreshActions()
	local target = state.target
	if not target then
		return
	end
	local isSelf = target == player
	local carry = state.carry

	-- Like
	likeTile.Interactable = not isSelf
	likeTile.Value.TextTransparency = if isSelf then 0.5 else 0
	likeTile.Caption.Text = if isSelf then "YOU" else "LIKES"

	-- Carry
	local carryTile = actions.Carry
	if isSelf or not Settings.CarryEnabled then
		setTile(carryTile, "Carry", if isSelf then "That's you" else "Turned off", false)
	elseif carry and carry.role == "carrier" and carry.userId == target.UserId then
		setTile(carryTile, "Put Down", "Let them go", true)
	elseif carry then
		setTile(carryTile, "Carry", "Busy right now", false)
	elseif coolingDown("Carry") then
		setTile(carryTile, "Carry", "Request sent", false)
	else
		setTile(carryTile, "Carry", "Piggyback ride", true)
	end

	-- Add friend
	local friendTile = actions.AddFriend
	if isSelf then
		setTile(friendTile, "Add Friend", "That's you", false)
	elseif state.friends[target.UserId] then
		setTile(friendTile, "Friends", "You are friends", false)
	else
		setTile(friendTile, "Add Friend", "Send request", true)
	end

	-- Follow
	local followTile = actions.Follow
	if isSelf or not Settings.FollowEnabled then
		setTile(followTile, "Follow", if isSelf then "That's you" else "Turned off", false)
	elseif state.following[target.UserId] then
		setTile(followTile, "Following", "Tap to unfollow", true)
	else
		setTile(followTile, "Follow", "Follow player", true)
	end

	-- Private chat
	local chatTile = actions.Chat
	if isSelf or not Settings.PrivateChatEnabled then
		setTile(chatTile, "Private Chat", if isSelf then "That's you" else "Turned off", false)
	else
		setTile(chatTile, "Private Chat", "Send a message", true)
	end
	local unread = state.unread[target.UserId] or 0
	chatTile.Badge.Visible = unread > 0 and chatTile.Interactable
	chatTile.Badge.Count.Text = if unread > 9 then "9+" else tostring(unread)
end

local function checkFriend(target)
	if target == player then
		return
	end
	task.spawn(function()
		local ok, isFriend = pcall(player.IsFriendsWith, player, target.UserId)
		if ok then
			state.friends[target.UserId] = isFriend
			if state.target == target then
				refreshActions()
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------

local function scrollChatToEnd()
	task.defer(function()
		messages.CanvasPosition = Vector2.new(0, messages.AbsoluteCanvasSize.Y)
	end)
end

local function appendBubble(order, mine, text)
	local bubble = messages[if mine then "BubbleMine" else "BubbleTheirs"]:Clone()
	bubble.Name = "Message"
	bubble.LayoutOrder = order
	bubble.Bubble.Text.Text = text
	bubble.Visible = true
	bubble.Parent = messages
end

local function renderChat()
	local target = state.target
	for _, child in messages:GetChildren() do
		if child.Name == "Message" or string.sub(child.Name, 1, 6) == "Sample" then
			child:Destroy()
		end
	end
	if not target then
		return
	end
	local conversation = state.conversations[target.UserId] or {}
	for index, message in conversation do
		appendBubble(index, message.mine, message.text)
	end
	chatPage.EmptyState.Text = `Say hi to {target.DisplayName} 👋`
	chatPage.EmptyState.Visible = #conversation == 0
	scrollChatToEnd()
end

local function addMessage(userId, mine, text)
	local conversation = state.conversations[userId]
	if not conversation then
		conversation = {}
		state.conversations[userId] = conversation
	end
	table.insert(conversation, { mine = mine, text = text })
	if #conversation > 60 then
		table.remove(conversation, 1)
	end
	if state.page == "Chat" and state.target and state.target.UserId == userId then
		renderChat()
	end
end

local function sendMessage()
	local target = state.target
	if not target or state.busy.Chat then
		return
	end
	local text = trim(chatInput.Text)
	if text == "" then
		return
	end
	state.busy.Chat = true
	local ok, result = pcall(chatRemote.InvokeServer, chatRemote, target.UserId, text)
	state.busy.Chat = false
	if ok and type(result) == "table" and result.ok then
		chatInput.Text = ""
		addMessage(target.UserId, true, result.text)
	else
		showToast(if ok and type(result) == "table" then result.message or "Message failed" else "Message failed", false)
	end
end

chatInput:GetPropertyChangedSignal("Text"):Connect(function()
	local text = chatInput.Text
	local length = utf8.len(text)
	local cut = if length and length > Settings.ChatMaxLength then utf8.offset(text, Settings.ChatMaxLength + 1) else nil
	if cut then
		chatInput.Text = string.sub(text, 1, cut - 1)
	end
end)
chatInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		sendMessage()
		if not UserInputService.TouchEnabled then
			chatInput:CaptureFocus()
		end
	end
end)
sendButton.Activated:Connect(sendMessage)

---------------------------------------------------------------------------
-- Pages and open / close
---------------------------------------------------------------------------

local function showPage(name)
	state.page = name
	home.Visible = name == "Home"
	profilePage.Visible = name == "Profile"
	chatPage.Visible = name == "Chat"
	local page = if name == "Profile" then profilePage elseif name == "Chat" then chatPage else nil
	if page then
		page.Position = UDim2.fromScale(0.1, 0)
		tween(page, 0.25, { Position = UDim2.new() }, Enum.EasingStyle.Quart)
	end
	if name == "Profile" then
		refreshProfile()
	elseif name == "Chat" then
		local target = state.target
		if target then
			state.unread[target.UserId] = nil
			refreshActions()
		end
		renderChat()
	end
end

local function disconnectTarget()
	for _, connection in targetConnections do
		connection:Disconnect()
	end
	table.clear(targetConnections)
end

local cardHome = card.Position
local closeToken = 0

local function openCard(target, page)
	if typeof(target) == "number" then
		target = Players:GetPlayerByUserId(target)
	end
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players then
		return
	end

	disconnectTarget()
	state.target = target
	refreshIdentity()
	refreshCommunity()
	refreshStats()
	refreshActions()
	loadAvatar(target)
	checkFriend(target)
	showPage("Home")

	table.insert(targetConnections, target.AttributeChanged:Connect(function(name)
		if state.target ~= target then
			return
		end
		refreshIdentity()
		refreshCommunity()
		refreshStats()
		if name == "PMLikes" then
			pulse(likeTile.Pulse)
		end
		if state.page == "Profile" then
			refreshProfile()
		end
	end))
	table.insert(targetConnections, target:GetPropertyChangedSignal("DisplayName"):Connect(refreshIdentity))

	closeToken += 1
	if not card.Visible then
		card.Position = cardHome - UDim2.fromOffset(60, 0)
		card.Visible = true
		tween(card, 0.32, { Position = cardHome }, Enum.EasingStyle.Quart)
	end
	if page and page ~= "Home" then
		showPage(page)
	end
end

local function closeCard()
	if not card.Visible then
		return
	end
	disconnectTarget()
	state.target = nil
	closeToken += 1
	local token = closeToken
	tween(card, 0.2, { Position = cardHome - UDim2.fromOffset(60, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.2, function()
		if closeToken == token then
			card.Visible = false
			clearBust()
		end
	end)
end

openEvent.Event:Connect(openCard)

Players.PlayerRemoving:Connect(function(leaving)
	if state.target == leaving then
		showToast(`{leaving.DisplayName} left the game`, false)
		closeCard()
	end
end)

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- Runs `callback` unless the same action is still waiting for the server.
local function once(key, callback)
	if state.busy[key] then
		return
	end
	state.busy[key] = true
	task.spawn(function()
		local ok, err = pcall(callback)
		state.busy[key] = nil
		if not ok then
			warn("[PlayerMenu]", err)
		end
	end)
end

local function invoke(remote, ...)
	local ok, result = pcall(remote.InvokeServer, remote, ...)
	if ok and type(result) == "table" then
		return result
	end
	return { ok = false, message = "Something went wrong" }
end

local function doLike()
	local target = state.target
	if not target or target == player then
		return
	end
	pulse(likeTile.Pulse)
	once("Like", function()
		local result = invoke(likeRemote, target.UserId)
		if not result.ok then
			showToast(result.message or "Can't like right now", false)
		end
	end)
end

local function doCarry()
	local target = state.target
	if not target then
		return
	end
	once("Carry", function()
		if state.carry then
			local result = invoke(carryRemote, "Drop")
			if not result.ok then
				showToast(result.message or "Can't put down", false)
			end
			return
		end
		local result = invoke(carryRemote, "Request", target.UserId)
		showToast(result.message or "Can't carry right now", result.ok == true)
		if result.ok and Settings.CarryRequiresConsent then
			state.cooldown.Carry = os.clock() + 4
			refreshActions()
			task.delay(4, refreshActions)
		end
	end)
end

local function doAddFriend()
	local target = state.target
	if not target or target == player then
		return
	end
	local ok = pcall(function()
		StarterGui:SetCore("PromptSendFriendRequest", target)
	end)
	if not ok then
		showToast("Friend requests are not available here", false)
		return
	end
	for _, seconds in { 6, 14, 30 } do
		task.delay(seconds, checkFriend, target)
	end
end

local function doFollow()
	local target = state.target
	if not target or target == player then
		return
	end
	once("Follow", function()
		local result = invoke(followRemote, "Toggle", target.UserId)
		if result.ok then
			state.following[target.UserId] = if result.following then true else nil
			showToast(if result.following then `Following {target.DisplayName}` else `Unfollowed {target.DisplayName}`, true)
			if state.target == target then
				refreshActions()
			end
		else
			showToast(result.message or "Can't follow right now", false)
		end
	end)
end

likeTile.Activated:Connect(doLike)
actions.Profile.Activated:Connect(function()
	showPage("Profile")
end)
actions.Carry.Activated:Connect(doCarry)
actions.AddFriend.Activated:Connect(doAddFriend)
actions.Follow.Activated:Connect(doFollow)
actions.Chat.Activated:Connect(function()
	showPage("Chat")
end)

for _, page in { home, profilePage, chatPage } do
	page.CloseButton.Activated:Connect(closeCard)
end
profilePage.BackButton.Activated:Connect(function()
	showPage("Home")
end)
chatPage.BackButton.Activated:Connect(function()
	showPage("Home")
end)

-- Hover color on the action tiles.
for _, tile in actions:GetChildren() do
	if tile:IsA("TextButton") then
		tile.MouseEnter:Connect(function()
			if tile.Interactable then
				tween(tile, 0.12, { BackgroundTransparency = TILE_HOVER_TRANSPARENCY })
			end
		end)
		tile.MouseLeave:Connect(function()
			tween(tile, 0.12, { BackgroundTransparency = TILE_TRANSPARENCY })
		end)
	end
end

---------------------------------------------------------------------------
-- Carry popups
---------------------------------------------------------------------------

local function refreshCarryBar()
	local carry = state.carry
	carryBar.Visible = carry ~= nil
	if carry then
		if carry.role == "carrier" then
			carryBar.Message.Text = `🤗  Carrying {carry.name}`
			carryBar.DropButton.Label.Text = "PUT DOWN"
		else
			carryBar.Message.Text = `🤗  On {carry.name}'s back`
			carryBar.DropButton.Label.Text = "GET DOWN"
		end
	end
end

local function hideRequest()
	state.request = nil
	carryRequest.Visible = false
end

local function showRequest(data)
	local token = (state.request and state.request.token or 0) + 1
	state.request = { userId = data.userId, token = token }
	carryRequest.Message.Text = `{data.name} wants to carry you`
	carryRequest.Detail.Text = `Piggyback ride  •  {data.timeout}s`
	carryRequest.Timer.Fill.Size = UDim2.fromScale(1, 1)
	carryRequest.Position = UDim2.new(0.5, 0, 0, -10)
	carryRequest.Visible = true
	tween(carryRequest, 0.3, { Position = UDim2.new(0.5, 0, 0, 16) }, Enum.EasingStyle.Back)
	tween(carryRequest.Timer.Fill, data.timeout, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	task.delay(data.timeout, function()
		if state.request and state.request.token == token then
			hideRequest()
		end
	end)
end

carryRequest.Accept.Activated:Connect(function()
	local request = state.request
	if not request then
		return
	end
	hideRequest()
	once("CarryAnswer", function()
		local result = invoke(carryRemote, "Accept", request.userId)
		if not result.ok then
			showToast(result.message or "Can't accept right now", false)
		end
	end)
end)

carryRequest.Decline.Activated:Connect(function()
	local request = state.request
	if not request then
		return
	end
	hideRequest()
	once("CarryAnswer", function()
		invoke(carryRemote, "Decline", request.userId)
	end)
end)

carryBar.DropButton.Activated:Connect(function()
	once("Carry", function()
		local result = invoke(carryRemote, "Drop")
		if not result.ok then
			showToast(result.message or "Can't put down", false)
		end
	end)
end)

toast.Activated:Connect(function()
	local userId = toast:GetAttribute("OpenUserId")
	if userId then
		toast.Visible = false
		openCard(userId, "Chat")
	end
end)

---------------------------------------------------------------------------
-- Messages from the server
---------------------------------------------------------------------------

local handlers = {}

function handlers.Liked(data)
	local giver = Players:GetPlayerByUserId(data.from)
	local receiver = Players:GetPlayerByUserId(data.to)
	if not receiver then
		return
	end
	worldHearts(receiver)
	if state.target == receiver and data.from == player.UserId then
		cardHearts()
	end
	if receiver == player and giver then
		showToast(`❤️ {giver.DisplayName} liked you`, true)
	end
end

function handlers.Toast(data)
	showToast(data.text, data.ok == true)
end

function handlers.CarryRequest(data)
	showRequest(data)
end

function handlers.CarryRequestEnded(data)
	if state.request and state.request.userId == data.userId then
		hideRequest()
	end
end

function handlers.CarryStarted(data)
	state.carry = { role = data.role, userId = data.userId, name = data.name }
	if state.request then
		hideRequest()
	end
	refreshCarryBar()
	refreshActions()
end

function handlers.CarryEnded()
	state.carry = nil
	refreshCarryBar()
	refreshActions()
end

function handlers.Chat(data)
	addMessage(data.from, false, data.text)
	local viewing = state.target and state.target.UserId == data.from and state.page == "Chat" and card.Visible
	if not viewing then
		state.unread[data.from] = (state.unread[data.from] or 0) + 1
		refreshActions()
		showToast(`💬 {data.name}: {data.text}`, "chat", data.from)
	end
end

notifyRemote.OnClientEvent:Connect(function(kind, data)
	local handler = handlers[kind]
	if handler and type(data) == "table" then
		handler(data)
	end
end)

---------------------------------------------------------------------------
-- Tap / click a player in the world
---------------------------------------------------------------------------

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function playerAt(position)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	raycastParams.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
	local instance = result and result.Instance
	while instance and instance ~= workspace do
		if instance:IsA("Model") then
			local found = Players:GetPlayerFromCharacter(instance)
			if found then
				return found
			end
		end
		instance = instance.Parent
	end
	return nil
end

local function withinOpenDistance(target)
	if Settings.OpenDistance <= 0 then
		return true
	end
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local theirs = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	return mine ~= nil and theirs ~= nil and (mine.Position - theirs.Position).Magnitude <= Settings.OpenDistance
end

local presses = {}

local function pressKey(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		return input
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		return "mouse"
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	local key = pressKey(input)
	if key and not processed and Settings.TapToOpen then
		presses[key] = { position = input.Position, time = os.clock() }
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local key = pressKey(input)
	local press = key and presses[key]
	if not press then
		return
	end
	presses[key] = nil
	-- A tap, not a camera drag.
	if (input.Position - press.position).Magnitude > 10 or os.clock() - press.time > 0.4 then
		return
	end
	local target = playerAt(input.Position)
	if target and withinOpenDistance(target) then
		openCard(target)
	end
end)

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

for _, child in messages:GetChildren() do
	if string.sub(child.Name, 1, 6) == "Sample" then
		child:Destroy()
	end
end
fitChip(home.RoleChip, 24)
fitChip(communityChip, 24)
likeTile.Pulse.Scale = 1
card.Visible = false
profilePage.Visible = false
chatPage.Visible = false
toast.Visible = false
carryRequest.Visible = false
carryBar.Visible = false

-- Who I already follow (the server may still be loading my profile).
task.spawn(function()
	for _ = 1, 10 do
		local result = invoke(followRemote, "List")
		if result.ok then
			for _, userId in result.ids do
				state.following[userId] = true
			end
			refreshActions()
			return
		end
		task.wait(2)
	end
end)
