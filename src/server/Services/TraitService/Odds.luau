--!strict
-- Tabel odds trait untuk UI + fingerprint quote. Dibangun dari Roll.distribution (fungsi bobot yang sama
-- dengan roll server), jadi angka di UI selalu identik dengan peluang roll berikutnya.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Roll = require(script.Parent.Roll)

local Odds = {}

-- Bentuk TraitOdds dari distribusi: setiap tier dan setiap trait (termasuk yang 0%) tercantum.
function Odds.fromDistribution(entries: Roll.Distribution): Types.TraitOdds
	local byTier: { [string]: Types.TraitTierOdds } = {}
	local tiers: { Types.TraitTierOdds } = {}
	for _, tier in Roll.TIERS do
		local view: Types.TraitTierOdds = { tier = tier, percent = 0, traits = {} }
		byTier[tier] = view
		table.insert(tiers, view)
	end
	for _, entry in entries do
		local view = byTier[entry.tier]
		view.percent += entry.percent
		table.insert(view.traits, { id = entry.id, name = entry.name, percent = entry.percent })
	end
	for _, view in tiers do
		view.percent = math.clamp(view.percent, 0, 100)
	end
	return { tiers = tiers }
end

-- Peluang referensi tanpa pity.
function Odds.base(): Types.TraitOdds
	return Odds.fromDistribution(Roll.baseDistribution())
end

-- Peluang aktual reroll berikutnya untuk counter pity ini.
function Odds.next(sinceLegendary: number): Types.TraitOdds
	return Odds.fromDistribution(Roll.distribution(sinceLegendary))
end

-- Fingerprint yang dilihat pemain saat quote: pity global, trait unit saat itu, dan config.
-- Berubah → quote lama basi (ODDS_CHANGED).
function Odds.fingerprint(sinceLegendary: number, traitId: string?): string
	return `{sinceLegendary}:{traitId or "-"}#{Roll.SIGNATURE}`
end

return table.freeze(Odds)
