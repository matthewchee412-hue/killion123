--[[
	Tests the answer-bank modules (AnswerMatcher, Luck, Rarity, banks) outside Roblox.

	Run from the repo root:
		lune run tests/run_matcher.luau

	Exits with code 1 if any check fails.
]]

local process = require("@lune/process")
local Shim = require("./shim")

local ROOT = "src/ServerStorage/ShrimpillionAnswers"

local passed, failed = 0, 0

local function expect(label: string, cond: boolean, detail: string?)
	if cond then
		passed += 1
		print("  ok    " .. label)
	else
		failed += 1
		print("  FAIL  " .. label .. (if detail then "  (" .. detail .. ")" else ""))
	end
end

local function describe(r): string
	return string.format("reason=%s display=%s tier=%s", tostring(r.reason), tostring(r.display), tostring(r.tier))
end

-------------------------------------------------------------------------------
-- loading (timed)
-------------------------------------------------------------------------------

print("Loading modules")
local t0 = os.clock()
local folder = Shim.folder(ROOT)
local Matcher = Shim.require(folder.AnswerMatcher)
local Luck = Shim.require(folder.Luck)
local Rarity = Shim.require(folder.Rarity)
local Categories = Shim.require(folder.Categories)
local tModules = os.clock() - t0

local t1 = os.clock()
Matcher.preloadAll()
local tBanks = os.clock() - t1

local bankFiles = 0
for _, child in folder.Banks:GetChildren() do
	if string.match(child.Name, "^Bank_") then
		bankFiles += 1
	end
end

local totalEntries, mismatched = 0, {}
for _, info in Categories.list do
	local n = #Matcher.getBank(info.id).entries
	totalEntries += n
	if n ~= info.count then
		table.insert(mismatched, string.format("%s: %d loaded, %d listed", info.id, n, info.count))
	end
end

expect("202 bank modules found", bankFiles == 202, tostring(bankFiles))
expect("201 categories", #Categories.list == 201, tostring(#Categories.list))
expect("every bank loads as many answers as Categories says", #mismatched == 0, table.concat(mismatched, "; "))
expect("Rarity has 5 tiers", Rarity.tiers[0] ~= nil and Rarity.tiers[4] ~= nil and Rarity.tiers[5] == nil)

-------------------------------------------------------------------------------
-- answers
-------------------------------------------------------------------------------

print("\nAnswers")

local function expectAnswer(cat: string, text: string, reason: string, display: string?, tier: number?)
	local r = Matcher.check(cat, text)
	local good = r.reason == reason
		and (display == nil or r.display == display)
		and (tier == nil or r.tier == tier)
	local want = if reason == "ok"
		then string.format("%s%s", display or "?", if tier then " (" .. Rarity.tiers[tier].name .. ")" else "")
		else reason
	expect(string.format("[%s] %q -> %s", cat, text, want), good, describe(r))
end

expectAnswer("animals", "dog", "ok", "Dog", 0)
expectAnswer("animals", "Dogs", "ok", "Dog", 0)
expectAnswer("body_parts", "infraorbitals", "ok", "Infraorbital nerve")
expectAnswer("body_parts", "infraorbital", "ok", "Infraorbital nerve")
expectAnswer("body_parts", "zygomatics", "ok", "Cheekbone")
expectAnswer("sharks_rays", "hammerhead", "ok", "Hammerhead shark")
expectAnswer("sea_creatures", "hammerhead", "ok", "Hammerhead shark")
for _, cat in { "animals", "sea_creatures", "fish" } do
	expectAnswer(cat, "golden", "unknown")
	expectAnswer(cat, "killer", "unknown")
end
expectAnswer("animals", "", "empty")

-- used within a round
local round = Matcher.newRound("animals")
local first = round:submit("dog")
local again = round:submit("dog")
local plural = round:submit("the Dogs!")
expect("round: first \"dog\" is ok", first.ok and first.reason == "ok", describe(first))
expect("round: second \"dog\" is used", not again.ok and again.reason == "used", describe(again))
expect("round: \"the Dogs!\" is also used", not plural.ok and plural.reason == "used", describe(plural))
expect("round: isUsed(\"dog\")", round:isUsed("dog"))

local bodyRound = Matcher.newRound("body_parts")
local a1 = bodyRound:submit("infraorbital")
local a2 = bodyRound:submit("infraorbitals")
expect("round: first \"infraorbital\" -> Infraorbital nerve", a1.ok and a1.display == "Infraorbital nerve", describe(a1))
expect("round: \"infraorbitals\" then moves to another unused infraorbital answer",
	a2.ok and a2.display ~= "Infraorbital nerve" and string.find(a2.display or "", "^Infraorbital") ~= nil, describe(a2))
local sharkRound = Matcher.newRound("sharks_rays")
sharkRound:submit("Hammerhead shark")
local h = sharkRound:submit("hammerhead")
expect("round: \"hammerhead\" after \"Hammerhead shark\" is used", h.reason == "used", describe(h))

-------------------------------------------------------------------------------
-- luck at level 5
-------------------------------------------------------------------------------

print("\nLuck (level 5)")

local TRIALS = 500
local rng = Shim.Random.new(20261029)
local chances = Luck.chances(5)

local LETTERS = "bcdfghjklmnpqrstvwxz"
local function gibberish(): string
	local out = {}
	for i = 1, rng:NextInteger(5, 8) do
		local n = rng:NextInteger(1, #LETTERS)
		out[i] = string.sub(LETTERS, n, n)
	end
	return table.concat(out)
end

-- wrong answers: how often are they rescued?
local rescues, badRescue, wrongTried = 0, 0, 0
while wrongTried < TRIALS do
	local text = gibberish()
	if Matcher.check("animals", text).reason == "unknown" then
		wrongTried += 1
		local r = Luck.submit(Matcher.newRound("animals"), text, 5, true, rng)
		if r.lucky == "rescue" then
			rescues += 1
			if not (r.ok and r.tier <= 1 and r.originalDisplay == text) then
				badRescue += 1
			end
		end
	end
end

-- right answers: how often do they go one tier deeper?
local RIGHT = { "dog", "cat", "lion", "tiger", "horse", "cow", "pig", "elephant", "monkey", "rabbit" }
local upgrades, badUpgrade = 0, 0
for i = 1, TRIALS do
	local text = RIGHT[(i - 1) % #RIGHT + 1]
	local before = Matcher.check("animals", text)
	local r = Luck.submit(Matcher.newRound("animals"), text, 5, true, rng)
	if r.lucky == "upgrade" then
		upgrades += 1
		if not (r.ok and r.tier == before.tier + 1 and r.originalDisplay == before.display) then
			badUpgrade += 1
		end
	elseif not (r.ok and r.display == before.display) then
		badUpgrade += 1
	end
end

-- 4 standard errors either side: a correct module fails this about 1 in 15,000 runs
local function within(hits: number, p: number): (boolean, string)
	local rate = hits / TRIALS
	local margin = 4 * math.sqrt(p * (1 - p) / TRIALS)
	return math.abs(rate - p) <= margin, string.format("%.1f%% (want %.0f%% ± %.1f)", rate * 100, p * 100, margin * 100)
end

local okR, txtR = within(rescues, chances.rescue)
local okU, txtU = within(upgrades, chances.upgrade)
print(string.format("  rescue  %d / %d = %s", rescues, TRIALS, txtR))
print(string.format("  upgrade %d / %d = %s", upgrades, TRIALS, txtU))
expect("rescue rate is about " .. chances.rescue * 100 .. "%", okR, txtR)
expect("upgrade rate is about " .. chances.upgrade * 100 .. "%", okU, txtU)
expect("every rescue is a Shallows/Reef answer and keeps what was typed", badRescue == 0, tostring(badRescue))
expect("every upgrade is exactly one tier deeper; non-upgrades are unchanged", badUpgrade == 0, tostring(badUpgrade))

-- no rescue when the chat filter changed the text, or at luck 0
local filtered, level0 = 0, 0
for _ = 1, 200 do
	local text = gibberish()
	if Luck.submit(Matcher.newRound("animals"), text, 5, false, rng).lucky then
		filtered += 1
	end
	if Luck.submit(Matcher.newRound("animals"), text, 0, true, rng).lucky then
		level0 += 1
	end
end
expect("mayRescue = false never rescues", filtered == 0, tostring(filtered))
expect("luck 0 never rescues", level0 == 0, tostring(level0))

local luckRound = Matcher.newRound("animals")
Luck.submit(luckRound, "dog", 0, true, rng)
local luckAgain = Luck.submit(luckRound, "dog", 5, true, rng)
expect("Luck.submit: a used answer comes back used", luckAgain.reason == "used" and not luckAgain.lucky, describe(luckAgain))

-------------------------------------------------------------------------------
-- timing
-------------------------------------------------------------------------------

print("\nTiming")

local function timeCheck(cat: string, text: string, reps: number): number
	local s = os.clock()
	for _ = 1, reps do
		Matcher.check(cat, text)
	end
	return (os.clock() - s) / reps * 1e6
end

print(string.format("  require modules            %7.1f ms", tModules * 1000))
print(string.format("  preloadAll (201 banks)     %7.1f ms   (%d answers)", tBanks * 1000, totalEntries))
print(string.format("  check exact  \"dog\"         %7.1f µs", timeCheck("animals", "dog", 2000)))
print(string.format("  check plural \"zygomatics\"  %7.1f µs", timeCheck("body_parts", "zygomatics", 2000)))
print(string.format("  check typo   \"elephnat\"    %7.1f µs", timeCheck("animals", "elephnat", 500)))
print(string.format("  check miss   \"qwrtzplk\"    %7.1f µs", timeCheck("animals", "qwrtzplk", 500)))

-------------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
