--!strict
-- Tipe & helper bersama modul TradeService (Coordinator, Requests). Tanpa logika sesi.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local TradeTypes = require(Shared.TradeTypes)
local TradeSession = require(script.Parent.TradeSession)

export type Offer = { uids: { string }, skins: { string } }
export type Party = { player: Player, userId: number, accountAgeDays: number, offer: Offer }
export type TradeApi = {
	isEnabled: () -> boolean,
	isLocked: (player: Player) -> boolean,
	checkPlayer: (player: Player, accountAgeDays: number) -> string?,
	checkOffer: (player: Player, offer: Offer) -> string?,
	checkPair: (a: Party, b: Party) -> string?,
	lock: (
		player: Player,
		lock: { uids: { string }, skins: { string }, gold: number, incomingUnits: number, incomingSkins: { string } }
	) -> (),
	unlock: (player: Player) -> (),
	-- "TRADE_PENDING_RECOVERY": keputusan belum diketahui; onResolved dipanggil sekali saat selesai.
	commit: (a: Party, b: Party, onResolved: ((code: string?) -> ())?) -> (string?, any?),
	describeUnits: (player: Player, uids: { string }) -> { TradeSession.UnitBrief },
}
export type Deps = {
	trades: TradeApi,
	proximity: (a: Player, b: Player) -> string?,
	isTradingAllowed: (player: Player) -> boolean, -- boleh yield; fail-closed
	accountAgeDays: (player: Player) -> number,
	findPlayer: (userId: number) -> Player?,
	isPresent: (player: Player) -> boolean,
	displayName: (player: Player?, userId: number) -> string,
	now: () -> number,
	newId: () -> string,
	send: (player: Player, view: TradeTypes.TradeView) -> (),
	spawn: (fn: () -> ()) -> (),
}
export type Handler = (player: Player, ...any) -> Types.Result
export type Context = {
	deps: Deps,
	sessions: { [string]: TradeSession.Session },
	byUser: { [number]: TradeSession.Session },
	playerOf: (side: TradeSession.Side) -> Player?,
	ownSession: (player: Player, sessionId: any) -> TradeSession.Session?,
	publish: (session: TradeSession.Session) -> (),
	success: (session: TradeSession.Session, player: Player) -> Types.Result,
	cancel: (session: TradeSession.Session, reason: string) -> boolean,
}

local Contract = {}

function Contract.fail(code: string): Types.Result
	return { ok = false, code = code }
end

return table.freeze(Contract)
