--!strict

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local UIController = {}
local active: ScreenGui?

function UIController.show(screen: ScreenGui, first: GuiObject?): ()
	GuiService.SelectedObject = nil
	if active and active ~= screen then
		active.Enabled = false
	end
	active = screen
	screen.Enabled = true
	UIController.focus(first)
end

function UIController.focus(first: GuiObject?): ()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = first
	end
end

return UIController
