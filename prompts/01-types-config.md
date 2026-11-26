# 01 — Types & Config

## Tujuan
Menerjemahkan dokumen desain menjadi tipe Luau dan modul config runtime yang menjadi satu-satunya sumber angka balancing.

## Konteks
- `docs/ARCHITECTURE.md` §6, §8
- `docs/UNITS.md` (semua), `docs/ECONOMY.md` (semua), `docs/SYSTEMS.md` B2

## Scope
Dikerjakan:
- `Types.luau`: `Rarity`, `Element`, `Status`, `UnitClass`, `UnitDef`, `TraitDef`, `SynergyDef`, `BannerDef`, `StageDef`, `ProductDef`, `OwnedUnit`, `Profile`, `Result`
- Config: `Constants`, `Units` (15 unit), `Synergies`, `Traits` (+ pity), `Banners` (Standar + 1 Limited contoh featured `seraphine`), `Economy` (biaya, pengali rarity & bintang, rumus level, bongkar), `Stages` (struktur 3 bab × 10 stage; musuh stage boleh placeholder skala naik), `Products` (ID = 0 sebagai placeholder + komentar TODO), `Territories`, `Assets` (kosong/placeholder)
- Semua tabel di-`table.freeze` (dalam juga, pakai helper deep freeze)
- Validator config `src/shared/Config/Validate.luau` yang dijalankan saat server boot: total odds = 100%, setiap unit di banner ada di `Units`, setiap ultimate punya ID, tidak ada rarity/elemen tak dikenal → `error()` jika salah

TIDAK dikerjakan: logika battle, data pemain. Jangan mengubah angka dari dokumen.

## Deliverables
- `src/shared/Types.luau`
- `src/shared/Config/*.luau` (lihat ARCHITECTURE §2)
- `src/shared/Config/Validate.luau`
- `tests/Config.spec.luau`

## Kriteria terima
- Angka sama persis dengan `docs/UNITS.md` & `docs/ECONOMY.md`. Jika dokumen ambigu, tulis pertanyaan di ringkasan, jangan menebak diam-diam
- Server boot menjalankan validator tanpa error
- Fungsi helper `Economy.levelCost(n)` dan `Economy.starMultiplier(stars)` tersedia dan ter-test

## Cara uji
- Play Solo → tidak ada error validator
- Ubah sementara satu odds jadi salah → server harus error jelas (lalu kembalikan)

## Setelah selesai
- Centang task di ROADMAP
