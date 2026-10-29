--[[
	Tests the ring round system (RingLogic, RateLimiter, FeedFormat) outside Roblox,
	with fake time and bot players.

	Run from the repo root:
		lune run tests/run_rounds.luau          -- checks + one full 3-player game log
		lune run tests/run_rounds.luau quiet    -- checks only

	Exits with code 1 if any check fails.
]]

local process = require("@lune/process")
local Shim = require("./shim")

local answersFolder = Shim.folder("src/ServerStorage/ShrimpillionAnswers")
local sharedFolder = Shim.folder("src/ReplicatedStorage/Shared")
local serverFolder = Shim.folder("src/ServerScriptService/Server")

local Matcher = Shim.require(answersFolder.AnswerMatcher)
local Luck = Shim.require(answersFolder.Luck)
local Rarity = Shim.require(answersFolder.Rarity)
local Categories = Shim.require(answersFolder.Categories)
local Config = Shim.require(sharedFolder.RoundConfig)
local FeedFormat = Shim.require(sharedFolder.FeedFormat)
local RingLogic = Shim.require(serverFolder.Rings.RingLogic)
local RateLimiter = Shim.require(serverFolder.RateLimiter)

local quiet = process.args[1] == "quiet"
local passed, failed = 0, 0

local function expect(label: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
		print("  ok    " .. label)
	else
		failed += 1
		print("  FAIL  " .. label .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-------------------------------------------------------------------------------
-- a test ring that records everything it emits
-------------------------------------------------------------------------------

local function newRing(opts)
	opts = opts or {}
	local rec = { events = {}, feed = {}, replies = {}, coins = {}, banners = {}, ended = {}, lines = {} }
	local matcher = Matcher
	if opts.category then
		matcher = setmetatable({
			randomCategory = function()
				return opts.category
			end,
		}, { __index = Matcher })
	end
	local clock = { t = 0 }
	local ring = RingLogic.new(opts.id or "Test", opts.seats or 8, opts.ranked == true, {
		Matcher = matcher,
		Luck = Luck,
		Rarity = Rarity,
		Categories = Categories,
		Config = Config,
		rng = Shim.Random.new(opts.seed or 1),
		emit = function(e)
			table.insert(rec.events, e)
			if e.type == "feed" then
				table.insert(rec.feed, e)
				local line = string.format("[%5.1fs] %s", clock.t, FeedFormat.line(e))
				table.insert(rec.lines, line)
				if opts.log then
					print("    " .. line)
				end
			elseif e.type == "reply" then
				table.insert(rec.replies, e)
			elseif e.type == "coins" then
				rec.coins[e.userId] = (rec.coins[e.userId] or 0) + e.amount
			elseif e.type == "banner" then
				table.insert(rec.banners, e)
			elseif e.type == "matchEnded" then
				table.insert(rec.ended, e)
			end
		end,
	})
	return ring, rec, clock
end

-- advance fake time in 0.1 s steps
local function run(ring, clock, seconds: number, each: ((number) -> boolean?)?)
	local stop = clock.t + seconds
	while clock.t < stop - 1e-9 do
		clock.t += 0.1
		ring:step(clock.t)
		if each and each(clock.t) then
			return true
		end
	end
	return false
end

local function lastFeed(rec, kind: string)
	for i = #rec.feed, 1, -1 do
		if rec.feed[i].kind == kind then
			return rec.feed[i]
		end
	end
	return nil
end

local function countFeed(rec, kind: string): number
	local n = 0
	for _, e in rec.feed do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

-- one answer of each tier from a category, by display name, that the matcher
-- maps back to that same entry
local function answersByTier(categoryId: string): { [number]: { string } }
	local out = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
	for _, e in Matcher.getBank(categoryId).entries do
		local r = Matcher.check(categoryId, e.display)
		if r.ok and r.tier == e.tier and #out[e.tier] < 20 then
			table.insert(out[e.tier], e.display)
		end
	end
	return out
end

local ANIMALS = answersByTier("animals")

local function seatThree(ring, clock)
	ring:sit(1, 101, "Ava", clock.t)
	ring:sit(4, 102, "Ben", clock.t)
	ring:sit(6, 103, "Cy", clock.t)
end

local function startGame(ring, clock)
	seatThree(ring, clock)
	run(ring, clock, Config.COUNTDOWN + 0.1)
end

-------------------------------------------------------------------------------
print("Lobby")
-------------------------------------------------------------------------------
do
	local ring, rec, clock = newRing()
	ring:sit(1, 1, "A", 0)
	expect("1 player: still waiting", ring.phase == "waiting")
	ring:sit(2, 2, "B", 0)
	expect("casual starts a countdown at 2 players", ring.phase == "countdown")
	expect("countdown is 15 s", ring.endsAt == 15, ring.endsAt)
	expect("can't sit in a taken seat", not ring:sit(2, 3, "C", 0))
	expect("can't sit twice", not ring:sit(3, 1, "A", 0))
	ring:stand(2, 1)
	expect("standing up below the minimum cancels the countdown", ring.phase == "waiting")
	expect("the player who stood up left the ring", ring.players[2] == nil and ring.seats[2] == nil)

	ring:sit(2, 2, "B", 2)
	for i = 3, 8 do
		ring:sit(i, i, "P" .. i, 3)
	end
	expect("all 8 seats full: countdown drops to 8 s", ring.endsAt == 3 + Config.COUNTDOWN_FULL, ring.endsAt)
	clock.t = 3
	run(ring, clock, 8.1)
	expect("game starts when the countdown ends", ring.phase == "playing")
	expect("everyone seated is in the game", #ring:alive() == 8)
	expect("blowfish goes to a seated player", ring.players[ring.round.holder] ~= nil)
	expect("category prompt is shown", type(ring:snapshot(clock.t).prompt) == "string")
	expect("category has 30+ answers", Categories.byId[ring.round.categoryId].count >= 30)
	expect("hidden pop point is 18–30 s", ring.round.maxAir >= 18 and ring.round.maxAir <= 30, ring.round.maxAir)

	local ranked = newRing({ ranked = true })
	for i = 1, 3 do
		ranked:sit(i, i, "R" .. i, 0)
	end
	expect("ranked doesn't start with 3", ranked.phase == "waiting")
	ranked:sit(4, 4, "R4", 0)
	expect("ranked starts at 4", ranked.phase == "countdown")
end

-------------------------------------------------------------------------------
print("\nAnswers and passing")
-------------------------------------------------------------------------------
do
	local ring, rec, clock = newRing({ category = "animals" })
	startGame(ring, clock)
	local holder = ring.round.holder
	local other = if holder == 101 then 102 else 101

	local r = ring:submit(other, ANIMALS[0][1], false, 0, clock.t)
	expect("answer from someone who isn't holding is rejected", r.reason == "not_your_turn")
	expect("…and changes nothing", ring.round.holder == holder)

	run(ring, clock, 2)
	local before = ring:air(clock.t)
	r = ring:submit(holder, "zzzqqq", false, 0, clock.t)
	expect("wrong answer: holder keeps it", not r.ok and ring.round.holder == holder)
	expect("wrong answer: no coins", rec.coins[holder] == nil)
	expect("wrong answer: a shake reply goes to the holder", rec.replies[#rec.replies].to == holder and rec.replies[#rec.replies].ok == false)
	expect("wrong answer: air keeps filling (no other penalty)", math.abs(ring:air(clock.t) - before) < 1e-6)

	local shallow = ANIMALS[0][1]
	r = ring:submit(holder, shallow, false, 0, clock.t)
	expect("Shallows answer is accepted", r.ok and r.tier == 0, r.reason)
	expect("Shallows: +1 coin", rec.coins[holder] == 1, rec.coins[holder])
	local holderSeat = ring.players[holder].seat
	local nextHolder = ring.players[ring.round.holder]
	local expectSeat
	for k = 1, 7 do
		local s = (holderSeat + k - 1) % 8 + 1
		if ring.seats[s] then
			expectSeat = s
			break
		end
	end
	expect("passes to the next seated player clockwise", nextHolder.seat == expectSeat, nextHolder.seat)
	expect("Shallows lets out no air", math.abs(ring:air(clock.t) - before) < 1e-6)

	local h2 = ring.round.holder
	r = ring:submit(h2, shallow, false, 0, clock.t)
	expect("same answer again: used", r.reason == "used")
	expect("used answer: holder keeps it", ring.round.holder == h2)

	run(ring, clock, 0.5)
	local reef = ANIMALS[1][1]
	r = ring:submit(h2, reef, false, 0, clock.t)
	expect("Reef answer: +3 coins", r.ok and rec.coins[h2] == 3, rec.coins[h2])
	expect("Reef lets out 1 s of air", math.abs(ring:air(clock.t) - (before + 0.5 - 1)) < 1e-6, ring:air(clock.t))

	-- deflate never below 0
	local h3 = ring.round.holder
	ring.round.airBase = 0.5
	ring.round.heldSince = clock.t
	r = ring:submit(h3, ANIMALS[2][1], false, 0, clock.t)
	expect("Twilight with 0.5 s of air: air stops at 0", r.ok and ring:air(clock.t) == 0, ring:air(clock.t))

	-- the filter hid something: wrong, never rescued
	local h4 = ring.round.holder
	r = ring:submit(h4, ANIMALS[0][2], true, 5, clock.t)
	expect("filter changed the text: counts as wrong", not r.ok and r.reason == "filtered")
	expect("…even though the words were a real answer", ring.round.holder == h4)
	local rescued = 0
	for _ = 1, 30 do
		if ring:submit(h4, "####", true, 5, clock.t).ok then
			rescued += 1
		end
	end
	expect("filtered text is never rescued by luck 5 (30 tries)", rescued == 0, rescued)

	local snap = ring:snapshot(clock.t)
	local leaks = {}
	for k in snap do
		local lk = string.lower(k)
		if string.find(lk, "air") or string.find(lk, "max") then
			table.insert(leaks, k)
		end
	end
	expect("snapshot doesn't show air or the pop point", #leaks == 0, table.concat(leaks, ","))
	expect("snapshot shows a puff stage", type(snap.puff) == "number")
end

-------------------------------------------------------------------------------
print("\nMidnight / Abyss")
-------------------------------------------------------------------------------
do
	local ring, rec, clock = newRing({ category = "animals" })
	startGame(ring, clock)
	local holder = ring.round.holder
	run(ring, clock, 4)
	local airBefore = ring:air(clock.t)
	local r = ring:submit(holder, ANIMALS[3][1], false, 0, clock.t)
	expect("Midnight answer: +12 coins", r.ok and rec.coins[holder] == 12, rec.coins[holder])
	expect("Midnight: holder picks (picking phase)", ring.phase == "picking")
	expect("pick timer is 10 s", math.abs(ring.endsAt - (clock.t + 10)) < 1e-6)
	expect("Midnight lets out 3 s", math.abs(ring:air(clock.t) - (airBefore - 3)) < 1e-6)
	run(ring, clock, 3)
	expect("air doesn't fill while picking", math.abs(ring:air(clock.t) - (airBefore - 3)) < 1e-6)
	local others = {}
	for _, p in ring:alive() do
		if p.id ~= holder then
			table.insert(others, p.id)
		end
	end
	expect("non-holder can't pick", not ring:pick(others[1], others[2], clock.t))
	expect("holder can't pick themselves", not ring:pick(holder, holder, clock.t))
	expect("holder can't pick a stranger", not ring:pick(holder, 999, clock.t))
	expect("holder picks a player", ring:pick(holder, others[2], clock.t))
	expect("…who now holds it", ring.round.holder == others[2] and ring.phase == "playing")
	expect("Midnight gives no extra air", math.abs(ring:air(clock.t) - (airBefore - 3)) < 1e-6)

	-- pick timeout
	local h = ring.round.holder
	ring:submit(h, ANIMALS[3][2], false, 0, clock.t)
	run(ring, clock, Config.PICK_TIME + 0.2)
	expect("no pick in 10 s: goes to a random other player", ring.phase == "playing" and ring.round.holder ~= h)
	expect("…and the feed says so", lastFeed(rec, "pass").how == "timeout")

	-- Abyss
	local ha = ring.round.holder
	ring.round.airBase = 10
	ring.round.heldSince = clock.t
	local coinsBefore = rec.coins[ha] or 0
	r = ring:submit(ha, ANIMALS[4][1], false, 0, clock.t)
	expect("Abyss: +25 coins", r.ok and r.tier == 4 and rec.coins[ha] == coinsBefore + 25, rec.coins[ha])
	expect("Abyss: a server-wide banner", #rec.banners == 1 and rec.banners[1].userId == ha)
	expect("Abyss: holder picks", ring.phase == "picking")
	expect("Abyss lets out 5 s", math.abs(ring:air(clock.t) - 5) < 1e-6, ring:air(clock.t))
	local target
	for _, p in ring:alive() do
		if p.id ~= ha then
			target = p.id
		end
	end
	ring:pick(ha, target, clock.t)
	expect("Abyss: next holder starts with +2 s of air", math.abs(ring:air(clock.t) - 7) < 1e-6, ring:air(clock.t))
	expect("feed shows the bonus air", lastFeed(rec, "pass").bonus == 2)
end

-------------------------------------------------------------------------------
print("\nDive Deeper")
-------------------------------------------------------------------------------
do
	local ring, rec, clock = newRing({ category = "animals" })
	startGame(ring, clock)
	local h = ring.round.holder
	ring.round.airBase = 10
	ring.round.heldSince = clock.t
	expect("holder can Dive Deeper", ring:dive(h, clock.t))
	expect("only once per turn", not ring:dive(h, clock.t))
	local r = ring:submit(h, ANIMALS[2][1], false, 0, clock.t)
	expect("dive + Twilight: double coins (12)", r.ok and rec.coins[h] == 12, rec.coins[h])
	expect("dive + Twilight: double air let out (4 s)", math.abs(ring:air(clock.t) - 6) < 1e-6, ring:air(clock.t))
	expect("feed marks the dive hit", lastFeed(rec, "answer").dive == "hit")

	local h2 = ring.round.holder
	expect("new turn: the next holder can dive", ring:dive(h2, clock.t))
	local a0 = ring:air(clock.t)
	r = ring:submit(h2, ANIMALS[0][3], false, 0, clock.t)
	expect("dive + Shallows: +3 s of air", math.abs(ring:air(clock.t) - (a0 + 3)) < 1e-6, ring:air(clock.t))
	expect("dive + Shallows: the turn carries on", ring.round.holder == h2 and ring.phase == "playing")
	expect("dive + Shallows: no coins", rec.coins[h2] == nil)
	expect("dive + Shallows: that answer is now used", ring:submit(h2, ANIMALS[0][3], false, 0, clock.t).reason == "used")
	expect("can't dive again this turn", not ring:dive(h2, clock.t))
	r = ring:submit(h2, ANIMALS[1][3], false, 0, clock.t)
	expect("after a missed dive, a normal answer passes as usual (3 coins)", r.ok and rec.coins[h2] == 3 and ring.round.holder ~= h2)

	local h3 = ring.round.holder
	ring.round.airBase = 0
	ring.round.heldSince = clock.t
	ring:dive(h3, clock.t)
	ring:submit(h3, "notananimalxyz", false, 0, clock.t)
	run(ring, clock, Config.DIVE_WINDOW + 0.05)
	expect("dive + 5 s with no deep answer: +3 s of air", math.abs(ring:air(clock.t) - (Config.DIVE_WINDOW + 0.1 + 3)) < 0.11, ring:air(clock.t))
	expect("…and the turn carries on", ring.round.holder == h3)
	expect("feed: dive missed (timeout)", lastFeed(rec, "diveMiss").why == "timeout")
end

-------------------------------------------------------------------------------
print("\nPops, standing up and the end of a game")
-------------------------------------------------------------------------------
do
	local ring, rec, clock = newRing({ category = "animals" })
	startGame(ring, clock)
	local h = ring.round.holder
	local maxAir = ring.round.maxAir
	local poppedAt
	run(ring, clock, 40, function(t)
		if lastFeed(rec, "pop") then
			poppedAt = t
			return true
		end
		return false
	end)
	expect("holding it too long pops it at the hidden max", poppedAt and math.abs((poppedAt - Config.COUNTDOWN - 0.1) - maxAir) < 0.15, poppedAt)
	expect("the holder is out", ring.players[h].status == "ghost")
	expect("ghost stays in their seat", ring.seats[ring.players[h].seat] == ring.players[h])
	expect("short gap before the next round", ring.phase == "between")
	local firstCategoryRound = ring.round.number
	run(ring, clock, Config.ROUND_GAP + 0.1)
	expect("next round starts", ring.phase == "playing" and ring.round.number == firstCategoryRound + 1)
	expect("ghosts never get the blowfish", ring.players[ring.round.holder].status == "alive")

	-- the ghost stands up: just leaves, game goes on
	ring:stand(h, clock.t)
	expect("a ghost standing up just leaves", ring.phase == "playing" and ring.players[h] == nil)

	-- a non-holder stands up mid-round: counts as popping, and the game ends
	local holder = ring.round.holder
	local other
	for _, p in ring:alive() do
		if p.id ~= holder then
			other = p.id
		end
	end
	ring:stand(other, clock.t)
	expect("standing up mid-round counts as popping", lastFeed(rec, "left").userId == other)
	expect("last player left wins", ring.phase == "results" and ring.results.winnerId == holder)
	expect("results list 1st, 2nd, 3rd", #ring.results.placements == 3
		and ring.results.placements[1].userId == holder
		and ring.results.placements[2].userId == other
		and ring.results.placements[3].userId == h)
	expect("matchEnded is emitted once", #rec.ended == 1)
	run(ring, clock, Config.RESULTS_TIME + 0.1)
	expect("after 6 s of results the ring resets", ring.phase == "waiting" and ring.players[holder].status == "waiting")

	-- the holder stands up mid-round
	local ring2, rec2, clock2 = newRing({ category = "animals", seed = 7 })
	startGame(ring2, clock2)
	ring2:sit(8, 104, "Dee", clock2.t)
	expect("someone sitting down mid-game waits for the next one", ring2.players[104].status == "waiting")
	local h2 = ring2.round.holder
	ring2:stand(h2, clock2.t)
	expect("holder stands up: they're out and the round ends", lastFeed(rec2, "left").wasHolder == true and ring2.phase == "between")
	run(ring2, clock2, Config.ROUND_GAP + 0.1)
	expect("new round goes on with the other 2", ring2.phase == "playing" and #ring2:alive() == 2)
	expect("the late joiner isn't in this game", ring2.players[104].status == "waiting" and ring2.round.holder ~= 104)
	local n = countFeed(rec2, "round")
	ring2:submit(ring2.round.holder, ANIMALS[0][1], false, 0, clock2.t)
	expect("still the same round after a pass", countFeed(rec2, "round") == n)
end

-------------------------------------------------------------------------------
print("\nRate limiter")
-------------------------------------------------------------------------------
do
	local lim = RateLimiter.new(4, 2)
	local ok = 0
	for _ = 1, 10 do
		if lim:allow(1, 0) then
			ok += 1
		end
	end
	expect("burst of 4 allowed, the rest dropped", ok == 4, ok)
	expect("refills over time (2 per second)", lim:allow(1, 0.5) and not lim:allow(1, 0.5))
	expect("players have their own buckets", lim:allow(2, 0.5))
	lim:forget(1)
	expect("forget resets a player", lim:allow(1, 0.5))
end

-------------------------------------------------------------------------------
print("\nFeed lines")
-------------------------------------------------------------------------------
do
	local line = FeedFormat.line({ kind = "answer", name = "Ava", text = "chile soup", from = "chile soup", display = "Paella",
		lucky = "rescue", tierName = "Shallows", coins = 1, deflate = 0 })
	expect("luck shows typed → result ✨ LUCKY!", string.find(line, "chile soup → Paella ✨ LUCKY!", 1, true) ~= nil, line)
end

-------------------------------------------------------------------------------
print("\nFull games with 3 bots (random seeds)")
-------------------------------------------------------------------------------

-- Bots: when holding, they wait a bit then type something. Mostly real answers
-- (more common ones than rare), sometimes a typo-gibberish or a repeat.
-- One bot has luck 5. Sometimes they Dive Deeper; sometimes they let the pick timer run out.
local TIER_WEIGHTS = { 0.42, 0.22, 0.16, 0.12, 0.08 }
local NONSENSE = { "chile soup", "asdfgh", "blorp", "uhhh", "idk", "spaceship" }

local function botGame(seed: number, log: boolean)
	local ring, rec, clock = newRing({ seed = seed, log = log })
	local brain = Shim.Random.new(seed * 31 + 5)
	local luck = { [101] = 0, [102] = 5, [103] = 0 }
	local plan = nil -- { at, holder, turnKey }
	local said = {}

	local function chooseAnswer(categoryId: string): string
		local roll, tier = brain:NextNumber(), 0
		for t, w in TIER_WEIGHTS do
			roll -= w
			if roll <= 0 then
				tier = t - 1
				break
			end
		end
		local pool = {}
		for _, e in Matcher.getBank(categoryId).entries do
			if e.tier == tier then
				table.insert(pool, e.display)
			end
		end
		if #pool == 0 then
			pool = { Matcher.getBank(categoryId).entries[1].display }
		end
		return pool[brain:NextInteger(1, #pool)]
	end

	seatThree(ring, clock)
	local acceptedFromWrongPlayer = 0
	local maxRounds = 0
	run(ring, clock, 600, function(t)
		if ring.phase == "results" then
			return true
		end
		local r = ring.round
		if not r or not r.holder then
			plan = nil
			return false
		end
		maxRounds = math.max(maxRounds, r.number)
		local key = tostring(r.holder) .. ":" .. ring.phase .. ":" .. tostring(r.turn)
		if not plan or plan.key ~= key then
			plan = { key = key, at = t + brain:NextNumber(1.5, if ring.phase == "picking" then 12 else 6) }
			if ring.phase == "playing" and brain:NextNumber() < 0.2 then
				ring:dive(r.holder, t)
			end
			-- someone not holding tries to answer: must be ignored
			for id in luck do
				if id ~= r.holder and ring.players[id] and ring:submit(id, "dog", false, 0, t).ok then
					acceptedFromWrongPlayer += 1
				end
			end
		end
		if t >= plan.at then
			plan.at = t + brain:NextNumber(1, 4)
			local h = r.holder
			if ring.phase == "picking" then
				local options = {}
				for _, p in ring:alive() do
					if p.id ~= h then
						table.insert(options, p.id)
					end
				end
				ring:pick(h, options[brain:NextInteger(1, #options)], t)
			else
				local roll = brain:NextNumber()
				local text
				if roll < 0.15 then
					text = NONSENSE[brain:NextInteger(1, #NONSENSE)]
				elseif roll < 0.22 and #said > 0 then
					text = said[brain:NextInteger(1, #said)]
				else
					text = chooseAnswer(r.categoryId)
				end
				local res = ring:submit(h, text, false, luck[h] or 0, t)
				if res.ok then
					table.insert(said, text)
				end
			end
		end
		return false
	end)
	return ring, rec, acceptedFromWrongPlayer, maxRounds
end

if not quiet then
	print("\n  --- log of a full 3-player game (seed 3) ---")
end
local ring, rec, wrongAccepted = botGame(3, not quiet)
if not quiet then
	print("  --- end of log ---\n")
end
expect("game ends with a winner", ring.phase == "results" and ring.results.winnerId ~= nil)
expect("2 pops for 3 players", countFeed(rec, "pop") + countFeed(rec, "left") == 2)
expect("a new category every round", (function()
	local seen = {}
	for _, e in rec.feed do
		if e.kind == "round" then
			if seen[e.categoryName] then
				return false
			end
			seen[e.categoryName] = true
		end
	end
	return true
end)())
expect("answers from non-holders were never accepted", wrongAccepted == 0, wrongAccepted)

local stats = { games = 0, noWinner = 0, lucky = 0, dives = 0, picks = 0, timeouts = 0, banners = 0, badPop = 0, bad = 0 }
for seed = 10, 60 do
	local g, grec, wa = botGame(seed, false)
	stats.games += 1
	if not (g.phase == "results" and g.results.winnerId) then
		stats.noWinner += 1
	end
	stats.bad += wa
	for _, e in grec.feed do
		if e.kind == "answer" and e.lucky then
			stats.lucky += 1
		elseif e.kind == "dive" then
			stats.dives += 1
		elseif e.kind == "pass" and e.how == "picked" then
			stats.picks += 1
		elseif e.kind == "pass" and e.how == "timeout" then
			stats.timeouts += 1
		end
	end
	stats.banners += #grec.banners
	-- coins in the results match the coins handed out
	for _, pl in g.results and g.results.placements or {} do
		if (grec.coins[pl.userId] or 0) ~= pl.coins then
			stats.badPop += 1
		end
	end
end
print(string.format("  %d games: %d luck swaps, %d dives, %d picks, %d pick timeouts, %d Abyss banners",
	stats.games, stats.lucky, stats.dives, stats.picks, stats.timeouts, stats.banners))
expect(stats.games .. " bot games all end with a winner", stats.noWinner == 0, stats.noWinner)
expect("results coins match coins awarded", stats.badPop == 0, stats.badPop)
expect("bots hit luck, dives, picks, timeouts and banners", stats.lucky > 0 and stats.dives > 0 and stats.picks > 0
	and stats.timeouts > 0 and stats.banners > 0)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
