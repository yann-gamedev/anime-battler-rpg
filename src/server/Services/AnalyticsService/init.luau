--!strict
-- AnalyticsService (prompt 10, docs/GDD.md §12, docs/ECONOMY.md §7): event Roblox Analytics dari server.
-- - Ekonomi: LogEconomyEvent untuk setiap delta mata uang yang SUDAH di-commit (sumber & penggunaan).
-- - Funnel onboarding: LogOnboardingFunnelStepEvent hanya pada transisi state profil di commit.
-- - Custom: summon, pembelian Robux (receipt baru), klaim quest, raid, durasi sesi.
-- Event Roblox hanya terkirim dari server di game yang dipublikasikan (bukan Studio/client).
-- Kegagalan layanan di-pcall dan di-log berjeda; analytics tidak pernah menggagalkan gameplay.
-- TODO(verify-api): signature mengikuti docs AnalyticsService (diperiksa 2026-11-26); cek ulang sebelum rilis.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RobloxAnalytics = game:GetService("AnalyticsService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Analytics = require(Shared.Config.Analytics)
local Core = require(script.Core)
local Derive = require(script.Derive)

export type OnboardingState = Derive.OnboardingState

local AnalyticsService = {}

local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

local function fieldMap(fields: Core.Fields): { [string]: string }?
	if not fields or #fields == 0 then
		return nil
	end
	local map: { [string]: string } = {}
	for index, value in fields do
		map[FIELD_KEYS[index]] = value
	end
	return map
end

local robloxBackend: Core.Backend = {
	economy = function(player, isSource, currency, amount, endingBalance, transactionType, itemSku)
		local flow = if isSource then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
		RobloxAnalytics:LogEconomyEvent(player, flow, currency, amount, endingBalance, transactionType, itemSku)
	end,
	onboarding = function(player, step, stepName)
		RobloxAnalytics:LogOnboardingFunnelStepEvent(player, step, stepName)
	end,
	custom = function(player, eventName, value, fields)
		RobloxAnalytics:LogCustomEvent(player, eventName, value, fieldMap(fields))
	end,
}

local function createCore(backend: Core.Backend): Core.Core
	return Core.create({
		backend = backend,
		clock = os.clock,
		playerCount = function(): number
			return #Players:GetPlayers()
		end,
		warn = function(message: string)
			warn(message)
		end,
	})
end

local core = createCore(robloxBackend)
local joinedAt: { [Player]: number } = {}

local function isPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

-- Delta mata uang yang sudah di-commit, dengan saldo akhir setelah delta ini.
function AnalyticsService.logEconomy(
	player: Player,
	kind: string,
	delta: number,
	endingBalance: number,
	source: string
): ()
	if isPlayer(player) then
		core.economy(player, kind, delta, endingBalance, source)
	end
end

-- Kompatibel dengan pemanggil lama (UserId). Tanpa saldo akhir event ekonomi tidak dikirim, karena
-- LogEconomyEvent membutuhkan endingBalance yang benar.
function AnalyticsService.logCurrencyChange(
	userId: number,
	kind: string,
	delta: number,
	source: string,
	endingBalance: number?
): ()
	local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if player and endingBalance ~= nil then
		AnalyticsService.logEconomy(player, kind, delta, endingBalance, source)
	end
end

-- Pembelian Developer Product yang baru diberikan (bukan retry). robuxSpent = CurrencySpent aktual.
function AnalyticsService.logPurchase(userId: number, productKey: string, robuxSpent: number, firstBonus: boolean): ()
	local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if player then
		core.custom(player, Analytics.events.purchase, robuxSpent, { productKey, tostring(firstBonus == true) })
	end
end

-- Summon yang sudah di-commit. rarities = rarity tiap unit yang diberikan.
function AnalyticsService.logSummon(player: Player, bannerId: string, currency: string, rarities: { string }): ()
	if isPlayer(player) and #rarities > 0 then
		core.custom(player, Analytics.events.summon, #rarities, { bannerId, currency, Derive.bestRarity(rarities) })
	end
end

function AnalyticsService.logQuestClaim(player: Player, questId: string, period: string): ()
	if isPlayer(player) then
		core.custom(player, Analytics.events.questClaim, 1, { questId, period })
	end
end

function AnalyticsService.logRaidAttempt(player: Player, damage: number, tierIndex: number): ()
	if isPlayer(player) then
		core.custom(player, Analytics.events.raidAttempt, damage, { `tier{tierIndex}` })
	end
end

-- Langkah 1 funnel onboarding: profil baru selesai dimuat (dipanggil DataService sekali per profil baru).
function AnalyticsService.logNewProfile(player: Player): ()
	if isPlayer(player) then
		core.onboarding(player, 1)
	end
end

export type Baseline = { balances: { [string]: number }, onboarding: OnboardingState }

-- Dipanggil DataService/Commit pada draft yang sudah direkonsiliasi, SEBELUM mutasi.
function AnalyticsService.baseline(draft: any): Baseline
	local balances: { [string]: number } = {}
	if type(draft.currencies) == "table" then
		for kind, amount in draft.currencies do
			balances[kind] = amount
		end
	end
	return { balances = balances, onboarding = Derive.onboardingState(draft) }
end

-- Dipanggil DataService/Commit SETELAH draft menggantikan profil: event ekonomi per delta (dengan saldo
-- akhir) dan langkah onboarding yang baru tercapai pada commit ini.
function AnalyticsService.logCommit(player: Player, baseline: Baseline, deltas: { Derive.Delta }, after: any): ()
	if not isPlayer(player) then
		return
	end
	for _, event in Derive.economyEvents(baseline.balances, deltas) do
		core.economy(player, event.kind, event.amount, event.endingBalance, event.source)
	end
	for _, step in Derive.onboardingSteps(baseline.onboarding, Derive.onboardingState(after)) do
		core.onboarding(player, step)
	end
end

-- Studio saja: ganti backend dengan mock (test); anggaran & statistik ikut direset.
function AnalyticsService.setBackendForTest(backend: Core.Backend): boolean
	if not RunService:IsStudio() then
		return false
	end
	core = createCore(backend)
	return true
end

function AnalyticsService.stats(): { sent: number, dropped: number, failed: number }
	return core.stats()
end

local function onPlayerAdded(player: Player): ()
	if joinedAt[player] == nil then
		joinedAt[player] = os.clock()
	end
end

local function onPlayerRemoving(player: Player): ()
	local started = joinedAt[player]
	joinedAt[player] = nil
	if started then
		local seconds = math.floor(os.clock() - started)
		core.custom(player, Analytics.events.session, seconds, { Derive.sessionBucket(seconds) })
	end
end

function AnalyticsService.init(): () end

function AnalyticsService.start(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return AnalyticsService
