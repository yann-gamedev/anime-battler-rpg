--!strict
-- Test reroll trait (prompts/08-traits.md): roll & odds murni dari Config/Traits, pity global 100,
-- handler remote dengan sesi palsu + ledger DataService asli (restricted, quote, kepemilikan, locked,
-- saldo, rollback), serta audit hook trait di BattleSim/Stats.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local Roll = require(Services.TraitService.Roll)
local Odds = require(Services.TraitService.Odds)
local Handlers = require(Services.TraitService.Handlers)
local Traits = require(Services.DataService.Traits)
local Template = require(Services.DataService.Template)
local Shared = ReplicatedStorage.Shared
local TraitConfig = require(Shared.Config.Traits)
local Economy = require(Shared.Config.Economy)
local Constants = require(Shared.Config.Constants)
local Signal = require(Shared.Util.Signal)
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

local function fakePlayer(userId: number): any
	return { UserId = userId, Name = `Tester{userId}` }
end

local function newUnit(uid: string, trait: string?, locked: boolean?): any
	return {
		uid = uid,
		unitId = "kael",
		stars = 1,
		level = 1,
		xp = 0,
		trait = trait,
		locked = locked == true,
		obtainedAt = 0,
		source = "story",
	}
end

-- Dunia uji: sesi palsu + ledger DataService asli + handler asli.
local function world(options: { restricted: boolean?, u: number? }?)
	local sessions: { [any]: { Data: any } } = {}
	local present: { [any]: boolean } = {}
	local policy = { restricted = if options then options.restricted == true else false, calls = 0 }
	local rng = { u = if options and options.u then options.u else 0 }
	local ledger = Traits.create(function(player: Player): any
		return sessions[player]
	end, Signal.new())
	local handlers = Handlers.create({
		ledger = ledger :: any,
		isRestricted = function(): boolean
			policy.calls += 1
			return policy.restricted
		end,
		isPresent = function(player: Player): boolean
			return present[player] == true
		end,
		rng = {
			NextNumber = function(): number
				return rng.u
			end,
		},
	})
	local function join(userId: number, shards: number?): any
		local player = fakePlayer(userId)
		local profile = Template.create(0)
		profile.currencies.TraitShards = shards or 0
		profile.units["u1"] = newUnit("u1", nil, false)
		profile.units["u2"] = newUnit("u2", "swift", false)
		profile.units["locked"] = newUnit("locked", "prodigy", true)
		sessions[player] = { Data = profile }
		present[player] = true
		return player
	end
	return { sessions = sessions, present = present, policy = policy, rng = rng, handlers = handlers, join = join }
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

	t.test("validates RerollTrait/GetTraitInfo arguments", function()
		local check = Handlers.validateUidArgs
		t.expect(check(1, "u1")).toBe(nil)
		t.expect(check(0, nil)).toBe("INVALID_ARGUMENTS")
		t.expect(check(2, "u1")).toBe("INVALID_ARGUMENTS")
		for _, uid in { nil, 1, "", string.rep("a", Constants.MAX_UID_LENGTH + 1), {}, true } :: { any } do
			t.expect(check(1, uid)).toBe("INVALID_ARGUMENTS")
		end
		local w = world()
		local player = w.join(1, 5)
		t.expect(w.handlers.rerollTrait(player).code).toBe("INVALID_ARGUMENTS")
		t.expect(w.handlers.getTraitInfo(player, "u1", "extra").code).toBe("INVALID_ARGUMENTS")
		t.expect(w.policy.calls).toBe(0)
	end)

	t.test("GetTraitInfo returns the TraitInfo contract with live odds and pity", function()
		local w = world()
		local player = w.join(1, 3)
		w.sessions[player].Data.traitPity = PITY - 1
		local result = w.handlers.getTraitInfo(player, "u2")
		t.expect(result.ok).toBe(true)
		local info = result.data
		t.expect(info.uid).toBe("u2")
		t.expect(info.traitId).toBe("swift")
		t.expect(info.locked).toBe(false)
		t.expect(info.restricted).toBe(false)
		t.expect(info.shards).toBe(3)
		t.expect(info.cost).toBe(Economy.traitShardsPerReroll)
		t.expect(info.pity.sinceLegendary).toBe(PITY - 1)
		t.expect(info.pity.rolls).toBe(PITY)
		near(t, tierOdds(info.odds, "Legendary").percent, 100, EPSILON, "info pity odds")
		t.expect(w.handlers.getTraitInfo(player, "missing").code).toBe("UNIT_NOT_OWNED")
		t.expect(w.handlers.getTraitInfo(fakePlayer(9), "u1").code).toBe("DATA_NOT_READY")
	end)

	t.test("reroll spends one shard, replaces the trait and stores pity in one commit", function()
		local w = world({ u = 0 })
		local player = w.join(1, 2)
		t.expect(w.handlers.getTraitInfo(player, "u1").ok).toBe(true)
		local result = w.handlers.rerollTrait(player, "u1")
		t.expect(result.ok).toBe(true)
		local profile = w.sessions[player].Data
		t.expect(profile.currencies.TraitShards).toBe(2 - Economy.traitShardsPerReroll)
		t.expect(profile.units.u1.trait).toBe("swift")
		t.expect(profile.traitPity).toBe(1)
		t.expect(result.data.snapshot.units.u1.trait).toBe("swift")
		t.expect(result.data.snapshot.currencies.TraitShards).toBe(1)
		t.expect(result.data.info.pity.sinceLegendary).toBe(1)
		-- Respons sukses menerbitkan quote baru: reroll berikutnya tanpa GetTraitInfo diterima.
		t.expect(w.handlers.rerollTrait(player, "u1").ok).toBe(true)
		-- Commit menukar draft: baca profil terbaru dari sesi.
		t.expect(w.sessions[player].Data.currencies.TraitShards).toBe(0)
		t.expect(w.sessions[player].Data.traitPity).toBe(2)
	end)

	t.test("ledger pity reaches 99, the 100th reroll is Legendary and resets", function()
		local w = world({ u = 0 })
		local player = w.join(1, PITY + 1)
		w.sessions[player].Data.traitPity = PITY - 2
		t.expect(w.handlers.getTraitInfo(player, "u1").ok).toBe(true)
		t.expect(w.handlers.rerollTrait(player, "u1").data.info.pity.sinceLegendary).toBe(PITY - 1)
		local forced = w.handlers.rerollTrait(player, "u1")
		t.expect(forced.ok).toBe(true)
		t.expect(Roll.tierOf(w.sessions[player].Data.units.u1.trait)).toBe("Legendary")
		t.expect(w.sessions[player].Data.traitPity).toBe(0)
		-- Pity global: unit lain melanjutkan counter yang sama.
		t.expect(w.handlers.getTraitInfo(player, "u2").data.pity.sinceLegendary).toBe(0)
	end)

	t.test("restricted players are blocked server-side without spending", function()
		local w = world({ restricted = true })
		local player = w.join(1, 5)
		local info = w.handlers.getTraitInfo(player, "u1")
		t.expect(info.ok).toBe(true)
		t.expect(info.data.restricted).toBe(true)
		t.expect(w.handlers.rerollTrait(player, "u1").code).toBe("RESTRICTED_REGION")
		t.expect(w.sessions[player].Data.currencies.TraitShards).toBe(5)
		t.expect(w.sessions[player].Data.units.u1.trait).toBe(nil)
		-- Quote tidak diterbitkan selama restricted: setelah status berubah, odds harus diambil ulang.
		w.policy.restricted = false
		t.expect(w.handlers.rerollTrait(player, "u1").code).toBe("ODDS_CHANGED")
		t.expect(w.sessions[player].Data.currencies.TraitShards).toBe(5)
		-- Pemain keluar saat lookup kebijakan → tidak ada commit.
		t.expect(w.handlers.getTraitInfo(player, "u1").ok).toBe(true)
		w.present[player] = nil
		t.expect(w.handlers.rerollTrait(player, "u1").code).toBe("DATA_NOT_READY")
		t.expect(w.sessions[player].Data.currencies.TraitShards).toBe(5)
	end)

	t.test("stale quotes are rejected with ODDS_CHANGED and never retried", function()
		local w = world({ u = 0 })
		local player = w.join(1, 10)
		t.expect(w.handlers.rerollTrait(player, "u1").code).toBe("ODDS_CHANGED")
		t.expect(w.handlers.getTraitInfo(player, "u1").ok).toBe(true)
		t.expect(w.handlers.getTraitInfo(player, "u2").ok).toBe(true)
		-- Reroll u2 mengubah pity global → quote u1 basi.
		t.expect(w.handlers.rerollTrait(player, "u2").ok).toBe(true)
		local profile = w.sessions[player].Data
		local shards, pity = profile.currencies.TraitShards, profile.traitPity
		t.expect(w.handlers.rerollTrait(player, "u1").code).toBe("ODDS_CHANGED")
		t.expect(profile.currencies.TraitShards).toBe(shards)
		t.expect(profile.traitPity).toBe(pity)
		t.expect(profile.units.u1.trait).toBe(nil)
		-- Trait berubah di luar quote (mis. sesi lain) → basi.
		t.expect(w.handlers.getTraitInfo(player, "u1").ok).toBe(true)
		profile.units.u1 = newUnit("u1", "keen", false)
		t.expect(w.handlers.rerollTrait(player, "u1").code).toBe("ODDS_CHANGED")
		-- Hanya issuance terbaru yang berlaku; issuance ulang dengan state sama tetap sah.
		t.expect(w.handlers.getTraitInfo(player, "u1").ok).toBe(true)
		t.expect(w.handlers.getTraitInfo(player, "u1").ok).toBe(true)
		t.expect(w.handlers.rerollTrait(player, "u1").ok).toBe(true)
		-- Quote per pemain: quote pemain lain tidak berlaku.
		local other = w.join(2, 10)
		t.expect(w.handlers.rerollTrait(other, "u1").code).toBe("ODDS_CHANGED")
		w.handlers.clear(player)
		t.expect(w.handlers.rerollTrait(player, "u1").code).toBe("ODDS_CHANGED")
	end)

	t.test("rejects units not owned, locked units and missing shards without spending", function()
		local w = world()
		local owner = w.join(1, 5)
		local other = w.join(2, 5)
		w.sessions[other].Data.units["foreign"] = newUnit("foreign", nil, false)
		t.expect(w.handlers.rerollTrait(owner, "foreign").code).toBe("UNIT_NOT_OWNED")
		t.expect(w.handlers.getTraitInfo(owner, "foreign").code).toBe("UNIT_NOT_OWNED")
		t.expect(w.handlers.getTraitInfo(owner, "locked").data.locked).toBe(true)
		t.expect(w.handlers.rerollTrait(owner, "locked").code).toBe("UNIT_LOCKED")
		t.expect(w.sessions[owner].Data.units.locked.trait).toBe("prodigy")
		-- Unit dihapus setelah quote → bukan milik lagi.
		t.expect(w.handlers.getTraitInfo(owner, "u2").ok).toBe(true)
		w.sessions[owner].Data.units.u2 = nil
		t.expect(w.handlers.rerollTrait(owner, "u2").code).toBe("UNIT_NOT_OWNED")
		local broke = w.join(3, 0)
		t.expect(w.handlers.getTraitInfo(broke, "u1").ok).toBe(true)
		t.expect(w.handlers.rerollTrait(broke, "u1").code).toBe("NOT_ENOUGH_TRAIT_SHARDS")
		for _, bad in { -1, 0.5, 0 / 0, math.huge, "5" } :: { any } do
			w.sessions[broke].Data.currencies.TraitShards = bad
			t.expect(w.handlers.rerollTrait(broke, "u1").code).toBe("NOT_ENOUGH_TRAIT_SHARDS")
		end
		t.expect(w.sessions[broke].Data.units.u1.trait).toBe(nil)
		t.expect(w.sessions[owner].Data.currencies.TraitShards).toBe(5)
	end)

	t.test("commit rolls back on roll errors, invalid results, yields and lost sessions", function()
		local sessions: { [any]: any } = {}
		local ledger = Traits.create(function(player: Player): any
			return sessions[player]
		end, Signal.new())
		local player = fakePlayer(1)
		local profile = Template.create(0)
		profile.currencies.TraitShards = 3
		profile.units.u1 = newUnit("u1", "swift", false)
		profile.traitPity = 7
		sessions[player] = { Data = profile }
		local function apply(target: any, value: any): string?
			local code = ledger.apply(target, value)
			return code
		end
		local function request(roll: any, precheck: any?): any
			return {
				uid = "u1",
				cost = 1,
				precheck = precheck or function(): string?
					return nil
				end,
				roll = roll,
			}
		end
		local function unchanged()
			local data = sessions[player].Data
			t.expect(data).toBe(profile)
			t.expect(data.currencies.TraitShards).toBe(3)
			t.expect(data.units.u1.trait).toBe("swift")
			t.expect(data.traitPity).toBe(7)
		end
		t.expect(apply(
			player,
			request(function()
				error("boom")
			end)
		)).toBe("INTERNAL_ERROR")
		unchanged()
		t.expect(apply(
			player,
			request(function()
				return { traitId = "prodigy", tier = "Common" }, 0
			end)
		)).toBe("INTERNAL_ERROR")
		unchanged()
		t.expect(apply(
			player,
			request(function()
				return { traitId = "unknown", tier = "Common" }, 8
			end)
		)).toBe("INTERNAL_ERROR")
		unchanged()
		t.expect(apply(
			player,
			request(function()
				return { traitId = "swift", tier = "Common" }, -1
			end)
		)).toBe("INTERNAL_ERROR")
		unchanged()
		t.expect(apply(
			player,
			request(function()
				return { traitId = "swift", tier = "Common" }, 8
			end, function(): string?
				coroutine.yield()
				return nil
			end)
		)).toBe("INTERNAL_ERROR")
		unchanged()
		-- Sesi diganti selama mutasi → DATA_NOT_READY, profil asli tidak tersentuh.
		t.expect(apply(
			player,
			request(function()
				sessions[player] = { Data = profile }
				return { traitId = "sharp", tier = "Common" }, 8
			end)
		)).toBe("DATA_NOT_READY")
		unchanged()
		t.expect(apply(player, { uid = "u1", cost = 0 } :: any)).toBe("INVALID_REQUEST")
		t.expect(apply(fakePlayer(2), request(function() end))).toBe("DATA_NOT_READY")
		unchanged()
		-- Sukses: draft menggantikan profil sekaligus.
		local code, result = ledger.apply(
			player,
			request(function()
				return { traitId = "echo", tier = "Legendary" }, 0
			end)
		)
		t.expect(code).toBe(nil)
		t.expect((result :: any).previousTraitId).toBe("swift")
		local committed = sessions[player].Data
		t.expect(committed ~= profile).toBe(true)
		t.expect(committed.units.u1.trait).toBe("echo")
		t.expect(committed.traitPity).toBe(0)
		t.expect(committed.currencies.TraitShards).toBe(2)
		t.expect(profile.units.u1.trait).toBe("swift")
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
