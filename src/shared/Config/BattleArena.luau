--!strict
local Constants = require(script.Parent.Constants)

local columns = math.sqrt(Constants.BOARD_SLOTS)
local cellSize = 7
local gap = 3
local BattleArena = {
	modelName = "BattleArena",
	originName = "Origin",
	columns = columns,
	cellSize = cellSize,
	width = columns * cellSize,
	depth = 2 * columns * cellSize + gap,
}

-- Replay cells are row-major on the combined board, with the seam between rows 3 and 4.
function BattleArena.cellOffset(cell: number): (number, number)
	local column = (cell - 1) % columns
	local row = math.floor((cell - 1) / columns)
	local x = (column - (columns - 1) / 2) * cellSize
	local z = (row - (2 * columns - 1) / 2) * cellSize + (if row < columns then -gap else gap) / 2
	return x, z
end

return table.freeze(BattleArena)
