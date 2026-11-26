--!strict
-- Bagian DataService: mutasi progres story & inventory yang di-commit atomik.
-- Pola: salin profil → aturan murni memutasi draft (tanpa yield) → bila sukses, draft menggantikan
-- session.Data dalam satu langkah. Gagal di titik mana pun = profil asli tidak tersentuh.
-- Service lain memanggil fungsi bernama di sini lewat `DataService.progress`, bukan menulis profil.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local AnalyticsService = require(script.Parent.Parent.AnalyticsService)
local InventoryRules = require(script.Parent.InventoryRules)
local Replication = require(script.Parent.Replication)
local StoryRules = require(script.Parent.StoryRules)

type Outcome = StoryRules.Outcome
type Mutation = (draft: Types.Profile) -> (string?, Outcome?)
type SessionLike = { Data: Types.Profile }

local getSession: ((Player) -> SessionLike?)? = nil
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
	local session = if sessionGetter then sessionGetter(player) else nil
	if not session then
		return "DATA_NOT_READY", nil
	end
	local original = session.Data
	local draft = TableUtil.deepCopy(original)
	StoryRules.reconcile(draft)
	local thread = coroutine.create(mutate)
	local ok, code, outcome = coroutine.resume(thread, draft)
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		warn("[DataService] progress mutation cannot yield")
		return "INTERNAL_ERROR", nil
	end
	if not ok then
		warn(`[DataService] progress mutation failed: {code}`)
		return "INTERNAL_ERROR", nil
	end
	if code ~= nil then
		return code, nil
	end
	if not outcome or (sessionGetter :: any)(player) ~= session or session.Data ~= original then
		return "DATA_NOT_READY", nil
	end
	session.Data = draft
	for _, delta in outcome.deltas do
		AnalyticsService.logCurrencyChange(player.UserId, delta.kind, delta.amount, delta.source)
	end
	local signal = changed :: Signal.Signal<Player, string>
	if outcome.units then
		signal:Fire(player, "units")
	end
	if outcome.currencies then
		signal:Fire(player, "currencies")
	end
	if outcome.teams then
		signal:Fire(player, "teams")
	end
	signal:Fire(player, "progress")
	return nil, outcome
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
