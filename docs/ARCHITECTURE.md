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
        3. result = BattleSim.run(teamA, teamB, seed)   -- murni data, instan
        4. beri reward berdasarkan result.winner
        5. kirim { seed, log, winner, rewards } ke client
Client BattleViewController
  └─► memutar `log` (urutan event) dengan model & animasi
```

- `BattleSim` **tidak** menyentuh Instance, `workspace`, atau waktu nyata. Input = tabel unit + seed, output = `{ winner, log, ticks }`. Fixed tick (mis. 10 tick/detik), batas maks 900 tick (90 detik) → seri jika habis.
- Karena deterministik, PvP async dan Perang Wilayah memakai sim yang sama dengan snapshot tim pertahanan.
- Bentuk event log (contoh):
  ```lua
  { t = 12, kind = "attack", src = 3, dst = 7, dmg = 140, crit = false }
  { t = 40, kind = "ultimate", src = 1, skill = "seraphine_dawn", targets = {7, 8} }
  { t = 41, kind = "death", unit = 8 }
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
	teams: { { name: string, slots: { [number]: string? } } }, -- slot 1..9 → uid
	story: { cleared: { [string]: number } }, -- stageId → bintang 1..3
	pity: { [string]: { sinceLegendary: number, sinceMythic: number } }, -- per bannerId
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

## 7. Studio build scripts (`studio/`)

- Dipakai untuk membangun **hierarki instance** (layout UI, lobby placeholder) sekali jalan.
- Harus idempoten: hapus instance lama dengan nama sama, lalu buat ulang (lihat `studio/ui/build_main_menu.luau`).
- Logika interaktif TIDAK disimpan sebagai string `Source`. Build script hanya membuat instance; controller di `src/client/Controllers/` yang mencari instance itu berdasarkan nama.
- Setelah dijalankan, hasil UI disimpan di place (Team Create) atau diekspor ke `.rbxm` dan ditaruh di `assets/` (opsional).

> Catatan: `build_main_menu.luau` yang sudah ada masih menaruh logika di `controller.Source`. File dipindah ke `studio/ui/` di prompt 00; logikanya dipecah ke `src/client/Controllers/MenuController.luau` di prompt 05.

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
		base = { hp = 520, atk = 64, def = 18, spd = 1.0, range = 3 },
		ultimate = "kael_flare_burst",
	},
}

return table.freeze(Units)
```

Isi lengkap unit ada di `docs/UNITS.md`; config di-generate/ditulis berdasarkan dokumen itu. **Dokumen adalah sumber desain, config adalah sumber runtime** — jika berbeda, laporkan dan samakan.
