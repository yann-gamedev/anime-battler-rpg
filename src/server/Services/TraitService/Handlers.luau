--!strict
-- Handler remote GetTraitInfo & RerollTrait, dibuat lewat factory agar dependensi (data, kebijakan, RNG)
-- dapat diganti di test. Urutan RerollTrait:
--   1. Validasi bentuk argumen (tanpa yield): tepat satu uid string 1..MAX_UID_LENGTH.
--   2. Data siap? Catat ID quote terakhir untuk uid ini (diterbitkan GetTraitInfo / respons sukses).
--   3. Lookup kebijakan (boleh yield) SEBELUM mutasi; restricted → RESTRICTED_REGION (Shards bisa dibeli
--      Robux, jadi reroll Shards = item acak berbayar; docs/ECONOMY.md §2).
--   4. Commit atomik DataService tanpa yield: kepemilikan, locked, quote dicek lagi terhadap pity & trait
--      draft, saldo Shards, roll, pengurangan Shards, trait baru, pity.
--   5. Bangun snapshot + info terbaru dan quote baru secara sinkron (tanpa panggilan kebijakan baru).
-- Quote basi tidak di-retry otomatis: client menerima ODDS_CHANGED dan harus memanggil GetTraitInfo lagi.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Economy = require(Shared.Config.Economy)
local Odds = require(script.Parent.Odds)
local Roll = require(script.Parent.Roll)

type Quote = { id: number, fingerprint: string }
type QuoteState = { sinceLegendary: number, traitId: string? }

export type LedgerState = { shards: number, sinceLegendary: number, unit: { traitId: string?, locked: boolean } }
export type LedgerResult = { uid: string, traitId: string, previousTraitId: string?, sinceLegendary: number }
export type Ledger = {
	apply: (player: Player, request: any) -> (string?, LedgerResult?),
	getState: (player: Player, uid: string) -> (string?, LedgerState?),
	getMyData: (player: Player) -> Types.MyData?,
}
export type Deps = {
	ledger: Ledger,
	isRestricted: (player: Player) -> boolean, -- boleh yield
	isPresent: (player: Player) -> boolean,
	rng: Roll.Rng,
}
export type Handlers = {
	getTraitInfo: (player: Player, ...any) -> Types.Result,
	rerollTrait: (player: Player, ...any) -> Types.Result,
	clear: (player: Player) -> (),
}

local COST: number = Economy.traitShardsPerReroll
-- Batas jumlah quote per pemain (satu per uid); dibatasi kapasitas inventaris.
local MAX_QUOTES: number = Constants.MAX_UNITS_PER_PLAYER

local Handlers = {}
Handlers.COST = COST

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

-- Validasi bentuk (uid). Mengembalikan kode error atau nil.
function Handlers.validateUidArgs(argCount: number, uid: any): string?
	if argCount ~= 1 or typeof(uid) ~= "string" or uid == "" or #uid > Constants.MAX_UID_LENGTH then
		return "INVALID_ARGUMENTS"
	end
	return nil
end

function Handlers.create(deps: Deps): Handlers
	local quotes: { [Player]: { [string]: Quote } } = {}
	local quoteCounts: { [Player]: number } = {}
	local nextQuoteId = 0

	local function issueQuote(player: Player, uid: string, state: LedgerState): ()
		local perPlayer = quotes[player]
		if not perPlayer or (perPlayer[uid] == nil and (quoteCounts[player] or 0) >= MAX_QUOTES) then
			perPlayer = {}
			quotes[player] = perPlayer
			quoteCounts[player] = 0
		end
		if perPlayer[uid] == nil then
			quoteCounts[player] = (quoteCounts[player] or 0) + 1
		end
		nextQuoteId += 1
		perPlayer[uid] = { id = nextQuoteId, fingerprint = Odds.fingerprint(state.sinceLegendary, state.unit.traitId) }
	end

	-- Payload TraitInfo dari state server. Quote hanya diterbitkan untuk pemain yang boleh reroll.
	local function buildInfo(player: Player, uid: string, restricted: boolean): (string?, Types.TraitInfo?)
		local code, state = deps.ledger.getState(player, uid)
		if code or not state then
			return code or "DATA_NOT_READY", nil
		end
		if restricted then
			local perPlayer = quotes[player]
			if perPlayer and perPlayer[uid] then
				perPlayer[uid] = nil
				quoteCounts[player] -= 1
			end
		else
			issueQuote(player, uid, state)
		end
		return nil,
			{
				uid = uid,
				traitId = state.unit.traitId,
				locked = state.unit.locked,
				restricted = restricted,
				shards = state.shards,
				cost = COST,
				pity = { sinceLegendary = state.sinceLegendary, rolls = Roll.PITY_ROLLS },
				odds = Odds.next(state.sinceLegendary),
			}
	end

	local function getTraitInfo(player: Player, ...: any): Types.Result
		local uid = ...
		local code = Handlers.validateUidArgs(select("#", ...), uid)
		if code then
			return failure(code)
		end
		code = deps.ledger.getState(player, uid)
		if code then
			return failure(code)
		end
		local restricted = deps.isRestricted(player)
		if not deps.isPresent(player) then
			return failure("DATA_NOT_READY")
		end
		local info
		code, info = buildInfo(player, uid, restricted ~= false)
		if code or not info then
			return failure(code or "DATA_NOT_READY")
		end
		return { ok = true, data = info }
	end

	local function rerollTrait(player: Player, ...: any): Types.Result
		local uid = ...
		local code = Handlers.validateUidArgs(select("#", ...), uid)
		if code then
			return failure(code)
		end
		code = deps.ledger.getState(player, uid)
		if code then
			return failure(code)
		end
		local playerQuotes = quotes[player]
		local quote = if playerQuotes then playerQuotes[uid] else nil
		local quoteId = if quote then quote.id else nil

		local restricted = deps.isRestricted(player)
		if not deps.isPresent(player) then
			return failure("DATA_NOT_READY")
		end
		if restricted ~= false then
			return failure("RESTRICTED_REGION")
		end

		local function precheck(state: QuoteState): string?
			local current = quotes[player]
			local active = if current then current[uid] else nil
			if
				quoteId == nil
				or not active
				or active.id ~= quoteId
				or active.fingerprint ~= Odds.fingerprint(state.sinceLegendary, state.traitId)
			then
				return "ODDS_CHANGED"
			end
			return nil
		end
		local function roll(sinceLegendary: number): (Roll.Draw, number)
			return Roll.reroll(sinceLegendary, deps.rng)
		end
		local commitCode, result = deps.ledger.apply(player, {
			uid = uid,
			cost = COST,
			precheck = precheck,
			roll = roll,
		})
		if commitCode or not result then
			return failure(commitCode or "INTERNAL_ERROR")
		end
		local snapshot = deps.ledger.getMyData(player)
		local infoCode, info = buildInfo(player, uid, false)
		if not snapshot or infoCode or not info then
			-- Reroll sudah tersimpan; client cukup memuat ulang data.
			return failure(infoCode or "DATA_NOT_READY")
		end
		local data: Types.TraitRerollData = { snapshot = snapshot, info = info }
		return { ok = true, data = data }
	end

	local function clear(player: Player): ()
		quotes[player] = nil
		quoteCounts[player] = nil
	end

	return { getTraitInfo = getTraitInfo, rerollTrait = rerollTrait, clear = clear }
end

return table.freeze(Handlers)
