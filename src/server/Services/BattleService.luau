--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local TestBattle = require(Shared.Config.TestBattle)
local Stages = require(Shared.Config.Stages)
local BattleArena = require(Shared.Config.BattleArena)
local BattleSim = require(Shared.BattleSim)
local TeamRules = require(Shared.TeamRules)
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local DataService = require(script.Parent.DataService)
local TeamService = require(script.Parent.TeamService)

local BattleService = {}
local seedGenerator = Random.new()

local function simulate(
	profile: Types.Profile,
	teamUnits: { string },
	enemyDef: Types.StageDef,
	maxUnits: number
): (Types.BattleResult?, string?)
	local owned: { [string]: boolean } = {}
	for uid in profile.units do
		owned[uid] = true
	end
	local valid, code = TeamRules.validateSlots(teamUnits, owned, maxUnits)
	if not valid then
		return nil, code
	end

	local teamA: { Types.BattleUnitInput } = {}
	for cell, uid in teamUnits do
		if uid ~= TeamRules.EMPTY_SLOT then
			local unit = profile.units[uid]
			table.insert(teamA, {
				unitId = unit.unitId,
				stars = unit.stars,
				level = unit.level,
				trait = unit.trait,
				cell = cell,
			})
		end
	end
	if #teamA == 0 then
		return nil, "EMPTY_TEAM"
	end

	local teamB: { Types.BattleUnitInput } = {}
	for _, enemy in enemyDef.enemies do
		table.insert(teamB, { unitId = enemy.unitId, stars = enemy.stars, level = enemy.level, cell = enemy.slot })
	end
	local seed = seedGenerator:NextInteger(1, 2147483647)
	local result = BattleSim.run({ teamA = teamA, teamB = teamB, seed = seed })
	print(`[Battle] stage={enemyDef.id} seed={seed} winner={result.winner} ticks={result.ticks} events={#result.log}`)
	return result, nil
end

-- Server callers provide a slot snapshot and trusted stage definition.
function BattleService.runPve(
	player: Player,
	teamUnits: { string },
	enemyDef: Types.StageDef
): (Types.BattleResult?, string?)
	local profile = DataService.getProfile(player)
	if not profile then
		return nil, "DATA_NOT_READY"
	end
	return simulate(profile, teamUnits, enemyDef, TeamService.getMaxBoardUnits(profile))
end

function BattleService.init(): ()
	local replay = RemoteSetup.getEvent("BattleResult")
	local function startSavedBattle(player: Player, teamId: any, testBattle: boolean): Types.Result
		if not TeamService.isTeamIndexAllowed(player, teamId) then
			return { ok = false, code = "INVALID_TEAM_ID" }
		end
		local arena = Workspace:FindFirstChild(BattleArena.modelName)
		local origin = arena and arena:FindFirstChild(BattleArena.originName)
		if not origin or not origin:IsA("BasePart") then
			return { ok = false, code = "ARENA_NOT_READY" }
		end
		local profile = DataService.getProfile(player)
		if not profile then
			return { ok = false, code = "DATA_NOT_READY" }
		end
		-- Preset tambahan yang belum pernah disimpan = tim kosong.
		local team = profile.teams[teamId]
		if not team then
			return { ok = false, code = "EMPTY_TEAM" }
		end
		local enemy = if testBattle then TestBattle else Stages.chapters[1][1]
		local maxUnits = if testBattle then Constants.BOARD_UNITS_MAX else TeamService.getMaxBoardUnits(profile)
		local result, code = simulate(profile, team.slots, enemy, maxUnits)
		if not result then
			return { ok = false, code = code }
		end
		replay:FireClient(player, result)
		return { ok = true }
	end

	RemoteSetup.bindFunction("StartTestBattle", function(player: Player, teamId: any, ...: any): Types.Result
		if not RunService:IsStudio() or not table.find(Constants.ADMIN_USER_IDS, player.UserId) then
			return { ok = false, code = "FORBIDDEN" }
		end
		if select("#", ...) ~= 0 then
			return { ok = false, code = "INVALID_TEAM_ID" }
		end
		return startSavedBattle(player, teamId, true)
	end)
	RemoteSetup.bindFunction("StartPracticeBattle", function(player: Player, teamId: any, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return { ok = false, code = "INVALID_TEAM_ID" }
		end
		return startSavedBattle(player, teamId, false)
	end)
end

function BattleService.start(): () end

return table.freeze(BattleService)
