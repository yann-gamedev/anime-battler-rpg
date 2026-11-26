--!strict
-- Test Battle Pass: info musim, XP story/quest (cap), klaim tier free/premium, klaim ganda, tier terkunci,
-- pilihan unit Epic, musim tidak aktif, rollback klaim, dan validasi config Products/BattlePass.
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local BattlePassLedger = require(Services.DataService.BattlePass)
local Template = require(Services.DataService.Template)
local Handlers = require(Services.BattlePassService.Handlers)
local Shared = game:GetService("ReplicatedStorage").Shared
local BattlePass = require(Shared.Config.BattlePass)
local Constants = require(Shared.Config.Constants)
local Products = require(Shared.Config.Products)
local Units = require(Shared.Config.Units)
local Validate = require(Shared.Config.Validate)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)

local SEASON = BattlePass.seasons[1]
local XP_PER_TIER = SEASON.xpPerTier

local function world()
	local sessions: { [any]: any } = {}
	local clock = { value = SEASON.startsAt + 10 }
	local nextUid = 0
	local ledger = BattlePassLedger.create(
		function(player: Player): any
			return sessions[player]
		end,
		Signal.new(),
		{
			now = function(): number
				return clock.value
			end,
			newUid = function(): string
				nextUid += 1
				return `bp-{nextUid}`
			end,
		}
	)
	local h = Handlers.create({
		ledger = ledger,
		now = function(): number
			return clock.value
		end,
	})
	local function join(): any
		local player = { UserId = 3 }
		sessions[player] = { Data = Template.create(0) }
		return player
	end
	local function record(player: any): any
		return sessions[player].Data.battlePass.seasons[SEASON.id]
	end
	local function giveXp(player: any, tiers: number)
		local total = tiers * XP_PER_TIER
		while total > 0 do
			local step = math.min(total, BattlePass.maxQuestXpPerGrant)
			assert(h.grantQuestXp(player, "test_quest", step) == nil)
			total -= step
		end
	end
	return { sessions = sessions, clock = clock, h = h, join = join, record = record, giveXp = giveXp }
end

local function findTier(track: string, kind: string): number
	for tier, def in SEASON.tiers do
		local rewards = if track == "Premium" then def.premium else def.free
		for _, reward in rewards do
			if reward.kind == kind then
				return tier
			end
		end
	end
	error("no tier with " .. kind)
end

return function(t: TestRunner.TestContext): ()
	t.test("season config: 28 days, 30 tiers, ~1000 free Gems, one free Epic choice", function()
		Validate.shop()
		t.expect(SEASON.endsAt - SEASON.startsAt).toBe(28 * 86400)
		t.expect(#SEASON.tiers).toBe(30)
		local gems = 0
		for _, def in SEASON.tiers do
			for _, reward in def.free do
				if reward.kind == "Currency" and reward.id == "Gems" then
					gems += reward.amount :: number
				end
			end
		end
		t.expect(gems).toBe(1000)
		local choice = SEASON.tiers[findTier("Free", "UnitChoice")].free
		for _, reward in choice do
			for _, unitId in reward.options or {} do
				t.expect(Units[unitId].rarity).toBe("Epic")
			end
		end
		t.expect(Products.definitions.pass_premium.battlePassSeasonId).toBe(SEASON.id)
	end)

	t.test("config validation rejects premium units and duplicate product IDs", function()
		local pass = TableUtil.deepCopy(BattlePass) :: any
		table.insert(pass.seasons[1].tiers[1].premium, { kind = "UnitChoice", options = { "selene" } })
		t.expect(pcall(Validate.shop, nil, pass)).toBe(false)
		local products = TableUtil.deepCopy(Products) :: any
		products.definitions.gems_s.id = 5
		products.definitions.gems_m.id = 5
		t.expect(pcall(Validate.shop, products, nil)).toBe(false)
		local badAcademy = TableUtil.deepCopy(Products) :: any
		badAcademy.academy[1].costGems = -1
		t.expect(pcall(Validate.shop, badAcademy, nil)).toBe(false)
	end)

	t.test("GetBattlePass reports server state for the active season", function()
		local w = world()
		local p = w.join()
		local r = w.h.GetBattlePass(p)
		t.expect(r.ok).toBe(true)
		t.expect(r.data.seasonId).toBe(SEASON.id)
		t.expect(r.data.active).toBe(true)
		t.expect(r.data.xp).toBe(0)
		t.expect(r.data.unlockedTier).toBe(0)
		t.expect(#r.data.tiers).toBe(30)
		t.expect(w.h.GetBattlePass(p, true).code).toBe("INVALID_ARGUMENTS")
		t.expect(w.h.GetBattlePass({ UserId = 1 } :: any).code).toBe("DATA_NOT_READY")
	end)

	t.test("story wins and quest XP accrue with caps", function()
		local w = world()
		local p = w.join()
		local _, xp = w.h.awardStoryWin(p)
		t.expect(xp).toBe(BattlePass.storyWinXp)
		t.expect(w.h.grantQuestXp(p, "q", BattlePass.maxQuestXpPerGrant + 1)).toBe("INVALID_AMOUNT")
		t.expect(w.h.grantQuestXp(p, "q", 0)).toBe("INVALID_AMOUNT")
		t.expect(w.h.grantQuestXp(p, "q", 1.5)).toBe("INVALID_AMOUNT")
		t.expect(w.h.grantQuestXp(p, "", 10)).toBe("INVALID_QUEST")
		w.giveXp(p, 40)
		t.expect(w.record(p).xp).toBe(#SEASON.tiers * XP_PER_TIER)
	end)

	t.test("free claim grants once; locked and duplicate claims are rejected", function()
		local w = world()
		local p = w.join()
		t.expect(w.h.ClaimBattlePassTier(p, "Free", 1).code).toBe("TIER_LOCKED")
		w.giveXp(p, 1)
		local r = w.h.ClaimBattlePassTier(p, "Free", 1)
		t.expect(r.ok).toBe(true)
		t.expect(r.data.tiers[1].freeClaimed).toBe(true)
		local gold = w.sessions[p].Data.currencies.Gold
		t.expect(gold > 0).toBe(true)
		t.expect(w.h.ClaimBattlePassTier(p, "Free", 1).code).toBe("ALREADY_CLAIMED")
		t.expect(w.sessions[p].Data.currencies.Gold).toBe(gold)
		t.expect(w.h.ClaimBattlePassTier(p, "Free", 2).code).toBe("TIER_LOCKED")
	end)

	t.test("premium track requires the receipt entitlement for this season", function()
		local w = world()
		local p = w.join()
		w.giveXp(p, 1)
		t.expect(w.h.ClaimBattlePassTier(p, "Premium", 1).code).toBe("PREMIUM_REQUIRED")
		w.record(p).premium = true
		local before = w.sessions[p].Data.currencies.Gems
		t.expect(w.h.ClaimBattlePassTier(p, "Premium", 1).ok).toBe(true)
		t.expect(w.sessions[p].Data.currencies.Gems > before).toBe(true)
		t.expect(w.h.ClaimBattlePassTier(p, "Premium", 1).code).toBe("ALREADY_CLAIMED")
	end)

	t.test("unit choice validates the option and grants exactly one unit", function()
		local w = world()
		local p = w.join()
		local tier = findTier("Free", "UnitChoice")
		w.giveXp(p, tier)
		t.expect(w.h.ClaimBattlePassTier(p, "Free", tier).code).toBe("UNIT_CHOICE_REQUIRED")
		t.expect(w.h.ClaimBattlePassTier(p, "Free", tier, "seraphine").code).toBe("INVALID_UNIT_CHOICE")
		t.expect(w.h.ClaimBattlePassTier(p, "Free", tier, 5).code).toBe("INVALID_UNIT_CHOICE")
		t.expect(w.h.ClaimBattlePassTier(p, "Free", 1, "selene").code).toBe("INVALID_UNIT_CHOICE")
		t.expect(next(w.sessions[p].Data.units)).toBe(nil)
		t.expect(w.h.ClaimBattlePassTier(p, "Free", tier, "selene").ok).toBe(true)
		local unit = w.sessions[p].Data.units["bp-1"]
		t.expect(unit.unitId).toBe("selene")
		t.expect(unit.source).toBe("battlepass")
		t.expect(w.h.ClaimBattlePassTier(p, "Free", tier, "nyx").code).toBe("ALREADY_CLAIMED")
	end)

	t.test("full inventory rolls back the whole claim", function()
		local w = world()
		local p = w.join()
		local tier = findTier("Free", "UnitChoice")
		w.giveXp(p, tier)
		local units = w.sessions[p].Data.units
		for index = 1, Constants.MAX_UNITS_PER_PLAYER do
			units[`u{index}`] = { uid = `u{index}`, unitId = "kael", stars = 1, level = 1, xp = 0, locked = false }
		end
		local gems = w.sessions[p].Data.currencies.Gems
		t.expect(w.h.ClaimBattlePassTier(p, "Free", tier, "selene").code).toBe("INVENTORY_FULL")
		t.expect(w.record(p).freeClaimed[tostring(tier)]).toBe(nil)
		t.expect(w.sessions[p].Data.currencies.Gems).toBe(gems)
	end)

	t.test("claim arguments and inactive seasons are rejected", function()
		local w = world()
		local p = w.join()
		w.giveXp(p, 30)
		for _, tier in { 0, 31, 1.5, 0 / 0, "1" :: any, math.huge } do
			t.expect(w.h.ClaimBattlePassTier(p, "Free", tier).code).toBe("INVALID_TIER")
		end
		t.expect(w.h.ClaimBattlePassTier(p, "free", 1).code).toBe("INVALID_TRACK")
		t.expect(w.h.ClaimBattlePassTier(p, nil :: any, 1).code).toBe("INVALID_TRACK")
		t.expect(w.h.ClaimBattlePassTier(p, "Free", 1, nil, "x").code).toBe("INVALID_ARGUMENTS")
		w.clock.value = SEASON.endsAt
		t.expect(w.h.ClaimBattlePassTier(p, "Free", 1).code).toBe("SEASON_INACTIVE")
		t.expect(w.h.awardStoryWin(p)).toBe("SEASON_INACTIVE")
		local info = w.h.GetBattlePass(p)
		t.expect(info.data.active).toBe(false)
		t.expect(info.data.seasonId).toBe(SEASON.id)
	end)
end
