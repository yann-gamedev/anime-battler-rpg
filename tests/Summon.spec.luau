--!strict
-- Test murni roll gacha & odds (prompts/07-summon-banner.md). Tidak menyentuh profil atau PolicyService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local SummonModules = Server.Services.SummonService
local Roll = require(SummonModules.Roll)
local Odds = require(SummonModules.Odds)
local Catalog = require(SummonModules.Catalog)
local Shared = ReplicatedStorage.Shared
local Banners = require(Shared.Config.Banners)
local Economy = require(Shared.Config.Economy)
local Units = require(Shared.Config.Units)
local BattleRng = require(Shared.BattleSim.Rng)

type PityState = Roll.PityState

local standard = Banners.definitions.standard
local limited = Banners.definitions.limited_example
local RANK: { [string]: number } = { Rare = 1, Epic = 2, Legendary = 3, Mythic = 4 }
local EPSILON = 1e-9

local function state(sinceLegendary: number, sinceMythic: number, guaranteedFeatured: boolean?): PityState
	return {
		sinceLegendary = sinceLegendary,
		sinceMythic = sinceMythic,
		guaranteedFeatured = guaranteedFeatured == true,
	}
end

local function seeded(seed: number): Roll.Rng
	local rngState = BattleRng.new(seed)
	return {
		NextNumber = function(): number
			return BattleRng.nextNumber(rngState)
		end,
	}
end

local function constant(value: number): Roll.Rng
	return {
		NextNumber = function(): number
			return value
		end,
	}
end

local function rarityPercent(odds: any, rarity: string): number
	for _, entry in odds.rarities do
		if entry.rarity == rarity then
			return entry.percent
		end
	end
	error(`missing rarity {rarity}`)
end

local function unitPercent(odds: any, unitId: string): number
	for _, entry in odds.units do
		if entry.unitId == unitId then
			return entry.percent
		end
	end
	error(`missing unit {unitId}`)
end

local function near(t: TestRunner.TestContext, actual: number, expected: number, tolerance: number, label: string)
	if math.abs(actual - expected) > tolerance then
		error(`{label}: expected {expected} ± {tolerance}, got {actual}`, 2)
	end
	t.expect(true).toBe(true)
end

local function checkTotals(t: TestRunner.TestContext, odds: any, label: string)
	local rarities, units = 0, 0
	for _, entry in odds.rarities do
		t.expect(entry.percent >= 0 and entry.percent <= 100).toBe(true)
		rarities += entry.percent
	end
	for _, entry in odds.units do
		t.expect(entry.percent >= 0 and entry.percent <= 100).toBe(true)
		units += entry.percent
	end
	near(t, rarities, 100, EPSILON, `{label} rarity total`)
	near(t, units, 100, EPSILON, `{label} unit total`)
	t.expect(#odds.rarities).toBe(4)
	t.expect(#odds.units).toBe(#standard.unitIds)
end

return function(t: TestRunner.TestContext): ()
	t.test("base odds come from config for every rarity and unit", function()
		for _, banner in { standard, limited } do
			local odds = Odds.base(banner)
			checkTotals(t, odds, banner.id)
			for rarity, percent in banner.oddsPercent do
				near(t, rarityPercent(odds, rarity), percent, EPSILON, `{banner.id} {rarity}`)
			end
			for _, entry in odds.units do
				t.expect(entry.name).toBe(Units[entry.unitId].name)
				t.expect(entry.rarity).toBe(Units[entry.unitId].rarity)
			end
		end
		-- ECONOMY §2: Mythic 0.5% → Seraphine 0.25%, Umbra 0.25%; featured memegang 50% rarity-nya.
		near(t, unitPercent(Odds.base(standard), "seraphine"), 0.25, EPSILON, "standard seraphine")
		near(t, unitPercent(Odds.base(limited), "seraphine"), 0.25, EPSILON, "limited featured")
		near(t, unitPercent(Odds.base(limited), "umbra"), 0.25, EPSILON, "limited other mythic")
		t.expect(Odds.base(limited).units[1].unitId ~= nil).toBe(true)
	end)

	t.test("1,000,000 seeded base draws stay within 0.1% of config odds", function()
		local rng = seeded(20261126)
		local counts: { [string]: number } = { Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
		local fresh = state(0, 0)
		local total = 1000000
		for _ = 1, total do
			local draw = Roll.draw(standard, fresh, nil, rng)
			counts[draw.rarity] += 1
		end
		for rarity, percent in standard.oddsPercent do
			near(t, counts[rarity] / total * 100, percent, 0.1, `1M {rarity}`)
		end
	end)

	t.test("draw 50 without Legendary+ is always Legendary+ with relative odds", function()
		local odds = Odds.single(standard, state(49, 49))
		near(t, rarityPercent(odds, "Legendary"), 90, EPSILON, "pity Legendary")
		near(t, rarityPercent(odds, "Mythic"), 10, EPSILON, "pity Mythic")
		near(t, rarityPercent(Odds.single(standard, state(48, 48)), "Rare"), 70, EPSILON, "draw 49 unchanged")
		local rng = seeded(7)
		for _, u in { 0, 0.5, 0.999999 } do
			t.expect(RANK[Roll.draw(standard, state(49, 49), nil, constant(u)).rarity] >= 3).toBe(true)
		end
		for _ = 1, 10000 do
			t.expect(RANK[Roll.draw(limited, state(49, 100), nil, rng).rarity] >= 3).toBe(true)
		end
		-- Dari profil baru, RNG yang selalu memilih Rare: draw ke-50 menjadi Legendary+.
		local current = state(0, 0)
		local draw
		for index = 1, 50 do
			draw, current = Roll.draw(standard, current, nil, constant(0))
			t.expect(draw.rarity == "Rare").toBe(index < 50)
		end
		t.expect(current.sinceLegendary).toBe(0)
		t.expect(current.sinceMythic).toBe(50)
	end)

	t.test("draw 200 without Mythic is always Mythic and outranks Legendary+ pity", function()
		local odds = Odds.single(standard, state(49, 199))
		near(t, rarityPercent(odds, "Mythic"), 100, EPSILON, "hard pity")
		for _, u in { 0, 0.3, 0.999999 } do
			t.expect(Roll.draw(standard, state(10, 199), nil, constant(u)).rarity).toBe("Mythic")
		end
		local current = state(0, 0)
		local draw
		for index = 1, 200 do
			draw, current = Roll.draw(standard, current, nil, constant(0))
			if index % 50 == 0 and index < 200 then
				t.expect(draw.rarity).toBe("Legendary")
			end
		end
		t.expect(draw.rarity).toBe("Mythic")
		t.expect(current.sinceMythic).toBe(0)
		t.expect(current.sinceLegendary).toBe(0)
	end)

	t.test("limited 50/50: a missed featured Mythic guarantees the next one", function()
		local hard = state(0, 199)
		local miss, afterMiss = Roll.draw(limited, hard, nil, constant(0.75))
		t.expect(miss.unitId).toBe("umbra")
		t.expect(afterMiss.guaranteedFeatured).toBe(true)
		local guaranteed = Odds.single(limited, state(0, 0, true))
		near(t, unitPercent(guaranteed, "seraphine"), 0.5, EPSILON, "guaranteed featured")
		near(t, unitPercent(guaranteed, "umbra"), 0, EPSILON, "other mythic after miss")
		for _, u in { 0, 0.5, 0.999999 } do
			local hit, afterHit = Roll.draw(limited, state(0, 199, true), nil, constant(u))
			t.expect(hit.unitId).toBe("seraphine")
			t.expect(hit.featured).toBe(true)
			t.expect(afterHit.guaranteedFeatured).toBe(false)
		end
		local win, afterWin = Roll.draw(limited, hard, nil, constant(0.25))
		t.expect(win.unitId).toBe("seraphine")
		t.expect(afterWin.guaranteedFeatured).toBe(false)
		-- Non-Mythic tidak mengubah flag; banner Standard tidak pernah memakainya.
		local _, keep = Roll.draw(limited, state(0, 0, true), nil, constant(0))
		t.expect(keep.guaranteedFeatured).toBe(true)
		local _, standardState = Roll.draw(standard, hard, nil, constant(0.75))
		t.expect(standardState.guaranteedFeatured).toBe(false)
	end)

	t.test("10x guarantees Epic+ on draw 10 only after nine Rare results", function()
		local draws = Roll.rollBatch(standard, state(0, 0), 10, constant(0))
		t.expect(#draws).toBe(10)
		for index = 1, 9 do
			t.expect(draws[index].rarity).toBe("Rare")
		end
		t.expect(draws[10].rarity).toBe("Epic")
		local values = { 0.75, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
		local index = 0
		local scripted: Roll.Rng = {
			NextNumber = function(): number
				index += 1
				return values[index]
			end,
		}
		local mixed = Roll.rollBatch(standard, state(0, 0), 10, scripted)
		t.expect(mixed[1].rarity).toBe("Epic")
		t.expect(mixed[10].rarity).toBe("Rare")
		local single = Roll.rollBatch(standard, state(0, 0), 1, constant(0))
		t.expect(single[1].rarity).toBe("Rare")
		-- Pity Legendary+ menang atas jaminan Epic pada draw yang sama.
		local withPity = Roll.rollBatch(standard, state(40, 40), 10, constant(0))
		t.expect(withPity[10].rarity).toBe("Legendary")
	end)

	t.test("odds.ten has exact per-position marginals that each total 100%", function()
		local ten = Odds.marginals(standard, state(0, 0))
		t.expect(#ten).toBe(10)
		for position, odds in ten do
			checkTotals(t, odds, `position {position}`)
		end
		for position = 1, 9 do
			near(t, rarityPercent(ten[position], "Rare"), 70, EPSILON, `position {position} Rare`)
		end
		local allRare = 0.7 ^ 9
		near(t, rarityPercent(ten[10], "Rare"), 70 * (1 - allRare), EPSILON, "position 10 Rare")
		near(t, rarityPercent(ten[10], "Epic"), 25 * (1 - allRare) + allRare * 25 / 30 * 100, EPSILON, "pos 10 Epic")
		local pity = Odds.marginals(limited, state(49, 199, true))
		near(t, unitPercent(pity[1], "seraphine"), 100, EPSILON, "featured hard pity")
		near(t, rarityPercent(pity[2], "Rare"), 70, EPSILON, "after pity")
		near(t, rarityPercent(Odds.single(standard, state(3, 3)), "Epic"), 25, EPSILON, "single")
	end)

	t.test("odds.ten matches a seeded Monte Carlo of the real roll", function()
		local start = state(45, 196, false)
		local ten = Odds.marginals(limited, start)
		local batches = 40000
		local rarityCounts: { { [string]: number } } = {}
		local featuredCounts: { number } = {}
		for position = 1, 10 do
			rarityCounts[position] = { Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
			featuredCounts[position] = 0
		end
		local rng = seeded(99)
		for _ = 1, batches do
			local draws = Roll.rollBatch(limited, start, 10, rng)
			for position, draw in draws do
				rarityCounts[position][draw.rarity] += 1
				if draw.unitId == "seraphine" then
					featuredCounts[position] += 1
				end
			end
		end
		for position, odds in ten do
			checkTotals(t, odds, `limited position {position}`)
			for rarity, count in rarityCounts[position] do
				near(t, count / batches * 100, rarityPercent(odds, rarity), 0.75, `MC {position} {rarity}`)
			end
			local featured = featuredCounts[position] / batches * 100
			near(t, featured, unitPercent(odds, "seraphine"), 0.75, `MC {position} featured`)
		end
	end)

	t.test("banner views use config prices and server-time periods", function()
		local view = Catalog.view(limited, state(2, 3, true), limited.startsAt :: number)
		t.expect(view.active).toBe(true)
		t.expect(view.kind).toBe("Limited")
		t.expect(view.featuredUnitId).toBe("seraphine")
		t.expect(view.startsAt).toBe(1795651200)
		t.expect(view.endsAt).toBe(1796860800)
		t.expect(view.prices.gems1).toBe(Economy.summonGems[1])
		t.expect(view.prices.gems10).toBe(Economy.summonGems[10])
		t.expect(view.prices.tickets1).toBe(Economy.summonTicketsPerRoll)
		t.expect(view.prices.tickets10).toBe(Economy.summonTicketsPerRoll * 10)
		t.expect(view.pity.legendaryPlusRolls).toBe(50)
		t.expect(view.pity.mythicRolls).toBe(200)
		t.expect(view.pity.guaranteedFeatured).toBe(true)
		t.expect(#view.odds.ten).toBe(10)
		t.expect(Catalog.isActive(limited, 1795651199)).toBe(false)
		t.expect(Catalog.isActive(limited, 1796860799)).toBe(true)
		t.expect(Catalog.isActive(limited, 1796860800)).toBe(false)
		t.expect(Catalog.isActive(standard, 0)).toBe(true)
		t.expect(Catalog.isActive(standard, 4102444800)).toBe(true)
		local standardView = Catalog.view(standard, state(0, 0), 0)
		t.expect(standardView.featuredUnitId).toBe(nil)
		t.expect(standardView.startsAt).toBe(nil)
		t.expect(Catalog.fingerprint("standard", state(1, 2)) ~= Catalog.fingerprint("standard", state(1, 3)))
			.toBe(true)
	end)
end
