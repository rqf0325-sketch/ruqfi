--[[
	Touch controls for the bike (lives in Tuner.Interface next to the Drive
	script, which wires up Buttons.Left/Right/Gas/Brake/Upshift/Downshift/
	Handbrake itself).

	Roblox's own thumbstick and jump button would sit under these buttons, so
	they are hidden while riding and an Exit button replaces jump. The
	VehicleSpawnerClient also turns them back on when the player is no longer
	seated, in case this GUI is removed before it can do that itself.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

if not UserInputService.TouchEnabled then
	return
end

local player = Players.LocalPlayer
local interface = script.Parent
local buttons = interface:WaitForChild("Buttons")
local character = player.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")

-- The rev/acceleration test widget sits where the Gas button is.
local revAccel = interface:FindFirstChild("RevAccel")
if revAccel then
	revAccel.Visible = false
end

local function restore()
	GuiService.TouchControlsEnabled = true
	player:SetAttribute("VehicleTouchControlsHidden", nil)
end

GuiService.TouchControlsEnabled = false
player:SetAttribute("VehicleTouchControlsHidden", true)

buttons:WaitForChild("Exit").Activated:Connect(function()
	if humanoid then
		humanoid.Sit = false
		humanoid.Jump = true
	end
	restore()
end)

if humanoid then
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		if not humanoid.SeatPart then
			restore()
		end
	end)
	humanoid.Died:Connect(restore)
end
interface.Destroying:Connect(restore)
