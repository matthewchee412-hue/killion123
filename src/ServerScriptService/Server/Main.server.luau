--[[
	Server entry point. Builds placeholder rings if the map has none yet,
	then starts every ring.
]]

local Server = script.Parent

require(Server.Rings.PlaceholderRings).ensure()
require(Server.Rings.RingService).start()
