--!strict
-- Model pajangan lobby yang dibuat SERVER di karakter pemain (tereplikasi ke semua client).
-- Ringan: 2 Part massless tanpa collision/query + Weld + Motor6D. Server tidak pernah menulis
-- IdleJoint.Transform dan tidak punya loop render; animasi idle & visual unit/skin/aura dibuat client.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Lobby = require(Shared.Config.Lobby)
local Units = require(Shared.Config.Units)

export type Spec = { unitId: string, skinId: string?, stars: number, vipAura: boolean, ownerUserId: number }

local Showcase = {}

local function inertPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	return part
end

-- Kunci perbandingan agar model hanya dibangun ulang saat isinya berubah.
function Showcase.key(spec: Spec?): string
	if not spec then
		return ""
	end
	return `{spec.unitId}|{spec.skinId or ""}|{spec.stars}|{spec.vipAura}`
end

function Showcase.remove(character: Model?): ()
	local existing = if character then character:FindFirstChild(Lobby.modelName) else nil
	if existing then
		existing:Destroy()
	end
end

-- Membangun ulang pajangan pada karakter. Boleh yield (menunggu HumanoidRootPart). `isCurrent` false setelah
-- menunggu = permintaan ini sudah digantikan permintaan yang lebih baru (hindari model basi).
function Showcase.apply(character: Model?, spec: Spec?, isCurrent: () -> boolean): ()
	if not character then
		return
	end
	Showcase.remove(character)
	local def = if spec then Units[spec.unitId] else nil
	if not spec or not def then
		return
	end
	local hrp = character:WaitForChild("HumanoidRootPart", Lobby.rootWaitSeconds)
	if not hrp or not hrp:IsA("BasePart") or character.Parent == nil or not isCurrent() then
		return
	end
	Showcase.remove(character)

	local offset = CFrame.new(Lobby.offset.x, Lobby.offset.y, Lobby.offset.z)
	local lift = CFrame.new(0, Lobby.bodyLift, 0)
	local model = Instance.new("Model")
	model.Name = Lobby.modelName
	local root = inertPart(Lobby.rootName, Vector3.one)
	root.Transparency = 1
	root.CFrame = hrp.CFrame * offset
	root.Parent = model
	local size = Lobby.bodySize
	local body = inertPart(Lobby.bodyName, Vector3.new(size.x, size.y, size.z))
	local color = Lobby.elementColors[def.element]
	body.Color = if color then Color3.fromRGB(color.r, color.g, color.b) else Color3.new(1, 1, 1)
	body.CFrame = root.CFrame * lift
	body.Parent = model

	local weld = Instance.new("Weld")
	weld.Name = Lobby.weldName
	weld.Part0 = hrp
	weld.Part1 = root
	weld.C0 = offset
	weld.Parent = root
	local joint = Instance.new("Motor6D")
	joint.Name = Lobby.jointName
	joint.Part0 = root
	joint.Part1 = body
	joint.C0 = lift
	joint.Parent = root

	model.PrimaryPart = root
	model:SetAttribute("UnitId", spec.unitId)
	model:SetAttribute("SkinId", spec.skinId or "")
	model:SetAttribute("Stars", spec.stars)
	model:SetAttribute("VipAura", spec.vipAura)
	model:SetAttribute("OwnerUserId", spec.ownerUserId)
	model.Parent = character
end

return table.freeze(Showcase)
