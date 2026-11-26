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
		teams = { { name = Constants.DEFAULT_TEAM_NAME, slots = {} } },
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
	}
end

return table.freeze(Template)
