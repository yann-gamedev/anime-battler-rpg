--!strict
-- Tipe global proyek. Skema data mengikuti docs/ARCHITECTURE.md §6 (versi 1).

export type Result = {
	ok: boolean,
	code: string?,
	data: any?,
}

export type Rarity = "Rare" | "Epic" | "Legendary" | "Mythic"
export type Element = "Api" | "Es" | "Petir" | "Cahaya" | "Bayangan"
export type Status = "Murid" | "Familiar" | "Profesor"
export type UnitClass = "Tank" | "Mage" | "Assassin" | "Support" | "Summoner"
export type UnitSource = "summon" | "story" | "trade" | "event" | "admin"

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
}

export type StageDef = {
	id: string,
	chapter: number,
	index: number,
	enemies: { { unitId: string, slot: number, level: number, stars: number } },
	firstThreeStarGems: number,
}

export type ProductDef = {
	id: number,
	kind: "DeveloperProduct" | "GamePass",
	priceRobux: number?,
	grant: { currency: "Gems" | "TraitShards", amount: number }?,
}

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

export type Profile = {
	version: number,
	currencies: Currencies,
	accountLevel: number,
	units: { [string]: OwnedUnit },
	teams: { Team },
	story: { cleared: { [string]: number } },
	pity: { [string]: { sinceLegendary: number, sinceMythic: number } },
	traitPity: number,
	tradeDaily: { day: number, count: number },
	skinsOwned: { [string]: boolean },
	equippedSkins: { [string]: string },
	guildId: string?,
	processedReceipts: { [string]: boolean },
	stats: { battles: number, wins: number, summons: number, robuxSpent: number },
	flags: { tutorialDone: boolean },
	createdAt: number,
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

export type MyData = {
	currencies: Currencies,
	units: { [string]: ClientOwnedUnit },
	teams: { Team },
	story: { cleared: { [string]: number } },
	pity: { [string]: { sinceLegendary: number, sinceMythic: number } },
}

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

return table.freeze({})
