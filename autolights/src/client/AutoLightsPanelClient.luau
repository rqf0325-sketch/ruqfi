--[[
	AutoLightsPanelClient (LocalScript inside StarterGui.AutoLightsPanel)  —  by PAUL

	Runs the AutoLights Control Panel: switches for Sync, Dance Floor, Auto Pattern and Pyro,
	pattern / brightness / flash controls, pyro bursts, and Blackout / Restore.

	  • The panel is only shown to operators (Player attribute AutoLightsOperator, set by
	    AutoLightsControl). Press K or the LIGHTS button to open it.
	  • What the switches show comes from the attributes on ReplicatedStorage.AutoLights, so
	    every operator sees the same state live. Buttons only ask the server (Control remote);
	    the server checks that the player is an operator on every call.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local TOGGLE_KEY = Enum.KeyCode.K

local player = Players.LocalPlayer
local gui = script.Parent

local panel = gui:WaitForChild("Panel")
local openButton = gui:WaitForChild("OpenButton")
local left = panel:WaitForChild("Left")
local right = panel:WaitForChild("Right")
local beatTile = panel:WaitForChild("BeatTile")
local syncChip = panel:WaitForChild("SyncChip")
local toast = panel:WaitForChild("Toast")

local COLORS = {
	Green = Color3.fromRGB(61, 220, 151),
	Red = Color3.fromRGB(255, 85, 102),
	Amber = Color3.fromRGB(255, 190, 56),
	White = Color3.new(1, 1, 1),
	Pink = Color3.fromRGB(255, 82, 150),
}

panel.Visible = false
openButton.Visible = false
toast.Visible = false

local autoRoot = ReplicatedStorage:WaitForChild("AutoLights", 30)
local remotes = autoRoot and autoRoot:WaitForChild("Remotes", 10)
local control = remotes and remotes:WaitForChild("Control", 30)
if not control then
	warn("[AutoLightsPanel] Control remote not found; is AutoLightsControl running on the server?")
	return
end

local function tween(instance, time, props, style, direction)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function attr(name, default)
	local value = autoRoot:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function layout()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	panel.ResponsiveScale.Scale = math.clamp(math.min(size.X * 0.94 / 420, size.Y * 0.92 / 510), 0.55, 1.1)
	openButton.ResponsiveScale.Scale = math.clamp(size.Y / 720, 0.75, 1.1)
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

---------------------------------------------------------------------------
-- Toast
---------------------------------------------------------------------------

local toastToken = 0

local function showToast(text, ok)
	toastToken += 1
	local token = toastToken
	toast.Message.Text = text
	toast.Dot.BackgroundColor3 = if ok then COLORS.Green else COLORS.Red
	toast.Visible = true
	task.delay(2.5, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

---------------------------------------------------------------------------
-- Showing the state
---------------------------------------------------------------------------

local function setSwitch(row, on)
	local track = row.Track
	tween(track, 0.15, {
		BackgroundColor3 = if on then COLORS.Green else COLORS.White,
		BackgroundTransparency = if on then 0 else 0.7,
	})
	tween(track.Knob, 0.15, { Position = UDim2.fromScale(if on then 0.5 else 0.05, 3 / 22) })
end

-- Dim a control (and make it unclickable) when it cannot be used.
local function setEnabled(target, enabled)
	target.Interactable = enabled
	local dim = if enabled then 0 else 0.6
	for _, child in target:GetChildren() do
		if child:IsA("TextLabel") then
			child.TextTransparency = dim
		end
	end
end

local function refresh()
	local sync = attr("SyncEnabled", true) ~= false
	local floor = attr("DanceFloorEnabled", true) ~= false
	local pyro = attr("PyroEnabled", true) ~= false
	local blackout = attr("Blackout", false) == true
	local hasPyro = attr("HasPyro", false) == true
	local brightness = math.clamp(tonumber(attr("DFBrightness", 1)) or 1, 0.1, 1)
	local count = math.max(1, math.floor(tonumber(attr("DFPatternCount", 12)) or 12))
	local now = math.floor(tonumber(attr("DFPatternNow", 1)) or 1)
	local name = tostring(attr("DFPatternName", ""))
	local bpm = tonumber(attr("Bpm", nil))

	-- status chip
	local chipColor, chipText = COLORS.Green, "SYNC ON"
	if blackout then
		chipColor, chipText = COLORS.Red, "BLACKOUT"
	elseif not sync then
		chipColor, chipText = COLORS.Amber, "SYNC OFF"
	end
	syncChip.Label.Text = chipText
	syncChip.Label.TextColor3 = chipColor
	syncChip.Dot.BackgroundColor3 = chipColor
	syncChip.BackgroundColor3 = chipColor
	syncChip.Outline.Color = chipColor

	-- switches
	setSwitch(left.Toggle_Sync, sync)
	setSwitch(left.Toggle_DanceFloor, floor)
	setSwitch(left.Toggle_AutoPattern, attr("DFAutoPattern", true) ~= false)
	setSwitch(right.Toggle_Pyro, pyro and hasPyro)

	-- beat tile
	beatTile.Bpm.Text = if bpm then `{bpm} BPM` else "– BPM"
	beatTile.PatternName.Text = if name ~= "" then name else "–"
	beatTile.Bpm.TextTransparency = if sync then 0 else 0.6

	-- pattern + brightness
	left.PatternRow.PatternText.Text = if name ~= "" then `{name}   {now}/{count}` else "–"
	left.BrightnessRow.Track.Fill.Size = UDim2.fromScale(brightness, 1)
	left.BrightnessRow.Value.Text = `{math.floor(brightness * 100 + 0.5)}%`

	-- what can be used right now
	setEnabled(left.Flash, floor)
	setEnabled(right.Toggle_Pyro, hasPyro)
	right.Toggle_Pyro.Subtitle.Text = if hasPyro then "Fire, CO2, smoke, confetti" else "Pyro system not detected"
	for _, name2 in { "Fire_CO2", "Fire_CONFETTI", "Fire_SMOKE", "StopPyro" } do
		setEnabled(right[name2], hasPyro and (pyro or name2 == "StopPyro"))
	end

	local watermark = tostring(attr("Watermark", "PAUL"))
	if watermark == "" then
		watermark = "PAUL"
	end
	panel.Watermark.Text = watermark
	panel.WatermarkBig.Text = watermark
end

autoRoot.AttributeChanged:Connect(function(name)
	if name == "BeatCount" then
		beatTile.BeatDot.BackgroundTransparency = 0
		tween(beatTile.BeatDot, 0.25, { BackgroundTransparency = 0.8 })
		return
	end
	if name == "DFPulse" then
		return
	end
	refresh()
end)

---------------------------------------------------------------------------
-- Talking to the server
---------------------------------------------------------------------------

local busy = {}

local function send(action, value)
	if busy[action] then
		return
	end
	busy[action] = true
	task.spawn(function()
		local ok, result = pcall(function()
			return control:InvokeServer(action, value)
		end)
		busy[action] = nil
		if ok and type(result) == "table" then
			showToast(result.message or (if result.ok then "Done" else "Failed"), result.ok == true)
		else
			showToast("No answer from the server", false)
		end
	end)
end

local function bind(button, action, valueFn)
	button.Activated:Connect(function()
		send(action, if valueFn then valueFn() else nil)
	end)
end

bind(left.Toggle_Sync, "Sync", function() return attr("SyncEnabled", true) == false end)
bind(left.Toggle_DanceFloor, "DanceFloor", function() return attr("DanceFloorEnabled", true) == false end)
bind(left.Toggle_AutoPattern, "AutoPattern", function() return attr("DFAutoPattern", true) == false end)
bind(right.Toggle_Pyro, "Pyro", function() return attr("PyroEnabled", true) == false end)

bind(left.PatternRow.Prev, "PrevPattern")
bind(left.PatternRow.Next, "NextPattern")
bind(left.Flash, "Pulse")

local function brightnessStep(delta)
	return function()
		local current = tonumber(attr("DFBrightness", 1)) or 1
		return math.clamp(math.floor((current + delta) * 10 + 0.5) / 10, 0.1, 1)
	end
end
bind(left.BrightnessRow.Minus, "Brightness", brightnessStep(-0.1))
bind(left.BrightnessRow.Plus, "Brightness", brightnessStep(0.1))

for _, kind in { "CO2", "CONFETTI", "SMOKE" } do
	bind(right["Fire_" .. kind], "Fire", function() return kind end)
end
bind(right.StopPyro, "StopPyro")
bind(right.Blackout, "Blackout")
bind(right.Restore, "Restore")

---------------------------------------------------------------------------
-- Open / close (operators only)
---------------------------------------------------------------------------

local panelHome = panel.Position
local isOpen = false
local closeToken = 0

local function isOperator()
	return player:GetAttribute("AutoLightsOperator") == true
end

local function openPanel()
	if not isOperator() or isOpen then
		return
	end
	isOpen = true
	closeToken += 1
	refresh()
	panel.Position = panelHome + UDim2.fromOffset(50, 0)
	panel.Visible = true
	tween(panel, 0.3, { Position = panelHome }, Enum.EasingStyle.Quart)
end

local function closePanel()
	if not isOpen then
		return
	end
	isOpen = false
	closeToken += 1
	local token = closeToken
	tween(panel, 0.2, { Position = panelHome + UDim2.fromOffset(50, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.2, function()
		if closeToken == token then
			panel.Visible = false
		end
	end)
end

local function updateOperator()
	local operator = isOperator()
	openButton.Visible = operator
	if not operator then
		closePanel()
	end
end

openButton.Activated:Connect(function()
	if isOpen then closePanel() else openPanel() end
end)
panel.CloseButton.Activated:Connect(closePanel)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == TOGGLE_KEY and isOperator() then
		if isOpen then closePanel() else openPanel() end
	end
end)

player:GetAttributeChangedSignal("AutoLightsOperator"):Connect(updateOperator)
updateOperator()
refresh()
