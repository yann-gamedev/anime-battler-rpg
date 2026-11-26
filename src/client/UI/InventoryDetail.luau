--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Economy = require(Shared.Config.Economy)
local ProgressionRules = require(Shared.ProgressionRules)
local Units = require(Shared.Config.Units)
local Stats = require(Shared.BattleSim.Stats)
local SynergyResolver = require(Shared.BattleSim.SynergyResolver)
local Page = require(script.Parent.ProgressPage)
local Remote = require(script.Parent.ProgressRemote)
local TeamBoardView = require(script.Parent.TeamBoardView)
local Controls = require(script.Parent.Components.Controls)

local InventoryDetail = {}

function InventoryDetail.describeUnit(unit: Types.ClientOwnedUnit, teamSlot: number?): string
	return string.format(
		"%s · Lv %d · %d★%s%s",
		Units[unit.unitId].name,
		unit.level,
		unit.stars,
		if unit.locked then " · Locked" else "",
		if teamSlot then " · Slot " .. teamSlot else ""
	)
end

function InventoryDetail.render(
	body: ScrollingFrame,
	snapshot: Remote.Snapshot,
	unit: Types.ClientOwnedUnit,
	teamIndex: number,
	onAction: (string, ...any) -> (),
	onSelect: (string) -> (),
	inTeam: boolean
): TextButton
	local def = Units[unit.unitId]
	Page.label(body, InventoryDetail.describeUnit(unit))
	Page.label(body, string.format("%s · %s · %s · %s", def.rarity, def.element, def.status, def.class))
	local members: { Types.BattleUnitInput } = {}
	local selectedCell: number? = nil
	local team = snapshot.teams[teamIndex]
	if team then
		for cell, uid in team.slots do
			local member = snapshot.units[uid]
			if member then
				table.insert(members, {
					unitId = member.unitId,
					stars = member.stars,
					level = member.level,
					trait = member.trait,
					cell = cell,
				})
				if uid == unit.uid then
					selectedCell = cell
				end
			end
		end
	end
	local active = SynergyResolver.resolve(members)
	local stats = Stats.compute({
		unitId = unit.unitId,
		stars = unit.stars,
		level = unit.level,
		trait = unit.trait,
		cell = selectedCell or 1,
	}, if selectedCell then active else SynergyResolver.resolve({}))
	Page.label(
		body,
		string.format(
			"%s\nHP %d · ATK %d · DEF %d\nAttack speed %.2f · Range %d\nCrit %.1f%% · Crit damage %.0f%% · Mana gain %.0f%%",
			if selectedCell then "Saved team stats" else "Undeployed stats",
			math.round(stats.hp),
			math.round(stats.atk),
			math.round(stats.def),
			stats.spd,
			stats.range,
			stats.critChance * 100,
			stats.critDamage * 100,
			stats.manaGain * 100
		)
	)
	local synergies = TeamBoardView.describeSynergies(active)
	Page.label(body, "Saved team synergies\n" .. (if synergies == "" then "None active" else synergies))
	local ultimate = string.gsub(def.ultimate, "^[^_]+_", "")
	ultimate = string.gsub(string.gsub(ultimate, "_", " "), "(%a)([%a]*)", function(first, rest)
		return string.upper(first) .. rest
	end)
	Page.label(
		body,
		"Ultimate · " .. (if def.ultimate == "seraphine_dawn" then "Rite of the First Dawn" else ultimate)
	)

	local progression = snapshot.progression
	local belowMax = unit.level < Constants.UNIT_LEVEL_MAX
	local gold, scrolls = ProgressionRules.levelUpCost(unit.level, 1)
	local canLevel = belowMax
		and progression ~= nil
		and snapshot.currencies.Gold >= gold
		and progression.xpScrolls >= scrolls
	local level = Page.button(
		body,
		if belowMax
			then string.format("Level up · %d Gold + %d XP Scroll%s", gold, scrolls, if scrolls == 1 then "" else "s")
			else "Maximum level",
		function()
			if canLevel then
				onAction("LevelUpUnit", unit.uid, 1)
			end
		end
	)
	Controls.setEnabled(level, canLevel)
	local lock = Page.button(body, if unit.locked then "Unlock unit" else "Lock unit", function()
		onAction("LockUnit", unit.uid, not unit.locked)
	end)
	local required = Economy.mergeDuplicates[unit.stars]
	local merge = Page.button(
		body,
		if required then string.format("Merge · %d duplicate(s)", required) else "Maximum stars",
		function()
			onSelect("merge")
		end
	)
	Controls.setEnabled(merge, required ~= nil)
	local dismantle = Page.button(body, "Dismantle this unit", function()
		onSelect("single")
	end)
	Controls.setEnabled(dismantle, not unit.locked and not inTeam and def.rarity ~= "Mythic")
	if unit.locked or inTeam or def.rarity == "Mythic" then
		Page.label(body, "Locked, deployed, and Mythic units cannot be dismantled.")
	end
	return lock
end

return table.freeze(InventoryDetail)
