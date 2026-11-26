--!strict
-- Test murni reroll trait (prompts/08-traits.md): roll & odds dari Config/Traits, pity global 100,
-- serta audit hook trait di BattleSim/Stats. Alur handler & transaksi ada di TraitFlow.spec.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local Roll = require(Services.TraitService.Roll)
local Odds = require(Services.TraitService.Odds)
local Shared = ReplicatedStorage.Shared
local TraitConfig = require(Shared.Config.Traits)
local Constants = require(Shared.Config.Constants)
local BattleRng = require(Shared.BattleSim.Rng)
local Stats = require(Shared.BattleSim.Stats)

local EPSILON = 1e-9
local PITY = TraitConfig.pity.rolls

local function seeded(seed: number): Roll.Rng
	local rngState = BattleRng.new(seed)
	return {
		NextNumber = function(): number
			return BattleRng.nextNumber(rngState)
		end,
	}
end

local function near(t: TestRunner.TestContext, actual: number, expected: number, tolerance: number, label: string)
	if math.abs(actual - expected) > tolerance then
		error(`{label}: expected {expected} ± {tolerance}, got {actual}`, 2)
	end
	t.expect(true).toBe(true)
end

local function tierOdds(odds: any, tier: string): any
	for _, entry in odds.tiers do
		if entry.tier == tier then
			return entry
		end
	end
	error(`tier {tier} missing`)
end

local function traitPercent(odds: any, id: string): number
	for _, tier in odds.tiers do
		for _, trait in tier.traits do
			if trait.id == id then
				return trait.percent
			end
		end
	end
	error(`trait {id} missing`)
end

return function(t: TestRunner.TestContext): ()
	t.test("base odds per tier and per trait come from Config/Traits and total 100", function()
		local odds = Odds.base()
		t.expect(#odds.tiers).toBe(5)
		local total = 0
		for _, tier in odds.tiers do
			local def = TraitConfig.tiers[tier.tier]
			near(t, tier.percent, def.oddsPercent, EPSILON, `tier {tier.tier}`)
			t.expect(#tier.traits).toBe(#def.traits)
			for index, trait in tier.traits do
				t.expect(trait.id).toBe(def.traits[index].id)
				t.expect(trait.name).toBe(def.traits[index].name)
				near(t, trait.percent, def.oddsPercent / #def.traits, EPSILON, `trait {trait.id}`)
				total += trait.percent
			end
		end
		near(t, total, 100, EPSILON, "base total")
		near(t, traitPercent(odds, "swift"), 20, EPSILON, "swift")
		near(t, traitPercent(odds, "echo"), 0.7, EPSILON, "echo")
		near(t, traitPercent(odds, "archmage"), 0.1, EPSILON, "archmage")
	end)

	t.test("pity odds list every outcome, Legendary exactly 100% and the rest 0%", function()
		near(t, tierOdds(Odds.next(PITY - 2), "Common").percent, 60, EPSILON, "roll 99 unchanged")
		local odds = Odds.next(PITY - 1)
		t.expect(#odds.tiers).toBe(5)
		for _, tier in odds.tiers do
			t.expect(#tier.traits).toBe(#TraitConfig.tiers[tier.tier].traits)
			local expected = if tier.tier == "Legendary" then 100 else 0
			near(t, tier.percent, expected, EPSILON, `pity tier {tier.tier}`)
		end
		near(t, traitPercent(odds, "prodigy"), 50, EPSILON, "pity prodigy")
		near(t, traitPercent(odds, "echo"), 50, EPSILON, "pity echo")
		t.expect(traitPercent(odds, "archmage")).toBe(0)
		t.expect(traitPercent(odds, "swift")).toBe(0)
		-- Counter rusak/berlebih tetap memaksa Legendary.
		near(t, tierOdds(Odds.next(PITY + 5), "Legendary").percent, 100, EPSILON, "over pity")
	end)

	t.test("1,000,000 seeded base rerolls stay within 0.05 percentage points", function()
		local rng = seeded(20261126)
		local tierCounts: { [string]: number } = {}
		local traitCounts: { [string]: number } = {}
		local total = 1000000
		for _ = 1, total do
			local entry = Roll.pick(Roll.baseDistribution(), rng:NextNumber())
			tierCounts[entry.tier] = (tierCounts[entry.tier] or 0) + 1
			traitCounts[entry.id] = (traitCounts[entry.id] or 0) + 1
		end
		for tier, def in TraitConfig.tiers do
			near(t, (tierCounts[tier] or 0) / total * 100, def.oddsPercent, 0.05, `1M tier {tier}`)
			for _, trait in def.traits do
				local expected = def.oddsPercent / #def.traits
				near(t, (traitCounts[trait.id] or 0) / total * 100, expected, 0.05, `1M trait {trait.id}`)
			end
		end
	end)

	t.test("pity 99 → 100 forces exactly Legendary and resets on Legendary/Mythic", function()
		for _, u in { 0, 0.5, 0.999999 } do
			local draw, nextPity = Roll.reroll(PITY - 1, {
				NextNumber = function(): number
					return u
				end,
			})
			t.expect(draw.tier).toBe("Legendary")
			t.expect(nextPity).toBe(0)
		end
		local top = {
			NextNumber = function(): number
				return 0.999999
			end,
		}
		local mythic, afterMythic = Roll.reroll(10, top)
		t.expect(mythic.traitId).toBe("archmage")
		t.expect(afterMythic).toBe(0)
		t.expect(Roll.advance(98, "Epic")).toBe(99)
		t.expect(Roll.advance(98, "Legendary")).toBe(0)
		-- 99 reroll Common berturut-turut → counter 99 → reroll ke-100 Legendary → 0.
		local low = {
			NextNumber = function(): number
				return 0
			end,
		}
		local counter = 0
		for _ = 1, PITY - 1 do
			local draw
			draw, counter = Roll.reroll(counter, low)
			t.expect(draw.tier).toBe("Common")
		end
		t.expect(counter).toBe(PITY - 1)
		local forced
		forced, counter = Roll.reroll(counter, low)
		t.expect(forced.traitId).toBe("prodigy")
		t.expect(counter).toBe(0)
	end)

	t.test("every configured trait maps onto a BattleSim stat hook", function()
		local active: any = { elements = {}, statuses = {} }
		local function compute(trait: string?): any
			return Stats.compute({ unitId = "kael", cell = 1, trait = trait, level = 1, stars = 1 } :: any, active)
		end
		local plain = compute(nil)
		for _, tier in TraitConfig.tiers do
			for _, trait in tier.traits do
				local stats = compute(trait.id)
				local all = 1 + (trait.allStatsBonus or 0)
				near(t, stats.hp, plain.hp * all * (1 + (trait.hpBonus or 0)), EPSILON, `{trait.id} hp`)
				near(t, stats.atk, plain.atk * all * (1 + (trait.atkBonus or 0)), EPSILON, `{trait.id} atk`)
				near(t, stats.def, plain.def * all * (1 + (trait.defBonus or 0)), EPSILON, `{trait.id} def`)
				near(t, stats.spd, plain.spd * all * (1 + (trait.spdBonus or 0)), EPSILON, `{trait.id} spd`)
				near(t, stats.critChance, plain.critChance + (trait.critChanceBonus or 0), EPSILON, `{trait.id} crit`)
				near(t, stats.manaGain, plain.manaGain * (1 + (trait.manaGainBonus or 0)), EPSILON, `{trait.id} mana`)
				t.expect(stats.startingMana).toBe(trait.startingMana or 0)
				t.expect(stats.lifesteal).toBe(trait.lifesteal or 0)
				t.expect(stats.echoChance).toBe(trait.repeatUltimateChance or 0)
				local freeSeconds = trait.freeFirstUltimateAtSeconds
				local expectedTick = if freeSeconds
					then math.round(freeSeconds * Constants.BATTLE_TICKS_PER_SECOND)
					else nil
				t.expect(stats.freeUltimateTick).toBe(expectedTick)
			end
		end
		t.expect(compute("echo").echoChance).toBe(0.2)
		t.expect(compute("archmage").freeUltimateTick).toBe(30)
	end)
end
