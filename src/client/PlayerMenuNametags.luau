--[[
	PlayerMenuNametags (LocalScript inside StarterGui.PlayerMenuGui)

	Puts the NametagTemplate (name / role) above every player's head.
	The text and colors come from the Player attributes that
	PlayerMenuServer publishes (PMRole, PMRoleColor, ...), so changing
	an attribute on the server updates the tag right away.
	Restyle the tag by editing NametagTemplate in the GUI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = script.Parent

local Config = require(ReplicatedStorage:WaitForChild("PlayerMenu"):WaitForChild("Config"))
local Settings = Config.Settings.Nametags
if not Settings.Enabled then
	return
end

local template = gui:WaitForChild("NametagTemplate")
local WHITE = Color3.new(1, 1, 1)

local tags = {} -- [Player] = BillboardGui

-- The chip in the template has a fixed size (for the Studio preview); make it
-- grow with its text instead.
local function fitChip(chip)
	local label = chip:WaitForChild("Label")
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 9)
	padding.PaddingRight = UDim.new(0, 9)
	padding.Parent = chip
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, 0, 1, 0)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, chip.Size.Y.Offset)
end

local function applyTag(target, tag)
	local stack = tag:FindFirstChild("Stack")
	if not stack then
		return
	end
	local role = target:GetAttribute("PMRole") or ""
	local roleColor = target:GetAttribute("PMRoleColor") or WHITE
	local colorA = target:GetAttribute("PMNameColorA")
	local colorB = target:GetAttribute("PMNameColorB")

	stack.PlayerName.Text = target.DisplayName
	local gradient = stack.PlayerName:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Enabled = colorA ~= nil
		if colorA then
			gradient.Color = ColorSequence.new(colorA, colorB or colorA)
		end
	end

	local chip = stack.RoleChip
	chip.Visible = role ~= ""
	chip.Label.Text = role
	chip.BackgroundColor3 = roleColor
	chip.Outline.Color = roleColor
end

local function refresh(target)
	local tag = tags[target]
	if tag and tag.Parent then
		applyTag(target, tag)
	end
end

local function attach(target, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and Settings.HideDefaultName then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local head = character:WaitForChild("Head", 10)
	if not head or (target == player and not Settings.ShowOwn) then
		return
	end

	local old = tags[target]
	if old then
		old:Destroy()
	end
	local tag = template:Clone()
	tag.Name = "PlayerMenuNametag"
	tag.Adornee = head
	tag.MaxDistance = Settings.MaxDistance
	tag.StudsOffset = Vector3.new(0, Settings.StudsOffset, 0)
	tag.AlwaysOnTop = Settings.AlwaysOnTop
	fitChip(tag.Stack.RoleChip)
	applyTag(target, tag)
	tag.Enabled = true
	tag.Parent = head
	tags[target] = tag
end

local function watchPlayer(target)
	target.CharacterAdded:Connect(function(character)
		attach(target, character)
	end)
	target.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 2) == "PM" then
			refresh(target)
		end
	end)
	target:GetPropertyChangedSignal("DisplayName"):Connect(function()
		refresh(target)
	end)
	if target.Character then
		task.spawn(attach, target, target.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(target)
	tags[target] = nil
end)
for _, target in Players:GetPlayers() do
	watchPlayer(target)
end
