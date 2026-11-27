--!strict

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.Trade)
local Controls = require(script.Parent.Components.Controls)
local Page = require(script.Parent.ProgressPage)
local LobbyPage = require(script.Parent.LobbyPage)
local Theme = require(script.Parent.Theme)
local TradeState = require(script.Parent.TradeState)

type View = TradeState.View
type Offer = TradeState.Offer

export type Model = {
	view: View?,
	notice: string,
	pending: boolean,
	now: number,
}
export type Draw = { timer: TextLabel?, confirm: TextButton? }

local TradeView = {}

function TradeView.button(page: Page.Page, id: string, title: string, enabled: boolean, act: () -> ()): TextButton
	local button = Page.button(page.body, title, function()
		if enabled then
			act()
		end
	end)
	button.Name = id
	Controls.setEnabled(button, enabled)
	return button
end

function TradeView.error(page: Page.Page, message: string): ()
	Page.label(page.body, message).TextColor3 = Theme.error
end

local function offerColumn(row: Frame, title: string, status: string, offer: Offer, empty: string): ()
	local card = Controls.panel(UDim2.new(0.5, -Theme.gap / 2, 0, 0), row)
	card.AutomaticSize = Enum.AutomaticSize.Y
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Theme.gap)
	padding.PaddingBottom = UDim.new(0, Theme.gap)
	padding.PaddingLeft = UDim.new(0, Theme.gap)
	padding.PaddingRight = UDim.new(0, Theme.gap)
	padding.Parent = card
	Controls.flow(card)
	Page.label(card, title).Font = Theme.bold
	Page.label(card, status).TextColor3 = Theme.muted
	if #offer.units + #offer.skins == 0 then
		Page.label(card, empty).TextColor3 = Theme.error
	end
	for _, unit in offer.units do
		local line = Page.label(card, string.format("%s\n%s · %d★", unit.name, unit.rarity, unit.stars))
		line.TextColor3 = Theme.rarity[unit.rarity] or Theme.text
	end
	for _, skin in offer.skins do
		Page.label(card, "Skin · " .. skin.name)
	end
end

local function approvalText(ready: boolean, confirmed: boolean): string
	if confirmed then
		return "Confirmed"
	end
	return if ready then "Ready" else "Not ready"
end

local function offers(page: Page.Page, view: View): ()
	local row = Instance.new("Frame")
	row.Name = "Offers"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.gap)
	layout.Parent = row
	row.Parent = page.body
	offerColumn(row, "Your offer", approvalText(view.myReady, view.myConfirmed), view.mine, "You give nothing.")
	offerColumn(
		row,
		view.otherDisplayName .. "'s offer",
		approvalText(view.theirReady, view.theirConfirmed),
		view.theirs,
		"You receive nothing."
	)
end

function TradeView.begin(page: Page.Page, model: Model): (string?, Vector2)
	local selected = GuiService.SelectedObject
	local focus = if selected and selected.Parent == page.body then selected.Name else nil
	local position = page.body.CanvasPosition
	Page.clear(page)
	if model.pending then
		Page.label(page.body, "Waiting for the server…").TextColor3 = Theme.muted
	end
	if model.notice ~= "" then
		TradeView.error(page, model.notice)
	end
	return focus, position
end

function TradeView.finish(page: Page.Page, focus: string?, position: Vector2): ()
	local button = focus and page.body:FindFirstChild(focus)
	local selection = if button and button:IsA("TextButton") and button.Selectable then button else page.back
	LobbyPage.focus(page, selection)
	page.body.CanvasPosition = position
end

function TradeView.session(page: Page.Page, model: Model, send: (string, ...any) -> ()): Draw
	local view = assert(model.view, "A trade session view is required")
	local id, revision = view.sessionId, view.revision
	local draw: Draw = {}
	local live = model.now < view.expiresAt
	local available = live and not model.pending
	if view.status == "Done" then
		Page.label(page.body, "Trade completed.").Font = Theme.bold
	elseif view.status == "Cancelled" then
		TradeView.error(page, "Trade cancelled." .. (if view.reason then " (" .. view.reason .. ")" else ""))
	elseif not live and view.status ~= "Confirmed" then
		TradeView.error(page, "Trade time ended. Waiting for the server’s final status.")
	elseif view.status == "Requested" then
		if view.initiatorUserId == view.selfUserId then
			Page.label(page.body, "Waiting for " .. view.otherDisplayName .. " to accept.")
		else
			Page.label(page.body, view.otherDisplayName .. " wants to trade with you.")
			TradeView.button(page, "Accept", "Accept request", available, function()
				send("RespondTrade", id, true)
			end)
			TradeView.button(page, "Decline", "Decline request", available, function()
				send("RespondTrade", id, false)
			end)
		end
	else
		offers(page, view)
		Page.label(
			page.body,
			string.format(
				"Each player pays %d Gold. Traded units lose their trait and reset to level 1. The sender gets a %g%% Gold and XP Scroll upgrade refund.",
				Config.taxGold,
				Config.levelRefundRate * 100
			)
		)
		if view.status == "Countdown" or view.status == "Confirmed" then
			Page.label(page.body, "Offers are locked. Review both sides before confirming.")
			draw.timer = Page.label(page.body, "")
			if not view.myConfirmed then
				draw.confirm = TradeView.button(
					page,
					"Confirm",
					"Confirm trade",
					available and TradeState.canConfirm(view, model.now),
					function()
						send("ConfirmTrade", id, revision)
					end
				)
			end
		elseif TradeState.canEdit(view, model.now) then
			TradeView.button(page, "Ready", if view.myReady then "Undo Ready" else "Ready", available, function()
				send("SetReady", id, not view.myReady, revision)
			end)
		end
	end
	if live and not TradeState.terminal(view) and view.status ~= "Confirmed" then
		if view.status ~= "Requested" or view.initiatorUserId == view.selfUserId then
			TradeView.button(page, "Cancel", "Cancel trade", available, function()
				send("CancelTrade", id)
			end)
		end
	end
	return draw
end

function TradeView.updateTime(draw: Draw, view: View, now: number): ()
	local timer = draw.timer
	if timer then
		local remaining = math.max(0, math.ceil((view.countdownEndsAt or now) - now))
		timer.Text = if view.status == "Confirmed"
			then "Finalizing trade…"
			elseif view.myConfirmed then "Waiting for your partner to confirm."
			elseif remaining > 0 then string.format("Confirm available in %ds.", remaining)
			else "Confirm when you are ready."
	end
end

return table.freeze(TradeView)
