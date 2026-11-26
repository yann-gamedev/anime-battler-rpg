--!strict
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local DataServiceModules = Server.Services.DataService
local Migrations = require(DataServiceModules.Migrations)
local ProfileRules = require(DataServiceModules.ProfileRules)
local Template = require(DataServiceModules.Template)

return function(t: TestRunner.TestContext): ()
	t.test("creates independent default profiles with dense team slots", function()
		local first, second = Template.create(10), Template.create(20)
		t.expect(first.version).toBe(1)
		t.expect(first.createdAt).toBe(10)
		t.expect(second.createdAt).toBe(20)
		t.expect(#first.teams[1].slots).toBe(9)
		first.teams[1].slots[9] = "unit"
		first.currencies.Gems = 100
		t.expect(second.teams[1].slots[9]).toBe("")
		t.expect(second.currencies.Gems).toBe(0)
	end)

	t.test("keeps v1 profile contents and rejects invalid or future versions", function()
		local profile = Template.create(10)
		profile.currencies.Gems = 100
		Migrations.run(profile)
		t.expect(profile.currencies.Gems).toBe(100)

		for _, version in { 0, 1.5, 2, math.huge, 0 / 0, "1" } do
			local ok = pcall(Migrations.run, { version = version })
			t.expect(ok).toBe(false)
		end
		local ok = pcall(Migrations.run, {})
		t.expect(ok).toBe(false)
	end)

	t.test("accepts exact currency amounts and rejects invalid values or insufficient funds", function()
		t.expect(ProfileRules.isCurrencyKind("Gems")).toBe(true)
		t.expect(ProfileRules.isCurrencyKind("Robux")).toBe(false)
		t.expect(ProfileRules.currencyBalance(0, 100, false)).toBe(100)
		t.expect(ProfileRules.currencyBalance(100, 100, true)).toBe(0)
		t.expect(ProfileRules.currencyBalance(100, 101, true)).toBe(nil)
		for _, amount in { -1, 0, 0.5, math.huge, 0 / 0, "1" } do
			t.expect(ProfileRules.currencyBalance(100, amount :: any, true)).toBe(nil)
			t.expect(ProfileRules.currencyBalance(100, amount :: any, false)).toBe(nil)
		end
		t.expect(ProfileRules.currencyBalance(2 ^ 53 - 1, 1, false)).toBe(nil)
	end)

	t.test("validates progression, trait and immutable unit identity", function()
		local unit = {
			uid = "unit",
			unitId = "kael",
			stars = 1,
			level = 1,
			xp = 0,
			locked = false,
			obtainedAt = 10,
			source = "story" :: "story",
		}
		local candidate = table.clone(unit) :: any
		candidate.stars = 5
		candidate.level = 60
		candidate.trait = "swift"
		t.expect(ProfileRules.isUnitUpdateValid(unit, candidate)).toBe(true)
		candidate.uid = "other"
		t.expect(ProfileRules.isUnitUpdateValid(unit, candidate)).toBe(false)
		candidate.uid = unit.uid
		candidate.stars = 6
		t.expect(ProfileRules.isUnitUpdateValid(unit, candidate)).toBe(false)
		candidate.stars = 5
		candidate.level = 1.5
		t.expect(ProfileRules.isUnitUpdateValid(unit, candidate)).toBe(false)
		candidate.level = 60
		candidate.trait = "unknown"
		t.expect(ProfileRules.isUnitUpdateValid(unit, candidate)).toBe(false)
	end)
end
