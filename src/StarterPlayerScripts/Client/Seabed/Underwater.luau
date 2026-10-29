--[[
	Underwater — the look of the sea, on this client only.

	- When the camera goes under the water line, a soft blue-green
	  ColorCorrection fades in and the Atmosphere turns turquoise. Both fade
	  back out above water. It stays bright: no dark tint, no heavy fog.
	- God rays: wide glowing beams slanting down from the surface, gently
	  shimmering.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Underwater = {}

local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ABOVE -- copied from the server's Atmosphere at init
local BELOW = {
	Density = 0.36,
	Offset = 0,
	Color = Color3.fromRGB(150, 235, 230),
	Decay = Color3.fromRGB(70, 200, 210),
	Haze = 1.4,
	Glare = 0,
}

local MapConfig
local tint: ColorCorrectionEffect
local atmosphere: Atmosphere?
local under: boolean? = nil
local rays = {}

local function buildRays(rng: Random)
	local terrain = workspace.Terrain
	local sun = Vector3.new(10, 0, 14) -- how far the bottom of each ray slides from its top
	local area = MapConfig.SEABED_AREA
	for i = 1, 14 do
		local x = rng:NextNumber(area.minX + 10, area.maxX - 10)
		local z = rng:NextNumber(area.minZ - 10, area.maxZ - 20)
		local top = Instance.new("Attachment")
		top.Name = "RayTop"
		top.Position = Vector3.new(x, MapConfig.WATER_LEVEL - 1, z)
		top.Parent = terrain
		local bottom = Instance.new("Attachment")
		bottom.Name = "RayBottom"
		bottom.Position = Vector3.new(x, MapConfig.SEABED_Y + 1, z) + sun
		bottom.Parent = terrain

		local beam = Instance.new("Beam")
		beam.Name = "GodRay"
		beam.Attachment0 = top
		beam.Attachment1 = bottom
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = rng:NextNumber(7, 12)
		beam.Width1 = rng:NextNumber(16, 26)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 235), Color3.fromRGB(190, 255, 250))
		beam.Parent = terrain
		table.insert(rays, { beam = beam, phase = rng:NextNumber(0, math.pi * 2), speed = rng:NextNumber(0.25, 0.5) })
	end
end

function Underwater.init(rng: Random, config)
	MapConfig = config
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		ABOVE = {
			Density = atmosphere.Density,
			Offset = atmosphere.Offset,
			Color = atmosphere.Color,
			Decay = atmosphere.Decay,
			Haze = atmosphere.Haze,
			Glare = atmosphere.Glare,
		}
	end

	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "UnderwaterTint"
	tint.TintColor = Color3.new(1, 1, 1)
	tint.Brightness = 0
	tint.Contrast = 0
	tint.Saturation = 0
	tint.Enabled = true
	tint.Parent = Lighting

	buildRays(rng)
end

local function setUnder(value: boolean)
	if under == value then
		return
	end
	under = value
	if value then
		TweenService:Create(tint, FADE, {
			TintColor = Color3.fromRGB(205, 245, 240),
			Brightness = 0.05,
			Contrast = 0.05,
			Saturation = 0.15,
		}):Play()
	else
		TweenService:Create(tint, FADE, {
			TintColor = Color3.new(1, 1, 1),
			Brightness = 0,
			Contrast = 0,
			Saturation = 0,
		}):Play()
	end
	if atmosphere == nil or atmosphere.Parent == nil then
		atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	end
	if atmosphere and ABOVE then
		TweenService:Create(atmosphere, FADE, if value then BELOW else ABOVE):Play()
	end
end

function Underwater.step(t: number, camPos: Vector3)
	setUnder(MapConfig.isUnderwater(camPos))
	for _, ray in rays do
		local a = 0.55 + 0.15 * math.sin(t * ray.speed + ray.phase)
		ray.beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, a),
			NumberSequenceKeypoint.new(0.6, math.min(1, a + 0.25)),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
end

return Underwater
