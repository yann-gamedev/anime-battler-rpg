--!strict
local UserInputService = game:GetService("UserInputService")

local Controls = require(script.Parent.Controls)
local Theme = require(script.Parent.Parent.Theme)

export type Choice = { label: string, value: string? }
export type View = { screen: ScreenGui, first: TextButton }
local Modal = {}

function Modal.create(
	parent: Instance,
	title: string,
	choices: { Choice },
	selected: string?,
	onSelect: (string?) -> (),
	onCancel: () -> ()
): View
	local screen = Instance.new("ScreenGui")
	screen.Name = "ChoiceModal"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = 15
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local scrim = Instance.new("Frame")
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Theme.background
	scrim.BackgroundTransparency = Theme.scrimTransparency
	scrim.BorderSizePixel = 0
	scrim.Active = true
	scrim.Parent = screen

	local panel = Controls.panel(UDim2.new(1, -2 * Theme.padding, 1, -2 * Theme.padding), scrim)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	local constraint = Instance.new("UISizeConstraint")
	local row = Theme.touch + Theme.gap
	constraint.MaxSize = Vector2.new(Theme.modalWidth, row * (#choices + 2) + 2 * Theme.padding)
	constraint.Parent = panel
	local heading = Controls.label(title, UDim2.new(1, -2 * Theme.padding, 0, Theme.touch), panel)
	heading.Position = UDim2.fromOffset(Theme.padding, Theme.padding)
	heading.Font = Theme.bold

	local list = Controls.scroll(UDim2.new(1, -2 * Theme.padding, 1, -2 * Theme.padding - 2 * row), panel)
	list.Position = UDim2.fromOffset(Theme.padding, Theme.padding + row)
	local cancel = Controls.button("Cancel", UDim2.new(1, -2 * Theme.padding, 0, Theme.touch), panel)
	cancel.AnchorPoint = Vector2.new(0, 1)
	cancel.Position = UDim2.new(0, Theme.padding, 1, -Theme.padding)
	cancel.Activated:Connect(onCancel)

	local first = cancel
	for index, option in choices do
		local selectedOption = option.value == selected
		local button = Controls.button(
			if selectedOption then option.label .. "  ✓" else option.label,
			UDim2.new(1, 0, 0, Theme.touch),
			list
		)
		button.LayoutOrder = index
		if selectedOption then
			button.BackgroundColor3 = Theme.accent
			first = button
		end
		button.Activated:Connect(function()
			onSelect(option.value)
		end)
	end

	local back = UserInputService.InputBegan:Connect(function(input, processed)
		if screen.Enabled and not processed and input.KeyCode == Enum.KeyCode.ButtonB then
			onCancel()
		end
	end)
	screen.Destroying:Connect(function()
		back:Disconnect()
	end)
	screen.Parent = parent
	return { screen = screen, first = first }
end

return table.freeze(Modal)
