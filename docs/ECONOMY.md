# ECONOMY.md — Mata Uang, Banner, Harga

> **Semua harga Robux dan odds adalah PLACEHOLDER.** Agent dilarang mengubahnya tanpa instruksi manusia (lihat RULES §9). Nilai runtime ada di `src/shared/Config/Economy.luau`, `Banners.luau`, `Traits.luau`, `Products.luau`.

## 1. Mata uang

| Mata uang | Sumber | Dipakai untuk | Bisa dibeli Robux? | Bisa di-trade? |
|---|---|---|---|---|
| **Gold** | Stage, raid, jual unit | Level up, pajak trade, merge | Tidak | Tidak |
| **Gems** | Quest, first clear, login, event, **Robux** | Summon, battle pass tier skip | Ya | **Tidak** |
| **Trait Shards** | Raid, quest mingguan, bongkar unit Epic+, **Robux** | Reroll trait | Ya | Tidak |
| **Summon Tickets** | Tutorial, event, milestone story (**tidak pernah dijual**) | 1 tiket = 1× summon | Tidak | Tidak |
| **Asrama Tokens** | Perang wilayah | Toko Asrama (kosmetik, Gold, Shards) | Tidak | Tidak |

Tidak ada mata uang yang bisa di-trade → menekan jual-beli uang asli dan menjaga monetisasi.

## 2. Banner

### Biaya
- 1× summon = **50 Gems**
- 10× summon = **450 Gems**, dijamin minimal 1 Epic atau lebih

### Odds dasar (Banner Standar & Limited)

| Rarity | Peluang |
|---|---|
| Rare | 70.0% |
| Epic | 25.0% |
| Legendary | 4.5% |
| Mythic | 0.5% |

Di dalam satu rarity, unit dipilih rata, KECUALI di Banner Limited: unit unggulan (featured) memegang **50%** dari peluang rarity-nya.

UI wajib menampilkan peluang **per rarity dan per unit** (contoh: Mythic 0.5% → Seraphine 0.25%, Umbra 0.25%).

### Pity (per banner, disimpan di `profile.pity[bannerId]`)
- **Legendary+**: jika 50 summon berturut-turut tanpa Legendary/Mythic, summon ke-50 dijamin Legendary (atau Mythic sesuai odds relatif).
- **Mythic (hard pity)**: summon ke-200 tanpa Mythic → dijamin Mythic.
- **Limited 50/50**: jika Mythic yang didapat bukan unit featured, Mythic berikutnya dijamin featured.
- Counter pity ditampilkan di UI.

### Rotasi
- Banner Standar: permanen, berisi semua unit non-limited.
- Banner Limited: rotasi 14 hari, 1 unit featured. Unit limited boleh masuk Banner Standar setelah ≥ 3 bulan (keputusan per unit dicatat di DECISIONS).

### Jalur non-acak (wajib ada untuk `ArePaidRandomItemsRestricted`)
- **Toko Akademi**: unit Rare/Epic tertentu dan semua skin dibeli langsung (harga tetap) dengan Gems/Robux.
- Pemain dengan `ArePaidRandomItemsRestricted = true`:
  - **Summon dengan Gems diblok seluruhnya** (Gems bisa dibeli Robux, jadi summon Gems = item acak berbayar walau Gems-nya didapat gratis). Tombol disembunyikan, server menolak.
  - **Reroll trait dengan Trait Shards diblok** dengan alasan yang sama.
  - Summon memakai **Tiket Summon Gratis** (hanya dari gameplay, tidak pernah dijual) tetap boleh.
  - Pengganti reroll trait untuk pemain ini masih **keputusan terbuka** (lihat DECISIONS D-OPEN-1).
  - Verifikasi interpretasi ini dengan dokumen kebijakan Roblox terbaru sebelum rilis.

## 3. Pendapatan Gems pemain gratis (target)

| Sumber | Gems |
|---|---|
| Login harian | 20/hari |
| Quest harian (semua) | 120/hari |
| Boss raid harian | ~50/hari |
| Quest mingguan | 400/minggu |
| First clear 3★ per stage | 30 × 30 stage = 900 sekali |
| Battle pass jalur gratis | ~1.000/musim |

≈ **250 Gems/hari** → satu 10× summon tiap ~2 hari. Target: pemain gratis aktif mendapat 1 Legendary per ~2 minggu.

## 4. Progres unit

| Hal | Biaya |
|---|---|
| Level n → n+1 | `round(50 × n^1.5)` Gold + XP Scroll |
| 1★ → 2★ | 1 duplikat |
| 2★ → 3★ | 2 duplikat |
| 3★ → 4★ | 3 duplikat |
| 4★ → 5★ | 4 duplikat (total 10) |
| Bongkar unit | Rare 200 Gold · Epic 600 Gold + 1 Shard · Legendary 2.000 Gold + 5 Shards · Mythic tidak bisa dibongkar (harus konfirmasi khusus jika nanti diizinkan) |

## 5. Produk Robux (PLACEHOLDER)

### Developer Products

| ID config | Isi | Harga (R$) | Catatan |
|---|---|---|---|
| `gems_s` | 300 Gems | 100 | |
| `gems_m` | 1.300 Gems | 400 | |
| `gems_l` | 2.800 Gems | 800 | |
| `gems_xl` | 6.200 Gems | 1.700 | |
| `gems_xxl` | 17.500 Gems | 4.500 | |
| `shards_s` | 30 Trait Shards | 200 | Termasuk item acak berbayar (tidak langsung) |
| `pass_premium` | Battle Pass Premium musim ini | 800 | |
| `skin_*` | Skin unit | 300–1.200 | Toko langsung, non-acak |

Bonus pembelian pertama: Gems ×2 per paket, sekali per paket per akun.

### Gamepass

| ID config | Fungsi | Harga (R$) |
|---|---|---|
| `gp_speed2x` | Battle 2× speed | 150 |
| `gp_autoreplay` | Auto-replay stage yang sudah 3★ | 300 |
| `gp_presets` | +6 preset tim tersimpan | 100 |
| `gp_vip_aura` | Aura VIP di lobby | 400 |

## 6. Battle Pass

- Musim 28 hari, 30 tier, XP dari quest & battle.
- Gratis: Gold, Shards, ~1.000 Gems, 1 unit Epic pilihan.
- Premium: tambahan Gems, Shards, 1 skin eksklusif musim, bingkai profil.
- Tidak ada unit kompetitif yang HANYA ada di premium.

## 7. Batasan anti-inflasi

- Gold maksimum dari stage replay: berkurang 50% setelah 30 replay/hari (soft cap).
- Maks 10 trade/hari per pemain (lihat SYSTEMS).
- Semua pemberian mata uang di-log oleh `AnalyticsService` (sumber & jumlah) untuk memantau ekonomi.
