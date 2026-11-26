--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Controls = require(script.Parent.Parent.UI.Components.Controls)
local TeamBoardView = require(script.Parent.Parent.UI.TeamBoardView)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIController = require(script.Parent.UIController)

type Unit = {
	uid: string,
	name: string,
	rarity: string,
	element: string,
	status: string,
	stars: number,
	level: number,
}

type Board = {
	slots: { string },
	units: { Unit },
	maxUnits: number,
}

local REMOTE_WAIT_SECONDS = 4
local SLOW_REQUEST_SECONDS = 12
local TEAM_INDEX = 1

local TeamBoardController = {}
local view: TeamBoardView.View
local board: Board?
local unitsByUid: { [string]: Unit } = {}
local cards: { [string]: TextButton } = {}
local selectedUid: string?
local backToMenu: (() -> ())?
local busy = false
local dirty = false

local function request(remoteName: string, slots: { string }?): (Board?, string?)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT_SECONDS)
	local remote = if remotes then remotes:WaitForChild(remoteName, REMOTE_WAIT_SECONDS) else nil
	if not remote or not remote:IsA("RemoteFunction") then
		return nil, "Team service unavailable. Try again."
	end

	local invoked, result = pcall(function()
		if slots then
			return remote:InvokeServer(TEAM_INDEX, slots)
		end
		return remote:InvokeServer()
	end)
	if not invoked then
		warn("[TeamBoard] " .. remoteName .. " failed: " .. tostring(result))
		return nil, "Connection failed. Try again."
	end
	if type(result) ~= "table" or result.ok ~= true then
		local code = if type(result) == "table" and type(result.code) == "string" then result.code else "UNKNOWN"
		return nil, "Request failed (" .. code .. "). Try again."
	end

	local data = result.data
	if
		type(data) ~= "table"
		or type(data.slots) ~= "table"
		or type(data.units) ~= "table"
		or type(data.maxUnits) ~= "number"
		or #data.slots ~= #view.cells
	then
		return nil, "Unexpected server reply. Try again."
	end
	for index = 1, #view.cells do
		if type(data.slots[index]) ~= "string" then
			return nil, "Unexpected server reply. Try again."
		end
	end
	for _, unit in data.units do
		if
			type(unit) ~= "table"
			or type(unit.uid) ~= "string"
			or type(unit.name) ~= "string"
			or type(unit.rarity) ~= "string"
			or type(unit.element) ~= "string"
			or type(unit.status) ~= "string"
			or type(unit.stars) ~= "number"
			or type(unit.level) ~= "number"
		then
			return nil, "Unexpected unit data. Try again."
		end
	end
	return data, nil
end

local function status(message: string, isError: boolean?): ()
	view.status.Text = message
	view.status.TextColor3 = if isError then Theme.error else Theme.muted
end

local function setEnabled(button: TextButton, enabled: boolean): ()
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
	button.TextColor3 = if enabled then Theme.text else Theme.muted
end

local function occupiedCount(slots: { string }): number
	local count = 0
	for _, uid in slots do
		if uid ~= "" then
			count += 1
		end
	end
	return count
end

local function refresh(): ()
	local current = board
	local placed: { [string]: number } = {}
	if current then
		view.count.Text =
			string.format("Front row at top  ·  %d/%d deployed", occupiedCount(current.slots), current.maxUnits)
	else
		view.count.Text = "Front row at top"
	end
	for index, cell in view.cells do
		local uid = if current then current.slots[index] else ""
		local unit = unitsByUid[uid]
		cell.Text = if unit then unit.name elseif uid ~= "" then "Unknown unit" else "Empty"
		cell.BackgroundColor3 = if uid == selectedUid then Theme.accent else Theme.button
		setEnabled(cell, current ~= nil and not busy)
		if uid ~= "" then
			placed[uid] = index
		end
	end
	for uid, card in cards do
		local unit = unitsByUid[uid]
		local slot = placed[uid]
		local location = if slot then string.format("  ·  Slot %d", slot) else ""
		card.Text = string.format(
			"%s  ·  Lv %d  ·  %d★%s\n%s  ·  %s  ·  %s",
			unit.name,
			unit.level,
			unit.stars,
			location,
			unit.rarity,
			unit.element,
			unit.status
		)
		card.BackgroundColor3 = if uid == selectedUid then Theme.accent else Theme.button
		setEnabled(card, not busy)
	end
	view.action.Text = if current then "Save team" else "Retry"
	setEnabled(view.action, not busy and (current == nil or dirty))
	setEnabled(view.back, backToMenu ~= nil)
end

local function showSelection(uid: string): ()
	selectedUid = uid
	status("Tap a slot to place or move. Tap the same slot to remove.")
	refresh()
end

local function showBoard(data: Board): ()
	board = data
	table.clear(unitsByUid)
	for _, unit in data.units do
		unitsByUid[unit.uid] = unit
	end
	for uid, card in cards do
		if not unitsByUid[uid] then
			card:Destroy()
			cards[uid] = nil
		end
	end

	view.roster.Text = if #data.units == 0 then "No units in your roster" else "Your units"
	for index, unit in data.units do
		local uid = unit.uid
		local card = cards[uid]
		if not card then
			card = Controls.button("", UDim2.new(1, 0, 0, Theme.cardHeight), view.scroll)
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Color = Theme.rarity[unit.rarity] or Theme.border
			stroke.Parent = card
			card.Activated:Connect(function()
				if not busy then
					showSelection(uid)
					view.scroll.CanvasPosition = Vector2.zero
					UIController.focus(view.cells[1])
				end
			end)
			cards[uid] = card
		end
		card.LayoutOrder = view.roster.LayoutOrder + index
	end
end

local function sync(): ()
	if busy then
		return
	end
	local current = board
	if current and not dirty then
		return
	end

	busy = true
	status(if current then "Saving team…" else "Loading team…")
	refresh()
	local finished = false
	task.delay(SLOW_REQUEST_SECONDS, function()
		if not finished then
			status("Still waiting for the team server.")
		end
	end)
	local snapshot = if current then table.clone(current.slots) else nil
	local result, failure = request(if snapshot then "SaveTeam" else "GetTeamBoard", snapshot)
	finished = true
	busy = false
	if result then
		showBoard(result)
		dirty = false
		selectedUid = nil
		status(if current then "Team saved." else "Select a unit, then tap a slot.")
	else
		status(failure or "Request failed. Try again.", true)
	end
	refresh()
	if view.screen.Enabled then
		UIController.focus(if board then view.cells[1] else view.action)
	end
end

local function activateCell(index: number): ()
	local current = board
	if busy or not current then
		return
	end
	local target = current.slots[index]
	local selected = selectedUid
	if not selected then
		if target ~= "" and unitsByUid[target] then
			showSelection(target)
		end
		return
	end

	local previous = table.find(current.slots, selected)
	if previous == index then
		current.slots[index] = ""
	elseif previous then
		current.slots[previous] = target
		current.slots[index] = selected
	elseif target ~= "" or occupiedCount(current.slots) < current.maxUnits then
		current.slots[index] = selected
	else
		status("Team is full. Choose an occupied slot to replace a unit.", true)
		return
	end

	selectedUid = nil
	dirty = true
	status("Unsaved changes.")
	refresh()
end

function TeamBoardController.open(onBack: (() -> ())?): ()
	backToMenu = onBack
	if not view then
		view = TeamBoardView.create(Players.LocalPlayer:WaitForChild("PlayerGui"))
		for index, cell in view.cells do
			cell.Activated:Connect(function()
				activateCell(index)
			end)
		end
		local function goBack(): ()
			if backToMenu then
				backToMenu()
			end
		end
		view.back.Activated:Connect(goBack)
		view.action.Activated:Connect(sync)
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and view.screen.Enabled and input.KeyCode == Enum.KeyCode.ButtonB then
				goBack()
			end
		end)
	end
	view.back.Visible = onBack ~= nil
	refresh()
	UIController.show(view.screen, if onBack then view.back else view.action)
	if not board then
		task.spawn(sync)
	end
end

return TeamBoardController
