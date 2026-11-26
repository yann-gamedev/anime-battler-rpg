--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UIController = require(script.Parent.Parent.Controllers.UIController)
local Page = require(script.Parent.ProgressPage)

local LobbyPage = {}

function LobbyPage.bindBack(screen: ScreenGui, close: () -> ()): ()
	local input = UserInputService.InputBegan:Connect(function(key, processed)
		if
			screen.Enabled
			and not processed
			and (key.KeyCode == Enum.KeyCode.ButtonB or key.KeyCode == Enum.KeyCode.Backspace)
		then
			close()
		end
	end)
	screen.Destroying:Once(function()
		input:Disconnect()
	end)
end

function LobbyPage.create(title: string, onBack: () -> (), canClose: (() -> boolean)?): Page.Page
	local parent = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local page: Page.Page
	local function close()
		if not page.screen.Enabled or (canClose and not canClose()) then
			return
		end
		onBack()
		page.screen:Destroy()
	end
	page = Page.create(parent, title, close)
	LobbyPage.bindBack(page.screen, close)
	UIController.show(page.screen, page.back)
	return page
end

-- Reconnect selection when rows are replaced after a snapshot refresh.
function LobbyPage.focus(page: Page.Page, preferred: TextButton?): ()
	local previous = page.back
	for _, child in page.body:GetChildren() do
		if child:IsA("TextButton") and child.Selectable then
			previous.NextSelectionDown = child
			child.NextSelectionUp = previous
			previous = child
		end
	end
	previous.NextSelectionDown = nil
	UIController.focus(preferred or page.back.NextSelectionDown or page.back)
end

return table.freeze(LobbyPage)
