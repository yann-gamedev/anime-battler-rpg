# 06 — Story, Reward, Progres Unit, Inventory

## Tujuan
Membuat loop progres utama: memainkan stage story, menerima reward, menaikkan level & bintang unit, dan mengelola inventory.

## Konteks
- `docs/GDD.md` §6–8, §11
- `docs/ECONOMY.md` §3, §4, §7
- `docs/UNITS.md` §1

## Scope
Dikerjakan:
- `StageService`: `StartStage(stageId, teamIndex)` → cek stage terbuka, jalankan `BattleService`, hitung bintang (1★ menang, 2★ ≤ 2 unit mati, 3★ tanpa unit mati), beri reward dari `Config/Stages`, first-clear 3★ Gems sekali saja, soft cap Gold replay (ECONOMY §7), naikkan `accountLevel`, buka slot papan sesuai `Constants`
- `InventoryService`: `LevelUpUnit(uid, levels)`, `MergeUnit(targetUid, materialUids)` (aturan ECONOMY §4, unit sama, tidak locked, tidak di tim), `DismantleUnit(uids)`, `LockUnit(uid, locked)`
- Client: layar peta story (bab & stage, bintang), layar inventory (grid `UnitCard`, filter, sort), detail unit (stat akhir, sinergi, ultimate, tombol upgrade/merge/kunci), popup reward
- Konfirmasi sebelum merge/dismantle (menampilkan apa yang hilang)
- Onboarding GDD §11 langkah 2–5 (cutscene boleh placeholder teks). Beri 3 unit starter + Summon Tickets tutorial

TIDAK dikerjakan: summon (prompt 07), quest harian.

## Deliverables
- `src/server/Services/StageService.luau`, `InventoryService.luau`
- Controller client untuk Story, Inventory, UnitDetail, Onboarding
- Pembaruan `Config/Stages.luau` bila struktur musuh perlu ditambah (tanpa mengubah angka ekonomi)

## Kriteria terima
- Semua aksi divalidasi server; tidak bisa merge unit beda jenis, unit locked, atau unit di tim
- Reward first-clear tidak bisa didapat dua kali (uji dengan replay)
- Progres tersimpan setelah rejoin
- Pemain baru bisa menyelesaikan onboarding tanpa bantuan dalam ≤ 10 menit

## Cara uji
- Profil baru → onboarding → clear 1-1 s.d. 1-3 → level up & merge → rejoin

## Setelah selesai
- Jalankan `prompts/review-security.md` untuk InventoryService & StageService
- Centang ROADMAP
