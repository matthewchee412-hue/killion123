--[[
	MapBuilder — builds the Blowfish Blowout map when the server starts.

	The server only builds what everyone needs to share: terrain (beach,
	slope, sea, cliffs), lighting, the spawn, the beach props, and the six
	rings with their chairs and signs. Everything that moves (kelp, fish,
	crabs, bubbles, god rays) is built and animated by the client in
	StarterPlayerScripts/Client/Seabed, so the server stays light.

	Layout numbers are in ReplicatedStorage/Shared/MapConfig.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared.MapConfig)
local ChairSkins = require(Shared.ChairSkins)

local MapBuilder = {}

local GOLD = Color3.fromRGB(255, 196, 60)
local AQUA = Color3.fromRGB(70, 225, 235)
local OUTLINE = Color3.fromRGB(20, 22, 46)

local function part(props, parent: Instance?): BasePart
	local class = props.ClassName or "Part"
	props.ClassName = nil
	local p = Instance.new(class) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function decor(props, parent: Instance?): BasePart
	props.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	props.CanTouch = false
	props.CanQuery = false
	props.CastShadow = if props.CastShadow == nil then false else props.CastShadow
	return part(props, parent)
end

-------------------------------------------------------------------------------
-- lighting: bright and sunny, never dark (the client adds the underwater tint)
-------------------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 13
	Lighting.GeographicLatitude = 20
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(125, 145, 155)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 180, 190)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000

	for _, name in { "Atmosphere", "Bloom", "SunRays" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(205, 240, 245)
	atmosphere.Decay = Color3.fromRGB(110, 195, 215)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "SunRays"
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end

-------------------------------------------------------------------------------
-- terrain: sea, seabed, beach plateau, slope, rocky path, cliffs
-------------------------------------------------------------------------------

local function buildTerrain()
	local t = workspace.Terrain
	local C = MapConfig
	local width = C.MAX_X - C.MIN_X
	local midX = (C.MIN_X + C.MAX_X) / 2

	t:Clear()
	t.WaterColor = Color3.fromRGB(40, 205, 215)
	t.WaterTransparency = 0.85
	t.WaterReflectance = 0.3
	t.WaterWaveSize = 0.12
	t.WaterWaveSpeed = 8
	t:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(240, 222, 172))
	t:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(150, 140, 132))
	t:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(214, 176, 128))

	-- sea first, then solid ground over it
	local seaDepth = C.WATER_LEVEL - (C.SEABED_Y - 12)
	t:FillBlock(
		CFrame.new(midX, C.SEABED_Y - 12 + seaDepth / 2, (C.BEACH_EDGE_Z + C.MAX_Z) / 2),
		Vector3.new(width, seaDepth, C.MAX_Z - C.BEACH_EDGE_Z),
		Enum.Material.Water
	)

	-- seabed, 12 studs thick
	t:FillBlock(
		CFrame.new(midX, C.SEABED_Y - 6, (C.BEACH_BACK_Z + C.MAX_Z) / 2),
		Vector3.new(width, 12, C.MAX_Z - C.BEACH_BACK_Z),
		Enum.Material.Sand
	)

	-- beach plateau
	local beachH = C.BEACH_Y - C.SEABED_Y
	t:FillBlock(
		CFrame.new(midX, C.SEABED_Y + beachH / 2, (C.BEACH_BACK_Z + C.BEACH_EDGE_Z) / 2),
		Vector3.new(width, beachH, C.BEACH_EDGE_Z - C.BEACH_BACK_Z),
		Enum.Material.Sand
	)

	-- the slope: a thick tilted block whose top runs from the beach edge
	-- down to the seabed. Tilting about X by +angle makes +Z go downhill.
	local run = C.SLOPE_FOOT_Z - C.BEACH_EDGE_Z
	local angle = math.atan2(beachH, run)
	local length = math.sqrt(run * run + beachH * beachH)
	local mid = Vector3.new(midX, C.SEABED_Y + beachH / 2, (C.BEACH_EDGE_Z + C.SLOPE_FOOT_Z) / 2)
	local onSlope = CFrame.new(mid) * CFrame.Angles(angle, 0, 0)
	t:FillBlock(onSlope * CFrame.new(0, -20, 0), Vector3.new(width, 40, length + 16), Enum.Material.Sand)

	-- rocky path down the middle of the slope, a little proud of the sand
	t:FillBlock(onSlope * CFrame.new(0, -1, 0), Vector3.new(14, 6, length + 8), Enum.Material.Rock)
	local rng = Random.new(31)
	for i = 0, 10 do
		local along = -length / 2 + i * length / 10
		for _, side in { -1, 1 } do
			local cf = onSlope * CFrame.new(side * rng:NextNumber(9, 12), 0.5, along)
			t:FillBall(cf.Position, rng:NextNumber(2.5, 4.5), Enum.Material.Rock)
		end
	end
	-- a sandstone landing where the path meets the seabed
	t:FillCylinder(
		CFrame.new(midX, C.SEABED_Y - 1, C.SLOPE_FOOT_Z + 6),
		2.5,
		14,
		Enum.Material.Sandstone
	)

	-- cliffs on both sides and at the back, so the cove is closed. Each spot
	-- gets a low boulder (no gap above the seabed) and a high one (above the
	-- water line).
	local function cliff(x: number, z: number)
		t:FillBall(Vector3.new(x, C.SEABED_Y + 10, z), rng:NextNumber(20, 26), Enum.Material.Rock)
		t:FillBall(Vector3.new(x, C.WATER_LEVEL - 10 + rng:NextNumber(-4, 8), z), rng:NextNumber(22, 30), Enum.Material.Rock)
	end
	for z = C.BEACH_BACK_Z, C.MAX_Z, 16 do
		cliff(C.MIN_X - 8 + rng:NextNumber(-4, 4), z)
		cliff(C.MAX_X + 8 + rng:NextNumber(-4, 4), z)
	end
	for x = C.MIN_X, C.MAX_X, 16 do
		cliff(x, C.MAX_Z + 8 + rng:NextNumber(-4, 4))
	end
	-- dunes and rocks along the back of the beach so nobody walks off it
	for x = C.MIN_X, C.MAX_X, 14 do
		local material = if rng:NextNumber() < 0.4 then Enum.Material.Rock else Enum.Material.Sand
		t:FillBall(Vector3.new(x, C.BEACH_Y, C.BEACH_BACK_Z - 4 + rng:NextNumber(-3, 3)), rng:NextNumber(10, 16), material)
	end

	-- a few rocky outcrops and sand dunes along the edges of the seabed
	local area = C.SEABED_AREA
	for _ = 1, 26 do
		local x, z
		if rng:NextNumber() < 0.5 then
			x = (if rng:NextNumber() < 0.5 then area.minX else area.maxX) + rng:NextNumber(-12, 12)
			z = rng:NextNumber(area.minZ + 10, area.maxZ)
		else
			x = rng:NextNumber(area.minX, area.maxX)
			z = area.maxZ + rng:NextNumber(-10, 15)
		end
		local material = if rng:NextNumber() < 0.6 then Enum.Material.Rock else Enum.Material.Sand
		t:FillBall(Vector3.new(x, C.SEABED_Y - 2, z), rng:NextNumber(6, 12), material)
	end
end

-------------------------------------------------------------------------------
-- beach: spawn, palms, sign
-------------------------------------------------------------------------------

local function palm(parent: Instance, base: Vector3, lean: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Palm"
	local cf = CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local trunk = Color3.fromRGB(150, 110, 70)
	for i = 1, 6 do
		local seg = CFrame.Angles(math.rad(lean), 0, 0) * CFrame.new(0, 2.6, 0)
		cf *= seg
		decor({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 2.2 - i * 0.12, 2.2 - i * 0.12),
			CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
			Color = if i % 2 == 0 then trunk else trunk:Lerp(Color3.new(0, 0, 0), 0.1),
			Material = Enum.Material.Wood,
			CanCollide = true,
			CastShadow = true,
		}, model)
	end
	local top = cf.Position + Vector3.new(0, 1, 0)
	for i = 1, 7 do
		local yaw = i / 7 * math.pi * 2
		decor({
			Name = "Leaf",
			Size = Vector3.new(2.4, 0.3, 9),
			CFrame = CFrame.new(top) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, -4),
			Color = Color3.fromRGB(70, 185, 80):Lerp(Color3.fromRGB(140, 220, 90), rng:NextNumber()),
			Material = Enum.Material.Grass,
			CastShadow = true,
		}, model)
	end
	for i = 1, 3 do
		decor({
			Name = "Coconut",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.2, 1.2, 1.2),
			CFrame = CFrame.new(top + Vector3.new(math.cos(i * 2.1) * 0.9, -0.6, math.sin(i * 2.1) * 0.9)),
			Color = Color3.fromRGB(110, 75, 45),
		}, model)
	end
	model.Parent = parent
end

local function buildBeach(map: Instance)
	local C = MapConfig
	local beach = Instance.new("Folder")
	beach.Name = "Beach"
	beach.Parent = map

	-- remove the template baseplate and spawn if the place has them
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local spawn = part({
		ClassName = "SpawnLocation",
		Name = "BeachSpawn",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 12, 12),
		CFrame = CFrame.new(C.SPAWN + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(250, 236, 190),
		Material = Enum.Material.Sand,
	}, beach) :: SpawnLocation
	spawn.Neutral = true
	spawn.Duration = 0

	local rng = Random.new(7)
	for _, spot in {
		Vector3.new(-40, C.BEACH_Y, -120),
		Vector3.new(-62, C.BEACH_Y, -100),
		Vector3.new(38, C.BEACH_Y, -138),
		Vector3.new(66, C.BEACH_Y, -108),
		Vector3.new(-90, C.BEACH_Y, -150),
		Vector3.new(100, C.BEACH_Y, -145),
	} do
		palm(beach, spot, rng:NextNumber(4, 9), rng)
	end

	-- beach umbrella and towel next to the spawn
	local umbrellaBase = Vector3.new(18, C.BEACH_Y, -118)
	decor({
		Name = "UmbrellaPole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9, 0.4, 0.4),
		CFrame = CFrame.new(umbrellaBase + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.new(1, 1, 1),
	}, beach)
	for i = 1, 8 do
		decor({
			Name = "UmbrellaPanel",
			Size = Vector3.new(3.4, 0.2, 5),
			CFrame = CFrame.new(umbrellaBase + Vector3.new(0, 9, 0))
				* CFrame.Angles(0, i / 8 * math.pi * 2, 0)
				* CFrame.Angles(math.rad(-20), 0, 0)
				* CFrame.new(0, 0, -2.4),
			Color = if i % 2 == 0 then Color3.fromRGB(255, 90, 90) else Color3.new(1, 1, 1),
			Material = Enum.Material.Fabric,
			CastShadow = true,
		}, beach)
	end
	decor({
		Name = "Towel",
		Size = Vector3.new(4, 0.1, 7),
		CFrame = CFrame.new(umbrellaBase + Vector3.new(4, 0.1, 2)) * CFrame.Angles(0, math.rad(20), 0),
		Color = Color3.fromRGB(80, 200, 255),
		Material = Enum.Material.Fabric,
	}, beach)

	-- welcome sign at the top of the path
	local signPos = Vector3.new(0, C.BEACH_Y, C.BEACH_EDGE_Z - 12)
	for _, x in { -5, 5 } do
		decor({
			Name = "SignPost",
			Size = Vector3.new(0.8, 7, 0.8),
			CFrame = CFrame.new(signPos + Vector3.new(x, 3.5, 0)),
			Color = Color3.fromRGB(140, 100, 60),
			Material = Enum.Material.Wood,
			CanCollide = true,
		}, beach)
	end
	local board = decor({
		Name = "WelcomeBoard",
		Size = Vector3.new(13, 5, 0.6),
		CFrame = CFrame.new(signPos + Vector3.new(0, 7, 0)),
		Color = Color3.fromRGB(190, 140, 85),
		Material = Enum.Material.Wood,
		CanCollide = true,
		CastShadow = true,
	}, beach)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = "BLOWFISH BLOWOUT\nSwim down to play!"
		local stroke = Instance.new("UIStroke")
		stroke.Color = OUTLINE
		stroke.Thickness = 4
		stroke.Parent = label
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.08, 0)
		pad.PaddingBottom = UDim.new(0.08, 0)
		pad.PaddingLeft = UDim.new(0.05, 0)
		pad.PaddingRight = UDim.new(0.05, 0)
		pad.Parent = label
		label.Parent = gui
		gui.Parent = board
	end
end

-------------------------------------------------------------------------------
-- rings
-------------------------------------------------------------------------------

local function buildChair(ringModel: Model, index: number, centre: Vector3, ranked: boolean, rng: Random)
	local C = MapConfig
	local angle = (index - 1) / C.SEATS * math.pi * 2
	local pos = centre + Vector3.new(math.cos(angle) * C.RING_RADIUS, 0, math.sin(angle) * C.RING_RADIUS)
	local base = CFrame.lookAt(pos, Vector3.new(centre.X, pos.Y, centre.Z))

	local chair = Instance.new("Model")
	chair.Name = "Chair" .. index
	chair:SetAttribute("Ranked", ranked)

	local colliders = Instance.new("Folder")
	colliders.Name = "Colliders"
	colliders.Parent = chair
	local function collider(name: string, size: Vector3, offset: CFrame)
		part({
			Name = name,
			Size = size,
			CFrame = base * offset,
			Transparency = 1,
			CanTouch = false,
			CastShadow = false,
		}, colliders)
	end
	collider("Base", Vector3.new(6, 2, 6), CFrame.new(0, 1, 0.3))
	collider("Back", Vector3.new(5.6, 6.4, 1.8), CFrame.new(0, 4.6, 2.6) * CFrame.Angles(math.rad(12), 0, 0))
	collider("ArmL", Vector3.new(1.8, 1.6, 5), CFrame.new(-2.85, 2.9, -0.4))
	collider("ArmR", Vector3.new(1.8, 1.6, 5), CFrame.new(2.85, 2.9, -0.4))

	local seat = part({
		ClassName = "Seat",
		Name = "Seat",
		Size = Vector3.new(3, 0.4, 3),
		CFrame = base * CFrame.new(0, 2.2, -0.4),
		Transparency = 1,
		CastShadow = false,
	}, chair) :: Seat
	seat:SetAttribute("SeatSkin", ChairSkins.DEFAULT)

	local skin = ChairSkins.build(ChairSkins.DEFAULT, base, { ranked = ranked, rng = rng })
	skin.Parent = chair

	chair.WorldPivot = base
	chair.Parent = ringModel
end

local function buildSign(ringModel: Model, centre: Vector3, ranked: boolean)
	local accent = if ranked then GOLD else AQUA
	local anchor = decor({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(centre + Vector3.new(0, 17, 0)),
		Transparency = 1,
	}, ringModel)

	-- a glowing halo under the sign so you can spot rings from far away
	local halo = decor({
		Name = "SignHalo",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 9, 9),
		CFrame = CFrame.new(centre + Vector3.new(0, 13.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	}, ringModel)
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Brightness = if ranked then 2.5 else 1.5
	light.Range = 22
	light.Parent = halo

	local gui = Instance.new("BillboardGui")
	gui.Name = "SignGui"
	gui.Size = UDim2.fromScale(15, 6) -- studs, so it shrinks with distance
	gui.LightInfluence = 0
	gui.MaxDistance = 320
	gui.AlwaysOnTop = false
	gui.Parent = anchor

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = if ranked
		then ColorSequence.new(Color3.fromRGB(255, 225, 110), Color3.fromRGB(240, 150, 30))
		else ColorSequence.new(Color3.fromRGB(110, 240, 245), Color3.fromRGB(40, 170, 230))
	gradient.Parent = card

	local function label(name: string, text: string, y: number, h: number)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.05, y)
		l.Size = UDim2.fromScale(0.9, h)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Text = text
		local s = Instance.new("UIStroke")
		s.Color = OUTLINE
		s.Thickness = 3
		s.Parent = l
		l.Parent = card
		return l
	end
	label("Title", if ranked then "★ RANKED ★" else "CASUAL", 0.08, 0.32)
	label("Status", "Open 0/" .. MapConfig.SEATS, 0.42, 0.5)
end

local function buildRingFloor(ringModel: Model, centre: Vector3, ranked: boolean, rng: Random)
	local C = MapConfig
	-- a smooth pale sand disc so each ring reads as a place
	decor({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, C.RING_RADIUS * 2 + 10, C.RING_RADIUS * 2 + 10),
		CFrame = CFrame.new(centre + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = if ranked then Color3.fromRGB(250, 228, 160) else Color3.fromRGB(246, 236, 200),
		Material = Enum.Material.Sand,
	}, ringModel)

	-- trim round the edge: gold blocks for Ranked, pale pebbles for casual
	local trimRadius = C.RING_RADIUS + 5
	local pieces = 28
	for i = 1, pieces do
		local a = (i - 0.5) / pieces * math.pi * 2
		local p = centre + Vector3.new(math.cos(a) * trimRadius, 0.25, math.sin(a) * trimRadius)
		if ranked then
			decor({
				Name = "GoldTrim",
				Size = Vector3.new(0.6, 0.6, trimRadius * 2 * math.pi / pieces + 0.2),
				CFrame = CFrame.lookAt(p, centre + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, math.rad(90), 0),
				Color = GOLD,
				Material = Enum.Material.Foil,
			}, ringModel)
		else
			local s = rng:NextNumber(1.2, 2)
			decor({
				Name = "Pebble",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(s, s, s),
				CFrame = CFrame.new(p),
				Color = Color3.fromRGB(225, 220, 210):Lerp(Color3.fromRGB(190, 230, 235), rng:NextNumber()),
				Material = Enum.Material.Slate,
			}, ringModel)
		end
	end
	if ranked then
		-- gold glow line just inside the trim
		decor({
			Name = "GoldGlow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, trimRadius * 2 - 1, trimRadius * 2 - 1),
			CFrame = CFrame.new(centre + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 220, 120),
			Material = Enum.Material.Neon,
			Transparency = 0.7,
		}, ringModel)
	end
end

local function buildRing(rings: Instance, info, rng: Random)
	local centre = MapConfig.ringCentre(info)
	local model = Instance.new("Model")
	model.Name = info.name
	model:SetAttribute("Ranked", info.ranked)
	model:SetAttribute("Capacity", MapConfig.SEATS)

	local mid = decor({
		Name = "Centre",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(centre + Vector3.new(0, 3, 0)),
		Transparency = 1,
	}, model)
	model.PrimaryPart = mid

	buildRingFloor(model, centre, info.ranked, rng)
	for i = 1, MapConfig.SEATS do
		buildChair(model, i, centre, info.ranked, rng)
	end
	buildSign(model, centre, info.ranked)

	model.Parent = rings
end

-------------------------------------------------------------------------------

function MapBuilder.build()
	local started = os.clock()
	buildLighting()
	buildTerrain()

	local map = workspace:FindFirstChild("Map") or Instance.new("Folder")
	map.Name = "Map"
	map:ClearAllChildren()
	map.Parent = workspace
	buildBeach(map)

	-- RingService picks up every child of workspace.Rings. If the place
	-- already has rings (hand-built in Studio), leave them alone.
	local rings = workspace:FindFirstChild("Rings")
	if rings and #rings:GetChildren() > 0 then
		print("[MapBuilder] workspace.Rings already has rings; not building new ones")
	else
		if not rings then
			rings = Instance.new("Folder")
			rings.Name = "Rings"
			rings.Parent = workspace
		end
		local rng = Random.new(2024)
		for _, info in MapConfig.RINGS do
			buildRing(rings, info, rng)
		end
	end

	print(string.format("[MapBuilder] map built in %d ms", math.floor((os.clock() - started) * 1000)))
end

return MapBuilder
