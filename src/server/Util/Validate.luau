--!strict
-- Helper validasi argumen remote (docs/RULES.md §2). Semua fungsi murni.

local Validate = {}

function Validate.isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.isInt(value: any): boolean
	return Validate.isFiniteNumber(value) and math.floor(value) == value
end

function Validate.isIntInRange(value: any, min: number, max: number): boolean
	return Validate.isInt(value) and value >= min and value <= max
end

-- Mengembalikan predikat: string dengan panjang <= maxLen.
function Validate.isStringMax(maxLen: number): (value: any) -> boolean
	return function(value: any): boolean
		return typeof(value) == "string" and #value <= maxLen
	end
end

-- Mengembalikan predikat: nilai termasuk dalam set (array nilai yang diizinkan).
function Validate.isOneOf(allowed: { any }): (value: any) -> boolean
	local set: { [any]: boolean } = {}
	for _, item in allowed do
		set[item] = true
	end
	return function(value: any): boolean
		return value ~= nil and set[value] == true
	end
end

return table.freeze(Validate)
