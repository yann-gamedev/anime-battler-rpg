--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared =
	assert(ReplicatedStorage:FindFirstChild("Shared"), "Connect Rojo in Studio edit mode before building the arena.")
local Arena = require(shared.Config.BattleArena)
local Colors = {
	slab = Color3.fromRGB(18, 21, 35),
	near = Color3.fromRGB(46, 61, 88),
	nearAlt = Color3.fromRGB(55, 72, 102),
	far = Color3.fromRGB(76, 48, 72),
	farAlt = Color3.fromRGB(91, 55, 83),
	rune = Color3.fromRGB(172, 155, 236),
}

local model = Instance.new("Model")
model.Name = Arena.modelName
model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
local center = Vector3.new(0, 48, -180)

local function block(name: string, position: Vector3, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Position = position
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local origin = block(Arena.originName, center, Vector3.one, Colors.slab, Enum.Material.SmoothPlastic)
origin.Transparency = 1
model.PrimaryPart = origin
block(
	"Foundation",
	center - Vector3.new(0, 1.25, 0),
	Vector3.new(Arena.width + 6, 2, Arena.depth + 6),
	Colors.slab,
	Enum.Material.Slate
)
block(
	"Centerline",
	center - Vector3.new(0, 0.15, 0),
	Vector3.new(Arena.width, 0.18, 0.25),
	Colors.rune,
	Enum.Material.Neon
)

for cell = 1, 2 * Arena.columns ^ 2 do
	local x, z = Arena.cellOffset(cell)
	local color = if cell <= Arena.columns ^ 2
		then (if cell % 2 == 0 then Colors.nearAlt else Colors.near)
		else (if cell % 2 == 0 then Colors.farAlt else Colors.far)
	block(
		`Tile_{cell}`,
		center + Vector3.new(x, -0.2, z),
		Vector3.new(Arena.cellSize - 0.3, 0.4, Arena.cellSize - 0.3),
		color,
		Enum.Material.Slate
	)
end
for _, x in { -Arena.width / 2 - 1.2, Arena.width / 2 + 1.2 } do
	block(
		"RuneRail",
		center + Vector3.new(x, -0.1, 0),
		Vector3.new(0.16, 0.22, Arena.depth),
		Colors.rune,
		Enum.Material.Neon
	)
end

local old = Workspace:FindFirstChild(Arena.modelName)
if old then
	old:Destroy()
end
model.Parent = Workspace
print("[Arena] BattleArena built. Save the place to keep it.")
