# Review Trade M6

Review sumber dan pengujian lokal menggunakan dua pemain tiruan, ProfileStore tiruan, dan DataStore tiruan. Trade di server live tetap dinonaktifkan sampai perilaku Roblox diverifikasi di place uji privat.

| Status | Area | Bukti dan batas verifikasi |
|---|---|---|
| Lulus lokal | Remote dan kerahasiaan tawaran | Keenam RemoteFunction memakai rate limit dan validasi server. Event hanya dikirim ke peserta, dengan UID hanya pada sisi milik penerima. |
| Lulus lokal | Persetujuan | Tawaran baru menghapus Ready. Konfirmasi sebelum countdown ditolak. `revision` mengikat consent dan `updateId` mengurutkan snapshot. |
| Lulus lokal | Kepemilikan dan ekonomi | Pemeriksaan ulang pada commit mencakup kepemilikan, 1★, status lock, cooldown, kapasitas, pajak, refund level, dan batas UTC. Pemeriksaan tim pertahanan menunggu model data M7. |
| Lulus lokal | Idempotensi dan pemulihan | Tes tiruan mencakup pembatalan saat pemain keluar, konfirmasi berulang, pemulihan setelah simpan sebagian, dan deteksi UID ganda tanpa penghapusan. |
| Menunggu uji Roblox | Durabilitas dan kebijakan | Verifikasi dua client, `Save` dan `LastSavedData`, pembacaan indeks tanpa cache, audit harian, rejoin, serta hasil `PolicyService` asli di place uji. |

Karena asal pembelian item lama belum tercatat konsisten, seluruh penawaran memerlukan izin Trade dari kedua pemain. Lookup gagal atau data kebijakan tidak lengkap memblokir tindakan. [Pedoman Trade Roblox](https://create.roblox.com/docs/production/monetization/paid-random-items#ispaiditemtradingallowed)
