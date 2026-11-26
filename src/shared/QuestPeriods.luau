--!strict
-- Aturan murni periode quest/raid berbasis UTC (tanpa Instance). `now` = os.time() (detik Unix UTC).
-- Harian: [hari × 86400, (hari + 1) × 86400). Mingguan: mulai Senin 00:00 UTC, panjang 7 hari.
local Types = require(script.Parent.Types)
local Quests = require(script.Parent.Config.Quests)

local DAY = Quests.secondsPerDay
local OFFSET = Quests.weekStartOffsetDays

local QuestPeriods = {}

function QuestPeriods.utcDay(now: number): number
	return now // DAY
end

function QuestPeriods.utcWeek(now: number): number
	return (now // DAY + OFFSET) // 7
end

function QuestPeriods.dailyResetAt(now: number): number
	return (QuestPeriods.utcDay(now) + 1) * DAY
end

function QuestPeriods.weeklyResetAt(now: number): number
	return ((QuestPeriods.utcWeek(now) + 1) * 7 - OFFSET) * DAY
end

function QuestPeriods.key(period: Types.QuestPeriod, now: number): string
	if period == "Daily" then
		return `D{QuestPeriods.utcDay(now)}`
	end
	return `W{QuestPeriods.utcWeek(now)}`
end

return table.freeze(QuestPeriods)
