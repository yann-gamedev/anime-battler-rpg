--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Remote = require(script.Parent.MonetizationRemote)

local Purchase = {}
local player = Players.LocalPlayer
local pending: Remote.Product?
local preparing = false

function Purchase.isHidden(product: Remote.Product, restricted: boolean): boolean
	return restricted
		and (product.key == "shards_s" or (product.grant ~= nil and product.grant.currency == "TraitShards"))
end

function Purchase.canQuote(product: Remote.Product, restricted: boolean): boolean
	return product.available and product.id > 0 and not product.owned and not Purchase.isHidden(product, restricted)
end

function Purchase.getPrice(product: Remote.Product): number?
	local infoType = if product.kind == "GamePass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	local ok, info = pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, product.id, infoType)
	if not ok then
		warn("[Academy Shop] Price lookup failed for " .. product.key .. ": " .. tostring(info))
		return nil
	end
	local price = info.PriceInRobux
	return if info.IsForSale ~= false and type(price) == "number" and price >= 0 then price else nil
end

function Purchase.isBusy(): boolean
	return preparing or pending ~= nil
end

function Purchase.open(product: Remote.Product, restricted: boolean, price: number, canOpen: () -> boolean): string?
	if not Purchase.canQuote(product, restricted) or price < 0 or Purchase.isBusy() or not canOpen() then
		return "Purchase is unavailable."
	end
	preparing = true
	local prepared, failure = Remote.request("PrepareShopPurchase", product.key)
	preparing = false
	if not prepared or prepared.id ~= product.id or prepared.kind ~= product.kind then
		return failure or "This offer changed. Refresh for the latest price."
	end
	if not canOpen() then
		return "Purchase canceled."
	end
	pending = product
	local prompt = if product.kind == "GamePass"
		then MarketplaceService.PromptGamePassPurchase
		else MarketplaceService.PromptProductPurchase
	local ok, err = pcall(prompt, MarketplaceService, player, product.id)
	if not ok then
		pending = nil
		warn("[Academy Shop] Prompt failed: " .. tostring(err))
		return "Roblox could not open the purchase prompt."
	end
	return nil
end

function Purchase.observe(onFinished: (Remote.Product, boolean) -> ()): ()
	local function finish(kind: Remote.ProductKind, id: number, submitted: boolean)
		local product = pending
		if product and product.kind == kind and product.id == id then
			pending = nil
			onFinished(product, submitted)
		end
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, id, submitted)
		if userId == player.UserId then
			finish("DeveloperProduct", id, submitted)
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(owner, id, submitted)
		if owner == player then
			finish("GamePass", id, submitted)
		end
	end)
end

return table.freeze(Purchase)
