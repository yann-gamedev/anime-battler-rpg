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

function UIController.overlay(screen: ScreenGui, first: GuiObject?): () -> ()
	local previous = active
	local selection = GuiService.SelectedObject
	UIController.show(screen, first)
	return function()
		if active == screen then
			screen.Enabled = false
			active = nil
			if previous and previous.Parent then
				UIController.show(previous, if selection and selection:IsDescendantOf(previous) then selection else nil)
			else
				GuiService.SelectedObject = nil
			end
		end
	end
end

return UIController
