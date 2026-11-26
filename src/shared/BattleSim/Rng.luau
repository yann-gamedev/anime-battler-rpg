--!strict
local Rng = {}
export type State = { value: number }

local UINT32_SIZE = 2 ^ 32
local ZERO_SEED_STATE = 0x6D2B79F5

function Rng.new(seed: number): State
	assert(seed % 1 == 0 and math.abs(seed) < 2 ^ 53, "Battle seed must be an exact integer")
	local value = seed % UINT32_SIZE
	return { value = if value == 0 then ZERO_SEED_STATE else value }
end

function Rng.nextNumber(state: State): number
	local value = state.value
	value = bit32.bxor(value, bit32.lshift(value, 13))
	value = bit32.bxor(value, bit32.rshift(value, 17))
	value = bit32.bxor(value, bit32.lshift(value, 5))
	state.value = value
	return value / UINT32_SIZE
end

return table.freeze(Rng)
