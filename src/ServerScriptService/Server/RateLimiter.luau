--[[
	RateLimiter — a token bucket per key (usually a UserId). No Roblox services.

		local limiter = RateLimiter.new(4, 2) -- 4 at once, then 2 per second
		if not limiter:allow(player.UserId, os.clock()) then return end
		limiter:forget(player.UserId)         -- on PlayerRemoving
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(burst: number, perSecond: number)
	return setmetatable({ burst = burst, perSecond = perSecond, buckets = {} }, RateLimiter)
end

function RateLimiter:allow(key: any, now: number): boolean
	local b = self.buckets[key]
	if not b then
		b = { tokens = self.burst, at = now }
		self.buckets[key] = b
	end
	b.tokens = math.min(self.burst, b.tokens + (now - b.at) * self.perSecond)
	b.at = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

function RateLimiter:forget(key: any)
	self.buckets[key] = nil
end

return RateLimiter
