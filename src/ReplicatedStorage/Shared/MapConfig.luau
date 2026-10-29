--[[
	MapConfig — where everything on the map is. Shared so the client can
	build decorations around the same layout the server builds.

	Layout (studs, seen from above): the beach is at -Z and the sea goes
	towards +Z. The seabed is flat at y = SEABED_Y and the water surface is
	at y = WATER_LEVEL. The cove is closed by rock cliffs on three sides.
]]

local MapConfig = {}

MapConfig.SEABED_Y = 0
MapConfig.WATER_LEVEL = 48
MapConfig.BEACH_Y = 56

-- the whole cove, x and z ranges
MapConfig.MIN_X = -200
MapConfig.MAX_X = 200
MapConfig.BEACH_BACK_Z = -170 -- back edge of the beach
MapConfig.BEACH_EDGE_Z = -80 -- where the slope starts going down
MapConfig.SLOPE_FOOT_Z = 10 -- where the slope meets the seabed
MapConfig.MAX_Z = 320 -- back cliff

MapConfig.SPAWN = Vector3.new(0, 56, -130)

-- 8 seats around each ring
MapConfig.SEATS = 8
MapConfig.RING_RADIUS = 13 -- centre to the middle of each chair
MapConfig.RING_CLEAR = 24 -- keep decorations at least this far from a ring centre

MapConfig.RINGS = {
	{ name = "Ring1", x = -105, z = 70, ranked = false },
	{ name = "Ring2", x = -35, z = 55, ranked = false },
	{ name = "Ring3", x = 35, z = 55, ranked = false },
	{ name = "Ring4", x = 105, z = 70, ranked = false },
	{ name = "RankedRing1", x = -60, z = 175, ranked = true },
	{ name = "RankedRing2", x = 60, z = 175, ranked = true },
}

function MapConfig.ringCentre(ring): Vector3
	return Vector3.new(ring.x, MapConfig.SEABED_Y, ring.z)
end

-- true when a point on the seabed is clear of every ring
function MapConfig.clearOfRings(x: number, z: number, extra: number?): boolean
	local r = MapConfig.RING_CLEAR + (extra or 0)
	for _, ring in MapConfig.RINGS do
		local dx, dz = x - ring.x, z - ring.z
		if dx * dx + dz * dz < r * r then
			return false
		end
	end
	return true
end

-- the open, flat seabed where life can go (inside the cliffs, past the slope)
MapConfig.SEABED_AREA = {
	minX = -175,
	maxX = 175,
	minZ = 20,
	maxZ = 295,
}

-- true when a world position is inside the sea (used for underwater effects)
function MapConfig.isUnderwater(p: Vector3): boolean
	if p.Y > MapConfig.WATER_LEVEL then
		return false
	end
	if p.X < MapConfig.MIN_X or p.X > MapConfig.MAX_X or p.Z > MapConfig.MAX_Z then
		return false
	end
	-- over the slope, the water only starts where the sand is under the surface
	return p.Z > MapConfig.BEACH_EDGE_Z
end

return MapConfig
