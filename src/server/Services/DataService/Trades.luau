--!strict
-- Bagian DataService: pemilik mutasi trade di profil (RULES §3). TradeService hanya memakai fungsi bernama
-- di sini (lewat DataService.trades). Isi:
--   * kunci item selama countdown/commit + guard yang menolak mutasi lain atas item/Gold yang dikunci
--   * validasi pasangan (A1/A2) atas profil server
--   * applyPair: swap DUA profil dalam satu fungsi tanpa yield (docs ProfileStore Profile:IsActive:
--     "you may make changes to two profiles immediately without yielding after Profile:IsActive() returns
--     true for the two profiles"); UID tetap sama, event Changed dipicu SETELAH kedua profil diganti.
--   * indeks UID sesi aktif untuk deteksi dupe (flag + log, tanpa penghapusan otomatis)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local TradeTypes = require(Shared.TradeTypes)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local Constants = require(Shared.Config.Constants)
local AnalyticsService = require(script.Parent.Parent.AnalyticsService)
local Progress = require(script.Parent.Progress)
local StoryRules = require(script.Parent.StoryRules)
local TradeIndex = require(script.Parent.TradeIndex)
local TradeRules = require(script.Parent.TradeRules)

type TradeRecord = TradeTypes.TradeRecord
type Outcome = StoryRules.Outcome
export type SessionLike = { Data: Types.Profile, IsActive: (any) -> boolean }
export type Offer = { uids: { string }, skins: { string } }
export type Lock = {
	uids: { string },
	skins: { string },
	gold: number,
	incomingUnits: number,
	incomingSkins: { string },
}
export type Party = { player: Player, userId: number, accountAgeDays: number, offer: Offer }
export type DupeFlag = TradeIndex.DupeFlag
export type UnitBrief = { uid: string, unitId: string, stars: number }
type Step = {
	player: Player,
	role: TradeRules.Role,
	session: SessionLike,
	original: Types.Profile,
	draft: Types.Profile,
	outcome: Outcome?,
	anomalies: { string }?,
}
export type Ledger = {
	checkPlayer: (player: Player, accountAgeDays: number) -> string?,
	checkOffer: (player: Player, offer: Offer) -> string?,
	checkPair: (a: Party, b: Party) -> string?,
	buildRecord: (tradeId: string, a: Party, b: Party) -> (string?, TradeRecord?),
	lock: (player: Player, lock: Lock) -> (),
	unlock: (player: Player) -> (),
	guard: (player: Player, original: Types.Profile, draft: Types.Profile) -> string?,
	isUidLocked: (player: Player, uid: string) -> boolean,
	goldReserve: (player: Player) -> number,
	applyPair: (playerA: Player?, playerB: Player?, record: TradeRecord) -> (string?, { [Player]: { string } }?),
	applyLoaded: (session: SessionLike, userId: number, record: TradeRecord) -> (string?, { string }?),
	describeUnits: (player: Player, uids: { string }) -> { UnitBrief },
	indexProfile: (player: Player, profile: Types.Profile) -> { DupeFlag },
	unindex: (player: Player) -> (),
}

local Trades = {}

-- Unit tersimpan datar (tanpa sub-tabel): sama jika semua field sama.
local function sameUnit(a: Types.OwnedUnit, b: Types.OwnedUnit): boolean
	for key, value in a :: any do
		if (b :: any)[key] ~= value then
			return false
		end
	end
	for key in b :: any do
		if (a :: any)[key] == nil then
			return false
		end
	end
	return true
end

local function isActive(session: SessionLike?): boolean
	return session ~= nil and session:IsActive()
end

local function roleOf(record: TradeRecord, userId: number): TradeRules.Role?
	if record.a.userId == userId then
		return "a"
	elseif record.b.userId == userId then
		return "b"
	end
	return nil
end

-- Menjalankan fn tanpa yield. Yield/error = gagal (tidak ada perubahan yang dipasang).
local function runNoYield<T>(fn: () -> T): (boolean, T?)
	local thread = coroutine.create(fn)
	local ok, result = coroutine.resume(thread)
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		warn("[DataService] trade swap cannot yield")
		return false, nil
	end
	if not ok then
		warn(`[DataService] trade swap failed: {result}`)
		return false, nil
	end
	return true, result
end

function Trades.create(
	getSession: (Player) -> SessionLike?,
	changed: Signal.Signal<Player, string>,
	clock: () -> number
): Ledger
	local locks: { [Player]: Lock } = {}

	local function profileOf(player: Player): Types.Profile?
		local session = getSession(player)
		return if isActive(session) then (session :: SessionLike).Data else nil
	end
	local uidIndex = TradeIndex.create(profileOf, clock)

	local function checkPlayer(player: Player, accountAgeDays: number): string?
		local profile = profileOf(player)
		if not profile then
			return "DATA_NOT_READY"
		end
		return TradeRules.checkPlayer(profile, accountAgeDays, clock())
	end

	local function checkOffer(player: Player, offer: Offer): string?
		local profile = profileOf(player)
		if not profile then
			return "DATA_NOT_READY"
		end
		return TradeRules.checkOffer(profile, offer.uids, offer.skins, clock())
	end

	local function buildRecord(tradeId: string, a: Party, b: Party): (string?, TradeRecord?)
		local profileA, profileB = profileOf(a.player), profileOf(b.player)
		if not profileA or not profileB then
			return "DATA_NOT_READY", nil
		end
		local now = clock()
		local sideA = TradeRules.buildSide(profileA, a.userId, a.offer.uids, a.offer.skins, now)
		local sideB = TradeRules.buildSide(profileB, b.userId, b.offer.uids, b.offer.skins, now)
		return nil, TradeRules.buildRecord(tradeId, now, sideA, sideB)
	end

	-- Validasi lengkap kedua sisi pada profil server saat ini: pemain, tawaran, penerimaan, pajak.
	local function checkPair(a: Party, b: Party): string?
		if a.player == b.player or a.userId == b.userId then
			return "INVALID_TARGET"
		end
		if #a.offer.uids + #a.offer.skins + #b.offer.uids + #b.offer.skins == 0 then
			return "BOTH_SIDES_EMPTY"
		end
		local code = checkPlayer(a.player, a.accountAgeDays)
			or checkPlayer(b.player, b.accountAgeDays)
			or checkOffer(a.player, a.offer)
			or checkOffer(b.player, b.offer)
		if code then
			return code
		end
		local failure, record = buildRecord("check", a, b)
		if failure or not record then
			return failure or "DATA_NOT_READY"
		end
		local profileA, profileB = profileOf(a.player) :: Types.Profile, profileOf(b.player) :: Types.Profile
		return TradeRules.checkReceive(profileA, record.b, #record.a.units)
			or TradeRules.checkReceive(profileB, record.a, #record.b.units)
			or TradeRules.checkTax(profileA)
			or TradeRules.checkTax(profileB)
	end

	-- Guard untuk semua commit lain (Commit.run & mutasi langsung DataService) selama item dikunci trade.
	local function guard(player: Player, original: Types.Profile, draft: Types.Profile): string?
		local lock = locks[player]
		if not lock then
			return nil
		end
		for _, uid in lock.uids do
			local before, after = original.units[uid], draft.units[uid]
			if not after or not before or not sameUnit(before, after) then
				return "ITEM_IN_TRADE"
			end
		end
		for _, skinId in lock.skins do
			if draft.skinsOwned[skinId] ~= true then
				return "ITEM_IN_TRADE"
			end
		end
		for _, skinId in lock.incomingSkins do
			if original.skinsOwned[skinId] ~= true and draft.skinsOwned[skinId] == true then
				return "ITEM_IN_TRADE"
			end
		end
		if draft.currencies.Gold < lock.gold then
			return "GOLD_RESERVED_FOR_TRADE"
		end
		local count = 0
		for _ in draft.units do
			count += 1
		end
		local before = 0
		for _ in original.units do
			before += 1
		end
		if count > before and count + lock.incomingUnits > Constants.MAX_UNITS_PER_PLAYER then
			return "INVENTORY_RESERVED_FOR_TRADE"
		end
		return nil
	end

	local function uidsOf(side: TradeTypes.TradeSide): { string }
		local list: { string } = {}
		for _, unit in side.units do
			table.insert(list, unit.uid)
		end
		return list
	end

	-- Swap atomik (A4). Sesi yang hadir & aktif menerima sisinya. Kode error = tidak ada profil yang berubah.
	-- Dipanggil HANYA setelah keputusan "committed" tercatat; karena itu non-strict (anomali dilaporkan).
	local function applyPair(
		playerA: Player?,
		playerB: Player?,
		record: TradeRecord
	): (string?, { [Player]: { string } }?)
		local steps: { Step } = {}
		local function addStep(player: Player?, role: TradeRules.Role): ()
			local session = if player then getSession(player) else nil
			if player and session and isActive(session) then
				local original = session.Data
				local draft = TableUtil.deepCopy(original)
				Progress.reconcile(draft)
				TradeRules.reconcile(draft)
				table.insert(steps, {
					player = player,
					role = role,
					session = session,
					original = original,
					draft = draft,
					outcome = nil,
					anomalies = nil,
				})
			end
		end
		addStep(playerA, "a")
		addStep(playerB, "b")
		if #steps == 0 then
			return "DATA_NOT_READY", nil
		end
		local baselines: { any } = {}
		local ok, code = runNoYield(function(): string?
			for index, step in steps do
				baselines[index] = AnalyticsService.baseline(step.draft)
				local failure, outcome, anomalies = TradeRules.applyHalf(step.draft, record, step.role, false)
				if failure == "ALREADY_APPLIED" then
					step.outcome = nil
				elseif failure then
					return failure
				else
					step.outcome = outcome
					step.anomalies = anomalies
				end
			end
			-- Cek ulang kedua sesi tepat sebelum pemasangan, lalu pasang keduanya tanpa yield.
			for _, step in steps do
				if
					getSession(step.player) ~= step.session
					or not isActive(step.session)
					or step.session.Data ~= step.original
				then
					return "DATA_NOT_READY"
				end
			end
			for _, step in steps do
				if step.outcome then
					step.session.Data = step.draft
				end
			end
			return nil
		end)
		if not ok then
			return "INTERNAL_ERROR", nil
		end
		if code then
			return code, nil
		end
		local anomalies: { [Player]: { string } } = {}
		for index, step in steps do
			local outcome = step.outcome
			if outcome then
				uidIndex.move(uidsOf(if step.role == "a" then record.b else record.a), step.player)
				AnalyticsService.logCommit(step.player, baselines[index], outcome.deltas, step.draft)
				changed:Fire(step.player, "units")
				changed:Fire(step.player, "currencies")
				if outcome.teams then
					changed:Fire(step.player, "teams")
				end
				changed:Fire(step.player, "progress")
				anomalies[step.player] = step.anomalies or {}
			end
		end
		return nil, anomalies
	end

	-- Roll-forward saat profil dimuat (sebelum sesi dibuka untuk gameplay). Tidak memicu event.
	local function applyLoaded(session: SessionLike, userId: number, record: TradeRecord): (string?, { string }?)
		local role = roleOf(record, userId)
		if not role then
			return "TRADE_RECORD_MISMATCH", nil
		end
		local draft = TableUtil.deepCopy(session.Data)
		Progress.reconcile(draft)
		TradeRules.reconcile(draft)
		local failure: string? = nil
		local anomalies: { string }? = nil
		local ok = runNoYield(function(): boolean
			local code, _, list = TradeRules.applyHalf(draft, record, role, false)
			failure, anomalies = code, list
			return true
		end)
		if not ok then
			return "INTERNAL_ERROR", nil
		elseif failure == "ALREADY_APPLIED" then
			return nil, {}
		elseif failure then
			return failure, nil
		end
		session.Data = draft
		return nil, anomalies or {}
	end

	-- Ringkasan unit milik pemain untuk TradeView (hanya UID yang dimiliki; sisanya diabaikan).
	local function describeUnits(player: Player, uids: { string }): { UnitBrief }
		local profile = profileOf(player)
		local list: { UnitBrief } = {}
		for _, uid in uids do
			local unit = profile and profile.units[uid]
			if unit then
				table.insert(list, { uid = uid, unitId = unit.unitId, stars = unit.stars })
			end
		end
		return list
	end

	return {
		checkPlayer = checkPlayer,
		checkOffer = checkOffer,
		checkPair = checkPair,
		buildRecord = buildRecord,
		lock = function(player: Player, lock: Lock)
			locks[player] = lock
		end,
		unlock = function(player: Player)
			locks[player] = nil
		end,
		guard = guard,
		isUidLocked = function(player: Player, uid: string): boolean
			local lock = locks[player]
			return lock ~= nil and table.find(lock.uids, uid) ~= nil
		end,
		goldReserve = function(player: Player): number
			local lock = locks[player]
			return if lock then lock.gold else 0
		end,
		applyPair = applyPair,
		applyLoaded = applyLoaded,
		describeUnits = describeUnits,
		indexProfile = uidIndex.indexProfile,
		unindex = function(player: Player)
			locks[player] = nil
			uidIndex.unindex(player)
		end,
	}
end

return table.freeze(Trades)
