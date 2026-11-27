--!strict
-- Durabilitas trade dengan mock saja (tanpa DataStore/ProfileStore asli): commit normal, kegagalan log,
-- keputusan ambigu, presave tidak tahan lama, peserta keluar saat commit, pemulihan roll-forward/abort,
-- idempotensi pemulihan & log harian, guard kunci, dan indeks dupe.
local Server = game:GetService("ServerScriptService").Server
local Shared = game:GetService("ReplicatedStorage").Shared
local TestRunner = require(Server.Dev.TestRunner)
local DataModules = Server.Services.DataService
local Template = require(DataModules.Template)
local TradeJournal = require(DataModules.TradeJournal)
local TradeLog = require(DataModules.TradeLog)
local TradeRules = require(DataModules.TradeRules)
local Trades = require(DataModules.Trades)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local Trade = require(Shared.Config.Trade)

local NOW = 400 * 86400

local function newStore(): any
	local store: any = { data = {}, fail = {}, failAfterWrite = {}, down = false }
	function store.UpdateAsync(self: any, key: string, transform: (any, any) -> any): any
		if self.down then
			error("503 (mock)")
		end
		if (self.fail[key] or 0) > 0 then
			self.fail[key] -= 1
			error("throttled (mock)")
		end
		local value = transform(TableUtil.deepCopy(self.data[key]), nil)
		if value ~= nil then
			self.data[key] = TableUtil.deepCopy(value)
		end
		if (self.failAfterWrite[key] or 0) > 0 then
			self.failAfterWrite[key] -= 1
			error("timeout after write (mock)")
		end
		return value
	end
	function store.GetAsync(self: any, key: string): any
		if self.down then
			error("503 (mock)")
		end
		return TableUtil.deepCopy(self.data[key])
	end
	return store
end

local function newProfile(): any
	local profile: any = Template.create(0)
	profile.accountLevel = Trade.minAccountLevel
	profile.currencies.Gold = 2000
	TradeRules.reconcile(profile)
	return profile
end

local function addUnit(profile: any, uid: string, unitId: string): ()
	profile.units[uid] = {
		uid = uid,
		unitId = unitId,
		stars = 1,
		level = 1,
		xp = 0,
		locked = false,
		obtainedAt = 0,
		source = "summon",
	}
end

local function newSession(data: any): any
	local session: any = { Data = data, LastSavedData = TableUtil.deepCopy(data), active = true, saveOk = true }
	function session.IsActive(self: any): boolean
		return self.active
	end
	function session.Save(self: any): ()
		if self.saveOk then
			self.LastSavedData = TableUtil.deepCopy(self.Data)
		end
	end
	return session
end

local function world()
	local w: any = { sessions = {}, queue = {}, durable = true, store = newStore(), nextId = 0 }
	w.playerA = { UserId = 1, Name = "A" }
	w.playerB = { UserId = 2, Name = "B" }
	local function getSession(player: any): any
		local session = w.sessions[player]
		return if session and session.active then session else nil
	end
	w.getSession = getSession
	w.ledger = Trades.create(getSession, Signal.new(), function()
		return NOW
	end)
	w.log = TradeLog.create(w.store, { sleep = function() end, log = function() end })
	w.journal = TradeJournal.create({
		ledger = w.ledger,
		log = w.log,
		getSession = getSession,
		isDurable = function()
			return w.durable
		end,
		waitForSave = function() end,
		sleep = function() end,
		spawn = function(fn: () -> ())
			table.insert(w.queue, fn)
		end,
		newId = function(): string
			w.nextId += 1
			return `trade-{w.nextId}`
		end,
		report = function() end,
	})
	local a, b = newProfile(), newProfile()
	addUnit(a, "ua", "kael")
	addUnit(b, "ub", "pip")
	w.sessions[w.playerA] = newSession(a)
	w.sessions[w.playerB] = newSession(b)
	function w.parties(): (any, any)
		return { player = w.playerA, userId = 1, accountAgeDays = 30, offer = { uids = { "ua" }, skins = {} } }, {
			player = w.playerB,
			userId = 2,
			accountAgeDays = 30,
			offer = { uids = { "ub" }, skins = {} },
		}
	end
	function w.lockBoth(): ()
		w.ledger.lock(
			w.playerA,
			{ uids = { "ua" }, skins = {}, gold = Trade.taxGold, incomingUnits = 1, incomingSkins = {} }
		)
		w.ledger.lock(
			w.playerB,
			{ uids = { "ub" }, skins = {}, gold = Trade.taxGold, incomingUnits = 1, incomingSkins = {} }
		)
	end
	function w.drain(limit: number?): ()
		for _ = 1, limit or 20 do
			local fn = table.remove(w.queue, 1)
			if not fn then
				return
			end
			fn()
		end
	end
	function w.dataOf(player: any): any
		return w.sessions[player].Data
	end
	return w
end

return function(t: TestRunner.TestContext): ()
	t.test("normal commit swaps both, journals, finishes and releases locks", function()
		local w = world()
		w.lockBoth()
		local code, record = w.journal.commit(w.parties())
		t.expect(code).toBe(nil)
		t.expect(w.dataOf(w.playerA).units.ub ~= nil).toBe(true)
		t.expect(w.dataOf(w.playerB).units.ua ~= nil).toBe(true)
		t.expect(w.dataOf(w.playerA).units.ua).toBe(nil)
		t.expect(w.store.data[`t/{record.tradeId}`].state).toBe("committed")
		t.expect(w.ledger.goldReserve(w.playerA)).toBe(0)
		t.expect(next(w.store.data["u/1"]) ~= nil).toBe(true)
		w.drain()
		t.expect(next(w.store.data["u/1"])).toBe(nil)
		t.expect(next(w.store.data["u/2"])).toBe(nil)
		local shard = w.store.data[`d/{record.day}/{TradeLog.shardOf(record.tradeId)}`]
		t.expect(shard.count).toBe(1)
	end)

	t.test("a second commit for the same offers fails without changes", function()
		local w = world()
		assert(w.journal.commit(w.parties()) == nil)
		w.drain()
		local before = TableUtil.deepCopy(w.dataOf(w.playerA))
		local code = w.journal.commit(w.parties())
		t.expect(code).toBe("UNIT_NOT_OWNED")
		t.expect(TableUtil.deepCopy(w.dataOf(w.playerA))).toEqual(before)
	end)

	t.test("log outage before decision aborts later without item changes", function()
		local w = world()
		w.lockBoth()
		w.store.down = true
		local before = TableUtil.deepCopy(w.dataOf(w.playerA))
		local code = w.journal.commit(w.parties())
		t.expect(code).toBe("TRADE_PENDING_RECOVERY")
		t.expect(w.ledger.goldReserve(w.playerA)).toBe(Trade.taxGold) -- kunci tetap
		w.store.down = false
		w.drain()
		t.expect(w.ledger.goldReserve(w.playerA)).toBe(0)
		t.expect(TableUtil.deepCopy(w.dataOf(w.playerA))).toEqual(before)
	end)

	t.test("addPending failure after retries aborts cleanly", function()
		local w = world()
		w.store.fail["u/2"] = Trade.log.retryAttempts
		local code = w.journal.commit(w.parties())
		t.expect(code).toBe("TRADE_LOG_UNAVAILABLE")
		t.expect(w.dataOf(w.playerA).units.ua ~= nil).toBe(true)
		t.expect(next(w.store.data["u/1"] or {})).toBe(nil)
	end)

	t.test("ambiguous decision write converges to committed on resolve", function()
		local w = world()
		w.lockBoth()
		w.store.failAfterWrite["t/trade-1"] = Trade.log.retryAttempts
		w.store.fail["t/trade-1"] = 0
		-- Setiap percobaan menulis lalu error: hasil tidak diketahui walau backend sudah tertulis.
		local code = w.journal.commit(w.parties())
		t.expect(code).toBe("TRADE_PENDING_RECOVERY")
		t.expect(w.dataOf(w.playerA).units.ua ~= nil).toBe(true)
		w.drain()
		t.expect(w.dataOf(w.playerA).units.ub ~= nil).toBe(true)
		t.expect(w.dataOf(w.playerB).units.ua ~= nil).toBe(true)
		t.expect(w.ledger.goldReserve(w.playerB)).toBe(0)
	end)

	t.test("non-durable presave aborts with tombstone and no changes", function()
		local w = world()
		w.durable = false
		local code = w.journal.commit(w.parties())
		t.expect(code).toBe("TRADE_NOT_DURABLE")
		t.expect(w.store.data["t/trade-1"].state).toBe("aborted")
		t.expect(next(w.store.data["u/1"])).toBe(nil)
		t.expect(w.dataOf(w.playerB).units.ub ~= nil).toBe(true)
	end)

	t.test("participant leaving during the decision is rolled forward on next load", function()
		local w = world()
		local sessionB = w.sessions[w.playerB]
		local savedB = TableUtil.deepCopy(sessionB.Data)
		local original = w.store.UpdateAsync
		w.store.UpdateAsync = function(self: any, key: string, transform: any): any
			if key == "t/trade-1" then
				sessionB.active = false -- B keluar; sesi berakhir dengan data pra-trade
			end
			return original(self, key, transform)
		end
		local code = w.journal.commit(w.parties())
		t.expect(code).toBe(nil)
		t.expect(w.dataOf(w.playerA).units.ub ~= nil).toBe(true)
		t.expect(sessionB.Data.units.ua).toBe(nil)
		w.drain()
		t.expect(w.store.data["u/2"]["trade-1"] ~= nil).toBe(true)
		-- B masuk lagi: pemulihan menerapkan sisi B sekali.
		local reloaded = newSession(savedB)
		local ok, toFinish = w.journal.recover(2, reloaded)
		t.expect(ok).toBe(true)
		t.expect(#toFinish).toBe(1)
		t.expect(reloaded.Data.units.ua ~= nil).toBe(true)
		t.expect(reloaded.Data.units.ub).toBe(nil)
		t.expect(reloaded.Data.currencies.Gold).toBe(2000 - Trade.taxGold)
		-- Pemulihan berulang (mis. finish gagal) tidak menerapkan dua kali.
		local again, list = w.journal.recover(2, reloaded)
		t.expect(again).toBe(true)
		t.expect(#list).toBe(1)
		t.expect(reloaded.Data.currencies.Gold).toBe(2000 - Trade.taxGold)
		w.playerB = { UserId = 2, Name = "B2" }
		w.sessions[w.playerB] = reloaded
		t.expect(w.journal.finish(w.playerB, toFinish[1])).toBe(true)
		t.expect(next(w.store.data["u/2"])).toBe(nil)
	end)

	t.test("recovery aborts pending entries without a decision", function()
		local w = world()
		w.store.data["u/2"] = { ["trade-9"] = NOW }
		local session = newSession(newProfile())
		local ok, toFinish = w.journal.recover(2, session)
		t.expect(ok).toBe(true)
		t.expect(#toFinish).toBe(0)
		t.expect(w.store.data["t/trade-9"].state).toBe("aborted")
		t.expect(next(w.store.data["u/2"])).toBe(nil)
	end)

	t.test("recovery fails closed when the index cannot be read", function()
		local w = world()
		w.store.down = true
		local ok = w.journal.recover(2, newSession(newProfile()))
		t.expect(ok).toBe(false)
	end)

	t.test("daily append is idempotent and bounded", function()
		local w = world()
		local record: any = TradeRules.buildRecord(
			"trade-x",
			NOW,
			{ userId = 1, units = {}, skins = {} },
			{ userId = 2, units = {}, skins = {} }
		)
		t.expect(w.log.appendDaily(record)).toBe(nil)
		t.expect(w.log.appendDaily(record)).toBe(nil)
		local key = `d/{record.day}/{TradeLog.shardOf("trade-x")}`
		t.expect(w.store.data[key].count).toBe(1)
		w.store.data[key].count = Trade.log.maxEntriesPerShard
		record.tradeId = "trade-y"
		w.store.data[`d/{record.day}/{TradeLog.shardOf("trade-y")}`] = w.store.data[key]
		t.expect(w.log.appendDaily(record)).toBe("LOG_SHARD_FULL")
	end)

	t.test("pending index is bounded per user", function()
		local w = world()
		for index = 1, Trade.log.maxPendingPerUser do
			t.expect(w.log.addPending(1, `p{index}`, NOW)).toBe(nil)
		end
		t.expect(w.log.addPending(1, "p1", NOW)).toBe(nil)
		t.expect(w.log.addPending(1, "overflow", NOW)).toBe("TRADE_RECOVERY_PENDING")
	end)

	t.test("guard blocks changes to locked items, reserved gold and reserved capacity", function()
		local w = world()
		w.lockBoth()
		local original = w.dataOf(w.playerA)
		local draft = TableUtil.deepCopy(original)
		t.expect(w.ledger.guard(w.playerA, original, draft)).toBe(nil)
		draft.units.ua.level = 2
		t.expect(w.ledger.guard(w.playerA, original, draft)).toBe("ITEM_IN_TRADE")
		draft = TableUtil.deepCopy(original)
		draft.currencies.Gold = Trade.taxGold - 1
		t.expect(w.ledger.guard(w.playerA, original, draft)).toBe("GOLD_RESERVED_FOR_TRADE")
		t.expect(w.ledger.guard(w.playerB, w.dataOf(w.playerB), w.dataOf(w.playerB))).toBe(nil)
		local skin = "skin_academy_scholar"
		w.ledger.lock(w.playerB, { uids = {}, skins = {}, gold = 0, incomingUnits = 0, incomingSkins = { skin } })
		local draftB = TableUtil.deepCopy(w.dataOf(w.playerB))
		draftB.skinsOwned[skin] = true
		t.expect(w.ledger.guard(w.playerB, w.dataOf(w.playerB), draftB)).toBe("ITEM_IN_TRADE")
		w.ledger.unlock(w.playerA)
		draft.units.ua = nil
		t.expect(w.ledger.guard(w.playerA, original, draft)).toBe(nil)
	end)

	t.test("dupe index flags a UID held by another active session and follows transfers", function()
		local w = world()
		t.expect(#w.ledger.indexProfile(w.playerA, w.dataOf(w.playerA))).toBe(0)
		t.expect(#w.ledger.indexProfile(w.playerB, w.dataOf(w.playerB))).toBe(0)
		assert(w.journal.commit(w.parties()) == nil)
		local intruder = { UserId = 3, Name = "C" }
		local copy = newProfile()
		addUnit(copy, "ua", "kael") -- ua sekarang sah milik B
		w.sessions[intruder] = newSession(copy)
		local flags = w.ledger.indexProfile(intruder, copy)
		t.expect(#flags).toBe(1)
		t.expect(flags[1].otherUserId).toBe(2)
		t.expect(copy.units.ua ~= nil).toBe(true) -- tidak dihapus otomatis
	end)
end
