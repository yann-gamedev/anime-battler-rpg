--!strict
-- Aturan murni monetisasi yang memutasi DRAFT profil (salinan): receipt Developer Product dan Toko Akademi.
-- Dipanggil hanya lewat DataService/Purchases, yang meng-commit draft secara atomik lewat Commit.run.
-- Tidak boleh yield. Field baru additive (purchases, battlePass) dilengkapi `reconcile` tanpa migrasi.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local StoryRules = require(script.Parent.StoryRules)
local SummonRules = require(script.Parent.SummonRules)

type Outcome = StoryRules.Outcome

export type ReceiptRequest = {
	purchaseId: string,
	productKey: string,
	robuxSpent: number, -- CurrencySpent aktual dari receipt (bukan harga config)
	currency: { kind: Types.CurrencyKind, amount: number }?,
	firstBonusMultiplier: number?, -- hanya paket Gems
	battlePassSeasonId: string?,
}
export type ReceiptResult = {
	duplicate: boolean,
	firstBonus: boolean,
	granted: number, -- jumlah mata uang yang diberikan (0 bila bukan paket mata uang)
	premiumAlreadyOwned: boolean,
}

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local PURCHASE_SOURCE = "robux_purchase"
local ACADEMY_SOURCE = "academy_shop"

local ShopRules = {}

local function isFlagMap(value: any): boolean
	return type(value) == "table"
end

local function sanitizeFlags(value: any): { [string]: boolean }
	local flags: { [string]: boolean } = {}
	if type(value) == "table" then
		for key, flag in value do
			if type(key) == "string" and flag == true then
				flags[key] = true
			end
		end
	end
	return flags
end

-- Record musim battle pass tersanitasi (salinan baru).
function ShopRules.readSeason(value: any): Types.BattlePassSeasonRecord
	local record = if type(value) == "table" then value else {}
	return {
		xp = if Validate.isIntInRange(record.xp, 0, MAX_EXACT_INTEGER) then record.xp else 0,
		premium = record.premium == true,
		freeClaimed = sanitizeFlags(record.freeClaimed),
		premiumClaimed = sanitizeFlags(record.premiumClaimed),
	}
end

-- Melengkapi field additive prompt 09 pada profil lama (v1) tanpa mengubah arti field yang ada.
function ShopRules.reconcile(profile: any): ()
	if type(profile.purchases) ~= "table" then
		profile.purchases = {}
	end
	local purchases = profile.purchases
	if not isFlagMap(purchases.firstBonus) then
		purchases.firstBonus = {}
	end
	if not isFlagMap(purchases.academy) then
		purchases.academy = {}
	end
	if type(profile.battlePass) ~= "table" then
		profile.battlePass = {}
	end
	if type(profile.battlePass.seasons) ~= "table" then
		profile.battlePass.seasons = {}
	end
	for seasonId, record in profile.battlePass.seasons do
		if type(seasonId) == "string" then
			profile.battlePass.seasons[seasonId] = ShopRules.readSeason(record)
		end
	end
	if type(profile.processedReceipts) ~= "table" then
		profile.processedReceipts = {}
	end
	if type(profile.skinsOwned) ~= "table" then
		profile.skinsOwned = {}
	end
	if type(profile.stats) == "table" and not Validate.isIntInRange(profile.stats.robuxSpent, 0, MAX_EXACT_INTEGER) then
		profile.stats.robuxSpent = 0
	end
end

-- Record musim di draft, dibuat bila belum ada.
function ShopRules.season(profile: Types.Profile, seasonId: string): Types.BattlePassSeasonRecord
	local seasons = profile.battlePass.seasons
	local record = seasons[seasonId]
	if not record then
		record = ShopRules.readSeason(nil)
		seasons[seasonId] = record
	end
	return record
end

-- Unit baru (1★, level 1) dengan UID server. Mengembalikan kode error atau unit.
function ShopRules.addUnit(
	profile: Types.Profile,
	unitId: string,
	source: Types.UnitSource,
	now: number,
	newUid: () -> string
): (string?, Types.OwnedUnit?)
	if SummonRules.countUnits(profile) >= Constants.MAX_UNITS_PER_PLAYER then
		return "INVENTORY_FULL", nil
	end
	local uid = newUid()
	if type(uid) ~= "string" or uid == "" or profile.units[uid] ~= nil then
		return "INTERNAL_ERROR", nil
	end
	local unit: Types.OwnedUnit = {
		uid = uid,
		unitId = unitId,
		stars = Constants.UNIT_STARS_MIN,
		level = Constants.UNIT_LEVEL_MIN,
		xp = 0,
		trait = nil,
		locked = false,
		tradeCooldownUntil = nil,
		obtainedAt = now,
		source = source,
	}
	profile.units[uid] = unit
	return nil, unit
end

local function isValidReceipt(request: ReceiptRequest): boolean
	if type(request) ~= "table" or type(request.purchaseId) ~= "string" or request.purchaseId == "" then
		return false
	end
	if type(request.productKey) ~= "string" or not Validate.isIntInRange(request.robuxSpent, 0, MAX_EXACT_INTEGER) then
		return false
	end
	local currency = request.currency
	if currency and not Validate.isIntInRange(currency.amount, 1, MAX_EXACT_INTEGER) then
		return false
	end
	local multiplier = request.firstBonusMultiplier
	if multiplier ~= nil and not Validate.isIntInRange(multiplier, 1, 10) then
		return false
	end
	-- Produk harus memberi sesuatu: mata uang atau premium musim.
	return currency ~= nil or type(request.battlePassSeasonId) == "string"
end

-- Grant + bonus pertama + robuxSpent + marker receipt dalam satu draft. Receipt yang sudah tercatat
-- tidak memberi apa pun lagi (duplicate = true).
function ShopRules.applyReceipt(profile: Types.Profile, request: ReceiptRequest): (string?, Outcome?, ReceiptResult?)
	if not isValidReceipt(request) then
		return "INVALID_RECEIPT", nil, nil
	end
	local outcome = StoryRules.newOutcome()
	local result: ReceiptResult = { duplicate = false, firstBonus = false, granted = 0, premiumAlreadyOwned = false }
	if profile.processedReceipts[request.purchaseId] == true then
		result.duplicate = true
		return nil, outcome, result
	end
	local currency = request.currency
	if currency then
		local amount = currency.amount
		local multiplier = request.firstBonusMultiplier
		if multiplier and profile.purchases.firstBonus[request.productKey] ~= true then
			amount *= multiplier
			profile.purchases.firstBonus[request.productKey] = true
			result.firstBonus = true
		end
		local code = StoryRules.changeCurrency(profile, outcome, currency.kind, amount, PURCHASE_SOURCE, false)
		if code then
			return code, nil, nil
		end
		result.granted = amount
	end
	local seasonId = request.battlePassSeasonId
	if seasonId then
		local record = ShopRules.season(profile, seasonId)
		result.premiumAlreadyOwned = record.premium
		record.premium = true
	end
	local spent = profile.stats.robuxSpent + request.robuxSpent
	profile.stats.robuxSpent = if spent <= MAX_EXACT_INTEGER then spent else MAX_EXACT_INTEGER
	profile.processedReceipts[request.purchaseId] = true
	return nil, outcome, result
end

-- Item Toko Akademi sudah dibeli (atau skin sudah dimiliki dari jalur lain).
function ShopRules.isAcademyOwned(profile: Types.Profile, item: Types.AcademyItemDef): boolean
	if profile.purchases.academy[item.id] == true then
		return true
	end
	return item.kind == "Skin" and profile.skinsOwned[item.itemId] == true
end

-- Pembelian Toko Akademi: harga Gems dari config (bukan client), sekali per item per akun.
function ShopRules.buyAcademy(
	profile: Types.Profile,
	item: Types.AcademyItemDef,
	now: number,
	newUid: () -> string
): (string?, Outcome?)
	if ShopRules.isAcademyOwned(profile, item) then
		return "ALREADY_OWNED", nil
	end
	local outcome = StoryRules.newOutcome()
	local code = StoryRules.changeCurrency(profile, outcome, "Gems", item.costGems, ACADEMY_SOURCE, true)
	if code then
		return code, nil
	end
	if item.kind == "Unit" then
		local failure = ShopRules.addUnit(profile, item.itemId, "shop", now, newUid)
		if failure then
			return failure, nil
		end
		outcome.units = true
	else
		profile.skinsOwned[item.itemId] = true
	end
	profile.purchases.academy[item.id] = true
	return nil, outcome
end

return table.freeze(ShopRules)
