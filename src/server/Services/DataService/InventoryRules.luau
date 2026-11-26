--!strict
-- Aturan murni inventory yang memutasi DRAFT profil (salinan). Semua cek dilakukan sebelum mutasi pertama,
-- dan DataService.Progress hanya meng-commit draft bila tidak ada kode error, sehingga bahan tidak pernah
-- hilang saat validasi gagal. Tidak boleh yield.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Config.Progression)
local Units = require(Shared.Config.Units)
local ProgressionRules = require(Shared.ProgressionRules)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local StoryRules = require(script.Parent.StoryRules)

type Outcome = StoryRules.Outcome

local InventoryRules = {}

function InventoryRules.isInAnyTeam(profile: Types.Profile, uid: string): boolean
	for _, team in profile.teams do
		if table.find(team.slots, uid) then
			return true
		end
	end
	return false
end

-- Cek UID untuk dikonsumsi/dikunci: dimiliki, tidak locked, tidak di tim mana pun.
local function checkFree(profile: Types.Profile, uid: string): (string?, Types.OwnedUnit?)
	local unit = profile.units[uid]
	if not unit then
		return "UNIT_NOT_OWNED", nil
	end
	if unit.locked then
		return "UNIT_LOCKED", nil
	end
	if InventoryRules.isInAnyTeam(profile, uid) then
		return "UNIT_IN_TEAM", nil
	end
	return nil, unit
end

local function removeUnit(profile: Types.Profile, uid: string): ()
	profile.units[uid] = nil
	profile.equippedSkins[uid] = nil
end

function InventoryRules.levelUp(profile: Types.Profile, uid: string, levels: number): (string?, Outcome?)
	local unit = profile.units[uid]
	if not unit then
		return "UNIT_NOT_OWNED", nil
	end
	if not Validate.isIntInRange(levels, 1, Constants.UNIT_LEVEL_MAX - Constants.UNIT_LEVEL_MIN) then
		return "INVALID_LEVELS", nil
	end
	if unit.level >= Constants.UNIT_LEVEL_MAX then
		return "LEVEL_MAX", nil
	end
	if unit.level + levels > Constants.UNIT_LEVEL_MAX then
		return "LEVEL_EXCEEDS_MAX", nil
	end
	local gold, scrolls = ProgressionRules.levelUpCost(unit.level, levels)
	if profile.materials.XPScrolls < scrolls then
		return "NOT_ENOUGH_XP_SCROLLS", nil
	end
	local outcome = StoryRules.newOutcome()
	local code = StoryRules.changeCurrency(profile, outcome, "Gold", gold, "unit_level_up", true)
	if code then
		return code, nil
	end
	profile.materials.XPScrolls -= scrolls
	unit.level += levels
	outcome.units = true
	return nil, outcome
end

-- materialUids sudah divalidasi bentuknya (array string dense) oleh pemanggil remote.
function InventoryRules.merge(profile: Types.Profile, targetUid: string, materialUids: { string }): (string?, Outcome?)
	local code, target = checkFree(profile, targetUid)
	if code or not target then
		return code, nil
	end
	if target.stars >= Constants.UNIT_STARS_MAX then
		return "STARS_MAX", nil
	end
	local required = Economy.mergeDuplicates[target.stars]
	if #materialUids ~= required then
		return "WRONG_MATERIAL_COUNT", nil
	end
	local seen: { [string]: boolean } = {}
	for _, uid in materialUids do
		if uid == targetUid or seen[uid] then
			return "DUPLICATE_UNIT", nil
		end
		seen[uid] = true
		local materialCode, material = checkFree(profile, uid)
		if materialCode or not material then
			return materialCode, nil
		end
		if material.unitId ~= target.unitId then
			return "UNIT_MISMATCH", nil
		end
	end
	local outcome = StoryRules.newOutcome()
	code = StoryRules.changeCurrency(profile, outcome, "Gold", Progression.MERGE_GOLD[target.stars], "unit_merge", true)
	if code then
		return code, nil
	end
	for _, uid in materialUids do
		removeUnit(profile, uid)
	end
	target.stars += 1
	outcome.units = true
	return nil, outcome
end

function InventoryRules.dismantle(profile: Types.Profile, uids: { string }): (string?, Outcome?)
	if not profile.progress.tutorialBattleCleared then
		return "TUTORIAL_NOT_DONE", nil
	end
	if #uids < 1 or #uids > Progression.DISMANTLE_MAX_UNITS then
		return "INVALID_UNITS", nil
	end
	local seen: { [string]: boolean } = {}
	local totals: { [Types.CurrencyKind]: number } = {}
	for _, uid in uids do
		if seen[uid] then
			return "DUPLICATE_UNIT", nil
		end
		seen[uid] = true
		local code, unit = checkFree(profile, uid)
		if code or not unit then
			return code, nil
		end
		local def = Units[unit.unitId]
		local reward = def and (Economy.dismantleRewards :: any)[def.rarity]
		if not reward then
			return "UNIT_NOT_DISMANTLABLE", nil
		end
		for kind, amount in reward :: { [Types.CurrencyKind]: number } do
			totals[kind] = (totals[kind] or 0) + amount
		end
	end
	local outcome = StoryRules.newOutcome()
	for kind, amount in totals do
		local code = StoryRules.changeCurrency(profile, outcome, kind, amount, "unit_dismantle", false)
		if code then
			return code, nil
		end
	end
	for _, uid in uids do
		removeUnit(profile, uid)
	end
	outcome.units = true
	return nil, outcome
end

function InventoryRules.setLocked(profile: Types.Profile, uid: string, locked: boolean): (string?, Outcome?)
	local unit = profile.units[uid]
	if not unit then
		return "UNIT_NOT_OWNED", nil
	end
	if type(locked) ~= "boolean" then
		return "INVALID_LOCKED", nil
	end
	local outcome = StoryRules.newOutcome()
	if unit.locked ~= locked then
		unit.locked = locked
		outcome.units = true
	end
	return nil, outcome
end

return table.freeze(InventoryRules)
