--[[
	Swimmers — things that swim across the cove on loops, on this client:
	schools of fish, a sea turtle, a manta ray and jellyfish.

	Each swimmer follows a slow oval loop with a gentle up-and-down wave and
	always faces the way it's going. Fins, tails and tentacles animate.
	Loops that are far from the camera still move (they're cheap), but their
	fin animation is skipped.
]]

local Swimmers = {}

local Build
local MapConfig

type Loop = {
	centre: Vector3,
	rx: number,
	rz: number,
	bob: number,
	speed: number, -- radians per second around the loop
	angle: number,
}

type Swimmer = {
	kind: string,
	loop: Loop,
	rigs: { any },
	offsets: { CFrame }, -- per rig, for schools
	fins: { { [number]: number } }, -- per rig: part index -> side (-1/1) or tail (0)
	phase: number,
}

local swimmers: { Swimmer } = {}

local function loopAt(rng: Random, y0: number, y1: number, rMin: number, rMax: number): Loop
	local area = MapConfig.SEABED_AREA
	local rx = rng:NextNumber(rMin, rMax)
	local rz = rng:NextNumber(rMin * 0.7, rMax * 0.8)
	local cx = rng:NextNumber(area.minX + rx, area.maxX - rx)
	local cz = rng:NextNumber(area.minZ + rz, area.maxZ - rz)
	return {
		centre = Vector3.new(cx, rng:NextNumber(y0, y1), cz),
		rx = rx,
		rz = rz,
		bob = rng:NextNumber(1, 3),
		speed = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(0.6, 1) / ((rx + rz) / 2) * 6,
		angle = rng:NextNumber(0, math.pi * 2),
	}
end

local function loopFrame(loop: Loop, angle: number): CFrame
	local p = loop.centre + Vector3.new(math.cos(angle) * loop.rx, math.sin(angle * 2) * loop.bob, math.sin(angle) * loop.rz)
	local dir = math.sign(loop.speed)
	local tangent = Vector3.new(-math.sin(angle) * loop.rx * dir, math.cos(angle * 2) * loop.bob * 0.5 * dir, math.cos(angle) * loop.rz * dir)
	return CFrame.lookAt(p, p + tangent)
end

-------------------------------------------------------------------------------
-- builders. Every model faces -Z (forward).
-------------------------------------------------------------------------------

local FISH_COLOURS = {
	{ Color3.fromRGB(255, 220, 60), Color3.fromRGB(70, 140, 255) },
	{ Color3.fromRGB(255, 140, 40), Color3.new(1, 1, 1) },
	{ Color3.fromRGB(150, 110, 255), Color3.fromRGB(255, 230, 120) },
	{ Color3.fromRGB(120, 220, 255), Color3.fromRGB(230, 250, 255) },
	{ Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 230, 240) },
}

local function fish(folder: Instance, colours, scale: number)
	local rig = Build.rig()
	local fins = {}
	Build.add(rig, Build.blob({ Size = Vector3.new(0.6, 0.9, 1.7) * scale, Color = colours[1] }, folder), CFrame.identity)
	Build.add(rig, Build.blob({ Size = Vector3.new(0.62, 0.5, 0.5) * scale, Color = colours[2] }, folder), CFrame.new(0, 0, 0.1 * scale))
	local tail = Build.blob({ Size = Vector3.new(0.1, 0.9, 0.7) * scale, Color = colours[2] }, folder)
	fins[Build.add(rig, tail, CFrame.new(0, 0, 0.95 * scale))] = 0
	for _, x in { -0.27, 0.27 } do
		Build.add(rig, Build.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2 * scale, Color = Color3.fromRGB(20, 22, 46) }, folder), CFrame.new(x * scale, 0.12 * scale, -0.55 * scale))
	end
	return rig, fins
end

local function turtle(folder: Instance)
	local rig = Build.rig()
	local fins = {}
	local shell = Color3.fromRGB(90, 150, 80)
	local skin = Color3.fromRGB(160, 200, 120)
	Build.add(rig, Build.blob({ Size = Vector3.new(4.6, 1.8, 5.6), Color = shell, Material = Enum.Material.Slate }, folder), CFrame.identity)
	Build.add(rig, Build.blob({ Size = Vector3.new(3.2, 1.4, 4), Color = shell:Lerp(Color3.fromRGB(220, 200, 120), 0.4), Material = Enum.Material.Slate }, folder), CFrame.new(0, 0.35, 0))
	Build.add(rig, Build.blob({ Size = Vector3.new(4.2, 0.8, 5.2), Color = Color3.fromRGB(230, 220, 160) }, folder), CFrame.new(0, -0.45, 0))
	Build.add(rig, Build.blob({ Size = Vector3.new(1.3, 1.1, 1.6), Color = skin }, folder), CFrame.new(0, 0.1, -3.2))
	for _, x in { -0.35, 0.35 } do
		Build.add(rig, Build.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.25, Color = Color3.fromRGB(20, 22, 46) }, folder), CFrame.new(x, 0.35, -3.7))
	end
	-- flippers: pivot at the shoulder, so the offset is the shoulder and
	-- the flap (in step) rotates then pushes the flipper out sideways
	for _, side in { -1, 1 } do
		local front = Build.blob({ Size = Vector3.new(3.2, 0.3, 1.3), Color = skin }, folder)
		fins[Build.add(rig, front, CFrame.new(side * 2, -0.2, -1.4))] = side * 2 -- big front flippers
		local back = Build.blob({ Size = Vector3.new(1.6, 0.25, 1), Color = skin }, folder)
		fins[Build.add(rig, back, CFrame.new(side * 1.8, -0.2, 2.2))] = side
	end
	return rig, fins
end

local function manta(folder: Instance)
	local rig = Build.rig()
	local fins = {}
	local top = Color3.fromRGB(60, 80, 120)
	Build.add(rig, Build.blob({ Size = Vector3.new(4, 0.9, 5.5), Color = top }, folder), CFrame.identity)
	Build.add(rig, Build.blob({ Size = Vector3.new(3.6, 0.5, 5), Color = Color3.fromRGB(240, 245, 250) }, folder), CFrame.new(0, -0.25, 0))
	for _, side in { -1, 1 } do
		local wing = Build.blob({ Size = Vector3.new(8, 0.35, 4), Color = top }, folder)
		fins[Build.add(rig, wing, CFrame.new(side * 1.5, 0, 0.3))] = side * 2
		-- head lobes
		Build.add(rig, Build.blob({ Size = Vector3.new(0.5, 0.4, 1.4), Color = top }, folder), CFrame.new(side * 1.2, -0.1, -3) * CFrame.Angles(0.3, 0, 0))
	end
	Build.add(rig, Build.part({ Size = Vector3.new(0.18, 0.18, 6), Color = top }, folder), CFrame.new(0, 0, 5.5))
	return rig, fins
end

local function jellyfish(folder: Instance, rng: Random)
	local rig = Build.rig()
	local fins = {}
	local colour = ({
		Color3.fromRGB(255, 150, 220),
		Color3.fromRGB(190, 150, 255),
		Color3.fromRGB(140, 220, 255),
	})[rng:NextInteger(1, 3)]
	Build.add(rig, Build.blob({ Size = Vector3.new(3, 2.2, 3), Color = colour, Material = Enum.Material.Neon, Transparency = 0.45 }, folder), CFrame.identity)
	Build.add(rig, Build.blob({ Size = Vector3.new(1.6, 1.2, 1.6), Color = colour:Lerp(Color3.new(1, 1, 1), 0.5), Material = Enum.Material.Neon, Transparency = 0.3 }, folder), CFrame.new(0, 0.1, 0))
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local t = Build.part({ Size = Vector3.new(0.15, 4, 0.15), Color = colour, Material = Enum.Material.Neon, Transparency = 0.4 }, folder)
		fins[Build.add(rig, t, CFrame.new(math.cos(a) * 0.9, -2.4, math.sin(a) * 0.9))] = i
	end
	return rig, fins
end

-------------------------------------------------------------------------------

function Swimmers.init(rng: Random, build, config, parent: Instance)
	Build = build
	MapConfig = config
	local folder = Instance.new("Folder")
	folder.Name = "Swimmers"
	folder.Parent = parent

	-- fish schools
	for s = 1, 5 do
		local colours = FISH_COLOURS[(s - 1) % #FISH_COLOURS + 1]
		local entry: Swimmer = { kind = "school", loop = loopAt(rng, 6, 26, 25, 60), rigs = {}, offsets = {}, fins = {}, phase = rng:NextNumber(0, 6) }
		for _ = 1, rng:NextInteger(9, 13) do
			local rig, fins = fish(folder, colours, rng:NextNumber(0.8, 1.2))
			table.insert(entry.rigs, rig)
			table.insert(entry.fins, fins)
			table.insert(entry.offsets, CFrame.new(rng:NextNumber(-4, 4), rng:NextNumber(-2, 2), rng:NextNumber(-5, 5)))
		end
		table.insert(swimmers, entry)
	end

	local function single(kind: string, rig, fins, loop: Loop)
		table.insert(swimmers, { kind = kind, loop = loop, rigs = { rig }, offsets = { CFrame.identity }, fins = { fins }, phase = rng:NextNumber(0, 6) })
	end
	do
		local rig, fins = turtle(folder)
		single("turtle", rig, fins, loopAt(rng, 14, 22, 70, 100))
	end
	do
		local rig, fins = manta(folder)
		single("manta", rig, fins, loopAt(rng, 24, 32, 80, 110))
	end
	for _ = 1, 7 do
		local rig, fins = jellyfish(folder, rng)
		local loop = loopAt(rng, 14, 30, 10, 25)
		loop.speed *= 0.35
		loop.bob = 4
		single("jelly", rig, fins, loop)
	end

	local parts, cfs = {}, {}
	Swimmers.step(0, 0, Vector3.zero, parts, cfs, true)
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function Swimmers.step(t: number, dt: number, camPos: Vector3, parts: { BasePart }, cfs: { CFrame }, force: boolean?)
	for _, s in swimmers do
		local loop = s.loop
		loop.angle += loop.speed * dt
		local root = loopFrame(loop, loop.angle)
		if s.kind == "jelly" then
			-- jellies stay upright and pulse up and down instead of facing forward
			root = CFrame.new(root.Position + Vector3.new(0, math.sin(t * 0.8 + s.phase) * 2, 0))
		end
		local near = force or (root.Position - camPos).Magnitude < 220
		for r, rig in s.rigs do
			local extra = nil
			if near then
				extra = {}
				for idx, side in s.fins[r] do
					if s.kind == "school" then
						extra[idx] = CFrame.Angles(0, math.sin(t * 12 + s.phase + r) * 0.5, 0)
					elseif s.kind == "turtle" then
						local flap = math.sin(t * 1.6 + s.phase) * 0.5 * (if math.abs(side) > 1 then 1 else 0.5)
						local dirn = math.sign(side)
						extra[idx] = CFrame.Angles(0, 0, dirn * flap) * CFrame.new(dirn * 1.2, 0, 0)
					elseif s.kind == "manta" then
						local flap = math.sin(t * 1.2 + s.phase) * 0.45
						local dirn = math.sign(side)
						extra[idx] = CFrame.Angles(0, 0, dirn * flap) * CFrame.new(dirn * 3.6, 0, 0)
					else -- jelly tentacles
						extra[idx] = CFrame.Angles(math.sin(t * 2 + side) * 0.15, 0, math.cos(t * 1.7 + side) * 0.15)
					end
				end
			elseif s.kind == "turtle" or s.kind == "manta" then
				-- still push fins out to their resting place when far away
				extra = {}
				for idx, side in s.fins[r] do
					extra[idx] = CFrame.new(math.sign(side) * (if s.kind == "manta" then 3.6 else 1.2), 0, 0)
				end
			end
			local swim = if s.kind == "school"
				then root * s.offsets[r] * CFrame.new(0, math.sin(t * 2 + r) * 0.3, 0)
				else root
			Build.pose(rig, swim, parts, cfs, extra)
		end
	end
end

return Swimmers
