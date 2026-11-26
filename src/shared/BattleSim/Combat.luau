--!strict
local Types = require(script.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Config.Constants)
local Rng = require(script.Parent.Rng)
local State = require(script.Parent.State)
local Stats = require(script.Parent.Stats)
local SynergyResolver = require(script.Parent.SynergyResolver)
local Targeting = require(script.Parent.Targeting)

local Combat = {}
local TICKS = Constants.BATTLE_TICKS_PER_SECOND

function Combat.log(fight: State.Fight, event: Types.BattleEvent): ()
	table.insert(fight.log, event)
end

function Combat.slowAt(fight: State.Fight, unit: State.Unit): number
	local slow = Combat.value(unit.slow, fight.tick)
	for _, storm in fight.storms do
		if storm.side ~= unit.side and Targeting.distance(storm.cell, unit.cell) <= storm.radius then
			slow = math.max(slow, storm.slow)
		end
	end
	return slow
end

function Combat.spawn(
	fight: State.Fight,
	def: Types.UnitDef,
	side: Types.BattleSide,
	homeCell: number,
	cell: number,
	stats: Stats.Stats,
	synergy: SynergyResolver.Active,
	owner: number?,
	expires: number?
): State.Unit
	local unit: State.Unit = {
		id = #fight.units + 1,
		def = def,
		side = side,
		homeCell = homeCell,
		cell = cell,
		stats = stats,
		synergy = synergy,
		hp = stats.hp,
		mana = stats.startingMana,
		credit = 0,
		moveAt = 0,
		shield = 0,
		revived = false,
		usedFreeUltimate = false,
		owner = owner,
		expires = expires,
		stunUntil = 0,
		freezeUntil = 0,
		invulnerableUntil = 0,
	}
	table.insert(fight.units, unit)
	table.insert(fight.teams[side], unit)
	Combat.log(fight, {
		t = fight.tick,
		kind = "spawn",
		unit = unit.id,
		unitId = def.id,
		side = side,
		cell = cell,
		hp = unit.hp,
		maxHp = stats.hp,
		owner = owner,
	})
	return unit
end

function Combat.move(fight: State.Fight, unit: State.Unit, cell: number, leap: boolean): ()
	if cell ~= unit.cell then
		unit.cell = cell
		Combat.log(fight, { t = fight.tick, kind = "move", unit = unit.id, cell = cell, leap = leap })
	end
end

function Combat.status(fight: State.Fight, unit: State.Unit, effect: string, untilTick: number): ()
	Combat.log(fight, { t = fight.tick, kind = "status", unit = unit.id, effect = effect, untilTick = untilTick })
end

function Combat.untilTick(fight: State.Fight, seconds: number): number
	return fight.tick + math.round(TICKS * seconds)
end

function Combat.value(effect: State.Timed?, tick: number): number
	return if effect and effect.untilTick > tick then effect.value else 0
end

function Combat.setSlow(fight: State.Fight, dst: State.Unit, amount: number, seconds: number): ()
	local old = Combat.value(dst.slow, fight.tick)
	if dst.hp > 0 and old <= amount then
		local untilTick = Combat.untilTick(fight, seconds)
		if old == amount and dst.slow then
			untilTick = math.max(untilTick, dst.slow.untilTick)
		end
		dst.slow = { value = amount, untilTick = untilTick }
		Combat.status(fight, dst, "slow", untilTick)
	end
end

function Combat.setBurn(fight: State.Fight, src: State.Unit, dst: State.Unit, fraction: number, seconds: number): ()
	local old = dst.burn
	if dst.hp > 0 and (not old or old.untilTick < fight.tick or old.fraction <= fraction) then
		local untilTick = Combat.untilTick(fight, seconds)
		if old and old.fraction == fraction then
			untilTick = math.max(untilTick, old.untilTick)
		end
		dst.burn = {
			src = src.id,
			fraction = fraction,
			nextTick = if old then old.nextTick else fight.tick + TICKS,
			untilTick = untilTick,
		}
		Combat.status(fight, dst, "burn", untilTick)
	end
end

function Combat.addMana(unit: State.Unit, amount: number): ()
	unit.mana = math.min(Constants.MANA_MAX, unit.mana + amount * unit.stats.manaGain)
end

function Combat.heal(fight: State.Fight, unit: State.Unit, amount: number): ()
	if unit.hp > 0 and unit.hp < unit.stats.hp and amount > 0 then
		unit.hp = math.min(unit.stats.hp, unit.hp + amount)
		Combat.log(fight, { t = fight.tick, kind = "heal", unit = unit.id, hp = unit.hp, shield = unit.shield })
	end
end

function Combat.shield(fight: State.Fight, unit: State.Unit, fraction: number): ()
	unit.shield += unit.stats.hp * fraction
	Combat.log(fight, { t = fight.tick, kind = "shield", unit = unit.id, hp = unit.hp, shield = unit.shield })
end

function Combat.cleanse(fight: State.Fight, unit: State.Unit): ()
	unit.burn = nil
	unit.slow = nil
	unit.taunt = nil
	unit.stunUntil = 0
	unit.freezeUntil = 0
	Combat.status(fight, unit, "cleanse", fight.tick)
end

local function studentMultiplier(fight: State.Fight, unit: State.Unit): number
	local tier = if unit.def.status == "Murid" then unit.synergy.statuses.Murid else nil
	if tier and tier.stackIntervalSeconds and tier.atkAndDefBonus then
		local stacks = math.floor(fight.tick / (tier.stackIntervalSeconds * TICKS))
		return 1 + stacks * tier.atkAndDefBonus
	end
	return 1
end

function Combat.attackPower(fight: State.Fight, unit: State.Unit): number
	return unit.stats.atk * studentMultiplier(fight, unit) * (1 + Combat.value(unit.atkBuff, fight.tick))
end

local function die(fight: State.Fight, unit: State.Unit): ()
	Combat.log(fight, { t = fight.tick, kind = "death", unit = unit.id })
	local tier = if unit.def.status == "Familiar" then unit.synergy.statuses.Familiar else nil
	if tier and tier.firstReviveHp and not unit.revived then
		unit.revived = true
		unit.hp = unit.stats.hp * tier.firstReviveHp
		Combat.cleanse(fight, unit)
		Combat.log(fight, { t = fight.tick, kind = "revive", unit = unit.id, hp = unit.hp })
	end
end

function Combat.damage(
	fight: State.Fight,
	src: State.Unit,
	dst: State.Unit,
	amount: number,
	kind: "attack" | "skill" | "effect",
	crit: boolean?
): boolean
	if dst.hp <= 0 then
		return false
	end
	local tick = fight.tick
	local direct = kind ~= "effect"
	local damage = if dst.invulnerableUntil > tick then 0 else amount
	if direct then
		local base = Constants.DAMAGE_DEFENSE_BASE
		damage *= base / (base + dst.stats.def * studentMultiplier(fight, dst))
	end
	damage *= 1 - Combat.value(dst.reduction, tick)
	local absorbed = math.min(dst.shield, damage)
	local hpLoss = math.min(dst.hp, damage - absorbed)
	dst.shield -= absorbed
	dst.hp -= hpLoss
	local eventKind: "attack" | "damage" = if kind == "attack" then "attack" else "damage"
	Combat.log(fight, {
		t = tick,
		kind = eventKind,
		src = src.id,
		dst = dst.id,
		dmg = absorbed + hpLoss,
		crit = crit == true,
		hp = dst.hp,
		shield = dst.shield,
	})
	if dst.hp <= 0 then
		die(fight, dst)
	elseif direct and damage > 0 then
		Combat.addMana(dst, Constants.MANA_PER_HIT_TAKEN)
	end
	if direct and damage > 0 then
		local reflect = Combat.value(dst.reflect, tick)
		if reflect > 0 then
			Combat.damage(fight, dst, src, (absorbed + hpLoss) * reflect, "effect")
		end
		Combat.heal(fight, src, hpLoss * src.stats.lifesteal)
	end
	return damage > 0
end

function Combat.attack(fight: State.Fight, src: State.Unit, dst: State.Unit): ()
	local crit = Rng.nextNumber(fight.rng) < src.stats.critChance
	local raw = Combat.attackPower(fight, src) * (if crit then src.stats.critDamage else 1)
	Combat.addMana(src, Constants.MANA_PER_ATTACK)
	if not Combat.damage(fight, src, dst, raw, "attack", crit) or dst.hp <= 0 then
		return
	end
	local tier = src.synergy.elements[src.def.element]
	if not tier then
		return
	end
	if tier.burnHpPerSecond and tier.burnSeconds then
		Combat.setBurn(fight, src, dst, tier.burnHpPerSecond, tier.burnSeconds)
	end
	if tier.slow then
		Combat.setSlow(fight, dst, tier.slow, Constants.BATTLE_ICE_SLOW_SECONDS)
	end
	if tier.freezeChance and tier.freezeSeconds and Rng.nextNumber(fight.rng) < tier.freezeChance then
		dst.freezeUntil = math.max(dst.freezeUntil, Combat.untilTick(fight, tier.freezeSeconds))
		Combat.status(fight, dst, "freeze", dst.freezeUntil)
	end
end

function Combat.upkeep(fight: State.Fight, unit: State.Unit): ()
	local tick = fight.tick
	if unit.expires and unit.expires <= tick then
		unit.hp = 0
		Combat.log(fight, { t = tick, kind = "despawn", unit = unit.id })
		return
	end
	local burn = unit.burn
	if burn then
		if tick > burn.untilTick then
			unit.burn = nil
		elseif tick >= burn.nextTick then
			burn.nextTick += TICKS
			Combat.damage(fight, fight.units[burn.src], unit, unit.stats.hp * burn.fraction, "effect")
		end
	end
	if tick % TICKS == 0 then
		local light = unit.synergy.elements.Cahaya
		if light and light.healHpPerSecond and (light.healTarget == "allAllies" or unit.def.element == "Cahaya") then
			Combat.heal(fight, unit, unit.stats.hp * light.healHpPerSecond)
		end
	end
end

return table.freeze(Combat)
