--!strict
-- TraitService: remote GetTraitInfo & RerollTrait (prompts/08-traits.md, docs/UNITS.md §5).
-- RNG, pity, odds, dan pergantian trait hanya di server. Roll murni di Roll.luau, odds UI di Odds.luau
-- (fungsi bobot yang sama), mutasi profil hanya lewat DataService.traits dalam satu commit tanpa yield.
-- Kebijakan item acak berbayar dicek lewat ComplianceService sebelum commit (reroll Shards diblok bila
-- restricted). Pemain restricted memilih trait Common/Uncommon langsung dengan Gold (D-OPEN-1,
-- SelectRestrictedTrait), tanpa RNG dan tanpa menyentuh pity atau Shards.
local Players = game:GetService("Players")

local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local ComplianceService = require(script.Parent.ComplianceService)
local DataService = require(script.Parent.DataService)
local Handlers = require(script.Handlers)

local TraitService = {}

-- RNG server. Random.new() tanpa seed memakai entropi engine; tidak pernah dikirim ke client.
local random = Random.new()
local handlers: Handlers.Handlers? = nil

function TraitService.init(): ()
	local created = Handlers.create({
		ledger = DataService.traits :: any,
		isRestricted = ComplianceService.isPaidRandomRestricted,
		isPresent = function(player: Player): boolean
			return player.Parent == Players
		end,
		rng = random :: any,
	})
	handlers = created
	RemoteSetup.bindFunction("GetTraitInfo", created.getTraitInfo)
	RemoteSetup.bindFunction("RerollTrait", created.rerollTrait)
	RemoteSetup.bindFunction("SelectRestrictedTrait", created.selectRestrictedTrait)
end

function TraitService.start(): ()
	local created = handlers :: Handlers.Handlers
	Players.PlayerRemoving:Connect(created.clear)
end

return TraitService
