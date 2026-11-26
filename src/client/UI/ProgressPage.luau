--!strict
local Controls = require(script.Parent.Components.Controls)
local Theme = require(script.Parent.Theme)

export type Page = {
	screen: ScreenGui,
	body: ScrollingFrame,
	back: TextButton,
	message: TextLabel,
}

local Page = {}

function Page.create(parent: PlayerGui, title: string, onBack: () -> ()): Page
	local screen = Instance.new("ScreenGui")
	screen.Name = title
	screen.Enabled = false
	screen.ResetOnSpawn = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Theme.background
	background.Parent = screen

	local pad = Theme.padding
	local row = Theme.touch + Theme.gap
	local panel = Controls.panel(UDim2.new(1, -2 * pad, 1, -2 * pad), background)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(Theme.boardMaxWidth, math.huge)
	constraint.Parent = panel

	local heading = Controls.label(title, UDim2.new(1, -128 - 3 * pad, 0, Theme.touch), panel)
	heading.Position = UDim2.fromOffset(pad, pad)
	heading.TextSize = Theme.titleSize
	heading.Font = Theme.bold
	local back = Controls.button("Back", UDim2.fromOffset(128, Theme.touch), panel)
	back.AnchorPoint = Vector2.new(1, 0)
	back.Position = UDim2.new(1, -pad, 0, pad)
	back.Activated:Connect(onBack)

	local message = Controls.label("", UDim2.new(1, -2 * pad, 0, Theme.statusHeight), panel)
	message.Position = UDim2.new(0, pad, 1, -pad - Theme.statusHeight)
	message.TextColor3 = Theme.muted
	local body = Controls.scroll(UDim2.new(1, -2 * pad, 1, -2 * pad - row - Theme.statusHeight), panel)
	body.Position = UDim2.fromOffset(pad, pad + row)
	screen.Parent = parent
	return { screen = screen, body = body, back = back, message = message }
end

function Page.clear(page: Page): ()
	for _, child in page.body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Page.button(parent: Instance, label: string, action: () -> ()): TextButton
	local button = Controls.button(label, UDim2.new(1, 0, 0, Theme.touch), parent)
	button.Activated:Connect(action)
	return button
end

function Page.label(parent: Instance, value: string): TextLabel
	local label = Controls.label(value, UDim2.new(1, 0, 0, Theme.lineHeight), parent)
	label.AutomaticSize = Enum.AutomaticSize.Y
	return label
end

function Page.grid(parent: ScrollingFrame, minimumWidth: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(Theme.gap, Theme.gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local function resize()
		local width = frame.AbsoluteSize.X
		local columns = math.max(1, math.floor((width + Theme.gap) / (minimumWidth + Theme.gap)))
		layout.CellSize = UDim2.new(1 / columns, -math.ceil(Theme.gap * (1 - 1 / columns)), 0, height)
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()
	return frame
end

return table.freeze(Page)
