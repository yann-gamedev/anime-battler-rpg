--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.UI.Theme)
local UIController = require(script.Parent.UIController)
local ProgressController = require(script.Parent.ProgressController)

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
	if player:GetAttribute("MusicEnabled") == nil then
		player:SetAttribute("MusicEnabled", true)
	end

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
	local settings = background.SettingsPanel :: Frame
	local playButton = menu.PlayButton :: TextButton
	local settingsButton = menu.SettingsButton :: TextButton
	local quitButton = menu.QuitButton :: TextButton
	local musicButton = settings.MusicButton :: TextButton
	local backButton = settings.BackButton :: TextButton

	playButton.NextSelectionDown = settingsButton
	settingsButton.NextSelectionUp = playButton
	settingsButton.NextSelectionDown = quitButton
	quitButton.NextSelectionUp = settingsButton
	musicButton.NextSelectionDown = backButton
	backButton.NextSelectionUp = musicButton

	for _, button in { playButton, settingsButton, quitButton, musicButton, backButton } do
		wireHighlight(button)
	end

	local function showMenu(): ()
		menu.Visible = true
		settings.Visible = false
		UIController.show(screen, playButton)
	end

	local function updateMusic(): ()
		musicButton.Text = if player:GetAttribute("MusicEnabled") then "Music: On" else "Music: Off"
	end

	playButton.Activated:Connect(function()
		ProgressController.open(showMenu)
	end)
	settingsButton.Activated:Connect(function()
		menu.Visible = false
		settings.Visible = true
		UIController.focus(musicButton)
	end)
	quitButton.Activated:Connect(function()
		player:Kick("Thanks for playing!")
	end)
	musicButton.Activated:Connect(function()
		player:SetAttribute("MusicEnabled", not player:GetAttribute("MusicEnabled"))
	end)
	backButton.Activated:Connect(showMenu)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and screen.Enabled and settings.Visible and input.KeyCode == Enum.KeyCode.ButtonB then
			showMenu()
		end
	end)
	player:GetAttributeChangedSignal("MusicEnabled"):Connect(updateMusic)

	updateMusic()
	showMenu()
end

return MenuController
