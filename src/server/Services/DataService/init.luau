--!strict
-- DataService: SATU-SATUNYA modul yang memegang & memutasi data pemain (docs/RULES.md §3).
-- Backend saat ini: SessionStore (demo, tidak persisten). Lihat SessionStore.luau.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Units = require(Shared.Config.Units)
local Signal = require(Shared.Util.Signal)
local Migrations = require(script.Migrations)
local SessionStore = require(script.SessionStore)

local DataService = {}

-- Changed(player, path): path = "units" | "teams" | ...
DataService.Changed = Signal.new() :: Signal.Signal<Player, string>

local profiles: { [Player]: Types.Profile } = {}

local function countUnits(profile: Types.Profile): number
	local count = 0
	for _ in profile.units do
		count += 1
	end
	return count
end

-- Membuat unit baru tanpa yield. nil jika unitId tak dikenal atau batas unit penuh.
local function createUnit(profile: Types.Profile, unitId: string, source: Types.UnitSource): Types.OwnedUnit?
	if Units[unitId] == nil then
		warn(`[DataService] unitId tidak dikenal: {unitId}`)
		return nil
	end
	if countUnits(profile) >= Constants.MAX_UNITS_PER_PLAYER then
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

local function grantStarterUnits(profile: Types.Profile)
	for _, unitId in Constants.STARTER_UNIT_IDS do
		createUnit(profile, unitId, Constants.STARTER_UNIT_SOURCE :: Types.UnitSource)
	end
end

local function onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end
	local loaded = SessionStore.load(player.UserId)
	if not loaded then
		player:Kick("Data kamu gagal dimuat. Silakan masuk lagi sebentar lagi.")
		return
	end
	local profile = loaded.profile
	Migrations.run(profile)
	if loaded.isNew then
		grantStarterUnits(profile)
	end
	if player.Parent ~= Players then
		-- Pemain keluar saat profil dimuat.
		SessionStore.release(player.UserId)
		return
	end
	profiles[player] = profile
end

local function onPlayerRemoving(player: Player)
	profiles[player] = nil
	SessionStore.release(player.UserId)
end

function DataService.init()
	if not SessionStore.PERSISTENT then
		warn("[DataService] Mode SessionStore demo: data TIDAK disimpan, rejoin = profil baru.")
	end
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	game:BindToClose(function()
		for player in profiles do
			onPlayerRemoving(player)
		end
	end)
end

-- READ-ONLY untuk modul lain. Jangan memutasi tabel yang dikembalikan;
-- semua mutasi lewat fungsi DataService di bawah.
function DataService.getProfile(player: Player): Types.Profile?
	return profiles[player]
end

-- Set UID milik pemain (salinan baru, aman dimutasi pemanggil).
function DataService.getOwnedUidSet(player: Player): { [string]: boolean }?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local owned: { [string]: boolean } = {}
	for uid in profile.units do
		owned[uid] = true
	end
	return owned
end

function DataService.grantUnit(player: Player, unitId: string, source: Types.UnitSource): Types.OwnedUnit?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local unit = createUnit(profile, unitId, source)
	if unit then
		DataService.Changed:Fire(player, "units")
	end
	return unit
end

-- Menyimpan slot tim. `slots` = dense BOARD_SLOTS string ("" = kosong) yang SUDAH divalidasi
-- pemanggil (TeamRules); kepemilikan dicek ulang di sini tanpa yield sebagai pertahanan kedua.
function DataService.setTeamSlots(player: Player, teamIndex: number, slots: { string }): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local team = profile.teams[teamIndex]
	if not team then
		return false
	end
	local stored: { [number]: string? } = {}
	for index = 1, Constants.BOARD_SLOTS do
		local uid = slots[index]
		if typeof(uid) ~= "string" then
			return false
		end
		if uid ~= "" then
			if profile.units[uid] == nil then
				return false
			end
			stored[index] = uid
		end
	end
	team.slots = stored
	DataService.Changed:Fire(player, "teams")
	return true
end

return DataService
