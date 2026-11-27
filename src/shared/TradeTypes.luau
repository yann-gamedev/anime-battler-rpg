--!strict
-- Kontrak trade server ↔ client (prompt 11). Semua RemoteFunction trade mengembalikan
-- { ok: boolean, code: string?, data: TradeView? }; event privat TradeUpdated mengirim TradeView langsung.
-- countdownEndsAt & expiresAt memakai Workspace:GetServerTimeNow() (jam server tersinkron ke client).

export type TradeStatus = "Requested" | "Open" | "Ready" | "Countdown" | "Confirmed" | "Done" | "Cancelled"

-- uid hanya diisi untuk unit milik penerima view (sisi "mine"). UID lawan tidak pernah dikirim.
export type TradeUnitView = { uid: string?, unitId: string, name: string, rarity: string, stars: number }
export type TradeSkinView = { skinId: string, name: string }
export type TradeOffer = { units: { TradeUnitView }, skins: { TradeSkinView } }

export type TradeView = {
	sessionId: string,
	revision: number, -- pengikat persetujuan (expectedRevision); naik saat isi berubah / countdown baru
	updateId: number, -- urutan snapshot, naik monoton pada setiap mutasi state sesi
	status: TradeStatus,
	initiatorUserId: number,
	selfUserId: number,
	otherUserId: number,
	otherDisplayName: string,
	mine: TradeOffer,
	theirs: TradeOffer,
	myReady: boolean,
	theirReady: boolean,
	myConfirmed: boolean,
	theirConfirmed: boolean,
	countdownEndsAt: number?,
	expiresAt: number,
	reason: string?, -- kode alasan saat Cancelled (atau info saat Done)
}

-- Bagian server (tidak dikirim ke client): satu unit yang berpindah, snapshot saat keputusan dikunci.
export type TransferUnit = {
	uid: string,
	unitId: string,
	obtainedAt: number,
	cooldownUntil: number?, -- tradeCooldownUntil baru di sisi penerima (Mythic/limited)
	refundGold: number, -- refund level untuk pengirim
	refundScrolls: number,
}

export type TradeSide = { userId: number, units: { TransferUnit }, skins: { string } }

-- Rekaman trade yang dikunci sebelum swap. Dipakai jurnal TradeLog, marker profil, dan roll-forward.
export type TradeRecord = {
	v: number,
	tradeId: string,
	at: number, -- os.time() saat keputusan
	day: number, -- hari UTC dari `at`
	tax: number,
	a: TradeSide,
	b: TradeSide,
}

return table.freeze({})
