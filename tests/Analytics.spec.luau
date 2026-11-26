--!strict
-- Test analytics: bentuk event ekonomi (arah, nilai absolut, saldo akhir berurutan), sanitasi SKU/field,
-- anggaran request, kegagalan backend terisolasi + warning berjeda, langkah onboarding tanpa langkah palsu,
-- dan bucket sesi.
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Core = require(Server.Services.AnalyticsService.Core)
local Derive = require(Server.Services.AnalyticsService.Derive)
local Progress = require(Server.Services.DataService.Progress)
local Template = require(Server.Services.DataService.Template)
local Shared = game:GetService("ReplicatedStorage").Shared
local Analytics = require(Shared.Config.Analytics)

local function harness(players: number?)
	local calls: { any } = {}
	local warnings: { string } = {}
	local clock = { value = 0 }
	local mode = { fail = false }
	local function record(kind: string, ...: any)
		if mode.fail then
			error("service unavailable")
		end
		table.insert(calls, table.pack(kind, ...))
	end
	local core = Core.create({
		backend = {
			economy = function(...)
				record("economy", ...)
			end,
			onboarding = function(...)
				record("onboarding", ...)
			end,
			custom = function(...)
				record("custom", ...)
			end,
		},
		clock = function(): number
			return clock.value
		end,
		playerCount = function(): number
			return players or 1
		end,
		warn = function(message: string)
			table.insert(warnings, message)
		end,
	})
	return { core = core, calls = calls, warnings = warnings, clock = clock, mode = mode }
end

return function(ctx: TestRunner.TestContext)
	local test, expect = ctx.test, ctx.expect
	local player = { UserId = 1 } :: any

	test("economy events use flow direction, absolute amount and mapped transaction type", function()
		local h = harness()
		expect(h.core.economy(player, "Gems", -50, 450, "summon")).toBe(true)
		expect(h.core.economy(player, "Gems", 300, 750, "robux_purchase")).toBe(true)
		expect(h.core.economy(player, "Gold", 10, 10, "bad label!")).toBe(true)
		expect(h.core.economy(player, "Gold", 0, 10, "stage_reward")).toBe(false)
		expect(h.core.economy(player, "Gold", 0 / 0, 10, "stage_reward")).toBe(false)
		local sink, source, odd = h.calls[1], h.calls[2], h.calls[3]
		expect(sink[3]).toBe(false) -- Sink
		expect(sink[5]).toBe(50)
		expect(sink[6]).toBe(450)
		expect(sink[7]).toBe("Shop")
		expect(sink[8]).toBe("summon")
		expect(source[3]).toBe(true)
		expect(source[7]).toBe("IAP")
		expect(odd[7]).toBe(Analytics.defaultTransactionType)
		expect(odd[8]).toBe("other")
	end)

	test("ending balances follow the committed delta order", function()
		local events = Derive.economyEvents({ Gems = 100, Gold = 5 }, {
			{ kind = "Gems", amount = -50, source = "summon" },
			{ kind = "Gold", amount = 20, source = "quest_reward" },
			{ kind = "Gems", amount = 40, source = "quest_reward" },
		})
		expect(#events).toBe(3)
		expect(events[1].endingBalance).toBe(50)
		expect(events[2].endingBalance).toBe(25)
		expect(events[3].endingBalance).toBe(90)
	end)

	test("custom fields are capped at three sanitized server labels", function()
		local h = harness()
		expect(h.core.custom(player, "Summon", 10, { "standard", "Gems", "Mythic", "extra" })).toBe(true)
		expect(h.core.custom(player, "Summon", 1, { "<script>" })).toBe(true)
		expect(h.core.custom(player, "Summon", math.huge, nil)).toBe(false)
		expect(#h.calls[1][5]).toBe(3)
		expect(h.calls[2][5][1]).toBe("other")
		expect(h.core.onboarding(player, 99)).toBe(false)
		expect(h.core.onboarding(player, 1)).toBe(true)
		expect(h.calls[3][4]).toBe("ProfileCreated")
	end)

	test("request budget drops events beyond the per-minute window", function()
		local h = harness(0)
		for _ = 1, Analytics.budgetBase + 5 do
			h.core.custom(player, "Summon", 1, nil)
		end
		expect(#h.calls).toBe(Analytics.budgetBase)
		expect(h.core.stats().dropped).toBe(5)
		h.clock.value = Analytics.budgetWindowSeconds
		expect(h.core.custom(player, "Summon", 1, nil)).toBe(true)
	end)

	test("backend failures never throw and warnings are throttled", function()
		local h = harness()
		h.mode.fail = true
		for _ = 1, 5 do
			expect(h.core.economy(player, "Gems", 5, 5, "quest_reward")).toBe(false)
		end
		expect(h.core.stats().failed).toBe(5)
		expect(#h.warnings).toBe(1)
		h.clock.value = Analytics.failureWarnSeconds
		h.core.economy(player, "Gems", 5, 5, "quest_reward")
		expect(#h.warnings).toBe(2)
		h.mode.fail = false
		expect(h.core.economy(player, "Gems", 5, 10, "quest_reward")).toBe(true)
	end)

	test("onboarding steps come only from transitions after reconcile", function()
		local fresh: any = Template.create(0)
		Progress.reconcile(fresh)
		local before = Derive.onboardingState(fresh)
		local after: any = table.clone(fresh)
		after.progress = table.clone(fresh.progress)
		after.progress.tutorialBattleCleared = true
		expect(Derive.onboardingSteps(before, Derive.onboardingState(after))).toEqual({ 2 })
		-- Profil lama yang sudah selesai: reconcile menandai tutorial, jadi commit berikutnya tidak memicu langkah.
		local legacy: any = Template.create(0)
		legacy.flags.tutorialDone = true
		legacy.story.cleared["1-1"] = 3
		legacy.stats.summons = 4
		Progress.reconcile(legacy)
		local state = Derive.onboardingState(legacy)
		expect(#Derive.onboardingSteps(state, state)).toBe(0)
		local all = Derive.onboardingSteps(before, state)
		expect(all).toEqual({ 2, 3, 4, 5 })
	end)

	test("session buckets and best rarity", function()
		expect(Derive.sessionBucket(0)).toBe("lt5m")
		expect(Derive.sessionBucket(300)).toBe("5to15m")
		expect(Derive.sessionBucket(100000)).toBe("30mPlus")
		expect(Derive.bestRarity({ "Rare", "Mythic", "Epic" })).toBe("Mythic")
		expect(Derive.bestRarity({})).toBe("none")
	end)
end
