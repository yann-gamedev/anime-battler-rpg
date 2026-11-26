--!strict
-- Test cache gamepass (UserOwnsGamePassAsync palsu), atribut cermin UI, refresh setelah
-- PromptGamePassPurchaseFinished, cleanup, dan validasi indeks preset tim (TeamRules.isTeamIndex).
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Passes = require(Server.Services.MonetizationService.Passes)
local Shared = game:GetService("ReplicatedStorage").Shared
local Constants = require(Shared.Config.Constants)
local Products = require(Shared.Config.Products)
local TeamRules = require(Shared.TeamRules)

local definitions: any = {
	gp_speed2x = { id = 1, kind = "GamePass" },
	gp_autoreplay = { id = 2, kind = "GamePass" },
	gp_presets = { id = 3, kind = "GamePass" },
	gp_vip_aura = { id = 0, kind = "GamePass" },
	gems_s = { id = 9, kind = "DeveloperProduct", grant = { currency = "Gems", amount = 1 } },
}

local function world()
	local owned: { [number]: boolean } = {}
	local failing = { value = false }
	local present: { [any]: boolean } = {}
	local attributes: { [any]: { [string]: any } } = {}
	local calls: { number } = {}
	local passes = Passes.create({
		ownsAsync = function(_: number, passId: number): any
			table.insert(calls, passId)
			if failing.value then
				error("HTTP 503 (mock)")
			end
			return owned[passId] == true
		end,
		isPresent = function(player: Player): boolean
			return present[player] == true
		end,
		setAttribute = function(player: Player, name: string, value: any)
			attributes[player] = attributes[player] or {}
			attributes[player][name] = value
		end,
		log = function() end,
	}, definitions)
	local function join(): any
		local player = { UserId = 7 }
		present[player] = true
		return player
	end
	return {
		owned = owned,
		failing = failing,
		present = present,
		attributes = attributes,
		calls = calls,
		passes = passes,
		join = join,
	}
end

return function(t: TestRunner.TestContext): ()
	t.test("join lookup caches ownership and mirrors attributes", function()
		local w = world()
		local p = w.join()
		w.owned[2] = true
		w.owned[3] = true
		t.expect(w.passes.load(p)).toBe(true)
		-- ID 0 tidak pernah ditanyakan ke Marketplace.
		t.expect(#w.calls).toBe(3)
		t.expect(w.passes.has(p, "gp_autoreplay")).toBe(true)
		t.expect(w.passes.has(p, "gp_speed2x")).toBe(false)
		t.expect(w.passes.has(p, "gp_vip_aura")).toBe(false)
		t.expect(w.passes.extraPresets(p)).toBe(Products.extraPresetsWithPass)
		t.expect(w.attributes[p]).toEqual({
			PassSpeed2x = false,
			PassAutoReplay = true,
			PassExtraPresets = Products.extraPresetsWithPass,
			PassVipAura = false,
		})
		-- Atribut yang diubah (mis. oleh client) bukan sumber otoritas.
		w.attributes[p].PassSpeed2x = true
		t.expect(w.passes.has(p, "gp_speed2x")).toBe(false)
	end)

	t.test("lookup failure is fail-closed and retry can succeed", function()
		local w = world()
		local p = w.join()
		w.owned[1] = true
		w.failing.value = true
		t.expect(w.passes.load(p)).toBe(false)
		t.expect(w.passes.has(p, "gp_speed2x")).toBe(false)
		t.expect(w.passes.extraPresets(p)).toBe(0)
		w.failing.value = false
		t.expect(w.passes.load(p)).toBe(true)
		t.expect(w.passes.has(p, "gp_speed2x")).toBe(true)
		-- Lookup gagal berikutnya tidak mencabut kepemilikan yang sudah terlihat.
		w.failing.value = true
		w.passes.load(p)
		t.expect(w.passes.has(p, "gp_speed2x")).toBe(true)
	end)

	t.test("purchase finished on the server refreshes only matching purchased passes", function()
		local w = world()
		local p = w.join()
		w.passes.load(p)
		w.passes.onPurchaseFinished(p, 1, false)
		t.expect(w.passes.has(p, "gp_speed2x")).toBe(false)
		w.passes.onPurchaseFinished(p, 999, true)
		w.passes.onPurchaseFinished(p, "1", true)
		w.passes.onPurchaseFinished(p, 0, true)
		t.expect(w.passes.has(p, "gp_speed2x")).toBe(false)
		w.owned[1] = true
		w.passes.onPurchaseFinished(p, 1, true)
		t.expect(w.passes.has(p, "gp_speed2x")).toBe(true)
		t.expect(w.attributes[p].PassSpeed2x).toBe(true)
	end)

	t.test("leaving clears the cache and late lookups are discarded", function()
		local w = world()
		local p = w.join()
		w.owned[3] = true
		w.passes.load(p)
		w.passes.clear(p)
		w.present[p] = nil
		t.expect(w.passes.has(p, "gp_presets")).toBe(false)
		w.passes.load(p)
		w.passes.onPurchaseFinished(p, 3, true)
		t.expect(w.passes.has(p, "gp_presets")).toBe(false)
	end)

	t.test("team preset index is validated against the server pass cap", function()
		local maxWithPass = Constants.TEAM_PRESETS_BASE + Products.extraPresetsWithPass
		t.expect(maxWithPass).toBe(7)
		t.expect(TeamRules.isTeamIndex(1, 0)).toBe(true)
		t.expect(TeamRules.isTeamIndex(2, 0)).toBe(false)
		t.expect(TeamRules.isTeamIndex(7, Products.extraPresetsWithPass)).toBe(true)
		t.expect(TeamRules.isTeamIndex(8, Products.extraPresetsWithPass)).toBe(false)
		t.expect(TeamRules.isTeamIndex(3, 100)).toBe(false)
		for _, bad in { 0, -1, 1.5, 0 / 0, math.huge, "1", nil :: any, {} } do
			t.expect(TeamRules.isTeamIndex(bad, Products.extraPresetsWithPass)).toBe(false)
		end
	end)
end
