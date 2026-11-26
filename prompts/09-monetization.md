# 09 — Monetisasi: Developer Product, Gamepass, Toko

## Tujuan
Mengaktifkan pembelian Robux dengan aman (idempoten), gamepass kenyamanan, toko langsung non-acak, dan battle pass.

## Konteks
- `docs/RULES.md` §4 (**wajib**)
- `docs/ECONOMY.md` §5, §6
- `docs/GDD.md` §9
- Dokumentasi Roblox `MarketplaceService.ProcessReceipt` (verifikasi kontrak terbaru)

## Scope
Dikerjakan:
- `MonetizationService`:
  - Satu `ProcessReceipt` handler untuk seluruh game. Alur: cari pemain → profil aktif? (jika tidak, `NotProcessedYet`) → `isReceiptProcessed(PurchaseId)`? (jika ya, `PurchaseGranted`) → beri isi produk dari `Config/Products` → `markReceiptProcessed` → `PurchaseGranted`
  - Bonus pembelian pertama per paket
  - Gamepass: cek `UserOwnsGamePassAsync` saat join (pcall, cache) + `PromptGamePassPurchaseFinished`; fungsi `hasPass(player, id)`
  - Terapkan gamepass: 2× speed (BattleView), auto-replay (StageService, hanya stage 3★), preset tim, aura VIP lobby
  - Catat `stats.robuxSpent` & event analytics
- Toko Akademi (non-acak): skin & unit tertentu dengan harga tetap (Gems atau Robux). Wajib tersedia untuk pemain restricted
- Battle Pass: musim dari config, XP dari battle & quest, klaim tier gratis/premium di server
- UI Toko: paket Gems dengan harga Robux jelas, tanpa pola manipulatif (RULES §4)

TIDAK dikerjakan: mengubah harga di `docs/ECONOMY.md`. ID produk asli diisi manusia di `Config/Products.luau`.

## Deliverables
- `src/server/Services/MonetizationService.luau`, `BattlePassService.luau`
- Controller Toko & Battle Pass di client
- Pembaruan `Config/Products.luau` (struktur; ID tetap placeholder)

## Kriteria terima
- Menjalankan receipt yang sama 2× hanya memberi hadiah 1× (uji dengan memanggil handler langsung di test)
- Jika profil belum termuat, receipt dikembalikan `NotProcessedYet`
- Tidak ada pemberian hadiah dari client
- Pemain restricted tetap bisa membeli skin & unit di Toko Akademi

## Cara uji
- Test Purchase di Studio (Roblox menyediakan pembelian uji di Studio tanpa Robux sungguhan)
- Simulasi receipt duplikat lewat test

## Setelah selesai
- **Wajib** `prompts/review-security.md` (MonetizationService); centang ROADMAP
