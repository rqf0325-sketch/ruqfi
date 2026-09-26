--[[
	Generates StarterGui/VehicleSpawnerGui.rbxmx from src/VehicleSpawnerGui.luau.

	  lune run tools/build.luau            -- writes the .rbxmx
	  lune run tools/build.luau -- --tree  -- also writes build/tree.json (for tools/preview)
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local SOURCE = "src/VehicleSpawnerGui.luau"
local OUT_MODEL = "StarterGui/VehicleSpawnerGui.rbxmx"
local OUT_TREE = "build/tree.json"

local env = setmetatable({
	game = roblox.Instance.new("DataModel"),
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Font = roblox.Font,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = roblox.Vector2,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
}, { __index = getfenv(1) })

local gui = luau.load(fs.readFile(SOURCE), { debugName = SOURCE, environment = env })()
gui.Parent = nil

fs.writeFile(OUT_MODEL, roblox.serializeModel({ gui }, true))
print(`Wrote {OUT_MODEL} ({#gui:GetDescendants() + 1} instances)`)

if not table.find(process.args, "--tree") then
	return
end

-- JSON dump of the properties the preview renderer understands.
local PROPS = {
	"Name", "Position", "Size", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency",
	"Visible", "ZIndex", "LayoutOrder", "ClipsDescendants",
	"Text", "TextColor3", "TextTransparency", "TextXAlignment", "TextYAlignment", "TextScaled",
	"TextSize", "FontFace", "RichText", "PlaceholderText", "PlaceholderColor3",
	"ScrollBarThickness", "ScrollBarImageColor3", "ScrollBarImageTransparency",
	"CornerRadius", "Color", "Thickness", "Transparency", "Rotation",
	"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight",
	"FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment",
	"CellSize", "CellPadding", "AspectRatio", "AspectType", "DominantAxis",
}

local function encode(value)
	local kind = typeof(value)
	if kind == "UDim2" then
		return { xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset }
	elseif kind == "UDim" then
		return { s = value.Scale, o = value.Offset }
	elseif kind == "Vector2" then
		return { x = value.X, y = value.Y }
	elseif kind == "Color3" then
		return { r = value.R, g = value.G, b = value.B }
	elseif kind == "EnumItem" then
		return value.Name
	elseif kind == "Font" then
		return { family = value.Family, weight = value.Weight.Value }
	elseif kind == "ColorSequence" then
		local points = {}
		for _, k in value.Keypoints do
			table.insert(points, { t = k.Time, r = k.Value.R, g = k.Value.G, b = k.Value.B })
		end
		return points
	elseif kind == "NumberSequence" then
		local points = {}
		for _, k in value.Keypoints do
			table.insert(points, { t = k.Time, v = k.Value })
		end
		return points
	elseif kind == "string" or kind == "number" or kind == "boolean" then
		return value
	end
	return nil
end

local function dump(inst)
	local node = { class = inst.ClassName, props = {}, children = {} }
	for _, prop in PROPS do
		local ok, value = pcall(function()
			return inst[prop]
		end)
		if ok and value ~= nil then
			node.props[prop] = encode(value)
		end
	end
	for _, child in inst:GetChildren() do
		table.insert(node.children, dump(child))
	end
	return node
end

fs.writeDir("build")
fs.writeFile(OUT_TREE, serde.encode("json", dump(gui), true))
print(`Wrote {OUT_TREE}`)
