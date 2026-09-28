--[[
	Scooter — shared by ScooterServer, ScooterClient and the build script.
]]

local Shared = {}

-- The theme called `name`, falling back to Settings.Theme and then to the first listed one.
function Shared.theme(settings, name)
	for _, candidate in { name, settings.Theme, settings.ThemeOrder[1] } do
		if type(candidate) == "string" and settings.Themes[candidate] then
			return settings.Themes[candidate], candidate
		end
	end
	local fallback, theme = next(settings.Themes)
	return theme, fallback
end

-- Paints every part by its "Role" attribute. Returns the theme name used.
function Shared.applyTheme(body, settings, name)
	local theme, themeName = Shared.theme(settings, name)
	for _, part in body:GetDescendants() do
		if part:IsA("BasePart") then
			local role = part:GetAttribute("Role")
			local look = role and theme[role]
			if type(look) == "table" then
				part.Color = look.Color
				part.Material = look.Material or Enum.Material.SmoothPlastic
				part.Reflectance = look.Reflectance or 0
			end
		end
	end
	local underglow = body:FindFirstChild("Underglow", true)
	if underglow and theme.Light then
		underglow.Color = theme.Light
	end
	body:SetAttribute("Theme", themeName)
	body:SetAttribute("HasUnderglow", theme.Light ~= nil)
	return themeName
end

-- Mount.C0: puts the scooter's Root (the deck surface) under the rider's
-- feet. `hipHeight` is the rider's HipHeight before it is raised for the deck.
-- R6 holds the bar with the middle of its arm blocks; R15 holds it with the
-- hands at the end of longer, bending arms, so an R15 rider stands further
-- back from the bar (the scooter sits a little further forward).
local R15_BAR_REACH = 0.24 -- times the rider's height (below)

function Shared.mountOffset(humanoid, rootPart, hipHeight)
	local legs = hipHeight
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	if r6 then
		local leg = humanoid.Parent:FindFirstChild("Left Leg") or humanoid.Parent:FindFirstChild("Right Leg")
		legs += if leg then leg.Size.Y else 2
	end
	local height = rootPart.Size.Y / 2 + legs
	return CFrame.new(0, -height, if r6 then 0 else -R15_BAR_REACH * height)
end

-- The scooter is sized for a standard R6 (3 studs from the root part's
-- middle to the soles). Other riders get it scaled by their own height, so
-- a tall or small R15 avatar still reaches the grips.
local REFERENCE_HEIGHT = 3
local MIN_SCALE, MAX_SCALE = 0.75, 1.4

function Shared.riderScale(settings, humanoid, rootPart, hipHeight)
	if settings.FitRiderSize == false then
		return 1
	end
	local height = -Shared.mountOffset(humanoid, rootPart, hipHeight).Position.Y
	return math.clamp(height / REFERENCE_HEIGHT, MIN_SCALE, MAX_SCALE)
end

-- Scales the scooter (parts, joints, attachments) around its Root.
function Shared.fit(body, scale)
	if math.abs(body:GetScale() - scale) > 1e-3 then
		body:ScaleTo(scale)
	end
end

return Shared
