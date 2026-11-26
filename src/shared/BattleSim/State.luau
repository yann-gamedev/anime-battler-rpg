--!strict
local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Rng)
local Stats = require(script.Parent.Stats)
local SynergyResolver = require(script.Parent.SynergyResolver)

export type Timed = { value: number, untilTick: number }
export type Burn = { src: number, fraction: number, nextTick: number, untilTick: number }
export type Storm = { side: Types.BattleSide, cell: number, radius: number, slow: number, untilTick: number }
export type Unit = {
	id: number,
	def: Types.UnitDef,
	side: Types.BattleSide,
	cell: number,
	homeCell: number,
	stats: Stats.Stats,
	synergy: SynergyResolver.Active,
	hp: number,
	mana: number,
	credit: number,
	moveAt: number,
	shield: number,
	revived: boolean,
	usedFreeUltimate: boolean,
	owner: number?,
	expires: number?,
	burn: Burn?,
	slow: Timed?,
	atkBuff: Timed?,
	reduction: Timed?,
	reflect: Timed?,
	taunt: Timed?,
	stunUntil: number,
	freezeUntil: number,
	invulnerableUntil: number,
	bursts: { number }?,
}

export type Fight = {
	tick: number,
	rng: Rng.State,
	log: { Types.BattleEvent },
	storms: { Storm },
	units: { Unit },
	teams: { [Types.BattleSide]: { Unit } },
}

return table.freeze({})
