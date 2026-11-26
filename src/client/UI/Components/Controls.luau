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
