--!strict
local Page = require(script.Parent.ProgressPage)
local Controls = require(script.Parent.Components.Controls)
local Theme = require(script.Parent.Theme)
local Remote = require(script.Parent.SummonRemote)

type Actions = {
	select: (string) -> (),
	odds: (TextButton) -> (),
	summon: (Remote.Count, Remote.Payment) -> (),
	shop: () -> (),
}

local View = {}

local function priceFor(banner: Remote.Banner, count: Remote.Count, payment: Remote.Payment): number
	local prices = banner.prices
	if payment == "Gems" then
		return if count == 1 then prices.gems1 else prices.gems10
	end
	return if count == 1 then prices.tickets1 else prices.tickets10
end

function View.isActive(banner: Remote.Banner, now: number): boolean
	return banner.active
		and (banner.startsAt == nil or now >= banner.startsAt)
		and (banner.endsAt == nil or now < banner.endsAt)
end

function View.blockReason(
	info: Remote.Info,
	banner: Remote.Banner,
	count: Remote.Count,
	payment: Remote.Payment
): string?
	if payment == "Gems" and info.restricted ~= false then
		return "Gem summons unavailable"
	elseif not View.isActive(banner, workspace:GetServerTimeNow()) then
		return "Banner inactive"
	elseif info.capacity.max - info.capacity.used < count then
		return "Inventory space needed"
	end
	local balance = if payment == "Gems" then info.balances.Gems else info.balances.SummonTickets
	return if balance < priceFor(banner, count, payment) then "Insufficient " .. payment else nil
end

function View.balanceText(info: Remote.Info): string
	return string.format(
		"Gems %d · Tickets %d · Units %d/%d",
		info.balances.Gems,
		info.balances.SummonTickets,
		info.capacity.used,
		info.capacity.max
	)
end

local function formatDate(unix: number): string
	return DateTime.fromUnixTimestamp(unix):FormatUniversalTime("DD MMM YYYY HH:mm", "en-us") .. " UTC"
end

local function scheduleText(banner: Remote.Banner): string
	local now = workspace:GetServerTimeNow()
	if banner.endsAt and now >= banner.endsAt then
		return "Ended " .. formatDate(banner.endsAt)
	elseif banner.startsAt and now < banner.startsAt then
		return "Opens " .. formatDate(banner.startsAt)
	elseif banner.active and banner.endsAt then
		return "Active until " .. formatDate(banner.endsAt)
	end
	return if banner.active then "Active" else "Inactive"
end

local function paymentButtons(
	body: ScrollingFrame,
	info: Remote.Info,
	banner: Remote.Banner,
	payment: Remote.Payment,
	actions: Actions
): ()
	local grid = Page.grid(body, 116, Theme.cardHeight)
	for _, count: Remote.Count in { 1, 10 } do
		local reason = View.blockReason(info, banner, count, payment)
		local label = string.format("%d× · %d %s", count, priceFor(banner, count, payment), payment)
		local button = Page.button(grid, if reason then label .. "\n" .. reason else label, function()
			actions.summon(count, payment)
		end)
		button.LayoutOrder = count
		Controls.setEnabled(button, reason == nil)
	end
end

function View.banner(page: Page.Page, info: Remote.Info, banner: Remote.Banner?, actions: Actions): TextButton?
	local body = page.body
	if not banner then
		Page.label(body, "No banners are available.")
		return if info.restricted then Page.button(body, "Academy Shop", actions.shop) else nil
	end

	local selectors = Page.grid(body, 104, Theme.touch)
	for index, option in info.banners do
		local button = Page.button(selectors, option.kind, function()
			actions.select(option.id)
		end)
		button.LayoutOrder = index
		if option == banner then
			button.BackgroundColor3 = Theme.accent
		end
	end

	local schedule = Page.label(body, banner.kind .. " · " .. scheduleText(banner))
	schedule.Font = Theme.bold
	if banner.featuredUnitId then
		for _, unit in banner.odds.base.units do
			if unit.unitId == banner.featuredUnitId then
				local featured = Page.label(body, "Featured · " .. unit.name)
				featured.TextColor3 = Theme.rarity[unit.rarity] or Theme.text
				break
			end
		end
	end
	Page.label(body, View.balanceText(info))

	local odds: TextButton
	odds = Page.button(body, "View odds", function()
		actions.odds(odds)
	end)
	paymentButtons(body, info, banner, "Tickets", actions)
	if info.restricted == false then
		paymentButtons(body, info, banner, "Gems", actions)
	else
		Page.label(body, "Gem summons are unavailable. Free Summon Tickets can still be used.")
		Page.button(body, "Academy Shop", actions.shop)
	end

	local pity = banner.pity
	Page.label(
		body,
		string.format(
			"Pity · Legendary+ %d/%d · Mythic %d/%d",
			pity.sinceLegendary,
			pity.legendaryPlusRolls,
			pity.sinceMythic,
			pity.mythicRolls
		)
	)
	if pity.guaranteedFeatured then
		Page.label(body, "Your next Mythic on this banner is guaranteed to be featured.")
	end
	return odds
end

return table.freeze(View)
