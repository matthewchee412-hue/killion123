--[[
	Bubbles — streams of bubbles rising from little vents on the seabed and
	from behind every ring, on this client. A fixed pool of bubbles is
	reused: when one reaches the surface it starts again at a vent.
]]

local Bubbles = {}

local PER_VENT = 7

type Bubble = { part: BasePart, vent: Vector3, y: number, speed: number, wobble: number, phase: number }

local bubbles: { Bubble } = {}
local MapConfig

local function reset(b: Bubble, rng: Random, startY: number?)
	b.y = startY or MapConfig.SEABED_Y + 0.5
	b.speed = rng:NextNumber(3, 6)
	b.wobble = rng:NextNumber(0.2, 0.6)
	b.phase = rng:NextNumber(0, 6)
end

local rng: Random

function Bubbles.init(r: Random, Build, config, parent: Instance)
	rng = r
	MapConfig = config
	local folder = Instance.new("Folder")
	folder.Name = "Bubbles"
	folder.Parent = parent

	local vents = {}
	for _ = 1, 8 do
		table.insert(vents, Build.seabedPoint(rng, MapConfig, 2))
	end
	-- one vent just behind each ring, so bubbles rise past the signs
	for _, ring in MapConfig.RINGS do
		table.insert(vents, MapConfig.ringCentre(ring) + Vector3.new(0, 0, MapConfig.RING_RADIUS + 9))
	end

	for _, vent in vents do
		-- a small dark hole the bubbles come out of
		Build.blob({
			Size = Vector3.new(1.6, 0.3, 1.6),
			CFrame = CFrame.new(vent + Vector3.new(0, 0.05, 0)),
			Color = Color3.fromRGB(150, 140, 125),
			Material = Enum.Material.Rock,
		}, folder)
		for _ = 1, PER_VENT do
			local s = rng:NextNumber(0.3, 0.8)
			local b: Bubble = {
				part = Build.part({
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * s,
					Color = Color3.fromRGB(225, 250, 255),
					Transparency = 0.35,
					Reflectance = 0.3,
				}, folder),
				vent = vent,
				y = 0,
				speed = 0,
				wobble = 0,
				phase = 0,
			}
			-- spread them out up the stream from the start
			reset(b, rng, rng:NextNumber(MapConfig.SEABED_Y, MapConfig.WATER_LEVEL))
			table.insert(bubbles, b)
		end
	end
end

function Bubbles.step(t: number, dt: number, parts: { BasePart }, cfs: { CFrame })
	for _, b in bubbles do
		b.y += b.speed * dt
		if b.y > MapConfig.WATER_LEVEL - 0.5 then
			reset(b, rng)
		end
		local w = math.sin(t * 3 + b.phase) * b.wobble
		table.insert(parts, b.part)
		table.insert(cfs, CFrame.new(b.vent.X + w, b.y, b.vent.Z + math.cos(t * 2.3 + b.phase) * b.wobble))
	end
end

return Bubbles
