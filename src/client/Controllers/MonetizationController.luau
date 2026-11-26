--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local UI = script.Parent.Parent.UI
local UIController = require(script.Parent.UIController)
local Page = require(UI.ProgressPage)
local Controls = require(UI.Components.Controls)
local Modal = require(UI.Components.Modal)
local Remote = require(UI.MonetizationRemote)
local Purchase = require(UI.MarketplacePurchase)
local Pass = require(UI.BattlePassView)
local Theme = require(UI.Theme)

type Route = "Shop" | "Pass"
type Receipt = { product: Remote.Product, balance: number?, seasonId: string? }

local Controller = {}
local parent: PlayerGui
local pages: { [Route]: Page.Page } = {}
local route: Route = "Shop"
local track: Remote.Track = "Free"
local shop: Remote.ShopInfo?
local pass: Remote.PassInfo?
local asOf = 0
local notice = ""
local busy = false
local onBack: (() -> ())?
local receipt: Receipt?
local promptReceipt: Receipt?
local render: (boolean?) -> ()
local refresh: (string?) -> ()

local function active(): boolean
	return pages[route] ~= nil and pages[route].screen.Enabled
end

local function back(): ()
	if active() and not busy and not Purchase.isBusy() and onBack then
		local leave = onBack
		onBack = nil
		leave()
	end
end

local function start(message: string): boolean
	if not active() or busy or Purchase.isBusy() then
		return false
	end
	busy = true
	local page = pages[route]
	page.message.Text = message
	Controls.setEnabled(page.back, false)
	for _, child in page.body:GetChildren() do
		if child:IsA("TextButton") then
			Controls.setEnabled(child, false)
		end
	end
	task.delay(12, function()
		if busy and page.screen.Enabled and page.message.Text == message then
			page.message.Text = "Still waiting for the server."
		end
	end)
	return true
end

local function balance(product: Remote.Product, info: Remote.ShopInfo?): number?
	local grant = product.grant
	if info and grant then
		if grant.currency == "Gems" then
			return info.balances.Gems
		elseif grant.currency == "TraitShards" then
			return info.balances.TraitShards
		end
	end
	return nil
end

local function purchaseStatus(): string?
	local expected = receipt
	if not expected then
		return nil
	end
	local currentBalance = balance(expected.product, shop)
	local confirmed = (
		expected.product.key == "pass_premium"
		and pass ~= nil
		and pass.seasonId == expected.seasonId
		and pass.premium
	) or (currentBalance ~= nil and expected.balance ~= nil and currentBalance > expected.balance)
	for _, product in if shop then shop.products else {} do
		confirmed = confirmed or (product.key == expected.product.key and product.owned)
	end
	if confirmed then
		receipt = nil
		return "Account updated from the server."
	end
	return "Waiting for server confirmation. Refresh to check again."
end

refresh = function(message: string?)
	if not start("Refreshing from the server…") then
		return
	end
	local loaded, shopError = Remote.request("GetShopInfo")
	shop = loaded
	local passError: string?
	if route == "Pass" or (receipt and receipt.product.key == "pass_premium") then
		local updated, failure = Remote.request("GetBattlePass")
		pass = updated
		passError = failure
		asOf = workspace:GetServerTimeNow()
	end
	busy = false
	local receiptNotice = purchaseStatus()
	notice = (if route == "Pass" then passError else shopError) or message or receiptNotice or ""
	render(true)
end

local function mutate(name: string, ...: any): ()
	if not start("Updating account…") then
		return
	end
	local updated, failure = Remote.request(name, ...)
	if updated then
		if route == "Shop" then
			shop = updated
		else
			pass = updated
			asOf = workspace:GetServerTimeNow()
		end
		busy = false
		notice = if route == "Shop" then "Item purchased." else "Reward claimed."
		render(true)
	else
		busy = false
		refresh(failure)
	end
end

local function choose(title: string, choices: { Modal.Choice }, action: (string?) -> ()): ()
	if busy or Purchase.isBusy() or not active() then
		return
	end
	local modal: Modal.View
	local restore: () -> ()
	local function close()
		restore()
		modal.screen:Destroy()
	end
	modal = Modal.create(parent, title, choices, nil, function(value)
		close()
		action(value)
	end, close)
	restore = UIController.overlay(modal.screen, modal.first)
end

local function addProduct(page: Page.Page, product: Remote.Product, restricted: boolean): ()
	if Purchase.isHidden(product, restricted) then
		return
	end
	local label = product.name
	local grant = product.grant
	if grant then
		label ..= string.format(" · %d %s", grant.amount, grant.currency)
	end
	if product.firstBonus then
		label ..= " · First purchase bonus active"
	end
	Page.label(page.body, label)
	local price: number?
	local eligible = Purchase.canQuote(product, restricted)
	local button: TextButton
	button = Page.button(
		page.body,
		if product.owned then "Owned" elseif eligible then "Checking Roblox price…" else "Unavailable",
		function()
			if
				price == nil
				or not Purchase.canQuote(product, restricted)
				or not start("Opening Roblox purchase…")
			then
				return
			end
			receipt = nil
			promptReceipt = {
				product = product,
				balance = balance(product, shop),
				seasonId = if pass then pass.seasonId else nil,
			}
			local failure = Purchase.open(product, restricted, price, function()
				local season = pass
				local now = workspace:GetServerTimeNow()
				return button.Parent ~= nil
					and active()
					and (
						product.key ~= "pass_premium"
						or (season ~= nil and season.active and now >= season.startsAt and now < season.endsAt)
					)
			end)
			busy = false
			if failure then
				promptReceipt = nil
				refresh(failure)
			elseif Purchase.isBusy() then
				page.message.Text = "Roblox purchase prompt open."
			else
				refresh()
			end
		end
	)
	Controls.setEnabled(button, false)
	if eligible then
		task.spawn(function()
			price = Purchase.getPrice(product)
			if button.Parent then
				button.Text = if price ~= nil then string.format("%d Robux", price) else "Roblox price unavailable"
				Controls.setEnabled(button, price ~= nil and not busy and not Purchase.isBusy())
			end
		end)
	end
end

local function renderShop(page: Page.Page, info: Remote.ShopInfo): ()
	Page.label(page.body, string.format("Gems %d · Trait Shards %d", info.balances.Gems, info.balances.TraitShards))
	Page.label(page.body, "Direct purchases").Font = Theme.bold
	for _, item in info.academy do
		Page.label(page.body, item.name .. (if item.kind == "Skin" then " · Skin entitlement" else " · Unit"))
		local cost = string.format("%d Gems", item.costGems)
		local affordable = info.balances.Gems >= item.costGems
		local button = Page.button(
			page.body,
			if item.owned then "Owned" elseif affordable then "Buy · " .. cost else "Need " .. cost,
			function()
				if not item.owned and affordable then
					choose(
						"Buy " .. item.name .. "?",
						{ { label = "Confirm · " .. cost, value = item.id } },
						function(id)
							if id then
								mutate("BuyAcademyItem", id)
							end
						end
					)
				end
			end
		)
		Controls.setEnabled(button, affordable and not item.owned)
	end
	Page.label(page.body, "Roblox purchases").Font = Theme.bold
	for _, product in info.products do
		if product.key ~= "pass_premium" then
			addProduct(page, product, info.restricted)
		end
	end
end

local function renderPass(page: Page.Page, info: Remote.PassInfo): ()
	Pass.profileFrame(page, info.profileFrameId, Players.LocalPlayer.DisplayName)
	Page.label(page.body, info.seasonId .. (if info.active then " · Active" else " · Inactive"))
	Page.label(page.body, "Starts " .. Pass.utc(info.startsAt) .. "\nEnds " .. Pass.utc(info.endsAt))
	Page.label(
		page.body,
		string.format(
			"As of %s\n%d XP · %d XP per tier · Tier %d reached",
			Pass.utc(asOf),
			info.xp,
			info.xpPerTier,
			info.unlockedTier
		)
	)
	local viewTrack = track
	Page.button(
		page.body,
		if viewTrack == "Free" then "Free track · View Premium" else "Premium track · View Free",
		function()
			track = if viewTrack == "Free" then "Premium" else "Free"
			page.body.CanvasPosition = Vector2.zero
			render()
		end
	)
	if viewTrack == "Premium" then
		local currentShop = shop
		local offer: Remote.Product?
		if currentShop then
			for _, product in currentShop.products do
				if product.key == "pass_premium" then
					offer = product
					break
				end
			end
		end
		if info.premium then
			Page.label(page.body, "Premium active for this season.")
		elseif info.active and offer and currentShop then
			addProduct(page, offer, currentShop.restricted)
		else
			Page.label(page.body, "Premium purchase unavailable.")
		end
	end
	Pass.tiers(page, info, viewTrack, function(tier, options)
		if options then
			local choices: { Modal.Choice } = {}
			for _, id in options do
				table.insert(choices, { label = Pass.unitName(id), value = id })
			end
			choose("Choose a unit for tier " .. tier, choices, function(id)
				if id then
					mutate("ClaimBattlePassTier", viewTrack, tier, id)
				end
			end)
		else
			mutate("ClaimBattlePassTier", viewTrack, tier)
		end
	end)
end

render = function(keepScroll: boolean?)
	local page = pages[route]
	local scroll = if keepScroll then page.body.CanvasPosition else Vector2.zero
	Page.clear(page)
	page.message.Text = notice
	Controls.setEnabled(page.back, true)
	local reload = Page.button(page.body, "Refresh", function()
		refresh()
	end)
	local info = shop
	local season = pass
	if route == "Shop" and info then
		renderShop(page, info)
	elseif route == "Pass" and season then
		renderPass(page, season)
	end
	page.body.CanvasPosition = scroll
	UIController.focus(if scroll.Y == 0 then reload else page.back)
end

local function open(destination: Route, returnToOrigin: () -> ()): ()
	if not pages.Shop then
		parent = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		pages.Shop = Page.create(parent, "Academy Shop", back)
		pages.Pass = Page.create(parent, "Battle Pass", back)
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and active() and input.KeyCode == Enum.KeyCode.ButtonB then
				task.defer(back)
			end
		end)
		Purchase.observe(function(_, submitted)
			local expected = promptReceipt
			promptReceipt = nil
			if submitted then
				receipt = expected
			end
			if active() then
				refresh(if submitted then nil else "Roblox purchase closed.")
			end
			if submitted then
				task.delay(3, function()
					if active() and receipt == expected then
						refresh()
					end
				end)
			end
		end)
	end
	route = destination
	onBack = returnToOrigin
	track = "Free"
	notice = ""
	shop = nil
	pass = nil
	local page = pages[route]
	UIController.show(page.screen, page.back)
	render()
	refresh()
end

function Controller.openShop(returnToOrigin: () -> ()): ()
	open("Shop", returnToOrigin)
end

function Controller.openPass(returnToOrigin: () -> ()): ()
	open("Pass", returnToOrigin)
end

return table.freeze(Controller)
