--!strict
-- Nama event & pemetaan analytics (prompt 10, docs/GDD.md §12). Semua nama stabil dan berasal dari server;
-- tidak ada teks buatan pemain. Batas Roblox: ≤ 10 funnel, ≤ 100 nama custom event, ≤ 10 jenis resource,
-- 3 custom field per event, dan 120 + 20 × CCU request per menit (docs AnalyticsService).
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

return TableUtil.deepFreeze({
	-- Funnel onboarding (LogOnboardingFunnelStepEvent): langkah 1..n, sesuai GDD §11.
	onboardingSteps = {
		{ step = 1, name = "ProfileCreated" },
		{ step = 2, name = "TutorialBattleWon" },
		{ step = 3, name = "FirstSummon" },
		{ step = 4, name = "Stage1_1Cleared" },
		{ step = 5, name = "OnboardingDone" },
	},
	-- Stage yang menandai langkah 4.
	firstStoryStageId = "1-1",
	-- Sumber/penggunaan mata uang → transactionType (Enum.AnalyticsEconomyTransactionType.*.Name).
	-- Sumber lain dicatat sebagai "Gameplay".
	transactionTypes = {
		robux_purchase = "IAP",
		academy_shop = "Shop",
		summon = "Shop",
		trait_reroll = "Shop",
		trait_direct = "Shop",
		tutorial_reward = "Onboarding",
		quest_reward = "TimedReward",
		raid_reward = "TimedReward",
	} :: { [string]: string },
	defaultTransactionType = "Gameplay",
	maxSkuLength = 50,
	-- Nama custom event (LogCustomEvent).
	events = {
		summon = "Summon",
		purchase = "RobuxPurchase",
		session = "SessionLength",
		questClaim = "QuestClaimed",
		raidAttempt = "RaidAttempt",
	},
	-- Bucket durasi sesi (detik, batas atas eksklusif) untuk custom field.
	sessionBuckets = {
		{ maxSeconds = 300, label = "lt5m" },
		{ maxSeconds = 900, label = "5to15m" },
		{ maxSeconds = 1800, label = "15to30m" },
		{ maxSeconds = math.huge, label = "30mPlus" },
	},
	-- Anggaran request per menit (sedikit di bawah batas Roblox 120 + 20 × CCU).
	budgetBase = 100,
	budgetPerPlayer = 18,
	budgetWindowSeconds = 60,
	-- Jeda minimum antar warning kegagalan per jenis panggilan.
	failureWarnSeconds = 60,
})
