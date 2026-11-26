--!strict
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local Units = require(script.Parent.Units)

local oddsPercent: { [Types.Rarity]: number } = { Rare = 70, Epic = 25, Legendary = 4.5, Mythic = 0.5 }
local unitIds: { string } = {}
for unitId in Units do
	table.insert(unitIds, unitId)
end
table.sort(unitIds)

local definitions: { [string]: Types.BannerDef } = {
	standard = { id = "standard", kind = "Standard", oddsPercent = oddsPercent, unitIds = unitIds },
	-- Seraphine is a standard-pool unit featured on this example banner.
	limited_example = {
		id = "limited_example",
		kind = "Limited",
		oddsPercent = oddsPercent,
		unitIds = unitIds,
		featuredUnitId = "seraphine",
		featuredSharePercent = 50,
		guaranteeFeaturedAfterMiss = true,
		rotationDays = 14,
	},
}

return TableUtil.deepFreeze({
	definitions = definitions,
	pity = { legendaryPlusRolls = 50, mythicRolls = 200 },
	multiSummonGuarantee = { count = 10, minimumRarity = "Epic" },
})
