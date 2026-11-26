# AGENTS.md — Battler RPG (Roblox)

Dokumen ini adalah titik masuk untuk SEMUA agent AI (Claude Code, Codex, Cursor, dll.) dan manusia yang bekerja di repo ini. Baca sampai habis sebelum menulis kode.

## Ringkasan proyek

Game Roblox **auto battler RPG bertema anime** dengan karakter **original**. Realm pertama: **Akademi Sihir Arcanum**. Pemain mengumpulkan unit (gacha), menyusun tim di papan 3×3, lalu unit bertarung otomatis. Fitur sosial utama (setelah MVP): **Trade** dan **Perang Wilayah antar-Asrama (guild)**.

- Engine: Roblox, bahasa **Luau** (`--!strict`)
- Sinkronisasi kode: **Rojo** (kode di file, bukan di Studio)
- Gaya visual: **low-poly cel-shaded**, VFX sihir mencolok
- Target platform: **mobile dulu**, lalu PC/konsol
- Tim: 2 orang + agent AI

## Urutan baca wajib

1. `AGENTS.md` (file ini)
2. `docs/RULES.md` — aturan yang TIDAK BOLEH dilanggar
3. `docs/ARCHITECTURE.md` — struktur folder, pola service/controller, skema data
4. `docs/ROADMAP.md` — milestone aktif dan task berikutnya
5. Dokumen sesuai task:
   - Desain game umum → `docs/GDD.md`
   - Unit, sinergi, trait → `docs/UNITS.md`
   - Mata uang, banner, harga, odds → `docs/ECONOMY.md`
   - Trade dan Perang Wilayah → `docs/SYSTEMS.md`
6. Prompt task di `prompts/` (lihat `prompts/README.md`)
7. `docs/DECISIONS.md` — keputusan yang sudah diambil (jangan diulang-debat)

## 10 aturan emas (ringkasan `docs/RULES.md`)

1. **Server memutuskan, client hanya menampilkan.** Hasil battle, drop, summon, trade, pembelian → semua dihitung di server.
2. **Semua RemoteEvent/RemoteFunction divalidasi**: tipe argumen, kepemilikan item, rate limit.
3. **Data pemain hanya lewat `DataService`.** Store lain (Guild, Territory) hanya disentuh service pemiliknya — lihat tabel di RULES §3.
4. **Angka balancing hanya di `src/shared/Config/`.** Tidak ada magic number di logika.
5. **Item acak berbayar wajib menampilkan odds** dari sumber config yang sama dengan logika roll, dan **wajib menghormati `PolicyService.ArePaidRandomItemsRestricted`**.
6. **Karakter original saja.** Dilarang membuat unit yang menyalin nama, desain, atau jurus karakter anime/IP yang sudah ada.
7. **`--!strict` di setiap file Luau**, tipe untuk semua fungsi publik.
8. **Satu task = satu perubahan terfokus.** Jangan refactor area lain tanpa diminta.
9. **Jangan mengarang API Roblox.** Kalau ragu sebuah API ada, tulis catatan `-- TODO(verify-api)` dan laporkan.
10. **Setelah task selesai**: centang `docs/ROADMAP.md`, tambahkan entri di `docs/DECISIONS.md` jika ada keputusan baru.

## Alur kerja agent

1. Baca prompt task di `prompts/NN-*.md`.
2. Baca dokumen yang disebut di bagian "Konteks" prompt tersebut.
3. Tulis rencana singkat (file yang akan dibuat/diubah) sebelum coding.
4. Implementasi. Jaga file < 400 baris; pecah modul jika lebih.
5. Jalankan pengecekan:
   ```bash
   stylua src
   selene src
   rojo build -o build.rbxl   # memastikan tree Rojo valid
   ```
6. Tulis ringkasan: apa yang dibuat, cara menguji di Studio, risiko/TODO.
7. Update `docs/ROADMAP.md` (centang) dan `docs/DECISIONS.md` (jika perlu).

## Definition of Done

- [ ] Lolos `stylua --check src` dan `selene src` tanpa error
- [ ] Tidak ada logika gameplay penting di client
- [ ] Remote baru terdaftar di `src/shared/Net/Remotes.luau` dan divalidasi di server
- [ ] Angka baru ada di `Config/`, bukan di logika
- [ ] Ada cara uji manual yang jelas (langkah di Studio) atau test di `tests/`
- [ ] Dokumen terkait diperbarui jika perilaku berubah

## Hal yang harus ditanyakan ke manusia (jangan diputuskan sendiri)

- Mengubah harga Robux, odds banner, atau pity
- Menambah/menghapus mata uang
- Mengubah skema data yang membutuhkan migrasi data pemain lama
- Menambah dependency (package Wally) baru
- Apa pun yang menyentuh Trade atau pembelian Robux di luar scope prompt

## Folder `studio/`

Berisi **build script Studio** (dijalankan via Command Bar atau Roblox Studio MCP `execute_luau`) untuk membangun instance yang tidak praktis dibuat lewat Rojo, misalnya layout UI awal. Contoh: `studio/ui/build_main_menu.luau`. Logika (LocalScript/ModuleScript) yang permanen tetap ditulis di `src/`, bukan di string `Source` build script. Lihat `docs/ARCHITECTURE.md` bagian "Studio build scripts".
