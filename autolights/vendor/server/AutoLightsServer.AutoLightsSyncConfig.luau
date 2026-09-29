-- AutoLightsSyncConfig.lua
-- Place in: ServerScriptService > AutoLightsServer  (ModuleScript)
-- ═══════════════════════════════════════════════════════════════════
-- PHANTOM G-LIGHTS  By Jin Development — Config Module
-- Edit freely. All sync scripts read from here.
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

	-- Beat behaviour
	DF_FLASH_DURATION  = 0.10,   -- seconds tile stays at full brightness
	DF_FADE_SPEED      = 0.12,   -- fade speed per heartbeat step
	DF_IDLE_BRIGHTNESS = 0.06,   -- brightness between beats (0=off, 1=full)

	-- Color mode for the dancefloor tiles:
	--   "WAVE"     = color ripples outward from center on every beat  ← recommended
	--   "RANDOM"   = every tile picks a totally random color per beat
	--   "CHECKERS" = two alternating colors, swap every beat
	--   "RAINBOW"  = hue gradient across columns, shifts each beat
	DF_COLOR_MODE      = "WAVE",
}