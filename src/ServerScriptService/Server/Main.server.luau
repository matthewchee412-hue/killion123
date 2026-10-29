--[[
	Server entry point. Builds the map (terrain, beach and the six rings),
	then starts every ring.
]]

local Server = script.Parent

require(Server.Map.MapBuilder).build()
require(Server.Rings.RingService).start()
