--!strict
-- ComplianceService: wrapper PolicyService untuk item acak berbayar (docs/RULES.md §4, ECONOMY §2).
-- - GetPolicyInfoForPlayerAsync dipanggil dalam pcall. Gagal atau bentuk hasil tak terduga → restricted
--   (fail-closed), di-log, dan dicoba lagi setelah Constants.POLICY_RETRY_SECONDS.
-- - Hasil sukses di-cache per sesi pemain dan dibersihkan saat PlayerRemoving.
-- - Permintaan bersamaan untuk pemain yang sama menunggu satu fetch yang sedang berjalan (tanpa duplikasi).
-- - Perintah admin Studio (server Command Bar saja, tanpa remote) bisa memaksa restricted untuk UserId
--   yang ada di Constants.ADMIN_USER_IDS.
-- Fungsi ini boleh yield; panggil SEBELUM commit DataService, jangan di dalamnya.
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)

type Entry = { restricted: boolean, retryAt: number? }
type Flight = { waiters: { thread } }

export type CacheOptions = {
	fetch: (player: Player) -> any, -- boleh error/yield; dibungkus pcall
	isPresent: (player: Player) -> boolean,
	now: () -> number,
	retrySeconds: number,
	log: ((message: string) -> ())?,
	-- Pembaca field kebijakan → restricted (true = blok). Default: ArePaidRandomItemsRestricted.
	read: ((info: any) -> boolean?)?,
}

export type Cache = {
	isRestricted: (player: Player) -> boolean,
	peek: (player: Player) -> boolean?,
	setForced: (player: Player, forced: boolean) -> (),
	clear: (player: Player) -> (),
}

local ComplianceService = {}

-- Trade item berbayar (prompt 11): restricted = NOT IsPaidItemTradingAllowed. Bukan boolean → nil (fail-closed).
-- TODO(verify-api): halaman referensi PolicyService saat ini tidak mendaftar field hasil
-- GetPolicyInfoForPlayerAsync; nama field ini perlu dikonfirmasi di place uji. Field hilang = trade diblok.
function ComplianceService.readTradeRestricted(info: any): boolean?
	if type(info) ~= "table" then
		return nil
	end
	local value = info.IsPaidItemTradingAllowed
	return if type(value) == "boolean" then not value else nil
end

-- Membaca field kebijakan dari hasil PolicyService. Apa pun selain boolean → nil (pemanggil fail-closed).
function ComplianceService.readRestricted(info: any): boolean?
	if type(info) ~= "table" then
		return nil
	end
	local value = info.ArePaidRandomItemsRestricted
	return if type(value) == "boolean" then value else nil
end

function ComplianceService.createCache(options: CacheOptions): Cache
	local cache: { [Player]: Entry } = {}
	local flights: { [Player]: Flight } = {}
	local forced: { [Player]: boolean } = {}
	local log = options.log or warn
	local read = options.read or ComplianceService.readRestricted

	local function peek(player: Player): boolean?
		if forced[player] then
			return true
		end
		local entry = cache[player]
		if not entry then
			return nil
		end
		if entry.retryAt and options.now() >= entry.retryAt then
			return nil
		end
		return entry.restricted
	end

	-- (restricted, sukses). Gagal = (true, false): fail-closed.
	local function fetchOnce(player: Player): (boolean, boolean)
		local ok, result = pcall(options.fetch, player)
		local restricted = if ok then read(result) else nil
		if restricted == nil then
			log(`[ComplianceService] policy lookup failed for UserId={player.UserId}: {result}; fail-closed`)
			return true, false
		end
		return restricted, true
	end

	local function isRestricted(player: Player): boolean
		local known = peek(player)
		if known ~= nil then
			return known
		end
		local flight = flights[player]
		if flight then
			table.insert(flight.waiters, coroutine.running())
			local result = coroutine.yield()
			return if forced[player] then true elseif type(result) == "boolean" then result else true
		end
		local current: Flight = { waiters = {} }
		flights[player] = current
		local value, succeeded = fetchOnce(player)
		-- clear() saat pemain keluar membatalkan flight: hasilnya tidak di-cache.
		if flights[player] == current then
			flights[player] = nil
			if options.isPresent(player) then
				cache[player] = if succeeded
					then { restricted = value, retryAt = nil }
					else { restricted = true, retryAt = options.now() + options.retrySeconds }
			end
		end
		for _, waiter in current.waiters do
			task.spawn(waiter, value)
		end
		return if forced[player] then true else value
	end

	return {
		isRestricted = isRestricted,
		peek = peek,
		setForced = function(player: Player, value: boolean)
			forced[player] = if value then true else nil
		end,
		clear = function(player: Player)
			cache[player] = nil
			forced[player] = nil
			local flight = flights[player]
			flights[player] = nil
			if flight then
				-- Lepaskan penunggu sekarang (fail-closed); daftar dikosongkan agar fetch tidak me-resume dua kali.
				local waiters = table.clone(flight.waiters)
				table.clear(flight.waiters)
				for _, waiter in waiters do
					task.spawn(waiter, true)
				end
			end
		end,
	}
end

local function fetchPolicy(player: Player): any
	return PolicyService:GetPolicyInfoForPlayerAsync(player)
end

local function isPresent(player: Player): boolean
	return player.Parent == Players
end

local defaultCache = ComplianceService.createCache({
	fetch = fetchPolicy,
	isPresent = isPresent,
	now = os.clock,
	retrySeconds = Constants.POLICY_RETRY_SECONDS,
})
-- Cache terpisah untuk trade (field kebijakan berbeda, perilaku fail-closed & retry sama).
local tradeCache = ComplianceService.createCache({
	fetch = fetchPolicy,
	isPresent = isPresent,
	now = os.clock,
	retrySeconds = Constants.POLICY_RETRY_SECONDS,
	read = ComplianceService.readTradeRestricted,
})
local tradeOverride: { [Player]: boolean } = {}

-- true hanya bila kebijakan pemain secara afirmatif mengizinkan trade item berbayar. Boleh yield.
-- Provenance item (dibeli vs gameplay) belum tercatat andal, jadi SEMUA trade memakai syarat ini.
function ComplianceService.isPaidItemTradingAllowed(player: Player): boolean
	local forced = tradeOverride[player]
	if forced ~= nil then
		return forced
	end
	return not tradeCache.isRestricted(player)
end

-- Studio server Command Bar saja: paksa hasil kebijakan trade untuk UserId di Constants.ADMIN_USER_IDS.
-- nil = lepas override. Hanya untuk menguji alur trade di Studio (kebijakan asli tidak berubah).
function ComplianceService.adminForceTradeAllowed(player: Player, allowed: boolean?): boolean
	if not RunService:IsStudio() or (allowed ~= nil and typeof(allowed) ~= "boolean") then
		return false
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if table.find(Constants.ADMIN_USER_IDS, player.UserId) == nil then
		return false
	end
	tradeOverride[player] = allowed
	return true
end

-- true = item acak berbayar (summon Gems, reroll Shards) harus diblok untuk pemain ini. Boleh yield.
function ComplianceService.isPaidRandomRestricted(player: Player): boolean
	return defaultCache.isRestricted(player)
end

-- Nilai cache tanpa yield; nil = belum diketahui.
function ComplianceService.peekPaidRandomRestricted(player: Player): boolean?
	return defaultCache.peek(player)
end

-- Studio server Command Bar saja: paksa (true) atau lepaskan (false) status restricted untuk pemain uji
-- yang UserId-nya ada di Constants.ADMIN_USER_IDS. Tidak bisa memaksa pemain menjadi TIDAK restricted.
function ComplianceService.adminForceRestricted(player: Player, restricted: boolean): boolean
	if not RunService:IsStudio() or typeof(restricted) ~= "boolean" then
		return false
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if table.find(Constants.ADMIN_USER_IDS, player.UserId) == nil then
		return false
	end
	defaultCache.setForced(player, restricted)
	return true
end

function ComplianceService.init(): () end

function ComplianceService.start(): ()
	Players.PlayerRemoving:Connect(defaultCache.clear)
	Players.PlayerRemoving:Connect(function(player: Player)
		tradeCache.clear(player)
		tradeOverride[player] = nil
	end)
end

return ComplianceService
