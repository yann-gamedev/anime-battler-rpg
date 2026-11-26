--!strict
-- Test Boss Raid: lock onboarding, 1 percobaan per hari UTC, klaim ganda/rejoin, reset 00:00 UTC, cap damage,
-- battle gagal tidak memakai percobaan, tier reward, hpMultiplier BattleSim, dan rollback commit.
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local Meta = require(Services.DataService.Meta)
local MetaRules = require(Services.DataService.MetaRules)
local Progress = require(Services.DataService.Progress)
local Template = require(Services.DataService.Template)
local Handlers = require(Services.RaidService.Handlers)
local Shared = game:GetService("ReplicatedStorage").Shared
local BattleSim = require(Shared.BattleSim)
local Raids = require(Shared.Config.Raids)
local RaidMath = require(Shared.RaidMath)
local Signal = require(Shared.Util.Signal)

local DAY = 86400
local START = 1796083200 + 3600 -- 2026-12-01 01:00 UTC

local function fakeResult(dmgPerHit: number, hits: number): any
	local log: { any } = {
		{ t = 0, kind = "spawn", unit = 1, unitId = "kael", side = "A", cell = 9, hp = 100, maxHp = 100 },
		{ t = 0, kind = "spawn", unit = 2, unitId = Raids.boss.unitId, side = "B", cell = 11, hp = 1, maxHp = 1 },
		{ t = 0, kind = "spawn", unit = 3, unitId = Raids.boss.unitId, side = "A", cell = 8, hp = 1, maxHp = 1 },
	}
	for index = 1, hits do
		table.insert(
			log,
			{ t = index, kind = "attack", src = 1, dst = 2, dmg = dmgPerHit, crit = false, hp = 1, shield = 0 }
		)
		-- Damage ke unit tim A dengan unitId sama tidak dihitung.
		table.insert(log, { t = index, kind = "damage", src = 2, dst = 3, dmg = 999, crit = false, hp = 1, shield = 0 })
	end
	return { winner = "draw", ticks = 900, log = log, survivors = {} }
end

local function world()
	local sessions: { [any]: any } = {}
	local clock = { value = START }
	local battle = { result = fakeResult(1000, 3) :: any, code = nil :: string?, calls = 0 }
	local attempts = {}
	local function make()
		local ledger = Meta.create(function(player: Player): any
			return sessions[player]
		end, Signal.new())
		return Handlers.create({
			ledger = ledger,
			now = function(): number
				return clock.value
			end,
			isTeamIndexAllowed = function(_player, teamIndex): boolean
				return teamIndex == 1
			end,
			runBattle = function(_player, _teamIndex): (any, string?)
				battle.calls += 1
				return battle.result, battle.code
			end,
			onAttempt = function(_player, damage, tier)
				table.insert(attempts, { damage = damage, tier = tier })
			end,
		})
	end
	local function join(unlocked: boolean): any
		local player = { UserId = 11 }
		local profile = Template.create(0)
		Progress.reconcile(profile)
		profile.flags.tutorialDone = unlocked
		sessions[player] = { Data = profile }
		return player
	end
	return {
		sessions = sessions,
		clock = clock,
		battle = battle,
		attempts = attempts,
		h = make(),
		make = make,
		join = join,
	}
end

return function(ctx: TestRunner.TestContext)
	local test, expect = ctx.test, ctx.expect
	local maxHp = RaidMath.bossMaxHp()

	test("boss input applies hpMultiplier in BattleSim", function()
		local result = BattleSim.run({
			teamA = { { unitId = "kael", stars = 1, level = 1, cell = 5 } },
			teamB = { RaidMath.bossInput() },
			seed = 7,
			maxTicks = 5,
		})
		local spawn: any = nil
		for _, event in result.log do
			local e = event :: any
			if e.kind == "spawn" and e.side == "B" then
				spawn = e
			end
		end
		expect(spawn.unitId).toBe(Raids.boss.unitId)
		expect(math.floor(spawn.maxHp)).toBe(maxHp)
		expect(maxHp > 100000).toBe(true)
		local ok = pcall(BattleSim.run, {
			teamA = { { unitId = "kael", stars = 1, level = 1, cell = 5 } },
			teamB = { { unitId = "garrick", stars = 1, level = 1, cell = 2, hpMultiplier = 0.5 } },
			seed = 1,
		})
		expect(ok).toBe(false)
	end)

	test("credited damage counts only boss hits and is capped", function()
		expect(RaidMath.creditedDamage(fakeResult(1000.7, 3), maxHp)).toBe(3002)
		expect(RaidMath.creditedDamage(fakeResult(maxHp, 5), maxHp)).toBe(maxHp)
		expect(RaidMath.creditedDamage(fakeResult(math.huge, 1), maxHp)).toBe(maxHp)
		expect(RaidMath.creditedDamage(fakeResult(0 / 0, 2), maxHp)).toBe(0)
		local rewards, tier = RaidMath.rewardsFor(0, maxHp)
		expect(next(rewards)).toBe(nil)
		expect(tier).toBe(0)
		local _, top = RaidMath.rewardsFor(maxHp, maxHp)
		expect(top).toBe(#Raids.tiers)
		expect(RaidMath.rewardsFor(1, maxHp).Gems).toBe(Raids.tiers[1].rewards.Gems)
	end)

	test("locked before onboarding and snapshot shape", function()
		local w = world()
		local player = w.join(false)
		local info = w.h.GetRaidInfo(player)
		expect(info.ok).toBe(true)
		expect(info.data.unlocked).toBe(false)
		expect(info.data.bossId).toBe(Raids.boss.id)
		expect(info.data.bossMaxHp).toBe(maxHp)
		expect(info.data.resetAt).toBe((START // DAY + 1) * DAY)
		expect(#info.data.rewardTiers).toBe(#Raids.tiers)
		expect(w.h.StartRaid(player, 1).code).toBe("RAID_LOCKED")
		expect(w.battle.calls).toBe(0)
		expect(w.h.GetRaidInfo(player, 1).code).toBe("INVALID_ARGUMENTS")
	end)

	test("one attempt per UTC day with atomic rewards", function()
		local w = world()
		local player = w.join(true)
		expect(w.h.StartRaid(player, 2).code).toBe("INVALID_TEAM_INDEX")
		expect(w.h.StartRaid(player, 1, 1).code).toBe("INVALID_ARGUMENTS")
		local result = w.h.StartRaid(player, 1)
		expect(result.ok).toBe(true)
		expect(result.data.damage).toBe(3000)
		expect(result.data.raid.attempted).toBe(true)
		expect(result.data.raid.bestDamage).toBe(3000)
		expect(result.data.replay).toBe(w.battle.result)
		local profile = w.sessions[player].Data
		expect(profile.currencies.Gems).toBe(result.data.rewards.Gems)
		expect(profile.currencies.Gold).toBe(result.data.rewards.Gold)
		expect(#w.attempts).toBe(1)
		-- Klaim ganda: ditolak sebelum battle.
		expect(w.h.StartRaid(player, 1).code).toBe("ALREADY_ATTEMPTED")
		expect(w.battle.calls).toBe(1)
		-- "Rejoin": handler & ledger baru dengan data tersimpan yang sama.
		local rejoined = w.make()
		expect(rejoined.StartRaid(player, 1).code).toBe("ALREADY_ATTEMPTED")
		expect(rejoined.GetRaidInfo(player).data.attempted).toBe(true)
		-- 23:59:59 masih hari yang sama; 00:00 UTC membuka percobaan baru.
		w.clock.value = (START // DAY + 1) * DAY - 1
		expect(w.h.StartRaid(player, 1).code).toBe("ALREADY_ATTEMPTED")
		w.clock.value += 1
		local info = w.h.GetRaidInfo(player)
		expect(info.data.attempted).toBe(false)
		expect(info.data.bestDamage).toBe(0)
		expect(w.h.StartRaid(player, 1).ok).toBe(true)
		expect(#w.attempts).toBe(2)
	end)

	test("failed battle does not consume the attempt", function()
		local w = world()
		local player = w.join(true)
		w.battle.result = nil
		w.battle.code = "EMPTY_TEAM"
		expect(w.h.StartRaid(player, 1).code).toBe("EMPTY_TEAM")
		expect(w.sessions[player].Data.raid.attempted).toBe(false)
		w.battle.result = fakeResult(maxHp, 2)
		local result = w.h.StartRaid(player, 1)
		expect(result.data.damage).toBe(maxHp)
		expect(result.data.rewards.Gems).toBe(Raids.tiers[#Raids.tiers].rewards.Gems)
	end)

	test("commit rechecks the attempt in the draft", function()
		local profile: any = Template.create(0)
		Progress.reconcile(profile)
		profile.flags.tutorialDone = true
		local request = { day = 5, damage = 10, maxDamage = 100, rewards = { Gems = 15 } }
		expect(MetaRules.attemptRaid(profile, request)).toBe(nil)
		expect(MetaRules.attemptRaid(profile, request)).toBe("ALREADY_ATTEMPTED")
		local bad = { day = 6, damage = 101, maxDamage = 100, rewards = {} }
		expect(MetaRules.attemptRaid(profile, bad)).toBe("INVALID_REQUEST")
		local forbidden = { day = 6, damage = 1, maxDamage = 100, rewards = { SummonTickets = 5 } }
		expect(MetaRules.attemptRaid(profile, forbidden)).toBe("INTERNAL_ERROR")
		expect(profile.currencies.Gems).toBe(15)
	end)
end
