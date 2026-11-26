--!strict
-- InventoryService: remote LevelUpUnit, MergeUnit, DismantleUnit, LockUnit (prompts/06-story-progression.md).
-- Handler hanya memvalidasi bentuk argumen; kepemilikan, status unit, dan biaya dicek oleh
-- DataService.progress di atas draft profil pemanggil lalu di-commit atomik.
-- Respons sukses = snapshot GetMyData terbaru.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Config.Progression)
local Validate = require(script.Parent.Parent.Util.Validate)
local Activity = require(script.Parent.Parent.Util.Activity)
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local DataService = require(script.Parent.DataService)

local MAX_MERGE_MATERIALS = 0
for _, count in Economy.mergeDuplicates do
	MAX_MERGE_MATERIALS = math.max(MAX_MERGE_MATERIALS, count)
end

local InventoryService = {}

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

local function isUid(value: any): boolean
	return typeof(value) == "string" and value ~= "" and #value <= Constants.MAX_UID_LENGTH
end

local function respond(player: Player, code: string?): Types.Result
	if code then
		return failure(code)
	end
	local data = DataService.progress.getMyData(player)
	if not data then
		return failure("DATA_NOT_READY")
	end
	return { ok = true, data = data }
end

local function handleLevelUp(player: Player, uid: any, levels: any, ...: any): Types.Result
	if select("#", ...) ~= 0 or not isUid(uid) then
		return failure("INVALID_ARGUMENTS")
	end
	if not Validate.isIntInRange(levels, 1, Constants.UNIT_LEVEL_MAX - Constants.UNIT_LEVEL_MIN) then
		return failure("INVALID_LEVELS")
	end
	local code = DataService.progress.levelUpUnit(player, uid, levels)
	if code == nil then
		Activity.report(player, "unit_level", levels) -- progres quest setelah commit level up
	end
	return respond(player, code)
end

local function handleMerge(player: Player, targetUid: any, materialUids: any, ...: any): Types.Result
	if select("#", ...) ~= 0 or not isUid(targetUid) then
		return failure("INVALID_ARGUMENTS")
	end
	if not Validate.isStringArray(materialUids, 1, MAX_MERGE_MATERIALS, Constants.MAX_UID_LENGTH) then
		return failure("INVALID_MATERIALS")
	end
	return respond(player, DataService.progress.mergeUnit(player, targetUid, materialUids))
end

local function handleDismantle(player: Player, uids: any, ...: any): Types.Result
	if select("#", ...) ~= 0 then
		return failure("INVALID_ARGUMENTS")
	end
	if not Validate.isStringArray(uids, 1, Progression.DISMANTLE_MAX_UNITS, Constants.MAX_UID_LENGTH) then
		return failure("INVALID_UNITS")
	end
	return respond(player, DataService.progress.dismantleUnits(player, uids))
end

local function handleLock(player: Player, uid: any, locked: any, ...: any): Types.Result
	if select("#", ...) ~= 0 or not isUid(uid) or typeof(locked) ~= "boolean" then
		return failure("INVALID_ARGUMENTS")
	end
	return respond(player, DataService.progress.setUnitLocked(player, uid, locked))
end

function InventoryService.init(): ()
	RemoteSetup.bindFunction("LevelUpUnit", handleLevelUp)
	RemoteSetup.bindFunction("MergeUnit", handleMerge)
	RemoteSetup.bindFunction("DismantleUnit", handleDismantle)
	RemoteSetup.bindFunction("LockUnit", handleLock)
end

function InventoryService.start(): () end

return InventoryService
