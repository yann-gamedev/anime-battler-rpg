--!strict
-- Bagian DataService: perintah admin Studio (server Command Bar saja, tanpa remote). Dipindah dari init.luau
-- agar file < 400 baris; perilaku tidak berubah kecuali reset ditolak selama item pemain dikunci trade.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Template = require(script.Parent.Template)

local Admin = {}

function Admin.isStudioAdmin(player: Player): boolean
	return RunService:IsStudio() and table.find(Constants.ADMIN_USER_IDS, player.UserId) ~= nil
end

-- target = modul DataService (memakai target.addCurrency & target.Changed).
function Admin.attach(
	target: any,
	getSession: (Player) -> any,
	grantStarterUnits: (profile: Types.Profile) -> (),
	isTradeLocked: (player: Player) -> boolean
): ()
	-- Studio server Command Bar only. Both commands operate on the allowlisted player's own session.
	function target.adminResetProfile(player: Player): boolean
		local session = if Admin.isStudioAdmin(player) then getSession(player) else nil
		if not session or isTradeLocked(player) then
			return false
		end
		local profile = Template.create(os.time())
		grantStarterUnits(profile)
		session.Data = profile
		session:Save()
		target.Changed:Fire(player, "units")
		target.Changed:Fire(player, "currencies")
		target.Changed:Fire(player, "teams")
		return true
	end

	function target.adminAddGems(player: Player, amount: number): boolean
		return Admin.isStudioAdmin(player) and target.addCurrency(player, "Gems", amount, "studio_admin")
	end
end

return table.freeze(Admin)
