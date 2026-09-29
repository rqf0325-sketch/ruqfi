-- ReplicatedStorage/AutoLights/Shared/PresetLibrary.lua
local Palette = require(script.Parent.Palette)

-- NOTE:
-- Preset cinematic dibuat “simple”:
-- - 1 warna saja (p.color) dipakai untuk Heads/Washes/Bars/LEDs/LineBars/Extras
-- - Tidak pakai ColorSequence supaya washes/linebars tidak bug
-- - BeamThickness default 0 (laser feel)

local function SetupBase(color)
	return {
		{ type="sys", fn="CleanupPreset" },
		-- baseline ON semua (strobes ikut ON tapi dimness kecil)
		{ type="sys", fn="EnsureAllOnBaseline", args={color} },

		{ type="gl", folder="Heads", fn="Dimness", args={0.55} },
		{ type="gl", folder="Washes", fn="Dimness", args={0.45} },
		{ type="gl", folder="Bars", fn="Dimness", args={0.30} },
		{ type="gl", folder="LEDs", fn="Dimness", args={0.25} },
		{ type="gl", folder="LineBars", fn="Dimness", args={0.25} },

		-- laser feel: thickness 0
		{ type="gl", folder="Heads", fn="BeamMode", args={"Beam"} },
		{ type="gl", folder="Heads", fn="BeamThickness", args={0.0} },

		-- warna 1 saja untuk semua
		{ type="gl", folder="ALL", fn="Color", args={color} },
	}
end

local Presets = {
	{
		id="CINE_NEON_WASH",
		name="CINE_NEON_WASH",
		color=Palette.NEON_CYAN,
		phases = {
			setup = SetupBase(Palette.NEON_CYAN),
			intro = {
				{ type="gl", folder="ALL", fn="FadeOn", args={} },
				{ type="wait", seconds=2.5 },
			},
			loop = {
				A = {
					{ type="gl", folder="Heads", fn="Position.SmoothPan", args={true} },
					{ type="wait", seconds=10.0 },
				},
				B = {
					{ type="gl", folder="Heads", fn="Position.SmoothPan", args={false} },
					{ type="gl", folder="Heads", fn="Position.SlowTilt", args={true} },
					{ type="wait", seconds=10.0 },
				},
				C = {
					{ type="gl", folder="Heads", fn="Position.SlowTilt", args={false} },
					{ type="gl", folder="Heads", fn="CustomPositions.Wide", args={true} },
					{ type="wait", seconds=12.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.Wide", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
	},

	{
		id="CINE_AMBER_HALL",
		name="CINE_AMBER_HALL",
		color=Palette.AMBER,
		phases = {
			setup = SetupBase(Palette.AMBER),
			intro = {
				{ type="gl", folder="Heads", fn="BeamMode", args={"Gobo"} },
				{ type="gl", folder="Heads", fn="GoboSpread", args={0.25} },
				{ type="gl", folder="Heads", fn="RotateGobo", args={1} },
				{ type="wait", seconds=4.0 },
			},
			loop = {
				A = {
					{ type="gl", folder="Heads", fn="GoboSpread", args={0.15} },
					{ type="wait", seconds=6.0 },
					{ type="gl", folder="Heads", fn="GoboSpread", args={0.45} },
					{ type="wait", seconds=6.0 },
				},
				B = {
					{ type="gl", folder="Heads", fn="RotateGobo", args={-1} },
					{ type="wait", seconds=8.0 },
					{ type="gl", folder="Heads", fn="RotateGobo", args={0} },
					{ type="wait", seconds=8.0 },
				},
				C = {
					{ type="gl", folder="Heads", fn="CustomPositions.Cross", args={true} },
					{ type="wait", seconds=12.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.Cross", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="Heads", fn="RotateGobo", args={0} },
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
	},

	{
		id="CINE_ICE_BREATH",
		name="CINE_ICE_BREATH",
		color=Palette.ICE_BLUE,
		phases = {
			setup = SetupBase(Palette.ICE_BLUE),
			intro = {
				{ type="gl", folder="Washes", fn="FadeOn", args={} },
				{ type="wait", seconds=3.0 },
			},
			loop = {
				A = {
					{ type="gl", folder="Heads", fn="Position.Circle", args={true} },
					{ type="gl", folder="Heads", fn="MotorSpeed", args={0.006} },
					{ type="wait", seconds=14.0 },
				},
				B = {
					{ type="gl", folder="Heads", fn="Position.Circle", args={false} },
					{ type="gl", folder="Heads", fn="Position.RandomPan", args={true} },
					{ type="wait", seconds=14.0 },
					{ type="gl", folder="Heads", fn="Position.RandomPan", args={false} },
				},
				C = {
					{ type="gl", folder="Heads", fn="CustomPositions.UD", args={true} },
					{ type="wait", seconds=12.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.UD", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="Heads", fn="Position.Circle", args={false} },
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
	},

	{
		id="CINE_PURPLE_DRIFT",
		name="CINE_PURPLE_DRIFT",
		color=Palette.NEBULA_PURPLE,
		phases = {
			setup = SetupBase(Palette.NEBULA_PURPLE),
			intro = {
				{ type="gl", folder="Heads", fn="Position.SmoothTilt", args={true} },
				{ type="wait", seconds=3.0 },
			},
			loop = {
				A = {
					--{ type="gl", folder="Heads", fn="SetGlobalCueSetting", args={"GroupRandom", true} },
					--{ type="wait", seconds=10.0 },
					--{ type="gl", folder="Heads", fn="SetGlobalCueSetting", args={"GroupRandom", false} },
				},
				B = {
					{ type="gl", folder="Heads", fn="Position.SmoothTilt", args={false} },
					{ type="gl", folder="Heads", fn="Position.SmoothPan", args={true} },
					{ type="wait", seconds=14.0 },
				},
				C = {
					{ type="gl", folder="Heads", fn="Position.SmoothPan", args={false} },
					{ type="gl", folder="Heads", fn="CustomPositions.In", args={true} },
					{ type="wait", seconds=12.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.In", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="Heads", fn="Position.SmoothPan", args={false} },
				{ type="gl", folder="Heads", fn="Position.SmoothTilt", args={false} },
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
	},

	{
		id="CINE_TEAL_LINES",
		name="CINE_TEAL_LINES",
		color=Palette.TEAL,
		phases = {
			setup = SetupBase(Palette.TEAL),
			intro = {
				{ type="gl", folder="LineBars", fn="FadeOn", args={} },
				{ type="wait", seconds=3.0 },
			},
			loop = {
				A = {
					{ type="gl", folder="Heads", fn="CustomPositions.Wide", args={true} },
					{ type="wait", seconds=10.0 },
				},
				B = {
					{ type="gl", folder="Heads", fn="CustomPositions.Wide", args={false} },
					{ type="gl", folder="Heads", fn="CustomPositions.Cross", args={true} },
					{ type="wait", seconds=10.0 },
				},
				C = {
					{ type="gl", folder="Heads", fn="CustomPositions.Cross", args={false} },
					{ type="gl", folder="Heads", fn="CustomPositions.UD", args={true} },
					{ type="wait", seconds=10.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.UD", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
	},

	-- Tambahan 5 cinematic lagi (biar total 10)
	{
		id="CINE_WHITE_LASER",
		name="CINE_WHITE_LASER",
		color=Palette.WARM_WHITE,
		phases = {
			setup = SetupBase(Palette.WARM_WHITE),
			intro = {
				{ type="gl", folder="Heads", fn="Dimness", args={0.75} },
				{ type="gl", folder="Heads", fn="BeamThickness", args={0.0} },
				{ type="wait", seconds=2.0 },
			},
			loop = {
				A = {
					{ type="gl", folder="Heads", fn="Position.RandomPan", args={true} },
					{ type="wait", seconds=12.0 },
				},
				B = {
					{ type="gl", folder="Heads", fn="Position.RandomPan", args={false} },
					{ type="gl", folder="Heads", fn="Position.RandomCircle", args={true} },
					{ type="wait", seconds=12.0 },
					{ type="gl", folder="Heads", fn="Position.RandomCircle", args={false} },
				},
				C = {
					{ type="gl", folder="Heads", fn="CustomPositions.In", args={true} },
					{ type="wait", seconds=10.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.In", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="Heads", fn="Position.RandomPan", args={false} },
				{ type="gl", folder="Heads", fn="Position.RandomCircle", args={false} },
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
	},

	{
		id="CINE_RED_ALERT",
		name="CINE_RED_ALERT",
		color=Palette.RED,
		phases = {
			setup = SetupBase(Palette.RED),
			intro = {
				{ type="gl", folder="Strobes", fn="Dimness", args={0.18} }, -- ikut nyala, tidak flash
				{ type="wait", seconds=3.0 },
			},
			loop = {
				A = {
					{ type="gl", folder="Heads", fn="CustomPositions.Cross", args={true} },
					{ type="wait", seconds=8.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.Cross", args={false} },
				},
				B = {
					{ type="gl", folder="Heads", fn="CustomPositions.UD", args={true} },
					{ type="wait", seconds=8.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.UD", args={false} },
				},
				C = {
					{ type="gl", folder="Heads", fn="Position.SlowPan", args={true} },
					{ type="wait", seconds=10.0 },
					{ type="gl", folder="Heads", fn="Position.SlowPan", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
	},

	{
		id="CINE_LIME_RIDE",
		name="CINE_LIME_RIDE",
		color=Palette.LIME,
		phases = {
			setup = SetupBase(Palette.LIME),
			intro = {
				{ type="gl", folder="Heads", fn="MotorSpeed", args={0.008} },
				{ type="wait", seconds=2.0 },
			},
			loop = {
				A = {
					{ type="gl", folder="Heads", fn="Position.Circle", args={true} },
					{ type="wait", seconds=12.0 },
				},
				B = {
					{ type="gl", folder="Heads", fn="Position.Circle", args={false} },
					{ type="gl", folder="Heads", fn="Position.SmoothTilt", args={true} },
					{ type="wait", seconds=12.0 },
					{ type="gl", folder="Heads", fn="Position.SmoothTilt", args={false} },
				},
				C = {
					{ type="gl", folder="Heads", fn="Position.SmoothPan", args={true} },
					{ type="wait", seconds=12.0 },
					{ type="gl", folder="Heads", fn="Position.SmoothPan", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="Heads", fn="Position.Circle", args={false} },
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
	},

	{
		id="CINE_MAGENTA_GLOW",
		name="CINE_MAGENTA_GLOW",
		color=Palette.MAGENTA,
		phases = {
			setup = SetupBase(Palette.MAGENTA),
			intro = {
				{ type="gl", folder="Bars", fn="Dimness", args={0.40} },
				{ type="wait", seconds=2.0 },
			},
			loop = {
				A = {
					{ type="gl", folder="Heads", fn="CustomPositions.Wide", args={true} },
					{ type="wait", seconds=14.0 },
				},
				B = {
					{ type="gl", folder="Heads", fn="CustomPositions.Wide", args={false} },
					{ type="gl", folder="Heads", fn="CustomPositions.In", args={true} },
					{ type="wait", seconds=14.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.In", args={false} },
				},
				C = {
					{ type="gl", folder="Heads", fn="Position.RandomCircle", args={true} },
					{ type="wait", seconds=14.0 },
					{ type="gl", folder="Heads", fn="Position.RandomCircle", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
	},

	{
		id="CINE_BLUE_OCEAN",
		name="CINE_BLUE_OCEAN",
		color=Palette.BLUE,
		phases = {
			setup = SetupBase(Palette.BLUE),
			intro = {
				{ type="wait", seconds=2.0 },
			},
			loop = {
				A = {
					{ type="gl", folder="Heads", fn="Position.SlowPan", args={true} },
					{ type="wait", seconds=16.0 },
					{ type="gl", folder="Heads", fn="Position.SlowPan", args={false} },
				},
				B = {
					{ type="gl", folder="Heads", fn="Position.SlowTilt", args={true} },
					{ type="wait", seconds=16.0 },
					{ type="gl", folder="Heads", fn="Position.SlowTilt", args={false} },
				},
				C = {
					{ type="gl", folder="Heads", fn="CustomPositions.UD", args={true} },
					{ type="wait", seconds=14.0 },
					{ type="gl", folder="Heads", fn="CustomPositions.UD", args={false} },
				},
			},
			outro = {
				{ type="gl", folder="ALL", fn="FadeOff", args={} },
				{ type="wait", seconds=4.0 },
				{ type="sys", fn="CleanupPreset" },
			}
		}
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
