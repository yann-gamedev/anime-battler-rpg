# UNITS.md — Unit, Sinergi, Trait (Realm 1)

> Semua angka adalah **nilai awal untuk diuji**. Perubahan angka dicatat di `docs/DECISIONS.md`.
> Semua karakter ORIGINAL. Jangan mengganti dengan karakter dari IP lain.

## 1. Atribut

| Atribut | Arti |
|---|---|
| `hp` | Nyawa |
| `atk` | Damage dasar per serangan |
| `def` | Mengurangi damage: `damage = atk * 100 / (100 + def)` |
| `spd` | Serangan per detik |
| `range` | Jangkauan dalam sel (1 = melee) |
| Mana | 0–100. +10 per serangan, +5 per terkena serangan. Penuh → ultimate, reset ke 0 |
| Crit | Default 5% peluang, 150% damage |

### Pengali rarity (dikalikan ke `base`)

| Rarity | Pengali | Warna UI |
|---|---|---|
| Rare | 1.00 | Biru |
| Epic | 1.25 | Ungu |
| Legendary | 1.55 | Emas |
| Mythic | 1.90 | Merah-pelangi |

Stat akhir = `base × pengaliRarity × (1 + 0.20 × (stars − 1)) × (1 + 0.03 × (level − 1)) × bonusTrait × bonusSinergi`

## 2. Kelas

| Kelas | Peran | Perilaku targeting |
|---|---|---|
| Tank | Menahan damage | Musuh terdekat; ultimate biasanya taunt/perisai |
| Mage | Damage area | Musuh dengan HP tertinggi dalam jangkauan |
| Assassin | Burst ke barisan belakang | Awal battle lompat ke musuh barisan belakang dengan HP terendah |
| Support | Heal/buff | Menyerang terdekat; ultimate ke sekutu HP terendah |
| Summoner | Memanggil unit kecil | Familiar panggilan tidak mengisi slot papan |

## 3. Daftar unit awal (15)

| ID | Nama | Rarity | Kelas | Elemen | Status | hp | atk | def | spd | range | Ultimate |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `kael` | Kael Ardent | Rare | Mage | Api | Murid | 520 | 64 | 18 | 0.9 | 3 | **Flare Burst** — bola api, 180% atk area 1 sel |
| `mira` | Mira Frostwell | Rare | Support | Es | Murid | 600 | 40 | 25 | 0.8 | 3 | **Frost Veil** — perisai 20% hp ke 2 sekutu terlemah |
| `dorin` | Dorin Voltz | Rare | Assassin | Petir | Murid | 480 | 72 | 15 | 1.2 | 1 | **Static Dash** — 3 tebasan 70% atk, setrum 0.5 dtk |
| `brutus` | Golem Rimewall | Rare | Tank | Es | Familiar | 950 | 38 | 45 | 0.6 | 1 | **Glacier Guard** — taunt 3 dtk, −30% damage diterima |
| `pip` | Pip si Burung Bara | Rare | Summoner | Api | Familiar | 450 | 45 | 15 | 1.0 | 3 | **Ember Flock** — memanggil 2 burung bara (25% stat Pip) selama 8 dtk |
| `selene` | Selene Brightvale | Epic | Support | Cahaya | Murid | 640 | 42 | 28 | 0.8 | 3 | **Dawn Hymn** — heal semua sekutu 18% hp maks |
| `garrick` | Garrick Ironward | Epic | Tank | Petir | Murid | 1000 | 46 | 50 | 0.7 | 1 | **Thunder Bulwark** — perisai diri 30% hp, pantulkan 20% damage |
| `nyx` | Nyx Thorne | Epic | Assassin | Bayangan | Murid | 500 | 80 | 16 | 1.1 | 1 | **Umbral Step** — teleport, 260% atk ke target terlemah |
| `elodie` | Elodie Quill | Epic | Mage | Es | Murid | 540 | 66 | 18 | 0.85 | 3 | **Archive Blizzard** — 4 detik badai, slow 30% di area |
| `ignis` | Anjing Bara Ignis | Epic | Assassin | Api | Familiar | 520 | 74 | 18 | 1.15 | 1 | **Cinder Pounce** — lompat ke belakang, membakar 4% hp/dtk selama 4 dtk |
| `aurelian` | Prof. Aurelian Solis | Legendary | Support | Cahaya | Profesor | 700 | 50 | 30 | 0.8 | 3 | **Lecture of Light** — semua sekutu +25% atk & hapus debuff (cinematic) |
| `morvaine` | Prof. Morvaine Hollow | Legendary | Summoner | Bayangan | Profesor | 620 | 55 | 22 | 0.9 | 3 | **Hollow Choir** — memanggil 3 roh bayangan 10 dtk (cinematic) |
| `valka` | Valka Stormheart | Legendary | Mage | Petir | Murid | 560 | 78 | 20 | 0.9 | 3 | **Sky Verdict** — petir berantai ke 5 musuh, 150% atk (cinematic) |
| `seraphine` | Kepala Akademi Seraphine | Mythic | Mage | Cahaya | Profesor | 640 | 85 | 24 | 0.85 | 3 | **Rite of the First Dawn** — 350% atk semua musuh + 2 dtk stun (cinematic) |
| `umbra` | Umbra, Naga Jurang | Mythic | Tank | Bayangan | Familiar | 1300 | 60 | 55 | 0.7 | 1 | **Abyss Mantle** — kebal 3 dtk, lalu ledakan 200% atk area (cinematic) |

Distribusi: setiap elemen 3 unit; Murid 8, Familiar 4, Profesor 3.

## 4. Sinergi

Dihitung dari unit **unik** yang diturunkan (dua `kael` = 1 hitungan).

### Elemen

| Elemen | 2 unit | 3 unit |
|---|---|---|
| Api 🔥 | Serangan membakar 2% hp/dtk 3 dtk | Bakar 4% hp/dtk |
| Es ❄️ | Serangan memberi slow 10% | Slow 20% + 10% peluang beku 1 dtk |
| Petir ⚡ | +15% spd | +30% spd |
| Cahaya ✨ | Heal 2% hp/dtk untuk sekutu Cahaya | Heal 2% untuk SEMUA sekutu |
| Bayangan 🌑 | +15% crit chance | +30% crit chance, crit damage 175% |

### Status

| Status | Tingkat | Efek |
|---|---|---|
| Murid | 2 / 4 / 6 | Setiap 10 dtk, unit Murid +5% / +8% / +12% atk & def (menumpuk, "belajar di tengah battle") |
| Familiar | 2 / 3 | Familiar yang mati pertama kali bangkit dengan 30% / 50% hp |
| Profesor | 1 / 2 | Semua sekutu mengisi Mana +20% / +40% lebih cepat |

## 5. Trait

Satu slot per unit. Reroll = 1 Trait Shard. Hasil roll **mengganti** trait lama (pemain bisa "kunci" hasil lama dengan konfirmasi — reroll tidak bisa dibatalkan).

| Tier | Peluang | Trait (dipilih rata di dalam tier) |
|---|---|---|
| Biasa | 60% | **Swift** +8% spd · **Sturdy** +10% hp · **Sharp** +8% atk |
| Langka | 30% | **Focused** +15% mana gain · **Guardian** +15% def · **Keen** +10% crit chance |
| Epik | 8.5% | **Arcane Flow** mulai battle dengan 40 Mana · **Vampiric** lifesteal 10% · **Overdrive** +15% atk & +8% spd |
| Legendaris | 1.4% | **Prodigy** +25% semua stat · **Echo** ultimate 20% peluang dipakai 2× |
| Mitos | 0.1% | **Archmage** +35% semua stat, ultimate pertama gratis di detik 3 |

Total = 100%. Peluang per trait = peluang tier ÷ jumlah trait di tier itu (UI wajib menampilkan keduanya).

Pity trait: setiap 100 reroll tanpa tier Legendaris ke atas → reroll ke-100 dijamin Legendaris.

## 6. Menambah unit baru (checklist)

1. Tambah baris di tabel bagian 3 dokumen ini (desain dulu).
2. Tambah entri di `src/shared/Config/Units.luau`.
3. Implementasi ultimate di `src/shared/BattleSim/Skills.luau` (data-driven bila bisa).
4. Tambah asset ID model/animasi/VFX di `Config/Assets.luau`.
5. Masukkan ke banner di `Config/Banners.luau` (odds diperbarui otomatis dari config).
6. Jalankan `tests/BattleSim.spec.luau` + battle uji manual 1 lawan 1.
Gunakan `prompts/new-unit.md`.
