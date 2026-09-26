--[[
	Gives the rider the lights/indicator controls (DriveSeat.SS3) while they
	ride and removes them when they get off. Replaces the original
	"Gui Giver" + "TheFix" pair, which referenced values that do not exist
	on this bike and errored on every ride.
]]

local Players = game:GetService("Players")

local seat = script.Parent
local template = seat:WaitForChild("SS3")

local function removeFrom(player)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	for _, gui in playerGui and playerGui:GetChildren() or {} do
		local carSeat = gui.Name == "SS3" and gui:FindFirstChild("CarSeat")
		if carSeat and carSeat.Value == seat then
			gui:Destroy()
		end
	end
end

local rider = nil

seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	if rider then
		removeFrom(rider)
		rider = nil
	end
	local humanoid = seat.Occupant
	local player = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		rider = player
		local gui = template:Clone()
		gui.CarSeat.Value = seat
		gui.Parent = playerGui
	end
end)

seat.Destroying:Connect(function()
	if rider then
		removeFrom(rider)
	end
end)
