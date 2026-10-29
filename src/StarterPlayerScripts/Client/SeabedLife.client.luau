--[[
	SeabedLife — builds and animates everything that lives on the seabed,
	on this client only, so the server stays light:
	kelp, coral, rocks, shells, sand ripples, starfish, crabs, fish schools,
	a turtle, a manta, jellyfish, bubbles, god rays, the underwater tint and
	the ring signs.

	Everything is built once from a fixed seed (so every player sees the
	same seabed), then one loop moves all moving parts with a single
	workspace:BulkMoveTo, about 30 times a second.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapConfig"))

local Seabed = script.Parent:WaitForChild("Seabed")
local Build = require(Seabed.Build)
local Underwater = require(Seabed.Underwater)
local RingSigns = require(Seabed.RingSigns)
local Decor = require(Seabed.Decor)
local Kelp = require(Seabed.Kelp)
local Critters = require(Seabed.Critters)
local Swimmers = require(Seabed.Swimmers)
local Bubbles = require(Seabed.Bubbles)

-- the server builds the rings after the terrain and lighting, so once
-- they exist the map is ready
workspace:WaitForChild("Rings")

local life = Instance.new("Folder")
life.Name = "SeabedLife"
life.Parent = workspace

local started = os.clock()
Underwater.init(Random.new(11), MapConfig)
RingSigns.init()
Decor.init(Random.new(21), Build, MapConfig, life)
Kelp.init(Random.new(31), Build, MapConfig, life)
Critters.init(Random.new(41), Build, MapConfig, life)
Swimmers.init(Random.new(51), Build, MapConfig, life)
Bubbles.init(Random.new(61), Build, MapConfig, life)

local count = 0
for _, d in life:GetDescendants() do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(string.format("[SeabedLife] built %d parts in %d ms", count, math.floor((os.clock() - started) * 1000)))

local STEP = 1 / 30
local acc = 0
local t = 0
local parts: { BasePart } = {}
local cfs: { CFrame } = {}

RunService.Heartbeat:Connect(function(dt)
	t += dt
	acc += dt
	if acc < STEP then
		return
	end
	local stepDt = math.min(acc, 0.25)
	acc = 0

	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else MapConfig.SPAWN

	Underwater.step(t, camPos)
	RingSigns.step(t)

	table.clear(parts)
	table.clear(cfs)
	Kelp.step(t, camPos, parts, cfs)
	Critters.step(t, stepDt, camPos, parts, cfs)
	Swimmers.step(t, stepDt, camPos, parts, cfs)
	Bubbles.step(t, stepDt, parts, cfs)
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end)
