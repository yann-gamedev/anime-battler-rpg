# Review Keamanan

## Tujuan
Mengaudit perubahan (atau service yang disebut) terhadap exploit umum Roblox sebelum task ditandai selesai. **Hanya laporan** — jangan memperbaiki apa pun kecuali diminta.

## Input
Sebutkan target: `Review keamanan untuk <ServiceName>` atau `untuk diff branch ini`.

## Konteks
- `docs/RULES.md` §1–4
- Kode target + semua remote yang ia daftarkan

## Checklist (periksa SETIAP remote handler)

**Kepercayaan client**
- [ ] Apakah ada nilai dari client yang dipakai sebagai hasil (damage, reward, odds, harga, jumlah)?
- [ ] Apakah ada data profil yang dibaca dari argumen client, bukan dari server?

**Validasi input**
- [ ] Tipe setiap argumen dicek? (string vs number vs table)
- [ ] Angka: integer? rentang? NaN (`x ~= x`)? inf? negatif?
- [ ] String: panjang maksimum? set nilai yang diizinkan?
- [ ] Tabel: jumlah elemen dibatasi? elemen duplikat? kunci tak terduga diabaikan?

**Kepemilikan & state**
- [ ] UID/ID yang dikirim benar milik pemain?
- [ ] Item yang sedang dipakai di tempat lain (tim, trade, pertahanan) ditolak?
- [ ] Ada yield (`task.wait`, panggilan Async) di antara pengecekan saldo dan pengurangan saldo? → race condition
- [ ] Bisa dipanggil berulang cepat untuk mendapatkan hadiah ganda?

**Rate limit & DoS**
- [ ] Rate limiter dipasang?
- [ ] Ada loop/alokasi yang ukurannya ditentukan client?

**Uang & kebijakan**
- [ ] `ProcessReceipt` idempoten?
- [ ] Item acak berbayar cek `ArePaidRandomItemsRestricted` di server & fail-closed?
- [ ] Odds UI dari config yang sama dengan logika?

**Data**
- [ ] Penulisan DataStore hanya oleh pemilik di RULES §3?
- [ ] Mata uang bisa negatif dalam skenario tertentu?
- [ ] Data yang dikirim ke client tidak bocorkan data pemain lain?

## Output
Tabel temuan, diurutkan paling parah:

| # | Tingkat (Kritis/Tinggi/Sedang/Rendah) | File:baris | Masalah | Skenario exploit | Saran perbaikan |
|---|---|---|---|---|---|

Jika tidak ada temuan, tulis "Tidak ditemukan masalah" + daftar hal yang sudah diperiksa.
