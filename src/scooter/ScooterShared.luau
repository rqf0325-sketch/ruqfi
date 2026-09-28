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
function Shared.mountOffset(humanoid, rootPart, hipHeight)
	local legs = hipHeight
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = humanoid.Parent:FindFirstChild("Left Leg") or humanoid.Parent:FindFirstChild("Right Leg")
		legs += if leg then leg.Size.Y else 2
	end
	return CFrame.new(0, -(rootPart.Size.Y / 2 + legs), 0)
end

return Shared
