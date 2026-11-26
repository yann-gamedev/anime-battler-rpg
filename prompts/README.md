# prompts/ — Cara Memakai

Setiap file adalah **satu task** untuk agent. Kerjakan berurutan sesuai `docs/ROADMAP.md`.

## Cara pakai di Claude Code

```
> Kerjakan prompts/03-battle-sim.md
```

Agent akan membaca `AGENTS.md` (otomatis lewat CLAUDE.md), lalu dokumen di bagian **Konteks** prompt.

Tips:
- Satu prompt per sesi/branch. Mulai sesi baru (`/clear`) di antara task besar agar konteks bersih.
- Untuk task yang menyentuh > 3 file, minta agent membuat rencana dulu (plan mode).
- Setelah task sensitif (02, 07, 08, 09, 11, 12), jalankan `prompts/review-security.md`.
- Jika agent bertanya soal keputusan desain, jawab lalu catat di `docs/DECISIONS.md`.

## Daftar

| File | Milestone | Isi |
|---|---|---|
| `00-setup.md` | M0 | Toolchain, Rojo tree, skeleton bootstrap |
| `01-types-config.md` | M1 | Tipe & semua config dari dokumen |
| `02-data-service.md` | M1 | ProfileStore, template, migrasi, API mutasi |
| `03-battle-sim.md` | M2 | Simulasi battle deterministik + test |
| `04-battle-view.md` | M2 | BattleService + replay di client |
| `05-ui-team-board.md` | M3 | Fondasi UI, Main Menu, Team Board |
| `06-story-progression.md` | M3 | Story, reward, level, merge, inventory |
| `07-summon-banner.md` | M4 | Banner, pity, odds, ComplianceService |
| `08-traits.md` | M4 | Trait & reroll |
| `09-monetization.md` | M4 | Produk Robux, gamepass, toko |
| `10-lobby-quests.md` | M5 | Lobby, quest, raid, analytics |
| `11-trade.md` | M6 | Trade |
| `12-guild-territory.md` | M7 | Asrama & perang wilayah |
| `new-unit.md` | berulang | Menambah unit |
| `bugfix.md` | berulang | Perbaikan bug |
| `balance-pass.md` | berulang | Penyesuaian angka |
| `review-security.md` | berulang | Audit keamanan |

## Format setiap prompt

```
# NN — Judul
## Tujuan        satu paragraf
## Konteks       dokumen yang wajib dibaca
## Scope         yang dikerjakan / TIDAK dikerjakan
## Deliverables  daftar file
## Kriteria terima
## Cara uji
## Setelah selesai
```

Saat membuat prompt baru, ikuti format ini.
