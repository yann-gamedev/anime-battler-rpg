--!strict
local Units = require(game:GetService("ReplicatedStorage").Shared.Config.Units)
local Controls = require(script.Parent.Components.Controls)
local Page = require(script.Parent.ProgressPage)
local Remote = require(script.Parent.MonetizationRemote)
local Theme = require(script.Parent.Theme)

local View = {}

function View.utc(timestamp: number): string
	return os.date("!%d %b %Y, %H:%M UTC", math.floor(timestamp)) :: string
end

function View.unitName(id: string): string
	local unit = Units[id]
	return if unit then unit.name else id
end

local function describe(reward: Remote.Reward): string
	if reward.kind == "Currency" then
		return string.format("%d %s", reward.amount or 0, reward.id or "")
	elseif reward.kind == "Skin" then
		return "Skin entitlement: " .. (reward.id or "Season skin")
	end
	local names = {}
	for _, id in reward.options or {} do
		table.insert(names, View.unitName(id))
	end
	return "Choose one unit: " .. table.concat(names, ", ")
end

function View.tiers(page: Page.Page, info: Remote.PassInfo, track: Remote.Track, claim: (number, { string }?) -> ()): ()
	for _, tier in info.tiers do
		local heading = Page.label(page.body, "Tier " .. tier.tier)
		heading.Font = Theme.bold
		local free = track == "Free"
		local rewards = if free then tier.free else tier.premium
		local options: { string }?
		for _, reward in rewards do
			Page.label(page.body, describe(reward))
			if reward.kind == "UnitChoice" then
				options = reward.options
			end
		end
		local claimed = if free then tier.freeClaimed else tier.premiumClaimed
		local label = if claimed
			then "Claimed"
			elseif #rewards == 0 then "No reward"
			elseif not info.active then "Season inactive"
			elseif tier.tier > info.unlockedTier then "Locked"
			elseif not free and not info.premium then "Premium required"
			else nil
		if #rewards > 0 then
			local button = Page.button(
				page.body,
				label or (if options then "Choose & claim" else "Claim reward"),
				function()
					if not label then
						claim(tier.tier, options)
					end
				end
			)
			Controls.setEnabled(button, label == nil)
		else
			Page.label(page.body, label or "No reward")
		end
	end
end

return table.freeze(View)
