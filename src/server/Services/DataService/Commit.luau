--!strict
-- Bagian internal DataService: commit atomik draft profil. TIDAK diekspor lewat DataService.
-- Pola: salin profil → mutasi murni pada draft (tanpa yield) → bila sukses, draft menggantikan session.Data
-- dalam satu langkah. Gagal di titik mana pun (kode error, error Lua, yield, sesi hilang/berganti) =
-- profil asli tidak tersentuh.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local AnalyticsService = require(script.Parent.Parent.AnalyticsService)
local StoryRules = require(script.Parent.StoryRules)

export type Outcome = StoryRules.Outcome
export type Mutation = (draft: Types.Profile) -> (string?, Outcome?)
export type SessionLike = { Data: Types.Profile }
export type SessionGetter = (Player) -> SessionLike?

local Commit = {}

function Commit.run(
	getSession: SessionGetter,
	changed: Signal.Signal<Player, string>,
	player: Player,
	mutate: Mutation
): (string?, Outcome?)
	local session = getSession(player)
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
		warn("[DataService] profile mutation cannot yield")
		return "INTERNAL_ERROR", nil
	end
	if not ok then
		warn(`[DataService] profile mutation failed: {code}`)
		return "INTERNAL_ERROR", nil
	end
	if code ~= nil then
		return code, nil
	end
	if not outcome or getSession(player) ~= session or session.Data ~= original then
		return "DATA_NOT_READY", nil
	end
	session.Data = draft
	for _, delta in outcome.deltas do
		AnalyticsService.logCurrencyChange(player.UserId, delta.kind, delta.amount, delta.source)
	end
	if outcome.units then
		changed:Fire(player, "units")
	end
	if outcome.currencies then
		changed:Fire(player, "currencies")
	end
	if outcome.teams then
		changed:Fire(player, "teams")
	end
	changed:Fire(player, "progress")
	return nil, outcome
end

return table.freeze(Commit)
