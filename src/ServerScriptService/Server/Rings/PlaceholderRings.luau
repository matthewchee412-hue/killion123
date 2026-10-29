--[[
	PlaceholderRings — plain test rings until the real map exists (prompt 3).

	If workspace.Rings is missing or empty, this builds one casual and one
	Ranked ring near the origin: a sand disc, a Centre part and 8 Seats facing
	the middle. The map builder will replace these with boulder armchairs.
]]

local PlaceholderRings = {}

local RADIUS = 12
local SEATS = 8

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function build(name: string, centre: Vector3, ranked: boolean, parent: Instance)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Ranked", ranked)

	local floor = part({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, RADIUS * 2 + 8, RADIUS * 2 + 8),
		CFrame = CFrame.new(centre - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = if ranked then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(240, 220, 170),
		Material = Enum.Material.Sand,
	})
	floor.Parent = model

	local mid = part({
		Name = "Centre",
		Size = Vector3.new(2, 1, 2),
		CFrame = CFrame.new(centre + Vector3.new(0, 0.5, 0)),
		Color = Color3.fromRGB(80, 220, 230),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	mid.Parent = model
	model.PrimaryPart = mid

	for i = 1, SEATS do
		local angle = (i - 1) / SEATS * math.pi * 2
		local pos = centre + Vector3.new(math.cos(angle) * RADIUS, 1, math.sin(angle) * RADIUS)
		local seat = Instance.new("Seat")
		seat.Name = "Seat" .. i
		seat.Anchored = true
		seat.Size = Vector3.new(4, 1, 4)
		seat.CFrame = CFrame.lookAt(pos, Vector3.new(centre.X, pos.Y, centre.Z))
		seat.Color = Color3.fromRGB(120, 125, 140)
		seat.Material = Enum.Material.Slate
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat:SetAttribute("SeatSkin", "Default")
		seat.Parent = model
	end

	model.Parent = parent
end

function PlaceholderRings.ensure()
	local rings = workspace:FindFirstChild("Rings")
	if rings and #rings:GetChildren() > 0 then
		return
	end
	if not rings then
		rings = Instance.new("Folder")
		rings.Name = "Rings"
		rings.Parent = workspace
	end
	build("Ring1", Vector3.new(0, 1, 40), false, rings)
	build("RankedRing1", Vector3.new(45, 1, 40), true, rings)
	print("[PlaceholderRings] built 2 test rings (no map yet)")
end

return PlaceholderRings
