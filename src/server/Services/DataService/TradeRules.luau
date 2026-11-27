--!strict
-- Aturan murni trade (docs/SYSTEMS.md A1–A2, A4) atas DRAFT profil. Tanpa yield, tanpa Instance.
-- Dipakai DataService/Trades (validasi + swap dua profil) dan roll-forward pemulihan jurnal.
-- Asumsi legacy refund: di skema v1 level unit hanya naik lewat LevelUpUnit dengan biaya
-- ProgressionRules.levelUpCost saat ini (unit selalu dibuat di level 1, tidak ada sumber XP lain), sehingga
-- "Gold & XP Scroll yang sudah dipakai" = levelUpCost(1, level - 1). Unit 1★ belum pernah di-merge.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local TradeTypes = require(Shared.TradeTypes)
local Constants = require(Shared.Config.Constants)
local Banners = require(Shared.Config.Banners)
local Skins = require(Shared.Config.Skins)
local Trade = require(Shared.Config.Trade)
local Units = require(Shared.Config.Units)
local ProgressionRules = require(Shared.ProgressionRules)
local TeamRules = require(Shared.TeamRules)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local StoryRules = require(script.Parent.StoryRules)

type Outcome = StoryRules.Outcome
type TradeRecord = TradeTypes.TradeRecord
type TradeSide = TradeTypes.TradeSide

export type Role = "a" | "b"
export type ProfileTrade = { applied: { string }, dupeFlags: { [string]: number } }

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local SECONDS_PER_DAY = 86400
local RECORD_VERSION = 1

local limitedUnits: { [string]: boolean } = {}
if Trade.limitedFromLimitedBanners then
	for _, banner in Banners.definitions do
		if banner.kind == "Limited" and banner.featuredUnitId then
			limitedUnits[banner.featuredUnitId] = true
		end
	end
end

local TradeRules = {}

function TradeRules.utcDay(now: number): number
	return math.floor(now / SECONDS_PER_DAY)
end

-- Mythic & limited: cooldown 7 hari sejak didapat / sejak trade terakhir.
function TradeRules.needsCooldown(unitId: string): boolean
	local def = Units[unitId]
	return def ~= nil and (Trade.cooldownRarities[def.rarity] == true or limitedUnits[unitId] == true)
end

-- Refund level (floor) untuk unit di `level`: fraksi levelRefundRate dari biaya level 1 → level.
function TradeRules.levelRefund(level: number): (number, number)
	if not Validate.isIntInRange(level, Constants.UNIT_LEVEL_MIN + 1, Constants.UNIT_LEVEL_MAX) then
		return 0, 0
	end
	local gold, scrolls = ProgressionRules.levelUpCost(Constants.UNIT_LEVEL_MIN, level - Constants.UNIT_LEVEL_MIN)
	return math.floor(gold * Trade.levelRefundRate), math.floor(scrolls * Trade.levelRefundRate)
end

-- Data trade additive di profil (tanpa migrasi). Marker `applied` = tradeId yang sudah diterapkan (FIFO).
function TradeRules.reconcile(profile: any): ()
	local record = if type(profile.trade) == "table" then profile.trade else {}
	local applied: { string } = {}
	if type(record.applied) == "table" then
		for _, tradeId in record.applied do
			if type(tradeId) == "string" and #tradeId <= Constants.MAX_UID_LENGTH then
				table.insert(applied, tradeId)
			end
		end
	end
	local flags: { [string]: number } = {}
	if type(record.dupeFlags) == "table" then
		for uid, at in record.dupeFlags do
			if type(uid) == "string" and Validate.isIntInRange(at, 0, MAX_EXACT_INTEGER) then
				flags[uid] = at
			end
		end
	end
	profile.trade = { applied = applied, dupeFlags = flags }
	local daily = profile.tradeDaily
	if
		type(daily) ~= "table"
		or not Validate.isIntInRange(daily.day, 0, MAX_EXACT_INTEGER)
		or not Validate.isIntInRange(daily.count, 0, MAX_EXACT_INTEGER)
	then
		profile.tradeDaily = { day = 0, count = 0 }
	end
end

function TradeRules.isApplied(profile: Types.Profile, tradeId: string): boolean
	local record = (profile :: any).trade
	return type(record) == "table" and type(record.applied) == "table" and table.find(record.applied, tradeId) ~= nil
end

function TradeRules.tradesToday(profile: Types.Profile, day: number): number
	local daily = profile.tradeDaily
	return if type(daily) == "table" and daily.day == day and type(daily.count) == "number" then daily.count else 0
end

-- Unit di tim pertahanan wilayah (M7). Skema v1 belum punya pertahanan; field masa depan dicek defensif.
function TradeRules.isInDefense(profile: Types.Profile, uid: string): boolean
	local defense = (profile :: any).defense
	return type(defense) == "table" and type(defense.uids) == "table" and defense.uids[uid] == true
end

-- Syarat pemain (A2). accountAgeDays dari Player.AccountAge yang dibaca server.
function TradeRules.checkPlayer(profile: Types.Profile, accountAgeDays: number, now: number): string?
	if type(profile.accountLevel) ~= "number" or profile.accountLevel < Trade.minAccountLevel then
		return "ACCOUNT_LEVEL_TOO_LOW"
	end
	if not Validate.isFiniteNumber(accountAgeDays) or accountAgeDays < Trade.minAccountAgeDays then
		return "ACCOUNT_TOO_NEW"
	end
	if TradeRules.tradesToday(profile, TradeRules.utcDay(now)) >= Trade.dailyMaxTrades then
		return "DAILY_TRADE_LIMIT"
	end
	return nil
end

-- Satu unit bisa ditawarkan (A1): dimiliki, 1★, tidak locked, tidak di pertahanan, tidak cooldown.
function TradeRules.checkUnit(profile: Types.Profile, uid: string, now: number): string?
	local unit = profile.units[uid]
	if not unit then
		return "UNIT_NOT_OWNED"
	end
	if not Units[unit.unitId] then
		return "UNIT_NOT_TRADABLE"
	end
	if unit.stars ~= Trade.tradableStars then
		return "UNIT_STARS_NOT_TRADABLE"
	end
	if unit.locked then
		return "UNIT_LOCKED"
	end
	if TradeRules.isInDefense(profile, uid) then
		return "UNIT_IN_DEFENSE"
	end
	if type(unit.tradeCooldownUntil) == "number" and unit.tradeCooldownUntil > now then
		return "UNIT_ON_COOLDOWN"
	end
	if TradeRules.needsCooldown(unit.unitId) and unit.obtainedAt + Trade.cooldownSeconds > now then
		return "UNIT_ON_COOLDOWN"
	end
	return nil
end

-- Isi tawaran satu sisi (bentuk argumen sudah divalidasi pemanggil remote).
function TradeRules.checkOffer(profile: Types.Profile, uids: { string }, skins: { string }, now: number): string?
	if #uids + #skins > Trade.maxItemsPerSide then
		return "TOO_MANY_ITEMS"
	end
	local seen: { [string]: boolean } = {}
	for _, uid in uids do
		if seen[uid] then
			return "DUPLICATE_ITEM"
		end
		seen[uid] = true
		local code = TradeRules.checkUnit(profile, uid, now)
		if code then
			return code
		end
	end
	local seenSkins: { [string]: boolean } = {}
	for _, skinId in skins do
		if seenSkins[skinId] then
			return "DUPLICATE_ITEM"
		end
		seenSkins[skinId] = true
		if not Skins[skinId] then
			return "INVALID_SKIN"
		end
		if profile.skinsOwned[skinId] ~= true then
			return "SKIN_NOT_OWNED"
		end
	end
	return nil
end

-- Penerima: UID/skin yang masuk belum dimiliki dan kapasitas unit cukup setelah unit keluar.
function TradeRules.checkReceive(profile: Types.Profile, incoming: TradeSide, outgoingUnits: number): string?
	for _, unit in incoming.units do
		if profile.units[unit.uid] ~= nil then
			return "DUPLICATE_UID"
		end
	end
	for _, skinId in incoming.skins do
		if profile.skinsOwned[skinId] == true then
			return "SKIN_ALREADY_OWNED"
		end
	end
	local count = 0
	for _ in profile.units do
		count += 1
	end
	if count - outgoingUnits + #incoming.units > Constants.MAX_UNITS_PER_PLAYER then
		return "INVENTORY_FULL"
	end
	return nil
end

function TradeRules.checkTax(profile: Types.Profile): string?
	return if profile.currencies.Gold >= Trade.taxGold then nil else "NOT_ENOUGH_GOLD"
end

-- Snapshot sisi pengirim saat keputusan dikunci. Panggil hanya setelah checkOffer lolos.
function TradeRules.buildSide(
	profile: Types.Profile,
	userId: number,
	uids: { string },
	skins: { string },
	now: number
): TradeSide
	local units: { TradeTypes.TransferUnit } = {}
	for _, uid in uids do
		local unit = profile.units[uid]
		local gold, scrolls = TradeRules.levelRefund(unit.level)
		table.insert(units, {
			uid = uid,
			unitId = unit.unitId,
			obtainedAt = unit.obtainedAt,
			cooldownUntil = if TradeRules.needsCooldown(unit.unitId) then now + Trade.cooldownSeconds else nil,
			refundGold = gold,
			refundScrolls = scrolls,
		})
	end
	return { userId = userId, units = units, skins = table.clone(skins) }
end

function TradeRules.buildRecord(tradeId: string, now: number, a: TradeSide, b: TradeSide): TradeRecord
	return {
		v = RECORD_VERSION,
		tradeId = tradeId,
		at = now,
		day = TradeRules.utcDay(now),
		tax = Trade.taxGold,
		a = a,
		b = b,
	}
end

local function clearUnitReferences(profile: Types.Profile, uid: string, outcome: Outcome): ()
	profile.equippedSkins[uid] = nil
	for _, team in profile.teams do
		for index, assigned in team.slots do
			if assigned == uid then
				team.slots[index] = TeamRules.EMPTY_SLOT
				outcome.teams = true
			end
		end
	end
	local lobby = (profile :: any).lobby
	if type(lobby) == "table" and lobby.showcaseUid == uid then
		lobby.showcaseUid = ""
		lobby.showcaseSkinId = ""
	end
end

local function clearSkinReferences(profile: Types.Profile, skinId: string): ()
	for uid, equipped in profile.equippedSkins do
		if equipped == skinId then
			profile.equippedSkins[uid] = nil
		end
	end
	local lobby = (profile :: any).lobby
	if type(lobby) == "table" and lobby.showcaseSkinId == skinId then
		lobby.showcaseSkinId = ""
	end
end

-- Menerapkan SATU sisi trade ke draft profil `role`. strict = jalur live (semua item wajib ada & sah);
-- non-strict = roll-forward pemulihan (item yang sudah tidak ada dilewati dan dilaporkan di `anomalies`).
-- Idempoten: marker applied[tradeId] → "ALREADY_APPLIED" tanpa mutasi.
function TradeRules.applyHalf(
	profile: Types.Profile,
	record: TradeRecord,
	role: Role,
	strict: boolean
): (string?, Outcome?, { string }?)
	if TradeRules.isApplied(profile, record.tradeId) then
		return "ALREADY_APPLIED", nil, nil
	end
	local give = if role == "a" then record.a else record.b
	local receive = if role == "a" then record.b else record.a
	local anomalies: { string } = {}
	if strict then
		local uids: { string } = {}
		for _, unit in give.units do
			table.insert(uids, unit.uid)
			local owned = profile.units[unit.uid]
			if owned and owned.unitId ~= unit.unitId then
				return "UNIT_CHANGED", nil, nil
			end
		end
		local code = TradeRules.checkOffer(profile, uids, give.skins, record.at)
			or TradeRules.checkReceive(profile, receive, #give.units)
			or TradeRules.checkTax(profile)
		if code then
			return code, nil, nil
		end
	end
	local outcome = StoryRules.newOutcome()
	local refundGold, refundScrolls = 0, 0
	for _, unit in give.units do
		if profile.units[unit.uid] then
			profile.units[unit.uid] = nil
			clearUnitReferences(profile, unit.uid, outcome)
			refundGold += unit.refundGold
			refundScrolls += unit.refundScrolls
			outcome.units = true
		else
			table.insert(anomalies, `missing_give:{unit.uid}`)
		end
	end
	for _, skinId in give.skins do
		if profile.skinsOwned[skinId] == true then
			profile.skinsOwned[skinId] = nil
			clearSkinReferences(profile, skinId)
			outcome.units = true
		else
			table.insert(anomalies, `missing_skin:{skinId}`)
		end
	end
	for _, unit in receive.units do
		if profile.units[unit.uid] then
			table.insert(anomalies, `duplicate_receive:{unit.uid}`)
		else
			profile.units[unit.uid] = {
				uid = unit.uid,
				unitId = unit.unitId,
				stars = Trade.tradableStars,
				level = Constants.UNIT_LEVEL_MIN,
				xp = 0,
				trait = nil,
				locked = false,
				tradeCooldownUntil = unit.cooldownUntil,
				obtainedAt = record.at,
				source = "trade",
			}
			outcome.units = true
		end
	end
	for _, skinId in receive.skins do
		profile.skinsOwned[skinId] = true
		outcome.units = true
	end
	local code = StoryRules.changeCurrency(profile, outcome, "Gold", refundGold, "trade_level_refund", false)
		or StoryRules.addXpScrolls(profile, refundScrolls)
	if code then
		return code, nil, nil
	end
	local tax = math.min(record.tax, profile.currencies.Gold)
	if tax < record.tax then
		table.insert(anomalies, "tax_short")
	end
	code = StoryRules.changeCurrency(profile, outcome, "Gold", tax, "trade_tax", true)
	if code then
		return code, nil, nil
	end
	local daily = profile.tradeDaily
	if daily.day == record.day then
		daily.count += 1
	elseif record.day > daily.day then
		profile.tradeDaily = { day = record.day, count = 1 }
	end
	local trade = (profile :: any).trade :: ProfileTrade
	table.insert(trade.applied, record.tradeId)
	while #trade.applied > Trade.log.recentTradesKept do
		table.remove(trade.applied, 1)
	end
	return nil, outcome, anomalies
end

return table.freeze(TradeRules)
