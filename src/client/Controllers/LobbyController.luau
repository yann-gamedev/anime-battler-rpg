--!strict
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UI = script.Parent.Parent.UI
local Controls = require(UI.Components.Controls)
local Theme = require(UI.Theme)
local UIController = require(script.Parent.UIController)

export type Route = "Story" | "Summon" | "Shop" | "Quests" | "Raid" | "Announcements" | "Directory" | "Trade"
type Routes = { [Route]: () -> () }

local LobbyController = {}
local screen: ScreenGui?
local routes: Routes?
local player = Players.LocalPlayer

local function dispatch(route: Route): ()
	local hud = screen
	local actions = routes
	if hud and hud.Enabled and actions then
		actions[route]()
	end
end

function LobbyController.available(): boolean
	local lobby = Workspace:FindFirstChild("ArcanumLobby")
	return lobby ~= nil and lobby:GetAttribute("ArcanumLobbyBuild") == true
end

function LobbyController.open(actions: Routes): ()
	routes = actions
	local current = screen
	if not current then
		local hud = Instance.new("ScreenGui")
		hud.Name = "LobbyNavigation"
		hud.Enabled = false
		hud.ResetOnSpawn = false
		hud.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		hud.Parent = player:WaitForChild("PlayerGui")

		local menu = Controls.button("Academy Menu", UDim2.fromOffset(132, Theme.touch), hud)
		menu.AnchorPoint = Vector2.new(1, 0)
		menu.Position = UDim2.new(1, -Theme.padding, 0, Theme.padding)
		menu.Activated:Connect(function()
			dispatch("Directory")
		end)
		screen, current = hud, hud
	end
	-- Leave gamepad input with the Roblox character until the player opens a page.
	UIController.show(current, nil)
end

function LobbyController.start(): ()
	ProximityPromptService.PromptTriggered:Connect(function(marker, who)
		local lobby = Workspace:FindFirstChild("ArcanumLobby")
		if who ~= player or not lobby or not marker:IsDescendantOf(lobby) then
			return
		end
		local action = marker:GetAttribute("LobbyRoute")
		if
			action == "Story"
			or action == "Summon"
			or action == "Shop"
			or action == "Quests"
			or action == "Raid"
			or action == "Announcements"
			or action == "Trade"
		then
			dispatch(action)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.M or key == Enum.KeyCode.ButtonY then
			dispatch("Directory")
		end
	end)
end

return table.freeze(LobbyController)
