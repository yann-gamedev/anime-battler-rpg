--!strict
-- Aturan murni musim Battle Pass (tanpa Instance). Server memakai ini untuk otoritas; client hanya tampilan.
local Types = require(script.Parent.Types)
local BattlePass = require(script.Parent.Config.BattlePass)

local BattlePassSeason = {}

function BattlePassSeason.byId(seasonId: string): Types.BattlePassSeasonDef?
	for _, season in BattlePass.seasons do
		if season.id == seasonId then
			return season
		end
	end
	return nil
end

function BattlePassSeason.isActive(season: Types.BattlePassSeasonDef, now: number): boolean
	return now >= season.startsAt and now < season.endsAt
end

-- Musim aktif pada `now`, atau nil.
function BattlePassSeason.active(now: number): Types.BattlePassSeasonDef?
	for _, season in BattlePass.seasons do
		if BattlePassSeason.isActive(season, now) then
			return season
		end
	end
	return nil
end

-- Musim untuk ditampilkan: aktif; jika tidak ada, musim terakhir yang sudah mulai; jika belum ada, yang pertama.
function BattlePassSeason.display(now: number): Types.BattlePassSeasonDef
	local active = BattlePassSeason.active(now)
	if active then
		return active
	end
	local latest: Types.BattlePassSeasonDef? = nil
	for _, season in BattlePass.seasons do
		if season.startsAt <= now and (latest == nil or season.startsAt > latest.startsAt) then
			latest = season
		end
	end
	return latest or BattlePass.seasons[1]
end

-- XP maksimum yang berarti (tier terakhir terbuka).
function BattlePassSeason.maxXp(season: Types.BattlePassSeasonDef): number
	return #season.tiers * season.xpPerTier
end

function BattlePassSeason.unlockedTier(season: Types.BattlePassSeasonDef, xp: number): number
	return math.clamp(xp // season.xpPerTier, 0, #season.tiers)
end

return table.freeze(BattlePassSeason)
