--[[
	AnswerMatcher — checks typed answers against the Shrimpillion answer banks.

	Server-side only (keep the banks in ServerStorage so exploiters can't read them).

	local Matcher = require(ServerStorage.ShrimpillionAnswers.AnswerMatcher)

	local round = Matcher.newRound("sea_creatures")   -- tracks used answers for one round
	local result = round:submit("octopuss")
	-- result.ok        true if the answer counts
	-- result.reason    "ok" | "used" | "unknown" | "empty"
	-- result.display   canonical name to show everyone ("Octopus")
	-- result.tier      0..4 (see Rarity module; 4 = Abyss, the rarest)
	-- result.corrected true if a typo/plural was forgiven
	-- result.matchedKey the normalised spelling that matched

	Matcher.check(categoryId, text, usedSet?) is the stateless version.

	IMPORTANT: run the raw text through TextService:FilterStringAsync before
	showing it to other players. Use result.display (from our bank) for the
	"X said Y" feed where possible — it is already clean.
]]

local Categories = require(script.Parent.Categories)
local Blocklist = require(script.Parent.Blocklist)
local CommonWordsBlob = require(script.Parent.CommonWords) :: string
local BanksFolder = script.Parent:WaitForChild("Banks")

export type Entry = {
	display: string,
	tier: number,
	keys: { string },
	index: number,
}

export type Bank = {
	id: string,
	name: string,
	prompt: string,
	entries: { Entry },
	byKey: { [string]: { number } }, -- key -> entry indexes (a nickname can belong to 2 answers)
	byLength: { [number]: { string } }, -- key length -> keys (for typo search)
	byHead: { [string]: { number } }, -- distinctive first word of a longer name -> entries
}

export type Result = {
	ok: boolean,
	reason: string,
	display: string?,
	tier: number?,
	entryIndex: number?,
	matchedKey: string?,
	corrected: boolean,
	partial: boolean?, -- matched on the first word of a longer answer ("infraorbital")
	input: string,
}

local Matcher = {}

local cache: { [string]: Bank } = {}

-------------------------------------------------------------------------------
-- normalising
-------------------------------------------------------------------------------

local ACCENTS: { [string]: string } = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ã"] = "a", ["å"] = "a", ["ā"] = "a",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["ē"] = "e",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["ī"] = "i",
	["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["ö"] = "o", ["õ"] = "o", ["ø"] = "o", ["ō"] = "o",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ū"] = "u",
	["ñ"] = "n", ["ç"] = "c", ["ß"] = "ss", ["æ"] = "ae", ["œ"] = "oe", ["ð"] = "d", ["þ"] = "th",
	["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ñ"] = "n", ["Ö"] = "o", ["Ü"] = "u",
}

-- "The Octopus!" -> "octopus" ; "Rock & Roll" -> "rockandroll"
function Matcher.normalize(text: string): string
	local s = string.lower(text)
	s = string.gsub(s, "[\128-\255][\128-\191]*", function(ch)
		return ACCENTS[ch] or ""
	end)
	s = string.gsub(s, "&", "and")
	s = string.gsub(s, "[^%w]", "")
	return s
end

local function stripArticle(text: string): string
	local lower = string.lower(text)
	for _, art in { "the ", "a ", "an " } do
		if string.sub(lower, 1, #art) == art then
			return string.sub(text, #art + 1)
		end
	end
	return text
end

-- ~30k everyday English words. If someone types one of these and it isn't an
-- answer, we never "fix" it into one: "taking" must not become "Takin",
-- "whether" must not become "Wether", "private" must not become "Primate".
local commonWords: { [string]: boolean }? = nil
local function isCommonWord(key: string): boolean
	if not commonWords then
		local set = {}
		for _, w in string.split(CommonWordsBlob, " ") do
			set[w] = true
		end
		commonWords = set
	end
	return (commonWords :: { [string]: boolean })[key] == true
end

-------------------------------------------------------------------------------
-- loading banks
-------------------------------------------------------------------------------

local function parseInto(bank: Bank, blob: string, blocked: { [string]: boolean })
	for line in string.gmatch(blob, "[^\n]+") do
		local tier = tonumber(string.sub(line, 1, 1)) or 4
		local names = string.split(string.sub(line, 2), "|")
		local display = names[1]
		if not blocked[Matcher.normalize(display)] then
			local index = #bank.entries + 1
			local keys = {}
			for n, name in names do
				-- "Infraorbital nerve" can also be answered with just "infraorbital",
				-- but only when that first word isn't an everyday word ("golden", "blue")
				local words = string.split((string.gsub(name, "%-", " ")), " ")
				if #words > 1 then
					local head = Matcher.normalize(words[1])
					if #head >= 5 and not isCommonWord(head) and not blocked[head] then
						local hl = bank.byHead[head]
						if not hl then
							hl = {}
							bank.byHead[head] = hl
						end
						if not table.find(hl, index) then
							table.insert(hl, index)
						end
					end
				end
				local k = Matcher.normalize(name)
				if #k > 0 and not blocked[k] and not table.find(keys, k) then
					table.insert(keys, k)
					local list = bank.byKey[k]
					if not list then
						list = {}
						bank.byKey[k] = list
						local L = #k
						bank.byLength[L] = bank.byLength[L] or {}
						table.insert(bank.byLength[L], k)
					end
					if n == 1 then
						-- an answer's own name beats someone else's nickname:
						-- "seahorse" is the Seahorse, not the walrus (whose old nickname is seahorse)
						local pos = 1
						while pos <= #list and bank.entries[list[pos]].keys[1] == k do
							pos += 1
						end
						table.insert(list, pos, index)
					else
						table.insert(list, index)
					end
				end
			end
			table.insert(bank.entries, { display = display, tier = tier, keys = keys, index = index })
		end
	end
end

function Matcher.getBank(categoryId: string): Bank
	local cached = cache[categoryId]
	if cached then
		return cached
	end
	local info = Categories.byId[categoryId]
	assert(info, "Unknown category: " .. tostring(categoryId))

	local blocked: { [string]: boolean } = {}
	for _, list in { Blocklist.all or {}, Blocklist[categoryId] or {} } do
		for _, name in list do
			blocked[Matcher.normalize(name)] = true
		end
	end

	local bank: Bank = {
		id = categoryId,
		name = info.name,
		prompt = info.prompt,
		entries = {},
		byKey = {},
		byLength = {},
		byHead = {},
	}
	for part = 1, info.parts do
		local moduleName = if info.parts == 1 then "Bank_" .. categoryId else ("Bank_" .. categoryId .. "_" .. part)
		local blob = require(BanksFolder:WaitForChild(moduleName)) :: string
		parseInto(bank, blob, blocked)
	end
	cache[categoryId] = bank
	return bank
end

-- Load every bank up front (e.g. at server start) so the first round has no hitch.
function Matcher.preloadAll()
	for _, info in Categories.list do
		Matcher.getBank(info.id)
	end
end

-------------------------------------------------------------------------------
-- typo tolerance
-------------------------------------------------------------------------------

-- Damerau-Levenshtein (optimal string alignment) with an early exit once the
-- distance is guaranteed to exceed maxDist.
local function editDistance(a: string, b: string, maxDist: number): number
	local la, lb = #a, #b
	if math.abs(la - lb) > maxDist then
		return maxDist + 1
	end
	local prevPrev: { number } = {}
	local prev: { number } = {}
	for j = 0, lb do
		prev[j] = j
	end
	for i = 1, la do
		local cur: { number } = { [0] = i }
		local rowMin = i
		local ai = string.byte(a, i)
		for j = 1, lb do
			local bj = string.byte(b, j)
			local cost = if ai == bj then 0 else 1
			local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
			if i > 1 and j > 1 and ai == string.byte(b, j - 1) and string.byte(a, i - 1) == bj then
				v = math.min(v, prevPrev[j - 2] + 1)
			end
			cur[j] = v
			if v < rowMin then
				rowMin = v
			end
		end
		if rowMin > maxDist then
			return maxDist + 1
		end
		prevPrev = prev
		prev = cur
	end
	return prev[lb]
end

local function allowedTypos(len: number): number
	if len >= 10 then
		return 2
	elseif len >= 6 then
		return 1
	end
	return 0 -- short words are too easy to turn into a different real word ("table" -> "sable")
end

local IRREGULAR: { [string]: string } = {
	mice = "mouse", geese = "goose", teeth = "tooth", feet = "foot", oxen = "ox",
	children = "child", people = "person", men = "man", women = "woman", lice = "louse",
	octopi = "octopus", cacti = "cactus", fungi = "fungus", hippopotami = "hippopotamus",
	platypi = "platypus", fish = "fish", sheep = "sheep", deer = "deer", moose = "moose",
	squid = "squid", shrimps = "shrimp", prawns = "prawn", dice = "die", larvae = "larva",
	antennae = "antenna", vertebrae = "vertebra", phenomena = "phenomenon",
}

-- Singular/plural guesses: "octopuses" -> "octopus", "berries" -> "berry",
-- "wolves" -> "wolf", "boxes" -> "box", "cacti" -> "cactus".
-- If the typed word is an everyday English word we only ever make it singular,
-- never plural ("are" must not become "Ares").
local function variants(k: string, common: boolean): { string }
	local out = {}
	local function add(v: string)
		if #v >= 3 then
			table.insert(out, v)
		end
	end
	-- irregular plural as the last word: "giant octopi" -> "giantoctopus"
	for plural, single in IRREGULAR do
		if #k >= #plural and string.sub(k, -#plural) == plural and plural ~= single then
			add(string.sub(k, 1, #k - #plural) .. single)
		end
	end
	if string.sub(k, -3) == "ves" then
		add(string.sub(k, 1, -4) .. "f")
		add(string.sub(k, 1, -4) .. "fe")
	end
	if string.sub(k, -3) == "ies" then
		add(string.sub(k, 1, -4) .. "y")
	end
	if string.sub(k, -2) == "es" then
		-- only after s, x, z, ch, sh, o: "boxes" -> "box", but "rates" is not "rat"
		local stem = string.sub(k, 1, -3)
		local last1, last2 = string.sub(stem, -1), string.sub(stem, -2)
		if last1 == "s" or last1 == "x" or last1 == "z" or last1 == "o" or last2 == "ch" or last2 == "sh" then
			add(stem)
		end
	end
	if string.sub(k, -1) == "s" and string.sub(k, -2) ~= "ss" then
		add(string.sub(k, 1, -2))
	end
	if not common then
		if string.sub(k, -1) == "y" then
			add(string.sub(k, 1, -2) .. "ies")
		end
		add(k .. "s")
		add(k .. "es")
	end
	return out
end

-------------------------------------------------------------------------------
-- checking
-------------------------------------------------------------------------------

-- `used` holds both entry indexes (number keys) and spellings already typed this
-- round (string keys), so "anteater" can't be cashed in once for the aardvark,
-- again for the pangolin and again for the echidna.
export type UsedSet = { [any]: boolean }

local function pickEntry(bank: Bank, key: string, used: UsedSet?): (number?, boolean)
	-- returns entry index, and whether that answer was already used
	local list = bank.byKey[key]
	if not list then
		return nil, false
	end
	if used and used[key] then
		return list[1], true
	end
	for _, idx in list do
		if not used or not used[idx] then
			return idx, false
		end
	end
	return list[1], true
end

local function fuzzyKey(bank: Bank, key: string): string?
	local maxDist = allowedTypos(#key)
	if maxDist == 0 then
		return nil
	end
	local best: string? = nil
	local bestDist = maxDist + 1
	local tie = false
	local first = string.sub(key, 1, 1)
	for L = #key - maxDist, #key + maxDist do
		local bucket = bank.byLength[L]
		if bucket then
			for _, cand in bucket do
				-- people almost never get the first letter wrong; requiring it also
				-- stops one real word being "corrected" into a different one
				if string.sub(cand, 1, 1) == first then
					local d = editDistance(key, cand, maxDist)
					if d < bestDist then
						best, bestDist, tie = cand, d, false
					elseif d == bestDist and best ~= nil and bank.byKey[cand][1] ~= bank.byKey[best :: string][1] then
						tie = true
					end
				end
			end
		end
	end
	if tie then
		return nil -- two different answers are equally close: don't guess
	end
	return best
end

function Matcher.check(categoryId: string, text: string, used: UsedSet?): Result
	local bank = Matcher.getBank(categoryId)
	local raw = stripArticle(text)
	local key = Matcher.normalize(raw)
	if #key == 0 then
		return { ok = false, reason = "empty", corrected = false, input = text }
	end

	local function finish(k: string, corrected: boolean): Result?
		local idx, allUsed = pickEntry(bank, k, used)
		if not idx then
			return nil
		end
		local e = bank.entries[idx]
		local tier = e.tier
		return {
			ok = not allUsed,
			reason = if allUsed then "used" else "ok",
			display = e.display,
			tier = tier,
			entryIndex = idx,
			matchedKey = k,
			corrected = corrected,
			input = text,
		}
	end

	-- 1. exact
	local r = finish(key, false)
	if r then
		return r
	end
	local common = isCommonWord(key)
	-- 2. plural / singular
	for _, v in variants(key, common) do
		r = finish(v, true)
		if r then
			return r
		end
	end
	-- 3. typo (never for real words: "castle" is not a typo of "cattle")
	local fk = if common then nil else fuzzyKey(bank, key)
	if fk then
		r = finish(fk, true)
		if r then
			return r
		end
	end
	-- 4. first word of a longer answer ("infraorbitals" -> Infraorbital nerve).
	-- Entries are stored easiest-first, so the most familiar unused match wins.
	if not common then
		local tries = { key }
		for _, v in variants(key, false) do
			table.insert(tries, v)
		end
		local usedHit: number? = nil
		for _, k in tries do
			local list = bank.byHead[k]
			if list then
				for _, idx in list do
					if not used or not used[idx] then
						local e = bank.entries[idx]
						return {
							ok = true,
							reason = "ok",
							display = e.display,
							tier = e.tier,
							entryIndex = idx,
							matchedKey = e.keys[1],
							corrected = true,
							partial = true,
							input = text,
						}
					end
					usedHit = usedHit or idx
				end
			end
		end
		if usedHit then
			local e = bank.entries[usedHit]
			return { ok = false, reason = "used", display = e.display, tier = e.tier, entryIndex = usedHit,
				matchedKey = e.keys[1], corrected = true, partial = true, input = text }
		end
	end
	return { ok = false, reason = "unknown", corrected = false, input = text }
end

-------------------------------------------------------------------------------
-- per-round helper
-------------------------------------------------------------------------------

export type Round = {
	categoryId: string,
	used: UsedSet,
	history: { Result },
	submit: (self: Round, text: string) -> Result,
	isUsed: (self: Round, text: string) -> boolean,
}

local RoundClass = {}
RoundClass.__index = RoundClass

function RoundClass.submit(self: Round, text: string): Result
	local result = Matcher.check(self.categoryId, text, self.used)
	if result.ok and result.entryIndex then
		local entry = Matcher.getBank(self.categoryId).entries[result.entryIndex]
		self.used[result.entryIndex] = true
		self.used[entry.keys[1]] = true -- its real name
		if result.matchedKey then
			self.used[result.matchedKey] = true -- the spelling they typed
		end
		table.insert(self.history, result)
	end
	return result
end

function RoundClass.isUsed(self: Round, text: string): boolean
	local r = Matcher.check(self.categoryId, text, self.used)
	return r.reason == "used"
end

function Matcher.newRound(categoryId: string): Round
	Matcher.getBank(categoryId)
	return setmetatable({ categoryId = categoryId, used = {}, history = {} }, RoundClass) :: any
end

-- Pick a random category, weighted toward big banks (more room for rare answers).
function Matcher.randomCategory(rng: Random?, minSize: number?): string
	local r = rng or Random.new()
	local pool = {}
	local total = 0
	for _, info in Categories.list do
		if info.count >= (minSize or 0) then
			local w = math.sqrt(info.count)
			total += w
			table.insert(pool, { id = info.id, w = w })
		end
	end
	local roll = r:NextNumber() * total
	for _, p in pool do
		roll -= p.w
		if roll <= 0 then
			return p.id
		end
	end
	return pool[#pool].id
end

return Matcher
