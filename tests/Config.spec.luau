--!strict
local Config = game:GetService("ReplicatedStorage").Shared.Config
local TestRunner = require(game:GetService("ServerScriptService").Server.Dev.TestRunner)
local Banners = require(Config.Banners)
local Economy = require(Config.Economy)
local Stages = require(Config.Stages)
local Traits = require(Config.Traits)
local Units = require(Config.Units)
local Validate = require(Config.Validate)

return function(t: TestRunner.TestContext): ()
	t.test("validates the production configuration", function()
		Validate.run()
		t.expect(#Banners.definitions.standard.unitIds).toBe(15)
		t.expect(table.isfrozen(Units.kael.base)).toBe(true)
		t.expect(table.isfrozen(Banners.definitions.limited_example.unitIds)).toBe(true)
		t.expect(table.isfrozen(Traits.tiers.Epic.traits[1])).toBe(true)
	end)

	t.test("computes the documented level cost and star multiplier", function()
		t.expect(Economy.levelCost(1)).toBe(50)
		t.expect(Economy.levelCost(2)).toBe(141)
		t.expect(Economy.levelCost(4)).toBe(400)
		t.expect(Economy.starMultiplier(1)).toBe(1)
		t.expect(Economy.starMultiplier(5)).toBe(1.8)
	end)

	t.test("rejects modified banner odds and missing unit references", function()
		local banner = table.clone(Banners.definitions.standard)
		banner.oddsPercent = table.clone(banner.oddsPercent)
		banner.oddsPercent.Rare = 69
		local ok, err = pcall(Validate.run, Units, { standard = banner })
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "odds must total 100%", 1, true) ~= nil).toBe(true)
		banner.unitIds = { "missing" }
		ok, err = pcall(Validate.run, Units, { standard = banner })
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "unknown unit missing", 1, true) ~= nil).toBe(true)
	end)

	t.test("rejects changed trait odds and absent ultimate IDs", function()
		local tiers = table.clone(Traits.tiers)
		tiers.Common = table.clone(tiers.Common)
		tiers.Common.oddsPercent = 61
		local ok = pcall(Validate.run, Units, Banners.definitions, tiers)
		t.expect(ok).toBe(false)

		local units = table.clone(Units)
		units.kael = table.clone(units.kael)
		units.kael.ultimate = ""
		ok = pcall(Validate.run, units)
		t.expect(ok).toBe(false)
	end)

	t.test("rejects unrecognized unit rarity and element", function()
		local units = table.clone(Units)
		units.kael = table.clone(units.kael)
		units.kael.rarity = "Unknown" :: any
		local ok, err = pcall(Validate.run, units)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "unknown rarity", 1, true) ~= nil).toBe(true)

		units.kael.rarity = Units.kael.rarity
		units.kael.element = "Unknown" :: any
		ok, err = pcall(Validate.run, units)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "unknown element", 1, true) ~= nil).toBe(true)
	end)

	t.test("defines three chapters of ten stages with valid enemy references", function()
		t.expect(#Stages.chapters).toBe(3)
		for _, chapter in Stages.chapters do
			t.expect(#chapter).toBe(10)
			for _, stage in chapter do
				t.expect(Stages.byId[stage.id] == stage).toBe(true)
				t.expect(stage.firstThreeStarGems).toBe(30)
				for _, enemy in stage.enemies do
					t.expect(Units[enemy.unitId] ~= nil).toBe(true)
				end
			end
		end
	end)
end
