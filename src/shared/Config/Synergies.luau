--!strict
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local elements: { [Types.Element]: { Types.SynergyDef } } = {
	Api = {
		{ count = 2, burnHpPerSecond = 0.02, burnSeconds = 3 },
		{ count = 3, burnHpPerSecond = 0.04, burnSeconds = 3 },
	},
	Es = {
		{ count = 2, slow = 0.1 },
		{ count = 3, slow = 0.2, freezeChance = 0.1, freezeSeconds = 1 },
	},
	Petir = { { count = 2, speedBonus = 0.15 }, { count = 3, speedBonus = 0.3 } },
	Cahaya = {
		{ count = 2, healHpPerSecond = 0.02, healTarget = "matchingElement" },
		{ count = 3, healHpPerSecond = 0.02, healTarget = "allAllies" },
	},
	Bayangan = {
		{ count = 2, critChanceBonus = 0.15 },
		{ count = 3, critChanceBonus = 0.3, critDamageMultiplier = 1.75 },
	},
}

local statuses: { [Types.Status]: { Types.SynergyDef } } = {
	Murid = {
		{ count = 2, atkAndDefBonus = 0.05, stackIntervalSeconds = 10 },
		{ count = 4, atkAndDefBonus = 0.08, stackIntervalSeconds = 10 },
		{ count = 6, atkAndDefBonus = 0.12, stackIntervalSeconds = 10 },
	},
	Familiar = { { count = 2, firstReviveHp = 0.3 }, { count = 3, firstReviveHp = 0.5 } },
	Profesor = { { count = 1, manaGainBonus = 0.2 }, { count = 2, manaGainBonus = 0.4 } },
}

return TableUtil.deepFreeze({ elements = elements, statuses = statuses })
