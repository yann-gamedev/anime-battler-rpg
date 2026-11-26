--!strict
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local rarityMultipliers: { [Types.Rarity]: number } = { Rare = 1, Epic = 1.25, Legendary = 1.55, Mythic = 1.9 }
local Economy = {
	rarityMultipliers = rarityMultipliers,
	starStatBonus = 0.2,
	levelStatBonus = 0.03,
	levelGoldBase = 50,
	levelGoldExponent = 1.5,
	mergeDuplicates = { 1, 2, 3, 4 }, -- indexed by current stars
	dismantleRewards = {
		Rare = { Gold = 200 },
		Epic = { Gold = 600, TraitShards = 1 },
		Legendary = { Gold = 2000, TraitShards = 5 },
	},
	summonGems = { [1] = 50, [10] = 450 },
	summonTicketsPerRoll = 1,
	traitShardsPerReroll = 1,
	firstThreeStarGems = 30,
	replayGoldSoftCap = { replaysPerDay = 30, goldMultiplier = 0.5 },
	gemsIncomeTargets = { dailyLogin = 20, dailyQuests = 120, dailyRaid = 50, weeklyQuests = 400 },
	battlePass = { seasonDays = 28, tiers = 30, freeGemsTarget = 1000 },
}

function Economy.levelCost(level: number): number
	return math.round(Economy.levelGoldBase * level ^ Economy.levelGoldExponent)
end

function Economy.starMultiplier(stars: number): number
	return 1 + Economy.starStatBonus * (stars - 1)
end

return TableUtil.deepFreeze(Economy)
