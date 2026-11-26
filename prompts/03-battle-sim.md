# 03 — BattleSim Deterministik

## Tujuan
Membangun simulasi battle murni-data yang deterministik (seed sama → hasil sama), dipakai untuk PvE, PvP async, dan perang wilayah.

## Konteks
- `docs/ARCHITECTURE.md` §5
- `docs/UNITS.md` §1–5
- `docs/GDD.md` §6 (papan & battle)

## Scope
Dikerjakan:
- `BattleSim.run(input): BattleResult`
  - `input = { teamA: {BattleUnitInput}, teamB: {BattleUnitInput}, seed: number, maxTicks: number? }`
  - `BattleUnitInput = { unitId, stars, level, trait?, cell (1..9) }`
  - Output `{ winner: "A" | "B" | "draw", ticks, log: {BattleEvent}, survivors }`
- Fixed tick 10/detik, batas 900 tick
- `Rng.luau`: PRNG sendiri ber-seed (mis. xorshift/PCG) — **jangan** memakai `math.random`; `Random.new(seed)` boleh jika konsisten. Pilih satu dan catat di DECISIONS
- `Stats.luau`: hitung stat akhir sesuai rumus UNITS §1 (rarity, bintang, level, trait, sinergi)
- `Targeting.luau`: perilaku per kelas (UNITS §2), papan lawan dicerminkan
- `SynergyResolver.luau`: hitung sinergi aktif per tim dari unit unik
- `Skills.luau`: 15 ultimate data-driven (tabel efek: damage, area, heal, shield, summon, buff, debuff, stun, taunt). Familiar panggilan Summoner ditambahkan sebagai unit sementara
- Mana, crit, status efek (burn, slow, freeze, stun, shield, taunt, revive Familiar)
- Event log ringkas (lihat ARCHITECTURE §5) cukup untuk animasi client

TIDAK dikerjakan: Instance, model, animasi, remote, reward.

## Deliverables
- `src/shared/BattleSim/init.luau`, `Rng.luau`, `Stats.luau`, `Targeting.luau`, `Skills.luau`, `SynergyResolver.luau`
- Tipe `BattleEvent`, `BattleResult` di `Types.luau`
- `tests/BattleSim.spec.luau`

## Kriteria terima
- Test: seed & input sama dijalankan 100× → log identik
- Test: setiap ultimate terpanggil minimal sekali dalam battle uji
- Test: sinergi 2/3 elemen & status aktif sesuai tabel
- Test: battle 6 vs 6 selesai < 50 ms di Studio (ukur dengan `os.clock`)
- Tidak ada `require` ke service server atau penggunaan `workspace`/`task.wait` di BattleSim

## Cara uji
- `workspace.RunTests = true` → Play → semua spec BattleSim lulus
- Cetak ringkasan 1 battle (pemenang, jumlah event) di Output

## Setelah selesai
- Centang ROADMAP; catat pilihan PRNG di DECISIONS
