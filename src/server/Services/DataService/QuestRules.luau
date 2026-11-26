--!strict
-- Aturan murni quest yang memutasi DRAFT profil: progres dari aktivitas server dan klaim reward.
-- Dipanggil hanya lewat DataService/Meta (Commit.run). Tidak boleh yield. Hanya periode aktif yang
-- disimpan (record harian/mingguan diganti saat kunci periode berubah) sehingga ukuran data terbatas.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Quests = require(Shared.Config.Quests)
local QuestPeriods = require(Shared.QuestPeriods)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local BattlePassRules = require(script.Parent.BattlePassRules)
local ProfileRules = require(script.Parent.ProfileRules)
local StoryRules = require(script.Parent.StoryRules)

type Outcome = StoryRules.Outcome
type PeriodRecord = { key: string, progress: { [string]: number }, claimed: { [string]: boolean } }

export type BattlePassTarget = { seasonId: string, maxXp: number }
export type ClaimRequest = {
	questId: string,
	periodKey: string,
	now: number,
	battlePass: BattlePassTarget?, -- musim aktif; nil = tanpa XP Battle Pass
}

local QUEST_SOURCE = "quest_reward"
local MAX_PROGRESS_STEP = 2 ^ 31

local QuestRules = {}

local function fieldFor(period: Types.QuestPeriod): string
	return if period == "Daily" then "daily" else "weekly"
end

-- Record periode tersanitasi (salinan baru): hanya quest yang ada di config dan periode yang cocok.
local function readPeriod(value: any, period: Types.QuestPeriod): PeriodRecord
	local raw = if type(value) == "table" then value else {}
	local key = if type(raw.key) == "string" and #raw.key <= Quests.maxPeriodKeyLength then raw.key else ""
	local record: PeriodRecord = { key = key, progress = {}, claimed = {} }
	local progress = if type(raw.progress) == "table" then raw.progress else {}
	local claimed = if type(raw.claimed) == "table" then raw.claimed else {}
	for _, def in Quests.definitions do
		if def.period == period then
			local count = progress[def.id]
			if Validate.isIntInRange(count, 1, def.target) then
				record.progress[def.id] = count
			end
			if claimed[def.id] == true then
				record.claimed[def.id] = true
			end
		end
	end
	return record
end

-- Melengkapi/menyanitasi field additive `quests` pada profil (v1) tanpa migrasi.
function QuestRules.reconcile(profile: any): ()
	if type(profile.quests) ~= "table" then
		profile.quests = {}
	end
	profile.quests.daily = readPeriod(profile.quests.daily, "Daily")
	profile.quests.weekly = readPeriod(profile.quests.weekly, "Weekly")
end

-- Salinan record periode untuk `now` (record kosong bila periode tersimpan sudah lewat). Tidak memutasi.
function QuestRules.view(profile: Types.Profile, period: Types.QuestPeriod, now: number): PeriodRecord
	local stored = readPeriod((profile.quests :: any)[fieldFor(period)], period)
	local key = QuestPeriods.key(period, now)
	if stored.key ~= key then
		return { key = key, progress = {}, claimed = {} }
	end
	return stored
end

-- Record periode aktif pada draft, diganti record baru bila periode berganti.
local function current(profile: Types.Profile, period: Types.QuestPeriod, now: number): PeriodRecord
	local field = fieldFor(period)
	local quests = profile.quests :: any
	local record = quests[field]
	local key = QuestPeriods.key(period, now)
	if type(record) ~= "table" or record.key ~= key then
		record = { key = key, progress = {}, claimed = {} }
		quests[field] = record
	end
	return record
end

-- Progres dari aktivitas server terverifikasi (Util/Activity). Progres dibatasi target; quest yang sudah
-- diklaim tidak berubah. Mengembalikan (kode, outcome, jumlah quest yang berubah).
function QuestRules.addProgress(
	profile: Types.Profile,
	kind: Types.ActivityKind,
	amount: number,
	now: number
): (string?, Outcome?, number)
	if type(kind) ~= "string" or not Validate.isIntInRange(amount, 1, MAX_PROGRESS_STEP) then
		return "INVALID_REQUEST", nil, 0
	end
	if not Validate.isIntInRange(now, 0, 2 ^ 53 - 1) then
		return "INVALID_REQUEST", nil, 0
	end
	local changed = 0
	for _, def in Quests.definitions do
		if def.kind == kind then
			local record = current(profile, def.period, now)
			local before = record.progress[def.id] or 0
			if not record.claimed[def.id] and before < def.target then
				record.progress[def.id] = math.min(def.target, before + amount)
				changed += 1
			end
		end
	end
	return nil, StoryRules.newOutcome(), changed
end

-- Klaim sekali per quest per periode. Reward mata uang, tanda klaim, dan XP Battle Pass (musim aktif)
-- berada di draft yang sama sehingga ter-commit atau gagal bersama.
function QuestRules.claim(profile: Types.Profile, request: ClaimRequest): (string?, Outcome?, Types.RewardMap?)
	if type(request) ~= "table" or not Validate.isIntInRange(request.now, 0, 2 ^ 53 - 1) then
		return "INVALID_REQUEST", nil, nil
	end
	local def = if type(request.questId) == "string" then Quests.byId[request.questId] else nil
	if not def then
		return "INVALID_QUEST", nil, nil
	end
	if request.periodKey ~= QuestPeriods.key(def.period, request.now) then
		return "PERIOD_EXPIRED", nil, nil
	end
	local record = current(profile, def.period, request.now)
	if record.claimed[def.id] == true then
		return "ALREADY_CLAIMED", nil, nil
	end
	if (record.progress[def.id] or 0) < def.target then
		return "QUEST_INCOMPLETE", nil, nil
	end
	local outcome = StoryRules.newOutcome()
	local granted: Types.RewardMap = {}
	for _, kind in Quests.rewardCurrencies do
		local amount = def.rewards[kind]
		if amount then
			if not ProfileRules.isCurrencyKind(kind) then
				return "INTERNAL_ERROR", nil, nil
			end
			local code =
				StoryRules.changeCurrency(profile, outcome, kind :: Types.CurrencyKind, amount, QUEST_SOURCE, false)
			if code then
				return code, nil, nil
			end
			granted[kind] = amount
		end
	end
	record.claimed[def.id] = true
	local battlePass = request.battlePass
	if battlePass and def.battlePassXp > 0 then
		local code = BattlePassRules.addXp(profile, battlePass.seasonId, def.battlePassXp, battlePass.maxXp)
		if code then
			return code, nil, nil
		end
		granted[Quests.battlePassXpRewardKey] = def.battlePassXp
	end
	return nil, outcome, granted
end

return table.freeze(QuestRules)
