--[[
	RoundConfig — timings and limits for Blowfish Blowout rings.

	Shared so the client can show the same numbers (countdown lengths,
	minimum players). The pop point of each round is rolled on the server
	from POP_MIN..POP_MAX and never sent to clients.
]]

return {
	MIN_PLAYERS_CASUAL = 2,
	MIN_PLAYERS_RANKED = 4,

	COUNTDOWN = 15,      -- seconds once enough players are seated
	COUNTDOWN_FULL = 8,  -- seconds when every seat is full

	AIR_PER_SECOND = 1,  -- air fills while someone holds the blowfish
	POP_MIN = 18,        -- hidden pop point, rolled per round
	POP_MAX = 30,

	PICK_TIME = 10,      -- Midnight/Abyss: time to choose the next holder

	DIVE_WINDOW = 5,     -- Dive Deeper: seconds to land a Twilight+ answer
	DIVE_MIN_TIER = 2,   -- Twilight
	DIVE_MULTIPLIER = 2, -- air let out and coins on a hit
	DIVE_MISS_AIR = 3,   -- extra air on a miss

	ROUND_GAP = 3,       -- after a pop, before the next category
	RESULTS_TIME = 6,

	CATEGORY_MIN_SIZE = 30,
	MAX_ANSWER_LENGTH = 40, -- characters

	-- How puffed the blowfish looks, as a share of the hidden pop point.
	-- Clients get the stage (0..#PUFF_STAGES), never the air. The last stage flashes red.
	PUFF_STAGES = { 0.25, 0.5, 0.7, 0.85 },

	-- Token buckets per player: `burst` requests at once, refilling at `perSecond`.
	RATE_LIMITS = {
		SubmitAnswer = { burst = 4, perSecond = 2 },
		PickTarget = { burst = 3, perSecond = 1 },
		DiveDeeper = { burst = 2, perSecond = 0.5 },
	},
}
