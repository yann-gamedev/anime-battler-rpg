--!strict
-- Roll trait murni (tanpa Instance, tanpa data profil, tanpa yield). Satu fungsi bobot, `distribution`,
-- dipakai oleh roll server DAN oleh tabel odds yang dikirim ke UI (docs/RULES.md §4, docs/UNITS.md §5).
-- Pity global per pemain: reroll ke-`Traits.pity.rolls` tanpa tier reset (Legendary/Mythic) memaksa
-- tier `Traits.pity.guaranteedTier` PERSIS (Legendary saja, Mythic 0%). Semua angka dari Config/Traits.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Traits = require(Shared.Config.Traits)
local TableUtil = require(Shared.Util.TableUtil)

export type Entry = { id: string, name: string, tier: Types.TraitTier, percent: number }
export type Distribution = { Entry }
-- Random server (`Random.new()`) atau RNG deterministik untuk test: NextNumber() → [0, 1).
export type Rng = { NextNumber: (any) -> number }
export type Draw = { traitId: string, tier: Types.TraitTier }

-- Urutan tampilan & kumulatif: tier terendah lebih dulu, trait mengikuti urutan config.
local TIERS: { Types.TraitTier } = { "Common", "Uncommon", "Epic", "Legendary", "Mythic" }
local PITY_ROLLS: number = Traits.pity.rolls
local GUARANTEED_TIER: Types.TraitTier = Traits.pity.guaranteedTier :: Types.TraitTier
local RESET_TIERS: { [string]: boolean } = Traits.pity.resetTiers

assert(Traits.tiers[GUARANTEED_TIER], "Traits.pity.guaranteedTier tidak ada di Traits.tiers")
assert(RESET_TIERS[GUARANTEED_TIER] == true, "Traits.pity.guaranteedTier harus me-reset pity")
assert(math.floor(PITY_ROLLS) == PITY_ROLLS and PITY_ROLLS >= 1, "Traits.pity.rolls harus integer >= 1")

local Roll = {}
Roll.TIERS = table.freeze(table.clone(TIERS))
Roll.PITY_ROLLS = PITY_ROLLS

local tierById: { [string]: Types.TraitTier } = {}
for _, tier in TIERS do
	for _, trait in Traits.tiers[tier].traits do
		assert(tierById[trait.id] == nil, `Trait {trait.id} terdaftar dua kali`)
		tierById[trait.id] = tier
	end
end

-- Tier trait dari ID, atau nil bila ID tidak dikenal.
function Roll.tierOf(traitId: any): Types.TraitTier?
	return if type(traitId) == "string" then tierById[traitId] else nil
end

-- true bila reroll berikutnya (ke-`sinceLegendary + 1`) adalah reroll pity.
function Roll.isPityRoll(sinceLegendary: number): boolean
	return sinceLegendary + 1 >= PITY_ROLLS
end

local function build(forced: boolean): Distribution
	local entries: Distribution = {}
	for _, tier in TIERS do
		local def = Traits.tiers[tier]
		local tierPercent = if forced then (if tier == GUARANTEED_TIER then 100 else 0) else def.oddsPercent
		for _, trait in def.traits do
			table.insert(entries, {
				id = trait.id,
				name = trait.name,
				tier = tier,
				percent = math.clamp(tierPercent / #def.traits, 0, 100),
			})
		end
	end
	return TableUtil.deepFreeze(entries)
end

-- Config beku → cukup dua distribusi. Tabel beku dan dibagikan; jangan dimutasi.
local BASE = build(false)
local FORCED = build(true)

-- FUNGSI BOBOT TUNGGAL: peluang aktual tiap trait untuk reroll berikutnya pada state pity ini.
function Roll.distribution(sinceLegendary: number): Distribution
	return if Roll.isPityRoll(sinceLegendary) then FORCED else BASE
end

function Roll.baseDistribution(): Distribution
	return BASE
end

-- Memilih entri dari bilangan seragam u ∈ [0, 1). Entri berpeluang nol tidak pernah terpilih.
function Roll.pick(entries: Distribution, u: number): Entry
	assert(type(u) == "number" and u >= 0 and u < 1, "Roll.pick: u must be in [0, 1)")
	local target = u * 100
	local cumulative = 0
	local last: Entry? = nil
	for _, entry in entries do
		if entry.percent > 0 then
			cumulative += entry.percent
			last = entry
			if target < cumulative then
				return entry
			end
		end
	end
	-- Sisa pembulatan floating point jatuh ke entri berpeluang terakhir.
	return assert(last, "Roll.pick: empty distribution")
end

-- Counter pity sesudah satu hasil: tier reset (Legendary/Mythic) → 0, selain itu +1.
function Roll.advance(sinceLegendary: number, tier: Types.TraitTier): number
	return if RESET_TIERS[tier] == true then 0 else sinceLegendary + 1
end

-- Satu reroll. Murni terhadap state; hanya mengonsumsi satu bilangan dari rng.
function Roll.reroll(sinceLegendary: number, rng: Rng): (Draw, number)
	local entry = Roll.pick(Roll.distribution(sinceLegendary), rng:NextNumber())
	return { traitId = entry.id, tier = entry.tier }, Roll.advance(sinceLegendary, entry.tier)
end

-- Tanda tangan config yang memengaruhi odds; konstan selama server hidup (config beku).
local parts: { string } = { tostring(PITY_ROLLS), GUARANTEED_TIER }
for _, tier in TIERS do
	local def = Traits.tiers[tier]
	local ids: { string } = {}
	for _, trait in def.traits do
		table.insert(ids, trait.id)
	end
	table.insert(parts, `{tier}={def.oddsPercent}:{table.concat(ids, ",")}:{RESET_TIERS[tier] == true}`)
end
Roll.SIGNATURE = table.concat(parts, "|")

return table.freeze(Roll)
