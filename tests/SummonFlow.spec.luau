--!strict
-- Test alur summon tanpa DataStore/PolicyService asli: validasi input, gerbang restricted, cache kebijakan,
-- commit atomik DataService (saldo, kapasitas, rollback), serta handler remote dengan sesi palsu.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local ComplianceService = require(Services.ComplianceService)
local Handlers = require(Services.SummonService.Handlers)
local Summons = require(Services.DataService.Summons)
local Template = require(Services.DataService.Template)
local Shared = ReplicatedStorage.Shared
local Banners = require(Shared.Config.Banners)
local Signal = require(Shared.Util.Signal)

local limited = Banners.definitions.limited_example
local LIMITED_START = limited.startsAt :: number

type FakeSession = { Data: any }

local function constant(value: number): any
	return {
		NextNumber = function(): number
			return value
		end,
	}
end

local function fakePlayer(userId: number): any
	return { UserId = userId, Name = `Tester{userId}` }
end

-- Dunia uji: sesi palsu + ledger DataService asli + handler asli.
local function world(options: { restricted: boolean?, now: number? }?)
	local sessions: { [any]: FakeSession } = {}
	local present: { [any]: boolean } = {}
	local uidCounter = 0
	local clock = { now = if options and options.now then options.now else LIMITED_START }
	local policy = { restricted = if options then options.restricted == true else false, calls = 0 }
	local ledger = Summons.create(
		function(player: Player): any
			return sessions[player]
		end,
		Signal.new(),
		{
			now = function(): number
				return clock.now
			end,
			newUid = function(): string
				uidCounter += 1
				return `summon-uid-{uidCounter}`
			end,
		}
	)
	local handlers = Handlers.create({
		ledger = ledger :: any,
		isRestricted = function(): boolean
			policy.calls += 1
			return policy.restricted
		end,
		isPresent = function(player: Player): boolean
			return present[player] == true
		end,
		now = function(): number
			return clock.now
		end,
		rng = constant(0),
	})
	local function join(userId: number): any
		local player = fakePlayer(userId)
		sessions[player] = { Data = Template.create(0) }
		present[player] = true
		return player
	end
	return {
		sessions = sessions,
		present = present,
		clock = clock,
		policy = policy,
		ledger = ledger,
		handlers = handlers,
		join = join,
	}
end

local function unitCount(profile: any): number
	local count = 0
	for _ in profile.units do
		count += 1
	end
	return count
end

return function(t: TestRunner.TestContext): ()
	t.test("rejects malformed Summon arguments before any lookup", function()
		local check = Handlers.validateSummonArgs
		t.expect(check(3, "standard", 10, "Gems")).toBe(nil)
		t.expect(check(3, "limited_example", 1, "Tickets")).toBe(nil)
		t.expect(check(2, "standard", 10, nil)).toBe("INVALID_ARGUMENTS")
		t.expect(check(4, "standard", 10, "Gems")).toBe("INVALID_ARGUMENTS")
		for _, bannerId in { nil, 1, "", "unknown", string.rep("a", 65), {} } :: { any } do
			t.expect(check(3, bannerId, 1, "Gems")).toBe("INVALID_BANNER")
		end
		for _, count in { 0, 2, 9, 11, 10.5, -1, 0 / 0, math.huge, "10", {} } :: { any } do
			t.expect(check(3, "standard", count, "Gems")).toBe("INVALID_COUNT")
		end
		for _, payWith in { "Robux", "gems", 1, true, {} } :: { any } do
			t.expect(check(3, "standard", 1, payWith)).toBe("INVALID_PAYMENT")
		end
	end)

	t.test("blocks Gems for restricted players and checks the banner period", function()
		local standard = Banners.definitions.standard
		t.expect(Handlers.checkGate(standard, "Gems", true, 0)).toBe("RESTRICTED_REGION")
		t.expect(Handlers.checkGate(standard, "Tickets", true, 0)).toBe(nil)
		t.expect(Handlers.checkGate(standard, "Gems", false, 0)).toBe(nil)
		t.expect(Handlers.checkGate(limited, "Tickets", false, LIMITED_START - 1)).toBe("BANNER_INACTIVE")
		t.expect(Handlers.checkGate(limited, "Tickets", false, limited.endsAt :: number)).toBe("BANNER_INACTIVE")
		t.expect(Handlers.checkGate(limited, "Gems", false, LIMITED_START)).toBe(nil)
	end)

	t.test("policy cache fails closed, caches per session and shares one fetch", function()
		local now = 0
		local fetches = 0
		local result: any = { ArePaidRandomItemsRestricted = false }
		local fail = false
		local suspend = false
		local present = true
		local logs = 0
		local cache = ComplianceService.createCache({
			fetch = function(): any
				fetches += 1
				if suspend then
					coroutine.yield()
				end
				if fail then
					error("policy unavailable")
				end
				return result
			end,
			isPresent = function(): boolean
				return present
			end,
			now = function(): number
				return now
			end,
			retrySeconds = 60,
			log = function()
				logs += 1
			end,
		})
		local player = fakePlayer(1)
		t.expect(cache.peek(player)).toBe(nil)
		t.expect(cache.isRestricted(player)).toBe(false)
		t.expect(cache.isRestricted(player)).toBe(false)
		t.expect(fetches).toBe(1)

		local failing = fakePlayer(2)
		fail = true
		t.expect(cache.isRestricted(failing)).toBe(true)
		t.expect(cache.isRestricted(failing)).toBe(true)
		t.expect(fetches).toBe(2)
		t.expect(logs).toBe(1)
		fail = false
		now = 60
		t.expect(cache.isRestricted(failing)).toBe(false)
		t.expect(fetches).toBe(3)

		for _, malformed in { {}, { ArePaidRandomItemsRestricted = "false" }, "x" } :: { any } do
			result = malformed
			t.expect(cache.isRestricted(fakePlayer(10 + fetches))).toBe(true)
		end
		result = { ArePaidRandomItemsRestricted = true }

		-- Dua permintaan bersamaan menunggu satu fetch.
		local shared = fakePlayer(3)
		suspend = true
		local before = fetches
		local first = coroutine.create(cache.isRestricted)
		local second = coroutine.create(cache.isRestricted)
		coroutine.resume(first, shared)
		coroutine.resume(second, shared)
		t.expect(fetches).toBe(before + 1)
		suspend = false
		local ok, value = coroutine.resume(first)
		t.expect(ok and value).toBe(true)
		t.expect(coroutine.status(second)).toBe("dead")
		t.expect(cache.peek(shared)).toBe(true)

		-- Pemain keluar di tengah fetch: hasil tidak di-cache.
		local leaving = fakePlayer(4)
		result = { ArePaidRandomItemsRestricted = false }
		suspend = true
		local pending = coroutine.create(cache.isRestricted)
		local waiting = coroutine.create(cache.isRestricted)
		coroutine.resume(pending, leaving)
		coroutine.resume(waiting, leaving)
		suspend = false
		present = false
		cache.clear(leaving)
		-- Penunggu dilepas saat clear dengan hasil fail-closed, tidak menunggu fetch selesai.
		t.expect(coroutine.status(waiting)).toBe("dead")
		local resumed, pendingValue = coroutine.resume(pending)
		t.expect(resumed and pendingValue).toBe(false)
		t.expect(cache.peek(leaving)).toBe(nil)
		present = true

		cache.setForced(player, true)
		t.expect(cache.isRestricted(player)).toBe(true)
		cache.setForced(player, false)
		t.expect(cache.isRestricted(player)).toBe(false)
		cache.clear(player)
		t.expect(cache.peek(player)).toBe(nil)
	end)

	t.test("commits spend, units, pity and stats together for the caller only", function()
		local w = world()
		local player, other = w.join(1), w.join(2)
		local profile = w.sessions[player].Data
		profile.currencies.SummonTickets = 10
		local before = unitCount(profile)
		local result = w.handlers.summon(player, "standard", 10, "Tickets")
		t.expect(result.ok).toBe(true)
		local data = w.sessions[player].Data
		t.expect(data ~= profile).toBe(true)
		t.expect(data.currencies.SummonTickets).toBe(0)
		t.expect(unitCount(data)).toBe(before + 10)
		t.expect(data.stats.summons).toBe(10)
		t.expect(data.pity.standard.sinceLegendary).toBe(10)
		t.expect(data.pity.standard.sinceMythic).toBe(10)
		t.expect(data.pity.standard.guaranteedFeatured).toBe(nil)
		t.expect(#result.data.rolls).toBe(10)
		t.expect(result.data.rolls[10].rarity).toBe("Epic")
		for _, roll in result.data.rolls do
			t.expect(data.units[roll.uid].source).toBe("summon")
			t.expect(data.units[roll.uid].unitId).toBe(roll.unitId)
		end
		t.expect(result.data.info.balances.SummonTickets).toBe(0)
		t.expect(result.data.info.capacity.used).toBe(before + 10)
		t.expect(result.data.info.banners[1].pity.sinceLegendary).toBe(10)
		t.expect(next(w.sessions[other].Data.pity)).toBe(nil)
		t.expect(unitCount(w.sessions[other].Data)).toBe(before)
	end)

	t.test("rejects insufficient balance or capacity for the whole batch without spending", function()
		local w = world()
		local player = w.join(1)
		local profile = w.sessions[player].Data
		profile.currencies.SummonTickets = 9
		t.expect(w.handlers.summon(player, "standard", 10, "Tickets").code).toBe("NOT_ENOUGH_TICKETS")
		t.expect(w.sessions[player].Data).toBe(profile)
		t.expect(w.handlers.getBannerInfo(player).ok).toBe(true)
		profile.currencies.Gems = 449
		t.expect(w.handlers.summon(player, "standard", 10, "Gems").code).toBe("NOT_ENOUGH_GEMS")
		t.expect(profile.currencies.Gems).toBe(449)
		profile.currencies.Gems = 450
		for index = 1, 500 - unitCount(profile) - 9 do
			profile.units[`filler-{index}`] = { uid = `filler-{index}`, unitId = "kael" }
		end
		t.expect(w.handlers.summon(player, "standard", 10, "Gems").code).toBe("INVENTORY_FULL")
		t.expect(w.sessions[player].Data).toBe(profile)
		t.expect(profile.currencies.Gems).toBe(450)
		t.expect(w.handlers.summon(player, "standard", 1, "Gems").ok).toBe(true)
		t.expect(w.sessions[player].Data.currencies.Gems).toBe(400)
	end)

	t.test("rolls back when the roll fails, yields, returns bad data or the session ends", function()
		local w = world()
		local player = w.join(1)
		local profile = w.sessions[player].Data
		profile.currencies.Gems = 1000
		local function request(rollBatch: any): any
			return {
				bannerId = "standard",
				count = 1,
				currency = "Gems",
				price = 50,
				maxUnits = 500,
				precheck = function(): string?
					return nil
				end,
				rollBatch = rollBatch,
			}
		end
		local fresh = { sinceLegendary = 1, sinceMythic = 1, guaranteedFeatured = false }
		local cases: { any } = {
			function()
				error("roll failed")
			end,
			function()
				coroutine.yield()
				return { { unitId = "kael", rarity = "Rare" } }, fresh
			end,
			function()
				return { { unitId = "kael", rarity = "Mythic" } }, fresh
			end,
			function()
				return {}, fresh
			end,
			function()
				return { { unitId = "kael", rarity = "Rare" } }, { sinceLegendary = -1 }
			end,
		}
		for _, rollBatch in cases do
			t.expect(w.ledger.apply(player, request(rollBatch))).toBe("INTERNAL_ERROR")
			t.expect(w.sessions[player].Data).toBe(profile)
		end
		t.expect(profile.currencies.Gems).toBe(1000)
		local rejected = request(function() end)
		rejected.precheck = function(): string?
			return "ODDS_CHANGED"
		end
		t.expect(w.ledger.apply(player, rejected)).toBe("ODDS_CHANGED")
		local ending = request(function()
			w.sessions[player] = nil
			return { { unitId = "kael", rarity = "Rare" } }, fresh
		end)
		t.expect(w.ledger.apply(player, ending)).toBe("DATA_NOT_READY")
		t.expect(profile.currencies.Gems).toBe(1000)
		t.expect(w.handlers.summon(player, "standard", 1, "Tickets").code).toBe("DATA_NOT_READY")
	end)

	t.test("binds Gems summons to the last issued odds quote", function()
		local w = world()
		local player = w.join(1)
		local profile = w.sessions[player].Data
		profile.currencies.Gems = 1000
		t.expect(w.handlers.summon(player, "standard", 1, "Gems").code).toBe("ODDS_CHANGED")
		t.expect(profile.currencies.Gems).toBe(1000)
		local info = w.handlers.getBannerInfo(player)
		t.expect(info.ok).toBe(true)
		t.expect(info.data.restricted).toBe(false)
		t.expect(#info.data.banners).toBe(2)
		t.expect(info.data.banners[1].id).toBe("standard")
		t.expect(#info.data.banners[2].odds.ten).toBe(10)
		-- State pity berubah setelah quote diterbitkan → quote basi, tanpa spend.
		profile.pity.standard = { sinceLegendary = 5, sinceMythic = 5 }
		t.expect(w.handlers.summon(player, "standard", 1, "Gems").code).toBe("ODDS_CHANGED")
		t.expect(profile.currencies.Gems).toBe(1000)
		w.handlers.getBannerInfo(player)
		local result = w.handlers.summon(player, "standard", 1, "Gems")
		t.expect(result.ok).toBe(true)
		t.expect(w.sessions[player].Data.pity.standard.sinceLegendary).toBe(6)
		-- Respons sukses menerbitkan quote baru sehingga summon berikutnya sah.
		t.expect(w.handlers.summon(player, "standard", 1, "Gems").ok).toBe(true)
		t.expect(w.sessions[player].Data.currencies.Gems).toBe(900)
		w.handlers.clear(player)
		t.expect(w.handlers.summon(player, "standard", 1, "Gems").code).toBe("ODDS_CHANGED")
		t.expect(w.handlers.getBannerInfo(player, "extra").code).toBe("INVALID_ARGUMENTS")
	end)

	t.test("restricted players keep Tickets but never spend Gems", function()
		local w = world({ restricted = true })
		local player = w.join(1)
		local profile = w.sessions[player].Data
		profile.currencies.Gems = 1000
		profile.currencies.SummonTickets = 1
		local info = w.handlers.getBannerInfo(player)
		t.expect(info.data.restricted).toBe(true)
		t.expect(w.handlers.summon(player, "standard", 1, "Gems").code).toBe("RESTRICTED_REGION")
		t.expect(w.sessions[player].Data.currencies.Gems).toBe(1000)
		local result = w.handlers.summon(player, "limited_example", 1, "Tickets")
		t.expect(result.ok).toBe(true)
		t.expect(result.data.info.restricted).toBe(true)
		t.expect(w.sessions[player].Data.currencies.Gems).toBe(1000)
		t.expect(w.sessions[player].Data.currencies.SummonTickets).toBe(0)
	end)

	t.test("rejects inactive banners and players who left during the policy lookup", function()
		local w = world({ now = LIMITED_START - 1 })
		local player = w.join(1)
		w.sessions[player].Data.currencies.SummonTickets = 10
		t.expect(w.handlers.summon(player, "limited_example", 1, "Tickets").code).toBe("BANNER_INACTIVE")
		local info = w.handlers.getBannerInfo(player).data
		t.expect(info.banners[1].active).toBe(true)
		t.expect(info.banners[2].active).toBe(false)
		w.clock.now = limited.endsAt :: number
		t.expect(w.handlers.summon(player, "limited_example", 1, "Tickets").code).toBe("BANNER_INACTIVE")
		t.expect(w.handlers.summon(player, "standard", 1, "Tickets").ok).toBe(true)
		w.present[player] = false
		t.expect(w.handlers.summon(player, "standard", 1, "Tickets").code).toBe("DATA_NOT_READY")
		t.expect(w.handlers.getBannerInfo(player).code).toBe("DATA_NOT_READY")
		t.expect(w.sessions[player].Data.currencies.SummonTickets).toBe(9)
		t.expect(w.handlers.getBannerInfo(fakePlayer(99)).code).toBe("DATA_NOT_READY")
	end)
end
