--[[
	Rewards — where round coins go.

	For now coins only go on a "Coins" player attribute. The player data step
	(ProfileStore, prompt 5) replaces Rewards.give with real saved coins; the
	round code doesn't need to change.
]]

local Rewards = {}

function Rewards.give(player: Player, amount: number, reason: string)
	if amount <= 0 then
		return
	end
	player:SetAttribute("Coins", (player:GetAttribute("Coins") or 0) + amount)
end

return Rewards
