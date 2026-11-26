--!strict
local Theme = require(script.Parent.Parent.Theme)
local Controls = require(script.Parent.Parent.Components.Controls)

local Hud = {}

export type View = {
	screen: ScreenGui,
	time: TextLabel,
	cinematicTitle: TextLabel,
	speed: TextButton,
	cinematic: TextButton,
	skip: TextButton,
	exit: TextButton,
	result: Frame,
	resultTitle: TextLabel,
	resultDetail: TextLabel,
	close: TextButton,
}

local function panel(name: string, parent: Instance, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.BackgroundColor3 = Theme.panel
	Controls.round(frame)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.border
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end

local function centeredLabel(text: string, size: UDim2, parent: Instance): TextLabel
	local label = Controls.label(text, size, parent)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end

function Hud.create(parent: PlayerGui): View
	local screen = Instance.new("ScreenGui")
	screen.Name = "BattleReplay"
	screen.Enabled = false
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local header = panel("Clock", screen, UDim2.fromOffset(210, Theme.touch))
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, Theme.padding)
	local time = centeredLabel("Replay · 0:00", UDim2.fromScale(1, 1), header)
	time.Font = Theme.bold

	local cinematicTitle = centeredLabel("", UDim2.new(0.9, 0, 0, Theme.touch), screen)
	cinematicTitle.AnchorPoint = Vector2.new(0.5, 0)
	cinematicTitle.Position = UDim2.new(0.5, 0, 0, Theme.padding + Theme.touch + Theme.gap)
	cinematicTitle.Font = Theme.bold
	cinematicTitle.TextSize = Theme.titleSize
	cinematicTitle.TextStrokeTransparency = 0.3
	cinematicTitle.Visible = false

	local toolbarHeight = 2 * Theme.touch + 3 * Theme.gap
	local toolbar = panel("ReplayControls", screen, UDim2.new(1, -2 * Theme.padding, 0, toolbarHeight))
	toolbar.AnchorPoint = Vector2.new(0.5, 1)
	toolbar.Position = UDim2.new(0.5, 0, 1, -Theme.padding)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(Theme.maxWidth, toolbarHeight)
	limit.Parent = toolbar

	local buttonSize = UDim2.new(0.5, -1.5 * Theme.gap, 0, Theme.touch)
	local speed = Controls.button("Speed: 1×", buttonSize, toolbar)
	speed.Position = UDim2.fromOffset(Theme.gap, Theme.gap)
	local cinematic = Controls.button("Cinematics: On", buttonSize, toolbar)
	cinematic.Position = UDim2.new(0.5, Theme.gap / 2, 0, Theme.gap)
	local skip = Controls.button("Skip ultimate", buttonSize, toolbar)
	skip.Position = UDim2.fromOffset(Theme.gap, Theme.touch + 2 * Theme.gap)
	local exit = Controls.button("Exit replay", buttonSize, toolbar)
	exit.Position = UDim2.new(0.5, Theme.gap / 2, 0, Theme.touch + 2 * Theme.gap)
	speed.NextSelectionRight = cinematic
	speed.NextSelectionDown = skip
	cinematic.NextSelectionLeft = speed
	cinematic.NextSelectionDown = exit
	skip.NextSelectionUp = speed
	skip.NextSelectionRight = exit
	exit.NextSelectionLeft = skip
	exit.NextSelectionUp = cinematic

	local result = panel("BattleResult", screen, UDim2.new(0.9, 0, 0, 158))
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Position = UDim2.fromScale(0.5, 0.46)
	result.Visible = false
	local resultLimit = Instance.new("UISizeConstraint")
	resultLimit.MaxSize = Vector2.new(320, 158)
	resultLimit.Parent = result
	local resultTitle = centeredLabel("", UDim2.new(1, 0, 0, Theme.touch), result)
	resultTitle.Font = Theme.bold
	resultTitle.TextSize = Theme.titleSize
	resultTitle.Position = UDim2.fromOffset(0, Theme.gap)
	local resultDetail = centeredLabel("", UDim2.new(1, 0, 0, Theme.touch), result)
	resultDetail.TextColor3 = Theme.muted
	resultDetail.Position = UDim2.fromOffset(0, Theme.gap + Theme.touch)
	local close = Controls.button("Close", UDim2.new(1, -2 * Theme.padding, 0, Theme.touch), result)
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -Theme.padding)
	close.BackgroundColor3 = Theme.accent
	screen.Parent = parent
	return {
		screen = screen,
		time = time,
		cinematicTitle = cinematicTitle,
		speed = speed,
		cinematic = cinematic,
		skip = skip,
		exit = exit,
		result = result,
		resultTitle = resultTitle,
		resultDetail = resultDetail,
		close = close,
	}
end

function Hud.enable(button: TextButton, enabled: boolean): ()
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
	button.TextColor3 = if enabled then Theme.text else Theme.muted
end

return table.freeze(Hud)
