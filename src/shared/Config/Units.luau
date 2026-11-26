--!strict
-- Definisi unit (sumber runtime). Sumber desain: docs/UNITS.md §3.
-- Irisan ini baru memuat unit Rare awal; 15 unit lengkap ditambahkan di prompts/01-types-config.md.
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local Units: { [string]: Types.UnitDef } = {
	kael = {
		id = "kael",
		name = "Kael Ardent",
		rarity = "Rare",
		class = "Mage",
		element = "Api",
		status = "Murid",
		base = { hp = 520, atk = 64, def = 18, spd = 0.9, range = 3 },
		ultimate = "kael_flare_burst",
	},
	mira = {
		id = "mira",
		name = "Mira Frostwell",
		rarity = "Rare",
		class = "Support",
		element = "Es",
		status = "Murid",
		base = { hp = 600, atk = 40, def = 25, spd = 0.8, range = 3 },
		ultimate = "mira_frost_veil",
	},
	dorin = {
		id = "dorin",
		name = "Dorin Voltz",
		rarity = "Rare",
		class = "Assassin",
		element = "Petir",
		status = "Murid",
		base = { hp = 480, atk = 72, def = 15, spd = 1.2, range = 1 },
		ultimate = "dorin_static_dash",
	},
	brutus = {
		id = "brutus",
		name = "Golem Rimewall",
		rarity = "Rare",
		class = "Tank",
		element = "Es",
		status = "Familiar",
		base = { hp = 950, atk = 38, def = 45, spd = 0.6, range = 1 },
		ultimate = "brutus_glacier_guard",
	},
	pip = {
		id = "pip",
		name = "Pip si Burung Bara",
		rarity = "Rare",
		class = "Summoner",
		element = "Api",
		status = "Familiar",
		base = { hp = 450, atk = 45, def = 15, spd = 1.0, range = 3 },
		ultimate = "pip_ember_flock",
	},
}

return TableUtil.deepFreeze(Units)
