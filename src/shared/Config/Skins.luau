--!strict
-- Skin = entitlement kosmetik original (profile.skinsOwned[skinId]). Tidak mengubah stat.
-- assetId sengaja kosong: diisi manusia/art setelah aset dipublikasikan (docs/RULES.md §8).
local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local Skins: { [string]: Types.SkinDef } = {
	skin_academy_scholar = { id = "skin_academy_scholar", name = "Academy Scholar", assetId = "" },
	skin_s1_starfall = { id = "skin_s1_starfall", name = "Starfall Regalia", unitId = "selene", assetId = "" },
}

return TableUtil.deepFreeze(Skins)
