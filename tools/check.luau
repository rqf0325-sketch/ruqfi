--[[
	Compiles every script inside the generated model files with the Luau
	compiler, so a syntax error in any of them fails the build.

	  lune run tools/check.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local FILES = {
	"StarterGui/VehicleSpawnerGui.rbxmx",
	"ReplicatedStorage/VehicleSpawner.rbxmx",
	"ServerScriptService/VehicleSpawnerServer.rbxmx",
	"ServerStorage/Vehicles.rbxm",
	"StarterGui/PlayerMenuGui.rbxmx",
	"ReplicatedStorage/PlayerMenu.rbxmx",
	"ServerScriptService/PlayerMenuServer.rbxmx",
}

local checked, failed = 0, 0
for _, file in FILES do
	if not fs.isFile(file) then
		print(`skip {file} (not built)`)
		continue
	end
	for _, root in roblox.deserializeModel(fs.readFile(file)) do
		local all = root:GetDescendants()
		table.insert(all, root)
		for _, inst in all do
			if inst:IsA("LuaSourceContainer") then
				checked += 1
				local ok, err = pcall(luau.compile, inst.Source)
				if not ok then
					failed += 1
					print(`FAIL {file}: {inst:GetFullName()}\n  {err}`)
				end
			end
		end
	end
end

print(`{checked} scripts compiled, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
