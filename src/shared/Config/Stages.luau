--!strict
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local Economy = require(script.Parent.Economy)

type EnemyDef = { unitId: string, slot: number, level: number, stars: number }

local enemiesByChapter =
	{ { "brutus", "dorin", "mira" }, { "garrick", "nyx", "elodie" }, { "umbra", "valka", "aurelian" } }
-- Musuh placeholder ringan untuk awal bab 1 agar tiga starter bisa maju (onboarding GDD §11).
-- Stage yang tidak tercantum memakai seluruh musuh bab dengan level = urutan stage (D-011).
local lightEnemies: { [string]: { EnemyDef } } = {
	["1-1"] = { { unitId = "dorin", slot = 2, level = 1, stars = 1 } },
	["1-2"] = {
		{ unitId = "dorin", slot = 1, level = 1, stars = 1 },
		{ unitId = "mira", slot = 5, level = 1, stars = 1 },
	},
	["1-3"] = {
		{ unitId = "brutus", slot = 2, level = 1, stars = 1 },
		{ unitId = "dorin", slot = 1, level = 1, stars = 1 },
	},
}
local stagesPerChapter = 10
local chapters: { { Types.StageDef } } = {}
local byId: { [string]: Types.StageDef } = {}
-- Urutan unlock berurutan: 1-1 … 3-10.
local order: { string } = {}

for chapterIndex, enemyIds in enemiesByChapter do
	local chapter: { Types.StageDef } = {}
	for stageIndex = 1, stagesPerChapter do
		local id = `{chapterIndex}-{stageIndex}`
		local level = (chapterIndex - 1) * stagesPerChapter + stageIndex
		local enemies: { EnemyDef } = {}
		if lightEnemies[id] then
			for slot, enemy in lightEnemies[id] do
				enemies[slot] = table.clone(enemy)
			end
		else
			for slot, unitId in enemyIds do
				enemies[slot] = { unitId = unitId, slot = slot, level = level, stars = 1 }
			end
		end
		local stage: Types.StageDef = {
			id = id,
			chapter = chapterIndex,
			index = stageIndex,
			enemies = enemies,
			firstThreeStarGems = Economy.firstThreeStarGems,
		}
		chapter[stageIndex] = stage
		byId[id] = stage
		table.insert(order, id)
	end
	chapters[chapterIndex] = chapter
end

-- Battle tutorial (stageId khusus "tutorial"): satu musuh ringan, tanpa Gems first-clear.
local tutorial: Types.StageDef = {
	id = "tutorial",
	chapter = 0,
	index = 0,
	enemies = { { unitId = "brutus", slot = 2, level = 1, stars = 1 } },
	firstThreeStarGems = 0,
}

return TableUtil.deepFreeze({ chapters = chapters, byId = byId, order = order, tutorial = tutorial })
