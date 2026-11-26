--!strict
-- Konstanta gameplay & keamanan. Semua angka balancing ada di Config/, bukan di logika.
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type RateLimitRule = { max: number, windowSec: number }

local Constants = {
	-- Skema data pemain (docs/ARCHITECTURE.md §6).
	DATA_VERSION = 1,
	MAX_UNITS_PER_PLAYER = 500,

	-- Papan 3×3 (docs/GDD.md §6): 9 sel, unit diturunkan 3 di awal → 6 lewat progres story.
	BOARD_SLOTS = 9,
	BOARD_UNITS_START = 3,
	BOARD_UNITS_MAX = 6,

	-- Jumlah preset tim dasar. Irisan Team Board ini hanya memakai tim 1.
	-- (Gamepass gp_presets +6 belum diimplementasi, docs/ECONOMY.md.)
	TEAM_PRESETS_BASE = 1,
	DEFAULT_TEAM_NAME = "Tim 1",

	-- UID = HttpService:GenerateGUID(false) → 36 karakter. Batas atas defensif.
	MAX_UID_LENGTH = 64,

	-- Unit awal pemain baru (docs/GDD.md §11: "battle tutorial dengan 3 unit gratis").
	-- kael + pip = 2 unit Api untuk mengenalkan sinergi.
	STARTER_UNIT_IDS = { "kael", "pip", "mira" },
	STARTER_UNIT_SOURCE = "story",

	-- Batas nilai unit (docs/UNITS.md / ARCHITECTURE §6).
	UNIT_STARS_MIN = 1,
	UNIT_STARS_MAX = 5,
	UNIT_LEVEL_MIN = 1,
	UNIT_LEVEL_MAX = 60,

	-- docs/UNITS.md §1 dan docs/GDD.md §6.
	MANA_MAX = 100,
	MANA_PER_ATTACK = 10,
	MANA_PER_HIT_TAKEN = 5,
	BASE_CRIT_CHANCE = 0.05,
	BASE_CRIT_DAMAGE_MULTIPLIER = 1.5,
	BATTLE_MAX_SECONDS = 90,

	-- Rate limit per pemain per remote. Setiap RemoteFunction WAJIB punya entri di sini.
	RATE_LIMITS = {
		GetMyData = { max = 5, windowSec = 10 },
		GetTeamBoard = { max = 10, windowSec = 10 },
		SaveTeam = { max = 5, windowSec = 10 },
	} :: { [string]: RateLimitRule },

	-- UserId admin untuk perintah debug (AdminService, belum dibuat).
	ADMIN_USER_IDS = {} :: { number },
}

return TableUtil.deepFreeze(Constants)
