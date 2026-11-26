--!strict
-- DataService: SATU-SATUNYA modul yang memegang & memutasi data pemain (docs/RULES.md §3).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Units = require(Shared.Config.Units)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local TeamRules = require(Shared.TeamRules)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Replication = require(script.Replication)
local Validate = require(script.Parent.Parent.Util.Validate)
local AnalyticsService = require(script.Parent.AnalyticsService)
local Migrations = require(script.Migrations)
local Progress = require(script.Progress)
local ProfileRules = require(script.ProfileRules)
local Template = require(script.Template)

type Session = {
	Data: Types.Profile,
	FirstSessionTime: number,
	OnSessionEnd: { Connect: (any, () -> ()) -> any },
	IsActive: (Session) -> boolean,
	AddUserId: (Session, number) -> (),
	Reconcile: (Session) -> (),
	EndSession: (Session) -> (),
	Save: (Session) -> (),
}

local IS_STUDIO = RunService:IsStudio()
local LOAD_TIMEOUT_SECONDS = 120
local LOAD_FAILED = "Data kamu gagal dimuat. Silakan masuk lagi sebentar lagi."
local store = ProfileStore.New(if IS_STUDIO then "PlayerProfiles_Studio" else "PlayerProfiles_Live", Template.create(0))
local DataService = {}

-- Changed(player, path): path = "units" | "currencies" | "teams" | "progress".
DataService.Changed = Signal.new() :: Signal.Signal<Player, string>
-- Mutasi progres story & inventory yang atomik (DataService/Progress.luau).
DataService.progress = Progress

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local closing = false

local function getActiveSession(player: Player): Session?
	local session = sessions[player]
	if not closing and not ProfileStore.IsClosing and session and session:IsActive() then
		return session
	end
	return nil
end

local function getProfile(player: Player): Types.Profile?
	local session = getActiveSession(player)
	return if session then session.Data else nil
end

local function hasUnitSpace(profile: Types.Profile): boolean
	local count = 0
	for _ in profile.units do
		count += 1
		if count >= Constants.MAX_UNITS_PER_PLAYER then
			return false
		end
	end
	return true
end

local function createUnit(profile: Types.Profile, unitId: string, source: Types.UnitSource): Types.OwnedUnit?
	if
		type(unitId) ~= "string"
		or not Units[unitId]
		or not ProfileRules.isUnitSource(source)
		or not hasUnitSpace(profile)
	then
		return nil
	end
	local unit: Types.OwnedUnit = {
		uid = HttpService:GenerateGUID(false),
		unitId = unitId,
		stars = Constants.UNIT_STARS_MIN,
		level = Constants.UNIT_LEVEL_MIN,
		xp = 0,
		trait = nil,
		locked = false,
		tradeCooldownUntil = nil,
		obtainedAt = os.time(),
		source = source,
	}
	profile.units[unit.uid] = unit
	return unit
end

local function grantStarterUnits(profile: Types.Profile): ()
	for _, unitId in Constants.STARTER_UNIT_IDS do
		createUnit(profile, unitId, Constants.STARTER_UNIT_SOURCE :: Types.UnitSource)
	end
end

local function onPlayerAdded(player: Player): ()
	if loading[player] or sessions[player] or closing or player.Parent ~= Players then
		return
	end
	loading[player] = true
	local deadline = os.clock() + LOAD_TIMEOUT_SECONDS
	local ok, result = pcall(function()
		return store:StartSessionAsync(`Player_{player.UserId}`, {
			Cancel = function(): boolean
				return closing or player.Parent ~= Players or os.clock() >= deadline
			end,
		})
	end)
	loading[player] = nil
	if not ok then
		warn(`[DataService] Gagal mulai sesi UserId={player.UserId}: {result}`)
	end
	local session: Session? = if ok then result :: any else nil
	if not session then
		if player.Parent == Players and not closing and not ProfileStore.IsClosing then
			player:Kick(LOAD_FAILED)
		end
		return
	end

	if closing or ProfileStore.IsClosing or player.Parent ~= Players then
		session:EndSession()
		return
	end
	if ProfileStore.DataStoreState ~= "Access" then
		session:EndSession()
		warn(`[DataService] DataStore tidak tersedia: {ProfileStore.DataStoreState}`)
		player:Kick(LOAD_FAILED)
		return
	end

	local activeSession = session
	-- Stage migration and reconciliation on a copy so a failed step cannot be persisted.
	local data = session.Data
	local prepared, failure = pcall(function()
		activeSession.Data = TableUtil.deepCopy(data)
		Migrations.run(activeSession.Data)
		activeSession:Reconcile()
		local profile = activeSession.Data
		-- ProfileStore reconciles string keys only, so ensure the default array entry exists.
		if profile.teams[1] == nil then
			profile.teams[1] = Template.create(0).teams[1]
		end
		Progress.reconcile(profile)
		if profile.createdAt == 0 then
			profile.createdAt = activeSession.FirstSessionTime
			if next(profile.units) == nil then
				grantStarterUnits(profile)
			end
		end
		activeSession:AddUserId(player.UserId)
	end)
	if not prepared then
		session.Data = data
		session:EndSession()
		warn(`[DataService] Profil UserId={player.UserId} gagal disiapkan: {failure}`)
		player:Kick(LOAD_FAILED)
		return
	end

	session.OnSessionEnd:Connect(function()
		if sessions[player] == activeSession then
			sessions[player] = nil
			if player.Parent == Players and not closing and not ProfileStore.IsClosing then
				player:Kick("Sesi data kamu sudah berakhir. Silakan masuk lagi.")
			end
		end
	end)
	sessions[player] = session
end

local function onPlayerRemoving(player: Player): ()
	local session = sessions[player]
	sessions[player] = nil
	if session then
		session:EndSession()
	end
end

function DataService.init(): ()
	Replication.bind(getProfile, DataService.Changed)
	Progress.bind(getActiveSession, DataService.Changed)
end

function DataService.start(): ()
	-- ProfileStore's BindToClose ends active sessions and waits for final save jobs.
	game:BindToClose(function()
		closing = true
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- Read-only snapshot. Use DataService's mutation methods and read again for fresh data.
function DataService.getProfile(player: Player): Types.Profile?
	local profile = getProfile(player)
	return if profile then TableUtil.deepFreeze(TableUtil.deepCopy(profile)) else nil
end

-- Set UID milik pemain (salinan baru, aman dimutasi pemanggil).
function DataService.getOwnedUidSet(player: Player): { [string]: boolean }?
	local profile = getProfile(player)
	if not profile then
		return nil
	end
	local owned: { [string]: boolean } = {}
	for uid in profile.units do
		owned[uid] = true
	end
	return owned
end

local isLabel = Validate.isStringMax(128)

local function changeCurrency(
	player: Player,
	kind: Types.CurrencyKind,
	amount: number,
	source: string,
	spend: boolean
): boolean
	local profile = getProfile(player)
	if not profile or not ProfileRules.isCurrencyKind(kind) or not isLabel(source) or source == "" then
		return false
	end
	local balance = ProfileRules.currencyBalance(profile.currencies[kind], amount, spend)
	if balance == nil then
		return false
	end
	profile.currencies[kind] = balance
	AnalyticsService.logCurrencyChange(player.UserId, kind, if spend then -amount else amount, source)
	DataService.Changed:Fire(player, "currencies")
	return true
end

function DataService.addCurrency(player: Player, kind: Types.CurrencyKind, amount: number, source: string): boolean
	return changeCurrency(player, kind, amount, source, false)
end

function DataService.spendCurrency(player: Player, kind: Types.CurrencyKind, amount: number, reason: string): boolean
	return changeCurrency(player, kind, amount, reason, true)
end

function DataService.grantUnit(player: Player, unitId: string, source: Types.UnitSource): Types.OwnedUnit?
	local profile = getProfile(player)
	if not profile then
		return nil
	end
	local unit = createUnit(profile, unitId, source)
	if unit then
		DataService.Changed:Fire(player, "units")
	end
	return if unit then table.clone(unit) else nil
end

function DataService.removeUnit(player: Player, uid: string, reason: string): Types.OwnedUnit?
	if type(uid) ~= "string" then
		return nil
	end
	local profile = getProfile(player)
	local unit = profile and profile.units[uid]
	if not profile or not unit or unit.locked or not isLabel(reason) or reason == "" then
		return nil
	end
	profile.units[uid] = nil
	profile.equippedSkins[uid] = nil
	local teamChanged = false
	for _, team in profile.teams do
		for index, assigned in team.slots do
			if assigned == uid then
				team.slots[index] = TeamRules.EMPTY_SLOT
				teamChanged = true
			end
		end
	end
	DataService.Changed:Fire(player, "units")
	if teamChanged then
		DataService.Changed:Fire(player, "teams")
	end
	return table.clone(unit)
end

function DataService.updateUnit(player: Player, uid: string, mutator: (Types.OwnedUnit) -> ()): boolean
	if type(uid) ~= "string" then
		return false
	end
	local profile = getProfile(player)
	local unit = profile and profile.units[uid]
	if not profile or not unit or type(mutator) ~= "function" then
		return false
	end
	local candidate = table.clone(unit)
	local thread = coroutine.create(mutator)
	local ok, failure = coroutine.resume(thread, candidate)
	if not ok then
		warn(`[DataService] updateUnit mutator failed: {failure}`)
		return false
	end
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		warn("[DataService] updateUnit mutator cannot yield")
		return false
	end
	if
		getProfile(player) ~= profile
		or profile.units[uid] ~= unit
		or not ProfileRules.isUnitUpdateValid(unit, candidate)
	then
		return false
	end
	local updated = table.clone(unit)
	updated.stars = candidate.stars
	updated.level = candidate.level
	updated.xp = candidate.xp
	updated.trait = candidate.trait
	updated.locked = candidate.locked
	updated.tradeCooldownUntil = candidate.tradeCooldownUntil
	profile.units[uid] = updated
	DataService.Changed:Fire(player, "units")
	return true
end

local function isReceiptId(purchaseId: string): boolean
	return isLabel(purchaseId) and purchaseId ~= "" and utf8.len(purchaseId) ~= nil
end

function DataService.isReceiptProcessed(player: Player, purchaseId: string): boolean
	local profile = getProfile(player)
	return profile ~= nil and isReceiptId(purchaseId) and profile.processedReceipts[purchaseId] == true
end

function DataService.markReceiptProcessed(player: Player, purchaseId: string): boolean
	local profile = getProfile(player)
	if not profile or not isReceiptId(purchaseId) then
		return false
	end
	profile.processedReceipts[purchaseId] = true
	return true
end

function DataService.setTeamSlots(player: Player, teamIndex: number, slots: { string }): boolean
	local profile = getProfile(player)
	if not profile then
		return false
	end
	local team = profile.teams[teamIndex]
	if not team then
		return false
	end
	local owned = DataService.getOwnedUidSet(player)
	if not owned or not TeamRules.validateSlots(slots, owned, Constants.BOARD_UNITS_MAX) then
		return false
	end
	team.slots = table.clone(slots)
	DataService.Changed:Fire(player, "teams")
	return true
end

local function isStudioAdmin(player: Player): boolean
	return IS_STUDIO and table.find(Constants.ADMIN_USER_IDS, player.UserId) ~= nil
end

-- Studio server Command Bar only. Both commands operate on the allowlisted player's own session.
function DataService.adminResetProfile(player: Player): boolean
	local session = if isStudioAdmin(player) then getActiveSession(player) else nil
	if not session then
		return false
	end
	local profile = Template.create(os.time())
	grantStarterUnits(profile)
	session.Data = profile
	session:Save()
	DataService.Changed:Fire(player, "units")
	DataService.Changed:Fire(player, "currencies")
	DataService.Changed:Fire(player, "teams")
	return true
end

function DataService.adminAddGems(player: Player, amount: number): boolean
	return isStudioAdmin(player) and DataService.addCurrency(player, "Gems", amount, "studio_admin")
end

return DataService
