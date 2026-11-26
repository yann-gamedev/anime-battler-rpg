# 11 — Trade

## Tujuan
Membangun sistem trade antar pemain yang aman dari dupe & penipuan, sesuai aturan pasar di dokumen.

## Konteks
- `docs/SYSTEMS.md` bagian A (**wajib baca penuh**)
- `docs/RULES.md` §1–3
- `docs/DECISIONS.md` D-004
- `docs/ARCHITECTURE.md` §6

## Scope
Dikerjakan:
- `TradeService`: state machine sesi (`Requested → Open → Ready → Countdown → Confirmed → Done | Cancelled`), semua state di server
- Remote: `RequestTrade(targetUserId)`, `RespondTrade(sessionId, accept)`, `SetTradeItems(sessionId, unitUids, skinIds)`, `SetReady(sessionId, ready)`, `ConfirmTrade(sessionId)`, `CancelTrade(sessionId)`; event `TradeUpdated`
- Validasi syarat A1 & A2 di setiap perubahan **dan** ulang saat swap
- Swap atomik persis seperti A4 (lewat fungsi `DataService` baru `transferUnit` / `transferSkin` yang dipanggil di dalam satu fungsi tanpa yield)
- Log trade di DataStore terpisah `TradeLog` (append per hari) — tetap lewat `DataService` atau modul log yang dikelola DataService (RULES §3)
- Deteksi dupe: saat profil dimuat, jika UID unit sudah tercatat milik pemain lain di sesi aktif → flag & log (tidak menghapus otomatis)
- Trading Plaza di lobby; UI dua panel, peringatan sisi kosong, reset Ready saat isi berubah, hitung mundur 5 detik
- Refund level saat unit dikirim (SYSTEMS A1)

TIDAK dikerjakan: chat trade, trade lintas server.

## Deliverables
- `src/server/Services/TradeService.luau` (+ submodul `TradeSession.luau`)
- Fungsi baru di `DataService`
- `src/client/Controllers/TradeController.luau`
- `tests/TradeSession.spec.luau` (state machine & validasi murni)

## Kriteria terima (uji wajib)
- Keluar server saat countdown → trade batal, tidak ada item hilang/ganda
- Mengubah isi saat countdown → ditolak/di-reset
- Confirm dikirim 20× cepat → swap hanya terjadi 1×
- Unit 2★+, locked, di tim pertahanan, atau cooldown tidak bisa ditambahkan
- Batas 10 trade/hari & pajak Gold berlaku
- Dua akun uji (Studio Test 2 clients) bisa trade end-to-end

## Setelah selesai
- **Wajib** `prompts/review-security.md` dengan fokus dupe; centang ROADMAP
