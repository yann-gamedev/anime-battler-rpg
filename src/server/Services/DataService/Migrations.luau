--!strict
-- Migrasi skema: [fromVersion] = function(profile) yang menaikkan ke fromVersion + 1.
-- Jangan hapus migrasi lama; jangan ubah arti field lama (docs/RULES.md §3).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared").Config.Constants)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)

local Migrations = {}

local steps: { [number]: (profile: any) -> () } = {
	-- v1 adalah versi awal; belum ada migrasi.
}

-- Menjalankan migrasi berurutan sampai DATA_VERSION. Error jika ada langkah yang hilang.
function Migrations.run(profile: any): ()
	local current = profile.version
	assert(Validate.isInt(current) and current >= 1, "profile.version tidak valid")
	assert(current <= Constants.DATA_VERSION, "profile.version lebih baru dari server")
	while current < Constants.DATA_VERSION do
		local step = steps[current]
		assert(step, `Migrasi dari versi {current} tidak ada`)
		step(profile)
		current += 1
		profile.version = current
	end
end

return table.freeze(Migrations)
