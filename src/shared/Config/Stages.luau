--!strict
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local Economy = require(script.Parent.Economy)

local enemiesByChapter =
	{ { "brutus", "dorin", "mira" }, { "garrick", "nyx", "elodie" }, { "umbra", "valka", "aurelian" } }
local stagesPerChapter = 10
local chapters: { { Types.StageDef } } = {}
local byId: { [string]: Types.StageDef } = {}

for chapterIndex, enemyIds in enemiesByChapter do
	local chapter: { Types.StageDef } = {}
	for stageIndex = 1, stagesPerChapter do
		local id = `{chapterIndex}-{stageIndex}`
		local level = (chapterIndex - 1) * stagesPerChapter + stageIndex
		local enemies: { { unitId: string, slot: number, level: number, stars: number } } = {}
		for slot, unitId in enemyIds do
			enemies[slot] = { unitId = unitId, slot = slot, level = level, stars = 1 }
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
	end
	chapters[chapterIndex] = chapter
end

return TableUtil.deepFreeze({ chapters = chapters, byId = byId })
