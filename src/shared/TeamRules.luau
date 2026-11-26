--!strict
-- Aturan murni validasi papan tim (tanpa Instance, bisa di-test).
-- Dipakai TeamService di server; client boleh memakai untuk umpan balik UI saja.
local Constants = require(script.Parent.Config.Constants)
local Products = require(script.Parent.Config.Products)

export type FailureCode = "INVALID_SLOTS" | "UNIT_NOT_OWNED" | "DUPLICATE_UNIT" | "TOO_MANY_UNITS"

local TeamRules = {}

TeamRules.EMPTY_SLOT = ""

-- Validasi bentuk & isi `slots`: array dense tepat BOARD_SLOTS string, "" = kosong.
-- Urutan cek: bentuk/tipe → kepemilikan → duplikat → jumlah.
function TeamRules.validateSlots(slots: any, ownedByUid: { [string]: boolean }, maxUnits: number): (boolean, string?)
	if typeof(maxUnits) ~= "number" or maxUnits ~= maxUnits or maxUnits < 0 or math.floor(maxUnits) ~= maxUnits then
		error("TeamRules.validateSlots: maxUnits harus integer >= 0")
	end
	if typeof(slots) ~= "table" or getmetatable(slots) ~= nil then
		return false, "INVALID_SLOTS"
	end

	local boardSlots = Constants.BOARD_SLOTS
	local keyCount = 0
	for key, value in slots do
		keyCount += 1
		if keyCount > boardSlots then
			return false, "INVALID_SLOTS"
		end
		if typeof(key) ~= "number" or math.floor(key) ~= key or key < 1 or key > boardSlots then
			return false, "INVALID_SLOTS"
		end
		if typeof(value) ~= "string" or #value > Constants.MAX_UID_LENGTH then
			return false, "INVALID_SLOTS"
		end
	end
	if keyCount ~= boardSlots then
		return false, "INVALID_SLOTS"
	end

	local seen: { [string]: boolean } = {}
	local placed = 0
	for index = 1, boardSlots do
		local uid = slots[index] :: string
		if uid ~= TeamRules.EMPTY_SLOT then
			if ownedByUid[uid] ~= true then
				return false, "UNIT_NOT_OWNED"
			end
			if seen[uid] then
				return false, "DUPLICATE_UNIT"
			end
			seen[uid] = true
			placed += 1
		end
	end

	if placed > maxUnits then
		return false, "TOO_MANY_UNITS"
	end
	return true, nil
end

-- Indeks preset tim yang sah: integer 1..(TEAM_PRESETS_BASE + extraPresets). extraPresets dari cache
-- gamepass server (0 atau Config/Products.extraPresetsWithPass); nilai lain dianggap 0.
function TeamRules.isTeamIndex(value: any, extraPresets: number): boolean
	local extra = if extraPresets == Products.extraPresetsWithPass then extraPresets else 0
	return typeof(value) == "number"
		and value == value
		and math.floor(value) == value
		and value >= 1
		and value <= Constants.TEAM_PRESETS_BASE + extra
end

return table.freeze(TeamRules)
