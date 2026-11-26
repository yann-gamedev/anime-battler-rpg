--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local UI = script.Parent.Parent.UI
local BattleViewController = require(script.Parent.BattleViewController)
local SummonController = require(script.Parent.SummonController)
local TeamBoardController = require(script.Parent.TeamBoardController)
local UIController = require(script.Parent.UIController)
local Page = require(UI.ProgressPage)
local Remote = require(UI.ProgressRemote)
local StoryView = require(UI.StoryView)
local InventoryView = require(UI.InventoryView)
local TraitRemote = require(UI.TraitRemote)
local TraitView = require(UI.TraitView)
local Controls = require(UI.Components.Controls)

local MonetizationController = require(script.Parent.MonetizationController)
local StoryFlow = require(script.Parent.StoryFlow)
local Products = require(ReplicatedStorage.Shared.Config.Products)
local player = Players.LocalPlayer
type Route = "hub" | "story" | "inventory"

local ProgressController = {}
local pages: { [Route]: Page.Page } = {}
local inventory = InventoryView.new()
local trait = TraitView.new()
local route: Route = "hub"
local parent: PlayerGui
local onBack: (() -> ())?
local data: Remote.Snapshot?
local busy = false
local requestId = 0
local notice = ""
local storyScroll = Vector2.zero
local focusStage: string?
local render: (boolean?) -> ()
local load: () -> ()

local function detailUid(): string?
	local uid = inventory.uid
	return if route == "inventory" and not inventory.mode and uid and data and data.units[uid] then uid else nil
end

local function refreshTrait(uid: string): ()
	TraitView.refresh(trait, uid, function()
		return detailUid() == uid and pages.inventory.screen.Enabled
	end, function(snapshot)
		data = snapshot or data
		render(true)
	end)
end

local function go(destination: Route): ()
	if busy then
		return
	end
	route = destination
	notice = ""
	render()
end

local function openTeam(): ()
	if busy then
		return
	end
	storyScroll = pages.story.body.CanvasPosition
	TeamBoardController.open(function()
		render(true)
		load()
	end)
end

local function openSummon(): ()
	if busy then
		return
	end
	if route == "story" then
		storyScroll = pages.story.body.CanvasPosition
	end
	SummonController.open(function()
		render(true)
		load()
	end)
end

local function back(): ()
	if busy then
		return
	end
	notice = ""
	if route == "inventory" and InventoryView.back(inventory) then
		render()
	elseif route == "story" then
		storyScroll = pages.story.body.CanvasPosition
		go("hub")
	elseif route ~= "hub" then
		go("hub")
	elseif onBack then
		onBack()
	end
end

local function beginRequest(message: string): ()
	busy = true
	TraitView.reset(trait, nil)
	requestId += 1
	local id = requestId
	local page = pages[route]
	page.message.Text = message
	Controls.setEnabled(page.back, false)
	for _, child in page.body:GetDescendants() do
		if child:IsA("TextButton") then
			Controls.setEnabled(child, false)
		end
	end
	task.delay(12, function()
		if busy and requestId == id and page.message.Text == message then
			page.message.Text = "Still waiting for the server…"
		end
	end)
end

load = function()
	if busy then
		return
	end
	beginRequest("Loading profile…")
	local snapshot, failure = Remote.snapshot("GetMyData")
	busy = false
	data = snapshot
	notice = failure or ""
	render(true)
end

local function mutate(name: string, ...: any): ()
	if busy or not data then
		return
	end
	beginRequest("Updating inventory…")
	local snapshot, failure = Remote.snapshot(name, ...)
	if snapshot then
		data = snapshot
		inventory.mode = nil
		inventory.confirm = false
		table.clear(inventory.selected)
		notice = "Inventory updated."
	else
		-- An interrupted response can follow a committed mutation. Refresh before accepting another action.
		data = Remote.snapshot("GetMyData")
		notice = failure or "Inventory could not be updated."
	end
	busy = false
	render()
end

local function inventoryAction(name: string, ...: any): ()
	if name ~= "RerollTrait" and name ~= "RefreshTraitInfo" and name ~= "SelectRestrictedTrait" then
		mutate(name, ...)
		return
	end
	local uid = detailUid()
	if busy or not uid or uid ~= ... or trait.pending then
		return
	end
	if name == "RefreshTraitInfo" then
		TraitView.reset(trait, nil)
		render(true)
		return
	end
	local info = trait.info
	local _, selected = ...
	local direct = name == "SelectRestrictedTrait"
	if not info or info.uid ~= uid then
		return
	end
	if direct then
		if type(selected) ~= "string" or not TraitRemote.canSelect(info, selected) then
			return
		end
	elseif info.restricted or info.locked or info.shards < info.cost then
		return
	end
	beginRequest(if direct then "Equipping trait…" else "Rerolling trait…")
	local snapshot, updatedInfo, code = TraitRemote.change(uid, if direct then selected else nil)
	busy = false
	if snapshot and updatedInfo then
		data = snapshot
		trait.uid = uid
		trait.info = updatedInfo
		notice = if direct then "Trait equipped." else "Trait rerolled."
		refreshTrait(uid)
	else
		notice = TraitRemote.message(code)
	end
	render(true)
end

local function startStage(stageId: string, teamIndex: number, auto: boolean?): ()
	local previous = data
	if busy or not previous or not previous.progression then
		return
	end
	storyScroll = pages.story.body.CanvasPosition
	focusStage = stageId
	beginRequest(if auto then "Starting auto-replay…" else "Starting battle with your saved team…")
	local result, failure = Remote.startStage(stageId, teamIndex, auto)
	if not result then
		data = Remote.snapshot("GetMyData")
		busy = false
		notice = failure or "Battle could not start."
		render(true)
		return
	end

	local lobbyUnlocked = not previous.progression.tutorialDone and result.progression.tutorialDone
	previous.progression = result.progression
	if stageId ~= "tutorial" then
		previous.story.cleared[stageId] = math.max(previous.story.cleared[stageId] or 0, result.stars)
	end
	previous.currencies.Gold += result.rewards.Gold
	previous.currencies.Gems += result.rewards.Gems
	previous.currencies.SummonTickets += result.rewards.SummonTickets

	BattleViewController.playStory(result.replay, function(completed)
		busy = false
		notice = ""
		render(true)
		local nextRound: (() -> ())?
		if auto and completed and result.replay.winner == "A" and player:GetAttribute("PassAutoReplay") == true then
			nextRound = function()
				if pages.story.screen.Enabled and player:GetAttribute("PassAutoReplay") == true then
					startStage(stageId, teamIndex, true)
				end
			end
		end
		StoryFlow.show(parent, result, lobbyUnlocked, function(visitedSummon)
			if lobbyUnlocked then
				go("hub")
			else
				render(true)
			end
			if visitedSummon then
				load()
			end
		end, nextRound)
	end)
end

local function chooseStage(stageId: string): ()
	if busy or not pages.story.screen.Enabled then
		return
	end
	local teamIndex = TeamBoardController.selectedIndex()
	local snapshot = data
	if
		not snapshot
		or player:GetAttribute("PassAutoReplay") ~= true
		or (snapshot.story.cleared[stageId] or 0) < Products.autoReplayRequiredStars
	then
		startStage(stageId, teamIndex)
		return
	end
	StoryFlow.chooseMode(parent, stageId, teamIndex, function(auto)
		startStage(stageId, teamIndex, auto)
	end)
end

local function returnToHub(): ()
	render(true)
	load()
end

render = function(preserveScroll: boolean?)
	local page = pages[route]
	local uid = detailUid()
	if trait.uid ~= uid then
		TraitView.reset(trait, uid)
		if uid then
			refreshTrait(uid)
		end
	end
	local scroll = if route == "story"
		then storyScroll
		elseif route == "inventory" and not inventory.uid and not inventory.mode then inventory.scroll
		elseif preserveScroll then page.body.CanvasPosition
		else Vector2.zero
	Page.clear(page)
	page.message.Text = notice
	Controls.setEnabled(page.back, route ~= "hub" or onBack ~= nil)
	local snapshot = data
	local first: TextButton?
	if route == "hub" then
		Page.label(
			page.body,
			if snapshot
					and snapshot.progression
					and snapshot.progression.tutorialDone
				then "Arcanum Lobby"
				else "Arcanum Academy"
		)
		first = Page.button(
			page.body,
			if snapshot
					and snapshot.progression
					and not snapshot.progression.tutorialDone
				then "Continue onboarding"
				else "Story",
			function()
				go("story")
			end
		)
		Page.button(page.body, "Inventory", function()
			go("inventory")
		end)
		Page.button(page.body, "Summon", openSummon)
		Page.button(page.body, "Team Board", openTeam)
		Page.button(page.body, "Academy Shop", function()
			MonetizationController.openShop(returnToHub)
		end)
		Page.button(page.body, "Battle Pass", function()
			MonetizationController.openPass(returnToHub)
		end)
		if snapshot then
			Page.label(
				page.body,
				string.format(
					"Gold %d · Gems %d · Summon Tickets %d",
					snapshot.currencies.Gold,
					snapshot.currencies.Gems,
					snapshot.currencies.SummonTickets
				)
			)
		end
	elseif not snapshot then
		Page.label(page.body, "Your profile is unavailable.")
	elseif route == "story" then
		first = StoryView.render(
			page,
			snapshot,
			chooseStage,
			openTeam,
			openSummon,
			focusStage,
			TeamBoardController.selectedIndex()
		)
	else
		first = InventoryView.render(page, snapshot, inventory, trait, inventoryAction, function(keepScroll)
			render(keepScroll)
		end)
	end
	local reload = Page.button(page.body, "Reload profile", load)
	UIController.show(page.screen, first or reload)
	page.body.CanvasPosition = scroll
end

local function bindUpdates(): ()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, 10)
		if not folder then
			return
		end
		for _, name in { "InventoryChanged", "CurrencyChanged" } do
			local event = folder:WaitForChild(name, 5)
			if event and event:IsA("RemoteEvent") then
				event.OnClientEvent:Connect(function()
					-- Invoke replies supply the authoritative post-mutation state during local requests.
					if not busy and pages[route].screen.Enabled then
						load()
					end
				end)
			end
		end
	end)
end

function ProgressController.open(returnToMenu: (() -> ())?): ()
	onBack = returnToMenu
	if not pages.hub then
		parent = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		pages.hub = Page.create(parent, "Play", back)
		pages.story = Page.create(parent, "Story", back)
		pages.inventory = Page.create(parent, "Inventory", back)
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and pages[route].screen.Enabled and input.KeyCode == Enum.KeyCode.ButtonB then
				back()
			end
		end)
		bindUpdates()
	end
	go("hub")
	load()
end

return ProgressController
