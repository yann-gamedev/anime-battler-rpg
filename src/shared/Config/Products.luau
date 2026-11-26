--!strict
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

-- TODO: Replace 0 with the published Marketplace IDs before enabling purchases.
local definitions: { [string]: Types.ProductDef } = {
	gems_s = { id = 0, kind = "DeveloperProduct", priceRobux = 100, grant = { currency = "Gems", amount = 300 } },
	gems_m = { id = 0, kind = "DeveloperProduct", priceRobux = 400, grant = { currency = "Gems", amount = 1300 } },
	gems_l = { id = 0, kind = "DeveloperProduct", priceRobux = 800, grant = { currency = "Gems", amount = 2800 } },
	gems_xl = { id = 0, kind = "DeveloperProduct", priceRobux = 1700, grant = { currency = "Gems", amount = 6200 } },
	gems_xxl = { id = 0, kind = "DeveloperProduct", priceRobux = 4500, grant = { currency = "Gems", amount = 17500 } },
	shards_s = {
		id = 0,
		kind = "DeveloperProduct",
		priceRobux = 200,
		grant = { currency = "TraitShards", amount = 30 },
	},
	pass_premium = { id = 0, kind = "DeveloperProduct", priceRobux = 800 },
	skin_example = { id = 0, kind = "DeveloperProduct" },
	gp_speed2x = { id = 0, kind = "GamePass", priceRobux = 150 },
	gp_autoreplay = { id = 0, kind = "GamePass", priceRobux = 300 },
	gp_presets = { id = 0, kind = "GamePass", priceRobux = 100 },
	gp_vip_aura = { id = 0, kind = "GamePass", priceRobux = 400 },
}

return TableUtil.deepFreeze({
	definitions = definitions,
	firstGemPurchaseMultiplier = 2,
	skinPriceRangeRobux = { min = 300, max = 1200 },
	battleSpeedWithPass = 2,
	extraPresetsWithPass = 6,
	autoReplayRequiredStars = 3,
})
