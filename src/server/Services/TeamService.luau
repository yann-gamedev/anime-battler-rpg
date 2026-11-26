--!strict
-- TeamService: remote GetTeamBoard & SaveTeam (irisan Team Board, prompts/05-ui-team-board.md).
-- Data dibaca/dimutasi hanya lewat DataService; client menerima subset aman, bukan profil.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Units = require(Shared.Config.Units)
local TeamRules = require(Shared.TeamRules)
local ProgressionRules = require(Shared.ProgressionRules)
local Validate = require(script.Parent.Parent.Util.Validate)
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local DataService = require(script.Parent.DataService)

local TeamService = {}

-- Irisan ini hanya memakai preset tim pertama.
local ACTIVE_TEAM_INDEX = 1

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

-- Batas unit di papan. Akan naik lewat progres story (GDD §6), BUKAN pembelian.
function TeamService.getMaxBoardUnits(profile: Types.Profile): number
	return ProgressionRules.maxBoardUnits(profile.story.cleared)
end

local function buildBoardData(profile: Types.Profile, teamIndex: number): Types.TeamBoardData
	local team = profile.teams[teamIndex]
	local slots: { string } = table.create(Constants.BOARD_SLOTS, TeamRules.EMPTY_SLOT)
	if team then
		for index = 1, Constants.BOARD_SLOTS do
			local uid = team.slots[index]
			-- Abaikan UID basi (unit sudah tidak dimiliki).
			if uid and profile.units[uid] then
				slots[index] = uid
			end
		end
	end

	local units: { Types.TeamBoardUnit } = {}
	for uid, owned in profile.units do
		local def = Units[owned.unitId]
		if def then
			table.insert(units, {
				uid = uid,
				unitId = owned.unitId,
				name = def.name,
				rarity = def.rarity,
				element = def.element,
				status = def.status,
				stars = owned.stars,
				level = owned.level,
			})
		end
	end
	table.sort(units, function(a, b)
		if a.unitId ~= b.unitId then
			return a.unitId < b.unitId
		end
		return a.uid < b.uid
	end)

	return { slots = slots, units = units, maxUnits = TeamService.getMaxBoardUnits(profile) }
end

local function handleGetTeamBoard(player: Player, ...: any): Types.Result
	if select("#", ...) ~= 0 then
		return failure("INVALID_ARGUMENTS")
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return failure("DATA_NOT_READY")
	end
	return { ok = true, data = buildBoardData(profile, ACTIVE_TEAM_INDEX) }
end

local function handleSaveTeam(player: Player, teamIndex: any, slots: any, ...: any): Types.Result
	if
		not Validate.isIntInRange(teamIndex, ACTIVE_TEAM_INDEX, Constants.TEAM_PRESETS_BASE)
		or select("#", ...) ~= 0
	then
		return failure("INVALID_TEAM_INDEX")
	end
	local profile = DataService.getProfile(player)
	local owned = DataService.getOwnedUidSet(player)
	if not profile or not owned then
		return failure("DATA_NOT_READY")
	end
	local ok, code = TeamRules.validateSlots(slots, owned, TeamService.getMaxBoardUnits(profile))
	if not ok then
		return failure(code or "INVALID_SLOTS")
	end
	if not DataService.setTeamSlots(player, teamIndex, slots) then
		return failure("SAVE_FAILED")
	end
	local savedProfile = DataService.getProfile(player)
	if not savedProfile then
		return failure("DATA_NOT_READY")
	end
	return { ok = true, data = buildBoardData(savedProfile, teamIndex) }
end

function TeamService.init(): ()
	RemoteSetup.bindFunction("GetTeamBoard", handleGetTeamBoard)
	RemoteSetup.bindFunction("SaveTeam", handleSaveTeam)
end

function TeamService.start(): () end

return TeamService
