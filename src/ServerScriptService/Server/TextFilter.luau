--[[
	TextFilter — runs a player's answer through Roblox's text filter before
	anyone else sees it.

		local text, changed = TextFilter.answer(player, raw) -- yields
		-- text: what everyone may see; changed: the filter hid something
		-- text is nil if the filter call failed (ask them to try again)
]]

local TextService = game:GetService("TextService")

local TextFilter = {}

function TextFilter.answer(player: Player, raw: string): (string?, boolean)
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(raw, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(filtered) ~= "string" then
		warn("[TextFilter] filter failed for", player.Name, filtered)
		return nil, true
	end
	return filtered, filtered ~= raw
end

return TextFilter
