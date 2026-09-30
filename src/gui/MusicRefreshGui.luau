--[[
	MusicRefreshGui — tombol refresh musik (tanpa script).

	tools/build.luau menjalankan file ini, menambahkan LocalScript
	src/client/MusicRefreshClient.luau, lalu menyimpan hasilnya ke
	StarterGui/MusicRefreshGui.rbxmx. File ini juga bisa di-paste ke
	Command Bar Studio untuk membuat tampilannya saja.

	Saat game berjalan, MusicRefreshClient memindahkan RefreshButton ke
	samping tombol Donate dan menyamakan tingginya. Posisi di bawah (pojok
	kanan atas, sejajar topbar Roblox) hanya dipakai kalau tombol Donate
	tidak ditemukan, atau kalau FollowDonateButton = false.

	Isi tombol memakai Scale, jadi ikut membesar/mengecil bersama tombolnya.
	Angka di bawah ditulis dalam pixel desain (tombol 100 x 36).
]]

local GUI_NAME = "MusicRefreshGui"
local FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"
local BUTTON_W, BUTTON_H = 100, 36
local TOAST_W, TOAST_H = 170, 30

local C = {
	Background = Color3.fromRGB(17, 20, 27),
	Text = Color3.fromRGB(245, 246, 248),
	Amber = Color3.fromRGB(255, 190, 56),
	Green = Color3.fromRGB(61, 220, 151),
	White = Color3.new(1, 1, 1),
}

local W = Enum.FontWeight

local function font(weight)
	return Font.new(FONT_FAMILY, weight, Enum.FontStyle.Normal)
end

local function new(className, parent, props)
	local inst = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

-- Position/size in design pixels inside a parent of pw x ph design pixels.
local function box(x, y, w, h, pw, ph)
	return UDim2.fromScale(x / pw, y / ph), UDim2.fromScale(w / pw, h / ph)
end

local function label(parent, name, text, x, y, w, h, pw, ph, color, weight, align)
	local position, size = box(x, y, w, h, pw, ph)
	return new("TextLabel", parent, {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color,
		FontFace = font(weight),
		TextSize = h,
		TextScaled = true,
		TextXAlignment = align,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
end

local function build()
	local screenGui = new("ScreenGui", nil, {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	})

	local button = new("TextButton", screenGui, {
		Name = "RefreshButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 11),
		Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
	})
	new("UICorner", button, { CornerRadius = UDim.new(0.5, 0) })
	new("UIStroke", button, {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = C.Amber,
		Transparency = 0.45,
		Thickness = 1.5,
	})
	label(button, "Icon", "🔄", 11, 9, 18, 18, BUTTON_W, BUTTON_H, C.White, W.Regular, Enum.TextXAlignment.Center)
	label(button, "Label", "MUSIC", 35, 11.5, 54, 13, BUTTON_W, BUTTON_H, C.Text, W.ExtraBold, Enum.TextXAlignment.Left)

	-- Short message under the button after a refresh
	local toast = new("Frame", button, {
		Name = "Toast",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 1, 6),
		Size = UDim2.fromScale(TOAST_W / BUTTON_W, TOAST_H / BUTTON_H),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
	})
	new("UICorner", toast, { CornerRadius = UDim.new(0.3, 0) })
	new("UIStroke", toast, {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = C.White,
		Transparency = 0.86,
		Thickness = 1,
	})
	local dotPosition, dotSize = box(12, 11, 8, 8, TOAST_W, TOAST_H)
	local dot = new("Frame", toast, {
		Name = "Dot",
		Position = dotPosition,
		Size = dotSize,
		BackgroundColor3 = C.Green,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
	new("UICorner", dot, { CornerRadius = UDim.new(0.5, 0) })
	local message = label(toast, "Message", "Music refreshed", 28, 9, 132, 12, TOAST_W, TOAST_H, C.Text, W.SemiBold, Enum.TextXAlignment.Left)
	message.ZIndex = 2

	return screenGui
end

---------------------------------------------------------------------------
-- Put it in StarterGui (replaces an older copy with the same name)
---------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local old = StarterGui:FindFirstChild(GUI_NAME)
if old then
	old:Destroy()
end

local gui = build()
gui.Parent = StarterGui

pcall(function()
	game:GetService("Selection"):Set({ gui })
end)
print("[MusicRefreshGui] Dibuat di StarterGui")

return gui
