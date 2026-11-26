--!strict
local Types = require(script.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Config.Constants)
local State = require(script.Parent.State)

local Targeting = {}
local WIDTH = math.sqrt(Constants.BOARD_SLOTS)
local HEIGHT = WIDTH * 2

function Targeting.startCell(side: Types.BattleSide, homeCell: number): number
	-- Rotate the two local boards so each team's front row faces the other.
	return if side == "A" then Constants.BOARD_SLOTS + 1 - homeCell else Constants.BOARD_SLOTS + homeCell
end

function Targeting.opposite(side: Types.BattleSide): Types.BattleSide
	return if side == "A" then "B" else "A"
end

local function x(cell: number): number
	return (cell - 1) % WIDTH + 1
end

local function y(cell: number): number
	return math.floor((cell - 1) / WIDTH) + 1
end

function Targeting.distance(a: number, b: number): number
	return math.abs(x(a) - x(b)) + math.abs(y(a) - y(b))
end

function Targeting.living(team: { State.Unit }): { State.Unit }
	local units: { State.Unit } = {}
	for _, unit in team do
		if unit.hp > 0 then
			table.insert(units, unit)
		end
	end
	return units
end

function Targeting.byHealth(a: State.Unit, b: State.Unit): boolean
	return if a.hp == b.hp then a.id < b.id else a.hp < b.hp
end

function Targeting.byDistance(cell: number): (State.Unit, State.Unit) -> boolean
	return function(a, b)
		local da, db = Targeting.distance(cell, a.cell), Targeting.distance(cell, b.cell)
		return if da == db then a.id < b.id else da < db
	end
end

function Targeting.backline(enemies: { State.Unit }): State.Unit?
	local target: State.Unit? = nil
	local bestRow = -1
	for _, enemy in enemies do
		local row = y(enemy.homeCell)
		if row > bestRow or (row == bestRow and target and Targeting.byHealth(enemy, target)) then
			target = enemy
			bestRow = row
		end
	end
	return target
end

function Targeting.choose(fight: State.Fight, unit: State.Unit, enemies: { State.Unit }): (State.Unit?, boolean)
	local taunt = unit.taunt
	if taunt and taunt.untilTick > fight.tick then
		local enemy = fight.units[taunt.value]
		if enemy.hp > 0 then
			return enemy, Targeting.distance(unit.cell, enemy.cell) <= unit.stats.range
		end
	end

	local frontAlive = false
	if unit.stats.range == 1 and unit.def.class ~= "Assassin" then
		for _, enemy in enemies do
			if enemy.owner == nil and enemy.homeCell <= WIDTH then
				frontAlive = true
				break
			end
		end
	end

	local inRange: State.Unit? = nil
	local nearest: State.Unit? = nil
	local byDistance = Targeting.byDistance(unit.cell)
	for _, enemy in enemies do
		if not frontAlive or enemy.homeCell <= WIDTH then
			if nearest == nil or byDistance(enemy, nearest) then
				nearest = enemy
			end
			if Targeting.distance(unit.cell, enemy.cell) <= unit.stats.range then
				if
					inRange == nil
					or (unit.def.class == "Mage" and (enemy.hp > inRange.hp or (enemy.hp == inRange.hp and enemy.id < inRange.id)))
					or (unit.def.class ~= "Mage" and byDistance(enemy, inRange))
				then
					inRange = enemy
				end
			end
		end
	end
	return inRange or nearest, inRange ~= nil
end

local function occupied(fight: State.Fight, mover: State.Unit): { [number]: boolean }
	local result: { [number]: boolean } = {}
	for _, unit in fight.units do
		if unit.hp > 0 and unit ~= mover and unit.owner == nil then
			result[unit.cell] = true
		end
	end
	return result
end

function Targeting.leapCell(fight: State.Fight, unit: State.Unit, target: State.Unit): number
	local blocked = occupied(fight, unit)
	local rear = if target.side == "A" then target.cell - WIDTH else target.cell + WIDTH
	if rear >= 1 and rear <= WIDTH * HEIGHT and not blocked[rear] then
		return rear
	end
	for cell = 1, WIDTH * HEIGHT do
		if not blocked[cell] and Targeting.distance(cell, target.cell) == 1 then
			return cell
		end
	end
	return unit.cell
end

function Targeting.stepToward(fight: State.Fight, unit: State.Unit, target: State.Unit): number?
	local blocked = occupied(fight, unit)
	blocked[target.cell] = true
	local queue = { unit.cell }
	local firstStep: { [number]: number } = { [unit.cell] = unit.cell }
	local head = 1
	while head <= #queue do
		local cell = queue[head]
		head += 1
		if Targeting.distance(cell, target.cell) <= unit.stats.range then
			return firstStep[cell]
		end
		local neighbors: { number } = {}
		if y(cell) > 1 then
			table.insert(neighbors, cell - WIDTH)
		end
		if y(cell) < HEIGHT then
			table.insert(neighbors, cell + WIDTH)
		end
		if x(cell) > 1 then
			table.insert(neighbors, cell - 1)
		end
		if x(cell) < WIDTH then
			table.insert(neighbors, cell + 1)
		end
		for _, neighbor in neighbors do
			if not blocked[neighbor] and not firstStep[neighbor] then
				firstStep[neighbor] = if cell == unit.cell then neighbor else firstStep[cell]
				table.insert(queue, neighbor)
			end
		end
	end
	return nil
end

return table.freeze(Targeting)
