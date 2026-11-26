--!strict
-- SummonService: remote GetBannerInfo & Summon (prompts/07-summon-banner.md).
-- Harga, RNG, pity, odds, dan pemberian unit hanya di server. Roll murni di Roll.luau, odds UI di Odds.luau
-- (fungsi bobot yang sama), mutasi profil hanya lewat DataService.summons dalam satu commit tanpa yield.
-- Kebijakan item acak berbayar dicek lewat ComplianceService sebelum commit.
local Players = game:GetService("Players")

local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local ComplianceService = require(script.Parent.ComplianceService)
local DataService = require(script.Parent.DataService)
local Handlers = require(script.Handlers)

local SummonService = {}

-- RNG server. Random.new() tanpa seed memakai entropi engine; tidak pernah dikirim ke client.
local random = Random.new()
local handlers: Handlers.Handlers? = nil

function SummonService.init(): ()
	local created = Handlers.create({
		ledger = DataService.summons :: any,
		isRestricted = ComplianceService.isPaidRandomRestricted,
		isPresent = function(player: Player): boolean
			return player.Parent == Players
		end,
		now = os.time,
		rng = random :: any,
	})
	handlers = created
	RemoteSetup.bindFunction("GetBannerInfo", created.getBannerInfo)
	RemoteSetup.bindFunction("Summon", created.summon)
end

function SummonService.start(): ()
	local created = handlers :: Handlers.Handlers
	Players.PlayerRemoving:Connect(created.clear)
end

return SummonService
