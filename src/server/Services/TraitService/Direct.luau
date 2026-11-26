--!strict
-- Pilihan trait langsung (tanpa RNG) untuk pemain restricted (D-OPEN-1). Murni: daftar opsi dan harga
-- dibaca dari Config/Traits.direct.goldCost, sumber yang sama untuk transaksi server dan tampilan UI.
-- Hanya tier yang punya harga di config (Common/Uncommon) yang bisa dipilih.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Traits = require(Shared.Config.Traits)

local DIRECT_TIERS: { Types.TraitDirectTier } = { "Common", "Uncommon" }
local GOLD_COST: { [string]: number } = Traits.direct.goldCost

local Direct = {}
Direct.MAX_TRAIT_ID_LENGTH = 0

local options: { Types.TraitDirectOption } = {}
local byId: { [string]: Types.TraitDirectOption } = {}
for _, tier in DIRECT_TIERS do
	local cost = GOLD_COST[tier]
	assert(type(cost) == "number" and cost >= 1 and math.floor(cost) == cost, `Traits.direct.goldCost.{tier} invalid`)
	for _, trait in Traits.tiers[tier].traits do
		local option: Types.TraitDirectOption = { id = trait.id, name = trait.name, tier = tier, cost = cost }
		table.insert(options, table.freeze(option))
		byId[trait.id] = option
		Direct.MAX_TRAIT_ID_LENGTH = math.max(Direct.MAX_TRAIT_ID_LENGTH, #trait.id)
	end
end
-- Tier lain tidak boleh diberi harga langsung (Epik ke atas hanya lewat reroll acak).
for tier in GOLD_COST do
	assert(table.find(DIRECT_TIERS, tier) ~= nil, `Traits.direct.goldCost.{tier}: tier tidak boleh dipilih langsung`)
end
table.freeze(options)

-- Opsi untuk traitId, atau nil bila bukan trait Common/Uncommon yang dikenal config.
function Direct.option(traitId: any): Types.TraitDirectOption?
	return if type(traitId) == "string" then byId[traitId] else nil
end

-- Payload `direct` untuk TraitInfo (salinan baru, aman dikirim ke client).
function Direct.view(gold: number): Types.TraitDirect
	local list: { Types.TraitDirectOption } = {}
	for _, option in options do
		table.insert(list, table.clone(option))
	end
	return { gold = gold, options = list }
end

return table.freeze(Direct)
