--!strict
-- State machine sesi trade MURNI (tanpa Instance, tanpa yield, tanpa DataService). docs/SYSTEMS.md A3.
--   Requested → Open → Ready → Countdown → Confirmed → Done | Cancelled
-- * revision  : pengikat persetujuan. Naik saat isi tawaran berubah dan saat countdown baru dipersenjatai.
--               Ready(true) & Confirm wajib membawa expectedRevision == revision (persetujuan basi ditolak).
--               Update kesiapan biasa TIDAK menaikkan revision, sehingga dua aksi sah bersamaan tetap sah.
-- * updateId  : urutan snapshot; naik pada SETIAP mutasi state (isi, ready, confirm, batal, terminal).
-- * Waktu (now, countdownEndsAt, expiresAt) memakai jam server tersinkron (Workspace:GetServerTimeNow()).
-- Semua fungsi mutasi mengembalikan kode error (tanpa mutasi) atau nil.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TradeTypes = require(Shared.TradeTypes)
local Trade = require(Shared.Config.Trade)

export type Status = TradeTypes.TradeStatus
export type UnitBrief = { uid: string, unitId: string, stars: number }
export type Side = {
	userId: number,
	units: { UnitBrief },
	skins: { string },
	ready: boolean,
	confirmed: boolean,
}
export type Session = {
	id: string,
	status: Status,
	revision: number,
	updateId: number,
	initiator: Side,
	target: Side,
	createdAt: number,
	expiresAt: number,
	countdownEndsAt: number?,
	reason: string?,
}

local TradeSession = {}

local function newSide(userId: number): Side
	return { userId = userId, units = {}, skins = {}, ready = false, confirmed = false }
end

function TradeSession.new(id: string, initiatorUserId: number, targetUserId: number, now: number): Session
	return {
		id = id,
		status = "Requested",
		revision = 1,
		updateId = 1,
		initiator = newSide(initiatorUserId),
		target = newSide(targetUserId),
		createdAt = now,
		expiresAt = now + math.min(Trade.requestSeconds, Trade.sessionMaxSeconds),
		countdownEndsAt = nil,
		reason = nil,
	}
end

function TradeSession.isTerminal(session: Session): boolean
	return session.status == "Done" or session.status == "Cancelled"
end

-- Sisi milik userId dan sisi lawan, atau nil bila bukan peserta.
function TradeSession.sides(session: Session, userId: number): (Side?, Side?)
	if session.initiator.userId == userId then
		return session.initiator, session.target
	elseif session.target.userId == userId then
		return session.target, session.initiator
	end
	return nil, nil
end

function TradeSession.itemCount(side: Side): number
	return #side.units + #side.skins
end

function TradeSession.isEmpty(side: Side): boolean
	return TradeSession.itemCount(side) == 0
end

local function bump(session: Session): ()
	session.updateId += 1
end

local function clearApprovals(session: Session): ()
	for _, side in { session.initiator, session.target } do
		side.ready = false
		side.confirmed = false
	end
	session.countdownEndsAt = nil
end

local function editable(session: Session): string?
	if TradeSession.isTerminal(session) then
		return "TRADE_CLOSED"
	elseif session.status == "Countdown" or session.status == "Confirmed" then
		return "TRADE_LOCKED"
	elseif session.status == "Requested" then
		return "TRADE_NOT_OPEN"
	end
	return nil
end

function TradeSession.respond(session: Session, userId: number, accept: boolean, now: number): string?
	if session.target.userId ~= userId then
		return if TradeSession.sides(session, userId) then "NOT_TARGET" else "NOT_PARTICIPANT"
	end
	if session.status ~= "Requested" then
		return if TradeSession.isTerminal(session) then "TRADE_CLOSED" else "ALREADY_RESPONDED"
	end
	if not accept then
		session.status = "Cancelled"
		session.reason = "DECLINED"
	else
		session.status = "Open"
		session.expiresAt = session.createdAt + Trade.sessionMaxSeconds
		if session.expiresAt <= now then
			session.status = "Cancelled"
			session.reason = "EXPIRED"
		end
	end
	bump(session)
	return nil
end

local function sameItems(side: Side, units: { UnitBrief }, skins: { string }): boolean
	if #side.units ~= #units or #side.skins ~= #skins then
		return false
	end
	for index, unit in units do
		if side.units[index].uid ~= unit.uid then
			return false
		end
	end
	for index, skinId in skins do
		if side.skins[index] ~= skinId then
			return false
		end
	end
	return true
end

-- Isi baru satu sisi (sudah divalidasi server). Mengubah isi = semua Ready/Confirm direset (A3 langkah 4).
function TradeSession.setItems(session: Session, userId: number, units: { UnitBrief }, skins: { string }): string?
	local mine = TradeSession.sides(session, userId)
	if not mine then
		return "NOT_PARTICIPANT"
	end
	local code = editable(session)
	if code then
		return code
	end
	if #units + #skins > Trade.maxItemsPerSide then
		return "TOO_MANY_ITEMS"
	end
	if sameItems(mine, units, skins) then
		return nil
	end
	mine.units = table.clone(units)
	mine.skins = table.clone(skins)
	clearApprovals(session)
	session.status = "Open"
	session.revision += 1
	bump(session)
	return nil
end

-- true bila Ready(true) dari userId akan mempersenjatai countdown (lawan sudah Ready).
function TradeSession.wouldArm(session: Session, userId: number): boolean
	local mine, other = TradeSession.sides(session, userId)
	return mine ~= nil and other ~= nil and not mine.ready and other.ready and editable(session) == nil
end

-- Mengembalikan (kode, armed). armed = countdown baru dimulai (pemanggil mengunci item).
function TradeSession.setReady(
	session: Session,
	userId: number,
	ready: boolean,
	expectedRevision: number,
	now: number
): (string?, boolean)
	local mine, other = TradeSession.sides(session, userId)
	if not mine or not other then
		return "NOT_PARTICIPANT", false
	end
	if TradeSession.isTerminal(session) then
		return "TRADE_CLOSED", false
	elseif session.status == "Requested" then
		return "TRADE_NOT_OPEN", false
	elseif session.status == "Confirmed" then
		return "TRADE_COMMITTING", false
	end
	if not ready then
		if not mine.ready then
			return nil, false
		end
		-- Isi tidak berubah, jadi kesiapan lawan tetap sah; countdown & konfirmasi dibatalkan.
		local otherReady = other.ready
		clearApprovals(session)
		other.ready = otherReady
		session.status = if other.ready then "Ready" else "Open"
		bump(session)
		return nil, false
	end
	if session.status == "Countdown" then
		return (if expectedRevision == session.revision then nil else "STALE_REVISION"), false
	end
	if expectedRevision ~= session.revision then
		return "STALE_REVISION", false
	end
	if TradeSession.isEmpty(mine) and TradeSession.isEmpty(other) then
		return "BOTH_SIDES_EMPTY", false
	end
	if mine.ready then
		return nil, false
	end
	mine.ready = true
	bump(session)
	if not other.ready then
		session.status = "Ready"
		return nil, false
	end
	session.status = "Countdown"
	session.revision += 1
	session.countdownEndsAt = now + Trade.countdownSeconds
	mine.confirmed = false
	other.confirmed = false
	return nil, true
end

-- Mengembalikan (kode, bothConfirmed). Konfirmasi hanya setelah countdown selesai, terikat revision.
function TradeSession.confirm(
	session: Session,
	userId: number,
	expectedRevision: number,
	now: number
): (string?, boolean)
	local mine, other = TradeSession.sides(session, userId)
	if not mine or not other then
		return "NOT_PARTICIPANT", false
	end
	if TradeSession.isTerminal(session) then
		return "TRADE_CLOSED", false
	end
	if session.status == "Confirmed" then
		-- Confirm berulang setelah keduanya setuju: idempoten, commit tetap berjalan satu kali.
		return (if expectedRevision == session.revision then nil else "STALE_REVISION"), false
	end
	if session.status ~= "Countdown" then
		return "TRADE_NOT_READY", false
	end
	if expectedRevision ~= session.revision then
		return "STALE_REVISION", false
	end
	local endsAt = session.countdownEndsAt
	if endsAt == nil or now < endsAt then
		return "COUNTDOWN_ACTIVE", false
	end
	if mine.confirmed then
		return nil, false
	end
	mine.confirmed = true
	bump(session)
	if other.confirmed then
		session.status = "Confirmed"
		return nil, true
	end
	return nil, false
end

-- Batal sebelum commit final. Sesi Confirmed (commit berjalan) & terminal tidak bisa dibatalkan di sini.
function TradeSession.cancel(session: Session, reason: string): boolean
	if TradeSession.isTerminal(session) or session.status == "Confirmed" then
		return false
	end
	session.status = "Cancelled"
	session.reason = reason
	clearApprovals(session)
	bump(session)
	return true
end

-- Hasil commit: SATU-SATUNYA jalan keluar dari Confirmed. Hanya berlaku sekali.
function TradeSession.finish(session: Session, failure: string?): boolean
	if session.status ~= "Confirmed" then
		return false
	end
	session.status = if failure then "Cancelled" else "Done"
	session.reason = failure
	bump(session)
	return true
end

-- Expiry sesi (> sessionMaxSeconds) atau permintaan tak dijawab. Commit yang berjalan tidak dibatalkan.
function TradeSession.tick(session: Session, now: number): boolean
	if now >= session.expiresAt then
		return TradeSession.cancel(session, "EXPIRED")
	end
	return false
end

return table.freeze(TradeSession)
