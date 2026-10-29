--[[
	Remotes — the one RemoteEvents folder in ReplicatedStorage.

	Client -> server:
		SubmitAnswer(text: string)
		PickTarget(userId: number)
		DiveDeeper()
	Server -> client:
		RingUpdate(message), where message.kind is one of
			"state"  { ring = snapshot }        full ring state (RingLogic:snapshot)
			"feed"   { ringId, event, line }    commentary (FeedFormat)
			"reply"  { ringId, ok, reason, ... } result of your own answer (shake on wrong)
			"banner" { name, display, ... }     Abyss answer, sent to everyone
			"left"   { ringId }                 you're no longer in that ring
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "SubmitAnswer", "PickTarget", "DiveDeeper", "RingUpdate" }

local Remotes = {}

function Remotes.setup(): { [string]: RemoteEvent }
	local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = ReplicatedStorage
	end
	local out = {}
	for _, name in NAMES do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		out[name] = remote
	end
	return out
end

return Remotes
