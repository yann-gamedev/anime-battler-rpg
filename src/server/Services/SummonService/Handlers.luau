--!strict
-- Handler remote GetBannerInfo & Summon, dibuat lewat factory agar dependensi (data, kebijakan, jam, RNG)
-- dapat diganti di test. Urutan Summon:
--   1. Validasi bentuk argumen + banner ID (tanpa yield).
--   2. Catat ID quote odds terakhir untuk banner (Gems).
--   3. Lookup kebijakan (boleh yield) SEBELUM mutasi; Gems + restricted → RESTRICTED_REGION.
--   4. Cek periode banner terhadap jam server.
--   5. Commit atomik DataService tanpa yield: quote dicek lagi terhadap state pity draft, lalu saldo,
--      kapasitas seluruh batch, roll, pemberian unit, pity, statistik.
--   6. Bangun info terbaru + quote baru secara sinkron (tanpa panggilan kebijakan baru).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Units = require(Shared.Config.Units)
local Catalog = require(script.Parent.Catalog)
local Roll = require(script.Parent.Roll)

type PityState = Roll.PityState
type Quote = { id: number, fingerprint: string }

export type LedgerState = {
	balances: { Gems: number, SummonTickets: number },
	unitCount: number,
	pity: { [string]: PityState },
}
export type Ledger = {
	apply: (player: Player, request: any) -> (string?, { Types.OwnedUnit }?),
	getState: (player: Player) -> LedgerState?,
}
export type Deps = {
	ledger: Ledger,
	isRestricted: (player: Player) -> boolean, -- boleh yield
	isPresent: (player: Player) -> boolean,
	now: () -> number,
	rng: Roll.Rng,
	maxUnits: number?,
}
export type Handlers = {
	getBannerInfo: (player: Player, ...any) -> Types.Result,
	summon: (player: Player, ...any) -> Types.Result,
	clear: (player: Player) -> (),
}

local function emptyPity(): PityState
	return { sinceLegendary = 0, sinceMythic = 0, guaranteedFeatured = false }
end

local Handlers = {}

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

local function isBannerId(value: any): boolean
	return typeof(value) == "string" and value ~= "" and #value <= Constants.MAX_BANNER_ID_LENGTH
end

-- Validasi bentuk Summon(bannerId, count, payWith). Mengembalikan kode error atau nil.
function Handlers.validateSummonArgs(argCount: number, bannerId: any, count: any, payWith: any): string?
	if argCount ~= 3 then
		return "INVALID_ARGUMENTS"
	end
	if not isBannerId(bannerId) or Catalog.get(bannerId) == nil then
		return "INVALID_BANNER"
	end
	if typeof(count) ~= "number" or not Catalog.isCount(count) then
		return "INVALID_COUNT"
	end
	if payWith ~= "Gems" and payWith ~= "Tickets" then
		return "INVALID_PAYMENT"
	end
	return nil
end

-- Gerbang kebijakan & periode (murni). Tickets dari gameplay tetap boleh untuk pemain restricted.
function Handlers.checkGate(
	banner: Types.BannerDef,
	payWith: Types.SummonPayment,
	restricted: boolean,
	now: number
): string?
	if payWith == "Gems" and restricted ~= false then
		return "RESTRICTED_REGION"
	end
	if not Catalog.isActive(banner, now) then
		return "BANNER_INACTIVE"
	end
	return nil
end

function Handlers.create(deps: Deps): Handlers
	local maxUnits = deps.maxUnits or Constants.MAX_UNITS_PER_PLAYER
	local quotes: { [Player]: { [string]: Quote } } = {}
	local nextQuoteId = 0

	-- Membangun payload GetBannerInfo dan menerbitkan quote baru per banner. Sinkron.
	local function buildInfo(player: Player, restricted: boolean): Types.BannerInfo?
		local state = deps.ledger.getState(player)
		if not state then
			return nil
		end
		local now = deps.now()
		local issued: { [string]: Quote } = {}
		local views: { Types.BannerView } = {}
		for _, bannerId in Catalog.orderedIds() do
			local banner = Catalog.get(bannerId) :: Types.BannerDef
			local pity = state.pity[bannerId] or emptyPity()
			table.insert(views, Catalog.view(banner, pity, now))
			nextQuoteId += 1
			issued[bannerId] = { id = nextQuoteId, fingerprint = Catalog.fingerprint(bannerId, pity) }
		end
		quotes[player] = issued
		return {
			restricted = restricted,
			balances = { Gems = state.balances.Gems, SummonTickets = state.balances.SummonTickets },
			capacity = { used = state.unitCount, max = maxUnits },
			banners = views,
		}
	end

	local function getBannerInfo(player: Player, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		if not deps.ledger.getState(player) then
			return failure("DATA_NOT_READY")
		end
		local restricted = deps.isRestricted(player)
		if not deps.isPresent(player) then
			return failure("DATA_NOT_READY")
		end
		local info = buildInfo(player, restricted)
		if not info then
			return failure("DATA_NOT_READY")
		end
		return { ok = true, data = info }
	end

	local function summon(player: Player, ...: any): Types.Result
		local bannerId, count, payWith = ...
		local code = Handlers.validateSummonArgs(select("#", ...), bannerId, count, payWith)
		if code then
			return failure(code)
		end
		local banner = Catalog.get(bannerId) :: Types.BannerDef
		if not deps.ledger.getState(player) then
			return failure("DATA_NOT_READY")
		end
		local playerQuotes = quotes[player]
		local quote = if playerQuotes then playerQuotes[bannerId] else nil
		local quoteId = if quote then quote.id else nil

		local restricted = deps.isRestricted(player)
		if not deps.isPresent(player) then
			return failure("DATA_NOT_READY")
		end
		code = Handlers.checkGate(banner, payWith, restricted, deps.now())
		if code then
			return failure(code)
		end
		if payWith == "Gems" and quoteId == nil then
			return failure("ODDS_CHANGED")
		end

		local currency, price = Catalog.price(count, payWith)
		local function precheck(state: PityState): string?
			if payWith ~= "Gems" then
				return nil
			end
			local current = quotes[player]
			local active = if current then current[bannerId] else nil
			if not active or active.id ~= quoteId or active.fingerprint ~= Catalog.fingerprint(bannerId, state) then
				return "ODDS_CHANGED"
			end
			return nil
		end
		local function rollBatch(state: PityState): ({ Roll.Draw }, PityState)
			return Roll.rollBatch(banner, state, count, deps.rng)
		end
		local commitCode, units = deps.ledger.apply(player, {
			bannerId = bannerId,
			count = count,
			currency = currency,
			price = price,
			maxUnits = maxUnits,
			precheck = precheck,
			rollBatch = rollBatch,
		})
		if commitCode or not units then
			return failure(commitCode or "INTERNAL_ERROR")
		end
		local rolls: { Types.SummonRoll } = {}
		for _, unit in units do
			local def = Units[unit.unitId]
			table.insert(rolls, { uid = unit.uid, unitId = unit.unitId, name = def.name, rarity = def.rarity })
		end
		local data: Types.SummonResultData =
			{ bannerId = bannerId, rolls = rolls, info = buildInfo(player, restricted) }
		return { ok = true, data = data }
	end

	local function clear(player: Player): ()
		quotes[player] = nil
	end

	return { getBannerInfo = getBannerInfo, summon = summon, clear = clear }
end

return table.freeze(Handlers)
