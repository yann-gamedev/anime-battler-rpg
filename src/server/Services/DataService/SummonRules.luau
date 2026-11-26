--!strict
-- Aturan murni summon yang memutasi DRAFT profil (salinan). Dipanggil hanya lewat DataService/Summons, yang
-- meng-commit draft secara atomik. Semua cek (quote, saldo, kapasitas, validitas hasil roll) dilakukan
-- sebelum mutasi pertama. Tidak boleh yield: roll dan precheck dijalankan di dalam coroutine commit.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Units = require(Shared.Config.Units)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local StoryRules = require(script.Parent.StoryRules)

type Outcome = StoryRules.Outcome

export type PityState = { sinceLegendary: number, sinceMythic: number, guaranteedFeatured: boolean }
export type Draw = { unitId: string, rarity: Types.Rarity }
export type Request = {
	bannerId: string,
	count: number,
	currency: "Gems" | "SummonTickets",
	price: number,
	maxUnits: number,
	-- Dicek terhadap state pity draft saat commit (mis. quote odds untuk Gems). nil = lolos.
	precheck: (state: PityState) -> string?,
	-- Roll murni; menerima state pity saat ini, mengembalikan hasil berurutan + state akhir.
	rollBatch: (state: PityState) -> ({ Draw }, PityState),
}

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local SUMMON_SOURCE = "summon"
local isBannerId = Validate.isStringMax(Constants.MAX_BANNER_ID_LENGTH)

local SummonRules = {}

local function isCounter(value: any): boolean
	return Validate.isIntInRange(value, 0, MAX_EXACT_INTEGER - 1)
end

-- State pity tersanitasi dari profil. Entri hilang/rusak = mulai dari nol.
function SummonRules.readPity(record: any): PityState
	if type(record) ~= "table" then
		return { sinceLegendary = 0, sinceMythic = 0, guaranteedFeatured = false }
	end
	return {
		sinceLegendary = if isCounter(record.sinceLegendary) then record.sinceLegendary else 0,
		sinceMythic = if isCounter(record.sinceMythic) then record.sinceMythic else 0,
		guaranteedFeatured = record.guaranteedFeatured == true,
	}
end

function SummonRules.countUnits(profile: Types.Profile): number
	local count = 0
	for _ in profile.units do
		count += 1
	end
	return count
end

local function isValidState(state: any): boolean
	return type(state) == "table"
		and isCounter(state.sinceLegendary)
		and isCounter(state.sinceMythic)
		and type(state.guaranteedFeatured) == "boolean"
end

local function isValidDraws(draws: any, count: number): boolean
	if type(draws) ~= "table" or #draws ~= count then
		return false
	end
	for index = 1, count do
		local draw = draws[index]
		local def = type(draw) == "table" and type(draw.unitId) == "string" and Units[draw.unitId]
		if not def or def.rarity ~= draw.rarity then
			return false
		end
	end
	return true
end

local function isValidRequest(request: Request): boolean
	return type(request) == "table"
		and isBannerId(request.bannerId)
		and request.bannerId ~= ""
		and Validate.isIntInRange(request.count, 1, Constants.MAX_UNITS_PER_PLAYER)
		and (request.currency == "Gems" or request.currency == "SummonTickets")
		and Validate.isIntInRange(request.price, 1, MAX_EXACT_INTEGER)
		and Validate.isIntInRange(request.maxUnits, 0, MAX_EXACT_INTEGER)
		and type(request.precheck) == "function"
		and type(request.rollBatch) == "function"
end

-- Menerapkan satu batch summon ke draft. Mengembalikan (kode error, nil, nil) atau (nil, outcome, unit baru).
function SummonRules.apply(
	profile: Types.Profile,
	request: Request,
	now: number,
	newUid: () -> string
): (string?, Outcome?, { Types.OwnedUnit }?)
	if not isValidRequest(request) or not Validate.isFiniteNumber(now) then
		return "INVALID_REQUEST", nil, nil
	end
	local state = SummonRules.readPity(profile.pity[request.bannerId])
	local code = request.precheck(table.clone(state))
	if code ~= nil then
		return code, nil, nil
	end
	local currencies = profile.currencies
	local balance = if request.currency == "Gems" then currencies.Gems else currencies.SummonTickets
	if not Validate.isIntInRange(balance, request.price, MAX_EXACT_INTEGER) then
		return if request.currency == "Gems" then "NOT_ENOUGH_GEMS" else "NOT_ENOUGH_TICKETS", nil, nil
	end
	if SummonRules.countUnits(profile) + request.count > request.maxUnits then
		return "INVENTORY_FULL", nil, nil
	end
	local draws, finalState = request.rollBatch(table.clone(state))
	if not isValidDraws(draws, request.count) or not isValidState(finalState) then
		warn("[DataService] summon roll returned an invalid result")
		return "INTERNAL_ERROR", nil, nil
	end

	-- Mulai mutasi: semua cek di atas sudah lolos.
	local outcome = StoryRules.newOutcome()
	code = StoryRules.changeCurrency(profile, outcome, request.currency, request.price, SUMMON_SOURCE, true)
	if code ~= nil then
		return code, nil, nil
	end
	local granted: { Types.OwnedUnit } = {}
	for _, draw in draws do
		local uid = newUid()
		if type(uid) ~= "string" or uid == "" or profile.units[uid] ~= nil then
			return "INTERNAL_ERROR", nil, nil
		end
		local unit: Types.OwnedUnit = {
			uid = uid,
			unitId = draw.unitId,
			stars = Constants.UNIT_STARS_MIN,
			level = Constants.UNIT_LEVEL_MIN,
			xp = 0,
			trait = nil,
			locked = false,
			tradeCooldownUntil = nil,
			obtainedAt = now,
			source = SUMMON_SOURCE,
		}
		profile.units[uid] = unit
		table.insert(granted, table.clone(unit))
	end
	profile.pity[request.bannerId] = {
		sinceLegendary = finalState.sinceLegendary,
		sinceMythic = finalState.sinceMythic,
		-- Flag opt-in: hanya disimpan saat aktif agar profil lama tetap sah tanpa migrasi.
		guaranteedFeatured = if finalState.guaranteedFeatured then true else nil,
	}
	local summons = profile.stats.summons
	if isCounter(summons) and summons <= MAX_EXACT_INTEGER - request.count then
		profile.stats.summons = summons + request.count
	end
	outcome.units = true
	return nil, outcome, granted
end

return table.freeze(SummonRules)
