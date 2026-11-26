--!strict
local Workspace = game:GetService("Workspace")

local model = Instance.new("Model")
model.Name = "ArcanumLobby"
model:SetAttribute("ArcanumLobbyBuild", true)
model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

local slate = Color3.fromRGB(45, 48, 77)
local stone = Color3.fromRGB(83, 88, 126)
local trim = Color3.fromRGB(235, 197, 122)
local violet = Color3.fromRGB(165, 125, 255)
local teal = Color3.fromRGB(103, 228, 217)
local coral = Color3.fromRGB(248, 122, 131)
local origin = Vector3.new(0, 2, 0)

local function block(name: string, x: number, y: number, z: number, size: Vector3, color: Color3, solid: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = solid == true
	part.CanTouch = false
	part.CanQuery = part.CanCollide
	part.Position = origin + Vector3.new(x, y, z)
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function sign(part: BasePart, title: string): ()
	local surface = Instance.new("BillboardGui")
	surface.Size = UDim2.fromScale(8, 2)
	surface.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 0.8, 0)
	surface.MaxDistance = 36
	surface.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(247, 239, 222)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Text = title
	label.Font = Enum.Font.GothamBold
	label.Parent = surface
end

local function prompt(part: BasePart, route: string, title: string): ()
	local marker = Instance.new("ProximityPrompt")
	marker.Name = route .. "Prompt"
	marker.ActionText = "Open"
	marker.ObjectText = title
	marker.KeyboardKeyCode = Enum.KeyCode.E
	marker.GamepadKeyCode = Enum.KeyCode.ButtonX
	marker.MaxActivationDistance = 9
	marker.RequiresLineOfSight = false
	marker.ClickablePrompt = true
	marker:SetAttribute("LobbyRoute", route)
	marker.Parent = part
end

block("FloatingFoundation", 0, -3, 0, Vector3.new(82, 4, 68), slate, true)
block("Courtyard", 0, -0.5, 0, Vector3.new(82, 1, 68), stone, true)
block("CentralWalk", 0, 0.01, 0, Vector3.new(12, 0.08, 62), slate)
block("CrossWalk", 0, 0.01, 0, Vector3.new(76, 0.08, 8), slate)
for _, x in { -40.5, 40.5 } do
	block("SideWall", x, 1.1, 0, Vector3.new(1, 2.2, 68), slate, true)
end
for _, z in { -33.5, 33.5 } do
	block("EndWall", 0, 1.1, z, Vector3.new(82, 2.2, 1), slate, true)
end
for _, x in { -37, 37 } do
	for _, z in { -30, 30 } do
		block("Turret", x, 3, z, Vector3.new(4, 6, 4), slate, true)
		local cap = block("TurretCap", x, 6.5, z, Vector3.new(4.8, 1, 4.8), trim)
		cap.Rotation = Vector3.new(0, 22.5, 0)
	end
end

local spawn = Instance.new("SpawnLocation")
spawn.Name = "AcademySpawn"
spawn.Size = Vector3.new(10, 0.2, 8)
spawn.Position = origin + Vector3.new(0, 0.1, 23)
spawn.Anchored = true
spawn.Neutral = true
spawn.Duration = 0
spawn.Color = trim
spawn.Parent = model

for _, x in { -4, 4 } do
	block("PortalColumn", x, 3.5, -25, Vector3.new(2, 7, 2), slate, true)
end
block("PortalArch", 0, 7, -25, Vector3.new(10, 1.4, 2), trim)
local portal = block("StoryPortal", 0, 3, -25, Vector3.new(6, 6, 0.35), violet)
portal.Material = Enum.Material.Neon
portal.Transparency = 0.26
sign(portal, "Story Portal")
prompt(portal, "Story", "Story Portal")

local function station(route: string, title: string, x: number, z: number, color: Color3): ()
	block(route .. "Plinth", x, 0.5, z, Vector3.new(5, 1, 5), slate, true)
	local crystal = block(route, x, 2.6, z, Vector3.new(2, 2, 2), color)
	crystal.Material = Enum.Material.Neon
	crystal.Rotation = Vector3.new(24, 45, 24)
	sign(crystal, title)
	prompt(crystal, route, title)
end

station("Summon", "Summon Altar", -23, -16, violet)
station("Quests", "Quest Desk", -24, 2, teal)
station("Raid", "Boss Raid", 24, -16, coral)

local merchant = block("AcademyMerchant", 24, 1.5, 2, Vector3.new(2, 3, 1.4), slate)
block("MerchantHead", 24, 3.3, 2, Vector3.new(1.4, 1.2, 1.3), trim)
block("MerchantHat", 24, 4.05, 2, Vector3.new(2.3, 0.4, 2.1), violet)
sign(merchant, "Academy Shop")
prompt(merchant, "Shop", "Academy Shop")

local board = block("AnnouncementsBoard", -22, 3.5, 20, Vector3.new(8, 4, 0.5), slate, true)
for _, x in { -25, -19 } do
	block("BoardPost", x, 1.3, 20, Vector3.new(0.5, 2.6, 0.5), trim, true)
end
sign(board, "Announcements")
prompt(board, "Announcements", "Announcements")

block("TradingPlaza", 23, 0.02, 21, Vector3.new(22, 0.1, 16), slate)
local plaza = block("PlazaSign", 23, 2.2, 29, Vector3.new(7, 2, 0.5), stone, true)
sign(plaza, "Trading Plaza")

local old = Workspace:FindFirstChild(model.Name)
assert(not old or old:GetAttribute("ArcanumLobbyBuild") == true, "ArcanumLobby is already reserved by another object.")
if old then
	old:Destroy()
end
model.Parent = Workspace
print("[Lobby] ArcanumLobby built. Save the place to keep it.")
