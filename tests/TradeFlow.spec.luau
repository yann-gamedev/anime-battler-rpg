--!strict
-- Alur TradeService.Coordinator dengan mock (tanpa Roblox/DataService): gerbang remote, event hanya ke
-- peserta, UID lawan tidak terkirim, confirm 20× → commit sekali, keluar/timeout/jarak saat countdown,
-- isi terkunci saat countdown, revision basi, dan kegagalan commit.
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Coordinator = require(Server.Services.TradeService.Coordinator)
local Trade = require(game:GetService("ReplicatedStorage").Shared.Config.Trade)

local function world()
	local w: any = {
		now = 1000,
		present = {},
		players = {},
		events = {},
		queue = {},
		proximity = nil,
		policy = {},
		playerCodes = {},
		commits = 0,
		commitCode = nil,
		locks = {},
		unlocks = 0,
		enabled = true,
		nextId = 0,
	}
	local function newPlayer(userId: number): any
		local player = { UserId = userId, DisplayName = `P{userId}` }
		w.players[userId] = player
		w.present[player] = true
		w.policy[player] = true
		w.events[player] = {}
		return player
	end
	w.a, w.b, w.c = newPlayer(1), newPlayer(2), newPlayer(3)
	w.coordinator = Coordinator.create({
		trades = {
			isEnabled = function()
				return w.enabled
			end,
			isLocked = function(player: any)
				return w.locks[player] ~= nil
			end,
			checkPlayer = function(player: any)
				return w.playerCodes[player]
			end,
			checkOffer = function()
				return nil
			end,
			checkPair = function()
				return w.pairCode
			end,
			lock = function(player: any, lock: any)
				w.locks[player] = lock
			end,
			unlock = function(player: any)
				w.locks[player] = nil
				w.unlocks += 1
			end,
			commit = function(a: any, b: any, onResolved: any)
				w.onResolved = onResolved
				w.commits += 1
				w.lastParties = { a, b }
				w.locks[a.player] = nil
				w.locks[b.player] = nil
				return w.commitCode
			end,
			describeUnits = function(_player: any, uids: { string })
				local list = {}
				for _, uid in uids do
					table.insert(list, { uid = uid, unitId = "kael", stars = 1 })
				end
				return list
			end,
		},
		proximity = function()
			return w.proximity
		end,
		isTradingAllowed = function(player: any)
			return w.policy[player] == true
		end,
		accountAgeDays = function()
			return 30
		end,
		findPlayer = function(userId: number)
			return w.players[userId]
		end,
		isPresent = function(player: any)
			return w.present[player] == true
		end,
		displayName = function(player: any, userId: number)
			return if player then player.DisplayName else tostring(userId)
		end,
		now = function()
			return w.now
		end,
		newId = function()
			w.nextId += 1
			return `session-{w.nextId}`
		end,
		send = function(player: any, view: any)
			table.insert(w.events[player], view)
		end,
		spawn = function(fn: () -> ())
			table.insert(w.queue, fn)
		end,
	})
	local h = w.coordinator.handlers
	w.h = h
	function w.drain(): ()
		while #w.queue > 0 do
			table.remove(w.queue, 1)()
		end
	end
	function w.last(player: any): any
		local list = w.events[player]
		return list[#list]
	end
	-- Sesi terbuka dengan satu unit di setiap sisi.
	function w.openSession(): string
		local id = h.RequestTrade(w.a, 2).data.sessionId
		assert(h.RespondTrade(w.b, id, true).ok, "TradeFlow setup must hold: h.RespondTrade(w.b, id, true).ok")
		assert(
			h.SetTradeItems(w.a, id, { "ua" }, {}).ok,
			"TradeFlow setup must hold: h.SetTradeItems(w.a, id, { 'ua' }, {}).ok"
		)
		assert(
			h.SetTradeItems(w.b, id, { "ub" }, {}).ok,
			"TradeFlow setup must hold: h.SetTradeItems(w.b, id, { 'ub' }, {}).ok"
		)
		return id
	end
	function w.countdown(): (string, number)
		local id = w.openSession()
		local revision = w.last(w.a).revision
		assert(
			h.SetReady(w.a, id, true, revision).ok,
			"TradeFlow setup must hold: h.SetReady(w.a, id, true, revision).ok"
		)
		local result = h.SetReady(w.b, id, true, revision)
		assert(result.ok, result.code)
		return id, result.data.revision
	end
	return w
end

return function(t: TestRunner.TestContext): ()
	t.test("request validates arguments and gates", function()
		local w = world()
		local h = w.h
		t.expect(h.RequestTrade(w.a, "2").code).toBe("INVALID_ARGUMENTS")
		t.expect(h.RequestTrade(w.a, 0 / 0).code).toBe("INVALID_ARGUMENTS")
		t.expect(h.RequestTrade(w.a, 2, "extra").code).toBe("INVALID_ARGUMENTS")
		t.expect(h.RequestTrade(w.a, 1).code).toBe("INVALID_TARGET")
		t.expect(h.RequestTrade(w.a, 99).code).toBe("TARGET_NOT_IN_SERVER")
		w.proximity = "NOT_IN_PLAZA"
		t.expect(h.RequestTrade(w.a, 2).code).toBe("NOT_IN_PLAZA")
		w.proximity = nil
		w.playerCodes[w.b] = "ACCOUNT_TOO_NEW"
		t.expect(h.RequestTrade(w.a, 2).code).toBe("TARGET_ACCOUNT_TOO_NEW")
		w.playerCodes[w.b] = nil
		w.policy[w.a] = false
		t.expect(h.RequestTrade(w.a, 2).code).toBe("TRADE_POLICY_RESTRICTED")
		w.policy[w.a] = true
		w.policy[w.b] = false
		t.expect(h.RequestTrade(w.a, 2).code).toBe("TARGET_TRADE_POLICY_RESTRICTED")
		w.enabled = false
		t.expect(h.RequestTrade(w.a, 2).code).toBe("TRADE_DISABLED")
	end)

	t.test("busy players cannot start a second session", function()
		local w = world()
		assert(w.h.RequestTrade(w.a, 2).ok, "TradeFlow setup must hold: w.h.RequestTrade(w.a, 2).ok")
		t.expect(w.h.RequestTrade(w.c, 1).code).toBe("TARGET_BUSY")
		t.expect(w.h.RequestTrade(w.b, 3).code).toBe("TRADE_BUSY")
	end)

	t.test("updates go only to participants and never reveal opponent UIDs", function()
		local w = world()
		local id = w.openSession()
		t.expect(#w.events[w.c]).toBe(0)
		local viewA = w.last(w.a)
		t.expect(viewA.sessionId).toBe(id)
		t.expect(viewA.mine.units[1].uid).toBe("ua")
		t.expect(viewA.theirs.units[1].uid).toBe(nil)
		t.expect(viewA.theirs.units[1].name ~= nil).toBe(true)
		t.expect(w.h.SetTradeItems(w.c, id, {}, {}).code).toBe("TRADE_NOT_FOUND")
		t.expect(w.h.CancelTrade(w.c, id).code).toBe("TRADE_NOT_FOUND")
	end)

	t.test("set items validates array shapes", function()
		local w = world()
		local id = w.openSession()
		t.expect(w.h.SetTradeItems(w.a, id, { 1 }, {}).code).toBe("INVALID_ARGUMENTS")
		t.expect(w.h.SetTradeItems(w.a, id, { "" }, {}).code).toBe("INVALID_ARGUMENTS")
		t.expect(w.h.SetTradeItems(w.a, id, { "a", nil, "b" } :: any, {}).code).toBe("INVALID_ARGUMENTS")
		local many = {}
		for index = 1, Trade.maxItemsPerSide do
			table.insert(many, `u{index}`)
		end
		t.expect(w.h.SetTradeItems(w.a, id, many, { "skin" }).code).toBe("TOO_MANY_ITEMS")
	end)

	t.test("arming the countdown checks the pair and locks both offers", function()
		local w = world()
		local id = w.openSession()
		local revision = w.last(w.a).revision
		assert(
			w.h.SetReady(w.a, id, true, revision).ok,
			"TradeFlow setup must hold: w.h.SetReady(w.a, id, true, revision).ok"
		)
		w.pairCode = "NOT_ENOUGH_GOLD"
		t.expect(w.h.SetReady(w.b, id, true, revision).code).toBe("NOT_ENOUGH_GOLD")
		t.expect(w.locks[w.a]).toBe(nil)
		w.pairCode = nil
		t.expect(w.h.SetReady(w.b, id, true, revision - 1).code).toBe("STALE_REVISION")
		local result = w.h.SetReady(w.b, id, true, revision)
		t.expect(result.data.status).toBe("Countdown")
		t.expect(w.locks[w.a].uids[1]).toBe("ua")
		t.expect(w.locks[w.b].incomingUnits).toBe(1)
		t.expect(w.locks[w.a].gold).toBe(Trade.taxGold)
	end)

	t.test("editing during countdown is rejected", function()
		local w = world()
		local id = w.countdown()
		t.expect(w.h.SetTradeItems(w.b, id, {}, {}).code).toBe("TRADE_LOCKED")
	end)

	t.test("rapid confirm spam commits exactly once", function()
		local w = world()
		local id, revision = w.countdown()
		t.expect(w.h.ConfirmTrade(w.a, id, revision).code).toBe("COUNTDOWN_ACTIVE")
		w.now += Trade.countdownSeconds
		for _ = 1, 20 do
			w.h.ConfirmTrade(w.a, id, revision)
			w.h.ConfirmTrade(w.b, id, revision)
		end
		w.drain()
		t.expect(w.commits).toBe(1)
		t.expect(w.last(w.a).status).toBe("Done")
		t.expect(w.last(w.b).status).toBe("Done")
		t.expect(w.coordinator.sessionOf(1)).toBe(nil)
		t.expect(w.h.ConfirmTrade(w.a, id, revision).code).toBe("TRADE_NOT_FOUND")
	end)

	t.test("leaving during countdown cancels and releases locks without commit", function()
		local w = world()
		w.countdown()
		w.present[w.b] = nil
		w.coordinator.playerRemoving(w.b)
		t.expect(w.last(w.a).status).toBe("Cancelled")
		t.expect(w.last(w.a).reason).toBe("PLAYER_LEFT")
		t.expect(w.locks[w.a]).toBe(nil)
		t.expect(w.commits).toBe(0)
	end)

	t.test("leaving after both confirmed but before commit cancels before the final commit", function()
		local w = world()
		local id, revision = w.countdown()
		w.now += Trade.countdownSeconds
		w.h.ConfirmTrade(w.a, id, revision)
		w.h.ConfirmTrade(w.b, id, revision)
		t.expect(w.h.CancelTrade(w.a, id).code).toBe("TRADE_COMMITTING")
		w.present[w.b] = nil
		w.coordinator.playerRemoving(w.b)
		w.drain()
		t.expect(w.commits).toBe(0)
		t.expect(w.last(w.a).reason).toBe("PLAYER_LEFT")
		t.expect(w.locks[w.a]).toBe(nil)
	end)

	t.test("expiry and lost proximity cancel open sessions", function()
		local w = world()
		w.openSession()
		w.now += Trade.sessionMaxSeconds + 1
		w.coordinator.tick()
		t.expect(w.last(w.a).reason).toBe("EXPIRED")
		local other = world()
		other.countdown()
		other.proximity = "TOO_FAR"
		other.coordinator.tick()
		t.expect(other.last(other.b).reason).toBe("TOO_FAR")
		t.expect(other.locks[other.b]).toBe(nil)
	end)

	t.test("unanswered request expires after requestSeconds", function()
		local w = world()
		assert(w.h.RequestTrade(w.a, 2).ok, "TradeFlow setup must hold: w.h.RequestTrade(w.a, 2).ok")
		w.now += Trade.requestSeconds
		w.coordinator.tick()
		t.expect(w.last(w.b).status).toBe("Cancelled")
		t.expect(w.last(w.b).reason).toBe("EXPIRED")
	end)

	t.test("commit failure ends Cancelled with the failure code", function()
		local w = world()
		local id, revision = w.countdown()
		w.now += Trade.countdownSeconds
		w.commitCode = "UNIT_NOT_OWNED"
		w.h.ConfirmTrade(w.a, id, revision)
		w.h.ConfirmTrade(w.b, id, revision)
		w.drain()
		t.expect(w.commits).toBe(1)
		t.expect(w.last(w.b).status).toBe("Cancelled")
		t.expect(w.last(w.b).reason).toBe("UNIT_NOT_OWNED")
	end)

	t.test("ambiguous commit stays Confirmed until the journal resolves", function()
		local w = world()
		local id, revision = w.countdown()
		w.now += Trade.countdownSeconds
		w.commitCode = "TRADE_PENDING_RECOVERY"
		w.h.ConfirmTrade(w.a, id, revision)
		w.h.ConfirmTrade(w.b, id, revision)
		w.drain()
		t.expect(w.last(w.a).status).toBe("Confirmed")
		t.expect(w.h.CancelTrade(w.a, id).code).toBe("TRADE_COMMITTING")
		w.coordinator.tick()
		t.expect(w.last(w.a).status).toBe("Confirmed")
		t.expect(w.h.RequestTrade(w.a, 3).code).toBe("TRADE_BUSY")
		w.onResolved(nil)
		t.expect(w.last(w.a).status).toBe("Done")
		t.expect(w.last(w.b).status).toBe("Done")
		w.onResolved("LATE")
		t.expect(w.last(w.a).status).toBe("Done")
		t.expect(w.coordinator.sessionOf(1)).toBe(nil)
	end)

	t.test("one empty side is allowed and both-empty is rejected", function()
		local w = world()
		local id = w.h.RequestTrade(w.a, 2).data.sessionId
		w.h.RespondTrade(w.b, id, true)
		local revision = w.last(w.a).revision
		t.expect(w.h.SetReady(w.a, id, true, revision).code).toBe("BOTH_SIDES_EMPTY")
		assert(
			w.h.SetTradeItems(w.a, id, { "ua" }, {}).ok,
			"TradeFlow setup must hold: w.h.SetTradeItems(w.a, id, { 'ua' }, {}).ok"
		)
		revision = w.last(w.a).revision
		t.expect(w.h.SetReady(w.b, id, true, revision).ok).toBe(true)
		t.expect(#w.last(w.b).mine.units).toBe(0)
	end)
end
