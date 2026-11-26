--!strict
-- Bagian DataService: pemilik mutasi reroll trait (Trait Shards, trait unit, pity trait global) dalam satu
-- commit atomik (Commit.run). Service lain hanya memanggil `apply` dengan request bernama dan `getState`
-- (salinan read-only); draft profil tidak pernah diberikan ke luar. Callback request hanya menerima state
-- pity + trait.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local Commit = require(script.Parent.Commit)
local Replication = require(script.Parent.Replication)
local TraitRules = require(script.Parent.TraitRules)

export type Request = TraitRules.Request
export type Result = TraitRules.Result
export type DirectRequest = TraitRules.DirectRequest
export type DirectResult = TraitRules.DirectResult
export type UnitState = { traitId: string?, locked: boolean }
export type State = { shards: number, gold: number, sinceLegendary: number, unit: UnitState }
export type Ledger = {
	apply: (player: Player, request: Request) -> (string?, Result?),
	-- Pilihan trait langsung dengan Gold (pemain restricted, D-OPEN-1).
	applyDirect: (player: Player, request: DirectRequest) -> (string?, DirectResult?),
	-- (kode, state): DATA_NOT_READY bila sesi belum siap, UNIT_NOT_OWNED bila uid bukan milik pemain.
	getState: (player: Player, uid: string) -> (string?, State?),
	getMyData: (player: Player) -> Types.MyData?,
}

local Traits = {}

function Traits.create(getSession: Commit.SessionGetter, changed: Signal.Signal<Player, string>): Ledger
	local function apply(player: Player, request: Request): (string?, Result?)
		local result: Result? = nil
		local code = Commit.run(getSession, changed, player, function(draft: Types.Profile)
			local failure, outcome, applied = TraitRules.apply(draft, request)
			result = applied
			return failure, outcome
		end)
		if code ~= nil then
			return code, nil
		end
		return nil, result
	end

	local function applyDirect(player: Player, request: DirectRequest): (string?, DirectResult?)
		local result: DirectResult? = nil
		local code = Commit.run(getSession, changed, player, function(draft: Types.Profile)
			local failure, outcome, applied = TraitRules.applyDirect(draft, request)
			result = applied
			return failure, outcome
		end)
		if code ~= nil then
			return code, nil
		end
		return nil, result
	end

	local function getState(player: Player, uid: string): (string?, State?)
		local session = getSession(player)
		if not session then
			return "DATA_NOT_READY", nil
		end
		local profile = session.Data
		local unit = if type(uid) == "string" then profile.units[uid] else nil
		if type(unit) ~= "table" then
			return "UNIT_NOT_OWNED", nil
		end
		return nil,
			{
				shards = profile.currencies.TraitShards,
				gold = profile.currencies.Gold,
				sinceLegendary = TraitRules.readPity(profile.traitPity),
				unit = { traitId = TraitRules.readTrait(unit.trait), locked = unit.locked ~= false },
			}
	end

	local function getMyData(player: Player): Types.MyData?
		local session = getSession(player)
		return if session then Replication.buildMyData(session.Data) else nil
	end

	return { apply = apply, applyDirect = applyDirect, getState = getState, getMyData = getMyData }
end

return table.freeze(Traits)
