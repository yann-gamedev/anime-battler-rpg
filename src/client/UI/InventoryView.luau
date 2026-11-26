--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Config.Progression)
local Units = require(Shared.Config.Units)
local InventoryDetail = require(script.Parent.InventoryDetail)
local Page = require(script.Parent.ProgressPage)
local Remote = require(script.Parent.ProgressRemote)
local Controls = require(script.Parent.Components.Controls)
local Modal = require(script.Parent.Components.Modal)
local UnitCard = require(script.Parent.Components.UnitCard)
local Theme = require(script.Parent.Theme)
local UIController = require(script.Parent.Parent.Controllers.UIController)

export type State = {
	uid: string?,
	mode: string?,
	confirm: boolean,
	selected: { [string]: boolean },
	filters: { [string]: string },
	scroll: Vector2,
	focusUid: string?,
}

local InventoryView = {}
local TEAM_INDEX = 1
local FILTERS = {
	{ "Element", "Api", "Es", "Petir", "Cahaya", "Bayangan" },
	{ "Rarity", "Rare", "Epic", "Legendary", "Mythic" },
	{ "Status", "Murid", "Familiar", "Profesor" },
	{ "Sort", "Level", "Stars", "Rarity" },
}

function InventoryView.new(): State
	return { confirm = false, selected = {}, filters = {}, scroll = Vector2.zero }
end

function InventoryView.back(state: State): boolean
	if state.confirm and state.mode ~= "single" then
		state.confirm = false
	elseif state.mode then
		state.mode = nil
		state.confirm = false
		table.clear(state.selected)
	elseif state.uid then
		state.uid = nil
	else
		return false
	end
	return true
end

local function choices(parent: PlayerGui, options: { string }, state: State, refresh: (boolean?) -> ()): ()
	local key = options[1]
	local entries: { Modal.Choice } = { { label = if key == "Sort" then "Name" else "All" } }
	for index = 2, #options do
		table.insert(entries, { label = options[index], value = options[index] })
	end
	local modal: Modal.View
	local restore: () -> ()
	local function close()
		restore()
		modal.screen:Destroy()
	end
	modal = Modal.create(parent, key, entries, state.filters[key], function(value)
		state.filters[key] = value
		close()
		refresh()
	end, close)
	restore = UIController.overlay(modal.screen, modal.first)
end

function InventoryView.render(
	page: Page.Page,
	snapshot: Remote.Snapshot,
	state: State,
	onAction: (string, ...any) -> (),
	refresh: (boolean?) -> ()
): TextButton?
	local body = page.body
	local saved: { [string]: boolean } = {}
	local slots: { [string]: number } = {}
	for index, team in snapshot.teams do
		for cell, uid in team.slots do
			if uid ~= "" then
				saved[uid] = true
				if index == TEAM_INDEX then
					slots[uid] = cell
				end
			end
		end
	end
	local target = if state.uid then snapshot.units[state.uid] else nil
	if state.uid and not target then
		state.uid = nil
		state.mode = nil
		state.confirm = false
		table.clear(state.selected)
	end
	if target and not state.mode then
		return InventoryDetail.render(body, snapshot, target, TEAM_INDEX, onAction, function(mode)
			state.mode = mode
			table.clear(state.selected)
			state.confirm = mode == "single"
			if state.confirm then
				state.selected[target.uid] = true
			end
			refresh()
		end, saved[target.uid] == true)
	end

	local mode = state.mode
	local required = if mode == "merge" and target then Economy.mergeDuplicates[target.stars] else nil
	local function eligible(unit: Types.ClientOwnedUnit): boolean
		if unit.locked or saved[unit.uid] then
			return false
		end
		if mode == "merge" then
			return target ~= nil and unit.uid ~= target.uid and unit.unitId == target.unitId
		end
		return Units[unit.unitId].rarity ~= "Mythic"
	end
	local selected: { string } = {}
	for uid in state.selected do
		local unit = snapshot.units[uid]
		if unit and eligible(unit) then
			table.insert(selected, uid)
		else
			state.selected[uid] = nil
		end
	end
	table.sort(selected)

	if mode and state.confirm then
		local mergeGold = if mode == "merge" and target and required then Progression.MERGE_GOLD[target.stars] else nil
		local gold = snapshot.currencies.Gold
		local canConfirm = #selected > 0
			and (mode ~= "merge" or (#selected == required and mergeGold ~= nil and gold >= mergeGold))
		Page.label(
			body,
			if mode == "merge" and target
				then string.format("Upgrade %s to %d★?", Units[target.unitId].name, target.stars + 1)
				else "Dismantle selected units?"
		)
		if mergeGold then
			Page.label(body, string.format("Gold consumed: %d · Balance: %d", mergeGold, gold))
			if gold < mergeGold then
				Page.label(body, string.format("You need %d more Gold.", mergeGold - gold))
			end
		end
		Page.label(body, "These units will be permanently removed.")
		for _, uid in selected do
			Page.label(body, InventoryDetail.describeUnit(snapshot.units[uid]) .. " · " .. uid)
		end
		local cancel = Page.button(body, "Cancel", function()
			InventoryView.back(state)
			refresh()
		end)
		local confirm = Page.button(body, if mode == "merge" then "Confirm merge" else "Confirm dismantle", function()
			if not canConfirm then
				return
			end
			if mode == "merge" and target then
				onAction("MergeUnit", target.uid, selected)
			else
				onAction("DismantleUnit", selected)
			end
		end)
		Controls.setEnabled(confirm, canConfirm)
		return cancel
	end

	local first: TextButton? = nil
	if mode then
		Page.label(
			body,
			if required
				then string.format("Choose %d duplicate(s) · %d selected", required, #selected)
				else string.format("Choose units to dismantle · %d selected", #selected)
		)
		first = Page.button(body, "Review selected units", function()
			state.confirm = true
			refresh()
		end)
		Controls.setEnabled(first, #selected > 0 and (mode ~= "merge" or #selected == required))
		if not first.Selectable then
			first = nil
		end
	else
		local progression = snapshot.progression
		Page.label(
			body,
			string.format(
				"Gold %d · XP Scrolls %s · Trait Shards %d",
				snapshot.currencies.Gold,
				if progression then tostring(progression.xpScrolls) else "Unavailable",
				snapshot.currencies.TraitShards
			)
		)
		local filters = Page.grid(body, 115, Theme.touch)
		for _, options in FILTERS do
			local name = options[1]
			local button = Page.button(filters, state.filters[name] or name, function()
				choices(page.screen.Parent :: PlayerGui, options, state, refresh)
			end)
			first = first or button
		end
		Page.button(body, "Select units to dismantle", function()
			state.scroll = body.CanvasPosition
			state.mode = "batch"
			refresh()
		end)
	end

	local roster: { Types.ClientOwnedUnit } = {}
	for _, unit in snapshot.units do
		local def = Units[unit.unitId]
		local filters = state.filters
		if
			(mode and eligible(unit))
			or (
				not mode
				and (not filters.Element or def.element == filters.Element)
				and (not filters.Rarity or def.rarity == filters.Rarity)
				and (not filters.Status or def.status == filters.Status)
			)
		then
			table.insert(roster, unit)
		end
	end
	local sort = state.filters.Sort
	table.sort(roster, function(a, b)
		if sort == "Level" and a.level ~= b.level then
			return a.level > b.level
		elseif sort == "Stars" and a.stars ~= b.stars then
			return a.stars > b.stars
		elseif sort == "Rarity" and Units[a.unitId].rarity ~= Units[b.unitId].rarity then
			return Economy.rarityMultipliers[Units[a.unitId].rarity] > Economy.rarityMultipliers[Units[b.unitId].rarity]
		end
		local nameA, nameB = Units[a.unitId].name, Units[b.unitId].name
		return if nameA == nameB then a.uid < b.uid else nameA < nameB
	end)
	if #roster == 0 then
		Page.label(body, if mode then "No eligible units." else "No units match these filters.")
	end
	local grid = Page.grid(body, 245, Theme.cardHeight)
	local focused: TextButton? = nil
	for order, unit in roster do
		local def = Units[unit.unitId]
		local card = UnitCard.create(grid)
		card.button.LayoutOrder = order
		UnitCard.update(card, {
			uid = unit.uid,
			unitId = unit.unitId,
			name = def.name,
			level = unit.level,
			stars = unit.stars,
			element = def.element,
			rarity = def.rarity,
			status = def.status,
		}, slots[unit.uid], state.selected[unit.uid] == true, true)
		if unit.locked then
			card.title.Text = "Locked · " .. card.title.Text
		end
		card.button.Activated:Connect(function()
			if mode then
				if required and not state.selected[unit.uid] and #selected >= required then
					return
				end
				state.selected[unit.uid] = if state.selected[unit.uid] then nil else true
				state.focusUid = unit.uid
			else
				state.scroll = body.CanvasPosition
				state.uid = unit.uid
			end
			refresh(mode ~= nil)
		end)
		if state.focusUid == unit.uid then
			focused = card.button
		end
		first = first or card.button
	end
	state.focusUid = nil
	return focused or first
end

return table.freeze(InventoryView)
