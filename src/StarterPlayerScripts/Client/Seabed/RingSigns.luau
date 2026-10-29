--[[
	RingSigns — keeps the sign above every ring up to date on this client:
	"Open 3/8", "Starting 0:08" or "In game". It reads the attributes that
	RingService sets on each ring model (Phase, Seated, EndsAt) and counts
	down with server time. The halo under the sign pulses while starting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RingSign = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RingSign"))

local RingSigns = {}

local STATUS_COLOR = {
	open = Color3.new(1, 1, 1),
	starting = Color3.fromRGB(255, 240, 120),
	playing = Color3.fromRGB(255, 200, 200),
}

type Sign = { model: Model, status: TextLabel, halo: BasePart?, capacity: number }
local signs: { Sign } = {}

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	task.spawn(function()
		local anchor = model:WaitForChild("Sign", 30)
		local gui = anchor and anchor:WaitForChild("SignGui", 30)
		local card = gui and gui:WaitForChild("Card", 30)
		local status = card and card:WaitForChild("Status", 30)
		if not (status and status:IsA("TextLabel")) then
			return
		end
		local capacity = model:GetAttribute("Capacity")
		if type(capacity) ~= "number" then
			capacity = 0
			for _, d in model:GetDescendants() do
				if d:IsA("Seat") then
					capacity += 1
				end
			end
		end
		local halo = model:FindFirstChild("SignHalo")
		table.insert(signs, {
			model = model,
			status = status,
			halo = if halo and halo:IsA("BasePart") then halo else nil,
			capacity = capacity,
		})
	end)
end

function RingSigns.init()
	local rings = workspace:WaitForChild("Rings")
	for _, model in rings:GetChildren() do
		track(model)
	end
	rings.ChildAdded:Connect(track)
end

function RingSigns.step(t: number)
	local now = workspace:GetServerTimeNow()
	for i = #signs, 1, -1 do
		local sign = signs[i]
		if sign.model.Parent == nil then
			table.remove(signs, i)
			continue
		end
		local m = sign.model
		local phase = m:GetAttribute("Phase")
		local text = RingSign.text(phase, m:GetAttribute("Seated"), sign.capacity, m:GetAttribute("EndsAt"), now)
		if sign.status.Text ~= text then
			sign.status.Text = text
		end
		local state = RingSign.state(phase)
		sign.status.TextColor3 = STATUS_COLOR[state]
		if sign.halo then
			sign.halo.Transparency = if state == "starting" then 0.25 + 0.25 * math.sin(t * 6) else 0.35
		end
	end
end

return RingSigns
