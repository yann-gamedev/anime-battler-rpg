--!strict
-- Bagian DataService: protokol durabilitas trade di atas TradeLog + marker profil. Boleh yield, KECUALI
-- swap dua profil (Trades.applyPair) yang dijalankan tanpa yield.
--
-- Mengapa bukan "satu transaksi": ProfileStore menyimpan tiap profil dengan UpdateAsync terpisah, dan
-- UpdateAsync hanya atomik per kunci. Server bisa mati di antara dua penyimpanan. Protokol:
--   1. prepare  : u/<A> dan u/<B> mencatat tradeId (indeks pemulihan). Gagal → batal, tanpa perubahan.
--   2. presave  : kedua profil disimpan dan LastSavedData dicek memuat item tawaran + Gold pajak, sehingga
--                 state yang tahan lama sudah memuat item yang dikunci (kunci menahan perubahan sesudahnya).
--   3. recheck  : validasi penuh lagi pada profil server (tanpa yield).
--   4. decide   : t/<tradeId> diisi "committed" lewat UpdateAsync satu kunci (titik komit). Pemulihan dari
--                 server lain menulis "aborted" ke kunci yang sama bila kosong, jadi hanya satu yang menang.
--                 Gagal/ambigu → TIDAK DIKETAHUI: item tetap dikunci, diselesaikan ulang di latar/saat muat.
--   5. apply    : swap dua profil tanpa yield (marker trade.applied[tradeId] di profil yang sama).
--   6. finish   : tunggu LastSavedData memuat marker → hapus dari u/<id>, append log harian (idempoten).
-- Pemulihan saat profil dimuat: untuk tiap tradeId di u/<id>, resolve (kosong → aborted). committed →
-- roll-forward sisi ini (idempoten lewat marker); aborted → hapus indeks. Gagal baca → muat profil ditolak.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local TradeTypes = require(Shared.TradeTypes)
local Trade = require(Shared.Config.Trade)
local TradeLog = require(script.Parent.TradeLog)
local Trades = require(script.Parent.Trades)
local TradeRules = require(script.Parent.TradeRules)

type TradeRecord = TradeTypes.TradeRecord
type Party = Trades.Party
export type SaveSession = {
	Data: Types.Profile,
	LastSavedData: any,
	IsActive: (any) -> boolean,
	Save: (any) -> (),
}
export type Deps = {
	ledger: Trades.Ledger,
	log: TradeLog.Log?, -- nil = trade dimatikan untuk lingkungan ini
	getSession: (Player) -> SaveSession?,
	isDurable: () -> boolean,
	waitForSave: (session: any, timeout: number) -> (),
	sleep: (seconds: number) -> (),
	spawn: (fn: () -> ()) -> (),
	newId: () -> string,
	report: ((message: string) -> ())?,
}
export type Journal = {
	isEnabled: () -> boolean,
	-- "TRADE_PENDING_RECOVERY" = keputusan belum diketahui; onResolved dipanggil SEKALI saat selesai:
	-- nil (committed & diterapkan), kode gagal (aborted), atau "TRADE_PENDING_RECOVERY" (semua peserta keluar).
	commit: (a: Party, b: Party, onResolved: ((code: string?) -> ())?) -> (string?, TradeRecord?),
	recover: (userId: number, session: Trades.SessionLike) -> (boolean, { TradeRecord }),
	finish: (player: Player, record: TradeRecord) -> boolean,
}

local LOG = Trade.log
local TradeJournal = {}

local function hasOffer(saved: any, side: TradeTypes.TradeSide, tax: number): boolean
	if type(saved) ~= "table" or type(saved.units) ~= "table" or type(saved.skinsOwned) ~= "table" then
		return false
	end
	for _, unit in side.units do
		local stored = saved.units[unit.uid]
		if type(stored) ~= "table" or stored.unitId ~= unit.unitId then
			return false
		end
	end
	for _, skinId in side.skins do
		if saved.skinsOwned[skinId] ~= true then
			return false
		end
	end
	return type(saved.currencies) == "table"
		and type(saved.currencies.Gold) == "number"
		and saved.currencies.Gold >= tax
end

local function hasMarker(saved: any, tradeId: string): boolean
	return type(saved) == "table"
		and type(saved.trade) == "table"
		and type(saved.trade.applied) == "table"
		and table.find(saved.trade.applied, tradeId) ~= nil
end

function TradeJournal.create(deps: Deps): Journal
	local ledger = deps.ledger
	local report = deps.report or warn

	-- true bila LastSavedData sesi pemain memenuhi predikat (memicu Save, menunggu, retry terbatas).
	local function confirmSaved(player: Player, predicate: (any) -> boolean): boolean
		local session = deps.getSession(player)
		if not session or not deps.isDurable() then
			return false
		end
		for attempt = 1, LOG.saveAttempts do
			if deps.getSession(player) ~= session or not session:IsActive() or not deps.isDurable() then
				return false
			end
			if predicate(session.LastSavedData) then
				return true
			end
			local before = session.LastSavedData
			session:Save()
			if session.LastSavedData == before then
				deps.waitForSave(session, LOG.saveWaitSeconds)
			end
			if predicate(session.LastSavedData) then
				return deps.isDurable()
			end
			if attempt < LOG.saveAttempts then
				deps.sleep(LOG.saveWaitSeconds)
			end
		end
		return false
	end

	local function unlockAll(a: Party, b: Party): ()
		ledger.unlock(a.player)
		ledger.unlock(b.player)
	end

	-- Batalkan trade yang belum diputuskan. Keputusan yang ternyata sudah "committed" tetap diterapkan.
	local function abort(record: TradeRecord, a: Party, b: Party): string?
		local log = deps.log :: TradeLog.Log
		local state, stored = log.resolve(record.tradeId)
		if state == "aborted" then
			log.removePending(a.userId, record.tradeId)
			log.removePending(b.userId, record.tradeId)
			unlockAll(a, b)
			return nil
		elseif state == "committed" and stored then
			ledger.applyPair(a.player, b.player, stored)
			unlockAll(a, b)
			return "COMMITTED"
		end
		return "UNKNOWN"
	end

	local function finish(player: Player, record: TradeRecord): boolean
		local log = deps.log
		if not log then
			return false
		end
		if not confirmSaved(player, function(saved: any): boolean
			return hasMarker(saved, record.tradeId)
		end) then
			report(
				`[TradeJournal] marker {record.tradeId} belum tersimpan untuk UserId={player.UserId}; menunggu pemulihan`
			)
			return false
		end
		-- Indeks pending baru dihapus setelah entri audit harian tercatat. Gagal (termasuk LOG_SHARD_FULL) =
		-- indeks tetap, sehingga muat profil berikutnya mengulang finish (marker ada → tanpa terap ulang).
		local code = log.appendDaily(record)
		if code then
			report(`[TradeJournal] log harian {record.tradeId}: {code}; indeks pending dipertahankan`)
			return false
		end
		return log.removePending(player.UserId, record.tradeId)
	end

	-- finish idempoten; diulang terbatas selama pemain online (sisanya diselesaikan saat profil dimuat).
	local function startFinish(players: { Player }, record: TradeRecord): ()
		for _, player in players do
			deps.spawn(function()
				for attempt = 1, LOG.retryAttempts do
					if finish(player, record) or not deps.getSession(player) then
						return
					end
					if attempt < LOG.retryAttempts then
						deps.sleep(LOG.finishRetrySeconds)
					end
				end
			end)
		end
	end

	-- Keputusan tidak diketahui: item tetap dikunci. Coba lagi selama ada peserta online.
	local function resolveLater(
		record: TradeRecord,
		a: Party,
		b: Party,
		failure: string,
		onResolved: ((code: string?) -> ())?
	): ()
		local function notify(code: string?): ()
			if onResolved then
				onResolved(code)
			end
		end
		deps.spawn(function()
			while deps.getSession(a.player) or deps.getSession(b.player) do
				deps.sleep(LOG.finishRetrySeconds)
				local code = abort(record, a, b)
				if code == nil then
					return notify(failure)
				elseif code == "COMMITTED" then
					startFinish({ a.player, b.player }, record)
					return notify(nil)
				end
			end
			-- Semua peserta keluar: kunci ikut hilang bersama sesi; pemulihan saat muat yang menyelesaikan.
			notify("TRADE_PENDING_RECOVERY")
		end)
	end

	local function commit(a: Party, b: Party, onResolved: ((code: string?) -> ())?): (string?, TradeRecord?)
		local log = deps.log
		if not log then
			unlockAll(a, b)
			return "TRADE_DISABLED", nil
		end
		local failure = ledger.checkPair(a, b)
		local code, record = nil, nil
		if not failure then
			code, record = ledger.buildRecord(deps.newId(), a, b)
			failure = code
		end
		if failure or not record then
			unlockAll(a, b)
			return failure or "INTERNAL_ERROR", nil
		end
		local tradeId = record.tradeId
		failure = log.addPending(a.userId, tradeId, record.at) or log.addPending(b.userId, tradeId, record.at)
		if not failure then
			local savedA = confirmSaved(a.player, function(saved: any): boolean
				return hasOffer(saved, record.a, record.tax)
			end)
			local savedB = savedA
				and confirmSaved(b.player, function(saved: any): boolean
					return hasOffer(saved, record.b, record.tax)
				end)
			failure = if savedA and savedB then ledger.checkPair(a, b) else "TRADE_NOT_DURABLE"
		end
		if failure then
			local aborted = abort(record, a, b)
			if aborted == "UNKNOWN" then
				resolveLater(record, a, b, failure, onResolved)
				return "TRADE_PENDING_RECOVERY", nil
			end
			if aborted == "COMMITTED" then
				-- Hanya terjadi bila t/<tradeId> sudah "committed" (mis. percobaan sebelumnya yang ambigu):
				-- keputusan tersimpan selalu menang, jadi sisi yang hadir diselesaikan.
				startFinish({ a.player, b.player }, record)
				return nil, record
			end
			return failure, nil
		end
		local state, stored = log.decide(record)
		if state == nil then
			resolveLater(record, a, b, "TRADE_ABORTED", onResolved)
			return "TRADE_PENDING_RECOVERY", nil
		elseif state == "aborted" or not stored or stored.tradeId ~= tradeId then
			log.removePending(a.userId, tradeId)
			log.removePending(b.userId, tradeId)
			unlockAll(a, b)
			return "TRADE_ABORTED", nil
		end
		-- Titik komit sudah tahan lama. Sisi yang sudah keluar diselesaikan oleh pemulihan saat muat.
		local applyCode, anomalies = ledger.applyPair(a.player, b.player, record)
		unlockAll(a, b)
		if applyCode then
			report(`[TradeJournal] apply {tradeId}: {applyCode}; diselesaikan saat profil dimuat ulang`)
		end
		for player, list in anomalies or {} do
			if #list > 0 then
				report(`[TradeJournal] anomali {tradeId} UserId={player.UserId}: {table.concat(list, ",")}`)
			end
		end
		startFinish({ a.player, b.player }, record)
		return nil, record
	end

	local function recover(userId: number, session: Trades.SessionLike): (boolean, { TradeRecord })
		local log = deps.log
		if not log then
			return true, {}
		end
		local ok, pending = log.readPending(userId)
		if not ok or not pending then
			return false, {}
		end
		local toFinish: { TradeRecord } = {}
		for tradeId in pending do
			local state, record = log.resolve(tradeId)
			if state == "aborted" then
				log.removePending(userId, tradeId)
			elseif state == "committed" and record then
				local code, anomalies = ledger.applyLoaded(session, userId, record)
				if code then
					report(`[TradeJournal] roll-forward {tradeId} UserId={userId} gagal: {code}`)
					return false, {}
				end
				if anomalies and #anomalies > 0 then
					report(
						`[TradeJournal] anomali roll-forward {tradeId} UserId={userId}: {table.concat(anomalies, ",")}`
					)
				end
				table.insert(toFinish, record)
			else
				return false, {}
			end
		end
		return true, toFinish
	end

	return {
		isEnabled = function(): boolean
			return deps.log ~= nil
		end,
		commit = commit,
		recover = recover,
		finish = finish,
	}
end

TradeJournal.hasMarker = hasMarker
TradeJournal.hasOffer = hasOffer
TradeJournal.isApplied = TradeRules.isApplied

return table.freeze(TradeJournal)
