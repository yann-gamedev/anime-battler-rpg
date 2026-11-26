--!strict
-- Rate limit fixed-window per pemain per key. Data pemain dibersihkan saat PlayerRemoving.
local Players = game:GetService("Players")

type Bucket = { windowStart: number, count: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

local RateLimiter = {}

-- true jika aksi diizinkan (dan dihitung), false jika melewati batas.
function RateLimiter.allow(player: Player, key: string, maxPerWindow: number, windowSec: number): boolean
	if player.Parent ~= Players then
		return false
	end
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[key]
	if not bucket or now - bucket.windowStart >= windowSec then
		perPlayer[key] = { windowStart = now, count = 1 }
		return maxPerWindow >= 1
	end
	if bucket.count >= maxPerWindow then
		return false
	end
	bucket.count += 1
	return true
end

function RateLimiter.clear(player: Player)
	buckets[player] = nil
end

Players.PlayerRemoving:Connect(RateLimiter.clear)

return RateLimiter
