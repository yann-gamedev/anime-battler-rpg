--!strict
-- Test toko: GetShopInfo, PrepareShopPurchase, BuyAcademyItem. Restricted tetap bisa belanja Toko Akademi
-- (harga Gems tetap), paket Shards disembunyikan untuk restricted, produk ID 0 tidak bisa disiapkan,
-- gamepass/premium yang dimiliki ditolak, dan pembelian Akademi atomik sekali per item.
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local Purchases = require(Services.DataService.Purchases)
local Template = require(Services.DataService.Template)
local Shop = require(Services.MonetizationService.Shop)
local Shared = game:GetService("ReplicatedStorage").Shared
local Products = require(Shared.Config.Products)
local Signal = require(Shared.Util.Signal)

local definitions: any = {
	gems_s = { id = 11, kind = "DeveloperProduct", name = "300 Gems", grant = { currency = "Gems", amount = 300 } },
	gems_m = { id = 0, kind = "DeveloperProduct", grant = { currency = "Gems", amount = 1300 } },
	shards_s = { id = 12, kind = "DeveloperProduct", grant = { currency = "TraitShards", amount = 30 } },
	pass_premium = { id = 13, kind = "DeveloperProduct", battlePassSeasonId = "s1" },
	gp_speed2x = { id = 14, kind = "GamePass" },
	gp_autoreplay = { id = 0, kind = "GamePass" },
}

local function costOf(id: string): number
	for _, item in Products.academy do
		if item.id == id then
			return item.costGems
		end
	end
	error("missing item " .. id)
end

local function world()
	local sessions: { [any]: any } = {}
	local state = { restricted = false, season = "s1" :: string?, passes = {} :: { [string]: boolean } }
	local nextUid = 0
	local ledger = Purchases.create(
		function(player: Player): any
			return sessions[player]
		end,
		Signal.new(),
		{
			isDurable = function(): boolean
				return true
			end,
			newUid = function(): string
				nextUid += 1
				return `shop-{nextUid}`
			end,
		}
	)
	local h = Shop.create({
		ledger = ledger,
		isRestricted = function(): boolean
			return state.restricted
		end,
		isPresent = function(player: Player): boolean
			return sessions[player] ~= nil
		end,
		hasPass = function(_: Player, key: string): boolean
			return state.passes[key] == true
		end,
		activeSeasonId = function(): string?
			return state.season
		end,
		definitions = definitions,
	})
	local function join(gems: number): any
		local player = { UserId = 1, Name = "P1" }
		local profile = Template.create(0)
		profile.currencies.Gems = gems
		sessions[player] = { Data = profile }
		return player
	end
	return { sessions = sessions, state = state, h = h, join = join }
end

local function product(info: any, key: string): any?
	for _, entry in info.products do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

return function(t: TestRunner.TestContext): ()
	t.test("shop info lists products, first bonus flag, and academy prices from config", function()
		local w = world()
		local p = w.join(0)
		local r = w.h.GetShopInfo(p)
		t.expect(r.ok).toBe(true)
		local gems = product(r.data, "gems_s")
		t.expect(gems.available).toBe(true)
		t.expect(gems.firstBonus).toBe(true)
		t.expect(gems.grant.amount).toBe(300)
		t.expect(product(r.data, "gems_m").available).toBe(false)
		t.expect(product(r.data, "pass_premium").firstBonus).toBe(nil)
		t.expect(#r.data.academy).toBe(#Products.academy)
		t.expect(r.data.academy[1].costGems).toBe(Products.academy[1].costGems)
		t.expect(w.h.GetShopInfo(p, 1).code).toBe("INVALID_ARGUMENTS")
	end)

	t.test("prepare returns only positive, available, eligible products and never grants", function()
		local w = world()
		local p = w.join(0)
		local r = w.h.PrepareShopPurchase(p, "gems_s")
		t.expect(r.ok).toBe(true)
		t.expect(r.data).toEqual({ id = 11, kind = "DeveloperProduct" })
		t.expect(w.sessions[p].Data.currencies.Gems).toBe(0)
		t.expect(w.h.PrepareShopPurchase(p, "gems_m").code).toBe("PRODUCT_UNAVAILABLE")
		t.expect(w.h.PrepareShopPurchase(p, "gp_autoreplay").code).toBe("PRODUCT_UNAVAILABLE")
		t.expect(w.h.PrepareShopPurchase(p, "skin_example").code).toBe("INVALID_PRODUCT")
		t.expect(w.h.PrepareShopPurchase(p, "nope").code).toBe("INVALID_PRODUCT")
		t.expect(w.h.PrepareShopPurchase(p, 11).code).toBe("INVALID_PRODUCT")
		t.expect(w.h.PrepareShopPurchase(p, string.rep("g", 100)).code).toBe("INVALID_PRODUCT")
		t.expect(w.h.PrepareShopPurchase(p, "gems_s", 1).code).toBe("INVALID_ARGUMENTS")
		w.state.passes.gp_speed2x = true
		t.expect(w.h.PrepareShopPurchase(p, "gp_speed2x").code).toBe("ALREADY_OWNED")
		w.state.season = nil
		t.expect(w.h.PrepareShopPurchase(p, "pass_premium").code).toBe("PRODUCT_UNAVAILABLE")
		w.state.season = "s1"
		w.sessions[p].Data.battlePass.seasons.s1 = { xp = 0, premium = true, freeClaimed = {}, premiumClaimed = {} }
		t.expect(w.h.PrepareShopPurchase(p, "pass_premium").code).toBe("ALREADY_OWNED")
	end)

	t.test("restricted players cannot see or prepare Shards but the academy stays open", function()
		local w = world()
		local p = w.join(1000)
		w.state.restricted = true
		local info = w.h.GetShopInfo(p)
		t.expect(info.data.restricted).toBe(true)
		t.expect(product(info.data, "shards_s")).toBe(nil)
		t.expect(product(info.data, "gems_s") ~= nil).toBe(true)
		t.expect(w.h.PrepareShopPurchase(p, "shards_s").code).toBe("RESTRICTED_REGION")
		local r = w.h.BuyAcademyItem(p, "academy_selene")
		t.expect(r.ok).toBe(true)
		t.expect(r.data.restricted).toBe(true)
		t.expect(r.data.balances.Gems).toBe(1000 - costOf("academy_selene"))
		local unit = w.sessions[p].Data.units["shop-1"]
		t.expect(unit.unitId).toBe("selene")
		t.expect(unit.source).toBe("shop")
	end)

	t.test("academy purchase is fixed price, once per item, and atomic", function()
		local w = world()
		local p = w.join(costOf("academy_kael") - 1)
		t.expect(w.h.BuyAcademyItem(p, "academy_kael").code).toBe("NOT_ENOUGH_GEMS")
		t.expect(next(w.sessions[p].Data.units)).toBe(nil)
		w.sessions[p].Data.currencies.Gems = 1000
		t.expect(w.h.BuyAcademyItem(p, "academy_kael").ok).toBe(true)
		t.expect(w.h.BuyAcademyItem(p, "academy_kael").code).toBe("ALREADY_OWNED")
		t.expect(w.sessions[p].Data.currencies.Gems).toBe(1000 - costOf("academy_kael"))
		local skin = w.h.BuyAcademyItem(p, "academy_scholar_skin")
		t.expect(skin.ok).toBe(true)
		t.expect(w.sessions[p].Data.skinsOwned.skin_academy_scholar).toBe(true)
		local owned = 0
		for _, item in skin.data.academy do
			owned += if item.owned then 1 else 0
		end
		t.expect(owned).toBe(2)
		t.expect(w.h.BuyAcademyItem(p, "academy_scholar_skin").code).toBe("ALREADY_OWNED")
		t.expect(w.h.BuyAcademyItem(p, "kael").code).toBe("INVALID_ITEM")
		t.expect(w.h.BuyAcademyItem(p, nil).code).toBe("INVALID_ITEM")
		t.expect(w.h.BuyAcademyItem(p, "academy_selene", 0).code).toBe("INVALID_ARGUMENTS")
	end)

	t.test("academy skin already owned from another source is not sold again", function()
		local w = world()
		local p = w.join(1000)
		w.sessions[p].Data.skinsOwned.skin_academy_scholar = true
		t.expect(w.h.BuyAcademyItem(p, "academy_scholar_skin").code).toBe("ALREADY_OWNED")
		t.expect(w.sessions[p].Data.currencies.Gems).toBe(1000)
	end)

	t.test("missing profile is DATA_NOT_READY", function()
		local w = world()
		local ghost: any = { UserId = 5 }
		t.expect(w.h.GetShopInfo(ghost).code).toBe("DATA_NOT_READY")
		t.expect(w.h.BuyAcademyItem(ghost, "academy_kael").code).toBe("DATA_NOT_READY")
	end)
end
