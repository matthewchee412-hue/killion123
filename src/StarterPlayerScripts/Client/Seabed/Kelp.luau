--[[
	Kelp — tall swaying kelp in patches, animated on this client.

	Each stalk is a chain of flat leafy segments. Every frame, each segment
	bends a little more than the one below it, with a wave travelling up the
	stalk, so it sways like it's in a gentle current. Stalks far from the
	camera stop moving to save work.
]]

local Kelp = {}

local SEGMENTS = 7
local SEG_HEIGHT = 3
local ACTIVE_DISTANCE = 170

type Stalk = {
	base: CFrame,
	parts: { BasePart },
	heights: { number },
	phase: number,
	speed: number,
	amp: number,
}

local stalks: { Stalk } = {}

local GREENS = {
	Color3.fromRGB(70, 170, 70),
	Color3.fromRGB(95, 190, 75),
	Color3.fromRGB(120, 200, 80),
	Color3.fromRGB(80, 160, 90),
}

local function stalk(Build, folder: Instance, at: Vector3, rng: Random)
	local base = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local color = GREENS[rng:NextInteger(1, #GREENS)]
	local count = rng:NextInteger(SEGMENTS - 2, SEGMENTS + 2)
	local s: Stalk = {
		base = base,
		parts = {},
		heights = {},
		phase = rng:NextNumber(0, math.pi * 2),
		speed = rng:NextNumber(0.6, 0.9),
		amp = rng:NextNumber(0.05, 0.09),
	}
	for i = 1, count do
		local h = SEG_HEIGHT * rng:NextNumber(0.9, 1.15)
		local width = 1.6 - (i / count) * 0.6
		local p = Build.blob({
			Name = "Kelp",
			Size = Vector3.new(width, h * 1.15, 0.25),
			Color = color:Lerp(Color3.fromRGB(170, 230, 110), i / count * 0.5),
			Material = Enum.Material.Grass,
		}, folder)
		table.insert(s.parts, p)
		table.insert(s.heights, h)
	end
	table.insert(stalks, s)
end

function Kelp.init(rng: Random, Build, MapConfig, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Kelp"
	folder.Parent = parent

	-- patches of kelp; more along the cliffs so the edges feel like a forest
	local area = MapConfig.SEABED_AREA
	local spots = {}
	for _ = 1, 9 do
		table.insert(spots, Build.seabedPoint(rng, MapConfig, 10))
	end
	for _ = 1, 6 do
		local side = if rng:NextNumber() < 0.5 then area.minX + 8 else area.maxX - 8
		table.insert(spots, Vector3.new(side, MapConfig.SEABED_Y, rng:NextNumber(area.minZ + 20, area.maxZ)))
	end
	for _, spot in spots do
		for _ = 1, rng:NextInteger(4, 7) do
			local p = spot + Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
			stalk(Build, folder, p, rng)
		end
	end
	-- pose every stalk once so far-away kelp isn't left at the origin
	local parts, cfs = {}, {}
	Kelp.step(0, Vector3.zero, parts, cfs, true)
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- queue every nearby stalk's segments into `parts`/`cfs` for BulkMoveTo
function Kelp.step(t: number, camPos: Vector3, parts: { BasePart }, cfs: { CFrame }, force: boolean?)
	for _, s in stalks do
		if not force and (s.base.Position - camPos).Magnitude > ACTIVE_DISTANCE then
			continue
		end
		local cf = s.base
		local n = #s.parts
		for i, part in s.parts do
			local k = i / n
			local wave = t * s.speed + s.phase - i * 0.45
			local bendX = math.sin(wave) * s.amp * (0.4 + k)
			local bendZ = math.cos(wave * 0.7) * s.amp * 0.6 * (0.4 + k)
			local h = s.heights[i]
			cf = cf * CFrame.Angles(bendX, 0, bendZ) * CFrame.new(0, h / 2, 0)
			table.insert(parts, part)
			table.insert(cfs, cf)
			cf = cf * CFrame.new(0, h / 2, 0)
		end
	end
end

return Kelp
