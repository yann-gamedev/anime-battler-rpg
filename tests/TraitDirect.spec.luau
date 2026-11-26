--!strict
-- Test pilihan trait langsung dengan Gold untuk pemain restricted (D-OPEN-1, SelectRestrictedTrait):
-- sukses, saldo/locked/kepemilikan, eligibility tier & kebijakan, preview basi/race, pity & Shards tetap,
-- serta rollback transaksi. Sesi palsu + ledger DataService asli + handler asli.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local Handlers = require(Services.TraitService.Handlers)
local Traits = require(Services.DataService.Traits)
local Template = require(Services.DataService.Template)
local Shared = ReplicatedStorage.Shared
local TraitConfig = require(Shared.Config.Traits)
local Signal = require(Shared.Util.Signal)

local COMMON_COST = TraitConfig.direct.goldCost.Common
local UNCOMMON_COST = TraitConfig.direct.goldCost.Uncommon

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

local function world()
	local sessions: { [any]: { Data: any } } = {}
	local present: { [any]: boolean } = {}
	local policy = { restricted = true, suspend = false, calls = 0 }
	local ledger = Traits.create(function(player: Player): any
		return sessions[player]
	end, Signal.new())
	local handlers = Handlers.create({
		ledger = ledger :: any,
		isRestricted = function(): boolean
			policy.calls += 1
			if policy.suspend then
				coroutine.yield()
			end
			return policy.restricted
		end,
		isPresent = function(player: Player): boolean
			return present[player] == true
		end,
		rng = {
			NextNumber = function(): number
				return 0
			end,
		},
	})
	local function join(userId: number, gold: number?): any
		local player = fakePlayer(userId)
		local profile = Template.create(0)
		profile.currencies.Gold = gold or 0
		profile.currencies.TraitShards = 4
		profile.traitPity = 37
		profile.units["u1"] = newUnit("u1", nil, false)
		profile.units["u2"] = newUnit("u2", "swift", false)
		profile.units["locked"] = newUnit("locked", nil, true)
		sessions[player] = { Data = profile }
		present[player] = true
		return player
	end
	local function data(player: any): any
		return sessions[player].Data
	end
	return {
		sessions = sessions,
		present = present,
		policy = policy,
		ledger = ledger,
		h = handlers,
		join = join,
		data = data,
	}
end

return function(t: TestRunner.TestContext): ()
	t.test("restricted GetTraitInfo adds direct Gold options from Config/Traits only", function()
		local w = world()
		local player = w.join(1, 750)
		local info = w.h.getTraitInfo(player, "u1").data
		t.expect(info.restricted).toBe(true)
		t.expect(info.direct.gold).toBe(750)
		local expected = #TraitConfig.tiers.Common.traits + #TraitConfig.tiers.Uncommon.traits
		t.expect(#info.direct.options).toBe(expected)
		for _, option in info.direct.options do
			t.expect(option.tier == "Common" or option.tier == "Uncommon").toBe(true)
			t.expect(option.cost).toBe(TraitConfig.direct.goldCost[option.tier])
		end
		t.expect(info.direct.options[1].id).toBe(TraitConfig.tiers.Common.traits[1].id)
		-- Field lama tetap ada.
		t.expect(info.pity.sinceLegendary).toBe(37)
		t.expect(#info.odds.tiers).toBe(5)
		w.policy.restricted = false
		t.expect(w.h.getTraitInfo(player, "u1").data.direct).toBe(nil)
	end)

	t.test("eligibility: only Common/Uncommon traits and only restricted players", function()
		local check = Handlers.validateSelectArgs
		t.expect(check(2, "u1", "swift")).toBe(nil)
		t.expect(check(2, "u1", "keen")).toBe(nil)
		for _, traitId in { "arcane_flow", "prodigy", "echo", "archmage", "unknown", "", string.rep("s", 200) } do
			t.expect(check(2, "u1", traitId)).toBe("INVALID_TRAIT")
		end
		for _, args in { { 1, "u1", "swift" }, { 3, "u1", "swift" }, { 2, "", "swift" }, { 2, "u1", 5 } } :: { any } do
			t.expect(check(args[1], args[2], args[3])).toBe("INVALID_ARGUMENTS")
		end
		local w = world()
		local player = w.join(1, 5000)
		t.expect(w.h.selectRestrictedTrait(player, "u1", "prodigy").code).toBe("INVALID_TRAIT")
		t.expect(w.h.selectRestrictedTrait(player, "u1").code).toBe("INVALID_ARGUMENTS")
		t.expect(w.policy.calls).toBe(0)
		t.expect(w.h.getTraitInfo(player, "u1").ok).toBe(true)
		w.policy.restricted = false
		t.expect(w.h.selectRestrictedTrait(player, "u1", "swift").code).toBe("RESTRICTED_ONLY")
		t.expect(w.data(player).currencies.Gold).toBe(5000)
		-- Reroll Shards tetap diblok bagi restricted.
		w.policy.restricted = true
		t.expect(w.h.rerollTrait(player, "u1").code).toBe("RESTRICTED_REGION")
		-- Ledger menolak tier lain walau handler dilewati.
		local code = w.ledger.applyDirect(player, {
			uid = "u1",
			traitId = "prodigy",
			precheck = function(): string?
				return nil
			end,
		})
		t.expect(code).toBe("INVALID_TRAIT")
		t.expect(w.data(player).units.u1.trait).toBe(nil)
	end)

	t.test("direct Gold selection sets the exact trait and keeps pity, Shards and other units", function()
		local w = world()
		local player = w.join(1, 1000)
		t.expect(w.h.getTraitInfo(player, "u1").ok).toBe(true)
		local result = w.h.selectRestrictedTrait(player, "u1", "guardian")
		t.expect(result.ok).toBe(true)
		local profile = w.data(player)
		t.expect(profile.units.u1.trait).toBe("guardian")
		t.expect(profile.currencies.Gold).toBe(1000 - UNCOMMON_COST)
		t.expect(profile.currencies.TraitShards).toBe(4)
		t.expect(profile.traitPity).toBe(37)
		t.expect(profile.units.u2.trait).toBe("swift")
		t.expect(result.data.snapshot.units.u1.trait).toBe("guardian")
		t.expect(result.data.snapshot.currencies.Gold).toBe(1000 - UNCOMMON_COST)
		t.expect(result.data.info.traitId).toBe("guardian")
		t.expect(result.data.info.direct.gold).toBe(1000 - UNCOMMON_COST)
		-- Respons menerbitkan preview baru; trait sama tidak dibeli ulang.
		t.expect(w.h.selectRestrictedTrait(player, "u1", "guardian").code).toBe("TRAIT_ALREADY_SET")
		t.expect(w.data(player).currencies.Gold).toBe(1000 - UNCOMMON_COST)
		-- Mengganti trait lama (dikonfirmasi lewat preview terbaru) dengan Common.
		t.expect(w.h.selectRestrictedTrait(player, "u1", "sharp").ok).toBe(true)
		t.expect(w.data(player).currencies.Gold).toBe(1000 - UNCOMMON_COST - COMMON_COST)
		t.expect(w.data(player).traitPity).toBe(37)
	end)

	t.test("rejects missing Gold, locked units and units not owned without spending", function()
		local w = world()
		local player = w.join(1, COMMON_COST - 1)
		local other = w.join(2, 9999)
		w.data(other).units["foreign"] = newUnit("foreign", nil, false)
		t.expect(w.h.getTraitInfo(player, "u1").ok).toBe(true)
		t.expect(w.h.selectRestrictedTrait(player, "u1", "swift").code).toBe("NOT_ENOUGH_GOLD")
		for _, bad in { -1, 0.5, 0 / 0, math.huge, "999" } :: { any } do
			w.data(player).currencies.Gold = bad
			t.expect(w.h.selectRestrictedTrait(player, "u1", "swift").code).toBe("NOT_ENOUGH_GOLD")
		end
		w.data(player).currencies.Gold = 5000
		t.expect(w.h.getTraitInfo(player, "locked").data.locked).toBe(true)
		t.expect(w.h.selectRestrictedTrait(player, "locked", "swift").code).toBe("UNIT_LOCKED")
		t.expect(w.h.selectRestrictedTrait(player, "foreign", "swift").code).toBe("UNIT_NOT_OWNED")
		t.expect(w.h.selectRestrictedTrait(player, "missing", "swift").code).toBe("UNIT_NOT_OWNED")
		t.expect(w.h.selectRestrictedTrait(fakePlayer(9), "u1", "swift").code).toBe("DATA_NOT_READY")
		-- Unit dihapus setelah preview → bukan milik lagi.
		t.expect(w.h.getTraitInfo(player, "u2").ok).toBe(true)
		w.data(player).units.u2 = nil
		t.expect(w.h.selectRestrictedTrait(player, "u2", "swift").code).toBe("UNIT_NOT_OWNED")
		t.expect(w.data(player).currencies.Gold).toBe(5000)
		t.expect(w.data(player).units.locked.trait).toBe(nil)
		t.expect(w.data(other).units.foreign.trait).toBe(nil)
	end)

	t.test("stale previews return TRAIT_CHANGED and racing selections spend once", function()
		local w = world()
		local player = w.join(1, 5000)
		t.expect(w.h.selectRestrictedTrait(player, "u2", "sharp").code).toBe("TRAIT_CHANGED")
		t.expect(w.h.getTraitInfo(player, "u2").ok).toBe(true)
		w.data(player).units.u2 = newUnit("u2", "keen", false)
		t.expect(w.h.selectRestrictedTrait(player, "u2", "sharp").code).toBe("TRAIT_CHANGED")
		t.expect(w.data(player).currencies.Gold).toBe(5000)
		-- Preview dari masa tidak restricted tidak ada: quote reroll tidak berlaku di jalur ini.
		w.policy.restricted = false
		t.expect(w.h.getTraitInfo(player, "u1").ok).toBe(true)
		w.policy.restricted = true
		t.expect(w.h.selectRestrictedTrait(player, "u1", "swift").code).toBe("TRAIT_CHANGED")
		-- Pemain keluar saat lookup kebijakan → tidak ada commit.
		t.expect(w.h.getTraitInfo(player, "u1").ok).toBe(true)
		w.present[player] = nil
		t.expect(w.h.selectRestrictedTrait(player, "u1", "swift").code).toBe("DATA_NOT_READY")
		w.present[player] = true
		-- Dua permintaan bersamaan dengan preview yang sama: hanya satu yang dibayar.
		t.expect(w.h.getTraitInfo(player, "u1").ok).toBe(true)
		w.policy.suspend = true
		local first = coroutine.create(w.h.selectRestrictedTrait)
		local second = coroutine.create(w.h.selectRestrictedTrait)
		coroutine.resume(first, player, "u1", "swift")
		coroutine.resume(second, player, "u1", "sturdy")
		w.policy.suspend = false
		local _, a = coroutine.resume(first)
		local _, b = coroutine.resume(second)
		t.expect(a.ok).toBe(true)
		t.expect(b.code).toBe("TRAIT_CHANGED")
		t.expect(w.data(player).units.u1.trait).toBe("swift")
		t.expect(w.data(player).currencies.Gold).toBe(5000 - COMMON_COST)
		-- Preview per pemain dan dibuang saat keluar.
		w.h.clear(player)
		t.expect(w.h.selectRestrictedTrait(player, "u1", "sturdy").code).toBe("TRAIT_CHANGED")
		t.expect(w.data(player).currencies.TraitShards).toBe(4)
		t.expect(w.data(player).traitPity).toBe(37)
	end)

	t.test("direct commit rolls back on precheck errors, yields and lost sessions", function()
		local w = world()
		local player = w.join(1, 1000)
		local original = w.data(player)
		local function attempt(precheck: any): string?
			local code = w.ledger.applyDirect(player, { uid = "u2", traitId = "keen", precheck = precheck })
			return code
		end
		t.expect(attempt(function()
			error("boom")
		end)).toBe("INTERNAL_ERROR")
		t.expect(attempt(function(): string?
			coroutine.yield()
			return nil
		end)).toBe("INTERNAL_ERROR")
		t.expect(attempt(function(): string?
			w.sessions[player] = { Data = original }
			return nil
		end)).toBe("DATA_NOT_READY")
		t.expect((w.ledger.applyDirect(player, { uid = "u2", traitId = "keen" } :: any))).toBe("INVALID_REQUEST")
		t.expect(w.data(player)).toBe(original)
		t.expect(original.currencies.Gold).toBe(1000)
		t.expect(original.units.u2.trait).toBe("swift")
		t.expect(attempt(function(): string?
			return nil
		end)).toBe(nil)
		t.expect(w.data(player) ~= original).toBe(true)
		t.expect(w.data(player).units.u2.trait).toBe("keen")
		t.expect(w.data(player).currencies.Gold).toBe(1000 - UNCOMMON_COST)
		t.expect(original.units.u2.trait).toBe("swift")
	end)
end
