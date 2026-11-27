--!strict
-- Syarat lokasi trade (SYSTEMS A3): satu server, kedua avatar hidup, berada di Trading Plaza, dan berdekatan.
-- Posisi diambil dari karakter yang diamati server (bukan dari client). Plaza = BasePart
-- Workspace.<lobbyName>.<partName> dari studio/world/build_lobby.luau; jarak dari Config/Trade.plaza.
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Trade = require(Shared.Config.Trade)

local PLAZA = Trade.plaza
local Proximity = {}

-- Titik lokal relatif pusat part (x, y, z) di dalam footprint plaza + margin dan rentang tinggi.
function Proximity.isInsidePlaza(x: number, y: number, z: number, sizeX: number, sizeY: number, sizeZ: number): boolean
	local height = y - sizeY / 2
	return math.abs(x) <= sizeX / 2 + PLAZA.horizontalMargin
		and math.abs(z) <= sizeZ / 2 + PLAZA.horizontalMargin
		and height >= PLAZA.minHeight
		and height <= PLAZA.maxHeight
end

function Proximity.isWithinPair(distance: number): boolean
	return distance == distance and distance <= PLAZA.maxPairDistance
end

local function findPlaza(): BasePart?
	local lobby = Workspace:FindFirstChild(PLAZA.lobbyName)
	local part = lobby and lobby:FindFirstChild(PLAZA.partName)
	return if part and part:IsA("BasePart") then part else nil
end

-- Posisi HumanoidRootPart avatar hidup milik pemain yang masih di server, atau nil.
local function rootPosition(player: Player): Vector3?
	if player.Parent == nil then
		return nil
	end
	local character = player.Character
	if not character or character.Parent == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

-- nil = lolos. Kode: PLAZA_UNAVAILABLE | AVATAR_NOT_READY | NOT_IN_PLAZA | TOO_FAR.
function Proximity.check(a: Player, b: Player): string?
	local plaza = findPlaza()
	if not plaza then
		return "PLAZA_UNAVAILABLE"
	end
	local positionA, positionB = rootPosition(a), rootPosition(b)
	if not positionA or not positionB then
		return "AVATAR_NOT_READY"
	end
	for _, position in { positionA, positionB } do
		local localPoint = plaza.CFrame:PointToObjectSpace(position)
		local size = plaza.Size
		if not Proximity.isInsidePlaza(localPoint.X, localPoint.Y, localPoint.Z, size.X, size.Y, size.Z) then
			return "NOT_IN_PLAZA"
		end
	end
	if not Proximity.isWithinPair((positionA - positionB).Magnitude) then
		return "TOO_FAR"
	end
	return nil
end

return table.freeze(Proximity)
