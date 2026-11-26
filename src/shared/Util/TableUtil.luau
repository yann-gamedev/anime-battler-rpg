--!strict
-- Utilitas tabel murni (tanpa Instance).

local TableUtil = {}

-- Membekukan tabel beserta semua sub-tabelnya (dipakai untuk Config).
function TableUtil.deepFreeze<T>(tbl: T): T
	local t = tbl :: any
	if typeof(t) ~= "table" or table.isfrozen(t) then
		return tbl
	end
	for _, value in t do
		if typeof(value) == "table" then
			TableUtil.deepFreeze(value)
		end
	end
	table.freeze(t)
	return tbl
end

-- Salinan dalam (untuk tabel data tanpa siklus).
function TableUtil.deepCopy<T>(tbl: T): T
	local t = tbl :: any
	if typeof(t) ~= "table" then
		return tbl
	end
	local copy = {}
	for key, value in t do
		copy[key] = TableUtil.deepCopy(value)
	end
	return (copy :: any) :: T
end

return TableUtil
