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
| D-010 | 2026-11-26 | Banner Limited contoh menampilkan Seraphine sebagai featured, dan Seraphine tetap ada di pool Standar | Prompt 01 meminta contoh featured, sedangkan ECONOMY §2 mencantumkan Seraphine dalam contoh peluang Standar |
| D-011 | 2026-11-26 | Stage awal memakai tiga musuh placeholder per bab dengan level 1–30 mengikuti urutan stage | Prompt 01 mengizinkan musuh sementara. Gold dan XP Scroll per stage menunggu angka reward di task story |
| D-012 | 2026-11-26 | ProfileStore dipasang melalui `lm-loleris/profilestore@1.0.3` di `ServerPackages` | Paket server Wally untuk dependency yang sudah disetujui pada D-008 |
| D-013 | 2026-11-26 | Sebelum penyimpanan persisten pertama, tim v1 memakai sembilan slot string dengan `""` untuk sel kosong | ProfileStore mensyaratkan array numerik tanpa celah. SessionStore sebelumnya hanya menyimpan data di memori |
| D-014 | 2026-11-26 | BattleSim memakai xorshift32 dengan state terpisah per battle. Seed dinormalisasi ke 32 bit, dan state nol memakai konstanta nonnol | Hasil replay dapat diuji dengan seed yang sama tanpa bergantung pada RNG global |
| D-015 | 2026-11-26 | Jarak memakai Manhattan pada papan gabungan. Range tetap sesuai definisi kelas. Tiap Familiar yang memenuhi sinergi dapat bangkit satu kali | Menetapkan aturan grid dan interpretasi revive untuk implementasi awal |
| D-016 | 2026-11-26 | Parameter uji awal: langkah tiap 5 tick, slow sinergi Es 1 detik, reflect Garrick 3 detik, buff Aurelian 5 detik, radius Elodie dan Umbra 1 sel, dan roh Morvaine memakai 25% stat pemanggil | Dokumen desain belum menetapkan nilai ini. Nilai runtime ada di Config untuk penyesuaian balancing |
| D-017 | 2026-11-26 | `StartTestBattle` memerlukan Studio dan UserId admin. Replay menghentikan jam simulasi pada tick cinematic | Membatasi jalur uji dan mempertahankan sinkronisasi event saat cinematic dilewati |
| D-018 | 2026-11-26 | Tombol Start battle di Team Board membuka latihan tanpa reward melawan susunan stage 1-1. Perubahan tim disimpan sebelum latihan dimulai | Memberi alur battle yang dapat dimainkan sebelum progres story tersedia dan menjaga hasil berdasarkan formasi yang divalidasi server |

## Keputusan terbuka (butuh manusia)

| ID | Pertanyaan | Opsi |
|---|---|---|
| D-OPEN-1 | Pengganti reroll trait untuk pemain dengan `ArePaidRandomItemsRestricted` | (a) Pilih trait tier Biasa/Langka langsung dengan Gold; (b) Trait hanya dari drop gameplay; (c) Toko trait tetap dengan Gems |
| D-OPEN-2 | Nama final game | — |
| D-OPEN-3 | Harga final semua produk Robux | Lihat `docs/ECONOMY.md` §5 |
| D-OPEN-4 | Pembagian peran 2 anggota tim (art/UI vs sistem) | — |
