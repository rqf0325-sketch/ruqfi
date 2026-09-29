-- DanceFloorSync.server.lua
-- Place in: ServerScriptService > AutoLightsServer
--
-- Creative beat-reactive dancefloor with:
--   • 12 different visual patterns that cycle automatically
--   • Soft brightness (won't hurt eyes — max ~35% of GLights)
--   • Smooth fade between patterns
--   • Movement: ripples, spirals, snakes, meteors, pulses, checkers
--   • Every pattern responds differently to each beat
--   • Fully duplicatable (DanceFloorJin, DanceFloorJin2 etc.)

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─────────────────────────────────────────────────────────────────
-- CONFIG
-- ─────────────────────────────────────────────────────────────────
local AutoLightsServer = script.Parent
local ok, SyncCFG = pcall(function()
	return require(AutoLightsServer:WaitForChild("AutoLightsSyncConfig", 3))
end)
if not ok then SyncCFG = {} end

local CFG = {
	GRID_COLS       = SyncCFG.DF_GRID_COLS   or 10,
	GRID_ROWS       = SyncCFG.DF_GRID_ROWS   or 10,
	TILE_GAP        = SyncCFG.DF_TILE_GAP    or 0.06,
	TILE_HEIGHT     = SyncCFG.DF_TILE_HEIGHT  or 0.12,

	-- ★ BRIGHTNESS: much softer than GLights
	-- Peak flash brightness (0-1). 0.35 = 35% — visible but not blinding
	PEAK_BRIGHTNESS  = 1.65,
	-- Between-beat glow (very dim)
	IDLE_BRIGHTNESS  = 1.24,
	-- How fast tiles fade back to idle
	FADE_SPEED       = 0.8,

	-- Pattern change: how many bars before switching pattern
	BARS_PER_PATTERN = 4,

	BEAT_THRESHOLD   = SyncCFG.BEAT_THRESHOLD or 180,
}

-- ─────────────────────────────────────────────────────────────────
-- MODULES
-- ─────────────────────────────────────────────────────────────────
local Modules       = AutoLightsServer:WaitForChild("Modules")
local LoggerService = require(Modules:WaitForChild("LoggerService"))
local BeatService   = require(Modules:WaitForChild("BeatService"))
local Logger        = LoggerService.new()
local Beat          = BeatService.new(Logger)
Beat:SetConfig({ baseThreshold = CFG.BEAT_THRESHOLD })

-- ─────────────────────────────────────────────────────────────────
-- REMOTES
-- ─────────────────────────────────────────────────────────────────
local autoRoot = ReplicatedStorage:FindFirstChild("AutoLights") or Instance.new("Folder")
autoRoot.Name = "AutoLights"; autoRoot.Parent = ReplicatedStorage

local remotes = autoRoot:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"; remotes.Parent = autoRoot

local function getOrMakeRE(n)
	local r = remotes:FindFirstChild(n)
	if not r then r = Instance.new("RemoteEvent"); r.Name = n; r.Parent = remotes end
	return r
end
local RE_AudioTelemetry = getOrMakeRE("AudioTelemetry")

-- ─────────────────────────────────────────────────────────────────
-- PALETTE  (soft, desaturated slightly so they don't scream)
-- ─────────────────────────────────────────────────────────────────
local COLORS = {}
pcall(function()
	local Shared  = ReplicatedStorage:WaitForChild("AutoLights"):WaitForChild("Shared")
	local Palette = require(Shared:WaitForChild("Palette"))
	for _, v in pairs(Palette) do
		if typeof(v) == "Color3" then table.insert(COLORS, v) end
	end
end)
if #COLORS < 4 then
	COLORS = {
		Color3.fromRGB(255,40,100),  Color3.fromRGB(40,160,255),
		Color3.fromRGB(255,100,20),  Color3.fromRGB(160,40,255),
		Color3.fromRGB(40,220,120),  Color3.fromRGB(255,200,30),
		Color3.fromRGB(255,40,180),  Color3.fromRGB(40,100,255),
		Color3.fromRGB(200,255,80),  Color3.fromRGB(80,220,255),
	}
end

local function rndColor()
	return COLORS[math.random(1, #COLORS)]
end

local function hueColor(h, s, v)
	s = s or 0.75  -- slightly desaturated vs GLights
	v = v or 1
	return Color3.fromHSV(h % 1, s, v)
end

local function lerpColor(a, b, t)
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

-- ─────────────────────────────────────────────────────────────────
-- GRID BUILDER
-- ─────────────────────────────────────────────────────────────────
local function buildGrid(dfPart)
	local existing = dfPart.Parent:FindFirstChild("_Tiles")
	if existing then existing:Destroy() end

	local tileFolder = Instance.new("Folder")
	tileFolder.Name = "_Tiles"
	tileFolder.Parent = dfPart.Parent

	local R    = CFG.GRID_ROWS
	local C    = CFG.GRID_COLS
	local gap  = CFG.TILE_GAP
	local th   = CFG.TILE_HEIGHT
	local sz   = dfPart.Size
	local cf   = dfPart.CFrame

	local usableX = sz.X - gap
	local usableZ = sz.Z - gap
	local tileW   = (usableX - gap*(C-1)) / C
	local tileD   = (usableZ - gap*(R-1)) / R
	local topY    = sz.Y/2 + th/2

	local tiles = {}
	for r = 1, R do
		tiles[r] = {}
		for c = 1, C do
			local lx = -usableX/2 + (c-1)*(tileW+gap) + tileW/2
			local lz = -usableZ/2 + (r-1)*(tileD+gap) + tileD/2

			local tile = Instance.new("Part")
			tile.Name          = ("T_%d_%d"):format(r,c)
			tile.Size          = Vector3.new(tileW, th, tileD)
			tile.Anchored      = true
			tile.CanCollide    = false
			tile.CastShadow    = false
			tile.Material      = Enum.Material.Neon
			tile.Color         = Color3.new(0,0,0)
			tile.TopSurface    = Enum.SurfaceType.Smooth
			tile.BottomSurface = Enum.SurfaceType.Smooth
			tile.CFrame        = cf * CFrame.new(lx, topY, lz)
			tile.Parent        = tileFolder

			tiles[r][c] = tile
		end
	end

	dfPart.Transparency = 1
	return tiles
end

-- ─────────────────────────────────────────────────────────────────
-- FLOOR STATE
-- ─────────────────────────────────────────────────────────────────
local function newFloorState(dfPart)
	local R = CFG.GRID_ROWS
	local C = CFG.GRID_COLS

	local tiles     = buildGrid(dfPart)
	-- current target color per tile
	local tgtColor  = {}
	-- current rendered brightness per tile (0-1)
	local bright    = {}
	-- per-tile phase offset (for animations that need it)
	local phase     = {}

	local maxDist = math.sqrt((R/2)^2 + (C/2)^2)

	for r = 1, R do
		tgtColor[r] = {}
		bright[r]   = {}
		phase[r]    = {}
		for c = 1, C do
			tgtColor[r][c] = Color3.new(0,0,0)
			bright[r][c]   = 0
			-- distance from center (0=center, 1=corner)
			local dr = (r - R/2 - 0.5)
			local dc = (c - C/2 - 0.5)
			phase[r][c] = math.sqrt(dr*dr + dc*dc) / maxDist
		end
	end

	return {
		tiles       = tiles,
		tgtColor    = tgtColor,
		bright      = bright,
		phase       = phase,
		R           = R, C = C,
		maxDist     = maxDist,
		beatCount   = 0,
		barCount    = 0,
		patternIdx  = 1,
		hue         = math.random(),   -- current base hue
		hue2        = math.random(),   -- secondary hue
		snakePos    = 1,               -- snake head position
		snakeDir    = 1,
		meteorCol   = math.random(1, C),
		meteorRow   = 1,
		spiralStep  = 0,
		lastPattern = nil,
	}
end

-- ─────────────────────────────────────────────────────────────────
-- PATTERNS
-- Each pattern is a function(fs, beatIndex) that sets
-- fs.tgtColor[r][c] and fs.bright[r][c] for tiles it wants to flash.
-- Tiles it doesn't touch fade naturally.
-- ─────────────────────────────────────────────────────────────────

-- Helper: flash a tile
local function flash(fs, r, c, color, brightness)
	brightness = brightness or CFG.PEAK_BRIGHTNESS
	if r<1 or r>fs.R or c<1 or c>fs.C then return end
	fs.tgtColor[r][c] = color
	fs.bright[r][c]   = brightness
end

-- Helper: flash with delay (ripple effect)
local function flashDelay(fs, r, c, color, delay, brightness)
	brightness = brightness or CFG.PEAK_BRIGHTNESS
	if r<1 or r>fs.R or c<1 or c>fs.C then return end
	task.delay(delay, function()
		if fs.tiles[r] and fs.tiles[r][c] then
			fs.tgtColor[r][c] = color
			fs.bright[r][c]   = brightness
		end
	end)
end

-- 1. RIPPLE FROM CENTER — concentric rings pulse outward
local function patternRipple(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.11) % 1
	local col = hueColor(fs.hue)
	for r = 1, R do
		for c = 1, C do
			local d     = fs.phase[r][c]  -- 0=center, 1=corner
			local delay = d * 0.22
			flashDelay(fs, r, c, hueColor((fs.hue + d*0.2) % 1), delay)
		end
	end
end

-- 2. CHECKERBOARD SWAP — two colors alternate every beat
local function patternChecker(fs, beat)
	local colA = hueColor(fs.hue)
	local colB = hueColor((fs.hue + 0.5) % 1)
	fs.hue = (fs.hue + 0.08) % 1
	local flip = (beat % 2 == 0)
	for r = 1, fs.R do
		for c = 1, fs.C do
			local isA = ((r+c) % 2 == 0) == flip
			flash(fs, r, c, isA and colA or colB, CFG.PEAK_BRIGHTNESS * 0.8)
		end
	end
end

-- 3. SNAKE — a bright line snakes across the floor
local function patternSnake(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.06) % 1
	local col = hueColor(fs.hue)

	-- advance snake by 2 columns per beat
	fs.snakePos = fs.snakePos + 2 * fs.snakeDir
	if fs.snakePos > C then fs.snakePos = C; fs.snakeDir = -1 end
	if fs.snakePos < 1 then fs.snakePos = 1; fs.snakeDir =  1 end

	-- light a vertical stripe at snake position
	for r = 1, R do
		local dist = math.abs(r - (R/2 + 0.5)) / (R/2)
		flash(fs, r, fs.snakePos, col, CFG.PEAK_BRIGHTNESS * (1 - dist*0.4))
		-- soft glow on adjacent columns
		local dimCol = hueColor((fs.hue + 0.05) % 1)
		if fs.snakePos > 1 then
			flash(fs, r, fs.snakePos-1, dimCol, CFG.PEAK_BRIGHTNESS * 0.3)
		end
		if fs.snakePos < C then
			flash(fs, r, fs.snakePos+1, dimCol, CFG.PEAK_BRIGHTNESS * 0.3)
		end
	end
end

-- 4. DIAGONAL SWEEP — color sweeps diagonally corner to corner
local function patternDiagonal(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.09) % 1
	local maxD = R + C - 2
	local beatMod = beat % (maxD + 1)

	for r = 1, R do
		for c = 1, C do
			local d = (r-1) + (c-1)
			if d == beatMod then
				flash(fs, r, c, hueColor(fs.hue), CFG.PEAK_BRIGHTNESS)
			elseif math.abs(d - beatMod) == 1 then
				flash(fs, r, c, hueColor((fs.hue+0.05)%1), CFG.PEAK_BRIGHTNESS * 0.4)
			end
		end
	end
end

-- 5. METEOR SHOWER — bright dots fall from top
local function patternMeteor(fs, beat)
	local R, C = fs.R, fs.C
	-- spawn a new meteor column each beat
	fs.meteorCol = math.random(1, C)
	local col    = hueColor((fs.hue + math.random()*0.3) % 1)
	fs.hue       = (fs.hue + 0.07) % 1

	-- flash each row with increasing delay (falling effect)
	for r = 1, R do
		local delay = (r-1) * 0.04
		local dim   = CFG.PEAK_BRIGHTNESS * (1 - (r-1)/R * 0.5)
		flashDelay(fs, r, fs.meteorCol, col, delay, dim)
		-- trail
		if r > 1 then
			flashDelay(fs, r-1, fs.meteorCol,
				hueColor((fs.hue+0.1)%1), delay + 0.01, dim * 0.3)
		end
	end
end

-- 6. SPIRAL — color spirals inward from edges
local function patternSpiral(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.10) % 1
	-- compute spiral order (outer ring first, then inner)
	local spiralOrder = {}
	local visited = {}
	for r = 1, R do
		visited[r] = {}
		for c = 1, C do visited[r][c] = false end
	end

	local top, bot, lft, rgt = 1, R, 1, C
	while top <= bot and lft <= rgt do
		for c = lft, rgt do table.insert(spiralOrder, {top, c}) end
		for r = top+1, bot do table.insert(spiralOrder, {r, rgt}) end
		if bot > top then
			for c = rgt-1, lft, -1 do table.insert(spiralOrder, {bot, c}) end
		end
		if rgt > lft then
			for r = bot-1, top+1, -1 do table.insert(spiralOrder, {r, lft}) end
		end
		top += 1; bot -= 1; lft += 1; rgt -= 1
	end

	-- flash each tile in spiral order with stagger
	for i, pos in ipairs(spiralOrder) do
		local delay = (i-1) * 0.015
		local hue   = (fs.hue + i/#spiralOrder * 0.4) % 1
		flashDelay(fs, pos[1], pos[2], hueColor(hue), delay,
			CFG.PEAK_BRIGHTNESS * (0.5 + 0.5 * (1 - i/#spiralOrder)))
	end
end

-- 7. COLUMNS RACE — columns light up in sequence, left to right or reverse
local function patternColumns(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.12) % 1
	local col = beat % C + 1  -- which column lights up this beat
	local mainCol = hueColor(fs.hue)
	for r = 1, R do
		local delay = (r-1) * 0.02
		flashDelay(fs, r, col, mainCol, delay)
	end
	-- soft echo on previous column
	local prev = col > 1 and col-1 or C
	for r = 1, R do
		flash(fs, r, prev, hueColor((fs.hue+0.15)%1), CFG.PEAK_BRIGHTNESS * 0.25)
	end
end

-- 8. ROWS RACE — rows sweep top to bottom
local function patternRows(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.08) % 1
	local row = beat % R + 1
	local mainCol = hueColor(fs.hue)
	for c = 1, C do
		local delay = (c-1) * 0.018
		flashDelay(fs, row, c, mainCol, delay)
	end
	local prev = row > 1 and row-1 or R
	for c = 1, C do
		flash(fs, prev, c, hueColor((fs.hue+0.2)%1), CFG.PEAK_BRIGHTNESS * 0.2)
	end
end

-- 9. HEARTBEAT PULSE — whole floor pulses softly in one color,
--    only the center tile goes bright
local function patternPulse(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.04) % 1
	local baseCol = hueColor(fs.hue, 0.6, 1)

	for r = 1, R do
		for c = 1, C do
			local d = fs.phase[r][c]  -- 0=center, 1=corner
			-- center bright, edges dim
			local b = CFG.PEAK_BRIGHTNESS * (1 - d * 0.75)
			flash(fs, r, c, hueColor((fs.hue + d*0.1)%1, 0.5, 1), b)
		end
	end
end

-- 10. RANDOM SCATTER — random tiles pop each beat
local function patternScatter(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.13) % 1
	-- light ~40% of tiles randomly
	local count = math.floor(R * C * 0.4)
	for _ = 1, count do
		local r = math.random(1, R)
		local c = math.random(1, C)
		flash(fs, r, c, hueColor(math.random()*1.0, 0.8, 1))
	end
end

-- 11. DIAMOND EXPAND — diamond shape grows from center outward
local function patternDiamond(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.09) % 1
	local size = (beat % math.floor(math.max(R,C)/2 + 1))
	local cr, cc = R/2 + 0.5, C/2 + 0.5

	for r = 1, R do
		for c = 1, C do
			local d = math.abs(r - cr) + math.abs(c - cc)
			if math.floor(d) == size then
				flash(fs, r, c, hueColor(fs.hue), CFG.PEAK_BRIGHTNESS)
			elseif math.floor(d) == math.max(0, size-1) then
				flash(fs, r, c, hueColor((fs.hue+0.1)%1), CFG.PEAK_BRIGHTNESS * 0.35)
			end
		end
	end
end

-- 12. DUAL WAVE — two color waves travel in opposite directions
local function patternDualWave(fs, beat)
	local R, C = fs.R, fs.C
	fs.hue  = (fs.hue  + 0.07) % 1
	fs.hue2 = (fs.hue2 + 0.11) % 1

	for r = 1, R do
		for c = 1, C do
			-- wave A travels left, wave B travels right
			local wA = math.sin((c/C + beat*0.15) * math.pi * 2) * 0.5 + 0.5
			local wB = math.sin((1 - c/C + beat*0.15) * math.pi * 2) * 0.5 + 0.5
			-- combine waves
			local combined = (wA + wB) * 0.5
			local col = lerpColor(hueColor(fs.hue, 0.7, 1), hueColor(fs.hue2, 0.7, 1), wA)
			local b   = CFG.PEAK_BRIGHTNESS * combined * 0.9
			if b > CFG.IDLE_BRIGHTNESS then
				flash(fs, r, c, col, b)
			end
		end
	end
end

-- PATTERN LIST (in order — cycles automatically every N bars)
local PATTERNS = {
	{ name="Ripple",    fn=patternRipple    },
	{ name="DualWave",  fn=patternDualWave  },
	{ name="Checker",   fn=patternChecker   },
	{ name="Diamond",   fn=patternDiamond   },
	{ name="Snake",     fn=patternSnake     },
	{ name="Columns",   fn=patternColumns   },
	{ name="Meteor",    fn=patternMeteor    },
	{ name="Pulse",     fn=patternPulse     },
	{ name="Diagonal",  fn=patternDiagonal  },
	{ name="Rows",      fn=patternRows      },
	{ name="Scatter",   fn=patternScatter   },
	{ name="Spiral",    fn=patternSpiral    },
}

-- ─────────────────────────────────────────────────────────────────
-- BEAT HANDLER
-- ─────────────────────────────────────────────────────────────────
local function onBeatForFloor(fs, beatIndex, barIndex)
	fs.beatCount += 1

	-- advance pattern every N bars
	local barsPerPattern = CFG.BARS_PER_PATTERN
	local beatsInBar = 4
	if fs.beatCount % (barsPerPattern * beatsInBar) == 0 then
		fs.patternIdx = (fs.patternIdx % #PATTERNS) + 1
		-- pattern changed silently
	end

	local pattern = PATTERNS[fs.patternIdx]
	task.spawn(pattern.fn, fs, beatIndex)
end

-- ─────────────────────────────────────────────────────────────────
-- HEARTBEAT FADE
-- ─────────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	local fadeStep = CFG.FADE_SPEED * dt * 60
	local idleDim  = CFG.IDLE_BRIGHTNESS
	local floors   = _G.__DFFloors or {}

	for _, fs in ipairs(floors) do
		for r = 1, fs.R do
			for c = 1, fs.C do
				local b = fs.bright[r][c]
				if b > idleDim then
					b = math.max(idleDim, b - fadeStep)
					fs.bright[r][c] = b
				elseif b < idleDim then
					b = math.min(idleDim, b + fadeStep * 0.5)
					fs.bright[r][c] = b
				end
				-- apply to tile
				local tile = fs.tiles[r][c]
				if tile and tile.Parent then
					local col = fs.tgtColor[r][c]
					tile.Color = Color3.new(
						col.R * b,
						col.G * b,
						col.B * b
					)
				end
			end
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────
-- DISCOVER FLOORS
-- ─────────────────────────────────────────────────────────────────
local floors = {}
_G.__DFFloors = floors  -- share with Heartbeat closure

local function discoverFloors()
	-- clear existing
	for _, fs in ipairs(floors) do
		local folder = fs.tiles[1] and fs.tiles[1][1] and fs.tiles[1][1].Parent
		if folder then pcall(function() folder:Destroy() end) end
	end
	table.clear(floors)

	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name:match("^DanceFloorJin") then
			local df = child:FindFirstChild("DF")
			if df and df:IsA("BasePart") then
				local fs = newFloorState(df)
				table.insert(floors, fs)
				-- start on a random pattern
				fs.patternIdx = math.random(1, #PATTERNS)
				-- floor registered silently
			end
		end
	end

	-- floors discovered silently
end

discoverFloors()

workspace.ChildAdded:Connect(function(child)
	if child.Name:match("^DanceFloorJin") then
		task.wait(0.5)
		local df = child:FindFirstChild("DF")
		if df and df:IsA("BasePart") then
			local fs = newFloorState(df)
			fs.patternIdx = math.random(1, #PATTERNS)
			table.insert(floors, fs)
			-- new floor registered silently
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────
-- TELEMETRY RECEIVER
-- ─────────────────────────────────────────────────────────────────
local telLastT       = {}
local activeTelUID   = nil
local activeTelLastT = -1e9

RE_AudioTelemetry.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then return end
	local nowT = os.clock()
	if not activeTelUID or (nowT - activeTelLastT) > 2.0 then
		activeTelUID = player.UserId
	end
	if player.UserId ~= activeTelUID then return end
	activeTelLastT = nowT

	local rms   = math.max(0, tonumber(payload.rms) or 0)
	local lastT = telLastT[player.UserId] or nowT
	local dt    = math.clamp(nowT - lastT, 0.001, 0.2)
	telLastT[player.UserId] = nowT

	local ev = Beat:StepFromRms(dt, nowT, rms)
	if ev then
		for _, fs in ipairs(floors) do
			task.spawn(onBeatForFloor, fs, ev.beatIndex, ev.barIndex)
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────
-- FALLBACK HEARTBEAT
-- ─────────────────────────────────────────────────────────────────
local lastFallbackT = -1e9
RunService.Heartbeat:Connect(function(dt)
	local nowT = os.clock()
	local age  = Beat:TelemetryAge(nowT)
	if age > 0.25 then Beat:Decay(dt) end
	if age > 2.0 and #floors > 0 then
		local bpm = tonumber(Beat:GetState().bpm) or 120
		local gap = 60 / math.max(1, bpm)
		if (nowT - lastFallbackT) >= gap then
			lastFallbackT = nowT
			local ev = Beat:ForceBeat(nowT)
			if ev then
				for _, fs in ipairs(floors) do
					task.spawn(onBeatForFloor, fs, ev.beatIndex, ev.barIndex)
				end
			end
		end
	end
end)

-- DanceFloorSync loaded