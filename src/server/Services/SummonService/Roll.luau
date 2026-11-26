--!strict
-- Roll gacha murni (tanpa Instance, tanpa data profil, tanpa yield). Satu fungsi bobot, `distribution`,
-- dipakai oleh roll server DAN oleh tabel odds yang dikirim ke UI (docs/RULES.md §4).
-- Urutan prioritas jaminan: hard pity Mythic > pity Legendary+ > minimum Epic pada draw terakhir 10×.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Banners = require(Shared.Config.Banners)
local Units = require(Shared.Config.Units)
local TableUtil = require(Shared.Util.TableUtil)

export type PityState = { sinceLegendary: number, sinceMythic: number, guaranteedFeatured: boolean }
-- Draw ke-`position` dari batch `batchCount`; `allRareSoFar` = semua draw sebelumnya di batch ini Rare.
export type Context = { position: number, batchCount: number, allRareSoFar: boolean }
export type Entry = { unitId: string, rarity: Types.Rarity, percent: number, featured: boolean }
export type Distribution = { Entry }
-- Random server (`Random.new()`) atau RNG deterministik untuk test: NextNumber() → [0, 1).
export type Rng = { NextNumber: (any) -> number }
export type Draw = { unitId: string, rarity: Types.Rarity, featured: boolean }

local RARITIES: { Types.Rarity } = { "Rare", "Epic", "Legendary", "Mythic" }
local RANK: { [Types.Rarity]: number } = { Rare = 1, Epic = 2, Legendary = 3, Mythic = 4 }
local LEGENDARY_RANK = RANK.Legendary
local MYTHIC_RANK = RANK.Mythic

type Pools = { [Types.Rarity]: { string } }

local Roll = {}
Roll.RARITIES = table.freeze(table.clone(RARITIES))

local poolCache: { [Types.BannerDef]: Pools } = setmetatable({}, { __mode = "k" }) :: any
local distributionCache: { [Types.BannerDef]: { [number]: Distribution } } = setmetatable({}, { __mode = "k" }) :: any

local function featuredRarity(banner: Types.BannerDef): Types.Rarity?
	local featuredId = banner.featuredUnitId
	if banner.kind ~= "Limited" or not featuredId then
		return nil
	end
	local def = Units[featuredId]
	return if def then def.rarity else nil
end

-- Pool per rarity: unit featured lebih dulu, sisanya urut ID agar tabel odds dan roll stabil.
local function pools(banner: Types.BannerDef): Pools
	local cached = poolCache[banner]
	if cached then
		return cached
	end
	local result: Pools = { Rare = {}, Epic = {}, Legendary = {}, Mythic = {} }
	for _, unitId in banner.unitIds do
		local def = assert(Units[unitId], `Banner {banner.id}: unknown unit {unitId}`)
		table.insert(result[def.rarity], unitId)
	end
	local featuredId = if featuredRarity(banner) then banner.featuredUnitId else nil
	for _, list in result do
		table.sort(list, function(a: string, b: string): boolean
			if a == featuredId or b == featuredId then
				return a == featuredId and b ~= featuredId
			end
			return a < b
		end)
	end
	poolCache[banner] = result
	return result
end

-- Rarity minimum yang dijamin untuk draw berikutnya (1 = tanpa jaminan).
function Roll.floorRank(state: PityState, context: Context?): number
	local pity = Banners.pity
	if state.sinceMythic + 1 >= pity.mythicRolls then
		return MYTHIC_RANK
	end
	if state.sinceLegendary + 1 >= pity.legendaryPlusRolls then
		return LEGENDARY_RANK
	end
	local multi = Banners.multiSummonGuarantee
	if context and context.batchCount == multi.count and context.position == multi.count and context.allRareSoFar then
		return RANK[multi.minimumRarity :: Types.Rarity]
	end
	return 1
end

local function guaranteedFeaturedApplies(banner: Types.BannerDef, state: PityState): boolean
	return state.guaranteedFeatured and banner.guaranteeFeaturedAfterMiss == true and featuredRarity(banner) ~= nil
end

local function build(banner: Types.BannerDef, floor: number, guaranteed: boolean): Distribution
	local unitPools = pools(banner)
	local total = 0
	for _, rarity in RARITIES do
		if RANK[rarity] >= floor then
			total += banner.oddsPercent[rarity]
		end
	end
	assert(total > 0, `Banner {banner.id}: no odds at or above the guaranteed rarity`)
	local featuredId = banner.featuredUnitId
	local featuredAt = featuredRarity(banner)
	local entries: Distribution = {}
	for _, rarity in RARITIES do
		local rarityPercent = if RANK[rarity] >= floor then banner.oddsPercent[rarity] / total * 100 else 0
		local list = unitPools[rarity]
		local sharePercent = if guaranteed then 100 else (banner.featuredSharePercent or 0)
		for _, unitId in list do
			local percent: number
			local isFeatured = rarity == featuredAt and unitId == featuredId
			if rarity ~= featuredAt then
				percent = rarityPercent / #list
			elseif isFeatured then
				percent = rarityPercent * sharePercent / 100
			else
				percent = rarityPercent * (100 - sharePercent) / 100 / (#list - 1)
			end
			table.insert(entries, {
				unitId = unitId,
				rarity = rarity,
				percent = math.clamp(percent, 0, 100),
				featured = isFeatured,
			})
		end
	end
	-- Beku dalam-dalam karena di-memo dan dibagikan ke semua pemanggil.
	return TableUtil.deepFreeze(entries)
end

-- FUNGSI BOBOT TUNGGAL: peluang aktual tiap unit untuk satu draw dengan state & konteks ini.
-- Hasil di-memo per (rarity minimum, jaminan featured); tabel beku, jangan dimutasi.
function Roll.distribution(banner: Types.BannerDef, state: PityState, context: Context?): Distribution
	local floor = Roll.floorRank(state, context)
	local guaranteed = guaranteedFeaturedApplies(banner, state)
	local key = floor * 2 + (if guaranteed then 1 else 0)
	local perBanner = distributionCache[banner]
	if not perBanner then
		perBanner = {}
		distributionCache[banner] = perBanner
	end
	local cached = perBanner[key]
	if cached then
		return cached
	end
	local entries = build(banner, floor, guaranteed)
	perBanner[key] = entries
	return entries
end

-- Peluang referensi tanpa modifier pity/featured/batch.
function Roll.baseDistribution(banner: Types.BannerDef): Distribution
	return Roll.distribution(banner, { sinceLegendary = 0, sinceMythic = 0, guaranteedFeatured = false }, nil)
end

-- Memilih entri dari bilangan seragam u ∈ [0, 1). Entri berpeluang nol tidak pernah terpilih.
function Roll.pick(entries: Distribution, u: number): Entry
	assert(type(u) == "number" and u >= 0 and u < 1, "Roll.pick: u must be in [0, 1)")
	local target = u * 100
	local cumulative = 0
	local last: Entry? = nil
	for _, entry in entries do
		if entry.percent > 0 then
			cumulative += entry.percent
			last = entry
			if target < cumulative then
				return entry
			end
		end
	end
	-- Sisa pembulatan floating point jatuh ke entri berpeluang terakhir.
	return assert(last, "Roll.pick: empty distribution")
end

-- State pity sesudah satu hasil.
function Roll.advance(banner: Types.BannerDef, state: PityState, rarity: Types.Rarity, unitId: string): PityState
	local rank = RANK[rarity]
	local guaranteed = state.guaranteedFeatured
	local featuredAt = featuredRarity(banner)
	if banner.guaranteeFeaturedAfterMiss == true and featuredAt ~= nil and rarity == featuredAt then
		guaranteed = unitId ~= banner.featuredUnitId
	end
	return {
		sinceLegendary = if rank >= LEGENDARY_RANK then 0 else state.sinceLegendary + 1,
		sinceMythic = if rank >= MYTHIC_RANK then 0 else state.sinceMythic + 1,
		guaranteedFeatured = guaranteed,
	}
end

function Roll.draw(banner: Types.BannerDef, state: PityState, context: Context?, rng: Rng): (Draw, PityState)
	local entry = Roll.pick(Roll.distribution(banner, state, context), rng:NextNumber())
	local draw: Draw = { unitId = entry.unitId, rarity = entry.rarity, featured = entry.featured }
	return draw, Roll.advance(banner, state, entry.rarity, entry.unitId)
end

-- Roll satu batch (1× atau 10×). Murni: state awal tidak dimutasi.
function Roll.rollBatch(banner: Types.BannerDef, state: PityState, count: number, rng: Rng): ({ Draw }, PityState)
	local draws: { Draw } = {}
	local current = state
	local allRare = true
	for position = 1, count do
		local draw
		draw, current =
			Roll.draw(banner, current, { position = position, batchCount = count, allRareSoFar = allRare }, rng)
		allRare = allRare and draw.rarity == "Rare"
		table.insert(draws, draw)
	end
	return draws, current
end

return table.freeze(Roll)
