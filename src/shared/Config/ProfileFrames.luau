--!strict
-- Bingkai profil = entitlement kosmetik original (profile.battlePass.profileFrames[frameId]). Tanpa stat.
-- assetId sengaja kosong: diisi manusia/art setelah aset dipublikasikan.
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type ProfileFrameDef = { id: string, name: string, assetId: string }

local ProfileFrames: { [string]: ProfileFrameDef } = {
	s1_academy_frame = { id = "s1_academy_frame", name = "Bingkai Akademi Musim 1", assetId = "" },
}

return TableUtil.deepFreeze(ProfileFrames)
