--!strict
-- TradeService (prompt 11, docs/SYSTEMS.md A): sesi trade antar pemain di server yang sama.
-- Semua state di server (TradeSession + Coordinator); data profil hanya lewat DataService.trades
-- (validasi, kunci item, commit berjurnal ke TradeLog). TradeUpdated hanya dikirim ke kedua peserta.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Trade = require(Shared.Config.Trade)
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local ComplianceService = require(script.Parent.ComplianceService)
local DataService = require(script.Parent.DataService)
local Coordinator = require(script.Coordinator)
local Proximity = require(script.Proximity)

local TradeService = {}

local REMOTES = { "RequestTrade", "RespondTrade", "SetTradeItems", "SetReady", "ConfirmTrade", "CancelTrade" }
local ageOverride: { [Player]: number } = {}

local function accountAgeDays(player: Player): number
	return ageOverride[player] or player.AccountAge
end

local coordinator = Coordinator.create({
	trades = DataService.trades,
	proximity = Proximity.check,
	isTradingAllowed = ComplianceService.isPaidItemTradingAllowed,
	accountAgeDays = accountAgeDays,
	findPlayer = function(userId: number): Player?
		return Players:GetPlayerByUserId(userId)
	end,
	isPresent = function(player: Player): boolean
		return player.Parent == Players
	end,
	displayName = function(player: Player?, userId: number): string
		return if player then player.DisplayName else tostring(userId)
	end,
	now = function(): number
		return Workspace:GetServerTimeNow()
	end,
	newId = function(): string
		return HttpService:GenerateGUID(false)
	end,
	send = function(player: Player, view: any)
		RemoteSetup.getEvent("TradeUpdated"):FireClient(player, view)
	end,
	spawn = function(fn: () -> ())
		task.spawn(fn)
	end,
})

-- Studio server Command Bar saja: ganti umur akun untuk pemain uji (Players lokal Studio berumur 0 hari).
-- nil = lepas override. Tidak tersedia di server live.
function TradeService.adminSetAccountAge(player: Player, days: number?): boolean
	if not RunService:IsStudio() or table.find(Constants.ADMIN_USER_IDS, player.UserId) == nil then
		return false
	end
	if days ~= nil and (type(days) ~= "number" or days ~= days or days < 0) then
		return false
	end
	ageOverride[player] = days
	return true
end

function TradeService.init(): ()
	for _, name in REMOTES do
		RemoteSetup.bindFunction(name, coordinator.handlers[name])
	end
end

function TradeService.start(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		coordinator.playerRemoving(player)
		ageOverride[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Trade.tickSeconds)
			coordinator.tick()
		end
	end)
end

return TradeService
