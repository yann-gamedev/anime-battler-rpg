# GDD.md — Game Design Document

> Nama game masih **placeholder: "Battler RPG"**. Nama final dicatat di `docs/DECISIONS.md`.

## 1. Visi

Auto battler bergaya anime dengan karakter original, di mana pemain merasa jadi **Summoner** yang membangun pasukan penyihir terkuat dan membawa Asramanya menguasai kampus. Seru ditonton (ultimate cinematic), dalam secara strategi (sinergi), dan hidup secara sosial (trade, perang Asrama).

## 2. Pilar desain

1. **Mudah dimulai, dalam dikuasai** — 1 menit pertama sudah battle; sinergi baru terasa di jam ke-2.
2. **Pamer itu penting** — unit langka, skin, dan efek ultimate terlihat oleh pemain lain di lobby dan di perang wilayah.
3. **Pemain gratis tetap bermakna** — mereka dibutuhkan Asrama (tiket serangan) dan bisa mendapat semua unit non-limited lewat bermain.
4. **Update rutin** — banner dan event mingguan, Realm baru per ekspansi.

## 3. Target pemain

- Usia utama 13–24, mobile, suka anime dan koleksi.
- Segmen belanja: whale (banner limited, reroll trait, skin), menengah (battle pass), kecil (gamepass sekali beli).
- Pemain kompetitif: ladder & perang wilayah. Pemain kasual: story, koleksi, trade.

## 4. Setting — Realm 1: Akademi Arcanum

Akademi sihir terapung di atas laut awan. Murid dibagi ke beberapa **Asrama** yang bersaing memperebutkan wilayah kampus. Pemain adalah Summoner muda yang bisa memanggil murid, profesor, dan familiar dari lingkaran rune.

Ekspansi berikutnya menambah Realm baru (contoh ide: kerajaan samurai langit, kota cyberpunk). Setiap Realm membawa unit, elemen/status baru, story, dan wilayah baru.

## 5. Gaya visual & audio

- **Low-poly cel-shaded**: warna flat, outline tebal (pakai `Highlight` atau mesh outline terbalik), palet cerah per elemen.
- Proporsi karakter chibi-ish (kepala besar) → mudah dibaca di layar HP dan ringan.
- VFX sihir sebagai "nilai jual": lingkaran rune, beam, partikel elemen.
- **Ultimate cinematic** untuk Legendary & Mythic: kamera zoom + pose + efek 2–3 detik, bisa di-skip, bisa dimatikan di Settings.
- Musik orkestra ringan + SFX sihir; setiap Mythic punya voice line pendek (original).

## 6. Core loop (per sesi 5–15 menit)

```
Susun tim di papan 3×3
      ↓
Battle otomatis (≈30–60 detik)
      ↓
Reward: Gold, XP Scroll, Gems, Trait Shards
      ↓
Upgrade (level, stars, trait) / Summon
      ↓
Kembali menyusun tim (tantangan lebih berat)
```

### Papan & battle

- Papan pemain 3×3 (9 sel), maksimal unit diturunkan: **3 di awal → 6** (terbuka lewat progres story, BUKAN lewat pembelian).
- Baris depan = jarak dekat, baris belakang = aman dari melee sampai barisan depan habis (kecuali Assassin).
- Setiap unit menyerang otomatis sesuai `spd` dan `range`. Setiap serangan & terkena damage mengisi **Mana**; Mana 100 → ultimate.
- Sinergi aktif berdasarkan unit yang DITURUNKAN (lihat `docs/UNITS.md`).
- Battle berakhir saat satu sisi habis atau 90 detik (seri = kalah untuk penyerang).

## 7. Meta loop (harian/mingguan)

| Sistem | Ringkas | Milestone |
|---|---|---|
| Story | 3 bab × 10 stage di Realm 1, bintang 1–3 per stage | MVP |
| Boss Raid | Boss harian dengan HP besar, reward berdasar damage | MVP |
| Summon | Banner Standar + Banner Limited (rotasi 2 minggu) | MVP |
| Trait | Reroll trait dengan Trait Shards | MVP |
| Quest harian & mingguan | Sumber Gems utama pemain gratis | MVP |
| Battle Pass | Musim 4 minggu, jalur gratis & premium | MVP+ |
| Lobby sosial | Pemain lain terlihat bersama unit pajangannya | MVP |
| Trade | Tukar unit dasar & skin antar pemain | M6 |
| Asrama & Perang Wilayah | Guild + perebutan wilayah mingguan async | M7 |
| PvP Ladder async | Lawan snapshot tim pemain lain | M7+ |

Detail Trade & Perang Wilayah: `docs/SYSTEMS.md`. Angka ekonomi: `docs/ECONOMY.md`.

## 8. Progres unit

- **Level** 1–60, naik dengan XP Scroll + Gold.
- **Stars** 1★–5★, naik dengan menggabungkan duplikat unit yang sama. Setiap bintang: +20% stat dasar. Bintang 3 dan 5 mengubah tampilan ultimate (efek lebih besar).
- **Trait**: satu slot per unit, di-reroll dengan Trait Shards. Odds di `docs/UNITS.md`.
- **Skin**: kosmetik saja, tidak mengubah stat.

## 9. Monetisasi (ringkas)

| Produk | Jenis Roblox | Catatan |
|---|---|---|
| Paket Gems | Developer Product | Sumber utama |
| Paket Trait Shards | Developer Product | Item acak berbayar secara tidak langsung → odds wajib tampil |
| Skin unit / efek ultimate | Developer Product (toko langsung) | Bisa di-trade |
| Battle Pass Premium | Developer Product per musim | |
| 2× Battle Speed | Gamepass | Kenyamanan |
| Auto-Replay Stage | Gamepass | Kenyamanan, hanya stage yang sudah 3 bintang |
| Preset Tim Tambahan | Gamepass | Slot simpan tim, bukan slot papan |
| VIP Lobby Aura | Gamepass | Kosmetik pamer |

Hal yang TIDAK dijual: slot papan tambahan, tiket serangan perang wilayah, mata uang yang bisa di-trade.

## 10. Layar UI (MVP)

1. Main Menu (sudah ada draft di `build_main_menu.luau`)
2. Lobby (hub 3D: portal Story, altar Summon, papan pengumuman, NPC toko)
3. Team Board (drag unit ke papan 3×3, indikator sinergi aktif)
4. Battle View (replay battle, tombol 2× speed, skip ultimate)
5. Hasil battle (bintang, reward)
6. Inventory unit (filter rarity/elemen/status, detail unit, upgrade, merge)
7. Summon (banner, tombol 1×/10×, **tombol "Lihat Odds" wajib**, pity counter)
8. Trait reroll (odds tampil di layar yang sama)
9. Toko (Gems, skin, gamepass)
10. Quest & Battle Pass
11. Settings (musik, SFX, matikan cinematic, grafis rendah)

Semua UI dirancang **mobile-first**: tombol minimal 44×44 px, teks minimal 14 pt, tanpa hover-only interaction.

## 11. Onboarding (10 menit pertama)

1. Cutscene singkat (≤20 detik, skip-able) → pemain memanggil familiar pertama.
2. Battle tutorial dengan 3 unit gratis.
3. Summon gratis 10× (dijamin minimal 1 Epic) → mengenalkan banner & odds.
4. Mengenalkan sinergi: "turunkan 2 unit Api".
5. Stage 1-1 s.d. 1-3, lalu lobby terbuka.

## 12. Metrik keberhasilan (soft launch)

| Metrik | Target awal |
|---|---|
| D1 retention | ≥ 25% |
| D7 retention | ≥ 8% |
| Rata-rata sesi | ≥ 12 menit |
| Konversi pembayar | ≥ 2% |
| Crash/error server | ≈ 0 error DataStore per 1.000 sesi |

Dicatat lewat `AnalyticsService` (Roblox Analytics custom events + funnel onboarding).
