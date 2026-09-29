-- AutoLightsSyncConfig.lua
-- Place in: ServerScriptService > AutoLightsServer  (ModuleScript)
-- ═══════════════════════════════════════════════════════════════════
-- PHANTOM G-LIGHTS  By Jin Development — Config Module
-- Edit freely. All sync scripts read from here.
--
-- Patch notes (PAUL): added DF_PEAK_BRIGHTNESS and the CONTROL block for the
-- AutoLights Control Panel; the DF_* values are now actually used by
-- DanceFloorSync.
-- ═══════════════════════════════════════════════════════════════════

return {

	-- ── AUDIO ──────────────────────────────────────────────────────
	SOUND_PATH      = "SoundService.ServerMusic",
	BEAT_THRESHOLD  = 150,   -- fixed threshold, not adaptive (works at all volumes)
	BEAT_ATTACK     = 0.92,
	BEAT_RELEASE    = 0.20,

	-- ── SHOW STRUCTURE ─────────────────────────────────────────────
	BARS_PER_PRESET        = 8,
	DROP_EVERY_N_BARS      = 4,
	ULTRA_EVERY_N_BARS     = 8,

	-- ── GLIGHT CHAOS ───────────────────────────────────────────────
	BRIGHTNESS             = 1.0,
	BASELINE_BRIGHTNESS    = 1.0,
	STROBE_BRIGHTNESS      = 1.0,
	STAGGER_MAX_S          = 0.05,
	EXTRA_EFFECT_CHANCE    = 0.65,
	BEAM_SNAP_EVERY_N_BEATS= 2,

	-- ── PYRO ───────────────────────────────────────────────────────
	PYRO_AUTO_ARM          = true,
	FPA_EVERY_N_BEATS      = 8,
	FPB_EVERY_N_BEATS      = 12,
	FPC_EVERY_N_BEATS      = 16,
	CO2_EVERY_N_BEATS      = 10,
	SPARK_EVERY_N_BEATS    = 8,
	CONFETTI_EVERY_N_BARS  = 8,
	FIRE_WAVE_ON_BAR       = false,
	CO2_ON_BAR             = false,

	-- ── ATMOSPHERE ─────────────────────────────────────────────────
	HAZE_ON_START          = true,

	-- ── DANCEFLOOR ─────────────────────────────────────────────────
	-- Grid size — how many tiles the DF Part is split into
	DF_GRID_COLS       = 8,      -- tiles across (X axis)
	DF_GRID_ROWS       = 8,      -- tiles deep   (Z axis)
	DF_TILE_GAP        = 0.08,   -- gap between tiles in studs
	DF_TILE_HEIGHT     = 0.15,   -- tile thickness in studs

	-- Beat behaviour (used by DanceFloorSync)
	DF_PEAK_BRIGHTNESS = 1.0,    -- brightness of a flashing tile (0-1)
	DF_IDLE_BRIGHTNESS = 0.06,   -- brightness between beats (0=off, 1=full)
	DF_FADE_SPEED      = 0.12,   -- fade speed per frame at 60 FPS (bigger = faster fade)
	DF_BARS_PER_PATTERN = 4,     -- bars before the floor switches to the next pattern

	-- (DF_COLOR_MODE and DF_FLASH_DURATION are no longer used: the floor runs its
	--  12 patterns automatically, and DF_FADE_SPEED sets how long a flash lasts.)

	-- ── CONTROL PANEL ──────────────────────────────────────────────
	-- Who may use the AutoLights Control Panel (Sync on/off, Blackout, ...).
	-- The game owner is always allowed. In Roblox Studio everyone is allowed.
	CONTROL = {
		PublicAccess = false, -- true = EVERY player can use the panel (not recommended)
		UserIds      = {},    -- extra UserIds allowed, e.g. { 123456789 }
		GroupId      = 0,     -- (optional) group whose members may use the panel
		MinRank      = 1,     -- rank needed in GroupId

		SyncOnAtStart      = true,
		DanceFloorOnAtStart = true,
		PyroOnAtStart      = true,
		Watermark          = "PAUL", -- text on the panel
	},
}
