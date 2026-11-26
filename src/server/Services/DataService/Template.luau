--!strict
-- Template profil default, skema v1 (docs/ARCHITECTURE.md §6).
-- Selalu salin dengan Template.create(); jangan memutasi tabel template.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)

local Template = {}

function Template.create(now: number): Types.Profile
	return {
		version = Constants.DATA_VERSION,
		currencies = { Gold = 0, Gems = 0, TraitShards = 0, SummonTickets = 0, AsramaTokens = 0 },
		accountLevel = 1,
		units = {},
		teams = { { name = Constants.DEFAULT_TEAM_NAME, slots = table.create(Constants.BOARD_SLOTS, "") } },
		story = { cleared = {} },
		pity = {},
		traitPity = 0,
		tradeDaily = { day = 0, count = 0 },
		skinsOwned = {},
		equippedSkins = {},
		guildId = nil,
		processedReceipts = {},
		stats = { battles = 0, wins = 0, summons = 0, robuxSpent = 0 },
		flags = { tutorialDone = false },
		createdAt = now,
		-- Field additive v1 (prompt 06); profil lama dilengkapi Reconcile + Progress.reconcile.
		materials = { XPScrolls = 0 },
		progress = { tutorialBattleCleared = false, firstThreeStarClaimed = {}, replayDay = 0, replayCount = 0 },
		-- Field additive v1 (prompt 09); profil lama dilengkapi ShopRules.reconcile.
		purchases = { firstBonus = {}, academy = {} },
		battlePass = { seasons = {}, profileFrames = {} },
		-- Field additive v1 (prompt 10); profil lama dilengkapi MetaRules.reconcile.
		quests = {
			daily = { key = "", progress = {}, claimed = {} },
			weekly = { key = "", progress = {}, claimed = {} },
		},
		raid = { day = 0, attempted = false, damage = 0 },
		lobby = { showcaseUid = "", showcaseSkinId = "" },
	}
end

return table.freeze(Template)
