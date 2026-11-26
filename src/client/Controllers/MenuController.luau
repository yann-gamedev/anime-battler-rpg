--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.UI.Theme)
local UIController = require(script.Parent.UIController)
local ProgressController = require(script.Parent.ProgressController)
local SettingsController = require(script.Parent.SettingsController)

local MenuController = {}

local function wireHighlight(button: TextButton): ()
	local function transition(color: Color3): ()
		TweenService:Create(button, Theme.menuFade, { BackgroundColor3 = color }):Play()
	end

	button.MouseEnter:Connect(function()
		transition(Theme.focus)
	end)
	button.MouseLeave:Connect(function()
		transition(Theme.button)
	end)
	button.SelectionGained:Connect(function()
		transition(Theme.focus)
	end)
	button.SelectionLost:Connect(function()
		transition(Theme.button)
	end)
end

function MenuController.start(): ()
	local player = Players.LocalPlayer

	local playerGui = player:WaitForChild("PlayerGui")
	local screen = playerGui:WaitForChild("MainMenu", 5)
	if not screen or not screen:IsA("ScreenGui") then
		warn("[Menu] MainMenu missing. Run studio/ui/build_main_menu.luau in Studio edit mode.")
		ProgressController.open(nil)
		return
	end

	-- Remove the embedded controller from places that still use the old layout.
	local legacy = screen:FindFirstChild("MenuController")
	if legacy and legacy:IsA("LocalScript") then
		legacy:Destroy()
	end

	local background = screen.Background
	local menu = background.Menu :: Frame
	local legacySettings = background:FindFirstChild("SettingsPanel") :: Frame?
	local playButton = menu.PlayButton :: TextButton
	local settingsButton = menu.SettingsButton :: TextButton
	local quitButton = menu.QuitButton :: TextButton

	playButton.NextSelectionDown = settingsButton
	settingsButton.NextSelectionUp = playButton
	settingsButton.NextSelectionDown = quitButton
	quitButton.NextSelectionUp = settingsButton

	for _, button in { playButton, settingsButton, quitButton } do
		wireHighlight(button)
	end

	local function showMenu(focus: TextButton?): ()
		menu.Visible = true
		if legacySettings then
			legacySettings.Visible = false
		end
		UIController.show(screen, focus or playButton)
	end

	playButton.Activated:Connect(function()
		ProgressController.open(showMenu)
	end)
	settingsButton.Activated:Connect(function()
		SettingsController.open(function()
			showMenu(settingsButton)
		end)
	end)
	quitButton.Activated:Connect(function()
		player:Kick("Thanks for playing!")
	end)
	showMenu()
end

return MenuController
