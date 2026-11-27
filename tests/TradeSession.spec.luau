--!strict
-- State machine trade murni (prompt 11): transisi, revision vs updateId, persetujuan basi, countdown,
-- konfirmasi berulang, batal/expiry, dan satu hasil terminal.
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local TradeSession = require(Server.Services.TradeService.TradeSession)
local Trade = require(game:GetService("ReplicatedStorage").Shared.Config.Trade)

local A, B = 1, 2

local function unit(uid: string): TradeSession.UnitBrief
	return { uid = uid, unitId = "kael", stars = 1 }
end

local function open(): TradeSession.Session
	local session = TradeSession.new("s1", A, B, 100)
	assert(
		TradeSession.respond(session, B, true, 101) == nil,
		"TradeSession setup must hold: TradeSession.respond(session, B, true, 101) == nil"
	)
	return session
end

-- Sesi di Countdown dengan unit di sisi A, kembali dengan revision countdown.
local function countdown(): (TradeSession.Session, number)
	local session = open()
	assert(
		TradeSession.setItems(session, A, { unit("u1") }, {}) == nil,
		"TradeSession setup must hold: TradeSession.setItems(session, A, { unit('u1') }, {}) == nil"
	)
	assert(
		TradeSession.setReady(session, A, true, session.revision, 102) == nil,
		"TradeSession setup must hold: TradeSession.setReady(session, A, true, session.revision, 102) == nil"
	)
	local code, armed = TradeSession.setReady(session, B, true, session.revision, 103)
	assert(code == nil and armed, "TradeSession setup must hold: code == nil and armed")
	return session, session.revision
end

return function(t: TestRunner.TestContext): ()
	t.test("request starts Requested with short expiry and only the target can respond", function()
		local session = TradeSession.new("s1", A, B, 100)
		t.expect(session.status).toBe("Requested")
		t.expect(session.expiresAt).toBe(100 + Trade.requestSeconds)
		t.expect(TradeSession.respond(session, A, true, 101)).toBe("NOT_TARGET")
		t.expect(TradeSession.respond(session, 3, true, 101)).toBe("NOT_PARTICIPANT")
		t.expect(TradeSession.setItems(session, A, {}, {})).toBe("TRADE_NOT_OPEN")
		t.expect(TradeSession.respond(session, B, true, 101)).toBe(nil)
		t.expect(session.status).toBe("Open")
		t.expect(session.expiresAt).toBe(100 + Trade.sessionMaxSeconds)
		t.expect(TradeSession.respond(session, B, true, 101)).toBe("ALREADY_RESPONDED")
	end)

	t.test("decline cancels with DECLINED", function()
		local session = TradeSession.new("s1", A, B, 100)
		t.expect(TradeSession.respond(session, B, false, 101)).toBe(nil)
		t.expect(session.status).toBe("Cancelled")
		t.expect(session.reason).toBe("DECLINED")
		t.expect(TradeSession.respond(session, B, true, 101)).toBe("TRADE_CLOSED")
	end)

	t.test("item change bumps revision and updateId and resets both readiness", function()
		local session = open()
		assert(
			TradeSession.setItems(session, B, { unit("b1") }, {}) == nil,
			"TradeSession setup must hold: TradeSession.setItems(session, B, { unit('b1') }, {}) == nil"
		)
		assert(
			TradeSession.setReady(session, B, true, session.revision, 102) == nil,
			"TradeSession setup must hold: TradeSession.setReady(session, B, true, session.revision, 102) == nil"
		)
		local revision, updateId = session.revision, session.updateId
		t.expect(TradeSession.setItems(session, A, { unit("a1") }, { "skin_x" })).toBe(nil)
		t.expect(session.revision).toBe(revision + 1)
		t.expect(session.updateId).toBe(updateId + 1)
		t.expect(session.target.ready).toBe(false)
		t.expect(session.status).toBe("Open")
	end)

	t.test("identical item list is a no-op without new revision", function()
		local session = open()
		assert(
			TradeSession.setItems(session, A, { unit("a1") }, {}) == nil,
			"TradeSession setup must hold: TradeSession.setItems(session, A, { unit('a1') }, {}) == nil"
		)
		local revision, updateId = session.revision, session.updateId
		t.expect(TradeSession.setItems(session, A, { unit("a1") }, {})).toBe(nil)
		t.expect(session.revision).toBe(revision)
		t.expect(session.updateId).toBe(updateId)
	end)

	t.test("rejects more than maxItemsPerSide combined items", function()
		local session = open()
		local units = {}
		for index = 1, Trade.maxItemsPerSide do
			table.insert(units, unit(`u{index}`))
		end
		t.expect(TradeSession.setItems(session, A, units, { "skin" })).toBe("TOO_MANY_ITEMS")
		t.expect(TradeSession.setItems(session, A, units, {})).toBe(nil)
	end)

	t.test("both sides empty cannot be readied; one empty side is allowed", function()
		local session = open()
		t.expect((TradeSession.setReady(session, A, true, session.revision, 102))).toBe("BOTH_SIDES_EMPTY")
		assert(
			TradeSession.setItems(session, A, { unit("a1") }, {}) == nil,
			"TradeSession setup must hold: TradeSession.setItems(session, A, { unit('a1') }, {}) == nil"
		)
		t.expect((TradeSession.setReady(session, B, true, session.revision, 102))).toBe(nil)
		t.expect(session.status).toBe("Ready")
	end)

	t.test("stale revision ready is rejected without mutation", function()
		local session = open()
		assert(
			TradeSession.setItems(session, A, { unit("a1") }, {}) == nil,
			"TradeSession setup must hold: TradeSession.setItems(session, A, { unit('a1') }, {}) == nil"
		)
		local updateId = session.updateId
		t.expect((TradeSession.setReady(session, A, true, session.revision - 1, 102))).toBe("STALE_REVISION")
		t.expect(session.initiator.ready).toBe(false)
		t.expect(session.updateId).toBe(updateId)
	end)

	t.test("simultaneous ready at the same revision are both valid and arm the countdown", function()
		local session = open()
		assert(
			TradeSession.setItems(session, A, { unit("a1") }, {}) == nil,
			"TradeSession setup must hold: TradeSession.setItems(session, A, { unit('a1') }, {}) == nil"
		)
		local revision = session.revision
		t.expect(TradeSession.wouldArm(session, A)).toBe(false)
		t.expect((TradeSession.setReady(session, A, true, revision, 102))).toBe(nil)
		t.expect(session.revision).toBe(revision)
		t.expect(TradeSession.wouldArm(session, B)).toBe(true)
		local code, armed = TradeSession.setReady(session, B, true, revision, 102)
		t.expect(code).toBe(nil)
		t.expect(armed).toBe(true)
		t.expect(session.status).toBe("Countdown")
		t.expect(session.revision).toBe(revision + 1)
		t.expect(session.countdownEndsAt).toBe(102 + Trade.countdownSeconds)
	end)

	t.test("content is locked during countdown", function()
		local session, revision = countdown()
		local updateId = session.updateId
		t.expect(TradeSession.setItems(session, B, { unit("b1") }, {})).toBe("TRADE_LOCKED")
		t.expect(session.revision).toBe(revision)
		t.expect(session.updateId).toBe(updateId)
	end)

	t.test("confirm before countdown end returns COUNTDOWN_ACTIVE without mutation", function()
		local session, revision = countdown()
		local updateId = session.updateId
		local code = TradeSession.confirm(session, A, revision, (session.countdownEndsAt :: number) - 0.1)
		t.expect(code).toBe("COUNTDOWN_ACTIVE")
		t.expect(session.initiator.confirmed).toBe(false)
		t.expect(session.updateId).toBe(updateId)
	end)

	t.test("confirm requires the armed countdown revision", function()
		local session, revision = countdown()
		local after = session.countdownEndsAt :: number
		t.expect((TradeSession.confirm(session, A, revision - 1, after))).toBe("STALE_REVISION")
		t.expect((TradeSession.confirm(session, A, revision, after))).toBe(nil)
		t.expect(session.status).toBe("Countdown")
	end)

	t.test("both confirmations move to Confirmed exactly once; repeats are idempotent", function()
		local session, revision = countdown()
		local after = session.countdownEndsAt :: number
		local _, first = TradeSession.confirm(session, A, revision, after)
		local _, second = TradeSession.confirm(session, B, revision, after)
		t.expect(first).toBe(false)
		t.expect(second).toBe(true)
		t.expect(session.status).toBe("Confirmed")
		local updateId = session.updateId
		local triggers = 0
		for _ = 1, 20 do
			local code, both = TradeSession.confirm(session, A, revision, after)
			assert(code == nil, "TradeSession setup must hold: code == nil")
			if both then
				triggers += 1
			end
		end
		t.expect(triggers).toBe(0)
		t.expect(session.updateId).toBe(updateId)
	end)

	t.test("unready during countdown cancels countdown but keeps the other side ready", function()
		local session, revision = countdown()
		local updateId = session.updateId
		t.expect((TradeSession.setReady(session, A, false, 0, 104))).toBe(nil)
		t.expect(session.status).toBe("Ready")
		t.expect(session.countdownEndsAt).toBe(nil)
		t.expect(session.target.ready).toBe(true)
		t.expect(session.revision).toBe(revision)
		t.expect(session.updateId).toBe(updateId + 1)
		local code, armed = TradeSession.setReady(session, A, true, revision, 105)
		t.expect(code).toBe(nil)
		t.expect(armed).toBe(true)
		t.expect(session.revision).toBe(revision + 1)
	end)

	t.test("cancel works before commit but not while Confirmed; finish is single terminal", function()
		local session, revision = countdown()
		local after = session.countdownEndsAt :: number
		TradeSession.confirm(session, A, revision, after)
		TradeSession.confirm(session, B, revision, after)
		t.expect(TradeSession.cancel(session, "PLAYER_LEFT")).toBe(false)
		t.expect(TradeSession.tick(session, session.expiresAt + 1)).toBe(false)
		t.expect(TradeSession.finish(session, nil)).toBe(true)
		t.expect(session.status).toBe("Done")
		t.expect(TradeSession.finish(session, "LATE")).toBe(false)
		t.expect(TradeSession.cancel(session, "LATE")).toBe(false)
		t.expect(session.status).toBe("Done")
	end)

	t.test("failed commit finishes Cancelled with the failure code", function()
		local session, revision = countdown()
		local after = session.countdownEndsAt :: number
		TradeSession.confirm(session, A, revision, after)
		TradeSession.confirm(session, B, revision, after)
		t.expect(TradeSession.finish(session, "NOT_ENOUGH_GOLD")).toBe(true)
		t.expect(session.status).toBe("Cancelled")
		t.expect(session.reason).toBe("NOT_ENOUGH_GOLD")
	end)

	t.test("expiry cancels open sessions and clears approvals", function()
		local session, _ = countdown()
		t.expect(TradeSession.tick(session, session.expiresAt - 1)).toBe(false)
		t.expect(TradeSession.tick(session, session.expiresAt)).toBe(true)
		t.expect(session.status).toBe("Cancelled")
		t.expect(session.reason).toBe("EXPIRED")
		t.expect(session.initiator.ready).toBe(false)
		t.expect((TradeSession.confirm(session, A, session.revision, session.expiresAt))).toBe("TRADE_CLOSED")
	end)

	t.test("updateId is strictly monotonic across every mutation", function()
		local session = TradeSession.new("s1", A, B, 100)
		local last = session.updateId
		local function step(): ()
			t.expect(session.updateId > last).toBe(true)
			last = session.updateId
		end
		TradeSession.respond(session, B, true, 101)
		step()
		TradeSession.setItems(session, A, { unit("a1") }, {})
		step()
		TradeSession.setReady(session, A, true, session.revision, 102)
		step()
		TradeSession.setReady(session, B, true, session.revision, 102)
		step()
		TradeSession.confirm(session, A, session.revision, 200)
		step()
		TradeSession.confirm(session, B, session.revision, 200)
		step()
		TradeSession.finish(session, nil)
		step()
	end)
end
