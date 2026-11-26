# 04 — BattleService & Battle View

## Tujuan
Menghubungkan BattleSim ke server (validasi, reward) dan memutar hasilnya di client sebagai battle yang terlihat hidup, dengan model placeholder.

## Konteks
- `docs/ARCHITECTURE.md` §4, §5
- `docs/RULES.md` §1, §2, §7
- `docs/GDD.md` §5 (ultimate cinematic), §6

## Scope
Dikerjakan:
- `BattleService`: fungsi internal `runPve(player, teamUnits, enemyDef): BattleResult` — membangun input dari profil (bukan dari data client), memanggil BattleSim
- Remote `StartTestBattle(teamId)` (sementara, hanya Studio/admin) → mengirim `BattleResult` ke client lewat `BattleResult` event
- Arena battle placeholder di workspace (dibuat oleh `studio/world/build_arena.luau`): 2 papan 3×3 berhadapan
- `BattleViewController`: spawn model placeholder (Part berwarna sesuai elemen + BillboardGui nama & HP bar), memutar log berdasarkan `t` (10 tick = 1 detik), tween gerak & serangan sederhana, angka damage melayang, efek mati
- Ultimate: kamera zoom singkat untuk Legendary/Mythic (≤ 3 detik), tombol **Skip** dan setting "matikan cinematic"
- Tombol 2× speed (hanya visual di client; cek gamepass dilakukan nanti di prompt 09 — sementara selalu aktif di Studio)
- Layar hasil (menang/kalah/seri)

TIDAK dikerjakan: Team Board, story, reward sungguhan (cukup log di server).

## Deliverables
- `src/server/Services/BattleService.luau`
- `src/client/Controllers/BattleViewController.luau` (+ submodul jika > 400 baris)
- `studio/world/build_arena.luau`
- Remote baru di `Remotes.luau`

## Kriteria terima
- Client tidak pernah mengirim stat/hasil; hanya `teamId`
- Replay sinkron dengan log (unit yang mati di log hilang di layar pada waktu yang sama ±1 tick)
- Tidak ada memory leak: semua model & koneksi battle dibersihkan setelah hasil ditutup
- FPS stabil di emulator HP Studio (Device Emulation) untuk 6 vs 6

## Cara uji
1. Jalankan `studio/world/build_arena.luau`
2. Play, panggil `StartTestBattle` lewat perintah admin
3. Uji Skip ultimate & 2× speed

## Setelah selesai
- Centang ROADMAP
