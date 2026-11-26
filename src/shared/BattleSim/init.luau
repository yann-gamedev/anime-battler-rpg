--!strict
local Shared = script.Parent
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Units = require(Shared.Config.Units)
local Combat = require(script.Combat)
local Rng = require(script.Rng)
local Skills = require(script.Skills)
local State = require(script.State)
local Stats = require(script.Stats)
local SynergyResolver = require(script.SynergyResolver)
local Targeting = require(script.Targeting)

local BattleSim = {}

local TICKS = Constants.BATTLE_TICKS_PER_SECOND
local MAX_TICKS = TICKS * Constants.BATTLE_MAX_SECONDS

local function isIntegerInRange(value: number, min: number, max: number): boolean
	return value >= min and value <= max and value % 1 == 0
end

local function addTeam(fight: State.Fight, input: { Types.BattleUnitInput }, side: Types.BattleSide): ()
	local ordered: { Types.BattleUnitInput } = {}
	local occupied: { [number]: boolean } = {}
	for _, member in input do
		assert(Units[member.unitId], `Unknown unit {member.unitId}`)
		assert(isIntegerInRange(member.cell, 1, Constants.BOARD_SLOTS), "Invalid battle unit cell")
		assert(not occupied[member.cell], "Battle team has duplicate cells")
		assert(
			isIntegerInRange(member.stars, Constants.UNIT_STARS_MIN, Constants.UNIT_STARS_MAX),
			"Invalid battle unit stars"
		)
		assert(
			isIntegerInRange(member.level, Constants.UNIT_LEVEL_MIN, Constants.UNIT_LEVEL_MAX),
			"Invalid battle unit level"
		)
		local hpMultiplier = member.hpMultiplier
		assert(
			hpMultiplier == nil
				or (
					type(hpMultiplier) == "number"
					and hpMultiplier >= 1
					and hpMultiplier <= Constants.BATTLE_HP_MULTIPLIER_MAX
				),
			"Invalid battle unit hpMultiplier"
		)
		occupied[member.cell] = true
		table.insert(ordered, member)
		assert(#ordered <= Constants.BOARD_UNITS_MAX, "Battle team exceeds unit limit")
	end
	table.sort(ordered, function(a: Types.BattleUnitInput, b: Types.BattleUnitInput): boolean
		return a.cell < b.cell
	end)
	local synergy = SynergyResolver.resolve(ordered)
	for _, member in ordered do
		local stats = Stats.compute(member, synergy)
		if member.hpMultiplier then
			stats.hp *= member.hpMultiplier -- boss raid: HP besar dari config server
		end
		Combat.spawn(
			fight,
			Units[member.unitId],
			side,
			member.cell,
			Targeting.startCell(side, member.cell),
			stats,
			synergy,
			nil,
			nil
		)
	end
end

local function winner(fight: State.Fight): (Types.BattleSide | "draw")?
	local aliveA, aliveB = false, false
	for _, unit in fight.units do
		if unit.hp > 0 then
			if unit.side == "A" then
				aliveA = true
			else
				aliveB = true
			end
			if aliveA and aliveB then
				return nil
			end
		end
	end
	if aliveA then
		return "A"
	end
	return if aliveB then "B" else "draw"
end

local function tryCast(fight: State.Fight, src: State.Unit, target: State.Unit, enemies: { State.Unit }): boolean
	if src.owner ~= nil then
		return false
	end
	local freeTick = src.stats.freeUltimateTick
	if freeTick and not src.usedFreeUltimate then
		if fight.tick < freeTick then
			return false
		end
		src.usedFreeUltimate = true
	elseif src.mana >= Constants.MANA_MAX then
		src.mana = 0
	else
		return false
	end
	Skills.cast(fight, src, target)
	if src.hp > 0 and src.stats.echoChance > 0 and Rng.nextNumber(fight.rng) < src.stats.echoChance then
		local nextTarget = Targeting.choose(fight, src, Targeting.living(enemies))
		if nextTarget then
			Skills.cast(fight, src, nextTarget)
		end
	end
	return true
end

local function act(fight: State.Fight, unit: State.Unit): ()
	local tick = fight.tick
	if unit.hp <= 0 or unit.freezeUntil > tick or unit.stunUntil > tick then
		return
	end

	local opposite = fight.teams[Targeting.opposite(unit.side)]
	local target, withinRange = Targeting.choose(fight, unit, Targeting.living(opposite))
	if not target then
		return
	end

	local speedMultiplier = 1 - Combat.slowAt(fight, unit)
	unit.credit += unit.stats.spd * speedMultiplier / TICKS
	if tryCast(fight, unit, target, opposite) then
		unit.credit = math.min(unit.credit, 1)
		return
	end
	if not withinRange then
		unit.credit = math.min(unit.credit, 1)
		if tick >= unit.moveAt then
			local cell = Targeting.stepToward(fight, unit, target)
			if cell then
				Combat.move(fight, unit, cell, false)
			end
			unit.moveAt = tick + math.ceil(Constants.BATTLE_MOVE_TICKS / speedMultiplier)
		end
		return
	end
	while unit.credit >= 1 and target and withinRange and unit.hp > 0 do
		unit.credit -= 1
		Combat.attack(fight, unit, target)
		if target.hp <= 0 then
			target, withinRange = Targeting.choose(fight, unit, Targeting.living(opposite))
		end
	end
end

function BattleSim.run(input: Types.BattleInput): Types.BattleResult
	local maxTicks = input.maxTicks or MAX_TICKS
	assert(isIntegerInRange(maxTicks, 1, MAX_TICKS), `maxTicks must be an integer in 1–{MAX_TICKS}`)
	local fight: State.Fight = {
		tick = 0,
		rng = Rng.new(input.seed),
		log = {},
		storms = {},
		units = {},
		teams = { A = {}, B = {} },
	}
	addTeam(fight, input.teamA, "A")
	addTeam(fight, input.teamB, "B")

	local result = winner(fight)
	if not result then
		for _, unit in fight.units do
			if unit.def.class == "Assassin" then
				local target = Targeting.backline(fight.teams[Targeting.opposite(unit.side)])
				if target then
					Combat.move(fight, unit, Targeting.leapCell(fight, unit, target), true)
				end
			end
		end
	end

	while not result and fight.tick < maxTicks do
		fight.tick += 1
		for index = #fight.storms, 1, -1 do
			if fight.storms[index].untilTick <= fight.tick then
				table.remove(fight.storms, index)
			end
		end
		for _, unit in fight.units do
			if unit.hp > 0 then
				Combat.upkeep(fight, unit)
				if unit.hp > 0 then
					Skills.upkeep(fight, unit)
				end
			end
		end
		for index = 1, #fight.units do -- Units summoned this tick start acting next tick.
			act(fight, fight.units[index])
		end
		result = winner(fight)
	end

	local survivors: { Types.BattleUnitSnapshot } = {}
	for _, unit in fight.units do
		if unit.hp > 0 then
			table.insert(survivors, {
				id = unit.id,
				unitId = unit.def.id,
				side = unit.side,
				cell = unit.cell,
				hp = unit.hp,
				maxHp = unit.stats.hp,
			})
		end
	end
	return { winner = result or "draw", ticks = fight.tick, log = fight.log, survivors = survivors }
end

return table.freeze(BattleSim)
