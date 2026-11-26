--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Traits = require(Shared.Config.Traits)
local UIController = require(script.Parent.Parent.Controllers.UIController)
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
			state.errorCode = if snapshot then "ODDS_CHANGED" else "UNAVAILABLE"
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

function TraitView.confirmReroll(parent: Instance, traitId: string?, cost: number, onConfirm: () -> ()): ()
	local current = traitId and definitions[traitId]
	if not current or current.tier == "Common" or current.tier == "Uncommon" then
		onConfirm()
		return
	end
	local modal: Modal.View
	local restore: () -> ()
	local closed = false
	local function close()
		restore()
		modal.screen:Destroy()
	end
	modal = Modal.create(parent, "Replace trait?", { { label = "Confirm reroll", value = "reroll" } }, nil, function()
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
		body = {
			string.format("Your current trait, %s, will be lost. Spend %d Trait Shards?", current.def.name, cost),
		},
		closeText = "Cancel",
	})
	restore = UIController.overlay(modal.screen, modal.first)
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
		Page.label(body, if state.pending then "Loading trait odds…" else TraitRemote.message(state.errorCode))
		if not state.pending then
			Page.button(body, "Refresh trait odds", function()
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
	elseif info.restricted then
		Page.label(body, TraitRemote.message("RESTRICTED_REGION"))
	elseif info.locked then
		Page.label(body, TraitRemote.message("UNIT_LOCKED"))
	elseif info.shards < info.cost then
		Page.label(body, TraitRemote.message("NOT_ENOUGH_TRAIT_SHARDS"))
	else
		Page.button(body, "Reroll trait", function()
			local screen = body:FindFirstAncestorOfClass("ScreenGui")
			local parent = screen and screen.Parent
			if screen and screen.Enabled and parent and state.info == info and not state.pending then
				TraitView.confirmReroll(parent, unit.trait, info.cost, function()
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
