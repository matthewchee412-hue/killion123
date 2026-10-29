--[[
	RingSign — the text on the sign above a ring, from its attributes.
	No Roblox services, so Lune can test it.

	text(phase, seated, capacity, endsAt, now) ->
		"Open 3/8", "Starting 0:08" or "In game"
]]

local RingSign = {}

function RingSign.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function RingSign.text(phase: string?, seated: number?, capacity: number, endsAt: number?, now: number): string
	if phase == "countdown" then
		return "Starting " .. RingSign.clock((endsAt or now) - now)
	elseif phase == nil or phase == "waiting" then
		return string.format("Open %d/%d", seated or 0, capacity)
	end
	return "In game"
end

-- "open", "starting" or "playing", for the sign's colour
function RingSign.state(phase: string?): string
	if phase == "countdown" then
		return "starting"
	elseif phase == nil or phase == "waiting" then
		return "open"
	end
	return "playing"
end

return RingSign
