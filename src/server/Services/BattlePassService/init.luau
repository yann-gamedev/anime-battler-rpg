--!strict
-- BattlePassService (docs/ECONOMY.md §6): remote GetBattlePass & ClaimBattlePassTier, XP story,
-- dan API quest untuk prompt 10. Premium hanya dari receipt (MonetizationService → DataService.purchases).
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local DataService = require(script.Parent.DataService)
local Handlers = require(script.Handlers)

local handlers = Handlers.create({ ledger = DataService.battlePass, now = os.time })

local BattlePassService = {}

-- Dipanggil StageService setelah kemenangan story (bukan tutorial) tercatat.
function BattlePassService.awardStoryWin(player: Player): (string?, number?)
	return handlers.awardStoryWin(player)
end

-- API server-only untuk quest (prompt 10): amount 1..Config/BattlePass.maxQuestXpPerGrant.
function BattlePassService.grantQuestXp(player: Player, questId: string, amount: number): (string?, number?)
	return handlers.grantQuestXp(player, questId, amount)
end

function BattlePassService.init(): ()
	RemoteSetup.bindFunction("GetBattlePass", handlers.GetBattlePass)
	RemoteSetup.bindFunction("ClaimBattlePassTier", handlers.ClaimBattlePassTier)
end

function BattlePassService.start(): () end

return BattlePassService
