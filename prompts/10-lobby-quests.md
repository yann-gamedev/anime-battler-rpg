# 10 — Lobby Sosial, Quest, Boss Raid, Analytics

## Tujuan
Melengkapi MVP: lobby tempat pemain saling melihat (pilar "pamer"), quest harian/mingguan sebagai sumber Gems gratis, boss raid harian, dan analytics untuk soft launch.

## Konteks
- `docs/GDD.md` §2, §7, §11, §12
- `docs/ECONOMY.md` §3, §7

## Scope
Dikerjakan:
- Lobby (build script `studio/world/build_lobby.luau`, low-poly placeholder): portal Story, altar Summon, NPC Toko, papan pengumuman, area Trading Plaza (kosong, disiapkan untuk M6)
- Pajangan: setiap pemain memilih 1 unit pajangan yang mengikuti di lobby (model + skin + aura VIP), terlihat semua pemain. Replikasi efisien (model di-spawn server, animasi idle di client)
- `QuestService`: quest harian (reset 00:00 UTC) & mingguan dari config, progres dari event service lain (Signal), klaim di server
- `RaidService`: boss harian, HP besar, reward berdasarkan damage tertinggi (1 percobaan gratis/hari, tidak bisa dibeli)
- `AnalyticsService` lengkap: funnel onboarding, sumber/penggunaan mata uang, summon, pembelian, durasi sesi — pakai `AnalyticsService` Roblox (verifikasi API terbaru)
- Settings: musik, SFX, matikan cinematic, mode grafis rendah (kurangi partikel)

## Deliverables
- `studio/world/build_lobby.luau`
- `src/server/Services/QuestService.luau`, `RaidService.luau`, `LobbyService.luau`, `AnalyticsService.luau` (lengkap)
- Config: `Quests.luau`, `Raids.luau`
- Controller: Lobby, Quest, Raid, Settings

## Kriteria terima
- 10 pemain di server uji (Studio Test → Clients 4+) tetap 60 FPS di lobby
- Quest tidak bisa diklaim dua kali; reset harian benar lintas zona waktu (pakai UTC)
- Event analytics muncul di Creator Dashboard (setelah publish ke place uji)

## Setelah selesai
- Jalankan `prompts/review-security.md` untuk **semua** service, lalu siapkan soft launch
- Centang ROADMAP
