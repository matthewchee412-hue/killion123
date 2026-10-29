--[[
	FeedFormat — turns a ring feed event into one commentary line.

	The server sends feed events through RingUpdate ({ kind = "feed", event = ... });
	the client feed and the server log both use FeedFormat.line(event).
	No Roblox services, so it runs under Lune too.
]]

local FeedFormat = {}

local function s(n: number): string
	if n == math.floor(n) then
		return string.format("%d s", n)
	end
	return string.format("%.1f s", n)
end

local function coins(n: number): string
	return string.format("+%d coin%s", n, if n == 1 then "" else "s")
end

local WRONG = {
	unknown = "✗",
	empty = "✗",
	used = "already said!",
	filtered = "✗",
}

local PASS = {
	clockwise = "passes to",
	picked = "picks",
	timeout = "ran out of time, it goes to",
}

local DIVE_MISS = {
	timeout = "5 s passed",
	shallow = "not deep enough",
}

function FeedFormat.line(e): string
	local kind = e.kind
	if kind == "answer" then
		local said = e.display
		if e.lucky then
			said = string.format("%s → %s ✨ LUCKY!", e.from or e.text, e.display)
		end
		local tail
		if e.dive == "miss" then
			tail = string.format("%s · dive missed", e.tierName)
		else
			tail = string.format("%s %s", e.tierName, coins(e.coins))
			if e.deflate > 0 then
				tail ..= string.format(", -%s air", s(e.deflate))
			end
			if e.dive == "hit" then
				tail ..= " · DIVE x2!"
			end
		end
		return string.format("%s: %s · %s", e.name, said, tail)
	elseif kind == "wrong" then
		local shown = if e.reason == "used" and e.display then e.display else e.text
		return string.format("%s: %s %s", e.name, shown, WRONG[e.reason] or "✗")
	elseif kind == "pass" then
		if e.how == "start" then
			return string.format("%s starts with the blowfish", e.toName)
		end
		local line = string.format("%s %s %s", e.fromName, PASS[e.how] or "passes to", e.toName)
		if e.bonus and e.bonus > 0 then
			line ..= string.format(" (+%s air)", s(e.bonus))
		end
		return line
	elseif kind == "picking" then
		return string.format("%s is picking who gets the blowfish…", e.name)
	elseif kind == "dive" then
		return string.format("%s dives deeper! 🤿", e.name)
	elseif kind == "diveMiss" then
		return string.format("%s's dive missed (%s): +%s air", e.name, DIVE_MISS[e.why] or e.why, s(e.air))
	elseif kind == "pop" then
		return string.format("💥 POP! %s is out", e.name)
	elseif kind == "left" then
		return string.format("%s stood up and popped", e.name)
	elseif kind == "round" then
		return string.format("Round %d: %s", e.number, e.prompt)
	elseif kind == "countdown" then
		return string.format("Starting in %s", s(e.seconds))
	elseif kind == "countdownCancelled" then
		return "Not enough players, waiting…"
	elseif kind == "matchStart" then
		return string.format("%s game with %d players!", if e.ranked then "Ranked" else "Casual", e.players)
	elseif kind == "win" then
		return string.format("🏆 %s wins!", e.name)
	elseif kind == "noWinner" then
		return "Nobody is left. No winner this time"
	end
	return tostring(kind)
end

return FeedFormat
