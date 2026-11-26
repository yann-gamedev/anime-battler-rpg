--!strict
local Types = require(script.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Config.Constants)
local Economy = require(script.Parent.Parent.Config.Economy)
local Traits = require(script.Parent.Parent.Config.Traits)
local Units = require(script.Parent.Parent.Config.Units)
local SynergyResolver = require(script.Parent.SynergyResolver)

local traitById: { [string]: Types.TraitDef } = {}
for _, tier in Traits.tiers do
	for _, trait in tier.traits do
		traitById[trait.id] = trait
	end
end

export type Stats = {
	hp: number,
	atk: number,
	def: number,
	spd: number,
	range: number,
	critChance: number,
	critDamage: number,
	manaGain: number,
	startingMana: number,
	lifesteal: number,
	echoChance: number,
	freeUltimateTick: number?,
}

local Stats = {}

function Stats.compute(input: Types.BattleUnitInput, active: SynergyResolver.Active): Stats
	local def = Units[input.unitId]
	local base = def.base
	local trait = if input.trait then assert(traitById[input.trait], `Unknown trait {input.trait}`) else nil
	local mult = Economy.rarityMultipliers[def.rarity]
		* Economy.starMultiplier(input.stars)
		* (1 + Economy.levelStatBonus * (input.level - 1))
		* (1 + (if trait then trait.allStatsBonus or 0 else 0))
	local element = active.elements[def.element]
	local professor = active.statuses.Profesor
	local freeSeconds = if trait then trait.freeFirstUltimateAtSeconds else nil
	return {
		hp = base.hp * mult * (1 + (if trait then trait.hpBonus or 0 else 0)),
		atk = base.atk * mult * (1 + (if trait then trait.atkBonus or 0 else 0)),
		def = base.def * mult * (1 + (if trait then trait.defBonus or 0 else 0)),
		spd = base.spd * mult * (1 + (if trait then trait.spdBonus or 0 else 0)) * (1 + (if element
			then element.speedBonus or 0
			else 0)),
		-- Range is grid geometry, including the melee/front-line rule.
		range = base.range,
		critChance = Constants.BASE_CRIT_CHANCE + (if trait then trait.critChanceBonus or 0 else 0) + (if element
			then element.critChanceBonus or 0
			else 0),
		critDamage = (if element then element.critDamageMultiplier else nil) or Constants.BASE_CRIT_DAMAGE_MULTIPLIER,
		manaGain = (1 + (if trait then trait.manaGainBonus or 0 else 0))
			* (1 + (if professor then professor.manaGainBonus or 0 else 0)),
		startingMana = if trait then trait.startingMana or 0 else 0,
		lifesteal = if trait then trait.lifesteal or 0 else 0,
		echoChance = if trait then trait.repeatUltimateChance or 0 else 0,
		freeUltimateTick = if freeSeconds then math.round(freeSeconds * Constants.BATTLE_TICKS_PER_SECOND) else nil,
	}
end

return table.freeze(Stats)
