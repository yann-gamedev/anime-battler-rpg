--!strict
-- Bagian DataService: mutasi progres story & inventory yang di-commit atomik.
-- Pola commit atomik ada di DataService/Commit.luau (draft → aturan murni tanpa yield → swap sekali).
-- Service lain memanggil fungsi bernama di sini lewat `DataService.progress`, bukan menulis profil.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local Commit = require(script.Parent.Commit)
local InventoryRules = require(script.Parent.InventoryRules)
local Replication = require(script.Parent.Replication)
local StoryRules = require(script.Parent.StoryRules)

type Outcome = StoryRules.Outcome
type Mutation = (draft: Types.Profile) -> (string?, Outcome?)
local getSession: Commit.SessionGetter? = nil
local changed: Signal.Signal<Player, string>? = nil

local Progress = {}

-- Dipanggil sekali oleh DataService.init.
function Progress.bind(sessionGetter: (Player) -> any, changedSignal: Signal.Signal<Player, string>): ()
	getSession = sessionGetter
	changed = changedSignal
end

-- Melengkapi field additive v1 pada profil (dipanggil saat profil dimuat dan pada setiap draft).
function Progress.reconcile(profile: Types.Profile): ()
	StoryRules.reconcile(profile)
end

local function commit(player: Player, mutate: Mutation): (string?, Outcome?)
	local sessionGetter = getSession
	local signal = changed
	if not sessionGetter or not signal then
		return "DATA_NOT_READY", nil
	end
	return Commit.run(sessionGetter, signal, player, mutate)
end

-- Snapshot GetMyData terbaru milik pemanggil, atau nil jika data belum siap.
function Progress.getMyData(player: Player): Types.MyData?
	local session = if getSession then getSession(player) else nil
	return if session then Replication.buildMyData(session.Data) else nil
end

function Progress.getProgression(player: Player): Types.ProgressionData?
	local session = if getSession then getSession(player) else nil
	return if session then Replication.progression(session.Data) else nil
end

-- Hasil battle stage → bintang, reward, progres. `stars` dihitung server dari BattleResult.
function Progress.applyStageResult(player: Player, stageId: string, stars: number): (string?, Outcome?)
	local now = os.time()
	return commit(player, function(draft: Types.Profile): (string?, Outcome?)
		return StoryRules.applyStageResult(draft, stageId, stars, now)
	end)
end

function Progress.levelUpUnit(player: Player, uid: string, levels: number): string?
	return (
		commit(player, function(draft: Types.Profile): (string?, Outcome?)
			return InventoryRules.levelUp(draft, uid, levels)
		end)
	)
end

function Progress.mergeUnit(player: Player, targetUid: string, materialUids: { string }): string?
	local materials = table.clone(materialUids)
	return (
		commit(player, function(draft: Types.Profile): (string?, Outcome?)
			return InventoryRules.merge(draft, targetUid, materials)
		end)
	)
end

function Progress.dismantleUnits(player: Player, uids: { string }): string?
	local list = table.clone(uids)
	return (
		commit(player, function(draft: Types.Profile): (string?, Outcome?)
			return InventoryRules.dismantle(draft, list)
		end)
	)
end

function Progress.setUnitLocked(player: Player, uid: string, locked: boolean): string?
	return (
		commit(player, function(draft: Types.Profile): (string?, Outcome?)
			return InventoryRules.setLocked(draft, uid, locked)
		end)
	)
end

return table.freeze(Progress)
