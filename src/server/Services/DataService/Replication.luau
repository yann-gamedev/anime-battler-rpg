--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local RemoteSetup = require(script.Parent.Parent.Parent.Net.RemoteSetup)

local Replication = {}

local function clientUnits(profile: Types.Profile): { [string]: Types.ClientOwnedUnit }
	local units: { [string]: Types.ClientOwnedUnit } = {}
	for uid, unit in profile.units do
		units[uid] = {
			uid = uid,
			unitId = unit.unitId,
			stars = unit.stars,
			level = unit.level,
			xp = unit.xp,
			trait = unit.trait,
			locked = unit.locked,
		}
	end
	return units
end

local function handleGetMyData(getProfile: (Player) -> Types.Profile?, player: Player, ...: any): Types.Result
	if select("#", ...) > 0 then
		return { ok = false, code = "INVALID_ARGUMENTS" }
	end
	local profile = getProfile(player)
	if not profile then
		return { ok = false, code = "DATA_NOT_READY" }
	end
	local data: Types.MyData = {
		currencies = table.clone(profile.currencies),
		units = clientUnits(profile),
		teams = TableUtil.deepCopy(profile.teams),
		story = TableUtil.deepCopy(profile.story),
		pity = TableUtil.deepCopy(profile.pity),
	}
	return { ok = true, data = data }
end

function Replication.bind(getProfile: (Player) -> Types.Profile?, changed: Signal.Signal<Player, string>): ()
	RemoteSetup.bindFunction("GetMyData", function(player: Player, ...: any): Types.Result
		return handleGetMyData(getProfile, player, ...)
	end)
	local inventoryChanged = RemoteSetup.getEvent("InventoryChanged")
	local currencyChanged = RemoteSetup.getEvent("CurrencyChanged")
	changed:Connect(function(player: Player, path: string)
		local profile = getProfile(player)
		if not profile or player.Parent ~= Players then
			return
		end
		if path == "units" then
			inventoryChanged:FireClient(player, clientUnits(profile))
		elseif path == "currencies" then
			currencyChanged:FireClient(player, table.clone(profile.currencies))
		end
	end)
end

return table.freeze(Replication)
