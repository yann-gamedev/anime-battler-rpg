# 12 — Asrama & Perang Wilayah

## Tujuan
Membangun guild (Asrama) lintas server dan perang wilayah mingguan async yang memberi whale alasan berinvestasi tanpa membuat pemain gratis tidak berguna.

## Konteks
- `docs/SYSTEMS.md` bagian B (**wajib baca penuh**)
- `docs/ARCHITECTURE.md` §5 (sim deterministik)
- `docs/RULES.md` §1–3, §5
- Dokumentasi Roblox `MemoryStoreService`, `MessagingService`, batas kuota DataStore (verifikasi angka terbaru)

## Scope
Karena besar, kerjakan dalam 3 sub-task (sesi terpisah):

**12a — GuildService**
- Buat/gabung/keluar/kick/promosi Asrama, nama & deskripsi difilter `TextService`
- Data Asrama di DataStore `Guilds` (bukan di profil); profil hanya `guildId`
- Penguncian tulis Asrama (UpdateAsync + versi) agar dua server tidak saling timpa
- UI Asrama (anggota, peran, undangan)

**12b — TerritoryService**
- Siklus mingguan SYSTEMS B3 (UTC), bracket ±8 Asrama
- Pendaftaran target, pemasangan tim pertahanan (B4) — snapshot tim & kunci unit dari trade
- Serangan (B5): tiket 3/hari, `BattleSim` melawan snapshot, HP pertahanan tersimpan, perebutan wilayah
- Status perang yang sering berubah di `MemoryStoreService`, hasil permanen di DataStore
- Notifikasi lintas server via `MessagingService` ("Perpustakaan direbut!")

**12c — Reward & UI**
- Penghitungan Minggu, distribusi Asrama Tokens berbasis kontribusi + minimum (B6), Toko Asrama
- Peta wilayah kampus di UI, riwayat serangan, papan kontribusi

## Deliverables
- `src/server/Services/GuildService.luau`, `TerritoryService.luau` (+ submodul)
- Config: `Territories.luau` (sudah ada), `GuildWar.luau` (jadwal, batas)
- Controller: `GuildController.luau`, `TerritoryMapController.luau`
- Tests untuk logika murni: bracket, distribusi reward, aturan slot pertahanan

## Kriteria terima
- Satu pemain tidak bisa menjaga > 1 slot; tiket tidak bisa dibeli atau ditambah lewat remote
- Dua server menyerang wilayah sama bersamaan → hasil konsisten (tidak ada dua pemilik)
- Kegagalan MemoryStore/DataStore ditangani (retry dengan backoff, tidak menghilangkan kontribusi)
- Buff wilayah tidak mengubah stat battle

## Setelah selesai
- **Wajib** `prompts/review-security.md`; uji beban sederhana; centang ROADMAP
