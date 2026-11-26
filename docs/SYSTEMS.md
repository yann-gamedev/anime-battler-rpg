# SYSTEMS.md — Trade & Perang Wilayah Antar-Asrama

Dua sistem ini **tidak masuk MVP**. Trade = milestone M6, Asrama & Perang Wilayah = M7. Keduanya sensitif: wajib review keamanan (`prompts/review-security.md`) sebelum rilis.

---

## A. TRADE (M6)

### A1. Apa yang bisa di-trade

| Item | Bisa? | Aturan |
|---|---|---|
| Unit Rare/Epic/Legendary | Ya | Hanya **1★**. Saat berpindah: trait dihapus, level reset ke 1 (pengirim dapat refund 80% Gold & XP Scroll yang sudah dipakai) |
| Unit Mythic & limited | Ya | Sama seperti di atas + **cooldown 7 hari** sejak didapat / sejak trade terakhir |
| Skin | Ya | Bebas, tidak terikat unit |
| Unit yang `locked`, sedang di tim pertahanan wilayah, atau sedang cooldown | Tidak | |
| Mata uang apa pun | Tidak | |

Alasan: unit hasil "investasi" (bintang, trait) tidak bisa dibeli dari pemain lain → kekuatan di perang wilayah tetap butuh bermain/upgrade sendiri. Lihat `docs/DECISIONS.md` D-004.

### A2. Syarat pemain
- Level akun ≥ 15 (dari progres story) **dan** `Player.AccountAge` ≥ 7 hari.
- Maks **10 trade selesai per hari**.
- Maks 8 item per sisi per trade.
- Pajak: **500 Gold per sisi** per trade selesai.

### A3. Alur

```
1. A kirim permintaan trade ke B (harus satu server, jarak dekat di lobby / Trading Plaza)
2. B terima → sesi trade dibuat di server (TradeService), id = GUID
3. Kedua pihak menambah/menghapus item → server validasi tiap perubahan & broadcast `TradeUpdated`
4. Setiap perubahan isi → status "Ready" kedua pihak di-reset
5. Keduanya "Ready" → hitung mundur 5 detik (isi terkunci)
6. Keduanya "Confirm" → server menjalankan SWAP ATOMIK
7. Sesi ditutup, log disimpan
```

Batal otomatis jika: salah satu keluar server, sesi > 3 menit, atau item tidak valid.

### A4. Swap atomik (WAJIB, inti anti-dupe)

Di dalam satu fungsi server tanpa yield:
1. Ambil profil A & B yang **aktif & ter-lock** (ProfileStore session). Jika salah satu tidak aktif → batal.
2. Validasi ulang SEMUA item: masih dimiliki, memenuhi A1, tidak di tim pertahanan, tidak cooldown.
3. Validasi Gold pajak kedua pihak.
4. Hapus item dari pemilik lama, tambah ke pemilik baru (UID **tetap sama**), kurangi pajak.
5. Set `source = "trade"`, `tradeCooldownUntil` bila perlu.
6. Tulis log `{tradeId, time, a, b, itemsA, itemsB}` ke DataStore log terpisah (append, untuk investigasi).
7. Tandai sesi selesai sehingga confirm ganda tidak memproses ulang.

Karena unit pindah dengan UID yang sama, jika suatu saat ditemukan UID yang sama di dua profil → itu indikasi dupe dan bisa dilacak dari log.

### A5. UI & anti-penipuan
- Dua panel berdampingan, item lawan selalu terlihat penuh (rarity, nama, ★).
- Peringatan merah jika satu sisi kosong ("Kamu tidak menerima apa pun").
- Hitung mundur dan reset Ready saat isi berubah (A3 langkah 4–5).
- Tidak ada chat bebas di jendela trade di MVP trade; jika ditambah, wajib filter teks.

---

## B. ASRAMA & PERANG WILAYAH (M7)

### B1. Asrama (guild)
- Dibuat dengan 5.000 Gold. Nama & deskripsi difilter `TextService`.
- Maks **30 anggota**. Peran: Ketua, Wakil (maks 3), Anggota.
- Data Asrama disimpan di DataStore terpisah (bukan di profil pemain); profil hanya menyimpan `guildId`.
- Lintas server → pakai `MemoryStoreService` untuk status perang yang sering berubah dan `MessagingService` untuk notifikasi; DataStore untuk data permanen.

### B2. Peta wilayah Realm 1 (6 wilayah)

| ID | Wilayah | Buff untuk Asrama pemilik |
|---|---|---|
| `observatory` | Menara Astronomi | +5% Gold dari stage |
| `library` | Perpustakaan Terlarang | +5% XP unit |
| `arena` | Arena Duel | +10% Asrama Tokens |
| `greenhouse` | Rumah Kaca | +1 Trait Shard dari raid harian |
| `bridge` | Jembatan Awan | +5% Gems quest harian |
| `great_hall` | Aula Agung | Kosmetik bendera Asrama di lobby semua server |

Buff sengaja kecil dan **tidak menambah kekuatan battle**.

### B3. Siklus mingguan (waktu server UTC, dikonversi di UI)

| Hari | Fase |
|---|---|
| Senin 00:00 | Pendaftaran: Asrama memilih ≤ 2 wilayah target. Anggota memasang tim pertahanan |
| Selasa–Sabtu | Fase serangan |
| Minggu | Penghitungan, reward, reset |

Matchmaking: Asrama dikelompokkan ke "bracket" berisi ±8 Asrama dengan kekuatan rata-rata mirip (rata-rata power 10 anggota terkuat).

### B4. Pertahanan
- Setiap wilayah punya **3 slot pertahanan** per Asrama pemilik.
- Setiap anggota boleh menjaga **maks 1 slot** di **maks 1 wilayah** (mencegah satu whale menjaga semuanya).
- Tim pertahanan = snapshot tim (unit dikunci dari trade selama perang).
- HP tim pertahanan **tersimpan** antar serangan (damage menumpuk), pulih penuh saat fase baru.

### B5. Serangan
- Setiap anggota mendapat **3 tiket serangan per hari**. Tiket **tidak bisa dibeli**.
- Serangan = `BattleSim` melawan snapshot pertahanan (deterministik, di server).
- Wilayah direbut saat ketiga slot pertahanan kalah. Asrama penyerang lalu harus memasang pertahanan sendiri.
- Kontribusi tercatat per anggota (serangan, damage, kemenangan) → menentukan bagian reward.

### B6. Reward
- Asrama Tokens per wilayah yang dikuasai di akhir minggu + bonus peringkat bracket.
- Distribusi ke anggota berdasarkan kontribusi, dengan **minimum** untuk semua anggota yang memakai ≥ 1 tiket.
- Toko Asrama: kosmetik eksklusif, bingkai, Gold, Trait Shards (dibatasi per minggu).

### B7. Anti-abuse
- Pemain yang keluar Asrama tidak bisa bergabung ke Asrama lain sampai fase pendaftaran berikutnya.
- Semua hasil serangan dihitung server; client hanya mengirim `{territoryId, slot, teamId}`.
- Rate limit serangan: 1 per 10 detik per pemain.
