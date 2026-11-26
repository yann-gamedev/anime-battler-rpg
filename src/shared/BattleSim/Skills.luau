--!strict
local Constants = require(script.Parent.Parent.Config.Constants)
local Ultimates = require(script.Parent.Parent.Config.Ultimates)
local Combat = require(script.Parent.Combat)
local State = require(script.Parent.State)
local Targeting = require(script.Parent.Targeting)

type Parameters = { [string]: number | boolean }
type SelectTargets = (State.Fight, State.Unit, State.Unit, Parameters) -> { State.Unit }
type Apply = (State.Fight, State.Unit, { State.Unit }, Parameters, State.Unit) -> ()
type Skill = { targets: SelectTargets, apply: Apply }

local Skills = {}
local NO_SYNERGY = { elements = {}, statuses = {} }

local function number(params: Parameters, key: string): number
	local value = params[key]
	assert(type(value) == "number", `Missing ultimate parameter {key}`)
	return value
end

local function enemies(fight: State.Fight, src: State.Unit): { State.Unit }
	return Targeting.living(fight.teams[Targeting.opposite(src.side)])
end

local function allies(fight: State.Fight, src: State.Unit): { State.Unit }
	return Targeting.living(fight.teams[src.side])
end

local function selfTarget(_fight: State.Fight, src: State.Unit): { State.Unit }
	return { src }
end

local function primary(_fight: State.Fight, _src: State.Unit, target: State.Unit): { State.Unit }
	return { target }
end

local function area(fight: State.Fight, src: State.Unit, cell: number, radius: number): { State.Unit }
	local result: { State.Unit } = {}
	for _, enemy in enemies(fight, src) do
		if Targeting.distance(cell, enemy.cell) <= radius then
			table.insert(result, enemy)
		end
	end
	return result
end

local function targetArea(fight: State.Fight, src: State.Unit, target: State.Unit, params: Parameters): { State.Unit }
	return area(fight, src, target.cell, number(params, "radiusCells"))
end

local function damageAll(fight: State.Fight, src: State.Unit, targets: { State.Unit }, params: Parameters): ()
	local damage = Combat.attackPower(fight, src) * number(params, "damageAtk")
	for _, dst in targets do
		Combat.damage(fight, src, dst, damage, "skill")
	end
end

local function stun(fight: State.Fight, dst: State.Unit, seconds: number): ()
	if dst.hp > 0 then
		dst.stunUntil = math.max(dst.stunUntil, Combat.untilTick(fight, seconds))
		Combat.status(fight, dst, "stun", dst.stunUntil)
	end
end

local function summon(fight: State.Fight, src: State.Unit, _targets: { State.Unit }, params: Parameters): ()
	local multiplier = number(params, "summonStatMultiplier")
	local stats = table.clone(src.stats)
	stats.hp *= multiplier
	stats.atk *= multiplier
	stats.def *= multiplier
	stats.spd *= multiplier
	stats.critChance = Constants.BASE_CRIT_CHANCE
	stats.critDamage = Constants.BASE_CRIT_DAMAGE_MULTIPLIER
	stats.startingMana = 0
	stats.manaGain = 1
	stats.lifesteal = 0
	stats.echoChance = 0
	stats.freeUltimateTick = nil
	local expires = Combat.untilTick(fight, number(params, "summonSeconds"))
	for _ = 1, number(params, "summonCount") do
		Combat.spawn(fight, src.def, src.side, src.homeCell, src.cell, stats, NO_SYNERGY, src.id, expires)
	end
end

local skills: { [string]: Skill } = {
	kael_flare_burst = { targets = targetArea, apply = damageAll },
	mira_frost_veil = {
		targets = function(fight, src, _, params)
			local targets = allies(fight, src)
			table.sort(targets, Targeting.byHealth)
			while #targets > number(params, "allyCount") do
				table.remove(targets)
			end
			return targets
		end,
		apply = function(fight, _, targets, params)
			for _, dst in targets do
				Combat.shield(fight, dst, number(params, "shieldHp"))
			end
		end,
	},
	dorin_static_dash = {
		targets = primary,
		apply = function(fight, src, targets, params)
			local dst = targets[1]
			local damage = Combat.attackPower(fight, src) * number(params, "damageAtk")
			for _ = 1, number(params, "hitCount") do
				if src.hp <= 0 or dst.hp <= 0 then
					break
				end
				if Combat.damage(fight, src, dst, damage, "skill") then
					stun(fight, dst, number(params, "stunSeconds"))
				end
			end
		end,
	},
	brutus_glacier_guard = {
		targets = enemies,
		apply = function(fight, src, targets, params)
			local untilTick = Combat.untilTick(fight, number(params, "tauntSeconds"))
			src.reduction = { value = number(params, "damageReduction"), untilTick = untilTick }
			Combat.status(fight, src, "damageReduction", untilTick)
			for _, dst in targets do
				dst.taunt = { value = src.id, untilTick = untilTick }
				Combat.status(fight, dst, "taunt", untilTick)
			end
		end,
	},
	pip_ember_flock = { targets = selfTarget, apply = summon },
	selene_dawn_hymn = {
		targets = allies,
		apply = function(fight, _, targets, params)
			for _, dst in targets do
				Combat.heal(fight, dst, dst.stats.hp * number(params, "healMaxHp"))
			end
		end,
	},
	garrick_thunder_bulwark = {
		targets = selfTarget,
		apply = function(fight, src, _, params)
			Combat.shield(fight, src, number(params, "shieldHp"))
			local untilTick = Combat.untilTick(fight, number(params, "reflectSeconds"))
			src.reflect = { value = number(params, "reflectDamage"), untilTick = untilTick }
			Combat.status(fight, src, "reflect", untilTick)
		end,
	},
	nyx_umbral_step = {
		targets = function(fight, src)
			local targets = enemies(fight, src)
			table.sort(targets, Targeting.byHealth)
			return { targets[1] }
		end,
		apply = function(fight, src, targets, params)
			Combat.move(fight, src, Targeting.leapCell(fight, src, targets[1]), true)
			damageAll(fight, src, targets, params)
		end,
	},
	elodie_archive_blizzard = {
		targets = targetArea,
		apply = function(fight, src, _, params, target)
			table.insert(fight.storms, {
				side = src.side,
				cell = target.cell,
				radius = number(params, "radiusCells"),
				slow = number(params, "slow"),
				untilTick = Combat.untilTick(fight, number(params, "stormSeconds")),
			})
		end,
	},
	ignis_cinder_pounce = {
		targets = function(fight, src)
			local target = Targeting.backline(enemies(fight, src))
			return if target then { target } else {}
		end,
		apply = function(fight, src, targets, params)
			local dst = targets[1]
			Combat.move(fight, src, Targeting.leapCell(fight, src, dst), true)
			Combat.setBurn(fight, src, dst, number(params, "burnHpPerSecond"), number(params, "burnSeconds"))
		end,
	},
	aurelian_lecture_of_light = {
		targets = allies,
		apply = function(fight, _, targets, params)
			local untilTick = Combat.untilTick(fight, number(params, "buffSeconds"))
			for _, dst in targets do
				if params.cleanseDebuffs then
					Combat.cleanse(fight, dst)
				end
				dst.atkBuff = { value = number(params, "atkBonus"), untilTick = untilTick }
				Combat.status(fight, dst, "attackBuff", untilTick)
			end
		end,
	},
	morvaine_hollow_choir = { targets = selfTarget, apply = summon },
	valka_sky_verdict = {
		targets = function(fight, src, target, params)
			local remaining = enemies(fight, src)
			table.remove(remaining, table.find(remaining, target))
			local targets = { target }
			while #remaining > 0 and #targets < number(params, "enemyCount") do
				table.sort(remaining, Targeting.byDistance(target.cell))
				target = table.remove(remaining, 1) :: State.Unit
				table.insert(targets, target)
			end
			return targets
		end,
		apply = damageAll,
	},
	seraphine_dawn = {
		targets = enemies,
		apply = function(fight, src, targets, params)
			local damage = Combat.attackPower(fight, src) * number(params, "damageAtk")
			for _, dst in targets do
				if Combat.damage(fight, src, dst, damage, "skill") then
					stun(fight, dst, number(params, "stunSeconds"))
				end
			end
		end,
	},
	umbra_abyss_mantle = {
		targets = selfTarget,
		apply = function(fight, src, _, params)
			local untilTick = Combat.untilTick(fight, number(params, "invulnerableSeconds"))
			src.invulnerableUntil = untilTick
			local bursts = src.bursts or {}
			table.insert(bursts, untilTick)
			src.bursts = bursts
			Combat.status(fight, src, "invulnerable", untilTick)
		end,
	},
}

function Skills.cast(fight: State.Fight, src: State.Unit, target: State.Unit): ()
	local id = src.def.ultimate
	local skill = assert(skills[id], `Unknown ultimate {id}`)
	local params = Ultimates[id]
	local targets = skill.targets(fight, src, target, params)
	local targetIds: { number } = {}
	for _, dst in targets do
		table.insert(targetIds, dst.id)
	end
	Combat.log(fight, {
		t = fight.tick,
		kind = "ultimate",
		src = src.id,
		skill = id,
		targets = targetIds,
		cinematic = params.cinematic == true,
		cell = target.cell,
	})
	if #targets > 0 then
		skill.apply(fight, src, targets, params, target)
	end
end

function Skills.upkeep(fight: State.Fight, src: State.Unit): ()
	local bursts = src.bursts
	if not bursts then
		return
	end
	local params = Ultimates[src.def.ultimate]
	while bursts[1] and bursts[1] <= fight.tick do
		table.remove(bursts, 1)
		damageAll(fight, src, area(fight, src, src.cell, number(params, "radiusCells")), params)
	end
	if #bursts == 0 then
		src.bursts = nil
	end
end

return table.freeze(Skills)
