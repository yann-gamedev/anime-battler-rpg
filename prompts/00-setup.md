# 00 — Setup Proyek

## Tujuan
Menyiapkan toolchain dan skeleton proyek sehingga `rojo serve` bisa disambungkan ke Studio dan bootstrap server/client berjalan tanpa error.

## Konteks
- `AGENTS.md`, `docs/RULES.md`, `docs/ARCHITECTURE.md` §1–4, §7

## Scope
Dikerjakan:
- `rokit.toml` berisi rojo, wally, stylua, selene (versi stabil terbaru; tulis versi yang dipakai di DECISIONS)
- `wally.toml` (realm shared/server sesuai kebutuhan) — **hanya** dependency yang disetujui (ProfileStore). Jika ProfileStore tidak tersedia lewat Wally, taruh modulnya di `src/server/Vendor/ProfileStore.luau` sesuai instruksi resmi pembuatnya dan catat sumber + versinya
- Verifikasi `default.project.json`, `stylua.toml`, `selene.toml`, `.gitignore` yang sudah ada; sesuaikan bila perlu. Jika memakai Wally, tambahkan `"Packages": { "$path": "Packages" }` di bawah `ReplicatedStorage` (sengaja belum ada agar `rojo build` tidak gagal saat folder belum dibuat). Jika Selene meminta definisi Roblox, jalankan `selene generate-roblox-std`
- Skeleton: `src/server/init.server.luau`, `src/client/init.client.luau` (loader init→start seperti ARCHITECTURE §3), `src/shared/Net/Remotes.luau` (list kosong), modul pembuat remote di server, `src/server/Util/RateLimiter.luau`, `src/server/Util/Validate.luau`, `src/shared/Util/Signal.luau`
- Test runner sederhana `src/server/Dev/TestRunner.luau`: hanya jalan jika `RunService:IsStudio()` dan atribut `workspace:GetAttribute("RunTests") == true`; me-require semua ModuleScript `*.spec` di `ServerStorage.Tests`, setiap spec mengembalikan `function(t)` dengan `t.test(name, fn)` dan `t.expect(value).toBe(x)` / `.toEqual(tbl)` / `.toBeTruthy()`; cetak ringkasan lulus/gagal. Tanpa dependency eksternal
- Pindahkan `build_main_menu.luau` → `studio/ui/build_main_menu.luau` (isi tidak diubah)
- `git init` jika belum, commit awal

TIDAK dikerjakan: gameplay, data, UI.

## Deliverables
- `rokit.toml`, `wally.toml`
- `src/server/init.server.luau`, `src/server/Net/RemoteSetup.luau`, `src/server/Dev/TestRunner.luau`, `tests/Sanity.spec.luau`, `src/server/Util/RateLimiter.luau`, `src/server/Util/Validate.luau`
- `src/client/init.client.luau`
- `src/shared/Net/Remotes.luau`, `src/shared/Util/Signal.luau`, `src/shared/Types.luau` (kosong dulu, ekspor tipe `Result`)
- `studio/ui/build_main_menu.luau`
- `README.md` singkat: cara instal tool & `rojo serve`

## Kriteria terima
- `rojo build -o build.rbxl` sukses
- `stylua --check src` & `selene src` bersih
- Di Studio (Play), Output menampilkan `[Server] booted` dan `[Client] booted` tanpa error
- `RateLimiter.allow(player, key, maxPerWindow, windowSec): boolean` berfungsi dan membersihkan data saat `PlayerRemoving`
- `Validate` punya helper: `isInt`, `isFiniteNumber`, `isStringMax(len)`, `isOneOf(set)`

## Cara uji
1. `rokit install`, `wally install` (jika dipakai)
2. `rojo serve`, connect plugin Rojo di Studio
3. Play Solo, cek Output

## Setelah selesai
- Centang M0 di `docs/ROADMAP.md`, ganti "Milestone aktif" ke M1
- Catat versi tool & sumber ProfileStore di `docs/DECISIONS.md`
