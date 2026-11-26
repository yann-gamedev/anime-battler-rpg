# 05 — Fondasi UI, Main Menu, Team Board

## Tujuan
Membuat sistem UI yang konsisten dan mobile-first, memindahkan logika Main Menu ke controller, dan membangun layar Team Board untuk menyusun tim di papan 3×3.

## Konteks
- `docs/GDD.md` §6, §10
- `docs/ARCHITECTURE.md` §7
- `docs/UNITS.md` §4 (indikator sinergi)
- `studio/ui/build_main_menu.luau` (sudah ada)

## Scope
Dikerjakan:
- `UI/Theme.luau`: warna (termasuk warna rarity & elemen), font, ukuran teks, radius, padding — satu sumber. Pakai palet yang sama dengan Main Menu yang ada
- `UI/Components/`: `Button`, `Panel`, `UnitCard` (ikon, rarity border, ★, level), `Modal`, `Toast`
- `UIController`: membuka/menutup layar, satu layar aktif, tombol back
- Refactor Main Menu: build script hanya membuat instance; logika pindah ke `MenuController.luau` (hapus `controller.Source` dari build script). Perilaku tetap sama
- `TeamService` (server): `SaveTeam(teamIndex, slots)` — validasi uid milik pemain, tidak duplikat, jumlah unit ≤ batas papan yang terbuka (`Constants`), sel 1..9
- `TeamBoardController`: daftar unit (scroll, filter elemen/rarity), drag-and-drop/tap-to-place ke papan 3×3, panel sinergi aktif real-time (pakai `SynergyResolver` dari shared), tombol Simpan & Mulai Battle
- Semua tombol ≥ 44×44 px, uji di Device Emulation (iPhone SE & tablet)

TIDAK dikerjakan: inventory lengkap, upgrade unit.

## Deliverables
- `src/client/UI/Theme.luau`, `src/client/UI/Components/*.luau`
- `src/client/Controllers/UIController.luau`, `MenuController.luau`, `TeamBoardController.luau`
- `src/server/Services/TeamService.luau`
- `studio/ui/build_main_menu.luau` (diperbarui), `studio/ui/build_team_board.luau` (jika layout dibuat via build script)

## Kriteria terima
- Main Menu berperilaku sama seperti sebelumnya (Play, Settings, Music toggle, Quit, navigasi gamepad)
- Tim tersimpan di server dan tetap ada setelah rejoin
- Panel sinergi berubah langsung saat unit dipindah
- Tidak ada warna/ukuran hardcode di controller (semua dari Theme)

## Cara uji
- Play di Device Emulation, susun tim 3 unit, simpan, rejoin, cek tim

## Setelah selesai
- Centang ROADMAP
