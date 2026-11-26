--!strict
-- Turunan metrik murni dari mutasi profil yang SUDAH di-commit (tanpa Instance).
-- Langkah onboarding hanya dicatat saat transisi false → true di satu commit, dibandingkan dengan draft yang
-- sudah direkonsiliasi (bukan profil mentah) agar rekonsiliasi data lama tidak menghasilkan langkah palsu.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Analytics = require(Shared.Config.Analytics)

export type OnboardingState = { tutorialWon: boolean, summoned: boolean, firstStage: boolean, done: boolean }
export type Delta = { kind: string, amount: number, source: string }
export type EconomyEvent = { kind: string, amount: number, endingBalance: number, source: string }

local Derive = {}

function Derive.onboardingState(profile: any): OnboardingState
	local progress = if type(profile.progress) == "table" then profile.progress else {}
	local stats = if type(profile.stats) == "table" then profile.stats else {}
	local story = if type(profile.story) == "table" then profile.story else {}
	local cleared = if type(story.cleared) == "table" then story.cleared else {}
	local flags = if type(profile.flags) == "table" then profile.flags else {}
	local stars = cleared[Analytics.firstStoryStageId]
	return {
		tutorialWon = progress.tutorialBattleCleared == true,
		summoned = type(stats.summons) == "number" and stats.summons > 0,
		firstStage = type(stars) == "number" and stars >= 1,
		done = flags.tutorialDone == true,
	}
end

-- Nomor langkah onboarding (urut naik) yang baru tercapai antara `before` dan `after`.
function Derive.onboardingSteps(before: OnboardingState, after: OnboardingState): { number }
	local steps: { number } = {}
	if after.tutorialWon and not before.tutorialWon then
		table.insert(steps, 2)
	end
	if after.summoned and not before.summoned then
		table.insert(steps, 3)
	end
	if after.firstStage and not before.firstStage then
		table.insert(steps, 4)
	end
	if after.done and not before.done then
		table.insert(steps, 5)
	end
	return steps
end

-- Event ekonomi dari delta commit. Delta diterapkan berurutan, jadi saldo akhir tiap event =
-- saldo awal (draft sebelum mutasi) + delta kumulatif mata uang yang sama.
function Derive.economyEvents(balances: { [string]: number }, deltas: { Delta }): { EconomyEvent }
	local running = table.clone(balances)
	local events: { EconomyEvent } = {}
	for _, delta in deltas do
		local balance = (running[delta.kind] or 0) + delta.amount
		running[delta.kind] = balance
		table.insert(
			events,
			{ kind = delta.kind, amount = delta.amount, endingBalance = balance, source = delta.source }
		)
	end
	return events
end

-- Bucket label durasi sesi dari config.
function Derive.sessionBucket(seconds: number): string
	for _, bucket in Analytics.sessionBuckets do
		if seconds < bucket.maxSeconds then
			return bucket.label
		end
	end
	return Analytics.sessionBuckets[#Analytics.sessionBuckets].label
end

-- Rarity tertinggi dari daftar rarity hasil summon.
function Derive.bestRarity(rarities: { string }): string
	local order = { Rare = 1, Epic = 2, Legendary = 3, Mythic = 4 }
	local best, bestRank = "none", 0
	for _, rarity in rarities do
		local rank = order[rarity] or 0
		if rank > bestRank then
			best, bestRank = rarity, rank
		end
	end
	return best
end

return table.freeze(Derive)
