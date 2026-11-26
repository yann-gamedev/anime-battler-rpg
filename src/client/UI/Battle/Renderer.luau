--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Arena = require(Shared.Config.BattleArena)
local Units = require(Shared.Config.Units)
local Theme = require(script.Parent.Parent.Theme)

local friendly = Color3.fromRGB(128, 234, 191)
local enemy = Color3.fromRGB(255, 141, 152)
local MAX_VISIBLE = 2 * Constants.BOARD_UNITS_MAX
local MAX_EFFECTS = 28
local MOVE_TIME = 1 / Constants.BATTLE_TICKS_PER_SECOND

type ModelView = { part: Part, health: Frame, shield: Frame, moveTween: Tween? }
type Unit = {
	id: number,
	name: string,
	color: Color3,
	side: Types.BattleSide,
	cell: number,
	hp: number,
	maxHp: number,
	shield: number,
	temporary: boolean,
	view: ModelView?,
}
type Effect = { part: Part, tween: Tween, untilTime: number }
export type Scene = { folder: Folder, origin: BasePart, units: { Unit }, effects: { Effect }, seconds: number }
local Renderer = {}

local function part(parent: Instance, color: Color3): Part
	local block = Instance.new("Part")
	block.Anchored = true
	block.CanCollide = false
	block.CanTouch = false
	block.CanQuery = false
	block.CastShadow = false
	block.Color = color
	block.Material = Enum.Material.SmoothPlastic
	block.Parent = parent
	return block
end

local function position(scene: Scene, cell: number, height: number): Vector3
	local x, z = Arena.cellOffset(cell)
	return scene.origin.CFrame:PointToWorldSpace(Vector3.new(x, height, z))
end

local function unitPosition(scene: Scene, unit: Unit): Vector3
	if not unit.temporary then
		return position(scene, unit.cell, 1.35)
	end
	local angle = unit.id % 6 * math.pi / 3
	local spread = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 1.65
	return position(scene, unit.cell, 2.65) + scene.origin.CFrame:VectorToWorldSpace(spread)
end

local function stopMove(view: ModelView): ()
	local tween = view.moveTween
	if tween then
		tween:Cancel()
		tween:Destroy()
		view.moveTween = nil
	end
end

local function health(unit: Unit): ()
	local view = unit.view
	if not view then
		return
	end
	view.health.Size = UDim2.fromScale(math.clamp(unit.hp / unit.maxHp, 0, 1), 1)
	view.shield.Size = UDim2.fromScale(math.clamp(unit.shield / unit.maxHp, 0, 1), 1)
end

local function billboard(block: Part, size: UDim2, offset: Vector3): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.Parent = block
	return gui
end

local function mount(scene: Scene, unit: Unit): ()
	local block = part(scene.folder, unit.color)
	block.Name = unit.name
	block.Shape = if unit.temporary then Enum.PartType.Ball else Enum.PartType.Block
	block.Size = if unit.temporary then Vector3.new(1.25, 1.25, 1.25) else Vector3.new(2.25, 2.7, 2.25)
	block.Position = unitPosition(scene, unit)

	local gui = billboard(block, UDim2.new(6.4, 0, 0, 27), Vector3.new(0, block.Size.Y / 2 + 0.65, 0))
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 17)
	name.BackgroundTransparency = 1
	name.Text = unit.name
	name.TextSize = Theme.textSize
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Font = Theme.bold
	name.TextColor3 = Theme.text
	name.TextStrokeTransparency = 0.25
	name.Parent = gui
	local track = Instance.new("Frame")
	track.Position = UDim2.fromScale(0.1, 0.7)
	track.Size = UDim2.new(0.8, 0, 0, 5)
	track.BorderSizePixel = 0
	track.BackgroundColor3 = Theme.background
	track.Parent = gui
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = if unit.side == "A" then friendly else enemy
	fill.Parent = track
	local shield = Instance.new("Frame")
	shield.AnchorPoint = Vector2.new(0, 1)
	shield.Size = UDim2.fromScale(0, 1)
	shield.Position = UDim2.fromScale(0, 0)
	shield.BorderSizePixel = 0
	shield.BackgroundColor3 = Theme.rarity.Rare
	shield.Parent = track
	unit.view = { part = block, health = fill, shield = shield }
	health(unit)
end

local function unmount(unit: Unit): ()
	local view = unit.view
	if view then
		stopMove(view)
		view.part:Destroy()
		unit.view = nil
	end
end

-- Originals take priority; only available visual slots are used for summons.
local function reconcile(scene: Scene): ()
	local shown = 0
	for _, temporary in { false, true } do
		for _, unit in scene.units do
			if unit.temporary == temporary then
				if unit.hp > 0 and shown < MAX_VISIBLE then
					shown += 1
					if not unit.view then
						mount(scene, unit)
					end
				else
					unmount(unit)
				end
			end
		end
	end
end

local function dropEffect(effect: Effect): ()
	effect.tween:Cancel()
	effect.tween:Destroy()
	effect.part:Destroy()
end

local function animate(scene: Scene, block: Part, duration: number, properties: { [string]: any }): ()
	if #scene.effects >= MAX_EFFECTS then
		dropEffect(table.remove(scene.effects, 1) :: Effect)
	end
	local tween = TweenService:Create(block, TweenInfo.new(duration, Enum.EasingStyle.Quad), properties)
	table.insert(scene.effects, { part = block, tween = tween, untilTime = scene.seconds + duration })
	tween:Play()
end

function Renderer.new(origin: BasePart): Scene
	local folder = Instance.new("Folder")
	folder.Name = "BattleReplayVisuals"
	folder.Parent = Workspace
	return { folder = folder, origin = origin, units = {}, effects = {}, seconds = 0 }
end

function Renderer.clearEffects(scene: Scene): ()
	for _, effect in scene.effects do
		dropEffect(effect)
	end
	table.clear(scene.effects)
end

function Renderer.destroy(scene: Scene): ()
	Renderer.clearEffects(scene)
	for _, unit in scene.units do
		unmount(unit)
	end
	table.clear(scene.units)
	scene.folder:Destroy()
end

function Renderer.step(scene: Scene, delta: number): ()
	scene.seconds += delta
	for index = #scene.effects, 1, -1 do
		if scene.effects[index].untilTime <= scene.seconds then
			dropEffect(table.remove(scene.effects, index) :: Effect)
		end
	end
end

function Renderer.unitPosition(scene: Scene, id: number): Vector3?
	local unit = scene.units[id]
	return if unit then unitPosition(scene, unit) else nil
end

local function hit(scene: Scene, src: Unit?, dst: Unit, dmg: number, crit: boolean, attack: boolean, speed: number): ()
	local target = dst.view
	if not target then
		return
	end
	local source = src and src.view
	if attack and src and source then
		local bolt = part(scene.folder, src.color)
		bolt.Name = "AttackBolt"
		bolt.Shape = Enum.PartType.Ball
		bolt.Material = Enum.Material.Neon
		bolt.Size = Vector3.one * 0.48
		bolt.Position = source.part.Position
		animate(scene, bolt, MOVE_TIME / speed, { Position = target.part.Position, Transparency = 1 })
	end
	if dmg > 0 then
		local anchor = part(scene.folder, dst.color)
		anchor.Position = target.part.Position + Vector3.new(0, 2, 0)
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.1
		local gui = billboard(anchor, UDim2.fromOffset(75, 26), Vector3.zero)
		local number = Instance.new("TextLabel")
		number.Size = UDim2.fromScale(1, 1)
		number.BackgroundTransparency = 1
		number.Text = tostring(math.max(1, math.round(dmg)))
		number.TextColor3 = if crit then Theme.rarity.Legendary else Theme.text
		number.TextSize = if crit then 20 else 16
		number.TextStrokeTransparency = 0.15
		number.Font = Theme.bold
		number.Parent = gui
		animate(scene, anchor, 0.46 / speed, { Position = anchor.Position + Vector3.new(0, 2.6, 0) })
	end
end

local function death(scene: Scene, unit: Unit, speed: number): ()
	local view = unit.view
	if view then
		local burst = part(scene.folder, unit.color)
		burst.Name = "DeathFlash"
		burst.Material = Enum.Material.Neon
		burst.Shape = Enum.PartType.Ball
		burst.Size = Vector3.one * 1.2
		burst.Position = view.part.Position
		animate(scene, burst, 0.18 / speed, { Size = Vector3.one * 3.5, Transparency = 1 })
	end
	unit.hp = 0
	unit.shield = 0
	unmount(unit)
end

function Renderer.apply(scene: Scene, event: Types.BattleEvent, speed: number): ()
	if event.kind == "spawn" then
		local def = Units[event.unitId]
		scene.units[event.unit] = {
			id = event.unit,
			name = if event.owner then "Familiar" else def.name,
			color = Theme.element[def.element],
			side = event.side,
			cell = event.cell,
			hp = event.hp,
			maxHp = event.maxHp,
			shield = 0,
			temporary = event.owner ~= nil,
		}
		reconcile(scene)
	elseif event.kind == "move" then
		local unit = scene.units[event.unit]
		unit.cell = event.cell
		local view = unit.view
		if view then
			stopMove(view)
			local goal = unitPosition(scene, unit)
			if event.leap then
				view.part.Position = goal
			else
				local tween = TweenService:Create(view.part, TweenInfo.new(MOVE_TIME / speed), { Position = goal })
				view.moveTween = tween
				tween:Play()
			end
		end
	elseif event.kind == "attack" or event.kind == "damage" then
		local dst = scene.units[event.dst]
		dst.hp, dst.shield = event.hp, event.shield
		health(dst)
		hit(scene, scene.units[event.src], dst, event.dmg, event.crit, event.kind == "attack", speed)
	elseif event.kind == "heal" or event.kind == "shield" then
		local unit = scene.units[event.unit]
		unit.hp, unit.shield = event.hp, event.shield
		health(unit)
	elseif event.kind == "death" or event.kind == "despawn" then
		death(scene, scene.units[event.unit], speed)
		reconcile(scene)
	elseif event.kind == "revive" then
		local unit = scene.units[event.unit]
		unit.hp = event.hp
		reconcile(scene)
		health(unit)
	end
end

return table.freeze(Renderer)
