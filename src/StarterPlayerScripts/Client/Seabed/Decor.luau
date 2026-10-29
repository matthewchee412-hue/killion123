--[[
	Decor — the still parts of the seabed, built once on this client:
	coral (branching, brain, fan, tube), anemones, rocks, shells and sand
	ripples. Coral clusters sit just outside every ring so each ring feels
	like its own little reef.
]]

local Decor = {}

local CORAL = {
	Color3.fromRGB(255, 110, 150), -- pink
	Color3.fromRGB(255, 150, 70), -- orange
	Color3.fromRGB(180, 110, 255), -- purple
	Color3.fromRGB(255, 220, 80), -- yellow
	Color3.fromRGB(90, 220, 200), -- teal
	Color3.fromRGB(255, 90, 90), -- red
}

local Build
local MapConfig
local folder: Folder

local function pick(rng: Random, list)
	return list[rng:NextInteger(1, #list)]
end

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end

local function branchCoral(at: Vector3, rng: Random, scale: number)
	local color = pick(rng, CORAL)
	local base = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local function branch(from: CFrame, len: number, width: number, depth: number)
		local mid = from * CFrame.new(0, len / 2, 0)
		Build.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(len, width, width),
			CFrame = Build.upright(mid),
			Color = color,
		}, folder)
		local tip = from * CFrame.new(0, len, 0)
		if depth >= 1 then
			Build.part({
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * width * 1.5,
				CFrame = tip,
				Color = lighter(color, 0.35),
				Material = Enum.Material.Neon,
			}, folder)
			return
		end
		for i = 1, 4 do
			local yaw = i / 4 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
			local tilt = math.rad(rng:NextNumber(25, 45))
			branch(tip * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0), len * 0.7, width * 0.75, depth + 1)
		end
	end
	branch(base, 2.4 * scale, 0.7 * scale, 0)
end

local function brainCoral(at: Vector3, rng: Random, scale: number)
	local color = pick(rng, CORAL)
	local s = rng:NextNumber(2.5, 4) * scale
	Build.blob({
		Size = Vector3.new(s, s * 0.6, s),
		CFrame = CFrame.new(at + Vector3.new(0, s * 0.18, 0)),
		Color = color,
		Material = Enum.Material.Slate,
	}, folder)
	-- a lighter cap so it reads as a round coral, not a rock
	Build.blob({
		Size = Vector3.new(s * 0.7, s * 0.25, s * 0.7),
		CFrame = CFrame.new(at + Vector3.new(0, s * 0.42, 0)),
		Color = lighter(color, 0.3),
		Material = Enum.Material.Slate,
	}, folder)
end

local function fanCoral(at: Vector3, rng: Random, scale: number)
	local color = pick(rng, { CORAL[1], CORAL[3], CORAL[6] })
	local cf = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	Build.part({
		Size = Vector3.new(0.4, 1.4 * scale, 0.4),
		CFrame = cf * CFrame.new(0, 0.7 * scale, 0),
		Color = color,
	}, folder)
	Build.blob({
		Size = Vector3.new(5 * scale, 4.4 * scale, 0.25),
		CFrame = cf * CFrame.new(0, 3.2 * scale, 0),
		Color = color,
		Transparency = 0.1,
	}, folder)
	Build.blob({
		Size = Vector3.new(3.4 * scale, 3 * scale, 0.3),
		CFrame = cf * CFrame.new(0, 3.2 * scale, 0),
		Color = lighter(color, 0.3),
	}, folder)
end

local function tubeCoral(at: Vector3, rng: Random, scale: number)
	local color = pick(rng, { CORAL[2], CORAL[4], CORAL[5] })
	for _ = 1, rng:NextInteger(4, 7) do
		local h = rng:NextNumber(1.5, 4) * scale
		local w = rng:NextNumber(0.6, 1.1) * scale
		local p = at + Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2)) * scale
		Build.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h, w, w),
			CFrame = Build.upright(CFrame.new(p + Vector3.new(0, h / 2, 0))),
			Color = color,
		}, folder)
		Build.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, w * 0.7, w * 0.7),
			CFrame = Build.upright(CFrame.new(p + Vector3.new(0, h + 0.02, 0))),
			Color = lighter(color, 0.5),
			Material = Enum.Material.Neon,
		}, folder)
	end
end

local function anemone(at: Vector3, rng: Random, scale: number)
	local color = pick(rng, { CORAL[1], CORAL[3], CORAL[5] })
	Build.blob({
		Size = Vector3.new(2, 1.2, 2) * scale,
		CFrame = CFrame.new(at + Vector3.new(0, 0.4 * scale, 0)),
		Color = color,
	}, folder)
	for i = 1, 8 do
		local yaw = i / 8 * math.pi * 2
		local cf = CFrame.new(at + Vector3.new(0, 0.8 * scale, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(math.rad(rng:NextNumber(15, 35)), 0, 0)
			* CFrame.new(0, 1 * scale, 0)
		Build.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2 * scale, 0.25 * scale, 0.25 * scale),
			CFrame = Build.upright(cf),
			Color = lighter(color, 0.4),
			Material = Enum.Material.Neon,
		}, folder)
	end
end

local CORALS = { branchCoral, branchCoral, brainCoral, fanCoral, tubeCoral, anemone }

local function coralCluster(at: Vector3, rng: Random, count: number)
	for _ = 1, count do
		local offset = Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
		pick(rng, CORALS)(at + offset, rng, rng:NextNumber(0.8, 1.3))
	end
end

local function rock(at: Vector3, rng: Random, size: number)
	local grey = Color3.fromRGB(150, 145, 140):Lerp(Color3.fromRGB(185, 175, 160), rng:NextNumber())
	Build.blob({
		Size = Vector3.new(size * rng:NextNumber(1, 1.5), size * rng:NextNumber(0.6, 0.9), size),
		CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-10, 10))),
		Color = grey,
		Material = Enum.Material.Rock,
		CastShadow = size > 4,
	}, folder)
	if rng:NextNumber() < 0.5 then
		-- a smaller rock leaning on it
		local s = size * 0.5
		Build.blob({
			Size = Vector3.new(s * 1.2, s * 0.8, s),
			CFrame = CFrame.new(at + Vector3.new(size * 0.6, -s * 0.1, size * 0.3)),
			Color = grey:Lerp(Color3.new(0, 0, 0), 0.08),
			Material = Enum.Material.Rock,
		}, folder)
	end
end

local SHELLS = {
	Color3.fromRGB(255, 225, 225),
	Color3.fromRGB(255, 200, 170),
	Color3.fromRGB(255, 245, 230),
	Color3.fromRGB(250, 180, 200),
}

local function shell(at: Vector3, rng: Random)
	local color = pick(rng, SHELLS)
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	if rng:NextNumber() < 0.6 then
		-- scallop: a flat fan with a darker hinge
		local cf = CFrame.new(at + Vector3.new(0, 0.15, 0)) * yaw * CFrame.Angles(math.rad(-10), 0, 0)
		Build.blob({ Size = Vector3.new(1.4, 0.35, 1.2), CFrame = cf, Color = color }, folder)
		Build.blob({
			Size = Vector3.new(0.6, 0.3, 0.4),
			CFrame = cf * CFrame.new(0, 0.02, 0.5),
			Color = color:Lerp(Color3.fromRGB(220, 120, 120), 0.35),
		}, folder)
	else
		-- conch: a cone of shrinking blobs
		local cf = CFrame.new(at + Vector3.new(0, 0.35, 0)) * yaw
		for i = 0, 2 do
			local s = 1 - i * 0.28
			Build.blob({
				Size = Vector3.new(s, s * 0.8, s * 1.1),
				CFrame = cf * CFrame.new(0, i * 0.08, -i * 0.45),
				Color = if i % 2 == 0 then color else color:Lerp(Color3.fromRGB(200, 140, 110), 0.3),
			}, folder)
		end
	end
end

local function ripples(at: Vector3, rng: Random)
	local cf = CFrame.new(at + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	local rows = rng:NextInteger(6, 10)
	local length = rng:NextNumber(10, 18)
	for r = 1, rows do
		local row = cf * CFrame.new(math.sin(r) * 1.2, 0, (r - rows / 2) * 1.7) * CFrame.Angles(0, math.sin(r * 1.7) * 0.08, 0)
		Build.blob({
			Size = Vector3.new(length * (1 - math.abs(r - rows / 2) / rows), 0.18, 0.55),
			CFrame = row,
			Color = Color3.fromRGB(252, 240, 205),
			Material = Enum.Material.Sand,
		}, folder)
	end
end

function Decor.init(rng: Random, build, config, parent: Instance)
	Build = build
	MapConfig = config
	folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = parent

	-- reefs just outside each ring, between the chairs
	for _, ring in MapConfig.RINGS do
		local centre = MapConfig.ringCentre(ring)
		for i = 1, 4 do
			local a = (i + rng:NextNumber(-0.2, 0.2)) / 4 * math.pi * 2 + math.pi / 8
			local d = rng:NextNumber(24, 29)
			coralCluster(centre + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), rng, rng:NextInteger(2, 4))
		end
	end

	-- reefs around the open seabed
	for _ = 1, 12 do
		coralCluster(Build.seabedPoint(rng, MapConfig, 8), rng, rng:NextInteger(3, 6))
	end

	-- a reef at the bottom of the slope to welcome people in
	for _, x in { -18, 18 } do
		coralCluster(Vector3.new(x, MapConfig.SEABED_Y, MapConfig.SLOPE_FOOT_Z + 14), rng, 5)
	end

	for _ = 1, 34 do
		rock(Build.seabedPoint(rng, MapConfig, 4), rng, rng:NextNumber(1.5, 7))
	end
	for _ = 1, 60 do
		shell(Build.seabedPoint(rng, MapConfig, -6), rng)
	end
	for _ = 1, 16 do
		ripples(Build.seabedPoint(rng, MapConfig, 6), rng)
	end
end

return Decor
