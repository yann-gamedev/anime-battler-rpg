--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local UI = script.Parent.Parent.UI
local UIController = require(script.Parent.UIController)
local MonetizationController = require(script.Parent.MonetizationController)
local Page = require(UI.ProgressPage)
local Controls = require(UI.Components.Controls)
local Theme = require(UI.Theme)
local Remote = require(UI.SummonRemote)
local View = require(UI.SummonView)
local Details = require(UI.SummonDetails)

local SummonController = {}
local page: Page.Page
local oddsPage: Page.Page
local resultPage: Page.Page
local parent: PlayerGui
local returnToOrigin: (() -> ())?
local closeOdds: (() -> ())?
local info: Remote.Info?
local selectedId: string?
local busy = false
local status = ""
local rolls: { Remote.Roll }?
local watch: thread?
local render: () -> ()
local refresh: (string?) -> ()

local function selectedBanner(): Remote.Banner?
	local snapshot = info
	if not snapshot then
		return nil
	end
	for _, banner in snapshot.banners do
		if banner.id == selectedId then
			return banner
		end
	end
	return snapshot.banners[1]
end

local function begin(message: string): ()
	busy = true
	status = message
	render()
	task.delay(12, function()
		if busy and page.screen.Enabled and page.message.Text == message then
			page.message.Text = "Still waiting for the server…"
		end
	end)
end

local function stopWatching(): ()
	if watch then
		task.cancel(watch)
		watch = nil
	end
end

local function watchSchedule(snapshot: Remote.Info, requestedAt: number): ()
	stopWatching()
	local nextChange = math.huge
	for _, banner in snapshot.banners do
		if banner.startsAt and banner.startsAt > requestedAt then
			nextChange = math.min(nextChange, banner.startsAt)
		end
		if banner.endsAt and banner.endsAt > requestedAt then
			nextChange = math.min(nextChange, banner.endsAt)
		end
	end
	if nextChange < math.huge then
		watch = task.delay(math.max(0, nextChange - workspace:GetServerTimeNow()) + 0.1, function()
			watch = nil
			if not busy and info == snapshot and (page.screen.Enabled or oddsPage.screen.Enabled) then
				if closeOdds then
					closeOdds()
				end
				refresh()
			end
		end)
	end
end

refresh = function(message: string?)
	if busy or not page.screen.Enabled then
		return
	end
	stopWatching()
	info = nil
	begin("Loading banner information…")
	local requestedAt = workspace:GetServerTimeNow()
	local snapshot, code = Remote.getInfo()
	info = snapshot
	busy = false
	status = message or ""
	if code then
		status = if message then message .. " Refresh failed. Try Refresh banners." else Remote.message(code)
	end
	render()
	if snapshot then
		watchSchedule(snapshot, requestedAt)
	end
end

local function odds(opener: TextButton): ()
	local banner = selectedBanner()
	if busy or not banner or not page.screen.Enabled then
		return
	end
	if banner.active and not View.isActive(banner, workspace:GetServerTimeNow()) then
		refresh("The banner schedule changed. Review the refreshed information.")
		return
	end
	local restore: () -> ()
	local function show(position: number): ()
		Page.clear(oddsPage)
		oddsPage.message.Text = banner.kind .. " banner"
		oddsPage.body.CanvasPosition = Vector2.zero
		local first = Details.odds(oddsPage, banner, position, show)
		UIController.focus(first)
	end
	restore = UIController.overlay(oddsPage.screen)
	closeOdds = function()
		closeOdds = nil
		restore()
		UIController.focus(opener)
	end
	show(0)
end

local function shop(): ()
	if busy or not page.screen.Enabled then
		return
	end
	stopWatching()
	MonetizationController.openShop(function()
		UIController.show(page.screen)
		refresh()
	end)
end

local function backToBanner(): ()
	rolls = nil
	UIController.show(page.screen)
	refresh()
end

local function showResults(batch: { Remote.Roll }): ()
	if rolls ~= batch then
		return
	end
	Page.clear(resultPage)
	resultPage.body.CanvasPosition = Vector2.zero
	local snapshot = info
	resultPage.message.Text = if snapshot then View.balanceText(snapshot) else ""
	Controls.setEnabled(resultPage.back, true)
	UIController.show(resultPage.screen, Details.results(resultPage, batch, backToBanner))
end

local function reveal(batch: { Remote.Roll }, index: number): ()
	Page.clear(resultPage)
	resultPage.body.CanvasPosition = Vector2.zero
	resultPage.message.Text = ""
	Controls.setEnabled(resultPage.back, false)
	local first: TextButton
	first = Details.reveal(resultPage, batch, index, function()
		if rolls ~= batch or not first.Parent or not resultPage.screen.Enabled then
			return
		end
		if index == #batch then
			showResults(batch)
		else
			reveal(batch, index + 1)
		end
	end, function()
		showResults(batch)
	end)
	resultPage.back.NextSelectionDown = first
	UIController.show(resultPage.screen, first)
end

local function summon(count: Remote.Count, payment: Remote.Payment): ()
	local snapshot = info
	local banner = selectedBanner()
	if busy or not snapshot or not banner or not page.screen.Enabled then
		return
	end
	if not View.isActive(banner, workspace:GetServerTimeNow()) then
		refresh("This banner is currently inactive.")
		return
	end
	if View.blockReason(snapshot, banner, count, payment) then
		return
	end

	stopWatching()
	begin("Summoning…")
	local result, code = Remote.summon(banner.id, count, payment)
	busy = false
	if result then
		info = result.info
		rolls = result.rolls
		reveal(result.rolls, 1)
	else
		-- A failed reply can follow a committed mutation. Only the read is repeated.
		refresh(Remote.message(code or "INVALID_REPLY"))
	end
end

local function selectBanner(id: string): ()
	if busy or not page.screen.Enabled or selectedId == id then
		return
	end
	selectedId = id
	render()
end

render = function()
	Page.clear(page)
	page.body.CanvasPosition = Vector2.zero
	page.message.Text = status
	page.message.TextColor3 = if not busy and status ~= "" then Theme.error else Theme.muted
	Controls.setEnabled(page.back, not busy and returnToOrigin ~= nil)
	if busy then
		UIController.show(page.screen)
		return
	end

	local snapshot = info
	local first: TextButton?
	if snapshot then
		local banner = selectedBanner()
		selectedId = if banner then banner.id else nil
		first =
			View.banner(page, snapshot, banner, { select = selectBanner, odds = odds, summon = summon, shop = shop })
	end
	local reload = Page.button(page.body, "Refresh banners", function()
		refresh()
	end)
	page.back.NextSelectionDown = first or reload
	UIController.show(page.screen, first or reload)
end

local function back(): ()
	if busy then
		return
	end
	if oddsPage.screen.Enabled and closeOdds then
		closeOdds()
	elseif resultPage.screen.Enabled and rolls then
		if resultPage.back.Active then
			backToBanner()
		else
			showResults(rolls)
		end
	elseif page.screen.Enabled and returnToOrigin then
		local restore = returnToOrigin
		returnToOrigin = nil
		stopWatching()
		info = nil
		restore()
	end
end

function SummonController.open(onBack: () -> ()): ()
	if not page then
		parent = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		page = Page.create(parent, "Summon", back)
		oddsPage = Page.create(parent, "Odds", back)
		resultPage = Page.create(parent, "Results", back)
		UserInputService.InputBegan:Connect(function(input, processed)
			if
				not processed
				and input.KeyCode == Enum.KeyCode.ButtonB
				and (page.screen.Enabled or oddsPage.screen.Enabled or resultPage.screen.Enabled)
			then
				task.defer(back)
			end
		end)
	end
	returnToOrigin = onBack
	UIController.show(page.screen)
	refresh()
end

return SummonController
