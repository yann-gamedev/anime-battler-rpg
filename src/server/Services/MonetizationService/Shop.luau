--!strict
-- Handler remote toko: GetShopInfo, PrepareShopPurchase, BuyAcademyItem. Tidak ada reward dari sini
-- untuk produk Robux: PrepareShopPurchase hanya memberi ID agar client bisa membuka prompt Roblox,
-- isi produk diberikan oleh ProcessReceipt (Developer Product) atau cache gamepass.
-- Toko Akademi terbuka untuk SEMUA pemain (termasuk restricted): non-acak, harga Gems tetap dari config.
-- Status restricted hanya menyembunyikan paket Trait Shards (mata uang item acak berbayar).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Products = require(Shared.Config.Products)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)

type ShopState = {
	gems: number,
	shards: number,
	firstBonusUsed: { [string]: boolean },
	academyOwned: { [string]: boolean },
	premiumSeasons: { [string]: boolean },
}
export type Deps = {
	ledger: {
		getShopState: (player: Player) -> ShopState?,
		buyAcademy: (player: Player, item: Types.AcademyItemDef) -> string?,
	},
	isRestricted: (player: Player) -> boolean, -- boleh yield (ComplianceService)
	isPresent: (player: Player) -> boolean,
	hasPass: (player: Player, key: string) -> boolean,
	activeSeasonId: () -> string?,
	definitions: { [string]: Types.ProductDef }?, -- default Config/Products (override untuk test)
}
export type Handlers = {
	GetShopInfo: (player: Player, ...any) -> Types.Result,
	PrepareShopPurchase: (player: Player, ...any) -> Types.Result,
	BuyAcademyItem: (player: Player, ...any) -> Types.Result,
}

-- Paket mata uang item acak berbayar: disembunyikan & tidak bisa disiapkan untuk pemain restricted.
local PAID_RANDOM_CURRENCIES: { [string]: boolean } = { TraitShards = true }
local isKey = Validate.isStringMax(Constants.MAX_SHOP_KEY_LENGTH)

local academyById: { [string]: Types.AcademyItemDef } = {}
for _, item in Products.academy do
	academyById[item.id] = item
end
local listed: { [string]: boolean } = {}
for _, key in Products.displayOrder do
	listed[key] = true
end

local Shop = {}

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

local function isHiddenFor(def: Types.ProductDef, restricted: boolean): boolean
	return restricted and def.grant ~= nil and PAID_RANDOM_CURRENCIES[def.grant.currency] == true
end

function Shop.create(deps: Deps): Handlers
	local defs = deps.definitions or Products.definitions
	-- (owned, available) produk untuk pemain ini.
	local function productStatus(
		player: Player,
		key: string,
		def: Types.ProductDef,
		state: ShopState
	): (boolean, boolean)
		local published = def.id > 0
		if def.kind == "GamePass" then
			local owned = deps.hasPass(player, key)
			return owned, published and not owned
		end
		local seasonId = def.battlePassSeasonId
		if seasonId then
			local owned = state.premiumSeasons[seasonId] == true
			return owned, published and not owned and deps.activeSeasonId() == seasonId
		end
		return false, published and def.grant ~= nil
	end

	local function buildInfo(player: Player, restricted: boolean): Types.ShopInfo?
		local state = deps.ledger.getShopState(player)
		if not state then
			return nil
		end
		local products: { Types.ShopProductView } = {}
		for _, key in Products.displayOrder do
			local def = defs[key]
			if def and not isHiddenFor(def, restricted) then
				local owned, available = productStatus(player, key, def, state)
				local grant = def.grant
				local isGems = grant ~= nil and grant.currency == "Gems"
				table.insert(products, {
					key = key,
					id = def.id,
					kind = def.kind,
					name = def.name or key,
					priceRobux = def.priceRobux,
					available = available,
					owned = owned,
					firstBonus = if isGems then state.firstBonusUsed[key] ~= true else nil,
					grant = if grant then { currency = grant.currency, amount = grant.amount } else nil,
				})
			end
		end
		local academy: { Types.AcademyItemView } = {}
		for _, item in Products.academy do
			table.insert(academy, {
				id = item.id,
				name = item.name,
				kind = item.kind,
				itemId = item.itemId,
				costGems = item.costGems,
				owned = state.academyOwned[item.id] == true,
			})
		end
		return {
			restricted = restricted,
			balances = { Gems = state.gems, TraitShards = state.shards },
			products = products,
			academy = academy,
		}
	end

	-- Policy di-lookup dulu (boleh yield), lalu state dibaca setelah yield.
	local function respondInfo(player: Player): Types.Result
		local restricted = deps.isRestricted(player)
		if not deps.isPresent(player) then
			return failure("DATA_NOT_READY")
		end
		local info = buildInfo(player, restricted)
		if not info then
			return failure("DATA_NOT_READY")
		end
		return { ok = true, data = info }
	end

	local function getShopInfo(player: Player, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		return respondInfo(player)
	end

	local function prepare(player: Player, productKey: any, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		if not isKey(productKey) or not listed[productKey] then
			return failure("INVALID_PRODUCT")
		end
		local def = defs[productKey]
		if not def then
			return failure("INVALID_PRODUCT")
		end
		local restricted = deps.isRestricted(player)
		if not deps.isPresent(player) then
			return failure("DATA_NOT_READY")
		end
		if isHiddenFor(def, restricted) then
			return failure("RESTRICTED_REGION")
		end
		local state = deps.ledger.getShopState(player)
		if not state then
			return failure("DATA_NOT_READY")
		end
		local owned, available = productStatus(player, productKey, def, state)
		if owned then
			return failure("ALREADY_OWNED")
		end
		if not available then
			return failure("PRODUCT_UNAVAILABLE")
		end
		local data: Types.PreparedPurchase = { id = def.id, kind = def.kind }
		return { ok = true, data = data }
	end

	local function buyAcademy(player: Player, itemId: any, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		local item = if isKey(itemId) then academyById[itemId] else nil
		if not item then
			return failure("INVALID_ITEM")
		end
		-- Tanpa cek policy: Toko Akademi wajib tersedia untuk pemain restricted (RULES §4).
		local code = deps.ledger.buyAcademy(player, item)
		if code then
			return failure(code)
		end
		return respondInfo(player)
	end

	return { GetShopInfo = getShopInfo, PrepareShopPurchase = prepare, BuyAcademyItem = buyAcademy }
end

return table.freeze(Shop)
