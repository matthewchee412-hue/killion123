--[[
	Build — small helpers for the client-only seabed decorations.

	Every decoration part is anchored, can't be collided with, touched or
	raycast, and casts no shadow, so it costs as little as possible.

	A "rig" is a group of parts that move together (a crab, a fish). Each
	part has an offset from the rig's root, and Build.pose writes the parts'
	CFrames into one batch so a single workspace:BulkMoveTo moves everything.
]]

local Build = {}

function Build.part(props, parent: Instance?): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- an ellipsoid of the given size
function Build.blob(props, parent: Instance?): BasePart
	local p = Build.part(props, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- a cylinder standing upright (Roblox cylinders lie along X)
function Build.upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

export type Rig = {
	parts: { BasePart },
	offsets: { CFrame },
	root: CFrame,
}

function Build.rig(): Rig
	return { parts = {}, offsets = {}, root = CFrame.identity }
end

-- add a part to a rig; `offset` is relative to the rig's root
function Build.add(rig: Rig, part: BasePart, offset: CFrame): number
	table.insert(rig.parts, part)
	table.insert(rig.offsets, offset)
	part.CFrame = rig.root * offset
	return #rig.parts
end

-- queue a rig's parts for BulkMoveTo. `extra[i]`, if given, is applied
-- after part i's offset (for flapping fins, waving legs).
function Build.pose(rig: Rig, root: CFrame, parts: { BasePart }, cfs: { CFrame }, extra: { [number]: CFrame }?)
	rig.root = root
	for i, part in rig.parts do
		local cf = root * rig.offsets[i]
		if extra and extra[i] then
			cf *= extra[i]
		end
		table.insert(parts, part)
		table.insert(cfs, cf)
	end
end

-- a random point on the open seabed that's clear of the rings
function Build.seabedPoint(rng: Random, MapConfig, extra: number?): Vector3
	local area = MapConfig.SEABED_AREA
	for _ = 1, 40 do
		local x = rng:NextNumber(area.minX, area.maxX)
		local z = rng:NextNumber(area.minZ, area.maxZ)
		if MapConfig.clearOfRings(x, z, extra) then
			return Vector3.new(x, MapConfig.SEABED_Y, z)
		end
	end
	return Vector3.new(0, MapConfig.SEABED_Y, (area.minZ + area.maxZ) / 2)
end

return Build
