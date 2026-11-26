--!strict
-- Boss Raid harian (prompt 10, docs/GDD.md §7, docs/ECONOMY.md §3). BASELINE PLACEHOLDER untuk balancing.
-- 1 percobaan gratis per hari UTC, tidak bisa dibeli. Reward = tier tertinggi yang dicapai damage percobaan
-- itu (damage dikreditkan maksimal bossMaxHp). Target ekonomi tier puncak ≈ 50 Gems/hari (gemsIncomeTargets.dailyRaid).
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type RaidTierDef = { minHpFraction: number, rewards: Types.RewardMap }
export type BossDef = {
	id: string,
	name: string,
	-- Rig/stat dasar dari Config/Units (replay memakai unitId ini). Placeholder sampai model boss dibuat.
	unitId: string,
	level: number,
	stars: number,
	cell: number, -- sel 1..9 tim B (2 = tengah baris depan)
	hpMultiplier: number, -- HP besar: HP unit × multiplier di BattleSim
}

local boss: BossDef = {
	id = "arcanum_rune_golem",
	name = "Rune Golem of Arcanum",
	unitId = "garrick",
	level = 10,
	stars = 1,
	cell = 2,
	hpMultiplier = 200,
}

-- Urut naik. minDamage tiap tier = ceil(minHpFraction × bossMaxHp), minimal 1.
local tiers: { RaidTierDef } = {
	{ minHpFraction = 0, rewards = { Gold = 300, Gems = 15 } },
	{ minHpFraction = 0.05, rewards = { Gold = 600, Gems = 25 } },
	{ minHpFraction = 0.15, rewards = { Gold = 1000, Gems = 35, TraitShards = 1 } },
	{ minHpFraction = 0.3, rewards = { Gold = 1500, Gems = 45, TraitShards = 2 } },
	{ minHpFraction = 0.5, rewards = { Gold = 2000, Gems = 50, TraitShards = 3 } },
}

return TableUtil.deepFreeze({
	boss = boss,
	tiers = tiers,
	-- Raid terbuka setelah onboarding selesai (flags.tutorialDone, sama dengan lobby: menang 1-3).
	requiresTutorialDone = true,
})
