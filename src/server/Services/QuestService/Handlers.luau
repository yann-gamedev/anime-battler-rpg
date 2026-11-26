--!strict
-- Logika QuestService yang bisa di-test: snapshot GetQuests, klaim, dan progres dari Activity.
-- Definisi, target, reward, dan periode hanya dari Config/Quests + jam server; client mengirim niat.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local MetaTypes = require(Shared.MetaTypes)
local Quests = require(Shared.Config.Quests)
local QuestPeriods = require(Shared.QuestPeriods)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)

export type BattlePassTarget = { seasonId: string, maxXp: number }
export type Ledger = {
	getQuests: (
		player: Player,
		now: number
	) -> { daily: MetaTypes.QuestPeriodRecord, weekly: MetaTypes.QuestPeriodRecord }?,
	addQuestProgress: (player: Player, kind: Types.ActivityKind, amount: number, now: number) -> string?,
	claimQuest: (player: Player, request: any) -> (string?, Types.RewardMap?),
}
export type Deps = {
	ledger: Ledger,
	now: () -> number,
	battlePass: (now: number) -> BattlePassTarget?,
	onClaimed: ((player: Player, def: Types.QuestDef, rewards: Types.RewardMap) -> ())?,
}

local isQuestId = Validate.isStringMax(Quests.maxQuestIdLength)
local isPeriodKey = Validate.isStringMax(Quests.maxPeriodKeyLength)
local isActivityKind = Validate.isOneOf({ "story_win", "story_stars", "unit_level", "raid_attempt" })

local Handlers = {}

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

function Handlers.create(deps: Deps)
	local ledger = deps.ledger

	local function buildInfo(player: Player): Types.QuestInfo?
		local now = deps.now()
		local state = ledger.getQuests(player, now)
		if not state then
			return nil
		end
		local battlePassActive = deps.battlePass(now) ~= nil
		local quests: { MetaTypes.QuestView } = {}
		for _, def in Quests.definitions do
			local record = if def.period == "Daily" then state.daily else state.weekly
			local rewards: Types.RewardMap = table.clone(def.rewards)
			if battlePassActive and def.battlePassXp > 0 then
				rewards[Quests.battlePassXpRewardKey] = def.battlePassXp
			end
			table.insert(quests, {
				id = def.id,
				period = def.period,
				periodKey = record.key,
				title = def.title,
				description = def.description,
				progress = math.min(record.progress[def.id] or 0, def.target),
				target = def.target,
				claimed = record.claimed[def.id] == true,
				rewards = rewards,
			})
		end
		return {
			serverTime = now,
			dailyResetAt = QuestPeriods.dailyResetAt(now),
			weeklyResetAt = QuestPeriods.weeklyResetAt(now),
			quests = quests,
		}
	end

	local function respond(player: Player): Types.Result
		local info = buildInfo(player)
		if not info then
			return failure("DATA_NOT_READY")
		end
		return { ok = true, data = info }
	end

	local function getQuests(player: Player, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		return respond(player)
	end

	local function claimQuest(player: Player, questId: any, periodKey: any, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		if not isQuestId(questId) or questId == "" or not Quests.byId[questId] then
			return failure("INVALID_QUEST")
		end
		if not isPeriodKey(periodKey) or periodKey == "" then
			return failure("INVALID_PERIOD")
		end
		local now = deps.now()
		local def = Quests.byId[questId]
		-- Kunci periode dari snapshot harus sama dengan periode server saat ini (reset UTC sudah lewat = ditolak).
		if periodKey ~= QuestPeriods.key(def.period, now) then
			return failure("PERIOD_EXPIRED")
		end
		local code, granted = ledger.claimQuest(player, {
			questId = questId,
			periodKey = periodKey,
			now = now,
			battlePass = deps.battlePass(now),
		})
		if code then
			return failure(code)
		end
		if deps.onClaimed then
			deps.onClaimed(player, def, granted or {})
		end
		return respond(player)
	end

	-- Dari Util/Activity (server-only). Kegagalan (mis. data belum siap) hanya berarti progres tidak dihitung.
	local function onActivity(player: Player, kind: any, amount: any): string?
		if type(kind) ~= "string" or not isActivityKind(kind) or not Validate.isIntInRange(amount, 1, 2 ^ 31) then
			return "INVALID_ACTIVITY"
		end
		return ledger.addQuestProgress(player, kind :: Types.ActivityKind, amount, deps.now())
	end

	return {
		GetQuests = getQuests,
		ClaimQuest = claimQuest,
		buildInfo = buildInfo,
		onActivity = onActivity,
	}
end

return table.freeze(Handlers)
