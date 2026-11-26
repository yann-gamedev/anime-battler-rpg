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
| D-020 | 2026-11-26 | Progres story menambah material XP Scroll dan status progres melalui rekonsiliasi profil v1. Tutorial memberi 10 tiket sekali pada kemenangan, dan kemenangan 1-3 membuka lobby | Menggunakan mata uang dan flag onboarding yang sudah ada. Summon sungguhan mengikuti prompt 07 |
| D-021 | 2026-11-26 | Gold/XP Scroll, biaya Gold merge, dan ambang slot papan memakai nilai sementara di `Config/Progression.luau`. Stage 1-1 sampai 1-3 memakai musuh pengantar (menggantikan D-011 untuk ketiga stage itu) | Dokumen ekonomi belum menentukan nilai ini. Simulasi menemukan lonjakan kesulitan mulai 1-4 |
| D-022 | 2026-11-26 | Summon Gems terikat pada peluang terakhir yang dikirim server untuk banner dan state pity pemain. UI menerima peluang aktual untuk 1× dan peluang marginal tiap posisi draw 10× | Peluang yang ditampilkan mencakup perubahan pity dan jaminan selama batch |
| D-023 | 2026-11-26 | `guaranteedFeatured` ditambahkan ke record pity v1. Banner Limited contoh aktif 26 November sampai sebelum 10 Desember 2026 UTC | Menyimpan jaminan featured berikutnya dan membatasi rotasi contoh ke 14 hari |
| D-024 | 2026-11-26 | PolicyService sukses di-cache selama sesi. Kegagalan lookup memblokir Gems dan dapat dicoba kembali setelah 60 detik | Menjaga pembatasan paid random items saat layanan kebijakan tidak merespons |
| D-025 | 2026-11-26 | Pemain restricted dapat memilih trait Biasa atau Langka langsung dengan Gold (menutup D-OPEN-1) | Jalur deterministik memakai Gold dari gameplay. Harga balancing awal 200 Gold untuk Biasa dan 600 Gold untuk Langka ada di `Config/Traits.luau` |
| D-026 | 2026-11-26 | Grant dari Developer Product, bonus pembelian pertama, dan marker receipt dikomit bersama. Receipt diakui setelah marker muncul di `LastSavedData` | Retry tidak menggandakan hadiah dan Roblox dapat mengirim ulang receipt yang belum tersimpan |
| D-027 | 2026-11-26 | Toko Akademi memakai harga tetap awal 150 Gems untuk Kael, 300 Gems untuk Selene, dan 250 Gems untuk skin Academy Scholar. Setiap entri dibeli satu kali per akun dan tersedia untuk pemain restricted | Jalur pembelian langsung dengan biaya dan isi yang diketahui sebelum konfirmasi |
| D-028 | 2026-11-26 | SKU Premium terikat ke ID musim. Musim contoh s1 berdurasi 28 hari dengan 30 tier. Klaim hanya selama musim aktif. Bingkai Akademi dari tier 30 Premium tetap dimiliki setelah musim berakhir | Menjaga kredit dari receipt tertunda pada musim asal dan memberi batas waktu klaim yang bisa ditampilkan di UI |
| D-029 | 2026-11-26 | Quest harian reset 00:00 UTC dan quest mingguan reset Senin 00:00 UTC. Profil menyimpan satu periode aktif dari setiap jenis | Reset seragam lintas zona waktu dan ukuran record profil tetap terbatas |
| D-030 | 2026-11-26 | Mata uang, XP Battle Pass aktif, dan status klaim quest disimpan dalam satu mutasi. Semua quest dapat diselesaikan tanpa summon | Retry aman dan pemain restricted mendapat sumber Gems yang sama |
| D-031 | 2026-11-26 | Raid terbuka setelah Story 1-3. Satu percobaan gratis per hari UTC memberi reward tier tertinggi berdasarkan damage server yang dibatasi HP boss | Aktivitas harian tanpa pembelian. Target tier tertinggi 50 Gems di `Config/Raids.luau` |
| D-032 | 2026-11-26 | Server mereplikasi satu model pajangan ringan dengan skin placeholder. Client menggerakkan idle dan menggambar aura VIP | Tampilan bisa dilihat pemain lain dengan biaya rendering yang bisa dikurangi lewat Low graphics |

## Keputusan terbuka (butuh manusia)

| ID | Pertanyaan | Opsi |
|---|---|---|
| D-OPEN-1 | Pengganti reroll trait untuk pemain dengan `ArePaidRandomItemsRestricted` | Diputuskan di D-025 |
| D-OPEN-2 | Nama final game | — |
| D-OPEN-3 | Harga final semua produk Robux | Lihat `docs/ECONOMY.md` §5 |
| D-OPEN-4 | Pembagian peran 2 anggota tim (art/UI vs sistem) | — |
