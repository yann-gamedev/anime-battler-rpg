# ARCHITECTURE.md — Struktur & Arsitektur

## 1. Tooling

| Tool | Fungsi |
|---|---|
| Rojo | Sinkron `src/` ↔ Studio |
| Wally | Package manager (`Packages/`) |
| StyLua | Formatter |
| Selene | Linter |
| Rokit | Instal & kunci versi tool di atas (`rokit.toml`, dibuat di prompt 00) |
| Roblox Studio MCP (opsional) | Agent membaca place / menjalankan build script `studio/` |

Dependency yang disetujui: **ProfileStore** (data pemain, session locking). Package lain harus disetujui manusia dan dicatat di `docs/DECISIONS.md`.

Jalankan `wally install` sebelum `rojo serve` atau `rojo build`. Rojo memetakan `ServerPackages` ke `ServerScriptService`, sehingga ProfileStore hanya tersedia di server.

## 2. Struktur folder

```
battler-rpg/
├── AGENTS.md                 # titik masuk semua agent
├── CLAUDE.md                 # tambahan khusus Claude Code
├── default.project.json      # tree Rojo
├── wally.toml                # dibuat di prompt 00
├── rokit.toml                # dibuat di prompt 00
├── stylua.toml / selene.toml
├── docs/                     # dokumen desain & aturan (sumber kebenaran)
├── prompts/                  # prompt task berurutan untuk agent
├── studio/                   # build script Studio (UI layout, dunia)
│   ├── ui/                   # build_main_menu.luau, build_team_board.luau
│   └── world/                # build_arena.luau, build_lobby.luau
├── tests/                    # → ServerStorage.Tests; spec untuk modul murni (BattleSim, Config)
│                             #   jalankan: set atribut workspace.RunTests = true lalu Play di Studio
└── src/
    ├── shared/               # → ReplicatedStorage.Shared
    │   ├── Types.luau        # tipe global (UnitDef, OwnedUnit, Profile, ...)
    │   ├── Config/           # SEMUA angka balancing
    │   │   ├── Constants.luau
    │   │   ├── Units.luau
    │   │   ├── Synergies.luau
    │   │   ├── Traits.luau
    │   │   ├── Banners.luau
    │   │   ├── Economy.luau
    │   │   ├── Stages.luau
    │   │   ├── Products.luau     # ID developer product & gamepass
│   │   ├── Territories.luau
│   │   ├── Ultimates.luau    # parameter angka untuk ultimate
│   │   ├── Validate.luau     # validasi config saat server boot
    │   │   └── Assets.luau       # asset ID model/anim/sound
    │   ├── BattleSim/        # simulasi battle deterministik, tanpa Instance
    │   │   ├── init.luau
    │   │   ├── Rng.luau
    │   │   ├── Stats.luau
    │   │   ├── Targeting.luau
    │   │   ├── Skills.luau
    │   │   └── SynergyResolver.luau
    │   ├── Net/
    │   │   └── Remotes.luau  # daftar nama & arah semua remote
    │   └── Util/
    │       ├── Signal.luau
    │       └── TableUtil.luau
    ├── server/               # → ServerScriptService.Server
    │   ├── init.server.luau  # bootstrap: require semua service, init lalu start
    │   ├── Services/
    │   │   ├── DataService/
    │   │   │   ├── init.luau
    │   │   │   ├── Template.luau
    │   │   │   └── Migrations.luau
    │   │   ├── InventoryService.luau
    │   │   ├── TeamService.luau
    │   │   ├── BattleService.luau
    │   │   ├── StageService.luau
    │   │   ├── SummonService.luau
    │   │   ├── TraitService.luau
    │   │   ├── MonetizationService.luau
    │   │   ├── ComplianceService.luau   # wrapper PolicyService + cache
    │   │   ├── TradeService.luau        # milestone M6
    │   │   ├── GuildService.luau        # milestone M7
    │   │   ├── TerritoryService.luau    # milestone M7
    │   │   ├── AnalyticsService.luau
    │   │   └── AdminService.luau        # perintah debug, hanya untuk UserId admin
    │   ├── Net/
    │   │   └── RemoteSetup.luau   # membuat instance remote dari Shared/Net/Remotes
    │   ├── Dev/
    │   │   └── TestRunner.luau    # hanya di Studio, jalankan tests/*.spec
    │   ├── Vendor/                # modul pihak ketiga tanpa Wally (mis. ProfileStore)
    │   └── Util/
    │       ├── RateLimiter.luau
    │       └── Validate.luau
    └── client/               # → StarterPlayer.StarterPlayerScripts.Client
        ├── init.client.luau
        ├── Controllers/
        │   ├── UIController.luau
        │   ├── MenuController.luau
        │   ├── LobbyController.luau
        │   ├── TeamBoardController.luau
        │   ├── BattleViewController.luau   # memutar event log
        │   ├── SummonController.luau
        │   ├── TradeController.luau
        │   ├── GuildController.luau
        │   └── AudioController.luau
        └── UI/
            ├── Theme.luau     # warna, font, ukuran (satu sumber)
            └── Components/    # tombol, panel, kartu unit, dsb
```

Folder yang belum ada dibuat oleh task yang membutuhkannya, bukan sekaligus.

## 3. Pola Service / Controller

Tanpa framework (tanpa Knit). Setiap service adalah ModuleScript dengan bentuk:

```lua
--!strict
local ExampleService = {}

function ExampleService.init()   -- dipanggil sekali, urutan bebas, TANPA yield
end

function ExampleService.start()  -- dipanggil setelah semua init selesai, boleh yield
end

return ExampleService
```

`init.server.luau` me-`require` semua modul di `Services/`, memanggil semua `init()`, lalu semua `start()`. Service lain diakses dengan `require` langsung. Hindari dependency melingkar; jika perlu komunikasi dua arah, pakai `Signal`.

Client sama persis dengan `Controllers/`.

## 4. Remote

`src/shared/Net/Remotes.luau` berisi daftar:

```lua
--!strict
return {
	Events = {        -- RemoteEvent
		"BattleResult",       -- S→C
		"InventoryChanged",   -- S→C
		"TradeUpdated",       -- S→C
	},
	Functions = {     -- RemoteFunction, hanya C→S
		"StartStage",
		"SaveTeam",
		"Summon",
		"RerollTrait",
		"GetBannerInfo",
	},
}
```

Server membuat instance di `ReplicatedStorage.Remotes`. Konvensi nama: kata kerja untuk C→S (`Summon`), kata benda/kejadian untuk S→C (`InventoryChanged`). Semua RemoteFunction mengembalikan `{ ok: boolean, code: string?, data: any? }`.

## 5. Battle: simulasi deterministik + replay

```
Client: StartStage(stageId, teamId)
  └─► Server BattleService
        1. validasi tim & stage
        2. seed = Random.new():NextInteger(...)
        3. result = BattleSim.run({ teamA = teamA, teamB = teamB, seed = seed })
        4. beri reward berdasarkan result.winner
        5. kirim { seed, log, winner, rewards } ke client
Client BattleViewController
  └─► memutar `log` (urutan event) dengan model & animasi
```

- `BattleSim` menerima tabel unit dan seed. Hasilnya `{ winner, log, ticks, survivors }`. Simulasi berjalan dalam 10 tick per detik, dengan batas 900 tick (90 detik) yang menghasilkan seri jika kedua tim masih hidup.
- Input menggunakan sel 1–9 per tim, dihitung dari baris depan. Log memakai sel 1–18 pada papan gabungan 3 kolom × 6 baris. Sel awal A = `10 - cell`, sel awal B = `9 + cell`. Log `spawn` memberi ID battle dan HP awal. Unit panggilan memiliki ID sendiri dan field `owner`.
- Karena deterministik, PvP async dan Perang Wilayah memakai sim yang sama dengan snapshot tim pertahanan.
- `BattleService.runPve(player, teamUnits, enemyDef)` membaca unit dari profil server. Remote `StartTestBattle(teamId)` hanya menerima indeks tim milik pemanggil. Di Studio, UserId yang ada di `Constants.ADMIN_USER_IDS` dapat menerima hasil melalui event pribadi `BattleResult`. Cinematic menghentikan jam replay pada tick ultimate sampai efek selesai atau dilewati.
- `StartPracticeBattle(teamId)` memakai tim yang sudah tersimpan dan batas slot yang sama dengan `SaveTeam`. Lawan diambil dari stage 1-1. Latihan tidak memberi reward atau progres story.
- Bentuk event log (contoh):
  ```lua
  { t = 12, kind = "attack", src = 3, dst = 7, dmg = 140, crit = false, hp = 300, shield = 0 }
  { t = 40, kind = "ultimate", src = 1, skill = "seraphine_dawn", cell = 12, targets = {7, 8}, cinematic = true }
  { t = 41, kind = "death", unit = 8 }
  ```

### Uji replay di Studio

1. Sinkronkan proyek dengan Rojo dalam mode Edit, lalu jalankan isi `studio/world/build_arena.luau` di Command Bar. Simpan place uji agar arena tetap ada.
2. Tambahkan UserId penguji ke `Constants.ADMIN_USER_IDS` pada checkout lokal. Gunakan place pengujian yang sudah dipublikasikan dengan akses API Studio untuk memuat profil.
3. Play Solo. Tempatkan dan simpan setidaknya satu unit. Dari **Client** Command Bar, jalankan `local r = game:GetService("ReplicatedStorage").Remotes.StartTestBattle:InvokeServer(1); assert(r.ok, r.code)`.
4. Uji 1×, 2×, Skip ultimate, dan Cinematics Off. Pastikan unit hilang ketika event kematian diputar dan layar hasil tampil. Tutup replay dan cek kamera kembali serta `Workspace.BattleReplayVisuals` hilang. Ulangi untuk memastikan replay dapat dibuka lagi.
5. Untuk 6 vs 6, siapkan enam unit lewat **Server** Command Bar di place uji, lalu ulangi langkah 3 dengan Device Emulation pada ponsel kecil dalam orientasi portrait dan landscape. Tim lawan uji berisi enam unit.

```luau
local player = game:GetService("Players"):GetPlayers()[1]
local data = require(game:GetService("ServerScriptService").Server.Services.DataService)
local slots = table.create(9, "")
for cell, unitId in { "brutus", "dorin", "pip", "mira", "elodie", "seraphine" } do
	slots[cell] = assert(data.grantUnit(player, unitId, "admin")).uid
end
assert(data.setTeamSlots(player, 1, slots))
```
- Ada test di `tests/BattleSim.spec.luau`: seed sama → hasil sama.

## 6. Skema data pemain (versi 1)

```lua
type OwnedUnit = {
	uid: string,
	unitId: string,        -- key di Config/Units
	stars: number,         -- 1..5
	level: number,         -- 1..60
	xp: number,
	trait: string?,        -- key di Config/Traits
	locked: boolean,       -- dikunci pemain dari dijual/trade
	tradeCooldownUntil: number?, -- os.time()
	obtainedAt: number,
	source: string,        -- "summon" | "story" | "trade" | "event" | "admin"
}

type Profile = {
	version: number,
	currencies: { Gold: number, Gems: number, TraitShards: number, SummonTickets: number, AsramaTokens: number },
	accountLevel: number,                    -- dari progres story; syarat trade (SYSTEMS A2)
	units: { [string]: OwnedUnit },          -- key = uid
	teams: { { name: string, slots: { string } } }, -- 9 entri; "" = slot kosong
	story: { cleared: { [string]: number } }, -- stageId → bintang 1..3
	pity: { [string]: { sinceLegendary: number, sinceMythic: number, guaranteedFeatured: boolean? } }, -- per bannerId
	materials: { XPScrolls: number },
	progress: { tutorialBattleCleared: boolean, firstThreeStarClaimed: { [string]: boolean }, replayDay: number, replayCount: number },
	traitPity: number,                       -- reroll sejak Legendaris+ terakhir (UNITS §5)
	tradeDaily: { day: number, count: number }, -- batas 10 trade/hari (SYSTEMS A2)
	skinsOwned: { [string]: boolean },
	equippedSkins: { [string]: string },     -- uid → skinId
	guildId: string?,
	processedReceipts: { [string]: boolean },
	stats: { battles: number, wins: number, summons: number, robuxSpent: number },
	flags: { tutorialDone: boolean },
	createdAt: number,
}
```

Template default ada di `DataService/Template.luau`. Batas: maks 500 unit per pemain (konstanta di `Constants.luau`).

`DataService.getProfile(player)` memberi snapshot beku. Panggil lagi setelah mutasi untuk membaca nilai terbaru. `GetMyData` mengirim mata uang, inventaris, tim, progres story, dan pity milik pemanggil. `InventoryChanged` dan `CurrencyChanged` mengirim snapshot terbaru hanya ke pemain tersebut.

### Uji penyimpanan di Studio

1. Gunakan place pengujian yang sudah dipublikasikan dan aktifkan **Enable Studio Access to API Services**. DataService memakai `PlayerProfiles_Studio` di Studio dan `PlayerProfiles_Live` di server live.
2. Masukkan UserId penguji ke `Constants.ADMIN_USER_IDS` di checkout lokal. Jalankan Play Solo dengan Command Bar dalam konteks **Server** dan pastikan profil sudah dimuat.
3. Di Command Bar, ambil pemain dengan `local player = game:GetService("Players"):GetPlayers()[1]`, lalu ambil service dengan `local data = require(game:GetService("ServerScriptService").Server.Services.DataService)`. Jalankan `assert(data.adminAddGems(player, 100))` dan catat saldo dari `data.getProfile(player).currencies.Gems`.
4. Stop dan Play lagi. Baca saldo dan pastikan tambahan 100 Gems tetap ada. `data.adminResetProfile(player)` mereset profil pemain penguji di store Studio. Kedua perintah hanya tersedia dari server bagi UserId yang diizinkan.
5. Untuk tes Luau di Studio, set atribut Boolean `Workspace.RunTests` ke `true` sebelum Play dan cek ringkasan di Output.

### Story dan inventory

`StartStage(stageId, teamIndex)` menjalankan pertarungan untuk tim tersimpan. Bintang dan reward dihitung serta disimpan di server sebelum replay dikembalikan melalui respons. Jika tim masih kosong, stage `tutorial` memakai starter pemain tanpa mengubah slot tim yang tersimpan.

`GetMyData`, `LevelUpUnit`, `MergeUnit`, `DismantleUnit`, dan `LockUnit` mengembalikan snapshot milik pemanggil saat berhasil. XP Scroll adalah material inventory. Field progres tambahan direkonsiliasi dalam skema v1, dan reward Gems pertama untuk 3★ diklaim bersama progres stage dalam satu mutasi profil.

Di place uji dengan API Services aktif, mulai dari profil baru melalui Play → Onboarding. Menangkan tutorial dan cek 10 tiket. Isi tim, lalu selesaikan 1-1 sampai 1-3. Ulangi 1-1 dengan 3★ dan pastikan Gems pertama tidak diberikan lagi. Uji level up, lock, konfirmasi merge dan dismantle, lalu Stop → Play untuk memastikan progres tersimpan.

### Summon dan peluang

`GetBannerInfo()` mengirim jadwal, harga, status restricted, pity, persentase dasar dan aktual 1×, serta persentase masing-masing posisi draw 10×. Banner aktif dan state pity ditentukan server. `Summon(bannerId, count, payWith)` mengembalikan unit yang diberikan dan snapshot banner terbaru. Saldo, inventaris, dan pity berubah dalam satu mutasi profil. Jika state yang mendasari peluang Gems berubah, server mengembalikan `ODDS_CHANGED` agar pemain melihat peluang terbaru sebelum mencoba lagi.

Di place uji yang dipublikasikan, buka Summon lewat Play atau hadiah onboarding, lalu periksa odds 1× dan semua posisi 10×. Untuk menguji pembatasan, masukkan UserId penguji ke `Constants.ADMIN_USER_IDS` dan gunakan **Server** Command Bar. Jalankan `require(game:GetService("ServerScriptService").Server.Services.ComplianceService).adminForceRestricted(player, true)` dengan `player` dari sesi uji. Uji bahwa UI menyembunyikan opsi Gems, server menolak request Gems, dan tiket gameplay bisa dipakai. Gunakan argumen `false` untuk melepas override dan memeriksa hasil kebijakan asli.

### Trait dan pilihan Gold

`GetTraitInfo(uid)` mengirim trait, biaya, pity, dan peluang aktual per tier dan per trait. `RerollTrait(uid)` menjalankan roll di server dan memakai peluang serta trait yang terakhir dikirim. Untuk pemain restricted, `SelectRestrictedTrait(uid, traitId)` memasang hasil pilihan Biasa atau Langka dengan biaya Gold tetap. Server memvalidasi policy, kepemilikan, status lock, dan saldo ketika transaksi dikomit.

Uji di place Studio yang dipublikasikan. Buka Inventory → detail unit, periksa odds dan konfirmasi sebelum mengganti trait Epic atau lebih tinggi. Paksa status restricted lewat `ComplianceService.adminForceRestricted` dari Server Command Bar. Pastikan pilihan Gold menampilkan biaya dan trait tujuan, lalu cek hasil dan saldo setelah konfirmasi. Lepaskan override untuk memeriksa kebijakan asli.

### Monetisasi dan Battle Pass

`MonetizationService` memasang satu callback `MarketplaceService.ProcessReceipt`. DataService menyimpan grant, bonus awal per paket Gems, statistik belanja, dan marker `PurchaseId` bersama. Callback mengembalikan `PurchaseGranted` setelah marker muncul di `LastSavedData`. `GetShopInfo` dan `PrepareShopPurchase(productKey)` mengirim data untuk tombol pembelian. `BuyAcademyItem(itemId)` memakai harga Gems dari katalog server dan berlaku juga untuk pemain restricted.

`GetBattlePass()` mengirim progres musim dan hak pemain. `ClaimBattlePassTier(track, tier, unitId?)` memeriksa XP, Premium, dan kelayakan hadiah di server. Kemenangan story menambah XP musim. Sejak prompt 10, DataService menyimpan XP Battle Pass aktif bersamaan dengan reward dan status klaim quest. Bingkai profil yang telah diklaim disimpan di profil dan tampil di halaman Battle Pass.

Di place Studio pengujian, jalankan suite dengan `Workspace.RunTests`, lalu buka Toko Akademi dengan override restricted. Beli unit dan skin, cek saldo dan kepemilikan, lalu ulangi setelah rejoin. Uji kontrol gamepass dengan UserId admin melalui `MonetizationService.adminSetPass(player, key, owned)` dari Server Command Bar. Verifikasi auto-replay pada stage 3★, kontrol 2×, slot preset, serta aura. Gunakan Developer Product dan GamePass khusus pengujian untuk memeriksa prompt, receipt, bonus Gems pertama, dan klaim Premium. ID produksi tetap 0 sampai pemilik place mengonfigurasinya.

### Lobby, quest, dan Boss Raid

Setelah Story 1-3, `LobbyService` membuka pajangan dan `RaidService` membuka Boss Raid. `SetLobbyShowcase(uid, skinId?)` memvalidasi kepemilikan unit, kepemilikan skin, dan kecocokan skin dengan unit. Server mereplikasi satu model per karakter. Client menggerakkan `Root.IdleJoint` dan menampilkan aura VIP secara lokal sesuai pengaturan grafis. Skin model saat ini memakai variasi warna dan material placeholder.

`GetQuests()` dan `ClaimQuest(questId, periodKey)` mengembalikan progres, reward, dan waktu reset berdasarkan jam server. Quest harian reset 00:00 UTC, dan quest mingguan reset Senin 00:00 UTC. Progres berasal dari Signal server setelah aktivitas berhasil. Status klaim, mata uang, dan XP Battle Pass aktif dikomit bersama.

`GetRaidInfo()` mengirim status percobaan hari UTC ini. `StartRaid(teamIndex)` menyimulasikan pertarungan dengan tim tersimpan. Server membatasi damage terkredit ke HP boss dan menyimpan percobaan, damage, serta reward tier tertinggi dalam satu mutasi. Replay hanya memvisualisasikan hasil tersebut.

`AnalyticsService` mengirim funnel onboarding, perubahan mata uang beserta saldo akhir, dan event summon, pembelian, klaim quest, raid, serta durasi sesi ke Roblox Analytics. Untuk uji penerimaan, publikasikan build ke place pengujian privat, jalankan alur onboarding dan satu siklus quest/raid, lalu periksa kategori Funnel, Economy, dan Custom di Creator Dashboard.

### Trade (M6)

`TradeService` menyimpan semua state sesi di server (`TradeService/TradeSession.luau`, murni). Remote: `RequestTrade(targetUserId)`, `RespondTrade(sessionId, accept)`, `SetTradeItems(sessionId, unitUids, skinIds)`, `SetReady(sessionId, ready, expectedRevision)`, `ConfirmTrade(sessionId, expectedRevision)`, `CancelTrade(sessionId)`. Semuanya mengembalikan `{ ok, code, data = TradeView }` (`src/shared/TradeTypes.luau`). Event `TradeUpdated` mengirim `TradeView` yang sama hanya ke kedua peserta. UID unit lawan tidak pernah dikirim. `revision` mengikat persetujuan dan hanya naik saat isi berubah atau countdown baru dimulai. `updateId` naik pada setiap mutasi. Konfirmasi baru diterima setelah `countdownEndsAt` (`Workspace:GetServerTimeNow()`). Angka trade ada di `Config/Trade.luau`.

Gerbang server: trade aktif untuk lingkungan ini, kedua pemain di server yang sama, avatar hidup di dalam `Workspace.ArcanumLobby.TradingPlaza` dan berdekatan, level akun, `Player.AccountAge`, batas harian UTC, kebijakan `IsPaidItemTradingAllowed` yang bernilai `true` untuk kedua pemain (fail-closed), serta kelayakan, kepemilikan, kapasitas, dan Gold pajak. Saat countdown dimulai, DataService mengunci item, Gold pajak, dan kapasitas penerima. Guard di `Commit.run` dan mutasi langsung menolak perubahan atas item tersebut (`ITEM_IN_TRADE`).

Data trade hanya diubah DataService (`DataService.trades`). `DataService/TradeJournal.luau` menjalankan prepare (indeks `u/<userId>`), presave (bukti `LastSavedData`), cek ulang, keputusan satu kunci `t/<tradeId>` lewat `UpdateAsync`, swap dua profil tanpa yield, lalu finish (marker tersimpan, hapus indeks, append `d/<hari>/<shard>`). Saat profil dimuat, tradeId di indeks diselesaikan. Kunci kosong ditulis `aborted`, sedangkan keputusan `committed` di-roll-forward sekali lewat marker `trade.applied`. Jika indeks tidak bisa dibaca, profil tidak dimuat. UID ganda di sesi aktif ditandai di `trade.dupeFlags` dan `f/<hari>` tanpa dihapus. Store: `TradeLog_Studio` di Studio, `TradeLog` di live. Field profil `trade` bersifat additive dan direkonsiliasi tanpa migrasi.

Uji di Studio (place pengujian dengan API Services aktif):

1. Jalankan `studio/world/build_lobby.luau`. Masukkan UserId penguji, termasuk `-1` dan `-2` untuk Players lokal, ke `Constants.ADMIN_USER_IDS` di checkout lokal.
2. Mulai **Test → Clients and Servers** dengan 2 client. Dari **Server** Command Bar, untuk tiap pemain: naikkan `accountLevel` lewat progres story atau profil uji ke ≥ 15, lalu jalankan `TradeService.adminSetAccountAge(player, 7)`. Jika kebijakan Studio tidak mengembalikan `IsPaidItemTradingAllowed`, jalankan `ComplianceService.adminForceTradeAllowed(player, true)`. Sediakan ≥ 500 Gold.
3. Bawa kedua avatar ke Trading Plaza. Kirim permintaan, terima, isi tawaran (unit 1★ dan skin), lalu Ready. Cek countdown 5 detik dan perubahan isi yang ditolak (`TRADE_LOCKED`). Confirm dari kedua sisi, lalu cek unit (UID sama, level 1, tanpa trait), refund, pajak, dan `tradeDaily`.
4. Ulangi dengan unit 2★, locked, Mythic baru, dan sisi kosong (harus muncul peringatan UI). Coba keluar saat countdown, spam Confirm, dan tunggu 3 menit sampai sesi expired.
5. Stop → Play. Pastikan hasil trade tersimpan dan indeks `u/<userId>` di `TradeLog_Studio` kosong.

## 7. Studio build scripts (`studio/`)

- Dipakai untuk membangun **hierarki instance** (layout UI, lobby placeholder) sekali jalan.
- Harus idempoten: hapus instance lama dengan nama sama, lalu buat ulang (lihat `studio/ui/build_main_menu.luau`).
- Logika interaktif TIDAK disimpan sebagai string `Source`. Build script hanya membuat instance; controller di `src/client/Controllers/` yang mencari instance itu berdasarkan nama.
- Setelah dijalankan, hasil UI disimpan di place (Team Create) atau diekspor ke `.rbxm` dan ditaruh di `assets/` (opsional).

### Uji Main Menu dan Team Board di Studio

1. Sinkronkan Rojo di mode Edit, lalu jalankan `studio/ui/build_main_menu.luau` dan `studio/world/build_arena.luau` di Command Bar. Menu memakai `UI/Theme.luau`. Team Board dibangun saat runtime.
2. Di place pengujian dengan akses DataStore Studio, jalankan Device Emulation untuk iPhone SE dan tablet. Uji Play, Settings, Music, Back, Quit, serta fokus gamepad.
3. Di Team Board, gabungkan dua filter lalu kosongkan lagi. Tempatkan Kael dan Pip untuk melihat sinergi Api, lalu pindahkan dan hapus salah satu unit. Uji tap di perangkat sentuh dan drag kartu ke slot dengan mouse.
4. Susun dan simpan tiga unit, lalu Stop → Play. Pastikan ketiga slot kembali terisi. Tekan **Start battle** untuk memulai replay latihan. Jika ada perubahan belum disimpan, UI menyimpannya dahulu dan hanya memulai battle jika server menerima tim.

### Uji Lobby Arcanum di Studio

1. Sinkronkan Rojo di mode Edit. Jalankan `studio/ui/build_main_menu.luau`, `studio/world/build_arena.luau`, dan `studio/world/build_lobby.luau` dari Command Bar. Jalankan ulang builder lobby dan pastikan hanya satu `Workspace.ArcanumLobby` yang dihasilkan, dengan `AcademySpawn` aktif.
2. Selesaikan Story 1-3 dengan profil uji. Buka courtyard lewat Play dan uji rute Story, Summon, Shop, Quest, Raid, dan Announcements. Uji sentuhan, keyboard (E di stasiun, M untuk menu), serta gamepad (X di stasiun, Y untuk menu, A untuk memilih, B untuk kembali).
3. Siapkan dua atau lebih client. Pilih unit pajangan, coba skin yang dimiliki, lalu periksa replika, idle, dan aura VIP dari client lain. Ulangi setelah ganti pilihan, respawn, dan rejoin. Coba Low graphics, nonaktifkan cinematic saat replay, lalu uji Music dan SFX dengan aset asli yang dikonfigurasi di `Config/Assets.luau` atau `Sound` tanpa SoundGroup dengan atribut `AudioCategory` bernilai `Music` atau `SFX`.
4. Buka quest harian dan mingguan, selesaikan satu target, dan pastikan hadiah hanya masuk sekali. Uji halaman yang melewati 00:00 UTC dan batas Senin. Jalankan raid, tutup replay lebih awal, lalu coba lagi setelah rejoin. Pastikan hasil server tetap tampil dan percobaan kedua ditolak dalam hari yang sama.
5. Gunakan Server & Clients di Studio untuk uji replikasi sampai delapan client. Untuk target sepuluh pemain, pakai place uji privat dengan pajangan aktif dan ukur lewat Performance Stats atau MicroProfiler di perangkat sasaran. Target 60 FPS setara sekitar 16,7 ms per frame. [Mode pengujian Roblox Studio](https://create.roblox.com/docs/studio/testing-modes).

## 8. Konfigurasi sebagai data

Semua config adalah ModuleScript yang mengembalikan tabel beku (`table.freeze`). Contoh `Config/Units.luau`:

```lua
--!strict
local Types = require(script.Parent.Parent.Types)

local Units: { [string]: Types.UnitDef } = {
	kael = {
		id = "kael",
		name = "Kael Ardent",
		rarity = "Rare",
		class = "Mage",
		element = "Api",
		status = "Murid",
		base = { hp = 520, atk = 64, def = 18, spd = 0.9, range = 3 },
		ultimate = "kael_flare_burst",
	},
}

return table.freeze(Units)
```

Isi lengkap unit ada di `docs/UNITS.md`; config di-generate/ditulis berdasarkan dokumen itu. **Dokumen adalah sumber desain, config adalah sumber runtime** — jika berbeda, laporkan dan samakan.
