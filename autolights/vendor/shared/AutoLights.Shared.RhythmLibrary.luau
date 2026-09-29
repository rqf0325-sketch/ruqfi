-- ReplicatedStorage/AutoLights/Shared/RhythmLibrary.lua
local Palette = require(script.Parent.Palette)

local function GL(folder, fn, args, selector)
	return { type="gl", folder=folder, fn=fn, args=args or {}, selector=selector }
end

local function SYS(fn, args)
	return { type="sys", fn=fn, args=args or {} }
end

local function SET(key, value)
	return { type="set", key=key, value=value }
end

local function INC(key, delta)
	return { type="inc", key=key, delta=delta or 1 }
end

local function TOGGLE(key)
	return { type="toggle", key=key }
end

local function BRANCH(key, ifTrue, ifFalse)
	return { type="branch", key=key, ifTrue=ifTrue or {}, ifFalse=ifFalse or {} }
end

local function PY(device, pattern, args, gate)
	return { type="pyro", device=device, pattern=pattern, args=args or {}, requireArmed=true, gate=gate or {} }
end

-- Helpers
local function ColorAllStep(color)
	return { GL("ALL","Color",{color}) }
end

local function FULL_BRIGHT_ALL()
	return {
		GL("ALL","On",{}),
		GL("ALL","Dimness",{1.0}),
		GL("Heads","Dimness",{1.0}),
		GL("Washes","Dimness",{1.0}),
		GL("Strobes","Dimness",{1.0}),
		GL("LineBars","Dimness",{1.0}),
		GL("LEDBars","Dimness",{1.0}),
	}
end

-- =========================================================
-- LOGIC WARNA 6-STEP (Sama persis urutan Custom Circle)
-- Cyan, Magenta, Lime, Amber, White, Nebula Purple
-- =========================================================
local function COLOR_SEQ_6_CUSTOM()
	return {
		TOGGLE("b1"),
		BRANCH("b1", {}, { TOGGLE("b2"), BRANCH("b2", {}, { TOGGLE("b3") }) }),

		-- Mapping 3-bit ke 6 Warna
		BRANCH("b3",
			{ -- b3 = True (4, 5...)
				BRANCH("b1",
					{ GL("ALL","Color",{Palette.NEBULA_PURPLE}) }, -- 5
					{ GL("ALL","Color",{Palette.WARM_WHITE}) }     -- 4
				)
			},
			{ -- b3 = False (0, 1, 2, 3)
				BRANCH("b2",
					{ -- b2 = True (2, 3)
						BRANCH("b1",
							{ GL("ALL","Color",{Palette.AMBER}) }, -- 3
							{ GL("ALL","Color",{Palette.LIME}) }   -- 2
						)
					},
					{ -- b2 = False (0, 1)
						BRANCH("b1",
							{ GL("ALL","Color",{Palette.MAGENTA}) }, -- 1
							{ GL("ALL","Color",{Palette.CYAN}) }     -- 0
						)
					}
				)
			}
		)
	}
end

local function INIT_COLOR_SEQ()
	return {
		SET("b1", false),
		SET("b2", false),
		SET("b3", false),
	}
end

-- =========================================================
-- PRESETS LIST
-- =========================================================

local Presets = {

	-- 1) TECH_TOGGLE
	{
		id="RHY_TECH_TOGGLE",
		name="RHY_TECH_TOGGLE",
		intensity="High",
		pyroPolicy={allowFPA=true, allowConfetti=false},
		onEnter={
			SYS("CleanupPreset"),
			table.unpack(FULL_BRIGHT_ALL()),
			GL("Heads","Position.Circle",{true}),
			GL("Strobes","Position.Circle",{true}),
			GL("Heads","BeamMode",{"Beam"}),
			GL("Heads","BeamThickness",{0.1}),
			GL("Heads","SmoothColor",{false}),
			SET("toggle", false),
		},
		onBeat={
			TOGGLE("toggle"),
			BRANCH("toggle", ColorAllStep(Palette.NEON_CYAN), ColorAllStep(Palette.NEON_MAGENTA)),
			BRANCH("toggle",
				{ GL("Heads","MotorSpeed",{0.045}), GL("Heads","GoboSpread",{0.2}) },
				{ GL("Heads","MotorSpeed",{0.025}), GL("Heads","GoboSpread",{0.8}) }
			),
			PY("FPA","AllHold",{duration=0.10},{levelAtLeast="High", everyNBeats=2}),
		},
		onExit={
			GL("Heads","Position.Circle",{false}),
			GL("Strobes","Position.Circle",{false}),
			GL("ALL","FadeOff",{}),
			SYS("CleanupPreset"),
		},
	},

	-- 2) BASS_SLAM
	{
		id="RHY_BASS_SLAM",
		name="RHY_BASS_SLAM",
		intensity="High",
		pyroPolicy={allowFPA=true, allowConfetti=false},
		onEnter={
			SYS("CleanupPreset"),
			table.unpack(FULL_BRIGHT_ALL()),
			GL("Heads","Position.Circle",{true}),
			GL("Heads","BeamMode",{"Beam"}),
			GL("Heads","BeamThickness",{0.1}),
			SET("slam", false),
		},
		onBeat={
			TOGGLE("slam"),
			BRANCH("slam",
				{ GL("Heads","CustomPositions.UD",{true}), GL("ALL","Color",{Palette.CYAN}), GL("Heads","MotorSpeed",{0.05}) },
				{ GL("Heads","CustomPositions.UD",{false}), GL("ALL","Color",{Palette.MAGENTA}), GL("Heads","MotorSpeed",{0.02}) }
			),
			PY("FPA","CenterPunch",{duration=0.10},{levelAtLeast="High", everyNBeats=1}),
		},
		onExit={
			GL("Heads","Position.Circle",{false}),
			GL("Heads","CustomPositions.UD",{false}),
			GL("ALL","FadeOff",{}),
			SYS("CleanupPreset"),
		},
	},

	-- 3) GOBO_STEP
	{
		id="RHY_GOBO_STEP",
		name="RHY_GOBO_STEP",
		intensity="High",
		pyroPolicy={allowFPA=true, allowConfetti=false},
		onEnter={
			SYS("CleanupPreset"),
			table.unpack(FULL_BRIGHT_ALL()),
			GL("Heads","Position.Circle",{true}),
			GL("Heads","BeamMode",{"Gobo"}),
			GL("Heads","RotateGobo",{1}),
			SET("mode", false),
		},
		onBeat={
			TOGGLE("mode"),
			BRANCH("mode",
				{ GL("Heads","GoboSpread",{0.55}), GL("ALL","Color",{Palette.WARM_WHITE}), GL("Heads","MotorSpeed",{0.03}) },
				{ GL("Heads","GoboSpread",{0.2}), GL("ALL","Color",{Palette.TEAL}), GL("Heads","MotorSpeed",{0.04}) }
			),
			PY("FPA","WaveL2R",{interval=0.08},{levelAtLeast="High", everyNBeats=2}),
		},
		onExit={
			GL("Heads","Position.Circle",{false}),
			GL("Heads","RotateGobo",{0}),
			GL("ALL","FadeOff",{}),
			SYS("CleanupPreset"),
		},
	},

	-- 4) NEON_RIPPLE
	{
		id="RHY_NEON_RIPPLE",
		name="RHY_NEON_RIPPLE",
		intensity="Medium",
		pyroPolicy={allowFPA=false, allowConfetti=true},
		onEnter={
			SYS("CleanupPreset"),
			table.unpack(FULL_BRIGHT_ALL()),
			GL("Heads","Position.Circle",{true}),
			GL("Heads","MotorSpeed",{0.035}),
			SET("rIndex", 1),
			SET("rDir", 1),
		},
		onBeat={
			{ type="neonRippleLEDs", colors={Palette.NEON_CYAN, Palette.NEON_MAGENTA, Palette.LIME, Palette.AMBER} },
			GL("Heads","MotorSpeed",{0.045}), 
		},
		onBar={
			PY("CONFETTI","Burst",{duration=1.00},{levelAtLeast="Insane", everyNBars=2}),
		},
		onExit={
			GL("Heads","Position.Circle",{false}),
			GL("ALL","FadeOff",{}),
			SYS("CleanupPreset"),
		},
	},

	-- 5) CIRCLE ACCEL CUSTOM (UPDATED - Motor Speed dinamis per beat)
	{
		id="RHY_CIRCLE_ACCEL_CUSTOM",
		name="RHY_CIRCLE_ACCEL_CUSTOM",
		intensity="High",
		pyroPolicy={allowFPA=true, allowConfetti=false},
		onEnter={
			SYS("CleanupPreset"),
			table.unpack(FULL_BRIGHT_ALL()),
			GL("Heads","Position.Circle",{true}), 
			GL("Heads","BeamMode",{"Gobo"}),
			GL("Heads","RotateGobo",{1}),
			GL("Heads","SmoothColor",{false}),
			SET("beat", 0),
			SET("speedIndex", 1),
			SET("spreadIndex", 1),
			SET("colorIndex", 1),
			SET("speedSeq", {0.006, 0.010, 0.016, 0.024, 0.032, 0.045}),
			SET("spreadSeq",{0.12, 0.20, 0.35, 0.50, 0.65, 0.80}),
			SET("colorSeq", {Palette.CYAN, Palette.MAGENTA, Palette.LIME, Palette.AMBER, Palette.WARM_WHITE, Palette.NEBULA_PURPLE}),
			-- Speed idle default
			GL("Heads","MotorSpeed",{0.006}),
		},
		onBeat={
			INC("beat", 1),
			{ type="circleAccelGoboHeads" },
			-- Speed naik tinggi pas beat, lalu turun ke idle
			SYS("Delay", {0.12, { type="circleAccelIdleSpeed" }}),
			PY("FPA","AllHold",{duration=0.10},{levelAtLeast="High", everyNBeats=8}),
		},
		onBar={
			SET("speedIndex", 1),
			SET("spreadIndex", 1),
			SET("colorIndex", 1),
		},
		onExit={
			GL("Heads","Position.Circle",{false}),
			GL("Heads","RotateGobo",{0}),
			GL("ALL","FadeOff",{}),
			SYS("CleanupPreset"),
		},
	},

	-- 6) RHY_CHAOS_ULTIMATE (UPDATED - Full Brightness + Strobe semua lights kecuali Heads & Washes)
	{
		id="RHY_CHAOS_ULTIMATE",
		name="RHY_CHAOS_ULTIMATE",
		intensity="Insane",
		pyroPolicy={allowFPA=true, allowConfetti=true, allowSmoke=true},
		onEnter={
			SYS("CleanupPreset"),
			table.unpack(FULL_BRIGHT_ALL()),

			GL("ALL","SmoothColor",{false}),

			-- MOVEMENT: RandomCircle ON (gerak random terus)
			GL("Heads","Position.RandomCircle",{true}),

			-- VISUAL: Laser Mode
			GL("Heads","BeamMode",{"Beam"}),
			GL("Heads","BeamThickness",{0.1}),
			--GL("ALL","SetGlobalCueSetting", "GroupRandom", {true}),

			-- COLOR SYSTEM: sama persis seperti RHY_CIRCLE_ACCEL_CUSTOM
			SET("beat", 0),
			SET("speedIndex", 1),
			SET("spreadIndex", 1),
			SET("colorIndex", 1),
			SET("speedSeq", {0.006, 0.010, 0.016, 0.024, 0.032, 0.045}),
			SET("spreadSeq",{0.12, 0.20, 0.35, 0.50, 0.65, 0.80}),
			SET("colorSeq", {Palette.CYAN, Palette.MAGENTA, Palette.LIME, Palette.AMBER, Palette.WARM_WHITE, Palette.NEBULA_PURPLE}),

			-- SPEED: idle default (lambat)
			GL("Heads","MotorSpeed",{0.006}),

			-- BRIGHTNESS: FULL DIMNESS untuk semua!
			GL("Strobes","Dimness",{1.0}),
			GL("LineBars","Dimness",{1.0}),
			GL("LEDBars","Dimness",{1.0}),
			GL("Heads","Dimness",{1.0}),
			GL("Washes","Dimness",{1.0}),
		},
		onBeat={
			INC("beat", 1),
			-- COLOR & SPEED: sama persis sistem RHY_CIRCLE_ACCEL_CUSTOM
			{ type="circleAccelGoboHeads" },

			-- Speed naik tinggi pas beat, lalu turun ke idle
			SYS("Delay", {0.12, { type="circleAccelIdleSpeed" }}),

			-- STROBE EFFECT: Flash untuk Strobes, LineBars, LEDBars (Heads & Washes tetap nyala normal)
			GL("Strobes","Action",{"Flash"}),
			GL("LineBars","Action",{"Flash"}),
			GL("LEDBars","Action",{"Flash"}),

			PY("SMOKE","Burst",{duration=0.2},{levelAtLeast="High", everyNBeats=4}),
		},
		onBar={
			-- Reset cycle tiap bar (sama seperti RHY_CIRCLE_ACCEL_CUSTOM)
			SET("speedIndex", 1),
			SET("spreadIndex", 1),
			SET("colorIndex", 1),
		},
		onExit={
			--GL("ALL","SetGlobalCueSetting", "GroupRandom", {false}),
			GL("Heads","Position.RandomCircle",{false}),
			GL("ALL","FadeOff",{}),
			SYS("CleanupPreset"),
		},
	},
}

local indexById = {}
for _,p in ipairs(Presets) do
	indexById[p.id] = p
end

return {
	list = Presets,
	byId = indexById,
}