--!strict
-- Test ProcessReceipt: duplikat, profil hilang, save gagal/retry, bonus per SKU, robuxSpent aktual,
-- validasi field receipt, fallback mock, dan premium terikat musim. Sesi ProfileStore palsu +
-- ledger DataService/Purchases asli + logika Receipts asli (tanpa MarketplaceService).
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local Purchases = require(Services.DataService.Purchases)
local Template = require(Services.DataService.Template)
local Receipts = require(Services.MonetizationService.Receipts)
local Shared = game:GetService("ReplicatedStorage").Shared
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)

local GEMS_S, GEMS_M, SHARDS, PREMIUM = 101, 102, 103, 104
local definitions: any = {
	gems_s = { id = GEMS_S, kind = "DeveloperProduct", grant = { currency = "Gems", amount = 300 } },
	gems_m = { id = GEMS_M, kind = "DeveloperProduct", grant = { currency = "Gems", amount = 1300 } },
	shards_s = { id = SHARDS, kind = "DeveloperProduct", grant = { currency = "TraitShards", amount = 30 } },
	pass_premium = { id = PREMIUM, kind = "DeveloperProduct", battlePassSeasonId = "s1" },
	gp_speed2x = { id = 201, kind = "GamePass" },
	skin_example = { id = 0, kind = "DeveloperProduct" },
}

local function newSession(data: any, saveMode: { value: string })
	local session: any = {
		Data = data,
		LastSavedData = TableUtil.deepCopy(data),
		OnAfterSave = Signal.new(),
		OnSessionEnd = Signal.new(),
		active = true,
		saves = 0,
	}
	function session.IsActive(self: any): boolean
		return self.active
	end
	function session.Save(self: any): ()
		self.saves += 1
		if saveMode.value == "ok" then
			self.LastSavedData = TableUtil.deepCopy(self.Data)
			self.OnAfterSave:Fire(self.LastSavedData)
		end
	end
	return session
end

local function world()
	local sessions: { [any]: any } = {}
	local present: { [any]: boolean } = {}
	local players: { [number]: any } = {}
	local saveMode = { value = "ok" }
	local durable = { value = true }
	local clock = { value = 0, sleeps = 0 }
	local granted: { string } = {}
	local ledger = Purchases.create(
		function(player: Player): any
			local session = sessions[player]
			return if session and session.active then session else nil
		end,
		Signal.new(),
		{
			isDurable = function(): boolean
				return durable.value
			end,
			waitForSave = function() end,
			sleep = function()
				clock.sleeps += 1
			end,
		}
	)
	local receipts = Receipts.create({
		ledger = ledger,
		findPlayer = function(userId: number): Player?
			return players[userId]
		end,
		isPresent = function(player: Player): boolean
			return present[player] == true
		end,
		hasProfile = function(player: Player): boolean
			return sessions[player] ~= nil and sessions[player].active
		end,
		isRobux = function(currencyType: any): boolean
			return currencyType == "Robux"
		end,
		sleep = function(seconds: number)
			clock.value += seconds
		end,
		clock = function(): number
			return clock.value
		end,
		log = function() end,
		onGranted = function(_: Player, key: string)
			table.insert(granted, key)
		end,
	}, definitions)
	local function join(userId: number, data: any?): any
		local player = { UserId = userId, Name = `P{userId}` }
		players[userId] = player
		present[player] = true
		sessions[player] = newSession(data or Template.create(0), saveMode)
		return player
	end
	local function receipt(userId: number, purchaseId: string, productId: number, spent: number?): any
		return {
			PlayerId = userId,
			PurchaseId = purchaseId,
			ProductId = productId,
			CurrencySpent = spent or 100,
			CurrencyType = "Robux",
		}
	end
	return {
		sessions = sessions,
		present = present,
		players = players,
		saveMode = saveMode,
		durable = durable,
		clock = clock,
		granted = granted,
		process = receipts.process,
		join = join,
		receipt = receipt,
		data = function(player: any): any
			return sessions[player].Data
		end,
	}
end

return function(t: TestRunner.TestContext): ()
	t.test("same receipt twice grants once and both acknowledge after save", function()
		local w = world()
		local p = w.join(1)
		t.expect(w.process(w.receipt(1, "r1", GEMS_S, 100))).toBe("PurchaseGranted")
		t.expect(w.process(w.receipt(1, "r1", GEMS_S, 100))).toBe("PurchaseGranted")
		t.expect(w.data(p).currencies.Gems).toBe(600)
		t.expect(w.data(p).stats.robuxSpent).toBe(100)
		t.expect(w.data(p).processedReceipts.r1).toBe(true)
		t.expect(w.sessions[p].LastSavedData.processedReceipts.r1).toBe(true)
		t.expect(#w.granted).toBe(1)
	end)

	t.test("missing or absent profile returns NotProcessedYet without granting", function()
		local w = world()
		t.expect(w.process(w.receipt(9, "r1", GEMS_S))).toBe("NotProcessedYet")
		local p = w.join(2)
		w.sessions[p].active = false
		t.expect(w.process(w.receipt(2, "r2", GEMS_S))).toBe("NotProcessedYet")
		t.expect(w.clock.value >= 60).toBe(true)
		w.present[p] = false
		t.expect(w.process(w.receipt(2, "r3", GEMS_S))).toBe("NotProcessedYet")
		t.expect(w.data(p).currencies.Gems).toBe(0)
		t.expect(next(w.data(p).processedReceipts)).toBe(nil)
	end)

	t.test("save failure keeps receipt pending; retry acknowledges without granting again", function()
		local w = world()
		local p = w.join(3)
		w.saveMode.value = "fail"
		t.expect(w.process(w.receipt(3, "r1", GEMS_M, 400))).toBe("NotProcessedYet")
		t.expect(w.data(p).currencies.Gems).toBe(2600)
		t.expect(w.sessions[p].saves > 1).toBe(true)
		t.expect(w.clock.sleeps > 0).toBe(true)
		t.expect(w.process(w.receipt(3, "r1", GEMS_M, 400))).toBe("NotProcessedYet")
		t.expect(w.data(p).currencies.Gems).toBe(2600)
		w.saveMode.value = "ok"
		t.expect(w.process(w.receipt(3, "r1", GEMS_M, 400))).toBe("PurchaseGranted")
		t.expect(w.data(p).currencies.Gems).toBe(2600)
		t.expect(w.data(p).stats.robuxSpent).toBe(400)
		t.expect(#w.granted).toBe(1)
	end)

	t.test("rejoin with marker already saved acknowledges without granting", function()
		local w = world()
		local saved = Template.create(0)
		saved.processedReceipts.old = true
		saved.currencies.Gems = 600
		local p = w.join(4, saved)
		t.expect(w.process(w.receipt(4, "old", GEMS_S))).toBe("PurchaseGranted")
		t.expect(w.data(p).currencies.Gems).toBe(600)
		t.expect(w.sessions[p].saves).toBe(0)
	end)

	t.test("mock or closing DataStore never claims durability", function()
		local w = world()
		local p = w.join(5)
		w.durable.value = false
		t.expect(w.process(w.receipt(5, "r1", GEMS_S))).toBe("NotProcessedYet")
		w.durable.value = true
		t.expect(w.process(w.receipt(5, "r1", GEMS_S))).toBe("PurchaseGranted")
		t.expect(w.data(p).currencies.Gems).toBe(600)
	end)

	t.test("session ending during confirmation returns NotProcessedYet", function()
		local w = world()
		local p = w.join(6)
		w.saveMode.value = "fail"
		local session = w.sessions[p]
		session.Save = function(self: any)
			self.active = false
		end
		t.expect(w.process(w.receipt(6, "r1", GEMS_S))).toBe("NotProcessedYet")
		t.expect(w.data(p).processedReceipts.r1).toBe(true)
	end)

	t.test("first purchase bonus is once per Gems package; Shards have no bonus", function()
		local w = world()
		local p = w.join(7)
		t.expect(w.process(w.receipt(7, "a", GEMS_S))).toBe("PurchaseGranted")
		t.expect(w.process(w.receipt(7, "b", GEMS_S))).toBe("PurchaseGranted")
		t.expect(w.data(p).currencies.Gems).toBe(900)
		t.expect(w.process(w.receipt(7, "c", GEMS_M, 400))).toBe("PurchaseGranted")
		t.expect(w.data(p).currencies.Gems).toBe(900 + 2600)
		t.expect(w.process(w.receipt(7, "d", SHARDS, 200))).toBe("PurchaseGranted")
		t.expect(w.data(p).currencies.TraitShards).toBe(30)
		t.expect(w.data(p).purchases.firstBonus).toEqual({ gems_s = true, gems_m = true })
		t.expect(w.data(p).stats.robuxSpent).toBe(800)
	end)

	t.test("robuxSpent uses CurrencySpent from the receipt, non-Robux counts zero", function()
		local w = world()
		local p = w.join(8)
		t.expect(w.process(w.receipt(8, "a", GEMS_S, 75))).toBe("PurchaseGranted")
		local other = w.receipt(8, "b", GEMS_S, 999)
		other.CurrencyType = "Tix"
		t.expect(w.process(other)).toBe("PurchaseGranted")
		t.expect(w.data(p).stats.robuxSpent).toBe(75)
	end)

	t.test("invalid receipt fields and unknown SKUs are left unprocessed", function()
		local w = world()
		local p = w.join(10)
		local cases: { any } = {
			w.receipt(10, "x", 999),
			w.receipt(10, "x", 0),
			w.receipt(10, "x", 201),
			w.receipt(10, "", GEMS_S),
			w.receipt(10, string.rep("a", 200), GEMS_S),
			w.receipt(10, "x", GEMS_S, -1),
			w.receipt(10, "x", GEMS_S, 0 / 0),
			w.receipt(10, "x", 0 / 0),
			w.receipt(11, "x", GEMS_S),
			"not a table",
		}
		local mismatched = w.receipt(10, "x", GEMS_S)
		mismatched.PlayerId = 10.5
		table.insert(cases, mismatched)
		local missingSpent = w.receipt(10, "x", GEMS_S)
		missingSpent.CurrencySpent = nil
		table.insert(cases, missingSpent)
		for _, info in cases do
			t.expect(w.process(info)).toBe("NotProcessedYet")
		end
		local impostor = { UserId = 99 }
		w.players[12] = impostor :: any
		w.present[impostor] = true
		t.expect(w.process(w.receipt(12, "x", GEMS_S))).toBe("NotProcessedYet")
		t.expect(w.data(p).currencies.Gems).toBe(0)
		t.expect(next(w.data(p).processedReceipts)).toBe(nil)
	end)

	t.test("premium receipt is bound to the product season and never double-counts", function()
		local w = world()
		local p = w.join(13)
		t.expect(w.process(w.receipt(13, "p1", PREMIUM, 800))).toBe("PurchaseGranted")
		t.expect(w.data(p).battlePass.seasons.s1.premium).toBe(true)
		t.expect(w.process(w.receipt(13, "p2", PREMIUM, 800))).toBe("PurchaseGranted")
		t.expect(w.data(p).battlePass.seasons.s1.premium).toBe(true)
		t.expect(w.data(p).stats.robuxSpent).toBe(1600)
		t.expect(w.data(p).currencies.Gems).toBe(0)
	end)

	t.test("old profiles without additive fields still process receipts", function()
		local w = world()
		local legacy: any = Template.create(0)
		legacy.purchases = nil
		legacy.battlePass = nil
		legacy.stats.robuxSpent = nil
		local p = w.join(14, legacy)
		t.expect(w.process(w.receipt(14, "r", GEMS_S, 100))).toBe("PurchaseGranted")
		t.expect(w.data(p).currencies.Gems).toBe(600)
		t.expect(w.data(p).stats.robuxSpent).toBe(100)
	end)
end
