-- Dumps an Instance tree to plain tables for the HTML preview renderer.
local PROPS = {
	"Name", "Position", "Size", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency",
	"Visible", "ZIndex", "LayoutOrder", "ClipsDescendants",
	"Text", "TextColor3", "TextTransparency", "TextXAlignment", "TextYAlignment", "TextScaled",
	"TextSize", "FontFace", "RichText", "PlaceholderText", "PlaceholderColor3",
	"ScrollBarThickness", "ScrollBarImageColor3", "ScrollBarImageTransparency",
	"CornerRadius", "Color", "Thickness", "Transparency", "Rotation",
	"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight",
	"FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment",
	"CellSize", "CellPadding", "AspectRatio", "AspectType", "DominantAxis", "Enabled",
	"Scale", "MaxTextSize", "MinTextSize", "ApplyStrokeMode",
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

return dump
