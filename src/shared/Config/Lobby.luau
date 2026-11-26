--!strict
-- Pajangan unit lobby (prompt 10). Server membuat satu model ringan per pemain; animasi idle di client.
-- Struktur model (kontrak client): Character.LobbyShowcase (Model, PrimaryPart = Root)
--   Root (Part tak terlihat) ← Weld "AnchorWeld" (anak Root) ke HumanoidRootPart, C0 = offset
--   Body (Part placeholder)  ← Motor6D "IdleJoint" (anak Root, Part0 Root, Part1 Body); Transform hanya di client
--   Atribut Model: UnitId, SkinId ("" = default), Stars, VipAura, OwnerUserId
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

return TableUtil.deepFreeze({
	modelName = "LobbyShowcase",
	rootName = "Root",
	bodyName = "Body",
	weldName = "AnchorWeld",
	jointName = "IdleJoint",
	-- Offset pajangan relatif HumanoidRootPart (studs): kanan, atas, belakang.
	offset = { x = 3, y = 0.5, z = 1.5 },
	-- Body diangkat dari Root lewat C0 IdleJoint.
	bodyLift = 1.5,
	bodySize = { x = 1.6, y = 2.4, z = 1.2 },
	rootWaitSeconds = 10,
	-- Lobby & pajangan terbuka setelah onboarding (flags.tutorialDone).
	requiresTutorialDone = true,
	-- Warna placeholder Body per elemen (RGB).
	elementColors = {
		Api = { r = 235, g = 96, b = 64 },
		Es = { r = 120, g = 196, b = 255 },
		Petir = { r = 250, g = 220, b = 80 },
		Cahaya = { r = 255, g = 244, b = 200 },
		Bayangan = { r = 120, g = 86, b = 170 },
	},
})
