--!strict
-- Tipe global proyek. Skema data mengikuti docs/ARCHITECTURE.md §6 (versi 1).
local ShopTypes = require(script.Parent.ShopTypes)

export type Result = {
	ok: boolean,
	code: string?,
	data: any?,
}

export type Rarity = "Rare" | "Epic" | "Legendary" | "Mythic"
export type Element = "Api" | "Es" | "Petir" | "Cahaya" | "Bayangan"
export type Status = "Murid" | "Familiar" | "Profesor"
export type UnitClass = "Tank" | "Mage" | "Assassin" | "Support" | "Summoner"
-- "shop" (Toko Akademi) dan "battlepass" additive prompt 09; arti nilai lama tetap.
export type UnitSource = "summon" | "story" | "trade" | "event" | "admin" | "shop" | "battlepass"

export type BaseStats = {
	hp: number,
	atk: number,
	def: number,
	spd: number,
	range: number,
}

export type UnitDef = {
	id: string,
	name: string,
	rarity: Rarity,
	class: UnitClass,
	element: Element,
	status: Status,
	base: BaseStats,
	ultimate: string,
}

export type TraitTier = "Common" | "Uncommon" | "Epic" | "Legendary" | "Mythic"

export type TraitDef = {
	id: string,
	name: string,
	hpBonus: number?,
	atkBonus: number?,
	defBonus: number?,
	spdBonus: number?,
	allStatsBonus: number?,
	manaGainBonus: number?,
	critChanceBonus: number?,
	startingMana: number?,
	lifesteal: number?,
	repeatUltimateChance: number?,
	freeFirstUltimateAtSeconds: number?,
}

export type SynergyDef = {
	count: number,
	burnHpPerSecond: number?,
	burnSeconds: number?,
	slow: number?,
	freezeChance: number?,
	freezeSeconds: number?,
	speedBonus: number?,
	healHpPerSecond: number?,
	healTarget: ("matchingElement" | "allAllies")?,
	critChanceBonus: number?,
	critDamageMultiplier: number?,
	atkAndDefBonus: number?,
	stackIntervalSeconds: number?,
	firstReviveHp: number?,
	manaGainBonus: number?,
}

export type BannerDef = {
	id: string,
	kind: "Standard" | "Limited",
	oddsPercent: { [Rarity]: number },
	unitIds: { string },
	featuredUnitId: string?,
	featuredSharePercent: number?,
	guaranteeFeaturedAfterMiss: boolean?,
	rotationDays: number?,
	startsAt: number?, -- detik Unix UTC, inklusif
	endsAt: number?, -- detik Unix UTC, eksklusif
}

-- Pity per banner. `guaranteedFeatured` additive v1 (nil = false), tanpa migrasi.
export type PityRecord = { sinceLegendary: number, sinceMythic: number, guaranteedFeatured: boolean? }

export type StageDef = {
	id: string,
	chapter: number,
	index: number,
	enemies: { { unitId: string, slot: number, level: number, stars: number } },
	firstThreeStarGems: number,
}

export type ProductKind = ShopTypes.ProductKind
export type ProductDef = {
	id: number, -- 0 = belum dipublikasikan (tidak tersedia)
	kind: ProductKind,
	name: string?,
	priceRobux: number?, -- referensi placeholder; client memakai harga aktual GetProductInfoAsync
	grant: { currency: "Gems" | "TraitShards", amount: number }?,
	-- Developer Product Premium Battle Pass terikat ke satu musim (receipt terlambat tetap ke musim ini).
	battlePassSeasonId: string?,
}

export type AcademyItemKind = ShopTypes.AcademyItemKind
-- Item Toko Akademi: non-acak, harga Gems tetap, terbuka untuk semua pemain (termasuk restricted).
export type AcademyItemDef = { id: string, name: string, kind: AcademyItemKind, itemId: string, costGems: number }
export type SkinDef = { id: string, name: string, unitId: string?, assetId: string }

export type OwnedUnit = {
	uid: string,
	unitId: string,
	stars: number,
	level: number,
	xp: number,
	trait: string?,
	locked: boolean,
	tradeCooldownUntil: number?,
	obtainedAt: number,
	source: UnitSource,
}

export type Team = {
	name: string,
	slots: { string }, -- slot 1..9, "" = kosong; dense agar dapat disimpan
}

export type CurrencyKind = "Gold" | "Gems" | "TraitShards" | "SummonTickets" | "AsramaTokens"

export type Currencies = {
	Gold: number,
	Gems: number,
	TraitShards: number,
	SummonTickets: number,
	AsramaTokens: number,
}

-- Field additive (tanpa migrasi, dilengkapi reconcile v1): bahan non-mata-uang.
export type Materials = { XPScrolls: number }

-- Field additive: status onboarding & progres story server-side.
export type StoryProgress = {
	tutorialBattleCleared: boolean, -- battle tutorial dimenangkan, 10 Summon Tickets sudah diberikan
	firstThreeStarClaimed: { [string]: boolean }, -- stageId → Gems first-clear 3★ sudah diklaim
	replayDay: number, -- hari UTC (os.time() // 86400) untuk counter replay
	replayCount: number, -- jumlah replay menang pada replayDay
}

export type Profile = {
	version: number,
	currencies: Currencies,
	accountLevel: number,
	units: { [string]: OwnedUnit },
	teams: { Team },
	story: { cleared: { [string]: number } },
	pity: { [string]: PityRecord },
	traitPity: number,
	tradeDaily: { day: number, count: number },
	skinsOwned: { [string]: boolean },
	equippedSkins: { [string]: string },
	guildId: string?,
	processedReceipts: { [string]: boolean },
	stats: { battles: number, wins: number, summons: number, robuxSpent: number },
	flags: { tutorialDone: boolean },
	createdAt: number,
	materials: Materials,
	progress: StoryProgress,
	purchases: PurchaseRecord,
	-- profileFrames/profileFrameId additive: entitlement bingkai lintas musim (nil di profil lama).
	battlePass: {
		seasons: { [string]: BattlePassSeasonRecord },
		profileFrames: { [string]: boolean }?,
		profileFrameId: string?,
	},
}

-- Field additive prompt 09 (tanpa migrasi, dilengkapi ShopRules.reconcile).
-- firstBonus: productKey → bonus pembelian pertama sudah dipakai. academy: itemId → sudah dibeli.
export type PurchaseRecord = { firstBonus: { [string]: boolean }, academy: { [string]: boolean } }
-- Klaim memakai kunci string tier ("1".."30") agar aman disimpan ProfileStore.
export type BattlePassSeasonRecord = {
	xp: number,
	premium: boolean,
	freeClaimed: { [string]: boolean },
	premiumClaimed: { [string]: boolean },
}

export type ClientOwnedUnit = {
	uid: string,
	unitId: string,
	stars: number,
	level: number,
	xp: number,
	trait: string?,
	locked: boolean,
}

export type ProgressionData = {
	accountLevel: number,
	maxBoardUnits: number,
	xpScrolls: number,
	tutorialBattleCleared: boolean,
	tutorialDone: boolean,
}

export type MyData = {
	currencies: Currencies,
	units: { [string]: ClientOwnedUnit },
	teams: { Team },
	story: { cleared: { [string]: number } },
	pity: { [string]: PityRecord },
	progression: ProgressionData,
}

export type StageRewards = { Gold: number, Gems: number, XPScrolls: number, SummonTickets: number }

-- Bentuk data aman yang dikirim ke client untuk Team Board (bukan profil penuh).
export type TeamBoardUnit = {
	uid: string,
	unitId: string,
	name: string,
	rarity: Rarity,
	element: Element,
	status: Status,
	stars: number,
	level: number,
}

export type TeamBoardData = {
	slots: { string }, -- dense 9 entri, "" = kosong
	units: { TeamBoardUnit },
	maxUnits: number,
}

export type BattleSide = "A" | "B"
export type BattleUnitInput = { unitId: string, stars: number, level: number, trait: string?, cell: number }
export type BattleInput = {
	teamA: { BattleUnitInput },
	teamB: { BattleUnitInput },
	seed: number,
	maxTicks: number?,
}
export type BattleUnitSnapshot = { id: number, unitId: string, side: BattleSide, cell: number, hp: number, maxHp: number }
export type BattleEvent =
	{
		t: number,
		kind: "spawn",
		unit: number,
		unitId: string,
		side: BattleSide,
		cell: number,
		hp: number,
		maxHp: number,
		owner: number?,
	}
	| { t: number, kind: "move", unit: number, cell: number, leap: boolean }
	| {
		t: number,
		kind: "attack" | "damage",
		src: number,
		dst: number,
		dmg: number,
		crit: boolean,
		hp: number,
		shield: number,
	}
	| { t: number, kind: "heal" | "shield", unit: number, hp: number, shield: number }
	| { t: number, kind: "ultimate", src: number, skill: string, cell: number, targets: { number }, cinematic: boolean }
	| { t: number, kind: "status", unit: number, effect: string, untilTick: number }
	| { t: number, kind: "revive", unit: number, hp: number }
	| { t: number, kind: "death" | "despawn", unit: number }

export type BattleResult = {
	winner: BattleSide | "draw",
	ticks: number,
	log: { BattleEvent },
	survivors: { BattleUnitSnapshot },
}

-- Data sukses StartStage(stageId, teamIndex).
export type StageResultData = {
	stageId: string,
	replay: BattleResult,
	stars: number,
	rewards: StageRewards,
	firstThreeStar: boolean,
	progression: ProgressionData,
}

export type BannerKind = "Standard" | "Limited"
export type SummonPayment = "Gems" | "Tickets"
export type RarityOdds = { rarity: Rarity, percent: number }
export type UnitOdds = { unitId: string, name: string, rarity: Rarity, percent: number }
-- Semua percent 0..100, termasuk hasil berpeluang nol.
export type Odds = { rarities: { RarityOdds }, units: { UnitOdds } }

export type BannerPityView = {
	sinceLegendary: number,
	sinceMythic: number,
	legendaryPlusRolls: number,
	mythicRolls: number,
	guaranteedFeatured: boolean,
}

export type BannerView = {
	id: string,
	kind: BannerKind,
	active: boolean,
	startsAt: number?,
	endsAt: number?,
	featuredUnitId: string?,
	prices: { gems1: number, gems10: number, tickets1: number, tickets10: number },
	pity: BannerPityView,
	odds: { base: Odds, single: Odds, ten: { Odds } },
}

-- Data sukses GetBannerInfo().
export type BannerInfo = {
	restricted: boolean,
	balances: { Gems: number, SummonTickets: number },
	capacity: { used: number, max: number },
	banners: { BannerView },
}

export type SummonRoll = { uid: string, unitId: string, name: string, rarity: Rarity }

-- Data sukses Summon(bannerId, count, payWith).
export type SummonResultData = { bannerId: string, rolls: { SummonRoll }, info: BannerInfo? }

-- Odds reroll trait. Semua percent 0..100, termasuk trait berpeluang nol.
export type TraitOddsEntry = { id: string, name: string, percent: number }
export type TraitTierOdds = { tier: TraitTier, percent: number, traits: { TraitOddsEntry } }
export type TraitOdds = { tiers: { TraitTierOdds } }

export type TraitDirectTier = "Common" | "Uncommon"
export type TraitDirectOption = { id: string, name: string, tier: TraitDirectTier, cost: number }
export type TraitDirect = { gold: number, options: { TraitDirectOption } }

-- Data sukses GetTraitInfo(uid). `odds` = peluang aktual reroll berikutnya (termasuk pity).
export type TraitInfo = {
	uid: string,
	traitId: string?,
	locked: boolean,
	restricted: boolean,
	shards: number,
	cost: number,
	pity: { sinceLegendary: number, rolls: number },
	odds: TraitOdds,
	-- Hanya untuk pemain restricted: pilihan trait langsung dengan Gold (D-OPEN-1).
	direct: TraitDirect?,
}

-- Data sukses RerollTrait(uid).
export type TraitRerollData = { snapshot: MyData, info: TraitInfo }

-- Toko & Battle Pass: definisi di ShopTypes.luau (dipisah agar file < 400 baris), diekspor ulang di sini.
export type ShopProductView = ShopTypes.ShopProductView
export type AcademyItemView = ShopTypes.AcademyItemView
export type ShopInfo = ShopTypes.ShopInfo
export type PreparedPurchase = ShopTypes.PreparedPurchase
export type RewardKind = ShopTypes.RewardKind
export type Reward = ShopTypes.Reward
export type BattlePassTrack = ShopTypes.BattlePassTrack
export type BattlePassTierDef = ShopTypes.BattlePassTierDef
export type BattlePassSeasonDef = ShopTypes.BattlePassSeasonDef
export type PassTierView = ShopTypes.PassTierView
export type PassInfo = ShopTypes.PassInfo

return table.freeze({})
