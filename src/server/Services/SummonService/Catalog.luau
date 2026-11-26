--!strict
-- Data banner murni: periode aktif (waktu server), harga, fingerprint quote, dan BannerView untuk client.
-- Semua angka dibaca dari Config/Banners + Config/Economy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Banners = require(Shared.Config.Banners)
local Economy = require(Shared.Config.Economy)
local Odds = require(script.Parent.Odds)
local Roll = require(script.Parent.Roll)

type PityState = Roll.PityState
export type CurrencyKind = "Gems" | "SummonTickets"

local MULTI_COUNT = Banners.multiSummonGuarantee.count

local Catalog = {}
Catalog.MULTI_COUNT = MULTI_COUNT

local definitions: { [string]: Types.BannerDef } = Banners.definitions
local orderedIds: { string } = {}
for id in definitions do
	table.insert(orderedIds, id)
end
-- Standard dulu, lalu urut ID.
table.sort(orderedIds, function(a: string, b: string): boolean
	local aStandard, bStandard = definitions[a].kind == "Standard", definitions[b].kind == "Standard"
	if aStandard ~= bStandard then
		return aStandard
	end
	return a < b
end)
table.freeze(orderedIds)

function Catalog.orderedIds(): { string }
	return orderedIds
end

function Catalog.get(bannerId: string): Types.BannerDef?
	return definitions[bannerId]
end

function Catalog.isCount(count: any): boolean
	return count == 1 or count == MULTI_COUNT
end

-- Aktif bila now ∈ [startsAt, endsAt). Tanpa periode = permanen.
function Catalog.isActive(banner: Types.BannerDef, now: number): boolean
	local startsAt, endsAt = banner.startsAt, banner.endsAt
	if startsAt ~= nil and now < startsAt then
		return false
	end
	if endsAt ~= nil and now >= endsAt then
		return false
	end
	return true
end

function Catalog.price(count: number, payWith: Types.SummonPayment): (CurrencyKind, number)
	if payWith == "Gems" then
		return "Gems", assert(Economy.summonGems[count], "Catalog.price: missing Gems price")
	end
	return "SummonTickets", Economy.summonTicketsPerRoll * count
end

local function prices(): { gems1: number, gems10: number, tickets1: number, tickets10: number }
	local _, gems1 = Catalog.price(1, "Gems")
	local _, gems10 = Catalog.price(MULTI_COUNT, "Gems")
	local _, tickets1 = Catalog.price(1, "Tickets")
	local _, tickets10 = Catalog.price(MULTI_COUNT, "Tickets")
	return { gems1 = gems1, gems10 = gems10, tickets1 = tickets1, tickets10 = tickets10 }
end

-- Tanda tangan config yang memengaruhi odds; konstan selama server hidup (config beku).
local signatures: { [string]: string } = {}
for id, banner in definitions do
	local odds = banner.oddsPercent
	signatures[id] = table.concat({
		odds.Rare,
		odds.Epic,
		odds.Legendary,
		odds.Mythic,
		banner.featuredUnitId or "-",
		banner.featuredSharePercent or 0,
		tostring(banner.guaranteeFeaturedAfterMiss == true),
		Banners.pity.legendaryPlusRolls,
		Banners.pity.mythicRolls,
		MULTI_COUNT,
		Banners.multiSummonGuarantee.minimumRarity,
		table.concat(banner.unitIds, ","),
	}, "|")
end

-- Fingerprint odds yang dilihat pemain: state pity + config. Berubah → quote lama basi (ODDS_CHANGED).
function Catalog.fingerprint(bannerId: string, state: PityState): string
	local signature = assert(signatures[bannerId], "Catalog.fingerprint: unknown banner")
	return `{state.sinceLegendary}:{state.sinceMythic}:{state.guaranteedFeatured}#{signature}`
end

function Catalog.view(banner: Types.BannerDef, state: PityState, now: number): Types.BannerView
	return {
		id = banner.id,
		kind = banner.kind,
		active = Catalog.isActive(banner, now),
		startsAt = banner.startsAt,
		endsAt = banner.endsAt,
		featuredUnitId = if banner.kind == "Limited" then banner.featuredUnitId else nil,
		prices = prices(),
		pity = {
			sinceLegendary = state.sinceLegendary,
			sinceMythic = state.sinceMythic,
			legendaryPlusRolls = Banners.pity.legendaryPlusRolls,
			mythicRolls = Banners.pity.mythicRolls,
			guaranteedFeatured = state.guaranteedFeatured,
		},
		odds = {
			base = Odds.base(banner),
			single = Odds.single(banner, state),
			ten = Odds.marginals(banner, state, MULTI_COUNT),
		},
	}
end

return table.freeze(Catalog)
