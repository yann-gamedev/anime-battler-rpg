--!strict
-- Angka progres story & inventory (prompts/06-story-progression.md).
-- Semua nilai yang TIDAK tercantum di docs/ECONOMY.md adalah PLACEHOLDER dan menunggu pass balancing.
-- Angka ekonomi yang sudah ada (levelCost, mergeDuplicates, dismantleRewards, firstThreeStarGems,
-- replayGoldSoftCap) tetap dibaca dari Config/Economy.luau.
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type BoardUnlock = { stageId: string, maxUnits: number }

local Progression = {
	-- Stage khusus onboarding (GDD §11 langkah 2). Tidak masuk story.cleared.
	TUTORIAL_STAGE_ID = "tutorial",
	-- Kemenangan stage ini menyelesaikan onboarding (flags.tutorialDone, lobby terbuka).
	ONBOARDING_FINAL_STAGE_ID = "1-3",
	-- Hadiah tutorial sekali saja (ECONOMY §1: Summon Tickets dari tutorial).
	TUTORIAL_SUMMON_TICKETS = 10,
	-- Sel papan starter saat tutorial jika tim tersimpan masih kosong (1–3 = baris depan).
	TUTORIAL_STARTER_CELLS = { kael = 5, pip = 2, mira = 8 } :: { [string]: number },

	-- Bintang: 3★ tanpa korban, 2★ korban ≤ TWO_STAR_MAX_CASUALTIES, 1★ menang.
	TWO_STAR_MAX_CASUALTIES = 2,

	-- accountLevel = BASE + PER_STAGE × jumlah stage story berbeda yang sudah dimenangkan.
	ACCOUNT_LEVEL_BASE = 1,
	ACCOUNT_LEVEL_PER_STAGE = 1,

	-- PLACEHOLDER: slot papan terbuka lewat clear stage (GDD §6, bukan pembelian).
	BOARD_UNLOCKS = {
		{ stageId = "1-5", maxUnits = 4 },
		{ stageId = "2-5", maxUnits = 5 },
		{ stageId = "3-5", maxUnits = 6 },
	} :: { BoardUnlock },

	-- PLACEHOLDER: reward per kemenangan stage. n = urutan stage 1..30.
	-- Gold = STAGE_GOLD_BASE + STAGE_GOLD_PER_STAGE × (n - 1)
	STAGE_GOLD_BASE = 100,
	STAGE_GOLD_PER_STAGE = 20,
	-- XP Scroll = STAGE_XP_SCROLLS_BASE + floor((n - 1) / STAGE_XP_SCROLLS_STEP)
	STAGE_XP_SCROLLS_BASE = 2,
	STAGE_XP_SCROLLS_STEP = 10,

	-- PLACEHOLDER: XP Scroll per kenaikan level n → n+1 = BASE + floor((n - 1) / STEP).
	LEVEL_XP_SCROLLS_BASE = 1,
	LEVEL_XP_SCROLLS_STEP = 10,

	-- PLACEHOLDER: biaya Gold merge, diindeks bintang target saat ini (1★→2★ … 4★→5★).
	MERGE_GOLD = { 500, 1500, 4000, 10000 } :: { number },

	-- Batas jumlah UID per permintaan bulk (DoS & validasi).
	DISMANTLE_MAX_UNITS = 50,

	-- Rolling counter replay harian memakai hari UTC: floor(os.time() / SECONDS_PER_DAY).
	SECONDS_PER_DAY = 86400,
}

return TableUtil.deepFreeze(Progression)
