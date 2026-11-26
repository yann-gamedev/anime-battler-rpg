--!strict
local TweenService = game:GetService("TweenService")
local Page = require(script.Parent.ProgressPage)
local Controls = require(script.Parent.Components.Controls)
local Theme = require(script.Parent.Theme)
local Remote = require(script.Parent.SummonRemote)

local Details = {}

local REVEAL_DURATION: { [string]: number } = { Rare = 0.25, Epic = 0.42, Legendary = 0.65, Mythic = 0.9 }

local function percent(value: number): string
	if value == 0 then
		return "0%"
	end
	-- Retain four places beyond the first significant digit for long decimals.
	-- Expand scientific notation so tiny positive outcomes still read as percentages.
	local formatted = string.format("%.4e", value)
	local first, fraction, exponent = string.match(formatted, "^(%d)%.(%d+)e([%+%-]%d+)$")
	local digits = first .. fraction
	local point = 1 + (tonumber(exponent) or 0)
	local decimal = if point <= 0
		then "0." .. string.rep("0", -point) .. digits
		elseif point >= #digits then digits .. string.rep("0", point - #digits)
		else string.sub(digits, 1, point) .. "." .. string.sub(digits, point + 1)
	if string.find(decimal, ".", 1, true) then
		decimal = string.gsub(string.gsub(decimal, "0+$", ""), "%.$", "")
	end
	return decimal .. "%"
end

-- Selectable text lets gamepad users reach every row of the scrolling disclosure.
local function focusRow(body: ScrollingFrame, row: GuiObject, previous: GuiObject): ()
	row.Selectable = true
	previous.NextSelectionDown = row
	row.NextSelectionUp = previous
	row.SelectionGained:Connect(function()
		local top = row.AbsolutePosition.Y - body.AbsolutePosition.Y
		local bottom = top + row.AbsoluteSize.Y
		local offset = if top < 0 then top else math.max(0, bottom - body.AbsoluteWindowSize.Y)
		body.CanvasPosition += Vector2.new(0, offset)
	end)
end

function Details.odds(page: Page.Page, banner: Remote.Banner, position: number, choose: (number) -> ()): TextButton
	local body = page.body
	local batch = position > 0
	local selectors = Page.grid(body, 100, Theme.touch)
	local single = Page.button(selectors, "Single", function()
		choose(0)
	end)
	local ten = Page.button(selectors, "Batch 10×", function()
		choose(if batch then position else 1)
	end)
	local base = Page.button(selectors, "Base", function()
		choose(-1)
	end)
	single.LayoutOrder = 1
	ten.LayoutOrder = 2
	base.LayoutOrder = 3
	local selected = if batch then ten elseif position == -1 then base else single
	selected.BackgroundColor3 = Theme.accent
	local previous: GuiObject = selected

	if batch then
		local positions = Page.grid(body, Theme.touch, Theme.touch)
		for index = 1, 10 do
			local button = Page.button(positions, tostring(index), function()
				choose(index)
			end)
			button.LayoutOrder = index
			if index == position then
				button.BackgroundColor3 = Theme.accent
				selected = button
			end
		end
		previous = selected
		local row = Page.label(
			body,
			string.format(
				"Batch position %d of 10. Each position shows marginal odds before purchase, accounting for pity and guarantees. Earlier results can change the conditional odds of later draws.",
				position
			)
		)
		focusRow(body, row, previous)
		previous = row
	elseif position == -1 then
		local row = Page.label(body, "Reference odds before pity and guarantees.")
		focusRow(body, row, previous)
		previous = row
	end

	local note = Page.label(body, "Percentages are rounded. Displayed probabilities may not total 100%.")
	focusRow(body, note, previous)
	previous = note
	local odds = if batch
		then banner.odds.ten[position]
		elseif position == -1 then banner.odds.base
		else banner.odds.single
	for _, rarity in odds.rarities do
		local row = Page.label(body, rarity.rarity .. " · " .. percent(rarity.percent))
		row.Font = Theme.bold
		row.TextColor3 = Theme.rarity[rarity.rarity] or Theme.text
		focusRow(body, row, previous)
		previous = row
	end
	for _, unit in odds.units do
		local row = Page.label(body, string.format("%s (%s) · %s", unit.name, unit.rarity, percent(unit.percent)))
		focusRow(body, row, previous)
		previous = row
	end
	page.back.NextSelectionDown = selected
	return selected
end

function Details.reveal(
	page: Page.Page,
	rolls: { Remote.Roll },
	index: number,
	nextRoll: () -> (),
	skip: () -> ()
): TextButton
	local roll = rolls[index]
	local skipButton = Page.button(page.body, "Skip to results", skip)
	Page.label(page.body, string.format("Summon %d of %d", index, #rolls))
	local card = Controls.panel(UDim2.new(1, 0, 0, Theme.cardHeight), page.body)
	card.BackgroundTransparency = 0.15
	local name = Controls.label(roll.name .. "\n" .. roll.rarity, UDim2.new(1, -2 * Theme.padding, 1, 0), card)
	name.Position = UDim2.fromOffset(Theme.padding, 0)
	name.TextColor3 = Theme.rarity[roll.rarity] or Theme.text
	name.TextTransparency = 1
	name.Font = Theme.bold
	name.TextSize = Theme.titleSize
	local duration = REVEAL_DURATION[roll.rarity] or REVEAL_DURATION.Rare
	TweenService:Create(name, TweenInfo.new(duration, Enum.EasingStyle.Quad), { TextTransparency = 0 }):Play()
	task.delay(duration + 0.32, nextRoll)
	return skipButton
end

function Details.results(page: Page.Page, rolls: { Remote.Roll }, done: () -> ()): TextButton
	local first = Page.button(page.body, "Back to banner", done)
	local previous: GuiObject = first
	for index, roll in rolls do
		local row = Page.label(page.body, string.format("%d. %s · %s", index, roll.name, roll.rarity))
		row.TextColor3 = Theme.rarity[roll.rarity] or Theme.text
		focusRow(page.body, row, previous)
		previous = row
	end
	page.back.NextSelectionDown = first
	return first
end

return table.freeze(Details)
