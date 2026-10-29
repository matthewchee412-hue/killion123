--[[
	Critters — starfish and crabs that slowly wander the seabed on this
	client. Each one picks a nearby spot, turns, walks there, rests a few
	seconds, and picks another. Crabs walk sideways and wave their legs;
	starfish creep and ripple their arms. Nothing walks into a ring.
]]

local Critters = {}

local ACTIVE_DISTANCE = 200

local Build
local MapConfig

type Critter = {
	rig: any,
	kind: string,
	pos: Vector3,
	target: Vector3,
	yaw: number,
	speed: number,
	rest: number,
	legs: { number },
	height: number,
	phase: number,
}

local critters: { Critter } = {}

local function newTarget(c: Critter, rng: Random)
	local area = MapConfig.SEABED_AREA
	for _ = 1, 20 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(8, 25)
		local x = math.clamp(c.pos.X + math.cos(a) * d, area.minX, area.maxX)
		local z = math.clamp(c.pos.Z + math.sin(a) * d, area.minZ, area.maxZ)
		if MapConfig.clearOfRings(x, z, -6) then
			c.target = Vector3.new(x, MapConfig.SEABED_Y, z)
			return
		end
	end
	c.target = c.pos
end

local function starfish(folder: Instance, at: Vector3, rng: Random): Critter
	local rig = Build.rig()
	rig.root = CFrame.new(at)
	local color = ({
		Color3.fromRGB(255, 120, 60),
		Color3.fromRGB(255, 80, 110),
		Color3.fromRGB(170, 100, 255),
		Color3.fromRGB(255, 200, 70),
	})[rng:NextInteger(1, 4)]
	local s = rng:NextNumber(0.9, 1.4)
	Build.add(rig, Build.blob({ Size = Vector3.new(1.4, 0.5, 1.4) * s, Color = color }, folder), CFrame.new(0, 0.25 * s, 0))
	local legs = {}
	for i = 1, 5 do
		local yaw = i / 5 * math.pi * 2
		local arm = Build.blob({ Size = Vector3.new(0.7, 0.4, 2.2) * s, Color = color }, folder)
		local idx = Build.add(rig, arm, CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0.2 * s, -1.1 * s))
		table.insert(legs, idx)
		-- a light dot at the tip of each arm
		local dot = Build.blob({ Size = Vector3.new(0.3, 0.2, 0.3) * s, Color = color:Lerp(Color3.new(1, 1, 1), 0.5) }, folder)
		Build.add(rig, dot, CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0.38 * s, -1.6 * s))
	end
	return {
		rig = rig,
		kind = "starfish",
		pos = at,
		target = at,
		yaw = rng:NextNumber(0, math.pi * 2),
		speed = rng:NextNumber(0.4, 0.7),
		rest = rng:NextNumber(0, 4),
		legs = legs,
		height = 0,
		phase = rng:NextNumber(0, 6),
	}
end

local function crab(folder: Instance, at: Vector3, rng: Random): Critter
	local rig = Build.rig()
	rig.root = CFrame.new(at)
	local shell = ({
		Color3.fromRGB(240, 90, 60),
		Color3.fromRGB(255, 130, 70),
		Color3.fromRGB(220, 70, 90),
	})[rng:NextInteger(1, 3)]
	local s = rng:NextNumber(0.9, 1.3)
	local legs = {}
	-- body (front is -Z, it walks along X)
	Build.add(rig, Build.blob({ Size = Vector3.new(2.2, 1, 1.7) * s, Color = shell }, folder), CFrame.new(0, 0.9 * s, 0))
	-- eyes on stalks
	for _, x in { -0.4, 0.4 } do
		Build.add(rig, Build.part({ Size = Vector3.new(0.15, 0.6, 0.15) * s, Color = shell }, folder), CFrame.new(x * s, 1.5 * s, -0.55 * s))
		Build.add(rig, Build.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.38 * s, Color = Color3.new(1, 1, 1) }, folder), CFrame.new(x * s, 1.85 * s, -0.55 * s))
		Build.add(rig, Build.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2 * s, Color = Color3.fromRGB(20, 22, 46) }, folder), CFrame.new(x * s, 1.87 * s, -0.7 * s))
	end
	-- claws
	for _, x in { -1, 1 } do
		local claw = Build.blob({ Size = Vector3.new(0.8, 0.6, 1.1) * s, Color = shell:Lerp(Color3.new(1, 1, 1), 0.15) }, folder)
		table.insert(legs, Build.add(rig, claw, CFrame.new(x * 1.05 * s, 1.0 * s, -1.2 * s)))
	end
	-- three legs per side
	for _, x in { -1, 1 } do
		for i = -1, 1 do
			local leg = Build.part({ Size = Vector3.new(1.1, 0.18, 0.18) * s, Color = shell }, folder)
			table.insert(legs, Build.add(rig, leg, CFrame.new(x * 1.3 * s, 0.45 * s, i * 0.5 * s) * CFrame.Angles(0, 0, x * 0.6)))
		end
	end
	return {
		rig = rig,
		kind = "crab",
		pos = at,
		target = at,
		yaw = rng:NextNumber(0, math.pi * 2),
		speed = rng:NextNumber(1.2, 2),
		rest = rng:NextNumber(0, 3),
		legs = legs,
		height = 0,
		phase = rng:NextNumber(0, 6),
	}
end

local rng: Random

function Critters.init(r: Random, build, config, parent: Instance)
	rng = r
	Build = build
	MapConfig = config
	local folder = Instance.new("Folder")
	folder.Name = "Critters"
	folder.Parent = parent
	for _ = 1, 10 do
		table.insert(critters, starfish(folder, Build.seabedPoint(rng, MapConfig, -6), rng))
	end
	for _ = 1, 8 do
		table.insert(critters, crab(folder, Build.seabedPoint(rng, MapConfig, -6), rng))
	end
	local parts, cfs = {}, {}
	for _, c in critters do
		Build.pose(c.rig, CFrame.new(c.pos) * CFrame.Angles(0, c.yaw, 0), parts, cfs)
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function turnToward(current: number, goal: number, maxStep: number): number
	local diff = (goal - current + math.pi) % (math.pi * 2) - math.pi
	if math.abs(diff) <= maxStep then
		return goal
	end
	return current + math.sign(diff) * maxStep
end

function Critters.step(t: number, dt: number, camPos: Vector3, parts: { BasePart }, cfs: { CFrame })
	for _, c in critters do
		if (c.pos - camPos).Magnitude > ACTIVE_DISTANCE then
			continue
		end
		local walking = false
		if c.rest > 0 then
			c.rest -= dt
			if c.rest <= 0 then
				newTarget(c, rng)
			end
		else
			local offset = Vector3.new(c.target.X - c.pos.X, 0, c.target.Z - c.pos.Z)
			local dist = offset.Magnitude
			if dist < 0.3 then
				c.rest = rng:NextNumber(2, 6)
			else
				local dir = offset / dist
				-- crabs face so their side points where they're going
				local goalYaw = if c.kind == "crab" then math.atan2(-dir.Z, dir.X) else math.atan2(-dir.X, -dir.Z)
				c.yaw = turnToward(c.yaw, goalYaw, dt * (if c.kind == "crab" then 2 else 0.6))
				local facing = math.abs((goalYaw - c.yaw + math.pi) % (math.pi * 2) - math.pi)
				if facing < 0.6 then
					c.pos += dir * math.min(dist, c.speed * dt)
					walking = true
				end
			end
		end

		local extra = {}
		local phase = t * (if c.kind == "crab" then 10 else 2) + c.phase
		for n, idx in c.legs do
			if c.kind == "crab" then
				local swing = if walking then math.sin(phase + n * 1.3) * 0.35 else math.sin(t * 2 + n) * 0.08
				-- the first two are the claws (snap up and down), the rest are legs (swing back and forth)
				extra[idx] = if n <= 2 then CFrame.Angles(swing * 0.8, 0, 0) else CFrame.Angles(0, swing, 0)
			else
				local curl = if walking then math.sin(phase + n * 1.2) * 0.15 else 0
				extra[idx] = CFrame.Angles(curl, 0, 0)
			end
		end
		local bob = if walking and c.kind == "crab" then math.abs(math.sin(phase)) * 0.08 else 0
		Build.pose(c.rig, CFrame.new(c.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, c.yaw, 0), parts, cfs, extra)
	end
end

return Critters
