--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local TeamBoardDraft = require(Shared.TeamBoardDraft)
local TeamRules = require(Shared.TeamRules)
local UI = script.Parent.Parent.UI
local Controls = require(UI.Components.Controls)
local Modal = require(UI.Components.Modal)
local Toast = require(UI.Components.Toast)
local UnitCard = require(UI.Components.UnitCard)
local TeamBoardDrag = require(UI.TeamBoardDrag)
local TeamBoardRemote = require(UI.TeamBoardRemote)
local TeamBoardView = require(UI.TeamBoardView)
local Theme = require(UI.Theme)
local UIController = require(script.Parent.UIController)

local TeamBoardController = {}
local SLOW_REQUEST = 12
local EMPTY = TeamRules.EMPTY_SLOT
local ELEMENTS = { "Api", "Es", "Petir", "Cahaya", "Bayangan" }
local RARITIES = { "Rare", "Epic", "Legendary", "Mythic" }
local view: TeamBoardView.View
local playerGui: PlayerGui
local bindCard: (TextButton, () -> (string?, string?)) -> ()
local board: Types.TeamBoardData?
local unitsByUid: { [string]: Types.TeamBoardUnit } = {}
local cards: { [string]: UnitCard.View } = {}
local selectedUid: string?
local element: string?
local rarity: string?
local backToMenu: (() -> ())?
local busy = false
local dirty = false
local teamIndex = 1
local player = Players.LocalPlayer

local function presetCount(): number
	local extra = player:GetAttribute("PassExtraPresets")
	return 1 + (if type(extra) == "number" then math.max(0, math.floor(extra)) else 0)
end

function TeamBoardController.selectedIndex(): number
	return if teamIndex <= presetCount() then teamIndex else 1
end

local function status(message: string, isError: boolean?): ()
	Toast.show(view.status, message, isError)
end

local function canInteract(): boolean
	return board ~= nil and not busy and view.screen.Enabled and teamIndex <= presetCount()
end

local function refresh(): ()
	local current = board
	local available = teamIndex <= presetCount()
	local deployed = if current then TeamBoardDraft.count(current.slots) else 0
	view.count.Text = if current
		then string.format("Front row at top  ·  %d/%d deployed", deployed, current.maxUnits)
		else "Front row at top"
	local placed: { [string]: number } = {}
	for index, cell in view.cells do
		local uid = if current then current.slots[index] else EMPTY
		local unit = unitsByUid[uid]
		cell.Text = if unit then unit.name else "Empty"
		cell.BackgroundColor3 = if uid == selectedUid then Theme.accent else Theme.button
		Controls.setEnabled(cell, current ~= nil and not busy and available)
		if uid ~= EMPTY then
			placed[uid] = index
		end
	end

	local visible = 0
	for uid, card in cards do
		local unit = unitsByUid[uid]
		local matches = current ~= nil and TeamBoardDraft.matches(unit, element, rarity)
		card.button.Visible = matches
		if matches then
			visible += 1
			UnitCard.update(card, unit, placed[uid], selectedUid == uid, not busy and available)
		else
			Controls.setEnabled(card.button, false)
		end
	end
	view.rosterMessage.Visible = visible == 0
	view.rosterMessage.Text = if not current
		then "Roster unavailable"
		elseif #current.units == 0 then "No units in your roster"
		else "No units match these filters"
	view.elementFilter.Text = element or "All elements"
	view.rarityFilter.Text = rarity or "All rarities"
	Controls.setEnabled(view.elementFilter, current ~= nil and not busy and available)
	Controls.setEnabled(view.rarityFilter, current ~= nil and not busy and available)
	TeamBoardView.setSynergies(view, TeamBoardDraft.synergies(if current then current.slots else {}, unitsByUid))

	view.preset.Text = if available then "Preset " .. teamIndex else "Preset " .. teamIndex .. " unavailable"
	Controls.setEnabled(view.preset, not busy and (presetCount() > 1 or not available))
	view.save.Text = if current then "Save team" else "Retry"
	Controls.setEnabled(view.save, not busy and available and (current == nil or dirty))
	Controls.setEnabled(view.play, not busy and available and deployed > 0)
	Controls.setEnabled(view.back, backToMenu ~= nil and not busy)
end

local function selectUnit(uid: string): ()
	if not canInteract() or not unitsByUid[uid] then
		return
	end
	selectedUid = uid
	view.boardScroll.CanvasPosition = Vector2.zero
	status("Choose a slot. Select the same slot to remove the unit.")
	refresh()
	UIController.focus(view.cells[1])
end

local function placeUnit(uid: string, index: number): ()
	local current = board
	if not current or not canInteract() or not unitsByUid[uid] then
		return
	end
	if not TeamBoardDraft.place(current.slots, uid, index, current.maxUnits) then
		status("Team is full. Choose an occupied slot to replace a unit.", true)
		return
	end
	selectedUid = nil
	dirty = true
	status("Unsaved changes.")
	refresh()
end

local function showBoard(data: Types.TeamBoardData): ()
	board = data
	table.clear(unitsByUid)
	for _, unit in data.units do
		unitsByUid[unit.uid] = unit
	end
	for uid, card in cards do
		if not unitsByUid[uid] then
			card.button:Destroy()
			cards[uid] = nil
		end
	end

	for order, unit in data.units do
		local uid = unit.uid
		local card = cards[uid]
		if not card then
			card = UnitCard.create(view.cards)
			bindCard(card.button, function()
				local current = unitsByUid[uid]
				return if current then uid else nil, if current then current.name else nil
			end)
			cards[uid] = card
		end
		card.button.LayoutOrder = order
	end
end

local function runRequest(startBattle: boolean): ()
	if busy or teamIndex > presetCount() then
		return
	end
	local current = board
	if startBattle and (not current or TeamBoardDraft.count(current.slots) == 0) then
		return
	end

	local snapshot = if current and dirty then table.clone(current.slots) else nil
	busy = true
	status(
		if snapshot then "Saving team…" elseif startBattle then "Starting practice battle…" else "Loading team…"
	)
	refresh()
	local finished = false
	task.delay(SLOW_REQUEST, function()
		if not finished then
			status("Still waiting for the server.")
		end
	end)

	local failure: string? = nil
	if snapshot or not startBattle then
		local data, message, code = TeamBoardRemote.load(teamIndex, snapshot)
		failure = if data then nil else message or "Request failed. Try again."
		if data then
			showBoard(data)
			dirty = false
			selectedUid = nil
		elseif code == "UNIT_NOT_OWNED" then
			local refreshed = TeamBoardRemote.load(teamIndex)
			if refreshed then
				showBoard(refreshed)
				dirty = false
				selectedUid = nil
				failure = "A unit is no longer owned. Your saved team was reloaded."
			end
		end
	end
	if startBattle and failure == nil then
		status("Starting practice battle…")
		local ok, message = TeamBoardRemote.startPractice(teamIndex)
		if not ok then
			failure = message or "Battle could not start. Try again."
		end
	end
	finished = true
	busy = false
	if failure then
		status(failure, true)
	elseif startBattle then
		status("Practice battle · no rewards.")
	elseif snapshot then
		status("Team saved.")
	else
		status("Select a unit, then choose a slot.")
	end
	refresh()
	if view.screen.Enabled then
		UIController.focus(if board then view.cells[1] else view.save)
	end
end

local function openFilter(filterElement: boolean): ()
	if not canInteract() then
		return
	end
	local choices: { Modal.Choice } = { { label = if filterElement then "All elements" else "All rarities" } }
	for _, label in if filterElement then ELEMENTS else RARITIES do
		table.insert(choices, { label = label, value = label })
	end
	local sheet: Modal.View
	local restore: () -> ()
	local function close(): ()
		restore()
		sheet.screen:Destroy()
	end
	sheet = Modal.create(
		playerGui,
		if filterElement then "Filter by element" else "Filter by rarity",
		choices,
		if filterElement then element else rarity,
		function(choice)
			if filterElement then
				element = choice
			else
				rarity = choice
			end
			selectedUid = nil
			close()
			refresh()
		end,
		close
	)
	restore = UIController.overlay(sheet.screen, sheet.first)
end

local function openPresets(): ()
	if busy or not view.screen.Enabled then
		return
	end
	local choices: { Modal.Choice } = {}
	for index = 1, presetCount() do
		table.insert(choices, { label = "Load preset " .. index, value = tostring(index) })
	end
	local sheet: Modal.View
	local restore: () -> ()
	local function close()
		restore()
		sheet.screen:Destroy()
	end
	sheet = Modal.create(
		playerGui,
		if dirty then "Unsaved team changes" else "Choose a preset",
		choices,
		tostring(teamIndex),
		function(value)
			local index = tonumber(value)
			close()
			if not index or index == teamIndex or index > presetCount() then
				return
			end
			teamIndex = index
			dirty = false
			selectedUid = nil
			board = nil
			runRequest(false)
		end,
		close,
		{
			body = if dirty
				then { "Loading a different preset discards this draft. Cancel to keep editing or save first." }
				else {},
			closeText = "Cancel",
		}
	)
	restore = UIController.overlay(sheet.screen, sheet.first)
end

local function wire(): ()
	bindCard = TeamBoardDrag.mount(
		playerGui,
		view.screen,
		view.boardScroll,
		view.cells,
		canInteract,
		selectUnit,
		function(uid, index)
			local current = board
			if current and current.slots[index] ~= uid then
				placeUnit(uid, index)
			end
		end
	)

	for index, cell in view.cells do
		cell.Activated:Connect(function()
			local current = board
			if not current or not canInteract() then
				return
			end
			if selectedUid then
				placeUnit(selectedUid, index)
			elseif current.slots[index] ~= EMPTY then
				selectUnit(current.slots[index])
			end
		end)
	end
	local function goBack(): ()
		if backToMenu and not busy then
			backToMenu()
		end
	end
	view.back.Activated:Connect(goBack)
	view.preset.Activated:Connect(openPresets)
	player:GetAttributeChangedSignal("PassExtraPresets"):Connect(refresh)
	view.save.Activated:Connect(function()
		runRequest(false)
	end)
	view.play.Activated:Connect(function()
		runRequest(true)
	end)
	view.elementFilter.Activated:Connect(function()
		openFilter(true)
	end)
	view.rarityFilter.Activated:Connect(function()
		openFilter(false)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and view.screen.Enabled and input.KeyCode == Enum.KeyCode.ButtonB then
			goBack()
		end
	end)
end

function TeamBoardController.open(onBack: (() -> ())?): ()
	backToMenu = onBack
	if not view then
		playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		view = TeamBoardView.create(playerGui)
		wire()
	end
	view.back.Visible = onBack ~= nil
	refresh()
	UIController.show(view.screen, if onBack then view.back elseif board then view.cells[1] else view.save)
	if not dirty then
		if teamIndex > presetCount() then
			teamIndex = 1
			board = nil
		end
		task.spawn(runRequest, false)
	end
end

return TeamBoardController
