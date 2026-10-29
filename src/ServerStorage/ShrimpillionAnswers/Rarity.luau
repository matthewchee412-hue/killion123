--[[
	Rarity — the five depth tiers and what each one does to the blowfish.

	Safe to copy into ReplicatedStorage too, so the client UI can use the
	same names and colours.

	Tier numbers come from AnswerMatcher results (result.tier).
	Every tuning number for the Blowfish Blowout lives here, so balancing the
	game means editing this table, not the round code.
]]

export type TierInfo = {
	id: number,
	name: string,
	blurb: string,
	color: Color3,
	depth: number,        -- metres, for the "you sank to 3,200 m" flavour
	coins: number,        -- reward per answer
	deflate: number,      -- seconds of air let out of the blowfish (0 = none)
	chooseTarget: boolean,-- answerer picks who gets the blowfish next
	bonusInflate: number, -- extra seconds of air pumped into the NEXT holder's timer
	announce: boolean,    -- server-wide banner
}

local Rarity = {}

Rarity.tiers = {
	[0] = {
		id = 0, name = "Shallows", blurb = "everyone says that one",
		color = Color3.fromRGB(150, 220, 255), depth = 10,
		coins = 1, deflate = 0, chooseTarget = false, bonusInflate = 0, announce = false,
	},
	[1] = {
		id = 1, name = "Reef", blurb = "nice one",
		color = Color3.fromRGB(80, 200, 170), depth = 200,
		coins = 3, deflate = 1, chooseTarget = false, bonusInflate = 0, announce = false,
	},
	[2] = {
		id = 2, name = "Twilight", blurb = "ooh, rare!",
		color = Color3.fromRGB(90, 120, 230), depth = 1000,
		coins = 6, deflate = 2, chooseTarget = false, bonusInflate = 0, announce = false,
	},
	[3] = {
		id = 3, name = "Midnight", blurb = "deep cut — you pick who gets it",
		color = Color3.fromRGB(160, 80, 230), depth = 4000,
		coins = 12, deflate = 3, chooseTarget = true, bonusInflate = 0, announce = false,
	},
	[4] = {
		id = 4, name = "Abyss", blurb = "who even knows that?!",
		color = Color3.fromRGB(255, 150, 50), depth = 11000,
		coins = 25, deflate = 5, chooseTarget = true, bonusInflate = 2, announce = true,
	},
} :: { [number]: TierInfo }

Rarity.ABYSS = 4

function Rarity.get(tier: number?): TierInfo
	return Rarity.tiers[tier or 0] or Rarity.tiers[0]
end

return Rarity
