--[[
	Tests the map layout (MapConfig) and the ring sign text (RingSign)
	outside Roblox.

	Run from the repo root:
		lune run tests/run_map.luau

	Exits with code 1 if any check fails.
]]

local process = require("@lune/process")
local Shim = require("./shim")

local sharedFolder = Shim.folder("src/ReplicatedStorage/Shared")
local MapConfig = Shim.require(sharedFolder.MapConfig)
local RingSign = Shim.require(sharedFolder.RingSign)
local Vector3 = require("@lune/roblox").Vector3

local passed, failed = 0, 0

local function expect(label: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
		print("  ok    " .. label)
	else
		failed += 1
		print("  FAIL  " .. label .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

print("ring sign text")
expect("open, nobody seated", RingSign.text("waiting", 0, 8, nil, 100) == "Open 0/8")
expect("open, 3 seated", RingSign.text("waiting", 3, 8, nil, 100) == "Open 3/8")
expect("no phase yet counts as open", RingSign.text(nil, nil, 8, nil, 100) == "Open 0/8")
expect("starting, 8 s left", RingSign.text("countdown", 3, 8, 108, 100) == "Starting 0:08", RingSign.text("countdown", 3, 8, 108, 100))
expect("starting rounds up part seconds", RingSign.text("countdown", 3, 8, 107.2, 100) == "Starting 0:08")
expect("starting, 15 s", RingSign.text("countdown", 2, 8, 115, 100) == "Starting 0:15")
expect("starting never goes negative", RingSign.text("countdown", 2, 8, 90, 100) == "Starting 0:00")
expect("over a minute", RingSign.clock(75) == "1:15")
for _, phase in { "playing", "picking", "between", "results" } do
	expect("in game while " .. phase, RingSign.text(phase, 5, 8, 120, 100) == "In game")
end
expect("state open", RingSign.state("waiting") == "open")
expect("state starting", RingSign.state("countdown") == "starting")
expect("state playing", RingSign.state("results") == "playing")

print("map layout")
local casual, ranked = 0, 0
local names = {}
for _, ring in MapConfig.RINGS do
	if ring.ranked then
		ranked += 1
	else
		casual += 1
	end
	expect(ring.name .. " has a unique name", names[ring.name] == nil)
	names[ring.name] = true
	local area = MapConfig.SEABED_AREA
	local reach = MapConfig.RING_RADIUS + 6 -- chairs and trim
	expect(
		ring.name .. " fits on the open seabed",
		ring.x - reach >= area.minX and ring.x + reach <= area.maxX and ring.z - reach >= area.minZ and ring.z + reach <= area.maxZ
	)
	expect(ring.name .. " centre is clear of decorations", not MapConfig.clearOfRings(ring.x, ring.z))
	local c = MapConfig.ringCentre(ring)
	expect(ring.name .. " sits on the seabed, under water", c.Y == MapConfig.SEABED_Y and MapConfig.isUnderwater(c + Vector3.new(0, 5, 0)))
end
expect("4 casual rings", casual == 4, casual)
expect("2 ranked rings", ranked == 2, ranked)

local closest = math.huge
for i, a in MapConfig.RINGS do
	for j, b in MapConfig.RINGS do
		if i < j then
			closest = math.min(closest, math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2))
		end
	end
end
-- two rings' chairs (radius 13 + 4) plus room to walk between them
expect("rings are at least 50 studs apart", closest >= 50, closest)

expect("spawn is on the beach, above water", not MapConfig.isUnderwater(MapConfig.SPAWN) and MapConfig.SPAWN.Y >= MapConfig.WATER_LEVEL)
expect("spawn is on the beach plateau", MapConfig.SPAWN.Z < MapConfig.BEACH_EDGE_Z and MapConfig.SPAWN.Z > MapConfig.BEACH_BACK_Z)
expect("above the surface is not underwater", not MapConfig.isUnderwater(Vector3.new(0, MapConfig.WATER_LEVEL + 1, 100)))
expect("deep in the cove is underwater", MapConfig.isUnderwater(Vector3.new(0, 10, 150)))
expect("outside the cliffs is not underwater", not MapConfig.isUnderwater(Vector3.new(MapConfig.MAX_X + 20, 10, 150)))

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
