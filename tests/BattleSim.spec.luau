--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local BattleSim = require(Shared.BattleSim)
local Constants = require(Shared.Config.Constants)
local Types = require(Shared.Types)
local Units = require(Shared.Config.Units)
local Rng = require(Shared.BattleSim.Rng)
local Stats = require(Shared.BattleSim.Stats)
local SynergyResolver = require(Shared.BattleSim.SynergyResolver)
local TestRunner = require(game:GetService("ServerScriptService").Server.Dev.TestRunner)

local function member(id: string, cell: number, trait: string?, level: number?, stars: number?): Types.BattleUnitInput
	return { unitId = id, cell = cell, trait = trait, level = level or 1, stars = stars or 1 }
end

local function sample(seed: number): Types.BattleInput
	return {
		teamA = {
			member("brutus", 1),
			member("ignis", 2),
			member("pip", 3, "arcane_flow"),
			member("kael", 4),
			member("elodie", 5),
			member("aurelian", 6),
		},
		teamB = {
			member("garrick", 1),
			member("umbra", 2),
			member("dorin", 3),
			member("mira", 4),
			member("nyx", 5),
			member("morvaine", 6),
		},
		seed = seed,
	}
end

return function(t: TestRunner.TestContext): ()
	t.test("repeats the same battle with the same full log and result 100 times", function()
		local input = sample(2026)
		local first = BattleSim.run(input)
		for _ = 1, 100 do
			t.expect(BattleSim.run(input)).toEqual(first)
		end
		t.expect(first.ticks > 0 and #first.log > 12).toBe(true)
	end)

	t.test("uses a reproducible nonzero xorshift32 sequence", function()
		local rng = Rng.new(1)
		t.expect(Rng.nextNumber(rng)).toBe(270369 / 2 ^ 32)
		t.expect(Rng.nextNumber(rng)).toBe(67634689 / 2 ^ 32)
		t.expect(Rng.nextNumber(Rng.new(0)) > 0).toBe(true)
	end)

	t.test("casts all 15 configured ultimates by charging mana from combat", function()
		local fought = 0
		for id, def in Units do
			local result = BattleSim.run({
				teamA = { member(id, 2, "arcane_flow", 25, 2) },
				teamB = { member("brutus", 2, "sturdy", 25, 3) },
				seed = 2026,
			})
			local cast = false
			for _, event in result.log do
				if event.kind == "ultimate" and event.src == 1 and event.skill == def.ultimate then
					cast = true
				end
			end
			assert(cast, `{id} did not use {def.ultimate}`)
			fought += 1
		end
		t.expect(fought).toBe(15)
	end)

	t.test("resolves every element's 2/3 tiers using distinct unit IDs", function()
		local pairsByElement: { [Types.Element]: { string } } = {
			Api = { "kael", "pip", "ignis" },
			Es = { "brutus", "mira", "elodie" },
			Petir = { "garrick", "dorin", "valka" },
			Cahaya = { "selene", "aurelian", "seraphine" },
			Bayangan = { "umbra", "nyx", "morvaine" },
		}
		for element, ids in pairsByElement do
			local units = { member(ids[1], 1), member(ids[1], 2) }
			t.expect(SynergyResolver.resolve(units).elements[element]).toBe(nil)
			units[2] = member(ids[2], 2)
			t.expect(assert(SynergyResolver.resolve(units).elements[element]).count).toBe(2)
			units[3] = member(ids[3], 3)
			t.expect(assert(SynergyResolver.resolve(units).elements[element]).count).toBe(3)
		end
	end)

	t.test("resolves all status thresholds and applies Professor and Lightning bonuses", function()
		local team: { Types.BattleUnitInput } = {}
		local function add(id: string): SynergyResolver.Active
			table.insert(team, member(id, #team + 1))
			return SynergyResolver.resolve(team)
		end
		t.expect(assert(add("aurelian").statuses.Profesor).manaGainBonus).toBe(0.2)
		t.expect(assert(add("seraphine").statuses.Profesor).manaGainBonus).toBe(0.4)
		add("brutus")
		t.expect(assert(add("pip").statuses.Familiar).firstReviveHp).toBe(0.3)
		t.expect(assert(add("ignis").statuses.Familiar).firstReviveHp).toBe(0.5)

		table.clear(team)
		add("dorin")
		t.expect(assert(add("garrick").statuses.Murid).atkAndDefBonus).toBe(0.05)
		add("kael")
		t.expect(assert(add("elodie").statuses.Murid).atkAndDefBonus).toBe(0.08)
		add("nyx")
		local active = add("valka")
		t.expect(assert(active.statuses.Murid).atkAndDefBonus).toBe(0.12)
		local stats = Stats.compute(member("dorin", 1, "swift", 11, 2), active)
		t.expect(stats.range).toBe(1)
		t.expect(math.abs(stats.spd - 1.2 * 1.2 * 1.3 * 1.08 * 1.3) < 1e-9).toBe(true)
	end)

	t.test("uses Archmage on tick 30 and logs summons that expire", function()
		local result = BattleSim.run({
			teamA = { member("pip", 2, "archmage", 15, 2) },
			teamB = { member("brutus", 2, "sturdy", 15, 2) },
			seed = 12,
		})
		local first: number? = nil
		local summoned = 0
		local despawned = 0
		for _, event in result.log do
			if event.kind == "ultimate" and event.src == 1 then
				first = first or event.t
			elseif event.kind == "spawn" and event.owner == 1 and event.t == 30 then
				summoned += 1
			elseif event.kind == "despawn" and event.t == 110 then
				despawned += 1
			end
		end
		t.expect(first).toBe(30)
		t.expect(summoned).toBe(2)
		t.expect(despawned).toBe(2)
	end)

	t.test("logs an assassin leap to the backline and revives each eligible Familiar once", function()
		local result = BattleSim.run({
			teamA = { member("nyx", 2, "archmage", 60, 5) },
			teamB = { member("brutus", 2), member("pip", 8) },
			seed = 19,
		})
		local revived: { [number]: boolean } = {}
		local leapt = false
		for _, event in result.log do
			if event.kind == "move" and event.unit == 1 and event.t == 0 and event.leap then
				leapt = event.cell >= 13
			elseif event.kind == "revive" then
				t.expect(revived[event.unit]).toBe(nil)
				revived[event.unit] = true
			end
		end
		t.expect(leapt).toBe(true)
		t.expect(revived[2]).toBe(true)
		t.expect(revived[3]).toBe(true)
		t.expect(result.winner).toBe("A")
	end)

	t.test("returns a draw at the tick cap and resolves an empty opposing team immediately", function()
		local input = sample(0)
		input.maxTicks = 1
		local short = BattleSim.run(input)
		t.expect(short.ticks).toBe(1)
		t.expect(short.winner).toBe("draw")
		input.teamB = {}
		local empty = BattleSim.run(input)
		t.expect(empty.ticks).toBe(0)
		t.expect(empty.winner).toBe("A")
	end)

	t.test("replays unit life and HP from chronological events", function()
		local result = BattleSim.run(sample(15))
		local hp: { [number]: number } = {}
		local lastTick = 0
		for _, event in result.log do
			t.expect(event.t >= lastTick and event.t <= result.ticks).toBe(true)
			lastTick = event.t
			if event.kind == "spawn" then
				t.expect(hp[event.unit]).toBe(nil)
				hp[event.unit] = event.hp
			elseif event.kind == "attack" or event.kind == "damage" then
				assert(hp[event.src] and hp[event.dst], "Damage references an unknown unit")
				hp[event.dst] = event.hp
			elseif event.kind == "heal" or event.kind == "revive" then
				hp[event.unit] = event.hp
			elseif event.kind == "death" or event.kind == "despawn" then
				hp[event.unit] = 0
			end
		end
		for _, survivor in result.survivors do
			t.expect(hp[survivor.id]).toBe(survivor.hp)
			hp[survivor.id] = 0
		end
		for _, remaining in hp do
			t.expect(remaining).toBe(0)
		end
	end)

	t.test("runs a 6 vs 6 simulation in less than 50 ms", function()
		local input = sample(711)
		local started = os.clock()
		local result = BattleSim.run(input)
		local elapsed = os.clock() - started
		print(
			string.format(
				"[BattleSim] winner=%s ticks=%d events=%d elapsed=%.2f ms",
				result.winner,
				result.ticks,
				#result.log,
				elapsed * 1000
			)
		)
		t.expect(result.ticks <= Constants.BATTLE_TICKS_PER_SECOND * Constants.BATTLE_MAX_SECONDS).toBe(true)
		assert(elapsed < 0.05, string.format("BattleSim took %.2f ms", elapsed * 1000))
	end)
end
