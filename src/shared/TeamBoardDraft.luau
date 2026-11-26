--!strict
local Types = require(script.Parent.Types)
local Constants = require(script.Parent.Config.Constants)
local TeamRules = require(script.Parent.TeamRules)
local SynergyResolver = require(script.Parent.BattleSim.SynergyResolver)

local TeamBoardDraft = {}

function TeamBoardDraft.count(slots: { string }): number
	local count = 0
	for _, uid in slots do
		if uid ~= TeamRules.EMPTY_SLOT then
			count += 1
		end
	end
	return count
end

-- Edits only the local draft. SaveTeam independently validates the finished formation.
function TeamBoardDraft.place(slots: { string }, uid: string, cell: number, maxUnits: number): boolean
	local previous = table.find(slots, uid)
	local target = slots[cell]
	if uid == TeamRules.EMPTY_SLOT or target == nil then
		return false
	end
	if previous == cell then
		slots[cell] = TeamRules.EMPTY_SLOT
	elseif previous then
		slots[previous] = target
		slots[cell] = uid
	elseif target ~= TeamRules.EMPTY_SLOT or TeamBoardDraft.count(slots) < maxUnits then
		slots[cell] = uid
	else
		return false
	end
	return true
end

function TeamBoardDraft.matches(unit: Types.TeamBoardUnit, element: string?, rarity: string?): boolean
	return (element == nil or unit.element == element) and (rarity == nil or unit.rarity == rarity)
end

function TeamBoardDraft.synergies(slots: { string }, byUid: { [string]: Types.TeamBoardUnit }): SynergyResolver.Active
	local members: { Types.BattleUnitInput } = {}
	for cell = 1, Constants.BOARD_SLOTS do
		local unit = byUid[slots[cell]]
		if unit then
			table.insert(members, { unitId = unit.unitId, level = unit.level, stars = unit.stars, cell = cell })
		end
	end
	return SynergyResolver.resolve(members)
end

return table.freeze(TeamBoardDraft)
