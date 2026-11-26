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

-- Array string dense tanpa metatable & tanpa kunci lain, jumlah minCount..maxCount,
-- setiap string tidak kosong dan panjang <= maxLen. Iterasi berhenti segera setelah batas terlampaui.
function Validate.isStringArray(value: any, minCount: number, maxCount: number, maxLen: number): boolean
	if typeof(value) ~= "table" or getmetatable(value) ~= nil then
		return false
	end
	local count = 0
	for key, item in value do
		count += 1
		if count > maxCount or not Validate.isIntInRange(key, 1, maxCount) then
			return false
		end
		if typeof(item) ~= "string" or item == "" or #item > maxLen then
			return false
		end
	end
	if count < minCount then
		return false
	end
	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end
	return true
end

return table.freeze(Validate)
