--!strict
-- Quest harian & mingguan (prompt 10, docs/ECONOMY.md §3). BASELINE PLACEHOLDER untuk pass balancing.
-- Target ekonomi: semua quest harian = 120 Gems/hari (Economy.gemsIncomeTargets.dailyQuests),
-- semua quest mingguan = 400 Gems/minggu (weeklyQuests) + Trait Shards (ECONOMY §1).
-- Reset harian 00:00 UTC. Reset mingguan Senin 00:00 UTC (lihat QuestPeriods.luau).
-- Quest tidak memakai summon agar pemain restricted (ArePaidRandomItemsRestricted) bisa menyelesaikan semua.
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local definitions: { Types.QuestDef } = {
	{
		id = "daily_story_wins",
		period = "Daily",
		kind = "story_win",
		title = "Juara Kelas",
		description = "Menangkan 3 battle story.",
		target = 3,
		rewards = { Gems = 40, Gold = 500 },
		battlePassXp = 30,
	},
	{
		id = "daily_story_stars",
		period = "Daily",
		kind = "story_stars",
		title = "Bintang Akademi",
		description = "Kumpulkan 6 bintang dari battle story.",
		target = 6,
		rewards = { Gems = 20, Gold = 300 },
		battlePassXp = 20,
	},
	{
		id = "daily_level_up",
		period = "Daily",
		kind = "unit_level",
		title = "Latihan Rutin",
		description = "Naikkan level unit sebanyak 3 kali.",
		target = 3,
		rewards = { Gems = 30 },
		battlePassXp = 20,
	},
	{
		id = "daily_raid",
		period = "Daily",
		kind = "raid_attempt",
		title = "Tantang Golem",
		description = "Selesaikan 1 percobaan Boss Raid.",
		target = 1,
		rewards = { Gems = 30 },
		battlePassXp = 30,
	},
	{
		id = "weekly_story_wins",
		period = "Weekly",
		kind = "story_win",
		title = "Penakluk Mingguan",
		description = "Menangkan 25 battle story.",
		target = 25,
		rewards = { Gems = 150, TraitShards = 5 },
		battlePassXp = 150,
	},
	{
		id = "weekly_raids",
		period = "Weekly",
		kind = "raid_attempt",
		title = "Pemburu Golem",
		description = "Selesaikan 5 percobaan Boss Raid.",
		target = 5,
		rewards = { Gems = 150, TraitShards = 5 },
		battlePassXp = 150,
	},
	{
		id = "weekly_level_up",
		period = "Weekly",
		kind = "unit_level",
		title = "Mentor Akademi",
		description = "Naikkan level unit sebanyak 15 kali.",
		target = 15,
		rewards = { Gems = 100, Gold = 2000 },
		battlePassXp = 100,
	},
}

local byId: { [string]: Types.QuestDef } = {}
for _, def in definitions do
	byId[def.id] = def
end

return TableUtil.deepFreeze({
	definitions = definitions,
	byId = byId,
	-- 1970-01-01 (hari UTC 0) adalah Kamis. (hari + 3) // 7 menghasilkan minggu yang mulai Senin 00:00 UTC.
	weekStartOffsetDays = 3,
	secondsPerDay = 86400,
	maxQuestIdLength = 32,
	maxPeriodKeyLength = 16,
	-- Mata uang yang boleh menjadi reward quest/raid (bukan SummonTickets/AsramaTokens).
	rewardCurrencies = { "Gold", "Gems", "TraitShards" },
	-- Kunci tampilan untuk XP Battle Pass di peta reward (hanya saat musim aktif).
	battlePassXpRewardKey = "BattlePassXP",
})
