--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Config.Constants)
local Types = require(Shared.Types)
local SynergyResolver = require(Shared.BattleSim.SynergyResolver)
local Controls = require(script.Parent.Components.Controls)
local Toast = require(script.Parent.Components.Toast)
local Theme = require(script.Parent.Theme)

local TeamBoardView = {}
local COLUMNS = math.sqrt(Constants.BOARD_SLOTS)

export type View = {
	screen: ScreenGui,
	back: TextButton,
	boardScroll: ScrollingFrame,
	rosterScroll: ScrollingFrame,
	cards: Frame,
	count: TextLabel,
	cells: { TextButton },
	synergy: TextLabel,
	rosterMessage: TextLabel,
	elementFilter: TextButton,
	rarityFilter: TextButton,
	status: TextLabel,
	save: TextButton,
	play: TextButton,
}

local function flowFrame(parent: Instance, height: number, order: number): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = order
	frame.Parent = parent
	return frame
end

local function heading(text: string, parent: Instance, order: number): TextLabel
	local label = Controls.label(text, UDim2.new(1, 0, 0, Theme.lineHeight), parent)
	label.Font = Theme.bold
	label.LayoutOrder = order
	return label
end

function TeamBoardView.create(parent: PlayerGui): View
	local screen = Instance.new("ScreenGui")
	screen.Name = "TeamBoard"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.Enabled = false

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Theme.background
	background.BorderSizePixel = 0
	background.Parent = screen

	local frame = Controls.panel(UDim2.new(1, -2 * Theme.gap, 1, -2 * Theme.gap), background)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	local width = Instance.new("UISizeConstraint")
	width.MaxSize = Vector2.new(Theme.boardMaxWidth, width.MaxSize.Y)
	width.Parent = frame

	local panel = flowFrame(frame, 0, 0)
	panel.Position = UDim2.fromOffset(Theme.padding, Theme.padding)
	panel.Size = UDim2.new(1, -2 * Theme.padding, 1, -2 * Theme.padding)
	local headerHeight = Theme.touch + Theme.gap
	local footerHeight = Theme.touch + Theme.statusHeight + Theme.gap
	local body = flowFrame(panel, 0, 0)
	body.Position = UDim2.fromOffset(0, headerHeight)
	body.Size = UDim2.new(1, 0, 1, -headerHeight - footerHeight)

	local back = Controls.button("Back", UDim2.fromOffset(Theme.touch * 2, Theme.touch), panel)
	local title = Controls.label("Team Board", UDim2.new(1, -Theme.touch * 2 - Theme.gap, 0, Theme.touch), panel)
	title.Position = UDim2.fromOffset(Theme.touch * 2 + Theme.gap, 0)
	title.Font = Theme.bold
	title.TextSize = Theme.titleSize

	local boardScroll = Controls.scroll(UDim2.fromScale(1, 1), body)
	local rosterScroll = Controls.scroll(UDim2.fromScale(1, 1), body)
	local count = Controls.label("Front row at top", UDim2.new(1, 0, 0, Theme.lineHeight), boardScroll)
	count.LayoutOrder = 1

	local boardHeight = COLUMNS * Theme.cellHeight + (COLUMNS - 1) * Theme.gap
	local gridFrame = flowFrame(boardScroll, boardHeight, 2)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / COLUMNS, -Theme.gap, 0, Theme.cellHeight)
	grid.CellPadding = UDim2.fromOffset(Theme.gap, Theme.gap)
	grid.FillDirectionMaxCells = COLUMNS
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridFrame

	local cells: { TextButton } = {}
	for index = 1, Constants.BOARD_SLOTS do
		local cell = Controls.button("Empty", UDim2.fromScale(1, 1), gridFrame)
		cell.Name = `Slot{index}`
		cell.LayoutOrder = index
		cells[index] = cell
	end

	heading("Active synergies", boardScroll, 3)
	local synergy = Controls.label("No active synergies", UDim2.new(1, 0, 0, Theme.lineHeight), boardScroll)
	synergy.AutomaticSize = Enum.AutomaticSize.Y
	synergy.TextColor3 = Theme.muted
	synergy.LayoutOrder = 4

	local roster = flowFrame(boardScroll, 0, 5)
	roster.AutomaticSize = Enum.AutomaticSize.Y
	Controls.flow(roster)
	heading("Your units", roster, 1)
	local filters = flowFrame(roster, Theme.touch, 2)
	local half = UDim2.new(0.5, -Theme.gap / 2, 0, Theme.touch)
	local elementFilter = Controls.button("All elements", half, filters)
	local rarityFilter = Controls.button("All rarities", half, filters)
	rarityFilter.Position = UDim2.new(0.5, Theme.gap / 2, 0, 0)
	local rosterMessage = Controls.label("", UDim2.new(1, 0, 0, Theme.lineHeight), roster)
	rosterMessage.TextColor3 = Theme.muted
	rosterMessage.LayoutOrder = 3
	local cards = flowFrame(roster, 0, 4)
	cards.AutomaticSize = Enum.AutomaticSize.Y
	Controls.flow(cards)

	local toast = Toast.create(UDim2.new(1, 0, 0, Theme.statusHeight), panel)
	toast.Position = UDim2.new(0, 0, 1, -footerHeight)
	local save = Controls.button("Save team", half, panel)
	save.AnchorPoint = Vector2.new(0, 1)
	save.Position = UDim2.fromScale(0, 1)
	local play = Controls.button("Start battle", half, panel)
	play.AnchorPoint = Vector2.new(0, 1)
	play.Position = UDim2.new(0.5, Theme.gap / 2, 1, 0)
	play.BackgroundColor3 = Theme.accent
	save.NextSelectionRight = play
	play.NextSelectionLeft = save

	local split = false
	local function resize(): ()
		local wide = frame.AbsoluteSize.X >= Theme.boardSplitWidth
		if split == wide then
			return
		end
		split = wide
		rosterScroll.Visible = wide
		if wide then
			local column = UDim2.new(0.5, -Theme.gap, 1, 0)
			boardScroll.Size = column
			rosterScroll.Size = column
			rosterScroll.Position = UDim2.new(0.5, Theme.gap, 0, 0)
			roster.Parent = rosterScroll
		else
			boardScroll.Size = UDim2.fromScale(1, 1)
			roster.Parent = boardScroll
		end
	end
	rosterScroll.Visible = false
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	screen.Parent = parent
	resize()

	return {
		screen = screen,
		back = back,
		boardScroll = boardScroll,
		rosterScroll = rosterScroll,
		cards = cards,
		count = count,
		cells = cells,
		synergy = synergy,
		rosterMessage = rosterMessage,
		elementFilter = elementFilter,
		rarityFilter = rarityFilter,
		status = toast,
		save = save,
		play = play,
	}
end

local function percent(value: number): string
	return string.format("%g%%", value * 100)
end

local function describe(tier: Types.SynergyDef): string
	if tier.burnHpPerSecond then
		return string.format("Burn %s HP/s", percent(tier.burnHpPerSecond))
	elseif tier.slow then
		return ("Slow %s"):format(percent(tier.slow))
			.. (if tier.freezeChance then " · " .. percent(tier.freezeChance) .. " freeze chance" else "")
	elseif tier.speedBonus then
		return "+" .. percent(tier.speedBonus) .. " attack speed"
	elseif tier.healHpPerSecond then
		return "Heal "
			.. percent(tier.healHpPerSecond)
			.. " HP/s "
			.. (if tier.healTarget == "allAllies" then "for all allies" else "for Cahaya units")
	elseif tier.critChanceBonus then
		return "+"
			.. percent(tier.critChanceBonus)
			.. " crit chance"
			.. (
				if tier.critDamageMultiplier then " · " .. percent(tier.critDamageMultiplier) .. " crit damage" else ""
			)
	elseif tier.atkAndDefBonus then
		return "+" .. percent(tier.atkAndDefBonus) .. " ATK & DEF per stack"
	elseif tier.firstReviveHp then
		return "Revive once with " .. percent(tier.firstReviveHp) .. " HP"
	elseif tier.manaGainBonus then
		return "+" .. percent(tier.manaGainBonus) .. " mana gain"
	end
	return ""
end

function TeamBoardView.describeSynergies(active: SynergyResolver.Active): string
	local lines: { string } = {}
	for name, tier in active.elements do
		if tier then
			table.insert(lines, string.format("%s (%d) · %s", name, tier.count, describe(tier)))
		end
	end
	for name, tier in active.statuses do
		if tier then
			table.insert(lines, string.format("%s (%d) · %s", name, tier.count, describe(tier)))
		end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

function TeamBoardView.setSynergies(view: View, active: SynergyResolver.Active): ()
	local description = TeamBoardView.describeSynergies(active)
	view.synergy.Text = if description ~= "" then description else "No active synergies"
	view.synergy.TextColor3 = if description ~= "" then Theme.text else Theme.muted
end

return table.freeze(TeamBoardView)
