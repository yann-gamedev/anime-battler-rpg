--!strict
-- Battle Pass (docs/ECONOMY.md §6). BASELINE PLACEHOLDER: angka reward bebas disetel ulang oleh desainer.
-- Musim 28 hari, 30 tier. Track gratis: Gold, Trait Shards, ~1.000 Gems, 1 unit Epic pilihan.
-- Track premium: tambahan Gems, Shards, dan 1 skin musim. Tidak ada unit yang hanya ada di premium.
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local Units = require(script.Parent.Units)

local SECONDS_PER_DAY = 86400
local SEASON_DAYS = 28
local TIER_COUNT = 30
local S1_STARTS_AT = 1795651200 -- 2026-11-26 00:00 UTC

local epicOptions: { string } = {}
for unitId, def in Units do
	if def.rarity == "Epic" then
		table.insert(epicOptions, unitId)
	end
end
table.sort(epicOptions)

local function currency(id: Types.CurrencyKind, amount: number): Types.Reward
	return { kind = "Currency", id = id, amount = amount }
end

-- Baseline musim 1: Gems gratis 100 tiap 3 tier (10 × 100 = 1.000), Shards tiap 10 tier, Gold di tier lain,
-- unit Epic pilihan di tier 25. Premium: Gems di tier non-kelipatan 5, Shards tiap 5 tier, skin di tier 30.
local function buildSeasonOneTiers(): { Types.BattlePassTierDef }
	local tiers: { Types.BattlePassTierDef } = {}
	for tier = 1, TIER_COUNT do
		local free: { Types.Reward } = {}
		local premium: { Types.Reward } = {}
		if tier % 3 == 0 then
			table.insert(free, currency("Gems", 100))
		else
			table.insert(free, currency("Gold", 500))
		end
		if tier % 10 == 0 then
			table.insert(free, currency("TraitShards", 5))
		end
		if tier == 25 then
			local choice: Types.Reward = { kind = "UnitChoice", options = epicOptions }
			table.insert(free, choice)
		end
		if tier == TIER_COUNT then
			local skin: Types.Reward = { kind = "Skin", id = "skin_s1_starfall" }
			table.insert(premium, skin)
		elseif tier % 5 == 0 then
			table.insert(premium, currency("TraitShards", 10))
		else
			table.insert(premium, currency("Gems", 60))
		end
		tiers[tier] = { free = free, premium = premium }
	end
	return tiers
end

local seasons: { Types.BattlePassSeasonDef } = {
	{
		id = "s1",
		startsAt = S1_STARTS_AT,
		endsAt = S1_STARTS_AT + SEASON_DAYS * SECONDS_PER_DAY,
		xpPerTier = 100,
		tiers = buildSeasonOneTiers(),
	},
}

return TableUtil.deepFreeze({
	seasons = seasons,
	seasonDays = SEASON_DAYS,
	tierCount = TIER_COUNT,
	secondsPerDay = SECONDS_PER_DAY,
	-- XP per kemenangan story (termasuk auto-replay; tutorial tidak dihitung).
	storyWinXp = 20,
	-- Batas per panggilan API quest (prompt 10) agar bug pemanggil tidak melompati musim.
	maxQuestXpPerGrant = 500,
	maxSeasonIdLength = 32,
})
