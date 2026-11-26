--!strict
-- Logika MarketplaceService.ProcessReceipt (satu callback untuk seluruh game, dipasang di init.luau).
-- Alur (docs Roblox "player-data-purchasing" + ProfileStore "Developer Products"):
--   validasi receipt → cari pemain & tunggu profil (terbatas) → grant + bonus pertama + robuxSpent +
--   marker PurchaseId dalam SATU commit DataService → PurchaseGranted HANYA setelah LastSavedData
--   memuat marker. Apa pun yang gagal/tidak dikenal → NotProcessedYet (Roblox mencoba lagi nanti).
-- Retry receipt yang sudah ditandai tidak memberi hadiah lagi; hanya menunggu bukti simpan.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Products = require(Shared.Config.Products)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)

export type Decision = "PurchaseGranted" | "NotProcessedYet"
export type Ledger = {
	isReceiptId: (purchaseId: any) -> boolean,
	grantReceipt: (player: Player, request: any) -> (string?, any),
	confirmSaved: (player: Player, purchaseId: string) -> boolean,
}
export type Deps = {
	ledger: Ledger,
	findPlayer: (userId: number) -> Player?,
	isPresent: (player: Player) -> boolean,
	hasProfile: (player: Player) -> boolean,
	isRobux: (currencyType: any) -> boolean,
	sleep: (seconds: number) -> (),
	clock: () -> number,
	log: ((message: string) -> ())?,
	onGranted: ((player: Player, productKey: string, robuxSpent: number, firstBonus: boolean) -> ())?,
}

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local GRANTED: Decision = "PurchaseGranted"
local NOT_YET: Decision = "NotProcessedYet"

local Receipts = {}

-- ProductId → key untuk Developer Product ber-ID asli yang punya isi (mata uang atau premium musim).
function Receipts.productIndex(definitions: { [string]: Types.ProductDef }): { [number]: string }
	local index: { [number]: string } = {}
	for key, def in definitions do
		local grantable = def.grant ~= nil or def.battlePassSeasonId ~= nil
		if def.kind == "DeveloperProduct" and def.id > 0 and grantable then
			assert(index[def.id] == nil, `Products: duplicate ProductId {def.id}`)
			index[def.id] = key
		end
	end
	return index
end

function Receipts.create(deps: Deps, definitions: { [string]: Types.ProductDef }?)
	local defs = definitions or Products.definitions
	local byId = Receipts.productIndex(defs)
	local log = deps.log or warn

	local function waitForProfile(player: Player): boolean
		local deadline = deps.clock() + Products.receipt.profileWaitSeconds
		while deps.isPresent(player) do
			if deps.hasProfile(player) then
				return true
			end
			if deps.clock() >= deadline then
				return false
			end
			deps.sleep(Products.receipt.profilePollSeconds)
		end
		return false
	end

	local function process(receiptInfo: any): Decision
		if type(receiptInfo) ~= "table" then
			log("[Monetization] receipt bukan tabel")
			return NOT_YET
		end
		local userId, purchaseId, productId = receiptInfo.PlayerId, receiptInfo.PurchaseId, receiptInfo.ProductId
		local spent = receiptInfo.CurrencySpent
		if
			not Validate.isIntInRange(userId, 1, MAX_EXACT_INTEGER)
			or not deps.ledger.isReceiptId(purchaseId)
			or not Validate.isIntInRange(productId, 1, MAX_EXACT_INTEGER)
			or not Validate.isIntInRange(spent, 0, MAX_EXACT_INTEGER)
		then
			log(`[Monetization] receipt tidak valid ProductId={tostring(productId)}`)
			return NOT_YET
		end
		local productKey = byId[productId]
		if not productKey then
			log(`[Monetization] ProductId tidak dikenal {productId}; receipt ditunda`)
			return NOT_YET
		end
		local player = deps.findPlayer(userId)
		if not player or player.UserId ~= userId or not waitForProfile(player) then
			return NOT_YET
		end
		local def = defs[productKey]
		local grant = def.grant
		local robuxSpent = if deps.isRobux(receiptInfo.CurrencyType) then spent else 0
		local code, result = deps.ledger.grantReceipt(player, {
			purchaseId = purchaseId,
			productKey = productKey,
			robuxSpent = robuxSpent,
			currency = if grant then { kind = grant.currency, amount = grant.amount } else nil,
			firstBonusMultiplier = if grant and grant.currency == "Gems"
				then Products.firstGemPurchaseMultiplier
				else nil,
			battlePassSeasonId = def.battlePassSeasonId,
		})
		if code ~= nil or result == nil then
			log(`[Monetization] grant gagal UserId={userId} product={productKey}: {code}`)
			return NOT_YET
		end
		if not result.duplicate then
			if result.premiumAlreadyOwned then
				log(`[Monetization] premium sudah dimiliki UserId={userId} product={productKey}`)
			end
			if deps.onGranted then
				deps.onGranted(player, productKey, robuxSpent, result.firstBonus)
			end
		end
		-- Hanya bukti LastSavedData yang boleh mengakui pembelian.
		if deps.ledger.confirmSaved(player, purchaseId) then
			return GRANTED
		end
		log(`[Monetization] receipt UserId={userId} product={productKey} belum terbukti tersimpan`)
		return NOT_YET
	end

	return { process = process, byId = byId }
end

return table.freeze(Receipts)
