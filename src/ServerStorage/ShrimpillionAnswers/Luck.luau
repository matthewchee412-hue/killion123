--[[
	Luck — turns answers into better ones, like Krillion turning "chile soup"
	into some random dish.

	Two things can happen when a player with luck answers:
	  1. RESCUE  — their answer isn't in the bank, but luck swaps it for a
	               random unused Shallows/Reef answer so they still pass.
	  2. UPGRADE — their answer is good, and luck swaps it for a random unused
	               answer one tier deeper (Reef -> Twilight, and so on).
	Abyss answers can't upgrade. Pass mayRescue=false when Roblox's text filter
	tagged what they typed (hashes), so rude words never get rescued.

	Players get luck levels 0..5 from Luck Potions (earned or bought).
	Roblox rules: anything bought with Robux that changes odds must show the
	exact chances, so the shop reads Luck.CHANCES directly for its odds table
	(Luck.oddsText). Change the numbers here and the shop updates too.

	Usage (server):
		local result = Luck.submit(round, text, player:GetAttribute("Luck") or 0, filterWasClean)
		-- result.lucky = "rescue" | "upgrade" | nil, result.originalDisplay = what they typed resolved to
]]

local Matcher = require(script.Parent.AnswerMatcher)

local Luck = {}

Luck.MAX = 5

-- [level] = { rescue = chance, upgrade = chance }
Luck.CHANCES = {
	[0] = { rescue = 0.00, upgrade = 0.00 },
	[1] = { rescue = 0.10, upgrade = 0.04 },
	[2] = { rescue = 0.20, upgrade = 0.08 },
	[3] = { rescue = 0.30, upgrade = 0.12 },
	[4] = { rescue = 0.40, upgrade = 0.16 },
	[5] = { rescue = 0.50, upgrade = 0.20 },
}

local RESCUE_MAX_TIER = 1 -- rescued answers are Shallows or Reef, never a free rare
local MIN_RESCUE_LEN = 3  -- "a" or "ok" never gets rescued

local defaultRng = Random.new()

function Luck.chances(level: number)
	return Luck.CHANCES[math.clamp(math.floor(level or 0), 0, Luck.MAX)]
end

-- Lines for the shop's odds panel, e.g. "Luck 3: 30% rescue, 12% upgrade"
function Luck.oddsText(): { string }
	local lines = {}
	for lvl = 1, Luck.MAX do
		local c = Luck.CHANCES[lvl]
		table.insert(lines, string.format(
			"Luck %d: %d%% chance a wrong answer is saved, %d%% chance a right answer goes one tier deeper",
			lvl, math.round(c.rescue * 100), math.round(c.upgrade * 100)))
	end
	return lines
end

local function randomUnused(bank, used, minTier: number, maxTier: number, rng: Random): number?
	local pool = {}
	for i, e in bank.entries do
		if e.tier >= minTier and e.tier <= maxTier and not used[i] and not used[e.keys[1]] then
			table.insert(pool, i)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

local function swapTo(round, result, idx: number, kind: string)
	local bank = Matcher.getBank(round.categoryId)
	local e = bank.entries[idx]
	result.originalDisplay = result.display or result.input
	result.ok = true
	result.reason = "ok"
	result.display = e.display
	result.tier = e.tier
	result.entryIndex = idx
	result.matchedKey = e.keys[1]
	result.corrected = true
	result.lucky = kind
	return result
end

-- Like round:submit(text), but rolls luck first.
function Luck.submit(round, text: string, level: number, mayRescue: boolean?, rng: Random?)
	local r = rng or defaultRng
	local c = Luck.chances(level)
	local result = Matcher.check(round.categoryId, text, round.used)
	local bank = Matcher.getBank(round.categoryId)

	if result.ok and result.tier and result.tier < 4 and c.upgrade > 0 and r:NextNumber() < c.upgrade then
		local t = result.tier + 1
		local idx = randomUnused(bank, round.used, t, t, r)
		if idx then
			-- also burn what they actually typed, so nobody else gets it free
			if result.entryIndex then
				round.used[result.entryIndex] = true
			end
			swapTo(round, result, idx, "upgrade")
		end
	elseif result.reason == "unknown" and mayRescue ~= false and c.rescue > 0
		and #Matcher.normalize(text) >= MIN_RESCUE_LEN and r:NextNumber() < c.rescue then
		local idx = randomUnused(bank, round.used, 0, RESCUE_MAX_TIER, r)
		if idx then
			swapTo(round, result, idx, "rescue")
		end
	end

	if result.ok and result.entryIndex then
		local e = bank.entries[result.entryIndex]
		round.used[result.entryIndex] = true
		round.used[e.keys[1]] = true
		if result.matchedKey then
			round.used[result.matchedKey] = true
		end
		table.insert(round.history, result)
	end
	return result
end

return Luck
