-- DanceFloorSync.server.lua
-- Place in: ServerScriptService > AutoLightsServer
--
-- Creative beat-reactive dancefloor with:
--   • 12 different visual patterns that cycle automatically
--   • Soft brightness (set in AutoLightsSyncConfig: DF_PEAK / DF_IDLE / DF_FADE)
--   • Smooth fade between patterns
--   • Movement: ripples, spirals, snakes, meteors, pulses, checkers
--   • Every pattern responds differently to each beat
--   • Fully duplicatable (DanceFloorJin, DanceFloorJin2 etc.)
--
-- Patch notes (PAUL):
--   • brightness / fade / pattern length now come from AutoLightsSyncConfig
--     (they used to be hard-coded to 1.65 / 1.24, so the floor never dimmed)
--   • the telemetry owner is the player whose audio actually moves; a muted client
--     can no longer freeze the beats for everybody, and rms is validated + rate limited
--   • floors that were destroyed are dropped; tiles are only written when they change
--   • follows the Control Panel: Sync switch (beats) and Dance Floor switch (tiles)

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

	-- Peak flash brightness (0-1)
	PEAK_BRIGHTNESS  = SyncCFG.DF_PEAK_BRIGHTNESS or 1.0,
	-- Between-beat glow (very dim)
	IDLE_BRIGHTNESS  = SyncCFG.DF_IDLE_BRIGHTNESS or 0.06,
	-- How fast tiles fade back to idle (per frame at 60 FPS)
	FADE_SPEED       = SyncCFG.DF_FADE_SPEED or 0.12,

	-- Pattern change: how many bars before switching pattern
	BARS_PER_PATTERN = SyncCFG.DF_BARS_PER_PATTERN or 4,

	BEAT_THRESHOLD   = SyncCFG.BEAT_THRESHOLD or 180,
}

-- ─────────────────────────────────────────────────────────────────
-- MODULES
-- ─────────────────────────────────────────────────────────────────
local Modules       = AutoLightsServer:WaitForChild("Modules")
local LoggerService = require(Modules:WaitForChild("LoggerService"))
local State         = require(Modules:WaitForChild("AutoLightsState"))
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
-- PALETTE  (kept for reference; the patterns below use hue colors)
-- ─────────────────────────────────────────────────────────────────
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

-- All floors (filled by discoverFloors below; declared first so the fade loop can use it)
local floors = {}

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
	return tiles, tileFolder
end

-- ─────────────────────────────────────────────────────────────────
-- FLOOR STATE
-- ─────────────────────────────────────────────────────────────────
local function newFloorState(dfPart)
	local R = CFG.GRID_ROWS
	local C = CFG.GRID_COLS

	local tiles, tileFolder = buildGrid(dfPart)
	-- current target color per tile
	local tgtColor  = {}
	-- current rendered brightness per tile (0-1)
	local bright    = {}
	-- per-tile phase offset (for animations that need it)
	local phase     = {}
	-- last color written to the tile (so unchanged tiles are not touched again)
	local applied   = {}

	local maxDist = math.sqrt((R/2)^2 + (C/2)^2)

	for r = 1, R do
		tgtColor[r] = {}
		bright[r]   = {}
		phase[r]    = {}
		applied[r]  = {}
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
		part        = dfPart,
		folder      = tileFolder,
		tiles       = tiles,
		tgtColor    = tgtColor,
		bright      = bright,
		phase       = phase,
		applied     = applied,
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
local function patternRipple(fs, _beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.11) % 1
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
local function patternSnake(fs, _beat)
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
local function patternMeteor(fs, _beat)
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
local function patternSpiral(fs, _beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.10) % 1
	-- compute spiral order (outer ring first, then inner)
	local spiralOrder = {}

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
local function patternPulse(fs, _beat)
	local R, C = fs.R, fs.C
	fs.hue = (fs.hue + 0.04) % 1

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
local function patternScatter(fs, _beat)
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
-- CONTROL PANEL HOOKS (attributes on ReplicatedStorage.AutoLights)
--   SyncEnabled / DanceFloorEnabled   the two main switches (see AutoLightsState)
--   DFAutoPattern (bool)              patterns advance by themselves (default true)
--   DFPattern (number)                set it to make every floor show that pattern
--   DFPatternNow / DFPatternName      read-only: pattern (number / name) of the first floor
--   DFBrightness (0.1 - 1)            multiplies peak and idle brightness
--   DFPulse (number)                  change it to flash the whole floor once
--   BeatCount / Bpm                   read-only, updated on every beat
-- Only server scripts write them, so players cannot change the floor by themselves.
-- ─────────────────────────────────────────────────────────────────
local BASE_PEAK = CFG.PEAK_BRIGHTNESS
local BASE_IDLE = CFG.IDLE_BRIGHTNESS
autoRoot:SetAttribute("DFPatternCount", #PATTERNS)

local function applyBrightness()
	local mult = tonumber(autoRoot:GetAttribute("DFBrightness")) or 1
	mult = math.clamp(mult, 0.1, 1)
	CFG.PEAK_BRIGHTNESS = BASE_PEAK * mult
	CFG.IDLE_BRIGHTNESS = BASE_IDLE * mult
end

local function publishPattern(index)
	autoRoot:SetAttribute("DFPatternNow", index)
	autoRoot:SetAttribute("DFPatternName", PATTERNS[index] and PATTERNS[index].name or "")
end

local beatCounter = 0
local function publishBeat(ev)
	beatCounter += 1
	autoRoot:SetAttribute("BeatCount", beatCounter)
	local bpm = ev and tonumber(ev.bpm)
	if not bpm then
		local okState, st = pcall(function() return Beat:GetState() end)
		bpm = okState and type(st) == "table" and tonumber(st.bpm) or nil
	end
	if bpm then
		autoRoot:SetAttribute("Bpm", math.floor(bpm + 0.5))
	end
end

-- ─────────────────────────────────────────────────────────────────
-- BEAT HANDLER
-- ─────────────────────────────────────────────────────────────────
local function onBeatForFloor(fs, beatIndex, _barIndex)
	fs.beatCount += 1

	-- advance pattern every N bars (unless the panel pinned one)
	local barsPerPattern = CFG.BARS_PER_PATTERN
	local beatsInBar = 4
	if autoRoot:GetAttribute("DFAutoPattern") ~= false
		and fs.beatCount % (barsPerPattern * beatsInBar) == 0 then
		fs.patternIdx = (fs.patternIdx % #PATTERNS) + 1
		if fs == floors[1] then
			publishPattern(fs.patternIdx)
		end
	end

	local pattern = PATTERNS[fs.patternIdx]
	task.spawn(pattern.fn, fs, beatIndex)
end

-- Beats only move the floor while both the Sync and the Dance Floor switches are ON.
local function floorLive()
	return State.SyncEnabled() and State.DanceFloorEnabled()
end

-- Flash the whole floor once (the panel's TEST button)
local function pulseAll()
	for _, fs in ipairs(floors) do
		local hue = math.random()
		for r = 1, fs.R do
			for c = 1, fs.C do
				flash(fs, r, c, hueColor((hue + fs.phase[r][c] * 0.3) % 1), CFG.PEAK_BRIGHTNESS)
			end
		end
	end
end

autoRoot:GetAttributeChangedSignal("DFBrightness"):Connect(applyBrightness)
autoRoot:GetAttributeChangedSignal("DFPulse"):Connect(function()
	if State.DanceFloorEnabled() then
		pulseAll()
	end
end)
autoRoot:GetAttributeChangedSignal("DFPattern"):Connect(function()
	local index = tonumber(autoRoot:GetAttribute("DFPattern"))
	if index and PATTERNS[math.floor(index)] then
		index = math.floor(index)
		for _, fs in ipairs(floors) do
			fs.patternIdx = index
		end
		publishPattern(index)
	end
end)
applyBrightness()

-- ─────────────────────────────────────────────────────────────────
-- HEARTBEAT FADE
-- ─────────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	local fadeStep = CFG.FADE_SPEED * dt * 60
	-- Dance Floor switch OFF: fade everything to black instead of the idle glow
	local idleDim  = if State.DanceFloorEnabled() then CFG.IDLE_BRIGHTNESS else 0

	for index = #floors, 1, -1 do
		local fs = floors[index]
		if not fs.part.Parent then
			-- the floor was destroyed: forget it
			table.remove(floors, index)
			continue
		end
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
				-- apply to tile, only when the color really changed
				local tile = fs.tiles[r][c]
				if tile and tile.Parent then
					local col = fs.tgtColor[r][c]
					local shown = Color3.new(col.R * b, col.G * b, col.B * b)
					if fs.applied[r][c] ~= shown then
						fs.applied[r][c] = shown
						tile.Color = shown
					end
				end
			end
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────
-- DISCOVER FLOORS
-- ─────────────────────────────────────────────────────────────────
local function registerFloor(child)
	local df = child:FindFirstChild("DF")
	if df and df:IsA("BasePart") then
		local fs = newFloorState(df)
		-- start on a random pattern
		fs.patternIdx = math.random(1, #PATTERNS)
		table.insert(floors, fs)
	end
end

local function discoverFloors()
	-- clear existing
	for _, fs in ipairs(floors) do
		if fs.folder then pcall(function() fs.folder:Destroy() end) end
	end
	table.clear(floors)

	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name:match("^DanceFloorJin") then
			registerFloor(child)
		end
	end
end

discoverFloors()
if floors[1] then
	publishPattern(floors[1].patternIdx)
end

workspace.ChildAdded:Connect(function(child)
	if child.Name:match("^DanceFloorJin") then
		task.wait(0.5)
		registerFloor(child)
	end
end)

-- ─────────────────────────────────────────────────────────────────
-- TELEMETRY RECEIVER
-- ─────────────────────────────────────────────────────────────────
-- One player at a time drives the beat detector. It is the player whose audio actually
-- moves: if the current one has been silent (rms ~ 0, e.g. muted) for a while, any player
-- that does report sound takes over. A sender that goes quiet altogether is dropped
-- after 2 s as before.
local TAKEOVER_AFTER   = 1.5   -- seconds of silence before another sender may take over
local MAX_RMS          = 2000  -- sane upper bound of Sound.PlaybackLoudness
local MAX_EVENTS_PER_S = 40    -- per player (clients send 20/s)

local telLastT       = {}
local telWindow      = {}
local activeTelUID   = nil
local activeTelLastT = -1e9
local activeSoundT   = -1e9

local function rateOk(userId, nowT)
	local w = telWindow[userId]
	if not w or nowT - w.start >= 1 then
		w = { start = nowT, count = 0 }
		telWindow[userId] = w
	end
	w.count += 1
	return w.count <= MAX_EVENTS_PER_S
end

RE_AudioTelemetry.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then return end
	local nowT = os.clock()
	if not rateOk(player.UserId, nowT) then return end

	local rawRms = tonumber(payload.rms)
	if not rawRms or rawRms ~= rawRms or rawRms == math.huge or rawRms == -math.huge then return end
	local rms = math.clamp(rawRms, 0, MAX_RMS)

	if not activeTelUID or (nowT - activeTelLastT) > 2.0 then
		activeTelUID = player.UserId
		activeSoundT = nowT
	elseif player.UserId ~= activeTelUID then
		-- somebody else is the owner; take over only if the owner has gone silent
		if rms > 1 and (nowT - activeSoundT) > TAKEOVER_AFTER then
			activeTelUID = player.UserId
			activeSoundT = nowT
		else
			return
		end
	end
	activeTelLastT = nowT
	if rms > 1 then activeSoundT = nowT end

	local lastT = telLastT[player.UserId] or nowT
	local dt    = math.clamp(nowT - lastT, 0.001, 0.2)
	telLastT[player.UserId] = nowT

	if not floorLive() then return end

	local ev = Beat:StepFromRms(dt, nowT, rms)
	if ev then
		publishBeat(ev)
		for _, fs in ipairs(floors) do
			task.spawn(onBeatForFloor, fs, ev.beatIndex, ev.barIndex)
		end
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	telLastT[player.UserId] = nil
	telWindow[player.UserId] = nil
	if activeTelUID == player.UserId then
		activeTelUID = nil
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
	if age > 2.0 and #floors > 0 and floorLive() then
		local bpm = tonumber(Beat:GetState().bpm) or 120
		local gap = 60 / math.max(1, bpm)
		if (nowT - lastFallbackT) >= gap then
			lastFallbackT = nowT
			local ev = Beat:ForceBeat(nowT)
			if ev then
				publishBeat(ev)
				for _, fs in ipairs(floors) do
					task.spawn(onBeatForFloor, fs, ev.beatIndex, ev.barIndex)
				end
			end
		end
	end
end)

-- DanceFloorSync loaded
