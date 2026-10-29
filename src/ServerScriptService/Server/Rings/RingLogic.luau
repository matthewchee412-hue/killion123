--[[
	RingLogic — the game on one ring, with no Roblox services, so Lune can test it.

	RingService owns the Roblox side (seats, remotes, text filter) and feeds this
	module plain calls with the current server time:

		local ring = RingLogic.new("Ring1", 8, false, deps)
		ring:sit(seatIndex, userId, name, now)
		ring:stand(userId, now)              -- stood up, died or left the game
		ring:submit(userId, filteredText, filterChanged, luckLevel, now)
		ring:pick(userId, targetUserId, now)
		ring:dive(userId, now)
		ring:step(now)                       -- call often (timers, pops)
		ring:snapshot(now)                   -- state for clients (no hidden air)

	deps = { Matcher, Luck, Rarity, Categories, Config, rng: Random, emit = function(event) }
	emit gets:
		{ type = "state" }                              something changed, resend snapshot
		{ type = "feed", kind = ..., ... }              commentary line (FeedFormat.line)
		{ type = "reply", to = userId, ... }            answer result for the holder only
		{ type = "coins", userId, amount, reason }
		{ type = "banner", userId, name, display, ... } Abyss: whole server
		{ type = "matchEnded", ranked, placements, rounds }

	Seats are numbered clockwise. Player status: "waiting" (seated, not in the
	current game), "alive", or "ghost" (popped, still seated and watching).
	A game is several rounds; each round has a new category and pops once.
]]

local RingLogic = {}
RingLogic.__index = RingLogic

export type Player = {
	id: number,
	name: string,
	seat: number,
	status: string,
}

function RingLogic.new(id: string, seatCount: number, ranked: boolean, deps)
	return setmetatable({
		id = id,
		seatCount = seatCount,
		ranked = ranked,
		deps = deps,
		seats = {} :: { [number]: Player },
		players = {} :: { [number]: Player },
		phase = "waiting", -- waiting | countdown | playing | picking | between | results
		endsAt = nil :: number?,
		match = nil :: any,
		round = nil :: any,
		results = nil :: any,
		lastPuff = 0,
	}, RingLogic)
end

-------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------

function RingLogic:_emit(event)
	event.ring = self.id
	self.deps.emit(event)
end

function RingLogic:_changed()
	self:_emit({ type = "state" })
end

function RingLogic:_feed(kind: string, fields)
	fields.type = "feed"
	fields.kind = kind
	self:_emit(fields)
end

function RingLogic:minPlayers(): number
	local c = self.deps.Config
	return if self.ranked then c.MIN_PLAYERS_RANKED else c.MIN_PLAYERS_CASUAL
end

function RingLogic:seatedCount(): number
	local n = 0
	for _ in self.players do
		n += 1
	end
	return n
end

-- alive players in seat order
function RingLogic:alive(): { Player }
	local list = {}
	for i = 1, self.seatCount do
		local p = self.seats[i]
		if p and p.status == "alive" then
			table.insert(list, p)
		end
	end
	return list
end

function RingLogic:holder(): Player?
	local r = self.round
	return if r and r.holder then self.players[r.holder] else nil
end

function RingLogic:inMatch(): boolean
	return self.phase == "playing" or self.phase == "picking" or self.phase == "between"
end

function RingLogic:air(now: number): number
	local r = self.round
	if not r then
		return 0
	end
	if self.phase == "playing" and r.holder then
		return r.airBase + (now - r.heldSince) * self.deps.Config.AIR_PER_SECOND
	end
	return r.airBase
end

function RingLogic:_freezeAir(now: number)
	local r = self.round
	r.airBase = self:air(now)
	r.heldSince = now
end

function RingLogic:_addAir(now: number, seconds: number)
	self:_freezeAir(now)
	self.round.airBase = math.max(0, self.round.airBase + seconds)
end

function RingLogic:puffStage(now: number): number
	local r = self.round
	if not r or not r.holder then
		return 0
	end
	local f = self:air(now) / r.maxAir
	local stage = 0
	for _, threshold in self.deps.Config.PUFF_STAGES do
		if f >= threshold then
			stage += 1
		end
	end
	return stage
end

function RingLogic:_nextClockwise(fromId: number): Player?
	local from = self.players[fromId]
	if not from then
		return self:alive()[1]
	end
	for k = 1, self.seatCount - 1 do
		local p = self.seats[(from.seat + k - 1) % self.seatCount + 1]
		if p and p.status == "alive" then
			return p
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- lobby
-------------------------------------------------------------------------------

function RingLogic:_checkLobby(now: number)
	if self.phase ~= "waiting" and self.phase ~= "countdown" then
		return
	end
	local c = self.deps.Config
	local n = self:seatedCount()
	local full = n >= self.seatCount
	if n >= self:minPlayers() then
		local length = if full then c.COUNTDOWN_FULL else c.COUNTDOWN
		if self.phase == "waiting" then
			self.phase = "countdown"
			self.endsAt = now + length
			self:_feed("countdown", { seconds = length })
			self:_changed()
		elseif full and self.endsAt > now + c.COUNTDOWN_FULL then
			self.endsAt = now + c.COUNTDOWN_FULL
			self:_feed("countdown", { seconds = c.COUNTDOWN_FULL })
			self:_changed()
		end
	elseif self.phase == "countdown" then
		self.phase = "waiting"
		self.endsAt = nil
		self:_feed("countdownCancelled", {})
		self:_changed()
	end
end

function RingLogic:sit(seatIndex: number, id: number, name: string, now: number): boolean
	if self.players[id] or self.seats[seatIndex] or seatIndex < 1 or seatIndex > self.seatCount then
		return false
	end
	local p: Player = { id = id, name = name, seat = seatIndex, status = "waiting" }
	self.seats[seatIndex] = p
	self.players[id] = p
	self:_changed()
	self:_checkLobby(now)
	return true
end

function RingLogic:stand(id: number, now: number)
	local p = self.players[id]
	if not p then
		return
	end
	self:step(now) -- a pop that was already due happens first
	p = self.players[id]
	if not p then
		return
	end
	if p.status == "alive" and self:inMatch() then
		self:_knockOut(p, now, "left")
	end
	self.seats[p.seat] = nil
	self.players[id] = nil
	self:_changed()
	self:_checkLobby(now)
end

-------------------------------------------------------------------------------
-- game flow
-------------------------------------------------------------------------------

function RingLogic:_startMatch(now: number)
	local count = 0
	for _, p in self.players do
		p.status = "alive"
		count += 1
	end
	self.match = { rounds = 0, out = {}, coins = {}, best = nil, usedCategories = {} }
	self.results = nil
	self:_feed("matchStart", { ranked = self.ranked, players = count })
	self:_startRound(now)
end

function RingLogic:_startRound(now: number)
	local d = self.deps
	local c = d.Config
	local m = self.match
	local categoryId
	for _ = 1, 20 do
		categoryId = d.Matcher.randomCategory(d.rng, c.CATEGORY_MIN_SIZE)
		if not m.usedCategories[categoryId] then
			break
		end
	end
	m.usedCategories[categoryId] = true
	m.rounds += 1
	local info = d.Categories.byId[categoryId]
	self.round = {
		number = m.rounds,
		categoryId = categoryId,
		prompt = info.prompt,
		categoryName = info.name,
		answers = d.Matcher.newRound(categoryId),
		maxAir = d.rng:NextNumber(c.POP_MIN, c.POP_MAX),
		airBase = 0,
		heldSince = now,
		holder = nil,
		turn = nil,
		pickBonus = 0,
	}
	self.endsAt = nil
	self.lastPuff = 0
	self:_feed("round", { number = m.rounds, prompt = info.prompt, categoryName = info.name })
	local alive = self:alive()
	self:_giveTo(alive[d.rng:NextInteger(1, #alive)], now, 0, "start", nil)
end

function RingLogic:_giveTo(p: Player, now: number, bonus: number, how: string, from: Player?)
	local r = self.round
	self.phase = "playing"
	self.endsAt = nil
	r.airBase = math.max(0, r.airBase + bonus)
	r.heldSince = now
	r.holder = p.id
	r.turn = { diveUsed = false, diveEndsAt = nil }
	self:_feed("pass", {
		how = how,
		fromId = from and from.id,
		fromName = from and from.name,
		toId = p.id,
		toName = p.name,
		bonus = bonus,
	})
	self:_changed()
end

function RingLogic:_knockOut(p: Player, now: number, how: string)
	local r = self.round
	local wasHolder = r and r.holder == p.id
	if wasHolder then
		self:_freezeAir(now)
	end
	p.status = "ghost"
	table.insert(self.match.out, { id = p.id, name = p.name })
	self:_feed(if how == "left" then "left" else "pop", {
		userId = p.id,
		name = p.name,
		wasHolder = wasHolder,
		category = r and r.categoryName,
	})
	if wasHolder then
		r.holder = nil
		r.turn = nil
	end
	if #self:alive() <= 1 then
		self:_endMatch(now)
	elseif wasHolder then
		self.phase = "between"
		self.endsAt = now + self.deps.Config.ROUND_GAP
	end
	self:_changed()
end

function RingLogic:_endMatch(now: number)
	local m = self.match
	local winner = self:alive()[1]
	local placements = {}
	if winner then
		table.insert(placements, { userId = winner.id, name = winner.name, place = 1, coins = m.coins[winner.id] or 0 })
	end
	for i = #m.out, 1, -1 do
		local o = m.out[i]
		table.insert(placements, { userId = o.id, name = o.name, place = #placements + 1, coins = m.coins[o.id] or 0 })
	end
	if self.round then
		self.round.holder = nil
		self.round.turn = nil
	end
	self.phase = "results"
	self.endsAt = now + self.deps.Config.RESULTS_TIME
	self.results = {
		winnerId = winner and winner.id,
		winnerName = winner and winner.name,
		placements = placements,
		best = m.best,
		rounds = m.rounds,
	}
	if winner then
		self:_feed("win", { userId = winner.id, name = winner.name })
	else
		self:_feed("noWinner", {})
	end
	self:_emit({ type = "matchEnded", ranked = self.ranked, placements = placements, rounds = m.rounds })
	self:_changed()
end

function RingLogic:_reset(now: number)
	for _, p in self.players do
		p.status = "waiting"
	end
	self.match = nil
	self.round = nil
	self.results = nil
	self.phase = "waiting"
	self.endsAt = nil
	self:_changed()
	self:_checkLobby(now)
end

function RingLogic:_diveMiss(now: number, why: string)
	local r = self.round
	local p = self:holder()
	r.turn.diveEndsAt = nil
	local extra = self.deps.Config.DIVE_MISS_AIR
	self:_addAir(now, extra)
	self:_feed("diveMiss", { userId = p and p.id, name = p and p.name, why = why, air = extra })
	self:_changed()
end

function RingLogic:step(now: number)
	local phase = self.phase
	if phase == "countdown" then
		if now >= self.endsAt then
			self:_startMatch(now)
		end
	elseif phase == "playing" then
		local r = self.round
		local holder = self:holder()
		if not holder then
			return
		end
		if self:air(now) >= r.maxAir then
			self:_knockOut(holder, now, "pop")
			return
		end
		if r.turn.diveEndsAt and now >= r.turn.diveEndsAt then
			self:_diveMiss(now, "timeout")
			if self:air(now) >= r.maxAir then
				self:_knockOut(holder, now, "pop")
				return
			end
		end
		local puff = self:puffStage(now)
		if puff ~= self.lastPuff then
			self.lastPuff = puff
			self:_changed()
		end
	elseif phase == "picking" then
		if now >= self.endsAt then
			local picker = self:holder()
			local options = {}
			for _, p in self:alive() do
				if p ~= picker then
					table.insert(options, p)
				end
			end
			self:_giveTo(options[self.deps.rng:NextInteger(1, #options)], now, self.round.pickBonus, "timeout", picker)
		end
	elseif phase == "between" then
		if now >= self.endsAt then
			self:_startRound(now)
		end
	elseif phase == "results" then
		if now >= self.endsAt then
			self:_reset(now)
		end
	end
end

-------------------------------------------------------------------------------
-- player actions (RingService validates types and rate limits first)
-------------------------------------------------------------------------------

function RingLogic:canSubmit(id: number): boolean
	return self.phase == "playing" and self.round ~= nil and self.round.holder == id
end

-- `text` is what the text filter returned. If the filter changed it, the answer
-- counts as wrong and luck never rescues it.
function RingLogic:submit(id: number, text: string, filterChanged: boolean, luckLevel: number, now: number)
	self:step(now)
	if not self:canSubmit(id) then
		return { ok = false, reason = "not_your_turn" }
	end
	local d = self.deps
	local c = d.Config
	local r = self.round
	local p = self.players[id]

	local result
	if filterChanged then
		result = { ok = false, reason = "filtered", input = text }
	else
		result = d.Luck.submit(r.answers, text, luckLevel or 0, true, d.rng)
	end

	if not result.ok then
		self:_emit({ type = "reply", to = id, ok = false, reason = result.reason, display = result.display, text = text })
		self:_feed("wrong", { userId = id, name = p.name, text = text, reason = result.reason, display = result.display })
		return result
	end

	local tier = d.Rarity.get(result.tier)
	local diving = r.turn.diveEndsAt ~= nil
	local base = {
		userId = id,
		name = p.name,
		text = text,
		display = result.display,
		tier = tier.id,
		tierName = tier.name,
		tierColor = tier.color,
		lucky = result.lucky,
		from = result.originalDisplay,
	}

	if diving and tier.id < c.DIVE_MIN_TIER then
		-- the answer is burned, nothing is earned, and the turn carries on
		base.coins = 0
		base.deflate = 0
		base.dive = "miss"
		self:_emit({ type = "reply", to = id, ok = true, kept = true, display = result.display, tier = tier.id, lucky = result.lucky, from = result.originalDisplay })
		self:_feed("answer", base)
		self:_diveMiss(now, "shallow")
		return result
	end

	local mult = if diving then c.DIVE_MULTIPLIER else 1
	local coins = tier.coins * mult
	local deflate = tier.deflate * mult
	self:_freezeAir(now)
	r.airBase = math.max(0, r.airBase - deflate)
	r.turn.diveEndsAt = nil

	local m = self.match
	m.coins[id] = (m.coins[id] or 0) + coins
	if not m.best or tier.id > m.best.tier then
		m.best = { userId = id, name = p.name, display = result.display, tier = tier.id, tierName = tier.name }
	end
	if coins > 0 then
		self:_emit({ type = "coins", userId = id, amount = coins, reason = "answer" })
	end

	base.coins = coins
	base.deflate = deflate
	base.dive = if diving then "hit" else nil
	self:_emit({ type = "reply", to = id, ok = true, kept = false, display = result.display, tier = tier.id, coins = coins, lucky = result.lucky, from = result.originalDisplay })
	self:_feed("answer", base)
	if tier.announce then
		self:_emit({ type = "banner", userId = id, name = p.name, display = result.display, tier = tier.id, tierName = tier.name, prompt = r.prompt })
	end

	if tier.chooseTarget then
		self.phase = "picking"
		self.endsAt = now + c.PICK_TIME
		r.pickBonus = tier.bonusInflate
		self:_feed("picking", { userId = id, name = p.name, bonus = tier.bonusInflate })
		self:_changed()
	else
		local nextP = self:_nextClockwise(id) :: Player
		self:_giveTo(nextP, now, tier.bonusInflate, "clockwise", p)
	end
	return result
end

function RingLogic:pick(id: number, targetId: number, now: number): (boolean, string?)
	self:step(now)
	if self.phase ~= "picking" or self.round.holder ~= id then
		return false, "not_picking"
	end
	local target = self.players[targetId]
	if not target or target.status ~= "alive" or target.id == id then
		return false, "bad_target"
	end
	self:_giveTo(target, now, self.round.pickBonus, "picked", self.players[id])
	return true
end

function RingLogic:dive(id: number, now: number): (boolean, string?)
	self:step(now)
	if not self:canSubmit(id) then
		return false, "not_your_turn"
	end
	local turn = self.round.turn
	if turn.diveUsed then
		return false, "already_dived"
	end
	turn.diveUsed = true
	turn.diveEndsAt = now + self.deps.Config.DIVE_WINDOW
	local p = self.players[id]
	self:_feed("dive", { userId = id, name = p.name, endsAt = turn.diveEndsAt })
	self:_changed()
	return true
end

-------------------------------------------------------------------------------
-- what clients see (no air, no pop point)
-------------------------------------------------------------------------------

function RingLogic:snapshot(now: number)
	local seats = {}
	for i = 1, self.seatCount do
		local p = self.seats[i]
		if p then
			table.insert(seats, { seat = i, userId = p.id, name = p.name, status = p.status })
		end
	end
	local r = self.round
	local turn = r and r.turn
	return {
		ringId = self.id,
		ranked = self.ranked,
		phase = self.phase,
		endsAt = self.endsAt,
		minPlayers = self:minPlayers(),
		seatCount = self.seatCount,
		seats = seats,
		holder = r and r.holder,
		puff = self:puffStage(now),
		prompt = r and r.prompt,
		categoryName = r and r.categoryName,
		roundNumber = r and r.number,
		diveUsed = turn and turn.diveUsed or false,
		diveEndsAt = turn and turn.diveEndsAt,
		results = self.results,
	}
end

return RingLogic
