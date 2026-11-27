--!strict
-- Koordinator sesi trade: handler remote (sudah di-rate-limit RemoteSetup) + siklus hidup sesi.
-- Semua dependensi Roblox/DataService diinjeksi sehingga alur bisa diuji dengan mock (tests/TradeFlow.spec).
-- Gerbang server: trade aktif, satu server, kedua avatar hidup & di Trading Plaza, syarat pemain (level,
-- umur akun, batas harian), kebijakan trade item berbayar afirmatif, kepemilikan & kelayakan item.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local TradeTypes = require(Shared.TradeTypes)
local Constants = require(Shared.Config.Constants)
local Trade = require(Shared.Config.Trade)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local Contract = require(script.Parent.Contract)
local TradeSession = require(script.Parent.TradeSession)
local Requests = require(script.Parent.Requests)
local View = require(script.Parent.View)

type Session = TradeSession.Session
type Side = TradeSession.Side
export type Offer = Contract.Offer
export type Party = Contract.Party
export type TradeApi = Contract.TradeApi
export type Deps = Contract.Deps
export type Handler = Contract.Handler
export type Coordinator = {
	handlers: { [string]: Handler },
	tick: () -> (),
	playerRemoving: (player: Player) -> (),
	sessionOf: (userId: number) -> Session?,
}

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local MAX_SESSION_ID_LENGTH = 64
local MAX_SKIN_ID_LENGTH = 64
local isSessionId = Validate.isStringMax(MAX_SESSION_ID_LENGTH)

local Coordinator = {}

local fail = Contract.fail

function Coordinator.create(deps: Deps): Coordinator
	local trades = deps.trades
	local sessions: { [string]: Session } = {}
	local byUser: { [number]: Session } = {}

	local function playerOf(side: Side): Player?
		local player = deps.findPlayer(side.userId)
		return if player and deps.isPresent(player) then player else nil
	end

	local function viewFor(session: Session, player: Player): TradeTypes.TradeView?
		local _, other = TradeSession.sides(session, player.UserId)
		if not other then
			return nil
		end
		return View.build(session, player.UserId, deps.displayName(playerOf(other), other.userId))
	end

	-- Kirim snapshot ke peserta yang masih di server; sesi terminal dilepas dari indeks.
	local function publish(session: Session): ()
		for _, side in { session.initiator, session.target } do
			local player = playerOf(side)
			local view = if player then viewFor(session, player) else nil
			if player and view then
				deps.send(player, view)
			end
		end
		if TradeSession.isTerminal(session) then
			sessions[session.id] = nil
			for _, side in { session.initiator, session.target } do
				if byUser[side.userId] == session then
					byUser[side.userId] = nil
				end
			end
		end
	end

	local function success(session: Session, player: Player): Types.Result
		return { ok = true, data = viewFor(session, player) }
	end

	local function unlockBoth(session: Session): ()
		for _, side in { session.initiator, session.target } do
			local player = deps.findPlayer(side.userId)
			if player then
				trades.unlock(player)
			end
		end
	end

	local function cancel(session: Session, reason: string): boolean
		local wasLocked = session.status == "Countdown"
		if not TradeSession.cancel(session, reason) then
			return false
		end
		if wasLocked then
			unlockBoth(session)
		end
		publish(session)
		return true
	end

	local function party(side: Side, player: Player): Party
		local uids: { string } = {}
		for _, unit in side.units do
			table.insert(uids, unit.uid)
		end
		return {
			player = player,
			userId = side.userId,
			accountAgeDays = deps.accountAgeDays(player),
			offer = { uids = uids, skins = table.clone(side.skins) },
		}
	end

	-- Sesi milik pemanggil. Sesi orang lain diperlakukan sama dengan tidak ada (tanpa bocoran).
	local function ownSession(player: Player, sessionId: any): Session?
		if not isSessionId(sessionId) then
			return nil
		end
		local session = sessions[sessionId]
		return if session and TradeSession.sides(session, player.UserId) then session else nil
	end

	local function startCommit(session: Session): ()
		deps.spawn(function()
			local playerA, playerB = playerOf(session.initiator), playerOf(session.target)
			local code: string? = nil
			if not playerA or not playerB then
				code = "PLAYER_LEFT"
			else
				code = deps.proximity(playerA, playerB)
				if not code and not (deps.isTradingAllowed(playerA) and deps.isTradingAllowed(playerB)) then
					code = "TRADE_POLICY_RESTRICTED"
				end
			end
			if code or not playerA or not playerB then
				unlockBoth(session)
			else
				-- Jurnal DataService melepas kunci sendiri (kecuali keputusan belum diketahui).
				code = trades.commit(party(session.initiator, playerA), party(session.target, playerB))
			end
			if TradeSession.finish(session, code) then
				publish(session)
			end
		end)
	end

	local handlers: { [string]: Handler } = {}

	Requests.attach(handlers, {
		deps = deps,
		sessions = sessions,
		byUser = byUser,
		playerOf = playerOf,
		ownSession = ownSession,
		publish = publish,
		success = success,
		cancel = cancel,
	})

	function handlers.SetTradeItems(player: Player, sessionId: any, unitUids: any, skinIds: any, ...: any): Types.Result
		if
			select("#", ...) > 0
			or not Validate.isStringArray(unitUids, 0, Trade.maxItemsPerSide, Constants.MAX_UID_LENGTH)
			or not Validate.isStringArray(skinIds, 0, Trade.maxItemsPerSide, MAX_SKIN_ID_LENGTH)
		then
			return fail("INVALID_ARGUMENTS")
		end
		local session = ownSession(player, sessionId)
		if not session then
			return fail("TRADE_NOT_FOUND")
		end
		local uids, skins = table.clone(unitUids :: { string }), table.clone(skinIds :: { string })
		if #uids + #skins > Trade.maxItemsPerSide then
			return fail("TOO_MANY_ITEMS")
		end
		local code = trades.checkOffer(player, { uids = uids, skins = skins })
		if code then
			return fail(code)
		end
		local before = session.updateId
		code = TradeSession.setItems(session, player.UserId, trades.describeUnits(player, uids), skins)
		if code then
			return fail(code)
		end
		if session.updateId ~= before then
			publish(session)
		end
		return success(session, player)
	end

	function handlers.SetReady(
		player: Player,
		sessionId: any,
		ready: any,
		expectedRevision: any,
		...: any
	): Types.Result
		if
			select("#", ...) > 0
			or typeof(ready) ~= "boolean"
			or not Validate.isIntInRange(expectedRevision, 0, MAX_EXACT_INTEGER)
		then
			return fail("INVALID_ARGUMENTS")
		end
		local session = ownSession(player, sessionId)
		if not session then
			return fail("TRADE_NOT_FOUND")
		end
		local mine, other = TradeSession.sides(session, player.UserId)
		local otherPlayer = if other then playerOf(other) else nil
		if ready and TradeSession.wouldArm(session, player.UserId) and mine and other then
			if not otherPlayer then
				cancel(session, "PLAYER_LEFT")
				return fail("PLAYER_LEFT")
			end
			-- Kebijakan dulu (bisa yield, biasanya dari cache), lalu cek sinkron tanpa yield sampai kunci dipasang.
			if not deps.isTradingAllowed(player) or not deps.isTradingAllowed(otherPlayer) then
				return fail("TRADE_POLICY_RESTRICTED")
			end
			if not TradeSession.wouldArm(session, player.UserId) or expectedRevision ~= session.revision then
				return fail("STALE_REVISION")
			end
			local code = deps.proximity(player, otherPlayer)
				or trades.checkPair(party(mine, player), party(other, otherPlayer))
			if code then
				return fail(code)
			end
		end
		local wasCountdown = session.status == "Countdown"
		local before = session.updateId
		local code, armed = TradeSession.setReady(session, player.UserId, ready, expectedRevision, deps.now())
		if code then
			return fail(code)
		end
		if armed and mine and other and otherPlayer then
			local mineParty, otherParty = party(mine, player), party(other, otherPlayer)
			local tax = Trade.taxGold
			trades.lock(player, {
				uids = mineParty.offer.uids,
				skins = mineParty.offer.skins,
				gold = tax,
				incomingUnits = #other.units,
				incomingSkins = table.clone(other.skins),
			})
			trades.lock(otherPlayer, {
				uids = otherParty.offer.uids,
				skins = otherParty.offer.skins,
				gold = tax,
				incomingUnits = #mine.units,
				incomingSkins = table.clone(mine.skins),
			})
		elseif wasCountdown and session.status ~= "Countdown" then
			unlockBoth(session)
		end
		if session.updateId ~= before then
			publish(session)
		end
		return success(session, player)
	end

	function handlers.ConfirmTrade(player: Player, sessionId: any, expectedRevision: any, ...: any): Types.Result
		if select("#", ...) > 0 or not Validate.isIntInRange(expectedRevision, 0, MAX_EXACT_INTEGER) then
			return fail("INVALID_ARGUMENTS")
		end
		local session = ownSession(player, sessionId)
		if not session then
			return fail("TRADE_NOT_FOUND")
		end
		local before = session.updateId
		local code, both = TradeSession.confirm(session, player.UserId, expectedRevision, deps.now())
		if code then
			return fail(code)
		end
		if session.updateId ~= before then
			publish(session)
		end
		local result = success(session, player)
		if both then
			startCommit(session)
		end
		return result
	end

	function handlers.CancelTrade(player: Player, sessionId: any, ...: any): Types.Result
		if select("#", ...) > 0 then
			return fail("INVALID_ARGUMENTS")
		end
		local session = ownSession(player, sessionId)
		if not session then
			return fail("TRADE_NOT_FOUND")
		end
		if session.status == "Confirmed" then
			return fail("TRADE_COMMITTING")
		end
		local view = viewFor(session, player)
		if not cancel(session, "CANCELLED_BY_PLAYER") then
			return fail("TRADE_CLOSED")
		end
		view = viewFor(session, player) or view
		return { ok = true, data = view }
	end

	-- Expiry, peserta hilang, dan syarat lokasi selama countdown. Dipanggil berkala oleh TradeService.
	local function tick(): ()
		local now = deps.now()
		for _, session in table.clone(sessions) do
			local playerA, playerB = playerOf(session.initiator), playerOf(session.target)
			if session.status == "Confirmed" then
				continue
			elseif not playerA or not playerB then
				cancel(session, "PLAYER_LEFT")
			elseif now >= session.expiresAt then
				cancel(session, "EXPIRED")
			elseif session.status == "Countdown" then
				local code = deps.proximity(playerA, playerB)
				if code then
					cancel(session, code)
				end
			end
		end
	end

	local function playerRemoving(player: Player): ()
		local session = byUser[player.UserId]
		if session then
			cancel(session, "PLAYER_LEFT")
		end
	end

	return {
		handlers = handlers,
		tick = tick,
		playerRemoving = playerRemoving,
		sessionOf = function(userId: number): Session?
			return byUser[userId]
		end,
	}
end

return table.freeze(Coordinator)
