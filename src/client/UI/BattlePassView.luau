--!strict
local Units = require(game:GetService("ReplicatedStorage").Shared.Config.Units)
local Controls = require(script.Parent.Components.Controls)
local Page = require(script.Parent.ProgressPage)
local Remote = require(script.Parent.MonetizationRemote)
local Theme = require(script.Parent.Theme)

local View = {}
local ACADEMY_FRAME_ID = "s1_academy_frame"
local ACADEMY_FRAME_NAME = "Academy Profile Frame"

function View.utc(timestamp: number): string
	return os.date("!%d %b %Y, %H:%M UTC", math.floor(timestamp)) :: string
end

function View.unitName(id: string): string
	local unit = Units[id]
	return if unit then unit.name else id
end

function View.profileFrame(page: Page.Page, frameId: string?, displayName: string): ()
	if frameId ~= ACADEMY_FRAME_ID then
		return
	end
	local frame = Controls.panel(UDim2.new(1, 0, 0, Theme.touch), page.body)
	frame.Name = "AcademyProfileFrame"
	frame.BackgroundColor3 = Theme.button
	local border = Instance.new("UIStroke")
	border.Color = Theme.rarity.Epic
	border.Thickness = 2
	border.Parent = frame

	local name = Controls.label(displayName, UDim2.new(1, -2 * Theme.padding, 1, 0), frame)
	name.Position = UDim2.fromOffset(Theme.padding, 0)
	name.Font = Theme.bold
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
end

local function describe(reward: Remote.Reward): string
	if reward.kind == "Currency" then
		return string.format("%d %s", reward.amount or 0, reward.id or "")
	elseif reward.kind == "Skin" then
		return "Skin entitlement: " .. (reward.id or "Season skin")
	elseif reward.kind == "ProfileFrame" then
		return if reward.id == ACADEMY_FRAME_ID then ACADEMY_FRAME_NAME else "Profile Frame"
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
