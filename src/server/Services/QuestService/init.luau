--!strict
-- QuestService (prompt 10): quest harian (reset 00:00 UTC) & mingguan (reset Senin 00:00 UTC) dari
-- Config/Quests. Progres hanya dari Util/Activity (aktivitas server yang sudah di-commit). Klaim di server:
-- reward, tanda klaim, dan XP Battle Pass musim aktif di-commit atomik oleh DataService.meta.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BattlePassSeason = require(Shared.BattlePassSeason)
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local Activity = require(script.Parent.Parent.Util.Activity)
local AnalyticsService = require(script.Parent.AnalyticsService)
local DataService = require(script.Parent.DataService)
local Handlers = require(script.Handlers)

local handlers = Handlers.create({
	ledger = DataService.meta,
	now = os.time,
	battlePass = function(now: number): Handlers.BattlePassTarget?
		local season = BattlePassSeason.active(now)
		return if season then { seasonId = season.id, maxXp = BattlePassSeason.maxXp(season) } else nil
	end,
	onClaimed = function(player: Player, def, _rewards)
		AnalyticsService.logQuestClaim(player, def.id, def.period)
	end,
})

local QuestService = {}

function QuestService.init(): ()
	RemoteSetup.bindFunction("GetQuests", handlers.GetQuests)
	RemoteSetup.bindFunction("ClaimQuest", handlers.ClaimQuest)
	Activity.fired:Connect(function(player: Player, kind, amount: number)
		local code = handlers.onActivity(player, kind, amount)
		if code and code ~= "DATA_NOT_READY" then
			warn(`[QuestService] progres {kind} gagal untuk {player.UserId}: {code}`)
		end
	end)
end

function QuestService.start(): () end

return QuestService
