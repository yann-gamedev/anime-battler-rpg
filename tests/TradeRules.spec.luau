--!strict
-- Aturan trade murni (SYSTEMS A1/A2/A4): syarat pemain, kelayakan unit, duplikat, kapasitas, pajak,
-- refund level, swap satu sisi (UID tetap, trait & level reset, cooldown, referensi tim/skin/pajangan),
-- pergantian hari UTC, dan idempotensi marker.
local Server = game:GetService("ServerScriptService").Server
local Shared = game:GetService("ReplicatedStorage").Shared
local TestRunner = require(Server.Dev.TestRunner)
local Template = require(Server.Services.DataService.Template)
local TradeRules = require(Server.Services.DataService.TradeRules)
local Constants = require(Shared.Config.Constants)
local Trade = require(Shared.Config.Trade)
local ProgressionRules = require(Shared.ProgressionRules)

local DAY = 86400
local NOW = 400 * DAY + 3600

local function newProfile(gold: number): any
	local profile: any = Template.create(0)
	profile.accountLevel = Trade.minAccountLevel
	profile.currencies.Gold = gold
	TradeRules.reconcile(profile)
	return profile
end

local function addUnit(profile: any, uid: string, unitId: string, overrides: { [string]: any }?): any
	local unit = {
		uid = uid,
		unitId = unitId,
		stars = 1,
		level = 1,
		xp = 0,
		trait = nil,
		locked = false,
		tradeCooldownUntil = nil,
		obtainedAt = 0,
		source = "summon",
	}
	for key, value in overrides or {} do
		(unit :: any)[key] = value
	end
	profile.units[uid] = unit
	return unit
end

local function record(a: any, b: any): any
	local sideA = TradeRules.buildSide(a.profile, 1, a.uids, a.skins, NOW)
	local sideB = TradeRules.buildSide(b.profile, 2, b.uids, b.skins, NOW)
	return TradeRules.buildRecord("trade-1", NOW, sideA, sideB)
end

return function(t: TestRunner.TestContext): ()
	t.test("player gates: account level, account age, daily limit with UTC rollover", function()
		local profile = newProfile(1000)
		t.expect(TradeRules.checkPlayer(profile, Trade.minAccountAgeDays, NOW)).toBe(nil)
		profile.accountLevel = Trade.minAccountLevel - 1
		t.expect(TradeRules.checkPlayer(profile, 30, NOW)).toBe("ACCOUNT_LEVEL_TOO_LOW")
		profile.accountLevel = Trade.minAccountLevel
		t.expect(TradeRules.checkPlayer(profile, Trade.minAccountAgeDays - 1, NOW)).toBe("ACCOUNT_TOO_NEW")
		t.expect(TradeRules.checkPlayer(profile, 0 / 0, NOW)).toBe("ACCOUNT_TOO_NEW")
		profile.tradeDaily = { day = TradeRules.utcDay(NOW), count = Trade.dailyMaxTrades }
		t.expect(TradeRules.checkPlayer(profile, 30, NOW)).toBe("DAILY_TRADE_LIMIT")
		-- Hari UTC berikutnya: hitungan baru.
		t.expect(TradeRules.checkPlayer(profile, 30, NOW + DAY)).toBe(nil)
	end)

	t.test("unit eligibility: ownership, stars, lock, defense, cooldowns", function()
		local profile = newProfile(1000)
		addUnit(profile, "rare", "kael")
		addUnit(profile, "two", "kael", { stars = 2 })
		addUnit(profile, "locked", "kael", { locked = true })
		addUnit(profile, "cool", "kael", { tradeCooldownUntil = NOW + 10 })
		addUnit(profile, "mythicNew", "umbra", { obtainedAt = NOW - 10 })
		addUnit(profile, "mythicOld", "umbra", { obtainedAt = NOW - Trade.cooldownSeconds })
		addUnit(profile, "limitedNew", "seraphine", { obtainedAt = NOW - 10 })
		addUnit(profile, "legendaryNew", "valka", { obtainedAt = NOW - 10 })
		addUnit(profile, "defense", "kael")
		profile.defense = { uids = { defense = true } }
		t.expect(TradeRules.checkUnit(profile, "rare", NOW)).toBe(nil)
		t.expect(TradeRules.checkUnit(profile, "missing", NOW)).toBe("UNIT_NOT_OWNED")
		t.expect(TradeRules.checkUnit(profile, "two", NOW)).toBe("UNIT_STARS_NOT_TRADABLE")
		t.expect(TradeRules.checkUnit(profile, "locked", NOW)).toBe("UNIT_LOCKED")
		t.expect(TradeRules.checkUnit(profile, "cool", NOW)).toBe("UNIT_ON_COOLDOWN")
		t.expect(TradeRules.checkUnit(profile, "mythicNew", NOW)).toBe("UNIT_ON_COOLDOWN")
		t.expect(TradeRules.checkUnit(profile, "mythicOld", NOW)).toBe(nil)
		t.expect(TradeRules.checkUnit(profile, "limitedNew", NOW)).toBe("UNIT_ON_COOLDOWN")
		t.expect(TradeRules.checkUnit(profile, "legendaryNew", NOW)).toBe(nil)
		t.expect(TradeRules.checkUnit(profile, "defense", NOW)).toBe("UNIT_IN_DEFENSE")
	end)

	t.test("offer rejects duplicates, unknown or unowned skins and too many items", function()
		local profile = newProfile(1000)
		addUnit(profile, "u1", "kael")
		profile.skinsOwned.skin_academy_scholar = true
		t.expect(TradeRules.checkOffer(profile, { "u1", "u1" }, {}, NOW)).toBe("DUPLICATE_ITEM")
		local skin = "skin_academy_scholar"
		t.expect(TradeRules.checkOffer(profile, {}, { skin, skin }, NOW)).toBe("DUPLICATE_ITEM")
		t.expect(TradeRules.checkOffer(profile, {}, { "nope" }, NOW)).toBe("INVALID_SKIN")
		t.expect(TradeRules.checkOffer(profile, {}, { "skin_s1_starfall" }, NOW)).toBe("SKIN_NOT_OWNED")
		local many = table.create(Trade.maxItemsPerSide, "u1")
		t.expect(TradeRules.checkOffer(profile, many, { skin }, NOW)).toBe("TOO_MANY_ITEMS")
		t.expect(TradeRules.checkOffer(profile, { "u1" }, { skin }, NOW)).toBe(nil)
	end)

	t.test("receive rejects duplicate UID, owned skin, and full inventory", function()
		local giver, receiver = newProfile(1000), newProfile(1000)
		addUnit(giver, "u1", "kael")
		giver.skinsOwned.skin_academy_scholar = true
		local side = TradeRules.buildSide(giver, 1, { "u1" }, { "skin_academy_scholar" }, NOW)
		t.expect(TradeRules.checkReceive(receiver, side, 0)).toBe(nil)
		addUnit(receiver, "u1", "kael")
		t.expect(TradeRules.checkReceive(receiver, side, 0)).toBe("DUPLICATE_UID")
		receiver.units.u1 = nil
		receiver.skinsOwned.skin_academy_scholar = true
		t.expect(TradeRules.checkReceive(receiver, side, 0)).toBe("SKIN_ALREADY_OWNED")
		receiver.skinsOwned.skin_academy_scholar = nil
		for index = 1, Constants.MAX_UNITS_PER_PLAYER do
			addUnit(receiver, `r{index}`, "pip")
		end
		t.expect(TradeRules.checkReceive(receiver, side, 0)).toBe("INVENTORY_FULL")
		t.expect(TradeRules.checkReceive(receiver, side, 1)).toBe(nil)
	end)

	t.test("tax requires taxGold", function()
		t.expect(TradeRules.checkTax(newProfile(Trade.taxGold - 1))).toBe("NOT_ENOUGH_GOLD")
		t.expect(TradeRules.checkTax(newProfile(Trade.taxGold))).toBe(nil)
	end)

	t.test("level refund is levelRefundRate of progression cost, floored", function()
		t.expect(select(1, TradeRules.levelRefund(1))).toBe(0)
		local gold, scrolls = ProgressionRules.levelUpCost(1, 2)
		local refundGold, refundScrolls = TradeRules.levelRefund(3)
		t.expect(refundGold).toBe(math.floor(gold * Trade.levelRefundRate))
		t.expect(refundScrolls).toBe(math.floor(scrolls * Trade.levelRefundRate))
		-- 50 + 141 Gold, 2 scroll → 152 Gold, 1 scroll.
		t.expect(refundGold).toBe(152)
		t.expect(refundScrolls).toBe(1)
	end)

	t.test("swap keeps UID, resets level and trait, refunds giver, taxes both, sets cooldown", function()
		local a, b = newProfile(1000), newProfile(800)
		addUnit(a, "ua", "umbra", { level = 3, trait = "iron_skin", obtainedAt = 0 })
		addUnit(b, "ub", "kael")
		b.skinsOwned.skin_academy_scholar = true
		local rec = record(
			{ profile = a, uids = { "ua" }, skins = {} },
			{ profile = b, uids = { "ub" }, skins = { "skin_academy_scholar" } }
		)
		local codeA = TradeRules.applyHalf(a, rec, "a", true)
		local codeB = TradeRules.applyHalf(b, rec, "b", true)
		t.expect(codeA).toBe(nil)
		t.expect(codeB).toBe(nil)
		t.expect(a.units.ua).toBe(nil)
		local moved = b.units.ua
		t.expect(moved.uid).toBe("ua")
		t.expect(moved.level).toBe(1)
		t.expect(moved.trait).toBe(nil)
		t.expect(moved.source).toBe("trade")
		t.expect(moved.tradeCooldownUntil).toBe(NOW + Trade.cooldownSeconds)
		t.expect(a.units.ub.tradeCooldownUntil).toBe(nil)
		t.expect(a.skinsOwned.skin_academy_scholar).toBe(true)
		t.expect(b.skinsOwned.skin_academy_scholar).toBe(nil)
		t.expect(a.currencies.Gold).toBe(1000 + 152 - Trade.taxGold)
		t.expect(a.materials.XPScrolls).toBe(1)
		t.expect(b.currencies.Gold).toBe(800 - Trade.taxGold)
		t.expect(a.tradeDaily.count).toBe(1)
		t.expect(b.tradeDaily.day).toBe(TradeRules.utcDay(NOW))
	end)

	t.test("swap clears team slot, equipped skin and showcase references", function()
		local a, b = newProfile(1000), newProfile(1000)
		addUnit(a, "ua", "kael")
		addUnit(a, "keep", "pip")
		a.teams[1].slots[1] = "ua"
		a.skinsOwned.skin_academy_scholar = true
		a.equippedSkins.ua = "skin_academy_scholar"
		a.equippedSkins.keep = "skin_academy_scholar"
		a.lobby = { showcaseUid = "keep", showcaseSkinId = "skin_academy_scholar" }
		local rec = record(
			{ profile = a, uids = { "ua" }, skins = { "skin_academy_scholar" } },
			{ profile = b, uids = {}, skins = {} }
		)
		local code, outcome = TradeRules.applyHalf(a, rec, "a", true)
		t.expect(code).toBe(nil)
		t.expect((outcome :: any).teams).toBe(true)
		t.expect(a.teams[1].slots[1]).toBe("")
		t.expect(a.equippedSkins.ua).toBe(nil)
		t.expect(a.equippedSkins.keep).toBe(nil)
		t.expect(a.lobby.showcaseUid).toBe("keep")
		t.expect(a.lobby.showcaseSkinId).toBe("")
	end)

	t.test("strict apply revalidates; marker makes repeat apply a no-op", function()
		local a, b = newProfile(1000), newProfile(1000)
		addUnit(a, "ua", "kael")
		local rec = record({ profile = a, uids = { "ua" }, skins = {} }, { profile = b, uids = {}, skins = {} })
		a.units.ua.locked = true
		t.expect((TradeRules.applyHalf(a, rec, "a", true))).toBe("UNIT_LOCKED")
		a.units.ua.locked = false
		t.expect((TradeRules.applyHalf(a, rec, "a", true))).toBe(nil)
		local gold = a.currencies.Gold
		t.expect((TradeRules.applyHalf(a, rec, "a", false))).toBe("ALREADY_APPLIED")
		t.expect(a.currencies.Gold).toBe(gold)
		t.expect(TradeRules.isApplied(a, "trade-1")).toBe(true)
	end)

	t.test("roll-forward tolerates missing items and reports anomalies", function()
		local a, b = newProfile(100), newProfile(1000)
		addUnit(b, "ub", "kael")
		local rec = record({ profile = a, uids = {}, skins = {} }, { profile = b, uids = { "ub" }, skins = {} })
		addUnit(a, "ub", "kael")
		local code, _, anomalies = TradeRules.applyHalf(a, rec, "a", false)
		t.expect(code).toBe(nil)
		t.expect(table.concat(anomalies :: { string }, ",")).toBe("duplicate_receive:ub,tax_short")
		t.expect(a.currencies.Gold).toBe(0)
	end)

	t.test("daily counter keeps a newer day when an older trade is rolled forward", function()
		local a, b = newProfile(1000), newProfile(1000)
		local rec = record({ profile = a, uids = {}, skins = {} }, { profile = b, uids = {}, skins = {} })
		a.tradeDaily = { day = rec.day + 1, count = 3 }
		TradeRules.applyHalf(a, rec, "a", false)
		t.expect(a.tradeDaily.day).toBe(rec.day + 1)
		t.expect(a.tradeDaily.count).toBe(3)
	end)

	t.test("applied markers are bounded FIFO", function()
		local a, b = newProfile(10 ^ 9), newProfile(10 ^ 9)
		for index = 1, Trade.log.recentTradesKept + 5 do
			local rec = record({ profile = a, uids = {}, skins = {} }, { profile = b, uids = {}, skins = {} })
			rec.tradeId = `t{index}`
			TradeRules.applyHalf(a, rec, "a", false)
		end
		t.expect(#a.trade.applied).toBe(Trade.log.recentTradesKept)
		t.expect(TradeRules.isApplied(a, "t1")).toBe(false)
		t.expect(TradeRules.isApplied(a, `t{Trade.log.recentTradesKept + 5}`)).toBe(true)
	end)
end
