--!strict
-- Bagian DataService: pemilik mutasi summon (uang, unit, pity, statistik) dalam satu commit atomik.
-- Service lain hanya memanggil `apply` dengan request bernama dan `getState` (salinan read-only);
-- draft profil tidak pernah diberikan ke luar. Callback request hanya menerima state pity.
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local Units = require(Shared.Config.Units)
local AnalyticsService = require(script.Parent.Parent.AnalyticsService)
local Commit = require(script.Parent.Commit)
local SummonRules = require(script.Parent.SummonRules)

export type Request = SummonRules.Request
export type PityState = SummonRules.PityState
export type State = {
	balances: { Gems: number, SummonTickets: number },
	unitCount: number,
	pity: { [string]: PityState },
}
export type Ledger = {
	apply: (player: Player, request: Request) -> (string?, { Types.OwnedUnit }?),
	getState: (player: Player) -> State?,
}
export type Options = { now: (() -> number)?, newUid: (() -> string)? }

local Summons = {}

local function defaultUid(): string
	return HttpService:GenerateGUID(false)
end

function Summons.create(
	getSession: Commit.SessionGetter,
	changed: Signal.Signal<Player, string>,
	options: Options?
): Ledger
	local clock = if options and options.now then options.now else os.time
	local newUid = if options and options.newUid then options.newUid else defaultUid

	local function apply(player: Player, request: Request): (string?, { Types.OwnedUnit }?)
		local now = clock()
		local granted: { Types.OwnedUnit }? = nil
		local code = Commit.run(getSession, changed, player, function(draft: Types.Profile)
			local failure, outcome, units = SummonRules.apply(draft, request, now, newUid)
			granted = units
			return failure, outcome
		end)
		if code ~= nil then
			return code, nil
		end
		-- Analytics dari unit yang benar-benar diberikan commit ini.
		local rarities: { string } = {}
		for _, unit in granted or {} do
			local def = Units[unit.unitId]
			table.insert(rarities, if def then def.rarity else "unknown")
		end
		AnalyticsService.logSummon(player, request.bannerId, request.currency, rarities)
		return nil, granted
	end

	local function getState(player: Player): State?
		local session = getSession(player)
		if not session then
			return nil
		end
		local profile = session.Data
		local pity: { [string]: PityState } = {}
		for bannerId, record in profile.pity do
			pity[bannerId] = SummonRules.readPity(record)
		end
		return {
			balances = { Gems = profile.currencies.Gems, SummonTickets = profile.currencies.SummonTickets },
			unitCount = SummonRules.countUnits(profile),
			pity = pity,
		}
	end

	return { apply = apply, getState = getState }
end

return table.freeze(Summons)
