--!strict
-- Produk Robux (docs/ECONOMY.md §5), Toko Akademi non-acak, dan parameter monetisasi.
-- Harga Robux di sini hanya referensi placeholder: client menampilkan harga aktual dari
-- MarketplaceService:GetProductInfoAsync sebelum membuka prompt Roblox.
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

-- TODO: Replace 0 with the published Marketplace IDs before enabling purchases.
local definitions: { [string]: Types.ProductDef } = {
	gems_s = {
		id = 0,
		kind = "DeveloperProduct",
		name = "300 Gems",
		priceRobux = 100,
		grant = { currency = "Gems", amount = 300 },
	},
	gems_m = {
		id = 0,
		kind = "DeveloperProduct",
		name = "1.300 Gems",
		priceRobux = 400,
		grant = { currency = "Gems", amount = 1300 },
	},
	gems_l = {
		id = 0,
		kind = "DeveloperProduct",
		name = "2.800 Gems",
		priceRobux = 800,
		grant = { currency = "Gems", amount = 2800 },
	},
	gems_xl = {
		id = 0,
		kind = "DeveloperProduct",
		name = "6.200 Gems",
		priceRobux = 1700,
		grant = { currency = "Gems", amount = 6200 },
	},
	gems_xxl = {
		id = 0,
		kind = "DeveloperProduct",
		name = "17.500 Gems",
		priceRobux = 4500,
		grant = { currency = "Gems", amount = 17500 },
	},
	shards_s = {
		id = 0,
		kind = "DeveloperProduct",
		name = "30 Trait Shards",
		priceRobux = 200,
		grant = { currency = "TraitShards", amount = 30 },
	},
	-- Satu SKU per musim: musim baru = produk baru dengan ID baru, SKU lama tetap terikat musimnya.
	pass_premium = {
		id = 0,
		kind = "DeveloperProduct",
		name = "Battle Pass Premium",
		priceRobux = 800,
		battlePassSeasonId = "s1",
	},
	-- Skin berbayar Robux belum punya isi; tanpa grant = tidak tersedia dan receipt-nya tidak diproses.
	skin_example = { id = 0, kind = "DeveloperProduct" },
	gp_speed2x = { id = 0, kind = "GamePass", name = "Battle 2× Speed", priceRobux = 150 },
	gp_autoreplay = { id = 0, kind = "GamePass", name = "Auto-Replay", priceRobux = 300 },
	gp_presets = { id = 0, kind = "GamePass", name = "+6 Preset Tim", priceRobux = 100 },
	gp_vip_aura = { id = 0, kind = "GamePass", name = "VIP Lobby Aura", priceRobux = 400 },
}

-- Urutan tampilan toko (deterministik).
local displayOrder = {
	"gems_s",
	"gems_m",
	"gems_l",
	"gems_xl",
	"gems_xxl",
	"shards_s",
	"pass_premium",
	"gp_speed2x",
	"gp_autoreplay",
	"gp_presets",
	"gp_vip_aura",
}

-- Gamepass → atribut Player yang direplikasi server (UI hanya membaca, bukan sumber otoritas).
local passAttributes = {
	gp_speed2x = "PassSpeed2x",
	gp_autoreplay = "PassAutoReplay",
	gp_presets = "PassExtraPresets",
	gp_vip_aura = "PassVipAura",
}

-- Toko Akademi: harga Gems tetap sementara (prompt 09), sekali beli per item per akun.
local academy: { Types.AcademyItemDef } = {
	{ id = "academy_kael", name = "Kael Ardent", kind = "Unit", itemId = "kael", costGems = 150 },
	{ id = "academy_selene", name = "Selene", kind = "Unit", itemId = "selene", costGems = 300 },
	{
		id = "academy_scholar_skin",
		name = "Academy Scholar",
		kind = "Skin",
		itemId = "skin_academy_scholar",
		costGems = 250,
	},
}

return TableUtil.deepFreeze({
	definitions = definitions,
	displayOrder = displayOrder,
	passAttributes = passAttributes,
	academy = academy,
	firstGemPurchaseMultiplier = 2,
	skinPriceRangeRobux = { min = 300, max = 1200 },
	battleSpeedWithPass = 2,
	extraPresetsWithPass = 6,
	autoReplayRequiredStars = 3,
	receipt = {
		-- Menunggu profil dimuat saat receipt datang ketika join, lalu NotProcessedYet.
		profileWaitSeconds = 60,
		profilePollSeconds = 0.5,
		-- Batas tunggu satu save ProfileStore dan jeda sebelum mencoba save lagi.
		saveWaitSeconds = 30,
		saveRetrySeconds = 10,
		saveAttempts = 6,
	},
	gamePassRetrySeconds = 60,
	-- Visual aura VIP (server membuat instance pada karakter; ikut tereplikasi).
	vipAura = {
		name = "VipAura",
		rate = 6,
		lifetime = 1.2,
		speed = 1.5,
		size = 0.6,
		color = { r = 255, g = 214, b = 92 },
	},
})
