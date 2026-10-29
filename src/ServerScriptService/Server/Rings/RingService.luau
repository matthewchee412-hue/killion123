--[[
	RingService — runs every ring in workspace.Rings at the same time.

	Each ring is a Model with Seat parts (anywhere inside it), a "Centre" (or
	"Center") part and a Ranked attribute. Seats are numbered clockwise seen
	from above; a seat's "SeatIndex" attribute overrides that order.

	The game rules live in RingLogic. This module connects them to Roblox:
	seats, the text filter, remotes (with type checks and rate limits),
	coins, ghosts, and the ring attributes the signs and HUD read:
		Phase, EndsAt (server time), Holder (UserId, 0 = none), Puff (0..4),
		Prompt, Seated, MinPlayers.

	RingService.MatchEnded (BindableEvent) fires with
		{ ringId, ranked, rounds, placements = { { userId, name, place, coins } } }
	for ranked points and win rewards later.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Answers = ServerStorage:WaitForChild("ShrimpillionAnswers")
local Matcher = require(Answers.AnswerMatcher)
local Luck = require(Answers.Luck)
local Rarity = require(Answers.Rarity)
local Categories = require(Answers.Categories)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.RoundConfig)
local FeedFormat = require(Shared.FeedFormat)

local Server = script.Parent.Parent
local RingLogic = require(script.Parent.RingLogic)
local RateLimiter = require(Server.RateLimiter)
local TextFilter = require(Server.TextFilter)
local Rewards = require(Server.Rewards)
local Remotes = require(Server.Remotes)

local RingService = {}
RingService.MatchEnded = Instance.new("BindableEvent")

type RingEntry = {
	model: Model,
	logic: any,
	seats: { Seat },
	seatIndex: { [Seat]: number },
	occupant: { [Seat]: Player },
	dirty: boolean,
	members: { [number]: Player }, -- everyone seated, by UserId
}

local rings: { [string]: RingEntry } = {}
local ringOf: { [number]: RingEntry } = {} -- UserId -> ring they sit in
local pending: { [number]: boolean } = {} -- answer waiting on the text filter
local remotes: { [string]: RemoteEvent }
local limiters: { [string]: any } = {}
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function log(ringId: string, line: string)
	print(string.format("[Ring %s %.1f] %s", ringId, now() % 1000, line))
end

local function sendRing(entry: RingEntry, message)
	for _, player in entry.members do
		remotes.RingUpdate:FireClient(player, message)
	end
end

-------------------------------------------------------------------------------
-- ghosts
-------------------------------------------------------------------------------

local function setGhost(player: Player, ghost: boolean)
	player:SetAttribute("Ghost", ghost)
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			if ghost then
				if d:GetAttribute("GhostBase") == nil then
					d:SetAttribute("GhostBase", d.Transparency)
				end
				d.Transparency = math.max(d.Transparency, 0.6)
			elseif d:GetAttribute("GhostBase") ~= nil then
				d.Transparency = d:GetAttribute("GhostBase")
				d:SetAttribute("GhostBase", nil)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- events from RingLogic
-------------------------------------------------------------------------------

local function syncGhosts(entry: RingEntry)
	for _, p in entry.logic.players do
		local player = entry.members[p.id]
		if player then
			local ghost = p.status == "ghost"
			if (player:GetAttribute("Ghost") == true) ~= ghost then
				setGhost(player, ghost)
			end
		end
	end
end

local function flush(entry: RingEntry)
	if not entry.dirty then
		return
	end
	entry.dirty = false
	local t = now()
	local snap = entry.logic:snapshot(t)
	local model = entry.model
	model:SetAttribute("Phase", snap.phase)
	model:SetAttribute("EndsAt", snap.endsAt or 0)
	model:SetAttribute("Holder", snap.holder or 0)
	model:SetAttribute("Puff", snap.puff)
	model:SetAttribute("Prompt", snap.prompt or "")
	model:SetAttribute("Seated", #snap.seats)
	model:SetAttribute("MinPlayers", snap.minPlayers)
	syncGhosts(entry)
	sendRing(entry, { kind = "state", ring = snap })
end

local function onEvent(entry: RingEntry, event)
	local kind = event.type
	if kind == "state" then
		entry.dirty = true
	elseif kind == "feed" then
		local line = FeedFormat.line(event)
		log(entry.model.Name, line)
		sendRing(entry, { kind = "feed", ringId = entry.model.Name, event = event, line = line })
	elseif kind == "reply" then
		local player = entry.members[event.to]
		if player then
			event.kind = "reply"
			event.ringId = entry.model.Name
			remotes.RingUpdate:FireClient(player, event)
		end
	elseif kind == "coins" then
		local player = entry.members[event.userId] or Players:GetPlayerByUserId(event.userId)
		if player then
			Rewards.give(player, event.amount, event.reason)
		end
	elseif kind == "banner" then
		event.kind = "banner"
		event.ringId = entry.model.Name
		remotes.RingUpdate:FireAllClients(event)
	elseif kind == "matchEnded" then
		RingService.MatchEnded:Fire({
			ringId = entry.model.Name,
			ranked = event.ranked,
			rounds = event.rounds,
			placements = event.placements,
		})
	end
end

-------------------------------------------------------------------------------
-- seats
-------------------------------------------------------------------------------

local function centreOf(model: Model): Vector3
	local c = model:FindFirstChild("Centre", true) or model:FindFirstChild("Center", true)
	if c and c:IsA("BasePart") then
		return c.Position
	elseif c and c:IsA("Attachment") then
		return c.WorldPosition
	end
	return model:GetPivot().Position
end

-- clockwise seen from above: +X is screen-right and +Z is screen-down, so
-- the angle atan2(z, x) grows clockwise
local function orderSeats(model: Model): { Seat }
	local centre = centreOf(model)
	local seats = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Seat") then
			table.insert(seats, d)
		end
	end
	local function key(seat: Seat): number
		local fixed = seat:GetAttribute("SeatIndex")
		if type(fixed) == "number" then
			return fixed - 1000
		end
		local offset = seat.Position - centre
		return math.atan2(offset.Z, offset.X)
	end
	table.sort(seats, function(a, b)
		return key(a) < key(b)
	end)
	return seats
end

local function leaveRing(player: Player)
	local entry = ringOf[player.UserId]
	if not entry then
		return
	end
	ringOf[player.UserId] = nil
	entry.logic:stand(player.UserId, now())
	entry.members[player.UserId] = nil
	if player.Parent then
		setGhost(player, false)
		player:SetAttribute("Ring", nil)
		remotes.RingUpdate:FireClient(player, { kind = "left", ringId = entry.model.Name })
	end
	flush(entry)
end

local function onOccupantChanged(entry: RingEntry, seat: Seat)
	local humanoid = seat.Occupant
	local player = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
	local previous = entry.occupant[seat]
	if previous == player then
		return
	end
	if previous then
		entry.occupant[seat] = nil
		if ringOf[previous.UserId] == entry then
			leaveRing(previous)
		end
	end
	if player then
		if ringOf[player.UserId] then
			leaveRing(player) -- moved straight from another seat
		end
		entry.occupant[seat] = player
		entry.members[player.UserId] = player
		ringOf[player.UserId] = entry
		player:SetAttribute("Ring", entry.model.Name)
		if not entry.logic:sit(entry.seatIndex[seat], player.UserId, player.DisplayName, now()) then
			entry.members[player.UserId] = nil
			ringOf[player.UserId] = nil
			player:SetAttribute("Ring", nil)
		end
		flush(entry)
	end
end

local function addRing(model: Instance)
	if not model:IsA("Model") or rings[model.Name] then
		return
	end
	local seats = orderSeats(model)
	if #seats < 2 then
		warn("[RingService] ring", model.Name, "has fewer than 2 seats, skipped")
		return
	end
	local entry: RingEntry
	entry = {
		model = model,
		seats = seats,
		seatIndex = {},
		occupant = {},
		dirty = true,
		members = {},
		logic = RingLogic.new(model.Name, #seats, model:GetAttribute("Ranked") == true, {
			Matcher = Matcher,
			Luck = Luck,
			Rarity = Rarity,
			Categories = Categories,
			Config = Config,
			rng = rng,
			emit = function(event)
				onEvent(entry, event)
			end,
		}),
	}
	for i, seat in seats do
		entry.seatIndex[seat] = i
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			onOccupantChanged(entry, seat)
		end)
	end
	model:GetAttributeChangedSignal("Ranked"):Connect(function()
		-- only takes effect between games
		if entry.logic.phase == "waiting" then
			entry.logic.ranked = model:GetAttribute("Ranked") == true
			entry.dirty = true
		end
	end)
	rings[model.Name] = entry
	flush(entry)
	log(model.Name, string.format("ready: %d seats, %s", #seats, if entry.logic.ranked then "Ranked" else "Casual"))
end

-------------------------------------------------------------------------------
-- remotes
-------------------------------------------------------------------------------

local function allowed(name: string, player: Player): boolean
	return limiters[name]:allow(player.UserId, os.clock())
end

-- trims, drops control characters and caps the length; nil if unusable
local function cleanAnswer(text: any): string?
	if type(text) ~= "string" or #text == 0 or #text > 200 or not utf8.len(text) then
		return nil
	end
	text = string.gsub(text, "%c", " ")
	text = string.match(text, "^%s*(.-)%s*$") :: string
	if text == "" then
		return nil
	end
	if utf8.len(text) > Config.MAX_ANSWER_LENGTH then
		text = string.sub(text, 1, utf8.offset(text, Config.MAX_ANSWER_LENGTH + 1) - 1)
	end
	return text
end

local function onSubmit(player: Player, raw: any)
	if not allowed("SubmitAnswer", player) then
		return
	end
	local entry = ringOf[player.UserId]
	local text = cleanAnswer(raw)
	if not entry or not text then
		return
	end
	if not entry.logic:canSubmit(player.UserId) then
		remotes.RingUpdate:FireClient(player, { kind = "reply", ringId = entry.model.Name, ok = false, reason = "not_your_turn" })
		return
	end
	if pending[player.UserId] then
		return
	end
	pending[player.UserId] = true
	local filtered, changed = TextFilter.answer(player, text)
	pending[player.UserId] = nil
	if ringOf[player.UserId] ~= entry then
		return -- stood up while the filter ran
	end
	if not filtered then
		remotes.RingUpdate:FireClient(player, { kind = "reply", ringId = entry.model.Name, ok = false, reason = "filter_error" })
		return
	end
	local luck = player:GetAttribute("Luck")
	entry.logic:submit(player.UserId, filtered, changed, if type(luck) == "number" then luck else 0, now())
	flush(entry)
end

local function onPick(player: Player, targetId: any)
	if not allowed("PickTarget", player) then
		return
	end
	local entry = ringOf[player.UserId]
	if not entry or type(targetId) ~= "number" or targetId ~= targetId or targetId % 1 ~= 0 then
		return
	end
	entry.logic:pick(player.UserId, targetId, now())
	flush(entry)
end

local function onDive(player: Player)
	if not allowed("DiveDeeper", player) then
		return
	end
	local entry = ringOf[player.UserId]
	if entry then
		entry.logic:dive(player.UserId, now())
		flush(entry)
	end
end

-------------------------------------------------------------------------------
-- start
-------------------------------------------------------------------------------

function RingService.start()
	remotes = Remotes.setup()
	for name, limit in Config.RATE_LIMITS do
		limiters[name] = RateLimiter.new(limit.burst, limit.perSecond)
	end

	local t = os.clock()
	Matcher.preloadAll()
	print(string.format("[RingService] answer banks loaded in %d ms", (os.clock() - t) * 1000))

	remotes.SubmitAnswer.OnServerEvent:Connect(onSubmit)
	remotes.PickTarget.OnServerEvent:Connect(onPick)
	remotes.DiveDeeper.OnServerEvent:Connect(onDive)

	Players.PlayerRemoving:Connect(function(player)
		leaveRing(player)
		pending[player.UserId] = nil
		for _, limiter in limiters do
			limiter:forget(player.UserId)
		end
	end)

	local folder = workspace:WaitForChild("Rings")
	for _, model in folder:GetChildren() do
		addRing(model)
	end
	folder.ChildAdded:Connect(addRing)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local t = now()
		for _, entry in rings do
			entry.logic:step(t)
			flush(entry)
		end
	end)
end

return RingService
