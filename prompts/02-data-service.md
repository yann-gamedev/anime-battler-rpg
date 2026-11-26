# 02 — DataService (ProfileStore)

## Tujuan
Menyimpan data pemain dengan aman (session locking), menyediakan API mutasi yang tervalidasi, dan menjadi satu-satunya modul yang menyentuh DataStore.

## Konteks
- `docs/RULES.md` §3, §9
- `docs/ARCHITECTURE.md` §3, §6
- Dokumentasi resmi ProfileStore (baca README/kode modulnya, jangan menebak API)

## Scope
Dikerjakan:
- `DataService.init/start`: load profil saat `PlayerAdded`, kick dengan pesan sopan jika gagal load/session dicuri, release saat `PlayerRemoving`, `game:BindToClose` aman
- `Template.luau` sesuai skema v1; reconcile field baru
- `Migrations.luau`: tabel `[fromVersion] = function(profile)`; jalankan berurutan sampai versi terbaru
- API (semua dipanggil dari server, tanpa yield di tengah mutasi):
  - `getProfile(player): Profile?` (read-only untuk modul lain; dokumentasikan bahwa mutasi harus via fungsi di bawah)
  - `addCurrency(player, kind, amount, source)` / `spendCurrency(player, kind, amount, reason): boolean`
  - `grantUnit(player, unitId, source): OwnedUnit?` (cek batas maks unit)
  - `removeUnit(player, uid, reason): OwnedUnit?`
  - `updateUnit(player, uid, mutatorFn)` dengan validasi hasil (stars 1..5, level 1..60)
  - `markReceiptProcessed(player, purchaseId)` / `isReceiptProcessed`
- Signal `DataService.Changed(player, path)` untuk mengirim update ke client lewat event `InventoryChanged` / `CurrencyChanged`
- Remote `GetMyData` (C→S) yang mengembalikan subset aman (currencies, units, teams, story, pity) — rate limit
- Hook ke `AnalyticsService` (stub dulu): setiap add/spend currency dicatat dengan `source/reason`
- Perintah admin (hanya UserId di `Constants.ADMIN_USER_IDS`) untuk reset profil di Studio

TIDAK dikerjakan: UI, trade, summon.

## Deliverables
- `src/server/Services/DataService/init.luau`, `Template.luau`, `Migrations.luau`
- `src/server/Services/AnalyticsService.luau` (stub)
- Remote baru di `Remotes.luau`
- `tests/DataService.spec.luau` untuk logika murni (migrasi, validasi) yang bisa dipisah dari DataStore

## Kriteria terima
- Tidak ada `DataStoreService` di file lain selain pemilik yang tercatat di RULES §3 (`grep` untuk membuktikan; saat ini hanya DataService)
- `spendCurrency` menolak jumlah negatif/NaN/non-integer dan saldo kurang
- Data tersimpan setelah keluar dan masuk lagi di Studio (aktifkan API Services di Game Settings)
- Menggunakan DataStore terpisah untuk Studio vs live (nama store mengandung suffix dari `RunService:IsStudio()`)

## Cara uji
1. Play, cek Gems default; gunakan perintah admin untuk menambah 100 Gems
2. Stop, Play lagi → Gems tetap
3. Jalankan tests

## Setelah selesai
- Jalankan `prompts/review-security.md` untuk DataService
- Centang ROADMAP
