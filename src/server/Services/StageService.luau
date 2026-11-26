--!strict
-- StageService: remote StartStage (prompts/06-story-progression.md) dan StartAutoReplay (prompt 09:
-- hanya pemilik gp_autoreplay menurut cache server, hanya stage yang sudah 3★ di profil server).
-- Server memilih tim (preset tersimpan), menjalankan BattleService, menghitung bintang, lalu
-- DataService.progress meng-commit reward & progres secara atomik. Replay hanya lewat respons.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Products = require(Shared.Config.Products)
local Progression = require(Shared.Config.Progression)
local ProgressionRules = require(Shared.ProgressionRules)
local TeamRules = require(Shared.TeamRules)
local Validate = require(script.Parent.Parent.Util.Validate)
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local BattleService = require(script.Parent.BattleService)
local BattlePassService = require(script.Parent.BattlePassService)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local TeamService = require(script.Parent.TeamService)

-- "tutorial" dan "N-NN" muat; ID lain ditolak sebelum lookup.
local isStageIdString = Validate.isStringMax(16)

local StageService = {}

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

local function isEmptyTeam(slots: { string }): boolean
	for _, uid in slots do
		if uid ~= TeamRules.EMPTY_SLOT then
			return false
		end
	end
	return true
end

-- Slot sementara berisi starter milik pemain untuk tutorial. Tidak disimpan ke profil.
function StageService.tutorialStarterSlots(profile: Types.Profile): { string }?
	local slots = table.create(Constants.BOARD_SLOTS, TeamRules.EMPTY_SLOT)
	local placed = 0
	for _, unitId in Constants.STARTER_UNIT_IDS do
		local cell = Progression.TUTORIAL_STARTER_CELLS[unitId]
		local pickUid: string? = nil
		local pickAt = math.huge
		for uid, unit in profile.units do
			if
				unit.unitId == unitId
				and (unit.obtainedAt < pickAt or (unit.obtainedAt == pickAt and uid < (pickUid :: string)))
			then
				pickUid, pickAt = uid, unit.obtainedAt
			end
		end
		if pickUid and cell and slots[cell] == TeamRules.EMPTY_SLOT then
			slots[cell] = pickUid
			placed += 1
		end
	end
	return if placed > 0 then slots else nil
end

local function runStage(player: Player, autoReplay: boolean, stageId: any, teamIndex: any, ...: any): Types.Result
	if select("#", ...) ~= 0 then
		return failure("INVALID_ARGUMENTS")
	end
	if not isStageIdString(stageId) then
		return failure("INVALID_STAGE")
	end
	local stage = ProgressionRules.stageDef(stageId)
	if not stage then
		return failure("INVALID_STAGE")
	end
	if not TeamService.isTeamIndexAllowed(player, teamIndex) then
		return failure("INVALID_TEAM_INDEX")
	end
	if autoReplay and not MonetizationService.hasPass(player, "gp_autoreplay") then
		return failure("PASS_REQUIRED")
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return failure("DATA_NOT_READY")
	end
	if not ProgressionRules.isStageUnlocked(profile.story.cleared, profile.progress.tutorialBattleCleared, stageId) then
		return failure("STAGE_LOCKED")
	end
	if autoReplay and profile.story.cleared[stageId] ~= Products.autoReplayRequiredStars then
		return failure("STAGE_NOT_THREE_STAR")
	end
	-- Preset tambahan yang belum pernah disimpan = tim kosong.
	local team = profile.teams[teamIndex]
	local slots = if team then team.slots else table.create(Constants.BOARD_SLOTS, TeamRules.EMPTY_SLOT)
	if ProgressionRules.isTutorial(stageId) and isEmptyTeam(slots) then
		local starters = StageService.tutorialStarterSlots(profile)
		if not starters then
			return failure("NO_STARTER_UNITS")
		end
		slots = starters
	end

	-- Batas bersama StartStage + StartAutoReplay agar dua remote tidak menggandakan laju battle.
	local rule = Constants.RATE_LIMITS.StartStage
	if not RateLimiter.allow(player, "StageBattle", rule.max, rule.windowSec) then
		return failure("RATE_LIMITED")
	end
	-- BattleService memvalidasi kepemilikan, duplikat, dan batas slot dari progres server.
	local result, battleCode = BattleService.runPve(player, slots, stage)
	if not result then
		return failure(battleCode or "BATTLE_FAILED")
	end
	local stars = ProgressionRules.countStars(result)
	local code, outcome = DataService.progress.applyStageResult(player, stageId, stars)
	if code or not outcome then
		return failure(code or "INTERNAL_ERROR")
	end
	if stars > 0 and not ProgressionRules.isTutorial(stageId) then
		-- Commit terpisah: kegagalan XP (mis. di luar musim) tidak membatalkan hasil stage.
		BattlePassService.awardStoryWin(player)
	end
	local progression = DataService.progress.getProgression(player)
	if not progression then
		return failure("DATA_NOT_READY")
	end
	local data: Types.StageResultData = {
		stageId = stageId,
		replay = result,
		stars = stars,
		rewards = outcome.rewards :: Types.StageRewards,
		firstThreeStar = outcome.firstThreeStar == true,
		progression = progression,
	}
	return { ok = true, data = data }
end

function StageService.init(): ()
	RemoteSetup.bindFunction("StartStage", function(player: Player, ...: any): Types.Result
		return runStage(player, false, ...)
	end)
	RemoteSetup.bindFunction("StartAutoReplay", function(player: Player, ...: any): Types.Result
		return runStage(player, true, ...)
	end)
end

function StageService.start(): () end

return StageService
