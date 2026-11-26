--!strict
-- RaidService (prompt 10, docs/GDD.md §7): boss harian dengan HP besar, 1 percobaan gratis per hari UTC
-- (tidak bisa dibeli). Battle memakai BattleService.runPve dengan tim tersimpan dan batas slot yang sama
-- dengan story. Raid terbuka setelah onboarding (flags.tutorialDone), sama dengan lobby.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local RaidMath = require(Shared.RaidMath)
local TeamRules = require(Shared.TeamRules)
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local Activity = require(script.Parent.Parent.Util.Activity)
local AnalyticsService = require(script.Parent.AnalyticsService)
local BattleService = require(script.Parent.BattleService)
local DataService = require(script.Parent.DataService)
local TeamService = require(script.Parent.TeamService)
local Handlers = require(script.Handlers)

local handlers = Handlers.create({
	ledger = DataService.meta,
	now = os.time,
	isTeamIndexAllowed = TeamService.isTeamIndexAllowed,
	runBattle = function(player: Player, teamIndex: number): (Types.BattleResult?, string?)
		local profile = DataService.getProfile(player)
		if not profile then
			return nil, "DATA_NOT_READY"
		end
		-- Preset tambahan yang belum pernah disimpan = tim kosong.
		local team = profile.teams[teamIndex]
		local slots = if team then team.slots else table.create(Constants.BOARD_SLOTS, TeamRules.EMPTY_SLOT)
		return BattleService.runPve(player, slots, RaidMath.stageDef())
	end,
	onAttempt = function(player: Player, damage: number, tierIndex: number)
		AnalyticsService.logRaidAttempt(player, damage, tierIndex)
		Activity.report(player, "raid_attempt", 1)
	end,
})

local RaidService = {}

function RaidService.init(): ()
	RemoteSetup.bindFunction("GetRaidInfo", handlers.GetRaidInfo)
	RemoteSetup.bindFunction("StartRaid", handlers.StartRaid)
end

function RaidService.start(): () end

return RaidService
