--!strict
-- Validasi config quest, raid, dan lobby saat server boot (dipanggil Config/Validate.run).
local Constants = require(script.Parent.Constants)
local Lobby = require(script.Parent.Lobby)
local Quests = require(script.Parent.Quests)
local Raids = require(script.Parent.Raids)
local Skins = require(script.Parent.Skins)
local Units = require(script.Parent.Units)

local MetaValidate = {}

local function isPositiveInt(value: any): boolean
	return type(value) == "number" and value >= 1 and value < 2 ^ 31 and math.floor(value) == value
end

local function checkRewards(rewards: { [string]: number }, label: string, allowEmpty: boolean): ()
	local count = 0
	for kind, amount in rewards do
		assert(table.find(Quests.rewardCurrencies, kind), `{label}: reward {kind} is not an allowed currency`)
		assert(isPositiveInt(amount), `{label}: reward {kind} must be a positive integer`)
		count += 1
	end
	assert(allowEmpty or count > 0, `{label}: rewards are empty`)
end

function MetaValidate.run(): ()
	local seen: { [string]: boolean } = {}
	local kinds = { story_win = true, story_stars = true, unit_level = true, raid_attempt = true }
	for index, def in Quests.definitions do
		local label = `Quests[{index}]`
		assert(type(def.id) == "string" and def.id ~= "", `{label}: id missing`)
		assert(#def.id <= Quests.maxQuestIdLength, `{label}: id too long`)
		assert(not seen[def.id], `{label}: duplicate id {def.id}`)
		seen[def.id] = true
		assert(Quests.byId[def.id] == def, `{label}: byId mismatch`)
		assert(def.period == "Daily" or def.period == "Weekly", `{label}: bad period`)
		assert(kinds[def.kind], `{label}: unknown kind {def.kind}`)
		assert(isPositiveInt(def.target), `{label}: target must be a positive integer`)
		assert(def.battlePassXp == 0 or isPositiveInt(def.battlePassXp), `{label}: bad battlePassXp`)
		checkRewards(def.rewards, label, false)
	end

	local boss = Raids.boss
	assert(Units[boss.unitId], "Raids.boss: unknown unitId")
	assert(boss.cell >= 1 and boss.cell <= Constants.BOARD_SLOTS, "Raids.boss: bad cell")
	assert(boss.level >= Constants.UNIT_LEVEL_MIN and boss.level <= Constants.UNIT_LEVEL_MAX, "Raids.boss: bad level")
	assert(boss.stars >= Constants.UNIT_STARS_MIN and boss.stars <= Constants.UNIT_STARS_MAX, "Raids.boss: bad stars")
	assert(
		boss.hpMultiplier >= 1 and boss.hpMultiplier <= Constants.BATTLE_HP_MULTIPLIER_MAX,
		"Raids.boss: bad hpMultiplier"
	)
	assert(#Raids.tiers > 0, "Raids: no reward tiers")
	local previous = -1
	for index, tier in Raids.tiers do
		assert(tier.minHpFraction > previous and tier.minHpFraction <= 1, `Raids.tiers[{index}]: must ascend in 0..1`)
		previous = tier.minHpFraction
		checkRewards(tier.rewards, `Raids.tiers[{index}]`, false)
	end

	-- Setiap skin punya placeholder pajangan berbeda; tidak ada style untuk skin yang tidak ada.
	local materials = { SmoothPlastic = true, Fabric = true, Glass = true, Neon = true, Metal = true, Marble = true }
	for skinId in Skins do
		assert(Lobby.skinBodyStyles[skinId], `Lobby.skinBodyStyles: missing style for {skinId}`)
	end
	for skinId, style in Lobby.skinBodyStyles do
		assert(Skins[skinId], `Lobby.skinBodyStyles: unknown skin {skinId}`)
		assert(materials[style.material], `Lobby.skinBodyStyles.{skinId}: unsupported material`)
		assert(style.sizeScale.x > 0 and style.sizeScale.y > 0 and style.sizeScale.z > 0, `{skinId}: bad scale`)
		assert(style.reflectance >= 0 and style.reflectance <= 1, `{skinId}: bad reflectance`)
	end
	assert(materials[Lobby.defaultBodyStyle.material], "Lobby.defaultBodyStyle: unsupported material")
	for element, color in Lobby.elementColors do
		assert(color.r and color.g and color.b, `Lobby.elementColors.{element}: bad color`)
	end
end

return table.freeze(MetaValidate)
