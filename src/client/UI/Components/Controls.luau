--!strict

local Theme = require(script.Parent.Parent.Theme)

local Controls = {}

function Controls.round(gui: GuiObject): ()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.radius)
	corner.Parent = gui
end

function Controls.button(text: string, size: UDim2, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.BackgroundColor3 = Theme.button
	button.TextColor3 = Theme.text
	button.Font = Theme.font
	button.TextSize = Theme.textSize
	button.TextWrapped = true
	button.Text = text
	Controls.round(button)
	button.Parent = parent
	return button
end

function Controls.setEnabled(button: TextButton, enabled: boolean): ()
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
	button.TextColor3 = if enabled then Theme.text else Theme.muted
end

function Controls.panel(size: UDim2, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.BackgroundColor3 = Theme.panel
	frame.BorderSizePixel = 0
	Controls.round(frame)
	frame.Parent = parent
	return frame
end

function Controls.flow(parent: Instance): ()
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.gap)
	layout.Parent = parent
end

function Controls.scroll(size: UDim2, parent: Instance): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = size
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = Theme.scrollbar
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Parent = parent
	Controls.flow(scroll)
	return scroll
end

function Controls.label(text: string, size: UDim2, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.text
	label.Font = Theme.font
	label.TextSize = Theme.textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = text
	label.Parent = parent
	return label
end

return Controls
