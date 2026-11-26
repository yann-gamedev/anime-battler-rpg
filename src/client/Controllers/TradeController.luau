--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Config = require(ReplicatedStorage.Shared.Config.Trade)

local UI = script.Parent.Parent.UI
local Controls = require(UI.Components.Controls)
local LobbyPage = require(UI.LobbyPage)
local Page = require(UI.ProgressPage)
local ProgressRemote = require(UI.ProgressRemote)
local Theme = require(UI.Theme)
local TradePicker = require(UI.TradePicker)
local TradeState = require(UI.TradeState)
local TradeView = require(UI.TradeView)
local UIController = require(script.Parent.UIController)

local RESPONSE_TIMEOUT = 8
local errors: { [string]: string } = {
	TRADE_DISABLED = "Trading is currently unavailable.",
	COUNTDOWN_ACTIVE = "Wait for the countdown to finish before confirming.",
	TRADE_LOCKED = "Both offers are locked.",
	RATE_LIMITED = "Wait a moment before trying again.",
}
local player = Players.LocalPlayer

local TradeController = {}
local state = TradeState.new()
local page: Page.Page?
local notification: TextButton?
local draw: TradeView.Draw = {}
local dismissed: string?
local notice = ""
local requestNumber = 0
local pending: number?
local pickerOpen = false
local profile: ProgressRemote.Snapshot?
local profileError: string?
local hasExpired = false
local confirmAvailable = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function expired(view: TradeState.View, time: number): boolean
	return not TradeState.terminal(view) and view.status ~= "Confirmed" and time >= view.expiresAt
end

local function visibleView(): TradeState.View?
	local view = state.view
	return if view and view.sessionId ~= dismissed then view else nil
end

local function updateNotification(): ()
	local button = notification
	if not button then
		return
	end
	local view = visibleView()
	local isOpen = page ~= nil and page.screen.Enabled
	button.Visible = view ~= nil and not isOpen
	if view and button.Visible then
		button.Text = if view.status == "Done"
			then "Trade completed · View"
			elseif view.status == "Cancelled" then "Trade cancelled · View"
			elseif TradeState.canRespond(view, now()) then "Trade request · " .. view.otherDisplayName
			else "View trade · " .. view.otherDisplayName
		if UserInputService.GamepadEnabled then
			button.Text ..= " · L3"
		end
	end
end

local render: () -> ()

local function apply(view: TradeState.View): ()
	local previous = state.view
	if not TradeState.apply(state, view, player.UserId, now()) then
		return
	end
	notice = ""
	if dismissed == view.sessionId and TradeState.terminal(view) then
		dismissed = nil
	end
	if not previous or previous.sessionId ~= view.sessionId or TradeState.terminal(view) then
		pending = nil
		pickerOpen = false
		profile = nil
		profileError = nil
	end
	render()
end

local function allowed(name: string, args: { any }): boolean
	local view = visibleView()
	local time = now()
	if pending then
		return false
	elseif name == "RequestTrade" then
		return view == nil or TradeState.terminal(view) or expired(view, time)
	elseif
		not view
		or args[1] ~= view.sessionId
		or TradeState.terminal(view)
		or view.status == "Confirmed"
		or expired(view, time)
	then
		return false
	elseif name == "SetReady" then
		return TradeState.canEdit(view, time) and args[3] == view.revision
	elseif name == "SetTradeItems" then
		return TradeState.canEdit(view, time) and #args[2] + #args[3] <= Config.maxItemsPerSide
	elseif name == "ConfirmTrade" then
		return TradeState.canConfirm(view, time) and args[2] == view.revision
	elseif name == "RespondTrade" then
		return TradeState.canRespond(view, time)
	end
	return name == "CancelTrade"
end

local function send(name: string, ...: any): ()
	local args = table.pack(...)
	if not allowed(name, args) then
		return
	end
	requestNumber += 1
	local ticket = requestNumber
	local startedAt = state.view
	pending = ticket
	notice = ""
	render()

	task.delay(RESPONSE_TIMEOUT, function()
		if pending == ticket then
			pending = nil
			notice = "No reply yet. The latest server update will appear here."
			render()
		end
	end)

	local folder = ReplicatedStorage:FindFirstChild(Remotes.FOLDER_NAME)
	local remote = folder and folder:FindFirstChild(name)
	local okay, reply = false, nil :: any
	if remote and remote:IsA("RemoteFunction") then
		okay, reply = pcall(remote.InvokeServer, remote, table.unpack(args, 1, args.n))
		if not okay then
			warn("[Trade] " .. name .. ": " .. tostring(reply))
		end
	end

	local current = state.view
	local data = if okay and type(reply) == "table" then reply.data else nil
	local ownsPending = pending == ticket
	if ownsPending then
		pending = nil
	end
	if type(data) == "table" and (current == startedAt or (current and current.sessionId == data.sessionId)) then
		apply(data)
	end
	if ownsPending then
		if not okay or type(reply) ~= "table" then
			notice = "Connection interrupted. Check the current trade before retrying."
		elseif reply.ok ~= true then
			local code = if type(reply.code) == "string" then reply.code else "UNKNOWN"
			notice = errors[code] or string.format("Trade action rejected (%s).", code)
		end
		render()
	end
end

local function loadPicker(): ()
	local view = visibleView()
	if not view then
		return
	end
	pickerOpen = true
	profile, profileError = nil, nil
	render()
	local originalPage = page
	local snapshot, errorMessage = ProgressRemote.snapshot("GetMyData")
	local current = visibleView()
	if page == originalPage and pickerOpen and current and current.sessionId == view.sessionId then
		profile, profileError = snapshot, errorMessage
		render()
	end
end

render = function(): ()
	updateNotification()
	local current = page
	if not current or not current.screen.Enabled then
		return
	end
	local view = visibleView()
	local time = now()
	local model: TradeView.Model = {
		view = view,
		notice = notice,
		pending = pending ~= nil,
		now = time,
	}
	local focus, position = TradeView.begin(current, model)
	draw = {}
	hasExpired = view ~= nil and expired(view, time)
	confirmAvailable = view ~= nil and TradeState.canConfirm(view, time)
	if view then
		draw = TradeView.session(current, model, send)
		TradeView.updateTime(draw, view, time)
		if TradeState.canEdit(view, time) then
			TradeView.button(
				current,
				"Picker",
				if pickerOpen then "Hide items" else "Edit offer",
				pending == nil,
				function()
					if pickerOpen then
						pickerOpen = false
						render()
					else
						loadPicker()
					end
				end
			)
			if pickerOpen then
				if profile then
					TradePicker.items(
						current,
						view,
						profile,
						Config.maxItemsPerSide,
						pending == nil,
						function(units, skins)
							if visibleView() == view then
								send("SetTradeItems", view.sessionId, units, skins)
							end
						end
					)
				elseif profileError then
					TradeView.error(current, profileError)
					TradeView.button(current, "ReloadItems", "Reload items", true, loadPicker)
				else
					Page.label(current.body, "Loading inventory…")
				end
			end
		elseif TradeState.terminal(view) or hasExpired then
			TradeView.button(current, "Find", "Find nearby players", pending == nil, function()
				dismissed = view.sessionId
				notice = ""
				render()
			end)
		end
	else
		TradePicker.peers(current, pending == nil, function(userId)
			send("RequestTrade", userId)
		end)
		TradeView.button(current, "Refresh", "Refresh nearby players", pending == nil, render)
	end
	TradeView.finish(current, focus, position)
end

function TradeController.open(): ()
	if page and page.screen.Enabled then
		return
	end
	if page then
		page.screen:Destroy()
	end
	local restore: () -> ()
	local function close(): ()
		local current = page
		if not current or not current.screen.Enabled then
			return
		end
		local view = visibleView()
		if view and TradeState.terminal(view) then
			dismissed = view.sessionId
		end
		page = nil
		pickerOpen = false
		restore()
		current.screen:Destroy()
		updateNotification()
	end
	local current = Page.create(player:WaitForChild("PlayerGui") :: PlayerGui, "Trade", close)
	current.back.Text = "Close"
	page = current
	restore = UIController.overlay(current.screen, current.back)
	LobbyPage.bindBack(current.screen, close)
	render()
end

function TradeController.start(): ()
	local screen = Instance.new("ScreenGui")
	screen.Name = "TradeNotification"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 5
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local button = Controls.button("View trade", UDim2.new(0.75, 0, 0, 2 * Theme.touch), screen)
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, Theme.touch + 2 * Theme.padding)
	button.Visible = false
	button.Activated:Connect(TradeController.open)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(Theme.modalWidth, math.huge)
	size.Parent = button
	screen.Parent = player:WaitForChild("PlayerGui")
	notification = button

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and button.Visible and input.KeyCode == Enum.KeyCode.ButtonL3 then
			TradeController.open()
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(updateNotification)

	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, RESPONSE_TIMEOUT)
		local event = folder and folder:WaitForChild("TradeUpdated", RESPONSE_TIMEOUT)
		if event and event:IsA("RemoteEvent") then
			event.OnClientEvent:Connect(apply)
		else
			warn("[Trade] TradeUpdated unavailable")
		end
	end)
	task.spawn(function()
		while screen.Parent do
			task.wait(0.2)
			local view = visibleView()
			if view then
				local time = now()
				if page and page.screen.Enabled then
					if expired(view, time) ~= hasExpired or TradeState.canConfirm(view, time) ~= confirmAvailable then
						render()
					else
						TradeView.updateTime(draw, view, time)
					end
				else
					updateNotification()
				end
			end
		end
	end)
end

return table.freeze(TradeController)
