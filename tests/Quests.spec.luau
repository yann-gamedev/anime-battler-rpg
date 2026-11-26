--!strict
-- Test quest: periode UTC (harian 00:00, mingguan Senin 00:00), progres dari aktivitas (cap target),
-- klaim sekali, kunci periode basi, reset lintas hari/minggu, XP Battle Pass atomik, rollback, dan target
-- ekonomi config (120 Gems/hari, 400 Gems/minggu).
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local Meta = require(Services.DataService.Meta)
local Template = require(Services.DataService.Template)
local Progress = require(Services.DataService.Progress)
local Handlers = require(Services.QuestService.Handlers)
local Shared = game:GetService("ReplicatedStorage").Shared
local Economy = require(Shared.Config.Economy)
local Quests = require(Shared.Config.Quests)
local QuestPeriods = require(Shared.QuestPeriods)
local Signal = require(Shared.Util.Signal)

-- 2026-11-30 adalah Senin. 1796083200 = 2026-12-01 00:00 UTC (Selasa).
local MONDAY = 1796083200 - 86400
local DAY = 86400

local function world(seasonActive: boolean?)
	local sessions: { [any]: any } = {}
	local clock = { value = MONDAY + 3600 }
	local ledger = Meta.create(function(player: Player): any
		return sessions[player]
	end, Signal.new())
	local claimed = {}
	local h = Handlers.create({
		ledger = ledger,
		now = function(): number
			return clock.value
		end,
		battlePass = function(_now: number): any
			return if seasonActive then { seasonId = "sTest", maxXp = 3000 } else nil
		end,
		onClaimed = function(_player, def)
			table.insert(claimed, def.id)
		end,
	})
	local function join(): any
		local player = { UserId = 7 }
		local profile = Template.create(0)
		Progress.reconcile(profile)
		sessions[player] = { Data = profile }
		return player
	end
	local function quest(player: any, id: string): any
		local info = h.buildInfo(player)
		for _, view in info.quests do
			if view.id == id then
				return view
			end
		end
		error("quest not found " .. id)
	end
	return { sessions = sessions, clock = clock, h = h, join = join, quest = quest, claimed = claimed }
end

return function(ctx: TestRunner.TestContext)
	local test, expect = ctx.test, ctx.expect

	test("periods use UTC days and Monday-start weeks", function()
		expect(QuestPeriods.utcDay(MONDAY)).toBe(MONDAY // DAY)
		expect(QuestPeriods.dailyResetAt(MONDAY + 5)).toBe(MONDAY + DAY)
		expect(QuestPeriods.dailyResetAt(MONDAY + DAY - 1)).toBe(MONDAY + DAY)
		expect(QuestPeriods.key("Daily", MONDAY - 1) ~= QuestPeriods.key("Daily", MONDAY)).toBe(true)
		-- Minggu 23:59:59 dan Senin 00:00 ada di minggu berbeda; Senin..Minggu dalam minggu yang sama.
		expect(QuestPeriods.key("Weekly", MONDAY - 1) ~= QuestPeriods.key("Weekly", MONDAY)).toBe(true)
		expect(QuestPeriods.key("Weekly", MONDAY)).toBe(QuestPeriods.key("Weekly", MONDAY + 7 * DAY - 1))
		expect(QuestPeriods.weeklyResetAt(MONDAY)).toBe(MONDAY + 7 * DAY)
		expect(QuestPeriods.weeklyResetAt(MONDAY + 6 * DAY + 5)).toBe(MONDAY + 7 * DAY)
		-- Epoch 1970-01-05 adalah Senin pertama.
		expect(QuestPeriods.weeklyResetAt(0)).toBe(4 * DAY)
	end)

	test("config meets economy Gems targets", function()
		local daily, weekly, weeklyShards = 0, 0, 0
		for _, def in Quests.definitions do
			if def.period == "Daily" then
				daily += def.rewards.Gems or 0
			else
				weekly += def.rewards.Gems or 0
				weeklyShards += def.rewards.TraitShards or 0
			end
		end
		expect(daily).toBe(Economy.gemsIncomeTargets.dailyQuests)
		expect(weekly).toBe(Economy.gemsIncomeTargets.weeklyQuests)
		expect(weeklyShards > 0).toBe(true)
	end)

	test("snapshot shape and reset times", function()
		local w = world(false)
		local player = w.join()
		local result = w.h.GetQuests(player)
		expect(result.ok).toBe(true)
		expect(result.data.serverTime).toBe(w.clock.value)
		expect(result.data.dailyResetAt).toBe(MONDAY + DAY)
		expect(result.data.weeklyResetAt).toBe(MONDAY + 7 * DAY)
		expect(#result.data.quests).toBe(#Quests.definitions)
		local view = w.quest(player, "daily_story_wins")
		expect(view.periodKey).toBe(QuestPeriods.key("Daily", w.clock.value))
		expect(view.progress).toBe(0)
		expect(view.claimed).toBe(false)
		expect(view.rewards[Quests.battlePassXpRewardKey]).toBe(nil)
		expect(w.h.GetQuests(player, 1).code).toBe("INVALID_ARGUMENTS")
		expect(w.h.GetQuests({ UserId = 99 } :: any).code).toBe("DATA_NOT_READY")
	end)

	test("activity progress is capped and claim works once", function()
		local w = world(false)
		local player = w.join()
		expect(w.h.onActivity(player, "story_win", 1)).toBe(nil)
		local view = w.quest(player, "daily_story_wins")
		expect(view.progress).toBe(1)
		expect(w.h.ClaimQuest(player, "daily_story_wins", view.periodKey).code).toBe("QUEST_INCOMPLETE")
		expect(w.h.onActivity(player, "story_win", 50)).toBe(nil)
		expect(w.quest(player, "daily_story_wins").progress).toBe(3)
		expect(w.quest(player, "weekly_story_wins").progress).toBe(25)
		local gems = w.sessions[player].Data.currencies.Gems
		local result = w.h.ClaimQuest(player, "daily_story_wins", view.periodKey)
		expect(result.ok).toBe(true)
		expect(w.sessions[player].Data.currencies.Gems).toBe(gems + 40)
		expect(w.sessions[player].Data.currencies.Gold).toBe(500)
		expect(w.quest(player, "daily_story_wins").claimed).toBe(true)
		expect(w.h.ClaimQuest(player, "daily_story_wins", view.periodKey).code).toBe("ALREADY_CLAIMED")
		expect(w.sessions[player].Data.currencies.Gems).toBe(gems + 40)
		expect(#w.claimed).toBe(1)
		-- Progres quest yang sudah diklaim tidak berubah lagi.
		expect(w.h.onActivity(player, "story_win", 1)).toBe(nil)
		expect(w.quest(player, "daily_story_wins").progress).toBe(3)
	end)

	test("invalid arguments and activity kinds are rejected", function()
		local w = world(false)
		local player = w.join()
		local key = QuestPeriods.key("Daily", w.clock.value)
		expect(w.h.ClaimQuest(player, "nope", key).code).toBe("INVALID_QUEST")
		expect(w.h.ClaimQuest(player, 5, key).code).toBe("INVALID_QUEST")
		expect(w.h.ClaimQuest(player, string.rep("a", 100), key).code).toBe("INVALID_QUEST")
		expect(w.h.ClaimQuest(player, "daily_raid", nil).code).toBe("INVALID_PERIOD")
		expect(w.h.ClaimQuest(player, "daily_raid", string.rep("D", 40)).code).toBe("INVALID_PERIOD")
		expect(w.h.ClaimQuest(player, "daily_raid", key, "x").code).toBe("INVALID_ARGUMENTS")
		expect(w.h.onActivity(player, "summon", 1)).toBe("INVALID_ACTIVITY")
		expect(w.h.onActivity(player, "story_win", 0)).toBe("INVALID_ACTIVITY")
		expect(w.h.onActivity(player, "story_win", 0 / 0)).toBe("INVALID_ACTIVITY")
		expect(w.h.onActivity(player, "story_win", 1.5)).toBe("INVALID_ACTIVITY")
	end)

	test("stale period key is rejected and daily progress resets at 00:00 UTC", function()
		local w = world(false)
		local player = w.join()
		w.h.onActivity(player, "raid_attempt", 1)
		local oldKey = w.quest(player, "daily_raid").periodKey
		w.clock.value = MONDAY + DAY -- tepat 00:00 UTC hari berikutnya
		expect(w.h.ClaimQuest(player, "daily_raid", oldKey).code).toBe("PERIOD_EXPIRED")
		local view = w.quest(player, "daily_raid")
		expect(view.progress).toBe(0)
		expect(view.periodKey ~= oldKey).toBe(true)
		-- Progres mingguan tetap dalam minggu yang sama.
		expect(w.quest(player, "weekly_raids").progress).toBe(1)
		w.h.onActivity(player, "raid_attempt", 1)
		expect(w.h.ClaimQuest(player, "daily_raid", view.periodKey).ok).toBe(true)
		-- Minggu berikutnya: progres mingguan dari awal.
		w.clock.value = MONDAY + 7 * DAY
		expect(w.quest(player, "weekly_raids").progress).toBe(0)
		-- Record tersimpan hanya periode aktif (terbatas).
		w.h.onActivity(player, "raid_attempt", 1)
		local stored = w.sessions[player].Data.quests
		expect(stored.weekly.key).toBe(QuestPeriods.key("Weekly", w.clock.value))
		expect(stored.daily.key).toBe(QuestPeriods.key("Daily", w.clock.value))
	end)

	test("claim grants battle pass XP atomically during an active season", function()
		local w = world(true)
		local player = w.join()
		w.h.onActivity(player, "unit_level", 3)
		local view = w.quest(player, "daily_level_up")
		expect(view.rewards[Quests.battlePassXpRewardKey]).toBe(20)
		expect(w.h.ClaimQuest(player, "daily_level_up", view.periodKey).ok).toBe(true)
		expect(w.sessions[player].Data.battlePass.seasons.sTest.xp).toBe(20)
	end)

	test("failed battle pass step rolls back the whole claim", function()
		local sessions: { [any]: any } = {}
		local ledger = Meta.create(function(player: Player): any
			return sessions[player]
		end, Signal.new())
		local player = { UserId = 8 } :: any
		local profile = Template.create(0)
		Progress.reconcile(profile)
		sessions[player] = { Data = profile }
		local now = MONDAY + 10
		expect(ledger.addQuestProgress(player, "raid_attempt", 1, now)).toBe(nil)
		local code = ledger.claimQuest(player, {
			questId = "daily_raid",
			periodKey = QuestPeriods.key("Daily", now),
			now = now,
			battlePass = { seasonId = "", maxXp = 100 }, -- tidak valid → addXp gagal
		})
		expect(code).toBe("INVALID_REQUEST")
		expect(sessions[player].Data.currencies.Gems).toBe(0)
		expect(sessions[player].Data.quests.daily.claimed.daily_raid).toBe(nil)
	end)

	test("reconcile sanitizes tampered quest records", function()
		local profile: any = Template.create(0)
		profile.quests = {
			daily = {
				key = "D1",
				progress = { daily_raid = 999, bogus = 1, daily_level_up = -1 },
				claimed = { x = true },
			},
			weekly = "broken",
		}
		Progress.reconcile(profile)
		expect(profile.quests.daily.progress.daily_raid).toBe(nil)
		expect(profile.quests.daily.progress.bogus).toBe(nil)
		expect(profile.quests.daily.claimed.x).toBe(nil)
		expect(profile.quests.weekly.key).toBe("")
		local legacy: any = Template.create(0)
		legacy.quests = nil
		legacy.raid = nil
		legacy.lobby = nil
		Progress.reconcile(legacy)
		expect(legacy.quests.daily.key).toBe("")
		expect(legacy.raid.attempted).toBe(false)
		expect(legacy.lobby.showcaseUid).toBe("")
	end)
end
