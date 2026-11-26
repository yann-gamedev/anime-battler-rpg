# 07 — Summon, Banner, Pity, Compliance

## Tujuan
Membuat sistem gacha yang adil, transparan (odds terlihat), patuh kebijakan Roblox, dan aman dari manipulasi client.

## Konteks
- `docs/RULES.md` §1, §4 (**wajib baca penuh**)
- `docs/ECONOMY.md` §1, §2
- `docs/GDD.md` §10 (layar Summon), §11
- Dokumentasi Roblox: "Paid random items policy" & `PolicyService` (verifikasi nama field terbaru)

## Scope
Dikerjakan:
- `ComplianceService`: `isPaidRandomRestricted(player): boolean` — memanggil `PolicyService:GetPolicyInfoForPlayerAsync` dalam `pcall`, cache per sesi; **jika gagal, anggap `true` (fail-closed)** dan log
- `SummonService`:
  - `Summon(bannerId, count: 1 | 10, payWith: "Gems" | "Tickets")`
  - Validasi: banner aktif (cek waktu mulai/akhir dari config), saldo cukup, ruang inventory cukup
  - Jika `payWith == "Gems"` dan pemain restricted → tolak `"RESTRICTED_REGION"`
  - Roll di server dengan `Random.new()` server; terapkan pity Legendary+ (50), hard pity Mythic (200), 50/50 featured, jaminan Epic+ di 10×
  - Kurangi mata uang, beri unit, update pity — dalam satu alur tanpa yield setelah pengurangan
  - Return daftar hasil untuk animasi
- Remote `GetBannerInfo` → odds per rarity & per unit dihitung dari `Config/Banners` + `Config/Units` (bukan angka hardcode di UI), pity counter pemain, status restricted
- Client `SummonController`: layar banner, tombol 1×/10× (menampilkan harga), **tombol "Lihat Odds" yang wajib terlihat sebelum beli**, animasi reveal per rarity (skip-able), pity counter
- Pemain restricted: tombol Gems tidak tampil; tampilkan tombol Toko Akademi (beli langsung — implementasi toko di prompt 09, di sini cukup tombol yang membuka placeholder)

TIDAK dikerjakan: pembelian Robux (prompt 09).

## Deliverables
- `src/server/Services/ComplianceService.luau`, `SummonService.luau`
- `src/client/Controllers/SummonController.luau`
- `tests/Summon.spec.luau` — fungsi roll murni dipisah (`SummonService/Roll.luau` atau di shared tanpa akses data) agar bisa di-test

## Kriteria terima
- Test simulasi 1.000.000 roll: distribusi rarity dalam ±0.1% dari odds config
- Test pity: roll ke-50 tanpa Legendary+ selalu Legendary+, roll ke-200 tanpa Mythic selalu Mythic, 50/50 bekerja
- Server menolak summon Gems untuk pemain restricted walau client dimodifikasi
- Odds di UI = odds di config (ubah config → UI ikut berubah tanpa ubah kode UI)
- Spam remote summon dibatasi rate limiter

## Cara uji
- Jalankan tests; di Studio, paksa `isPaidRandomRestricted` = true lewat perintah admin dan cek UI & server

## Setelah selesai
- Wajib `prompts/review-security.md` (SummonService, ComplianceService)
- Centang ROADMAP
