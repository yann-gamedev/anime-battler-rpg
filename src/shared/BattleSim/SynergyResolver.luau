--!strict
local Types = require(script.Parent.Parent.Types)
local Synergies = require(script.Parent.Parent.Config.Synergies)
local Units = require(script.Parent.Parent.Config.Units)

export type Active = {
	elements: { [Types.Element]: Types.SynergyDef? },
	statuses: { [Types.Status]: Types.SynergyDef? },
}

local SynergyResolver = {}

local function bestTier(tiers: { Types.SynergyDef }, count: number): Types.SynergyDef?
	local result: Types.SynergyDef? = nil
	for _, tier in tiers do
		if count >= tier.count then
			result = tier
		end
	end
	return result
end

function SynergyResolver.resolve(team: { Types.BattleUnitInput }): Active
	local seen: { [string]: boolean } = {}
	local elements: { [Types.Element]: number } = {}
	local statuses: { [Types.Status]: number } = {}
	for _, member in team do
		if not seen[member.unitId] then
			seen[member.unitId] = true
			local unit = assert(Units[member.unitId], `Unknown unit {member.unitId}`)
			elements[unit.element] = (elements[unit.element] or 0) + 1
			statuses[unit.status] = (statuses[unit.status] or 0) + 1
		end
	end
	local active: Active = { elements = {}, statuses = {} }
	for element, tiers in Synergies.elements do
		active.elements[element] = bestTier(tiers, elements[element] or 0)
	end
	for status, tiers in Synergies.statuses do
		active.statuses[status] = bestTier(tiers, statuses[status] or 0)
	end
	return active
end

return table.freeze(SynergyResolver)
