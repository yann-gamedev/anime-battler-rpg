# 08 — Trait & Reroll

## Tujuan
Menambahkan sistem trait yang menjadi sumber kedalaman build dan pendapatan, dengan odds transparan dan pity.

## Konteks
- `docs/UNITS.md` §5
- `docs/RULES.md` §4
- `docs/ECONOMY.md` §1, §2 (bagian restricted)
- `docs/DECISIONS.md` D-OPEN-1 (jika belum diputuskan, **tanya manusia** sebelum mengimplementasikan jalur restricted)

## Scope
Dikerjakan:
- `TraitService.RerollTrait(uid)`: validasi kepemilikan, tidak locked, punya Trait Shards, pemain tidak restricted → kurangi 1 Shard, roll tier & trait, terapkan pity 100, simpan `traitPity`
- Efek trait diterapkan di `BattleSim/Stats.luau` (sudah ada hook dari prompt 03; lengkapi bila perlu, termasuk `Echo` & `Archmage`)
- UI di layar detail unit: trait sekarang, tombol Reroll, **tabel odds per tier & per trait** di layar yang sama, pity counter, konfirmasi jika trait sekarang tier Epik ke atas ("trait lama akan hilang")
- Jalur pemain restricted sesuai keputusan D-OPEN-1

TIDAK dikerjakan: penjualan Shards dengan Robux (prompt 09).

## Deliverables
- `src/server/Services/TraitService.luau`
- Pembaruan `BattleSim/Stats.luau` / `Skills.luau` bila perlu
- UI trait di controller detail unit
- `tests/Traits.spec.luau`

## Kriteria terima
- Distribusi 1.000.000 roll sesuai odds ±0.05%
- Pity 100 bekerja dan reset setelah dapat Legendaris+
- Odds UI dibaca dari `Config/Traits`
- Server menolak reroll untuk pemain restricted

## Setelah selesai
- `prompts/review-security.md` (TraitService); centang ROADMAP
