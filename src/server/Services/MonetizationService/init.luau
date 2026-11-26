--!strict
-- MonetizationService (prompts/09-monetization.md, docs/RULES.md §4):
-- - SATU-SATUNYA tempat yang memasang MarketplaceService.ProcessReceipt (lihat Receipts.luau).
-- - Gamepass: UserOwnsGamePassAsync saat join (pcall, cache per sesi) + PromptGamePassPurchaseFinished
--   di server. `hasPass` adalah otoritas server; atribut Player hanya cermin untuk UI.
-- - Remote toko (Shop.luau). PromptProductPurchaseFinished TIDAK dipakai untuk memberi apa pun.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Products = require(Shared.Config.Products)
local BattlePassSeason = require(Shared.BattlePassSeason)
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local AnalyticsService = require(script.Parent.AnalyticsService)
local ComplianceService = require(script.Parent.ComplianceService)
local DataService = require(script.Parent.DataService)
local Aura = require(script.Aura)
local Passes = require(script.Passes)
local Receipts = require(script.Receipts)
local Shop = require(script.Shop)

local PASS_LOAD_ATTEMPTS = 3

local MonetizationService = {}

local characterConnections: { [Player]: RBXScriptConnection } = {}

local function isPresent(player: Player): boolean
	return player.Parent == Players
end

local passes = Passes.create({
	ownsAsync = function(userId: number, passId: number): any
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end,
	isPresent = isPresent,
	setAttribute = function(player: Player, name: string, value: any)
		player:SetAttribute(name, value)
	end,
	onChanged = function(player: Player)
		task.spawn(Aura.apply, player.Character, MonetizationService.hasPass(player, "gp_vip_aura"))
	end,
})

local receipts = Receipts.create({
	ledger = DataService.purchases,
	findPlayer = function(userId: number): Player?
		return Players:GetPlayerByUserId(userId)
	end,
	isPresent = isPresent,
	hasProfile = function(player: Player): boolean
		return DataService.getOwnedUidSet(player) ~= nil
	end,
	-- receiptInfo.CurrencyType: hanya Robux yang dihitung ke stats.robuxSpent.
	isRobux = function(currencyType: any): boolean
		return currencyType == Enum.CurrencyType.Robux
	end,
	sleep = function(seconds: number)
		task.wait(seconds)
	end,
	clock = os.clock,
	onGranted = function(player: Player, productKey: string, robuxSpent: number, firstBonus: boolean)
		AnalyticsService.logPurchase(player.UserId, productKey, robuxSpent, firstBonus)
	end,
})

-- Otoritas server untuk gamepass (cache sesi). key = key config, mis. "gp_autoreplay".
function MonetizationService.hasPass(player: Player, key: string): boolean
	return passes.has(player, key)
end

-- Preset tim tambahan dari gp_presets (0 atau Config/Products.extraPresetsWithPass).
function MonetizationService.extraPresets(player: Player): number
	return passes.extraPresets(player)
end

-- Studio server Command Bar saja: set kepemilikan gamepass sesi untuk UserId admin (uji tanpa Robux).
function MonetizationService.adminSetPass(player: Player, key: string, owned: boolean): boolean
	if not RunService:IsStudio() or table.find(Constants.ADMIN_USER_IDS, player.UserId) == nil then
		return false
	end
	if type(key) ~= "string" or Products.passAttributes[key] == nil or type(owned) ~= "boolean" then
		return false
	end
	passes.setForTest(player, key, owned)
	return true
end

local function onPlayerAdded(player: Player): ()
	if characterConnections[player] then
		return
	end
	characterConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		Aura.apply(character, passes.has(player, "gp_vip_aura"))
	end)
	for attempt = 1, PASS_LOAD_ATTEMPTS do
		if not isPresent(player) or passes.load(player) then
			return
		end
		if attempt < PASS_LOAD_ATTEMPTS then
			task.wait(Products.gamePassRetrySeconds)
		end
	end
end

local function onPlayerRemoving(player: Player): ()
	local connection = characterConnections[player]
	characterConnections[player] = nil
	if connection then
		connection:Disconnect()
	end
	passes.clear(player)
end

function MonetizationService.init(): ()
	local handlers = Shop.create({
		ledger = DataService.purchases,
		isRestricted = ComplianceService.isPaidRandomRestricted,
		isPresent = isPresent,
		hasPass = passes.has,
		activeSeasonId = function(): string?
			local season = BattlePassSeason.active(os.time())
			return if season then season.id else nil
		end,
	})
	RemoteSetup.bindFunction("GetShopInfo", handlers.GetShopInfo)
	RemoteSetup.bindFunction("PrepareShopPurchase", handlers.PrepareShopPurchase)
	RemoteSetup.bindFunction("BuyAcademyItem", handlers.BuyAcademyItem)
	-- Satu callback untuk seluruh game. Boleh yield sampai receipt terbukti tersimpan.
	MarketplaceService.ProcessReceipt = function(receiptInfo: any): Enum.ProductPurchaseDecision
		-- Error tak terduga = NotProcessedYet (grant + marker atomik, jadi retry tidak memberi dua kali).
		local ok, decision = xpcall(receipts.process, debug.traceback, receiptInfo)
		if not ok then
			warn(`[Monetization] ProcessReceipt error: {decision}`)
		end
		return if ok and decision == "PurchaseGranted"
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

function MonetizationService.start(): ()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, wasPurchased: boolean)
			passes.onPurchaseFinished(player, passId, wasPurchased)
		end
	)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MonetizationService
