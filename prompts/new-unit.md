# Tambah Unit Baru

## Input dari manusia
```
Nama:
Rarity: Rare | Epic | Legendary | Mythic
Kelas: Tank | Mage | Assassin | Support | Summoner
Elemen:
Status:
Konsep / kepribadian (1–2 kalimat):
Ide ultimate:
Masuk banner: Standar | Limited (tanggal) | Event
```

## Konteks
- `docs/UNITS.md` (seluruh), `docs/RULES.md` §5 (karakter original)

## Langkah
1. **Cek orisinalitas**: nama, desain, dan jurus tidak boleh meniru karakter IP lain. Jika input mirip karakter terkenal, hentikan dan usulkan alternatif original.
2. Usulkan stat `base` yang konsisten dengan unit lain dengan rarity & kelas sama (tunjukkan perbandingan dengan 2 unit terdekat). **Tunggu persetujuan manusia** sebelum lanjut.
3. Tambah baris di `docs/UNITS.md` §3 (dan perbarui baris "Distribusi").
4. Tambah entri di `Config/Units.luau`, efek ultimate di `BattleSim/Skills.luau` (data-driven).
5. Tambah placeholder di `Config/Assets.luau` (TODO asset ID).
6. Tambah ke banner di `Config/Banners.luau`.
7. Jalankan semua test + battle uji: unit baru vs 2 unit pembanding, 20 seed berbeda, laporkan winrate.

## Kriteria terima
- Validator config lulus, test lulus
- Winrate battle uji 40–60% melawan unit setara rarity (kecuali manusia menyatakan lain)
- Catat di `docs/DECISIONS.md`
