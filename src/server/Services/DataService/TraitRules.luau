--!strict
-- Aturan murni reroll trait yang memutasi DRAFT profil (salinan). Dipanggil hanya lewat DataService/Traits,
-- yang meng-commit draft secara atomik lewat Commit.run. Semua cek (kepemilikan, locked, quote, saldo,
-- validitas hasil roll) dilakukan sebelum mutasi pertama. Tidak boleh yield.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Traits = require(Shared.Config.Traits)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local StoryRules = require(script.Parent.StoryRules)

type Outcome = StoryRules.Outcome

-- State yang dilihat quote: counter pity global + trait unit saat ini.
export type QuoteState = { sinceLegendary: number, traitId: string? }
export type Draw = { traitId: string, tier: Types.TraitTier }
export type Request = {
	uid: string,
	cost: number,
	-- Dicek terhadap state draft saat commit (quote odds). nil = lolos.
	precheck: (state: QuoteState) -> string?,
	-- Roll murni; menerima counter pity saat ini, mengembalikan hasil + counter berikutnya.
	roll: (sinceLegendary: number) -> (Draw, number),
}
export type Result = { uid: string, traitId: string, previousTraitId: string?, sinceLegendary: number }

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local REROLL_SOURCE = "trait_reroll"
local isUid = Validate.isStringMax(Constants.MAX_UID_LENGTH)

local tierById: { [string]: Types.TraitTier } = {}
for tier, def in Traits.tiers do
	for _, trait in def.traits do
		tierById[trait.id] = tier
	end
end

local TraitRules = {}

local function isCounter(value: any): boolean
	return Validate.isIntInRange(value, 0, MAX_EXACT_INTEGER - 1)
end

-- Counter pity tersanitasi dari profil. Hilang/rusak = mulai dari nol.
function TraitRules.readPity(value: any): number
	return if isCounter(value) then value else 0
end

-- Trait unit tersanitasi: ID yang tidak dikenal config diperlakukan sebagai tanpa trait.
function TraitRules.readTrait(value: any): string?
	return if type(value) == "string" and tierById[value] ~= nil then value else nil
end

local function isValidRequest(request: Request): boolean
	return type(request) == "table"
		and isUid(request.uid)
		and request.uid ~= ""
		and Validate.isIntInRange(request.cost, 1, MAX_EXACT_INTEGER)
		and type(request.precheck) == "function"
		and type(request.roll) == "function"
end

-- Menerapkan satu reroll ke draft. Mengembalikan (kode error, nil, nil) atau (nil, outcome, hasil).
function TraitRules.apply(profile: Types.Profile, request: Request): (string?, Outcome?, Result?)
	if not isValidRequest(request) then
		return "INVALID_REQUEST", nil, nil
	end
	local unit = profile.units[request.uid]
	if type(unit) ~= "table" or unit.uid ~= request.uid then
		return "UNIT_NOT_OWNED", nil, nil
	end
	if unit.locked ~= false then
		return "UNIT_LOCKED", nil, nil
	end
	local sinceLegendary = TraitRules.readPity(profile.traitPity)
	local previous = TraitRules.readTrait(unit.trait)
	local code = request.precheck({ sinceLegendary = sinceLegendary, traitId = previous })
	if code ~= nil then
		return code, nil, nil
	end
	if not Validate.isIntInRange(profile.currencies.TraitShards, request.cost, MAX_EXACT_INTEGER) then
		return "NOT_ENOUGH_TRAIT_SHARDS", nil, nil
	end
	local draw, nextPity = request.roll(sinceLegendary)
	if
		type(draw) ~= "table"
		or type(draw.traitId) ~= "string"
		or tierById[draw.traitId] ~= draw.tier
		or not isCounter(nextPity)
	then
		warn("[DataService] trait roll returned an invalid result")
		return "INTERNAL_ERROR", nil, nil
	end

	-- Mulai mutasi: semua cek di atas sudah lolos.
	local outcome = StoryRules.newOutcome()
	code = StoryRules.changeCurrency(profile, outcome, "TraitShards", request.cost, REROLL_SOURCE, true)
	if code ~= nil then
		return "NOT_ENOUGH_TRAIT_SHARDS", nil, nil
	end
	local updated = table.clone(unit)
	updated.trait = draw.traitId
	profile.units[request.uid] = updated
	profile.traitPity = nextPity
	outcome.units = true
	return nil,
		outcome,
		{ uid = request.uid, traitId = draw.traitId, previousTraitId = previous, sinceLegendary = nextPity }
end

return table.freeze(TraitRules)
