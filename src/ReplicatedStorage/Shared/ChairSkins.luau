--[[
	ChairSkins — the look of the boulder armchairs, kept apart from the seat.

	A chair is a Model built by the map:
		Chair (Model, WorldPivot = ground centre, facing the ring centre)
		├─ Seat        the real Seat (SeatSkin attribute = skin name)
		├─ Colliders   invisible blocks so you can't walk through the rock
		└─ Skin        what you see; ChairSkins.apply swaps only this

	Skins come from, in order:
	1. ReplicatedStorage.ChairMeshes.<name>: a Model made in Studio (e.g. from
	   generated meshes). Its pivot must be the chair's ground centre with the
	   front (where you sit) facing -Z. See TODO-studio.md, section 5.
	2. The part-built skins below.

	Chair local space: origin on the ground, -Z = front, +Z = back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChairSkins = {}

ChairSkins.DEFAULT = "Default"

local STONES = {
	Color3.fromRGB(186, 172, 152),
	Color3.fromRGB(170, 160, 150),
	Color3.fromRGB(196, 180, 156),
	Color3.fromRGB(160, 152, 146),
}
local GOLD = Color3.fromRGB(255, 196, 60)
local MOSS = Color3.fromRGB(120, 190, 110)

local function shade(c: Color3, k: number): Color3
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

-- a part drawn as an ellipsoid of the given size
local function blob(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Rock
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	p.Parent = parent
	return p
end

local builders = {}

-- a rounded stone lounge chair: lumpy boulder base, scooped seat, a high
-- rounded back leaning back, and two thick arm rests
function builders.Default(skin: Model, base: CFrame, opts)
	local rng = opts.rng or Random.new()
	local stone = STONES[rng:NextInteger(1, #STONES)]
	local dark = shade(stone, 0.82)
	local light = shade(stone, 1.08)
	local function at(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	local lean = CFrame.Angles(math.rad(12), 0, 0) -- top of the back leans away from the ring

	-- boulder base and lumps around it
	blob(skin, "Base", Vector3.new(6.6, 3.2, 6.4), at(0, 1.2, 0.3), stone)
	blob(skin, "LumpL", Vector3.new(2.8, 2.2, 2.8), at(-2.7, 0.7, -1.9), dark)
	blob(skin, "LumpR", Vector3.new(2.6, 2.0, 2.6), at(2.8, 0.6, -1.6), dark)
	blob(skin, "LumpBack", Vector3.new(4.2, 2.6, 3.0), at(0.4, 0.8, 2.9), dark)

	-- the scooped seat: a darker, flatter dish sunk into the top
	blob(skin, "SeatDish", Vector3.new(4.2, 1.0, 4.0), at(0, 2.45, -0.4), dark, Enum.Material.Slate)

	-- high back with a darker hollow on the inside
	blob(skin, "Back", Vector3.new(6.2, 7.4, 2.6), at(0, 4.4, 2.5) * lean, stone)
	blob(skin, "BackHollow", Vector3.new(4.6, 5.6, 1.1), at(0, 4.7, 1.35) * lean, dark, Enum.Material.Slate)

	-- arm rests with rounded fronts
	for _, side in { -1, 1 } do
		blob(skin, "Arm", Vector3.new(2.0, 2.2, 5.6), at(side * 2.85, 3.0, -0.1), light)
		blob(skin, "ArmEnd", Vector3.new(2.2, 2.4, 1.8), at(side * 2.85, 2.9, -2.6), stone)
	end

	-- a bit of moss on top so it looks like it's been here a while
	blob(skin, "Moss", Vector3.new(2.4, 0.7, 1.6), at(rng:NextNumber(-1.5, 1.5), 7.9, 3.3) * lean, MOSS, Enum.Material.Grass)

	if opts.ranked then
		-- gold caps on the arms and a gold band round the base
		for _, side in { -1, 1 } do
			blob(skin, "GoldCap", Vector3.new(1.5, 0.9, 1.5), at(side * 2.85, 4.15, -2.6), GOLD, Enum.Material.Foil)
		end
		local band = Instance.new("Part")
		band.Name = "GoldBand"
		band.Anchored = true
		band.CanCollide = false
		band.CanTouch = false
		band.CanQuery = false
		band.Shape = Enum.PartType.Cylinder
		band.Size = Vector3.new(0.4, 7.6, 7.6)
		band.CFrame = at(0, 0.2, 0.3) * CFrame.Angles(0, 0, math.rad(90))
		band.Color = GOLD
		band.Material = Enum.Material.Foil
		band.Parent = skin
	end
end

function ChairSkins.has(name: string): boolean
	local meshes = ReplicatedStorage:FindFirstChild("ChairMeshes")
	return builders[name] ~= nil or (meshes ~= nil and meshes:FindFirstChild(name) ~= nil)
end

-- build the Skin model for a chair whose ground centre is `base`
function ChairSkins.build(name: string, base: CFrame, opts): Model
	opts = opts or {}
	local skin: Model
	local meshes = ReplicatedStorage:FindFirstChild("ChairMeshes")
	local template = meshes and meshes:FindFirstChild(name)
	if template and template:IsA("Model") then
		skin = template:Clone()
		skin:PivotTo(base)
		for _, d in skin:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
			end
		end
	else
		skin = Instance.new("Model")
		local build = builders[name] or builders[ChairSkins.DEFAULT]
		build(skin, base, opts)
	end
	skin.Name = "Skin"
	skin:SetAttribute("SkinName", name)
	return skin
end

-- swap the look of an existing chair (cosmetics); the Seat stays put
function ChairSkins.apply(chair: Model, name: string)
	local old = chair:FindFirstChild("Skin")
	local skin = ChairSkins.build(name, chair.WorldPivot, { ranked = chair:GetAttribute("Ranked") == true })
	if old then
		old:Destroy()
	end
	skin.Parent = chair
	local seat = chair:FindFirstChildOfClass("Seat")
	if seat then
		seat:SetAttribute("SeatSkin", name)
	end
end

return ChairSkins
