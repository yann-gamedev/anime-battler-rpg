--!strict
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local Units = require(script.Parent.Units)

-- Periode banner memakai detik Unix UTC dan dicek terhadap os.time() server. Standard tidak punya periode.
local SECONDS_PER_DAY = 86400
local LIMITED_EXAMPLE_ROTATION_DAYS = 14
local LIMITED_EXAMPLE_STARTS_AT = 1795651200 -- 2026-11-26 00:00 UTC

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
		rotationDays = LIMITED_EXAMPLE_ROTATION_DAYS,
		startsAt = LIMITED_EXAMPLE_STARTS_AT,
		-- Akhir eksklusif: 2026-12-10 00:00 UTC.
		endsAt = LIMITED_EXAMPLE_STARTS_AT + LIMITED_EXAMPLE_ROTATION_DAYS * SECONDS_PER_DAY,
	},
}

return TableUtil.deepFreeze({
	definitions = definitions,
	pity = { legendaryPlusRolls = 50, mythicRolls = 200 },
	secondsPerDay = SECONDS_PER_DAY,
	multiSummonGuarantee = { count = 10, minimumRarity = "Epic" },
})
