# DECISIONS.md — Log Keputusan

Format: `D-NNN | tanggal | keputusan | alasan`. Jangan hapus entri lama; jika berubah, tambahkan entri baru yang menggantikan ("menggantikan D-00X").

## Keputusan

| ID | Tanggal | Keputusan | Alasan |
|---|---|---|---|
| D-001 | 2026-11-26 | Genre: auto battler RPG bertema anime, karakter **original** | Tren auto battler naik; karakter original menghindari takedown IP dan membangun IP sendiri |
| D-002 | 2026-11-26 | Realm 1 = Akademi Sihir Arcanum; Realm lain lewat ekspansi | Tema cocok dengan guild = Asrama |
| D-003 | 2026-11-26 | Gaya visual low-poly cel-shaded, mobile-first | Ringan di HP, konsisten saat dibuat bertahap |
| D-004 | 2026-11-26 | Trade hanya unit 1★ (trait dihapus, level reset) + skin; mata uang tidak bisa di-trade | Mencegah pay-to-win lewat pasar & jual-beli uang asli |
| D-005 | 2026-11-26 | Fitur sosial utama: Trade (M6) dan Perang Wilayah antar-Asrama (M7), keduanya setelah MVP | Bug ekonomi di awal lebih fatal daripada rilis tanpa fitur |
| D-006 | 2026-11-26 | Battle = simulasi deterministik di server, client hanya replay event log | Anti-cheat, dan sim yang sama dipakai PvP async & perang wilayah |
| D-007 | 2026-11-26 | Kode dikelola dengan Rojo + git; Studio build script hanya untuk membangun instance | Kode bisa di-review, di-diff, dan dikerjakan agent |
| D-008 | 2026-11-26 | Data pemain memakai ProfileStore | Session locking mencegah dupe & kehilangan data |
| D-009 | 2026-11-26 | Slot papan & tiket serangan tidak dijual | Pemain gratis tetap bermakna di mode kompetitif |

## Keputusan terbuka (butuh manusia)

| ID | Pertanyaan | Opsi |
|---|---|---|
| D-OPEN-1 | Pengganti reroll trait untuk pemain dengan `ArePaidRandomItemsRestricted` | (a) Pilih trait tier Biasa/Langka langsung dengan Gold; (b) Trait hanya dari drop gameplay; (c) Toko trait tetap dengan Gems |
| D-OPEN-2 | Nama final game | — |
| D-OPEN-3 | Harga final semua produk Robux | Lihat `docs/ECONOMY.md` §5 |
| D-OPEN-4 | Pembagian peran 2 anggota tim (art/UI vs sistem) | — |
