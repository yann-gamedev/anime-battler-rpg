--!strict
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

return TableUtil.deepFreeze({
	observatory = { name = "Menara Astronomi", bonus = { stageGoldMultiplier = 1.05 } },
	library = { name = "Perpustakaan Terlarang", bonus = { unitXpMultiplier = 1.05 } },
	arena = { name = "Arena Duel", bonus = { asramaTokenMultiplier = 1.1 } },
	greenhouse = { name = "Rumah Kaca", bonus = { dailyRaidTraitShards = 1 } },
	bridge = { name = "Jembatan Awan", bonus = { dailyQuestGemsMultiplier = 1.05 } },
	great_hall = { name = "Aula Agung", bonus = { lobbyGuildBanner = true } },
})
