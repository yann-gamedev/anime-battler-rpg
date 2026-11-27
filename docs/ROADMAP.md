# ROADMAP.md — Milestone & Task

Kerjakan berurutan. Setiap task punya prompt di `prompts/`. Centang `[x]` hanya jika Definition of Done di `AGENTS.md` terpenuhi.

**Milestone aktif: M0**

## M0 — Setup proyek
- [ ] Rojo, Wally, StyLua, Selene, Rokit terpasang; `rojo serve` jalan → `prompts/00-setup.md`
- [ ] Pindahkan `build_main_menu.luau` ke `studio/ui/`

## M1 — Fondasi data
- [x] `Types.luau` + semua `Config/` awal dari `docs/UNITS.md` & `docs/ECONOMY.md` → `prompts/01-types-config.md`
- [ ] `DataService` dengan ProfileStore, template, migrasi, API mutasi → `prompts/02-data-service.md`
  - Implementasi, build, dan tes Luau lokal lulus. Verifikasi Stop → Play dengan DataStore pada place Studio pengujian masih tertunda.

## M2 — Battle
- [ ] `BattleSim` deterministik + sinergi + 15 ultimate + test → `prompts/03-battle-sim.md`
  - Implementasi, build, dan suite Luau lulus. Benchmark 6 vs 6 pada Roblox Studio masih tertunda.
- [ ] `BattleService` + `BattleViewController` (replay dengan model placeholder) → `prompts/04-battle-view.md`
  - Implementasi, build, dan tes timeline lulus. Uji visual dan FPS 6 vs 6 di Device Emulation masih tertunda.

## M3 — UI & progres
- [ ] Fondasi UI (Theme, komponen), Main Menu dipindah ke controller, Team Board 3×3 → `prompts/05-ui-team-board.md`
  - Build, tes draft dan sinergi, serta validasi latihan lokal lulus. Uji iPhone SE/tablet dan penyimpanan setelah rejoin di Studio masih tertunda.
- [ ] Story 30 stage, reward, level & merge unit, inventory → `prompts/06-story-progression.md`
  - Implementasi, build, dan tes lokal lulus. Uji onboarding, UI, serta persistensi setelah rejoin di Roblox Studio masih tertunda.

## M4 — Gacha & monetisasi
- [ ] Banner, pity, layar odds, `ComplianceService` → `prompts/07-summon-banner.md`
  - Build, 66 tes Luau, dan uji integrasi dengan mock lulus. Verifikasi PolicyService asli dan UI di Roblox Studio masih tertunda.
- [ ] Trait & reroll + pity trait → `prompts/08-traits.md`
  - Jalur restricted sudah diputuskan di D-025. Uji UI dan PolicyService asli di Roblox Studio masih tertunda.
- [x] Developer products, gamepass, ProcessReceipt idempoten, toko langsung → `prompts/09-monetization.md`
  - Implementasi, review keamanan terfokus, build, dan tes Luau lokal lulus. Uji transaksi Roblox, simpan/muat ulang profil, dan navigasi perangkat di Studio masih tertunda.

## M5 — Lobby & siap soft launch
- [x] Lobby sosial, pajangan unit, quest harian/mingguan, boss raid, analytics → `prompts/10-lobby-quests.md`
  - Build dan tes lokal lulus. Uji 60 FPS dengan 10 pemain, data profil asli, dan event di Creator Dashboard menunggu place uji.
- [x] Review sumber service sensitif → `prompts/review-security.md` ([hasil review](M5-SECURITY-REVIEW.md))
- [ ] **SOFT LAUNCH MVP** (uji dengan teman, pantau metrik di GDD §12)

## M6 — Trade
- [ ] `TradeService`, Trading Plaza, UI trade → `prompts/11-trade.md`
  - Backend: state machine, gerbang server, jurnal `TradeLog`, pemulihan, dan tes mock lokal lulus. Trade live dimatikan (D-034) sampai uji 2 client dan durabilitas DataStore di place uji Studio selesai.
- [ ] Review keamanan trade + uji dupe manual

## M7 — Asrama & Perang Wilayah
- [ ] `GuildService`, `TerritoryService`, peta wilayah, siklus mingguan → `prompts/12-guild-territory.md`
- [ ] PvP ladder async (opsional, pakai snapshot yang sama)

## M8 — Ekspansi Realm 2
- [ ] Desain Realm 2 di dokumen dulu (GDD, UNITS) → baru task kode

## Task berulang
- Tambah unit baru → `prompts/new-unit.md`
- Perbaiki bug → `prompts/bugfix.md`
- Pass balancing → `prompts/balance-pass.md`
- Review keamanan → `prompts/review-security.md`
