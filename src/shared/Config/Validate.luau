--!strict
local Types = require(script.Parent.Parent.Types)
local Banners = require(script.Parent.Banners)
local Constants = require(script.Parent.Constants)
local Economy = require(script.Parent.Economy)
local Progression = require(script.Parent.Progression)
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

local Validate = {}

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
	end

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
	assert(#Progression.MERGE_GOLD == #Economy.mergeDuplicates, "Progression: merge Gold must match star steps")
	for unitId, cell in Progression.TUTORIAL_STARTER_CELLS do
		assert(unitDefs[unitId] and cell >= 1 and cell <= Constants.BOARD_SLOTS, `Progression: bad starter {unitId}`)
	end
end

return table.freeze(Validate)
