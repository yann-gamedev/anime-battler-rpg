--!strict
-- Aturan murni progres story yang memutasi DRAFT profil (salinan). Dipanggil hanya oleh DataService.Progress,
-- yang meng-commit draft secara atomik jika tidak ada kode error. Tidak boleh yield.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Progression = require(Shared.Config.Progression)
local ProgressionRules = require(Shared.ProgressionRules)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local ProfileRules = require(script.Parent.ProfileRules)

export type CurrencyDelta = { kind: Types.CurrencyKind, amount: number, source: string }
export type Outcome = {
	units: boolean,
	currencies: boolean,
	teams: boolean,
	deltas: { CurrencyDelta },
	rewards: Types.StageRewards?,
	firstThreeStar: boolean?,
}

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local REWARD_SOURCE = "stage_reward"
local TUTORIAL_SOURCE = "tutorial_reward"

local StoryRules = {}

function StoryRules.newOutcome(): Outcome
	return { units = false, currencies = false, teams = false, deltas = {} }
end

-- Menambah/mengurangi mata uang pada draft. Mengembalikan kode error atau nil.
function StoryRules.changeCurrency(
	profile: Types.Profile,
	outcome: Outcome,
	kind: Types.CurrencyKind,
	amount: number,
	source: string,
	spend: boolean
): string?
	if amount == 0 then
		return nil
	end
	local balance = ProfileRules.currencyBalance(profile.currencies[kind], amount, spend)
	if balance == nil then
		return if spend then `NOT_ENOUGH_{string.upper(kind)}` else "CURRENCY_OVERFLOW"
	end
	profile.currencies[kind] = balance
	outcome.currencies = true
	table.insert(outcome.deltas, { kind = kind, amount = if spend then -amount else amount, source = source })
	return nil
end

function StoryRules.addXpScrolls(profile: Types.Profile, amount: number): string?
	local total = profile.materials.XPScrolls + amount
	if not Validate.isIntInRange(total, 0, MAX_EXACT_INTEGER) then
		return "MATERIAL_OVERFLOW"
	end
	profile.materials.XPScrolls = total
	return nil
end

local function bump(value: number): number
	return if Validate.isIntInRange(value, 0, MAX_EXACT_INTEGER - 1) then value + 1 else value
end

-- Menerapkan hasil battle stage yang sudah disimulasikan server. `stars` 0 = kalah/seri.
-- Idempoten terhadap reward sekali-saja: tutorial tickets & Gems first-clear 3★ dijaga flag di draft.
function StoryRules.applyStageResult(
	profile: Types.Profile,
	stageId: string,
	stars: number,
	now: number
): (string?, Outcome?)
	if not Validate.isIntInRange(stars, 0, 3) or not Validate.isFiniteNumber(now) then
		return "INVALID_RESULT", nil
	end
	local stage = ProgressionRules.stageDef(stageId)
	local progress = profile.progress
	local cleared = profile.story.cleared
	if not stage or not ProgressionRules.isStageUnlocked(cleared, progress.tutorialBattleCleared, stageId) then
		return "STAGE_LOCKED", nil
	end

	local outcome = StoryRules.newOutcome()
	local rewards: Types.StageRewards = { Gold = 0, Gems = 0, XPScrolls = 0, SummonTickets = 0 }
	outcome.rewards = rewards
	outcome.firstThreeStar = false
	profile.stats.battles = bump(profile.stats.battles)
	if stars == 0 then
		return nil, outcome
	end
	profile.stats.wins = bump(profile.stats.wins)

	if ProgressionRules.isTutorial(stageId) then
		if not progress.tutorialBattleCleared then
			progress.tutorialBattleCleared = true
			rewards.SummonTickets = Progression.TUTORIAL_SUMMON_TICKETS
		end
		local code =
			StoryRules.changeCurrency(profile, outcome, "SummonTickets", rewards.SummonTickets, TUTORIAL_SOURCE, false)
		return code, if code then nil else outcome
	end

	local order = ProgressionRules.stageOrder(stageId) :: number
	local previous = cleared[stageId]
	local isReplay = type(previous) == "number" and previous >= 1
	local gold = ProgressionRules.stageGold(order)
	if isReplay then
		local day = ProgressionRules.utcDay(now)
		if progress.replayDay ~= day then
			progress.replayDay = day
			progress.replayCount = 0
		end
		progress.replayCount = bump(progress.replayCount)
		gold = ProgressionRules.replayGold(gold, progress.replayCount)
	end
	rewards.Gold = gold
	rewards.XPScrolls = ProgressionRules.stageXpScrolls(order)
	cleared[stageId] = if isReplay then math.max(previous, stars) else stars
	if stars == 3 and progress.firstThreeStarClaimed[stageId] ~= true then
		progress.firstThreeStarClaimed[stageId] = true
		rewards.Gems = stage.firstThreeStarGems
		outcome.firstThreeStar = true
	end
	profile.accountLevel = math.max(profile.accountLevel, ProgressionRules.accountLevel(cleared))
	if stageId == Progression.ONBOARDING_FINAL_STAGE_ID then
		profile.flags.tutorialDone = true
	end

	local code = StoryRules.changeCurrency(profile, outcome, "Gold", rewards.Gold, REWARD_SOURCE, false)
		or StoryRules.changeCurrency(profile, outcome, "Gems", rewards.Gems, REWARD_SOURCE, false)
		or StoryRules.addXpScrolls(profile, rewards.XPScrolls)
	return code, if code then nil else outcome
end

-- Melengkapi field additive pada profil lama (v1) tanpa mengubah arti field yang ada.
function StoryRules.reconcile(profile: any): ()
	if type(profile.materials) ~= "table" then
		profile.materials = {}
	end
	if not Validate.isIntInRange(profile.materials.XPScrolls, 0, MAX_EXACT_INTEGER) then
		profile.materials.XPScrolls = 0
	end
	if type(profile.progress) ~= "table" then
		profile.progress = {}
	end
	local progress = profile.progress
	if type(progress.firstThreeStarClaimed) ~= "table" then
		progress.firstThreeStarClaimed = {}
	end
	if not Validate.isIntInRange(progress.replayDay, 0, MAX_EXACT_INTEGER) then
		progress.replayDay = 0
	end
	if not Validate.isIntInRange(progress.replayCount, 0, MAX_EXACT_INTEGER) then
		progress.replayCount = 0
	end
	if type(progress.tutorialBattleCleared) ~= "boolean" then
		progress.tutorialBattleCleared = false
	end
	local cleared = if type(profile.story) == "table" and type(profile.story.cleared) == "table"
		then profile.story.cleared
		else {}
	local flags = if type(profile.flags) == "table" then profile.flags else {}
	-- Profil yang sudah melewati onboarding tidak boleh terkunci di tutorial atau dapat tiket lagi.
	if flags.tutorialDone == true or next(cleared) ~= nil then
		progress.tutorialBattleCleared = true
	end
	-- Stage yang sudah 3★ dianggap sudah mengklaim Gems first-clear (cegah klaim ganda).
	for stageId, stars in cleared do
		if type(stageId) == "string" and stars == 3 then
			progress.firstThreeStarClaimed[stageId] = true
		end
	end
end

return table.freeze(StoryRules)
