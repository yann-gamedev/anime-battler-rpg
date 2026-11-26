--!strict
-- Aturan murni progres story (tanpa Instance, bisa di-test).
-- Server memakainya untuk keputusan otoritatif; client boleh memakai hanya untuk tampilan.
local Types = require(script.Parent.Types)
local Constants = require(script.Parent.Config.Constants)
local Economy = require(script.Parent.Config.Economy)
local Progression = require(script.Parent.Config.Progression)
local Stages = require(script.Parent.Config.Stages)

local ProgressionRules = {}

local orderById: { [string]: number } = {}
for index, stageId in Stages.order do
	orderById[stageId] = index
end

-- Urutan stage public 1..30, atau nil untuk ID yang tidak dikenal (termasuk "tutorial").
function ProgressionRules.stageOrder(stageId: string): number?
	return orderById[stageId]
end

function ProgressionRules.isTutorial(stageId: string): boolean
	return stageId == Progression.TUTORIAL_STAGE_ID
end

-- Stage definisi tepercaya dari Config, atau nil jika ID tidak dikenal.
function ProgressionRules.stageDef(stageId: string): Types.StageDef?
	if ProgressionRules.isTutorial(stageId) then
		return Stages.tutorial
	end
	return Stages.byId[stageId]
end

local function isCleared(cleared: { [string]: number }, stageId: string): boolean
	local stars = cleared[stageId]
	return type(stars) == "number" and stars >= 1
end

-- Tutorial selalu boleh. 1-1 terbuka setelah tutorial; stage lain setelah stage sebelumnya menang.
function ProgressionRules.isStageUnlocked(
	cleared: { [string]: number },
	tutorialBattleCleared: boolean,
	stageId: string
): boolean
	if ProgressionRules.isTutorial(stageId) then
		return true
	end
	local order = orderById[stageId]
	if not order then
		return false
	end
	if order == 1 then
		return tutorialBattleCleared
	end
	return isCleared(cleared, Stages.order[order - 1])
end

-- Jumlah stage story berbeda yang sudah dimenangkan (ID tak dikenal diabaikan).
function ProgressionRules.distinctClears(cleared: { [string]: number }): number
	local count = 0
	for _, stageId in Stages.order do
		if isCleared(cleared, stageId) then
			count += 1
		end
	end
	return count
end

function ProgressionRules.accountLevel(cleared: { [string]: number }): number
	return Progression.ACCOUNT_LEVEL_BASE
		+ Progression.ACCOUNT_LEVEL_PER_STAGE * ProgressionRules.distinctClears(cleared)
end

-- Batas unit di papan dari progres story (GDD §6), tidak pernah melebihi BOARD_UNITS_MAX.
function ProgressionRules.maxBoardUnits(cleared: { [string]: number }): number
	local maxUnits = Constants.BOARD_UNITS_START
	for _, unlock in Progression.BOARD_UNLOCKS do
		if isCleared(cleared, unlock.stageId) then
			maxUnits = math.max(maxUnits, unlock.maxUnits)
		end
	end
	return math.min(maxUnits, Constants.BOARD_UNITS_MAX)
end

-- Bintang dari hasil battle. Korban dihitung HANYA dari unit awal tim A
-- (spawn tick 0 tanpa owner); unit panggilan diabaikan. Unit yang bangkit dan bertahan tidak dihitung.
function ProgressionRules.countStars(result: Types.BattleResult): number
	if result.winner ~= "A" then
		return 0
	end
	local initial: { [number]: boolean } = {}
	local total = 0
	for _, event in result.log do
		if event.kind == "spawn" then
			local spawn = event :: any
			if spawn.t == 0 and spawn.side == "A" and spawn.owner == nil and not initial[spawn.unit] then
				initial[spawn.unit] = true
				total += 1
			end
		end
	end
	local alive = 0
	for _, survivor in result.survivors do
		if survivor.side == "A" and initial[survivor.id] then
			initial[survivor.id] = nil
			alive += 1
		end
	end
	local casualties = total - alive
	if casualties == 0 then
		return 3
	elseif casualties <= Progression.TWO_STAR_MAX_CASUALTIES then
		return 2
	end
	return 1
end

function ProgressionRules.stageGold(order: number): number
	return Progression.STAGE_GOLD_BASE + Progression.STAGE_GOLD_PER_STAGE * (order - 1)
end

function ProgressionRules.stageXpScrolls(order: number): number
	return Progression.STAGE_XP_SCROLLS_BASE + math.floor((order - 1) / Progression.STAGE_XP_SCROLLS_STEP)
end

-- Gold replay setelah soft cap harian (ECONOMY §7). replayIndex = replay ke-n hari ini (1-based).
function ProgressionRules.replayGold(gold: number, replayIndex: number): number
	local cap = Economy.replayGoldSoftCap
	if replayIndex > cap.replaysPerDay then
		return math.floor(gold * cap.goldMultiplier)
	end
	return gold
end

-- Biaya total menaikkan `levels` level dari `level`. Gold dari Economy.levelCost (ECONOMY §4).
function ProgressionRules.levelUpCost(level: number, levels: number): (number, number)
	local gold, scrolls = 0, 0
	for current = level, level + levels - 1 do
		gold += Economy.levelCost(current)
		scrolls += Progression.LEVEL_XP_SCROLLS_BASE + math.floor((current - 1) / Progression.LEVEL_XP_SCROLLS_STEP)
	end
	return gold, scrolls
end

function ProgressionRules.utcDay(now: number): number
	return math.floor(now / Progression.SECONDS_PER_DAY)
end

return table.freeze(ProgressionRules)
