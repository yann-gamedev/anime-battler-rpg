--!strict
-- Angka trade (docs/SYSTEMS.md A1–A5, prompt 11). SATU sumber tuning untuk server dan client.
-- Nama kunci kanonis dipakai juga oleh UI: maxItemsPerSide, taxGold, levelRefundRate, countdownSeconds.
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local SECONDS_PER_DAY = 86400

return TableUtil.deepFreeze({
	-- Gerbang rilis. Live dimatikan sampai invariant durabilitas diverifikasi di place uji (lihat DECISIONS).
	-- Studio memakai store *_Studio sehingga alur penuh bisa diuji tanpa menyentuh data live.
	liveEnabled = false,
	studioEnabled = true,

	-- SYSTEMS A2.
	minAccountLevel = 15,
	minAccountAgeDays = 7,
	dailyMaxTrades = 10,
	maxItemsPerSide = 8, -- unit + skin digabung
	taxGold = 500, -- per sisi per trade selesai

	-- SYSTEMS A1.
	tradableStars = 1,
	levelRefundRate = 0.8, -- fraksi Gold & XP Scroll yang sudah dipakai untuk level, dibulatkan ke bawah
	cooldownSeconds = 7 * SECONDS_PER_DAY, -- Mythic & limited: sejak didapat / sejak trade terakhir
	cooldownRarities = { Mythic = true } :: { [string]: boolean },
	-- Unit featured banner Limited dianggap "limited" (dibaca dari Config/Banners oleh aturan trade).
	limitedFromLimitedBanners = true,

	-- SYSTEMS A3. Waktu sesi memakai Workspace:GetServerTimeNow(); keputusan harian memakai hari UTC.
	countdownSeconds = 5,
	sessionMaxSeconds = 180,
	requestSeconds = 30, -- permintaan yang tidak dijawab dibatalkan lebih awal
	tickSeconds = 0.5, -- interval pengecekan countdown/expiry/jarak

	-- Trading Plaza: Workspace.ArcanumLobby.TradingPlaza (BasePart dari studio/world/build_lobby.luau).
	plaza = {
		lobbyName = "ArcanumLobby",
		partName = "TradingPlaza",
		horizontalMargin = 4, -- stud di luar tepi lantai plaza yang masih dihitung "di plaza"
		minHeight = -2, -- relatif permukaan atas lantai
		maxHeight = 12,
		maxPairDistance = 30, -- jarak HumanoidRootPart kedua pemain
	},

	-- TradeLog (DataStore milik DataService, RULES §3).
	log = {
		retryAttempts = 3,
		retryBackoffSeconds = 1,
		maxPendingPerUser = 1, -- satu jurnal belum selesai per pemain; trade baru ditolak sampai finish/pemulihan
		dailyShards = 64, -- bucket harian deterministik per tradeId
		maxEntriesPerShard = 1000, -- rekaman ≤ ~2 KB → jauh di bawah 4 MB per key
		maxDupeFlagsPerDay = 500,
		saveAttempts = 3,
		saveWaitSeconds = 10,
		finishRetrySeconds = 30,
		maxDupeFlagsPerProfile = 20,
		recentTradesKept = 50, -- marker trade terapan di profil (idempotensi), FIFO
	},
})
