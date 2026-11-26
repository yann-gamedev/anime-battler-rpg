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
	slots: { [number]: string? }, -- slot 1..9 → uid (sparse)
}

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

-- Bentuk data aman yang dikirim ke client untuk Team Board (bukan profil penuh).
export type TeamBoardUnit = {
	uid: string,
	unitId: string,
	name: string,
	rarity: string,
	element: string,
	status: string,
	stars: number,
	level: number,
}

export type TeamBoardData = {
	slots: { string }, -- dense 9 entri, "" = kosong
	units: { TeamBoardUnit },
	maxUnits: number,
}

return {}
