--!strict
-- Signal server-only untuk aktivitas yang sudah terverifikasi & di-commit server (progres quest, prompt 10).
-- Pemanggil: StageService (story menang + bintang), InventoryService (level up), RaidService (percobaan raid).
-- Tidak ada remote yang memicu ini secara langsung; memutar replay di client tidak menambah progres.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)

local Activity = {}

Activity.fired = Signal.new() :: Signal.Signal<Player, Types.ActivityKind, number>

-- amount: bilangan bulat >= 1 (mis. jumlah level atau bintang). Nilai lain diabaikan.
function Activity.report(player: Player, kind: Types.ActivityKind, amount: number): ()
	if type(amount) ~= "number" or amount < 1 or amount ~= amount or math.floor(amount) ~= amount then
		return
	end
	Activity.fired:Fire(player, kind, amount)
end

return table.freeze(Activity)
