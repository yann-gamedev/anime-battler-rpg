--!strict
local Types = require(script.Parent.Parent.Types)
local Banners = require(script.Parent.Banners)
local BattlePass = require(script.Parent.BattlePass)
local Constants = require(script.Parent.Constants)
local Economy = require(script.Parent.Economy)
local MetaValidate = require(script.Parent.MetaValidate)
local Products = require(script.Parent.Products)
local Progression = require(script.Parent.Progression)
local ProfileFrames = require(script.Parent.ProfileFrames)
local Skins = require(script.Parent.Skins)
local Stages = require(script.Parent.Stages)
local Synergies = require(script.Parent.Synergies)
local Traits = require(script.Parent.Traits)
local Ultimates = require(script.Parent.Ultimates)
local Units = require(script.Parent.Units)

local function checkOdds(odds: number, source: string): ()
	assert(type(odds) == "number" and odds >= 0 and odds <= 100, `{source}: odds out of range`)
end

local function checkTotal(total: number, source: string): ()
	assert(math.abs(total - 100) < 1e-9, `{source}: odds must total 100%, got {total}%`)
end

local function isUnixSeconds(value: any): boolean
	return type(value) == "number" and value >= 0 and value < 2 ^ 53 and math.floor(value) == value
end

-- Periode: Standard permanen; Limited [startsAt, endsAt) dengan panjang rotationDays dari config.
local function checkPeriod(banner: Types.BannerDef, label: string): ()
	if banner.kind == "Standard" then
		assert(banner.startsAt == nil and banner.endsAt == nil, `{label}: standard banners are permanent`)
		return
	end
	local startsAt, endsAt, days = banner.startsAt, banner.endsAt, banner.rotationDays
	assert(isUnixSeconds(startsAt) and isUnixSeconds(endsAt), `{label}: limited period is missing`)
	assert(type(days) == "number" and days > 0, `{label}: rotationDays is missing`)
	assert(
		(endsAt :: number) - (startsAt :: number) == days * Banners.secondsPerDay,
		`{label}: period must last rotationDays`
	)
end

-- Jaminan pity hanya valid jika rarity tujuannya punya peluang.
local function checkGuarantees(banner: Types.BannerDef, label: string): ()
	local odds = banner.oddsPercent
	assert(odds.Mythic > 0, `{label}: hard pity needs Mythic odds`)
	assert(odds.Legendary + odds.Mythic > 0, `{label}: Legendary+ pity needs odds`)
	local minimum = Banners.multiSummonGuarantee.minimumRarity
	local reachable = 0
	local counted = minimum == "Rare"
	for _, rarity in { "Rare", "Epic", "Legendary", "Mythic" } :: { Types.Rarity } do
		counted = counted or rarity == minimum
		if counted then
			reachable += odds[rarity]
		end
	end
	assert(reachable > 0, `{label}: multi-summon guarantee needs odds`)
end

local CURRENCIES = { Gold = true, Gems = true, TraitShards = true, SummonTickets = true, AsramaTokens = true }

local function isPositiveInt(value: any): boolean
	return type(value) == "number" and value >= 1 and value < 2 ^ 53 and math.floor(value) == value
end

local function checkReward(reward: Types.Reward, label: string): ()
	if reward.kind == "Currency" then
		assert(CURRENCIES[reward.id :: string], `{label}: unknown currency`)
		assert(isPositiveInt(reward.amount), `{label}: amount must be a positive integer`)
	elseif reward.kind == "UnitChoice" then
		local options = assert(reward.options, `{label}: options are missing`)
		assert(#options > 0, `{label}: empty options`)
		for _, unitId in options do
			assert(Units[unitId], `{label}: unknown unit {unitId}`)
		end
	elseif reward.kind == "Skin" then
		assert(Skins[reward.id :: string], `{label}: unknown skin`)
	elseif reward.kind == "ProfileFrame" then
		assert(ProfileFrames[reward.id :: string], `{label}: unknown profile frame`)
	else
		error(`{label}: unknown reward kind`)
	end
end

local Validate = {}

-- Produk, Toko Akademi, dan Battle Pass. Argumen opsional untuk test.
function Validate.shop(products: any?, battlePass: any?): ()
	local productConfig = products or Products
	local passConfig = battlePass or BattlePass
	local ids: { [number]: string } = {}
	local seasonIds: { [string]: boolean } = {}
	for _, season in passConfig.seasons do
		seasonIds[season.id] = true
	end
	for key, def in productConfig.definitions do
		local label = `Products.{key}`
		assert(def.kind == "DeveloperProduct" or def.kind == "GamePass", `{label}: unknown kind`)
		assert(def.id == 0 or isPositiveInt(def.id), `{label}: id must be 0 or a positive integer`)
		if def.id > 0 then
			assert(ids[def.id] == nil, `{label}: duplicate id with {ids[def.id]}`)
			ids[def.id] = key
		end
		if def.grant then
			assert(def.kind == "DeveloperProduct", `{label}: only developer products grant currency`)
			assert(def.grant.currency == "Gems" or def.grant.currency == "TraitShards", `{label}: bad currency`)
			assert(isPositiveInt(def.grant.amount), `{label}: bad grant amount`)
		end
		if def.battlePassSeasonId then
			assert(seasonIds[def.battlePassSeasonId], `{label}: unknown battle pass season`)
			assert(def.grant == nil, `{label}: premium product cannot also grant currency`)
		end
	end
	for _, key in productConfig.displayOrder do
		assert(productConfig.definitions[key], `Products.displayOrder: unknown product {key}`)
	end
	for key in productConfig.passAttributes do
		local def = productConfig.definitions[key]
		assert(def and def.kind == "GamePass", `Products.passAttributes: {key} is not a game pass`)
	end
	local itemIds: { [string]: boolean } = {}
	for _, item in productConfig.academy do
		local label = `Products.academy.{item.id}`
		assert(not itemIds[item.id], `{label}: duplicate item`)
		itemIds[item.id] = true
		assert(isPositiveInt(item.costGems), `{label}: costGems must be a positive integer`)
		if item.kind == "Unit" then
			assert(Units[item.itemId], `{label}: unknown unit`)
		else
			assert(item.kind == "Skin" and Skins[item.itemId], `{label}: unknown skin`)
		end
	end

	local seen: { [string]: boolean } = {}
	for _, season in passConfig.seasons do
		local label = `BattlePass.{season.id}`
		assert(not seen[season.id], `{label}: duplicate season`)
		seen[season.id] = true
		assert(#season.id <= passConfig.maxSeasonIdLength, `{label}: id too long`)
		assert(isUnixSeconds(season.startsAt) and isUnixSeconds(season.endsAt), `{label}: bad period`)
		assert(
			season.endsAt - season.startsAt == passConfig.seasonDays * passConfig.secondsPerDay,
			`{label}: season must last seasonDays`
		)
		assert(#season.tiers == passConfig.tierCount, `{label}: tier count mismatch`)
		assert(isPositiveInt(season.xpPerTier), `{label}: xpPerTier must be a positive integer`)
		local freeGems, freeUnitChoices = 0, 0
		for tier, def in season.tiers do
			for _, reward in def.free do
				checkReward(reward, `{label}.tiers[{tier}].free`)
				if reward.kind == "Currency" and reward.id == "Gems" then
					freeGems += reward.amount :: number
				elseif reward.kind == "UnitChoice" then
					freeUnitChoices += 1
				end
			end
			for _, reward in def.premium do
				checkReward(reward, `{label}.tiers[{tier}].premium`)
				-- Tidak ada unit yang hanya ada di premium (ECONOMY §6).
				assert(reward.kind ~= "UnitChoice", `{label}.tiers[{tier}]: premium cannot grant units`)
			end
		end
		local target = Economy.battlePass.freeGemsTarget
		assert(math.abs(freeGems - target) <= target * 0.1, `{label}: free Gems {freeGems} far from target`)
		assert(freeUnitChoices == 1, `{label}: free track needs exactly one unit choice`)
	end
end

function Validate.run(
	units: { [string]: Types.UnitDef }?,
	banners: { [string]: Types.BannerDef }?,
	traitTiers: { [Types.TraitTier]: Traits.TierDef }?
): ()
	local unitDefs = units or Units
	for id, unit in unitDefs do
		local label = `Units.{id}`
		assert(unit.id == id, `{label}: mismatched unit ID`)
		assert(Economy.rarityMultipliers[unit.rarity], `{label}: unknown rarity {unit.rarity}`)
		assert(Synergies.elements[unit.element], `{label}: unknown element {unit.element}`)
		assert(type(unit.ultimate) == "string" and Ultimates[unit.ultimate], `{label}: missing or unknown ultimate ID`)
	end

	for id, banner in banners or Banners.definitions do
		local label = `Banners.{id}`
		local seenUnits: { [string]: boolean } = {}
		local poolSizes: { [Types.Rarity]: number } = {}
		for _, unitId in banner.unitIds do
			local unit = assert(unitDefs[unitId], `{label}: unknown unit {unitId}`)
			assert(not seenUnits[unitId], `{label}: duplicate unit {unitId}`)
			seenUnits[unitId] = true
			poolSizes[unit.rarity] = (poolSizes[unit.rarity] or 0) + 1
		end

		local total = 0
		for rarity in Economy.rarityMultipliers do
			local odds = banner.oddsPercent[rarity]
			checkOdds(odds, `{label}.{rarity}`)
			assert(odds == 0 or poolSizes[rarity], `{label}: no units for {rarity} odds`)
			total += odds
		end
		for rarity in banner.oddsPercent do
			assert(Economy.rarityMultipliers[rarity], `{label}: unknown rarity {rarity}`)
		end
		checkTotal(total, label)

		if banner.kind == "Limited" then
			local featuredId = banner.featuredUnitId
			assert(featuredId and seenUnits[featuredId], `{label}: featured unit is missing from the pool`)
			local share = assert(banner.featuredSharePercent, `{label}: featured odds are missing`)
			checkOdds(share, `{label}.featuredSharePercent`)
			local rarity = unitDefs[featuredId].rarity
			assert(banner.oddsPercent[rarity] > 0, `{label}: featured rarity has zero odds`)
			assert(share == 100 or poolSizes[rarity] > 1, `{label}: no other units in featured rarity`)
		end
		checkPeriod(banner, label)
		checkGuarantees(banner, label)
	end
	local multi = Banners.multiSummonGuarantee
	assert(Economy.summonGems[1] and Economy.summonGems[multi.count], "Economy: summon Gems prices are missing")
	assert(
		Economy.rarityMultipliers[multi.minimumRarity :: Types.Rarity],
		"Banners: unknown multi-summon minimum rarity"
	)

	local total = 0
	for tier, def in traitTiers or Traits.tiers do
		checkOdds(def.oddsPercent, `Traits.{tier}`)
		assert(#def.traits > 0, `Traits.{tier}: empty trait pool`)
		total += def.oddsPercent
	end
	checkTotal(total, "Traits")

	local previous = Constants.BOARD_UNITS_START
	for _, unlock in Progression.BOARD_UNLOCKS do
		assert(Stages.byId[unlock.stageId], `Progression: unknown board unlock stage {unlock.stageId}`)
		assert(unlock.maxUnits > previous and unlock.maxUnits <= Constants.BOARD_UNITS_MAX, "Progression: bad unlock")
		previous = unlock.maxUnits
	end
	assert(Stages.byId[Progression.ONBOARDING_FINAL_STAGE_ID], "Progression: unknown onboarding stage")
	Validate.shop()
	MetaValidate.run()
	assert(#Progression.MERGE_GOLD == #Economy.mergeDuplicates, "Progression: merge Gold must match star steps")
	for unitId, cell in Progression.TUTORIAL_STARTER_CELLS do
		assert(unitDefs[unitId] and cell >= 1 and cell <= Constants.BOARD_SLOTS, `Progression: bad starter {unitId}`)
	end
end

return table.freeze(Validate)
