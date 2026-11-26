# Perbaikan Bug

## Input dari manusia
```
Gejala:
Langkah reproduksi:
Yang diharapkan:
Log/error (Output Studio):
Platform: Studio / Mobile / PC
```

## Langkah
1. Reproduksi dulu (atau jelaskan kenapa tidak bisa). Jangan menebak perbaikan tanpa memahami penyebab.
2. Temukan akar masalah; jelaskan dalam 2–3 kalimat.
3. Perbaiki seminimal mungkin. Jangan refactor area lain.
4. Tambahkan test regresi jika bug ada di modul murni (BattleSim, Config, Roll, TradeSession).
5. Jika bug menyangkut data/mata uang/trade: jelaskan apakah ada data pemain yang perlu dikoreksi, dan **jangan** menulis skrip koreksi data tanpa persetujuan.

## Output
- Penyebab, perbaikan (file yang diubah), cara verifikasi, risiko efek samping
- Branch: `fix/<nama-singkat>`
