# Pass Balancing

## Input dari manusia
```
Masalah yang dirasakan: (mis. "Valka terlalu kuat", "stage 2-7 terlalu sulit")
Data pendukung: (winrate, feedback pemain, analytics)
Batas: (angka apa yang boleh/tidak boleh diubah)
```

## Konteks
- `docs/UNITS.md`, `docs/ECONOMY.md`, `src/shared/Config/`

## Langkah
1. Tulis skrip simulasi sementara (server, hanya Studio) yang menjalankan `BattleSim` ≥ 500 seed untuk skenario terkait, laporkan winrate & durasi rata-rata.
2. Usulkan perubahan angka dalam tabel **sebelum → sesudah** beserta hasil simulasi ulang. **Jangan terapkan sebelum disetujui.**
3. Setelah disetujui: ubah config **dan** dokumen (`UNITS.md`/`ECONOMY.md`) agar sama, catat di `DECISIONS.md`.

## Larangan
- Tidak mengubah odds banner, harga Robux, atau pity tanpa instruksi eksplisit.
- Tidak nerf unit yang sedang dijual di banner limited aktif tanpa instruksi eksplisit (risiko kepercayaan pemain).
