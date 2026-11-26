--!strict
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local scenario: Types.StageDef = {
	id = "studio_test_battle",
	chapter = 0,
	index = 0,
	firstThreeStarGems = 0,
	enemies = {
		{ unitId = "brutus", slot = 1, level = 1, stars = 1 },
		{ unitId = "dorin", slot = 2, level = 1, stars = 1 },
		{ unitId = "garrick", slot = 3, level = 1, stars = 1 },
		{ unitId = "mira", slot = 4, level = 1, stars = 1 },
		{ unitId = "seraphine", slot = 5, level = 1, stars = 1 },
		{ unitId = "morvaine", slot = 6, level = 1, stars = 1 },
	},
}

return TableUtil.deepFreeze(scenario)
