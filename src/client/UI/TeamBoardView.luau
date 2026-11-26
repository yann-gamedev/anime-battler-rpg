--!strict

local Controls = require(script.Parent.Components.Controls)
local Theme = require(script.Parent.Theme)

local TeamBoardView = {}

export type View = {
	screen: ScreenGui,
	back: TextButton,
	scroll: ScrollingFrame,
	count: TextLabel,
	cells: { TextButton },
	roster: TextLabel,
	status: TextLabel,
	action: TextButton,
}

function TeamBoardView.create(parent: Instance): View
	local screen = Instance.new("ScreenGui")
	screen.Name = "TeamBoard"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10
	screen.Enabled = false
	screen.Parent = parent

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Theme.background
	background.BorderSizePixel = 0
	background.Parent = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(1, -2 * Theme.padding, 1, -2 * Theme.padding)
	panel.BackgroundColor3 = Theme.panel
	Controls.round(panel)
	panel.Parent = background

	local bounds = Instance.new("UISizeConstraint")
	bounds.MaxSize = Vector2.new(Theme.maxWidth, bounds.MaxSize.Y)
	bounds.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Theme.padding)
	padding.PaddingBottom = padding.PaddingTop
	padding.PaddingLeft = padding.PaddingTop
	padding.PaddingRight = padding.PaddingTop
	padding.Parent = panel

	local buttonSize = UDim2.fromOffset(2 * Theme.touch, Theme.touch)
	local back = Controls.button("Back", buttonSize, panel)
	local title = Controls.label("Team Board", UDim2.new(1, -2 * Theme.touch - Theme.gap, 0, Theme.touch), panel)
	title.Position = UDim2.fromOffset(2 * Theme.touch + Theme.gap, 0)
	title.Font = Theme.bold
	title.TextSize = Theme.titleSize

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(0, Theme.touch + Theme.gap)
	scroll.Size = UDim2.new(1, 0, 1, -2 * (Theme.touch + Theme.gap) - Theme.statusHeight)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = Theme.scrollbar
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Parent = panel

	local flow = Instance.new("UIListLayout")
	flow.SortOrder = Enum.SortOrder.LayoutOrder
	flow.Padding = UDim.new(0, Theme.gap)
	flow.Parent = scroll

	local count = Controls.label("", UDim2.new(1, 0, 0, Theme.touch), scroll)
	count.LayoutOrder = 1

	local board = Instance.new("Frame")
	board.LayoutOrder = 2
	board.BackgroundTransparency = 1
	board.Size = UDim2.new(1, 0, 0, 3 * Theme.cellHeight + 2 * Theme.gap)
	board.Parent = scroll

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 3, -Theme.gap, 0, Theme.cellHeight)
	grid.CellPadding = UDim2.fromOffset(Theme.gap, Theme.gap)
	grid.FillDirectionMaxCells = 3
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = board

	local cells: { TextButton } = {}
	for index = 1, 9 do
		local cell = Controls.button("Empty", UDim2.fromScale(1, 1), board)
		cell.LayoutOrder = index
		cells[index] = cell
	end

	local roster = Controls.label("Your units", UDim2.new(1, 0, 0, Theme.touch), scroll)
	roster.LayoutOrder = 3
	roster.Font = Theme.bold

	local status = Controls.label("", UDim2.new(1, -2 * Theme.touch - Theme.gap, 0, Theme.statusHeight), panel)
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.fromScale(0, 1)

	local action = Controls.button("Save team", buttonSize, panel)
	action.AnchorPoint = Vector2.new(1, 1)
	action.Position = UDim2.fromScale(1, 1)

	return {
		screen = screen,
		back = back,
		scroll = scroll,
		count = count,
		cells = cells,
		roster = roster,
		status = status,
		action = action,
	}
end

return TeamBoardView
