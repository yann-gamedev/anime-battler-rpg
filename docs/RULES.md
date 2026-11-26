# RULES.md — Aturan Wajib

Aturan di sini mengikat semua agent dan manusia. Jika prompt task bertentangan dengan dokumen ini, **dokumen ini menang** dan agent harus melaporkan konflik tersebut.

Tingkat: **WAJIB** = tidak boleh dilanggar. **SEBAIKNYA** = boleh dilanggar dengan alasan tertulis di `docs/DECISIONS.md`.

---

## 1. Otoritas server (WAJIB)

Client **tidak pernah** dipercaya. Yang dihitung HANYA di server:

| Hal | Di server | Client boleh |
|---|---|---|
| Hasil battle | Simulasi penuh + seed | Memutar ulang event log untuk animasi |
| Summon / gacha | Roll, pity, pemberian unit | Menampilkan animasi hasil |
| Reroll trait | Roll dan penerapan | Menampilkan hasil |
| Reward stage | Penentuan dan pemberian | Menampilkan popup |
| Trade | Validasi, swap atomik, log | Mengisi UI tawaran |
| Pembelian Robux | `ProcessReceipt` | Memanggil `PromptProductPurchase` |
| Perang wilayah | Hasil serangan, kepemilikan wilayah | Menampilkan peta |
| Level, XP, stars | Perhitungan dan penyimpanan | Menampilkan |

Client mengirim **niat** ("aku mau summon 10x di banner X"), bukan **hasil** ("aku dapat unit Y").

## 2. Remote (WAJIB)

- Semua remote didefinisikan di `src/shared/Net/Remotes.luau`. Server membuatnya saat boot; client hanya `WaitForChild`.
- Setiap handler server WAJIB:
  1. Validasi tipe tiap argumen (`typeof`, rentang angka, panjang string, `math.floor(x) == x` untuk integer, tolak NaN/inf).
  2. Validasi kepemilikan (unit UID milik pemain ini?).
  3. Rate limit per pemain per remote (pakai `src/server/Util/RateLimiter.luau`).
  4. Return error berupa kode (`"NOT_ENOUGH_GEMS"`), bukan pesan teks bebas.
- Hindari `RemoteFunction` dari server ke client (`InvokeClient`) — dilarang.
- Jangan mengirim seluruh profil ke client; kirim hanya data yang dibutuhkan UI.

## 3. Data pemain (WAJIB)

- Data **pemain** hanya disentuh `DataService`, memakai **ProfileStore** (session locking) — lihat ARCHITECTURE.
- Penyimpanan lain punya satu pemilik tetap, dan hanya pemilik itu yang memanggil `DataStoreService`/`MemoryStoreService`:

  | Store | Pemilik |
  |---|---|
  | Profil pemain (ProfileStore) | `DataService` |
  | `TradeLog` | `DataService` (dipanggil `TradeService`) |
  | `Guilds` | `GuildService` |
  | `Territories` + MemoryStore perang | `TerritoryService` |

  Menambah store baru = catat pemiliknya di tabel ini (butuh persetujuan manusia).
- Setiap perubahan data penting melalui fungsi `DataService` yang jelas (`addGems`, `grantUnit`, `removeUnit`), bukan menulis tabel profil sembarangan dari service lain.
- Skema punya `version`. Perubahan skema = tambah fungsi migrasi di `DataService/Migrations.luau`, **jangan** mengubah arti field lama.
- Setiap unit punya **UID unik** (`HttpService:GenerateGUID(false)`), dibuat di server.
- Mata uang tidak boleh negatif. Cek saldo dulu, kurangi, baru beri hadiah — dalam satu fungsi tanpa yield di tengah.

## 4. Monetisasi dan kepatuhan (WAJIB)

- Item acak berbayar (banner, reroll trait yang memakai mata uang yang bisa dibeli Robux) WAJIB:
  - Menampilkan **semua kemungkinan hasil dan odds numeriknya** di UI sebelum pemain membeli.
  - Odds di UI dibaca dari **config yang sama** dengan yang dipakai roll di server.
  - Mengecek `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted`. Jika `true`: sembunyikan/blokir fitur acak berbayar untuk pemain itu dan tawarkan **jalur beli langsung** (toko unit/skin tetap). Cek di server, bukan hanya di UI.
- `ProcessReceipt` WAJIB idempoten: simpan `PurchaseId` yang sudah diproses di profil; jangan beri hadiah dua kali.
- Gamepass dicek di server dengan `MarketplaceService:UserOwnsGamePassAsync` (di-cache).
- **Dilarang** pola manipulatif: timer palsu, "hanya tersisa 1!" palsu, menyembunyikan harga asli, popup beli yang muncul berulang setelah ditolak, mengubah odds diam-diam.
- Hadiah dari Robux tidak boleh membuat pemain gratis mustahil menang di mode kompetitif. Lihat batasan di `docs/SYSTEMS.md`.

## 5. Konten dan IP (WAJIB)

- Semua karakter, nama, desain, dan nama jurus **original**. Dilarang menyalin karakter, logo, musik, atau aset dari anime/game lain.
- Teks buatan pemain (nama Asrama, deskripsi, pesan trade) WAJIB difilter lewat `TextService:FilterStringAsync` sebelum ditampilkan ke pemain lain.
- Konten mengikuti Roblox Community Standards (tidak ada darah realistis, konten dewasa, dsb).

## 6. Gaya kode (WAJIB)

- `--!strict` di baris pertama setiap file Luau.
- Identifier Bahasa Inggris. Komentar Bahasa Indonesia boleh.
- Penamaan: `PascalCase` untuk modul/tipe/service, `camelCase` untuk fungsi & variabel, `SCREAMING_SNAKE` untuk konstanta.
- Satu modul = satu tanggung jawab. File > 400 baris → pecah.
- Tidak ada `_G`, `shared`, atau variabel global.
- Format: StyLua (`stylua.toml`). Lint: Selene (`selene.toml`).
- Gunakan `task.wait/task.spawn/task.defer`, bukan `wait/spawn/delay`.
- Semua koneksi event yang terkait pemain dibersihkan saat `PlayerRemoving`.
- Jangan pakai `pcall` untuk menyembunyikan bug; `pcall` hanya untuk panggilan yang memang bisa gagal (DataStore, HTTP, Marketplace, Policy, Text filter) dan error-nya di-log.

## 7. Performa mobile (SEBAIKNYA)

- Target 60 FPS di HP kelas menengah. Battle maksimal 12 unit di layar.
- Model unit: target < 3.000 segitiga, 1 tekstur atlas per Realm.
- VFX: batasi `ParticleEmitter.Rate`; ultimate cinematic maks ~3 detik dan bisa di-skip.
- Jangan loop `RenderStepped` di server; jangan `while true do` tanpa `task.wait`.
- Simulasi battle tidak memakai fisika Roblox; murni data (lihat ARCHITECTURE).

## 8. Git dan kolaborasi (WAJIB)

- Branch per task: `feat/<milestone>-<nama>`, `fix/<nama>`.
- Commit kecil, pesan jelas: `feat(summon): add pity counter`.
- Jangan commit: `*.rbxl` hasil build, `Packages/`, file berisi API key/secret.
- Place file (`.rbxl`) utama disimpan di luar git atau via Team Create; aset model di-publish ke Roblox, lalu ID-nya dicatat di `src/shared/Config/Assets.luau`.

## 9. Hal yang dilarang untuk agent

- Mengubah `docs/RULES.md` tanpa instruksi manusia.
- Mengubah angka di `docs/ECONOMY.md` / `Config/Economy.luau` tanpa diminta.
- Menambah package Wally baru tanpa izin.
- Menghapus data/migrasi lama.
- Menulis kode yang membaca/menulis DataStore di luar pemilik yang tercatat di §3.
- Menandai task selesai jika pengecekan gagal.
