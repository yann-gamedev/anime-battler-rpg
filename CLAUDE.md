# CLAUDE.md

@AGENTS.md

## Catatan khusus Claude Code

- Sebelum coding, baca `docs/RULES.md` dan `docs/ARCHITECTURE.md` (wajib), lalu dokumen yang disebut prompt task.
- Gunakan mode plan untuk task yang menyentuh lebih dari 3 file.
- Jika tersedia Roblox Studio MCP: boleh dipakai untuk **membaca** struktur place dan menjalankan build script di `studio/`. Kode permanen tetap ditulis ke `src/` agar tersinkron lewat Rojo dan masuk git.
- Jangan membuat file dokumentasi baru di luar `docs/` tanpa diminta.
- Untuk sistem sensitif (DataService, SummonService, TradeService, MonetizationService), selesaikan task dengan menjalankan `prompts/review-security.md` terhadap perubahanmu sendiri dan laporkan temuannya.
- Bahasa: dokumen dan komentar dalam Bahasa Indonesia; identifier kode dalam Bahasa Inggris.
