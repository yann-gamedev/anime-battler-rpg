--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Traits = require(Shared.Config.Traits)
local UIController = require(script.Parent.Parent.Controllers.UIController)
local Controls = require(script.Parent.Components.Controls)
local Modal = require(script.Parent.Components.Modal)
local Page = require(script.Parent.ProgressPage)
local ProgressRemote = require(script.Parent.ProgressRemote)
local TraitRemote = require(script.Parent.TraitRemote)

export type State = {
	uid: string?,
	generation: number,
	info: TraitRemote.Info?,
	errorCode: string?,
	pending: boolean,
}

local TraitView = {}
local definitions: { [string]: { tier: Types.TraitTier, def: Types.TraitDef } } = {}
for tier, entry in Traits.tiers do
	for _, def in entry.traits do
		definitions[def.id] = { tier = tier, def = def }
	end
end

function TraitView.new(): State
	return { generation = 0, pending = false }
end

function TraitView.reset(state: State, uid: string?): ()
	state.uid = uid
	state.generation += 1
	state.info = nil
	state.errorCode = nil
	state.pending = false
end

function TraitView.refresh(
	state: State,
	uid: string,
	isCurrent: () -> boolean,
	apply: (ProgressRemote.Snapshot?) -> ()
): ()
	state.pending = true
	local generation = state.generation
	task.defer(function()
		local snapshot = ProgressRemote.snapshot("GetMyData")
		if generation ~= state.generation or not isCurrent() then
			return
		end
		local info, code = TraitRemote.getInfo(uid)
		if generation ~= state.generation or not isCurrent() then
			return
		end
		state.pending = false
		state.info = nil
		state.errorCode = code
		local unit = snapshot and snapshot.units[uid]
		if info and unit and unit.trait == info.traitId and unit.locked == info.locked then
			state.info = info
		elseif info then
			state.errorCode = if not snapshot
				then "UNAVAILABLE"
				elseif info.restricted then "TRAIT_CHANGED"
				else "ODDS_CHANGED"
		end
		apply(snapshot)
	end)
end

local function percent(value: number): string
	return string.format("%.9g%%", value)
end

local function describe(def: Types.TraitDef): string
	local effects: { string } = {}
	local function bonus(value: number?, label: string)
		if value then
			table.insert(effects, "+" .. percent(value * 100) .. " " .. label)
		end
	end
	bonus(def.hpBonus, "HP")
	bonus(def.atkBonus, "ATK")
	bonus(def.defBonus, "DEF")
	bonus(def.spdBonus, "attack speed")
	bonus(def.manaGainBonus, "mana gain")
	bonus(def.critChanceBonus, "crit chance")
	bonus(def.allStatsBonus, "all stats")
	if def.startingMana then
		table.insert(effects, string.format("Start battle with %d mana", def.startingMana))
	end
	if def.lifesteal then
		table.insert(effects, percent(def.lifesteal * 100) .. " lifesteal")
	end
	if def.repeatUltimateChance then
		table.insert(effects, percent(def.repeatUltimateChance * 100) .. " chance to repeat ultimate")
	end
	if def.freeFirstUltimateAtSeconds then
		table.insert(effects, string.format("Free first ultimate at %gs", def.freeFirstUltimateAtSeconds))
	end
	return table.concat(effects, " · ")
end

local function confirm(parent: Instance, title: string, action: string, details: { string }, onConfirm: () -> ()): ()
	local modal: Modal.View
	local restore: () -> ()
	local closed = false
	local function close()
		restore()
		modal.screen:Destroy()
	end
	modal = Modal.create(parent, title, { { label = action, value = "confirm" } }, nil, function()
		if closed then
			return
		end
		closed = true
		close()
		onConfirm()
	end, function()
		if closed then
			return
		end
		closed = true
		-- Let the same ButtonB input finish before re-enabling the detail screen.
		task.defer(close)
	end, {
		body = details,
		closeText = "Cancel",
	})
	restore = UIController.overlay(modal.screen, modal.first)
end

local function confirmReroll(parent: Instance, traitId: string?, cost: number, onConfirm: () -> ()): ()
	local current = traitId and definitions[traitId]
	if not current or current.tier == "Common" or current.tier == "Uncommon" then
		onConfirm()
		return
	end
	confirm(parent, "Replace trait?", "Confirm reroll", {
		string.format("Your current trait, %s, will be lost. Spend %d Trait Shards?", current.def.name, cost),
	}, onConfirm)
end

local function renderDirect(
	body: ScrollingFrame,
	info: TraitRemote.Info,
	state: State,
	onAction: (string, ...any) -> ()
): ()
	Page.label(body, TraitRemote.message("RESTRICTED_REGION"))
	local direct = info.direct
	if not direct then
		return
	end
	Page.label(body, string.format("Choose a trait · Gold balance %d", direct.gold))
	if state.pending then
		Page.label(body, "Refreshing trait options…")
	elseif info.locked then
		Page.label(body, TraitRemote.message("UNIT_LOCKED"))
	end
	for _, option in direct.options do
		Page.label(body, string.format("%s · %s\n%s", option.name, option.tier, describe(definitions[option.id].def)))
		local status = if option.id == info.traitId
			then " · Equipped"
			elseif direct.gold < option.cost then " · Insufficient Gold"
			else ""
		local enabled = not state.pending and TraitRemote.canSelect(info, option.id)
		local button = Page.button(
			body,
			string.format("Equip %s · %d Gold%s", option.name, option.cost, status),
			function()
				local screen = body:FindFirstAncestorOfClass("ScreenGui")
				local parent = screen and screen.Parent
				if
					not enabled
					or not screen
					or not screen.Enabled
					or not parent
					or state.info ~= info
					or state.pending
				then
					return
				end
				local current = info.traitId and definitions[info.traitId]
				local details = { string.format("Equip %s for %d Gold?", option.name, option.cost) }
				if info.traitId then
					table.insert(
						details,
						string.format(
							"Your current trait, %s, will be lost.",
							if current then current.def.name else info.traitId
						)
					)
				end
				confirm(parent, "Choose trait", "Confirm selection", details, function()
					if state.info == info and not state.pending then
						onAction("SelectRestrictedTrait", info.uid, option.id)
					end
				end)
			end
		)
		Controls.setEnabled(button, enabled)
	end
end

function TraitView.render(
	body: ScrollingFrame,
	unit: Types.ClientOwnedUnit,
	shards: number,
	state: State,
	onAction: (string, ...any) -> ()
): ()
	local current = unit.trait and definitions[unit.trait]
	Page.label(
		body,
		if current
			then "Trait · " .. current.def.name .. " · " .. current.tier .. "\n" .. describe(current.def)
			elseif unit.trait then "Trait · Unknown"
			else "Trait · None"
	)
	local info = state.info
	if not info then
		Page.label(body, string.format("Trait Shards · %d", shards))
		Page.label(body, if state.pending then "Loading trait details…" else TraitRemote.message(state.errorCode))
		if not state.pending then
			Page.button(body, "Refresh trait details", function()
				onAction("RefreshTraitInfo", unit.uid)
			end)
		end
		return
	end
	if info.restricted then
		renderDirect(body, info, state, onAction)
		if not state.pending then
			Page.button(body, "Refresh trait options", function()
				onAction("RefreshTraitInfo", unit.uid)
			end)
		end
		return
	end
	Page.label(body, string.format("Trait Shards · %d balance · %d per reroll", info.shards, info.cost))
	Page.label(
		body,
		string.format(
			"Legendary pity · %d/%d\nAfter %d rerolls without Legendary or Mythic, the next reroll guarantees Legendary. Either tier resets pity.",
			info.pity.sinceLegendary,
			info.pity.rolls,
			info.pity.rolls - 1
		)
	)
	Page.label(body, "Odds for the next reroll")
	for _, tier in info.odds.tiers do
		local rows = { tier.tier .. " · " .. percent(tier.percent) }
		for _, trait in tier.traits do
			table.insert(rows, trait.name .. " · " .. percent(trait.percent))
		end
		Page.label(body, table.concat(rows, "\n"))
	end
	if state.pending then
		Page.label(body, "Refreshing trait odds…")
	elseif info.locked then
		Page.label(body, TraitRemote.message("UNIT_LOCKED"))
	elseif info.shards < info.cost then
		Page.label(body, TraitRemote.message("NOT_ENOUGH_TRAIT_SHARDS"))
	else
		Page.button(body, "Reroll trait", function()
			local screen = body:FindFirstAncestorOfClass("ScreenGui")
			local parent = screen and screen.Parent
			if screen and screen.Enabled and parent and state.info == info and not state.pending then
				confirmReroll(parent, unit.trait, info.cost, function()
					if state.info == info and not state.pending then
						onAction("RerollTrait", unit.uid)
					end
				end)
			end
		end)
	end
	if not state.pending then
		Page.button(body, "Refresh trait odds", function()
			onAction("RefreshTraitInfo", unit.uid)
		end)
	end
end

return table.freeze(TraitView)
