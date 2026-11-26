--!strict
-- Tipe lobby, quest, dan raid (prompt 10). Diekspor ulang oleh Types.luau; pakai lewat Types.<Nama>.

export type QuestPeriod = "Daily" | "Weekly"
-- Jenis aktivitas server yang menambah progres quest (Signal server-only, lihat Util/Activity.luau).
export type ActivityKind = "story_win" | "story_stars" | "unit_level" | "raid_attempt"

-- Reward quest/raid: kunci = CurrencyKind ("Gold" | "Gems" | "TraitShards"), nilai = jumlah.
export type RewardMap = { [string]: number }

export type QuestDef = {
	id: string,
	period: QuestPeriod,
	kind: ActivityKind,
	title: string,
	description: string,
	target: number,
	rewards: RewardMap,
	battlePassXp: number, -- 0 = tanpa XP Battle Pass
}

-- Satu periode quest tersimpan. Hanya periode aktif yang disimpan (record lama diganti saat periode baru).
export type QuestPeriodRecord = {
	key: string, -- "D<hariUTC>" atau "W<mingguUTC>"; "" = belum pernah
	progress: { [string]: number }, -- questId → progres (dibatasi target)
	claimed: { [string]: boolean }, -- questId → sudah diklaim
}
export type QuestRecord = { daily: QuestPeriodRecord, weekly: QuestPeriodRecord }

-- Percobaan raid harian. Hanya hari terakhir yang disimpan.
export type RaidRecord = { day: number, attempted: boolean, damage: number }

-- Pajangan lobby. "" = tidak ada / skin default.
export type LobbyRecord = { showcaseUid: string, showcaseSkinId: string }

export type QuestView = {
	id: string,
	period: QuestPeriod,
	periodKey: string,
	title: string,
	description: string,
	progress: number,
	target: number,
	claimed: boolean,
	rewards: RewardMap,
}

-- Data sukses GetQuests() dan ClaimQuest(questId, periodKey).
export type QuestInfo = {
	serverTime: number,
	dailyResetAt: number,
	weeklyResetAt: number,
	quests: { QuestView },
}

export type RaidRewardTier = { minDamage: number, rewards: RewardMap }

-- Data sukses GetRaidInfo().
export type RaidInfo = {
	unlocked: boolean,
	bossName: string,
	bossId: string,
	bossMaxHp: number,
	bestDamage: number,
	attempted: boolean,
	resetAt: number,
	serverTime: number,
	rewardTiers: { RaidRewardTier },
}

-- Data sukses GetLobbyInfo() dan SetLobbyShowcase(uid, skinId?).
export type LobbyInfo = { unlocked: boolean, showcaseUid: string?, showcaseSkinId: string? }

return table.freeze({})
