--!strict
-- Bagian DataService: SATU-SATUNYA pemanggil DataStore `TradeLog` (RULES §3). TradeService memanggil lewat
-- DataService.trades. Semua fungsi boleh yield; JANGAN dipanggil di dalam swap tanpa yield.
--
-- Kunci (≤ 50 karakter, docs "Error codes and limits"):
--   u/<userId>          indeks jurnal per pemain: { [tradeId] = at }  (dibatasi Trade.log.maxPendingPerUser)
--   t/<tradeId>         register keputusan satu trade: { state = "committed", record } | { state = "aborted" }
--   d/<hariUTC>/<shard> log harian per bucket: entries[tradeId] = record (append idempoten, dibatasi)
--   f/<hariUTC>         flag dupe UID: daftar entri (dibatasi)
-- Keputusan memakai UpdateAsync pada SATU kunci (baca-ubah-tulis berurutan per kunci), jadi "commit" dari
-- server trade dan "abort" dari pemulihan tidak bisa sama-sama menang. UpdateAsync bisa gagal walau
-- tulisan backend terjadi, jadi hasil gagal = TIDAK DIKETAHUI, bukan "tidak tertulis".
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TradeTypes = require(Shared.TradeTypes)
local Trade = require(Shared.Config.Trade)

type TradeRecord = TradeTypes.TradeRecord
export type Decision = "committed" | "aborted"
export type StoreLike = {
	UpdateAsync: (any, string, (any, any) -> any) -> any,
	GetAsync: (any, string, any?) -> any,
}
export type Options = {
	sleep: ((seconds: number) -> ())?,
	log: ((message: string) -> ())?,
	getOptions: any?, -- DataStoreGetOptions dengan UseCache = false (bypass cache 4 detik)
}
export type Log = {
	readPending: (userId: number) -> (boolean, { [string]: number }?),
	addPending: (userId: number, tradeId: string, at: number) -> string?,
	removePending: (userId: number, tradeId: string) -> boolean,
	decide: (record: TradeRecord) -> (Decision?, TradeRecord?),
	resolve: (tradeId: string) -> (Decision?, TradeRecord?),
	appendDaily: (record: TradeRecord) -> string?,
	flagDupe: (day: number, entry: { [string]: any }) -> boolean,
}

local LOG = Trade.log
local TradeLog = {}

function TradeLog.shardOf(tradeId: string): number
	local hash = 0
	for index = 1, #tradeId do
		hash = (hash * 31 + string.byte(tradeId, index)) % 2147483647
	end
	return hash % LOG.dailyShards
end

function TradeLog.create(store: StoreLike, options: Options): Log
	local sleep = options.sleep or task.wait
	local log = options.log or warn

	-- pcall + retry terbatas. Mengembalikan (true, hasil) atau (false, nil) setelah semua percobaan gagal.
	local function attempt(label: string, call: () -> any): (boolean, any)
		for index = 1, LOG.retryAttempts do
			local ok, result = pcall(call)
			if ok then
				return true, result
			end
			log(`[TradeLog] {label} gagal (percobaan {index}): {result}`)
			if index < LOG.retryAttempts then
				sleep(LOG.retryBackoffSeconds * index)
			end
		end
		return false, nil
	end

	local function readPending(userId: number): (boolean, { [string]: number }?)
		local ok, value = attempt(`read u/{userId}`, function()
			return store:GetAsync(`u/{userId}`, options.getOptions)
		end)
		if not ok then
			return false, nil
		end
		local pending: { [string]: number } = {}
		if type(value) == "table" then
			for tradeId, at in value do
				if type(tradeId) == "string" and type(at) == "number" then
					pending[tradeId] = at
				end
			end
		end
		return true, pending
	end

	local function addPending(userId: number, tradeId: string, at: number): string?
		local code: string? = nil
		local ok = attempt(`add u/{userId}`, function()
			return store:UpdateAsync(`u/{userId}`, function(old: any)
				local pending = if type(old) == "table" then old else {}
				code = nil
				if pending[tradeId] ~= nil then
					return nil -- sudah tercatat: idempoten, tanpa tulis
				end
				local count = 0
				for _ in pending do
					count += 1
				end
				if count >= LOG.maxPendingPerUser then
					code = "TRADE_RECOVERY_PENDING"
					return nil
				end
				pending[tradeId] = at
				return pending
			end)
		end)
		return if ok then code else "TRADE_LOG_UNAVAILABLE"
	end

	local function removePending(userId: number, tradeId: string): boolean
		local ok = attempt(`remove u/{userId}`, function()
			return store:UpdateAsync(`u/{userId}`, function(old: any)
				if type(old) ~= "table" or old[tradeId] == nil then
					return nil
				end
				old[tradeId] = nil
				return old
			end)
		end)
		return ok
	end

	-- Register keputusan. `desired` = "committed" (server trade) atau "aborted" (pemulihan).
	-- Kunci kosong → desired ditulis. Kunci terisi → keputusan yang ada menang (tanpa tulis).
	local function settle(tradeId: string, desired: Decision, record: TradeRecord?): (Decision?, TradeRecord?)
		local state: Decision? = nil
		local stored: TradeRecord? = nil
		local ok = attempt(`settle t/{tradeId}`, function()
			return store:UpdateAsync(`t/{tradeId}`, function(old: any)
				if type(old) == "table" and (old.state == "committed" or old.state == "aborted") then
					state = old.state
					stored = if old.state == "committed" then old.record else nil
					return nil
				end
				state = desired
				stored = record
				return { state = desired, record = record }
			end)
		end)
		if not ok then
			return nil, nil -- tidak diketahui: tulisan mungkin sudah terjadi di backend
		end
		if state == "committed" and (type(stored) ~= "table" or stored.tradeId ~= tradeId) then
			log(`[TradeLog] t/{tradeId} committed tanpa rekaman sah; fail-closed`)
			return nil, nil
		end
		return state, stored
	end

	local function decide(record: TradeRecord): (Decision?, TradeRecord?)
		return settle(record.tradeId, "committed", record)
	end

	local function resolve(tradeId: string): (Decision?, TradeRecord?)
		return settle(tradeId, "aborted", nil)
	end

	local function appendDaily(record: TradeRecord): string?
		local code: string? = nil
		local key = `d/{record.day}/{TradeLog.shardOf(record.tradeId)}`
		local ok = attempt(`append {key}`, function()
			return store:UpdateAsync(key, function(old: any)
				local shard = if type(old) == "table" and type(old.entries) == "table"
					then old
					else { count = 0, entries = {} }
				code = nil
				if shard.entries[record.tradeId] ~= nil then
					return nil -- append idempoten per tradeId
				end
				if (shard.count or 0) >= LOG.maxEntriesPerShard then
					code = "LOG_SHARD_FULL"
					return nil
				end
				shard.entries[record.tradeId] = record
				shard.count = (shard.count or 0) + 1
				return shard
			end)
		end)
		return if ok then code else "TRADE_LOG_UNAVAILABLE"
	end

	local function flagDupe(day: number, entry: { [string]: any }): boolean
		local ok = attempt(`flag f/{day}`, function()
			return store:UpdateAsync(`f/{day}`, function(old: any)
				local list = if type(old) == "table" then old else {}
				if #list >= LOG.maxDupeFlagsPerDay then
					return nil
				end
				table.insert(list, entry)
				return list
			end)
		end)
		return ok
	end

	return {
		readPending = readPending,
		addPending = addPending,
		removePending = removePending,
		decide = decide,
		resolve = resolve,
		appendDaily = appendDaily,
		flagDupe = flagDupe,
	}
end

return table.freeze(TradeLog)
