--!strict
-- Tipe toko & Battle Pass (prompt 09). Diekspor ulang oleh Types.luau; pakai lewat Types.<Nama>.

export type ProductKind = "DeveloperProduct" | "GamePass"
export type AcademyItemKind = "Unit" | "Skin"

-- Toko (GetShopInfo).
export type ShopProductView = {
	key: string,
	id: number,
	kind: ProductKind,
	name: string,
	priceRobux: number?,
	available: boolean,
	owned: boolean,
	firstBonus: boolean?,
	grant: { currency: string, amount: number }?,
}
export type AcademyItemView = {
	id: string,
	name: string,
	kind: AcademyItemKind,
	itemId: string,
	costGems: number,
	owned: boolean,
}
export type ShopInfo = {
	restricted: boolean,
	balances: { Gems: number, TraitShards: number },
	products: { ShopProductView },
	academy: { AcademyItemView },
}
export type PreparedPurchase = { id: number, kind: ProductKind }

-- Battle Pass (GetBattlePass).
export type RewardKind = "Currency" | "UnitChoice" | "Skin" | "ProfileFrame"
export type Reward = { kind: RewardKind, id: string?, amount: number?, options: { string }? }
export type BattlePassTrack = "Free" | "Premium"
export type BattlePassTierDef = { free: { Reward }, premium: { Reward } }
export type BattlePassSeasonDef = {
	id: string,
	startsAt: number, -- detik Unix UTC, inklusif
	endsAt: number, -- detik Unix UTC, eksklusif
	xpPerTier: number,
	tiers: { BattlePassTierDef },
}
export type PassTierView = {
	tier: number,
	free: { Reward },
	premium: { Reward },
	freeClaimed: boolean,
	premiumClaimed: boolean,
}
export type PassInfo = {
	seasonId: string,
	startsAt: number,
	endsAt: number,
	active: boolean,
	xp: number,
	xpPerTier: number,
	unlockedTier: number,
	premium: boolean,
	tiers: { PassTierView },
	-- Bingkai profil terakhir yang diperoleh (lintas musim); nil bila belum pernah diperoleh.
	profileFrameId: string?,
}

return table.freeze({})
