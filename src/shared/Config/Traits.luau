--!strict
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type TierDef = { oddsPercent: number, traits: { Types.TraitDef } }

local tiers: { [Types.TraitTier]: TierDef } = {
	Common = {
		oddsPercent = 60,
		traits = {
			{ id = "swift", name = "Swift", spdBonus = 0.08 },
			{ id = "sturdy", name = "Sturdy", hpBonus = 0.1 },
			{ id = "sharp", name = "Sharp", atkBonus = 0.08 },
		},
	},
	Uncommon = {
		oddsPercent = 30,
		traits = {
			{ id = "focused", name = "Focused", manaGainBonus = 0.15 },
			{ id = "guardian", name = "Guardian", defBonus = 0.15 },
			{ id = "keen", name = "Keen", critChanceBonus = 0.1 },
		},
	},
	Epic = {
		oddsPercent = 8.5,
		traits = {
			{ id = "arcane_flow", name = "Arcane Flow", startingMana = 40 },
			{ id = "vampiric", name = "Vampiric", lifesteal = 0.1 },
			{ id = "overdrive", name = "Overdrive", atkBonus = 0.15, spdBonus = 0.08 },
		},
	},
	Legendary = {
		oddsPercent = 1.4,
		traits = {
			{ id = "prodigy", name = "Prodigy", allStatsBonus = 0.25 },
			{ id = "echo", name = "Echo", repeatUltimateChance = 0.2 },
		},
	},
	Mythic = {
		oddsPercent = 0.1,
		traits = {
			{ id = "archmage", name = "Archmage", allStatsBonus = 0.35, freeFirstUltimateAtSeconds = 3 },
		},
	},
}

return TableUtil.deepFreeze({
	tiers = tiers,
	pity = { rolls = 100, guaranteedTier = "Legendary", resetTiers = { Legendary = true, Mythic = true } },
	-- D-OPEN-1: pemain ArePaidRandomItemsRestricted memilih trait tier ini langsung dengan Gold (tanpa RNG).
	-- Harga PLACEHOLDER sementara; dibaca server (transaksi) dan dikirim ke UI lewat GetTraitInfo.
	direct = { goldCost = { Common = 200, Uncommon = 600 } },
})
