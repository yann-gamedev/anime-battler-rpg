--!strict
-- Cache kepemilikan gamepass per sesi (docs/RULES.md §4). Sumber otoritas server = cache ini, BUKAN
-- atribut Player. Atribut (PassSpeed2x, PassAutoReplay, PassExtraPresets, PassVipAura) hanya cermin
-- untuk UI. UserOwnsGamePassAsync dipanggil dalam pcall; gagal = belum dimiliki (fail-closed) dan
-- ditandai untuk dicoba lagi. Cache dibersihkan saat pemain keluar.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Products = require(Shared.Config.Products)

export type Deps = {
	ownsAsync: (userId: number, passId: number) -> any, -- boleh yield/error
	isPresent: (player: Player) -> boolean,
	setAttribute: (player: Player, name: string, value: any) -> (),
	onChanged: ((player: Player) -> ())?,
	log: ((message: string) -> ())?,
}
export type Passes = {
	-- (sukses semua). Yield. Boleh dipanggil ulang untuk retry.
	load: (player: Player) -> boolean,
	-- PromptGamePassPurchaseFinished (server). Yield.
	onPurchaseFinished: (player: Player, passId: any, wasPurchased: any) -> (),
	has: (player: Player, key: string) -> boolean,
	extraPresets: (player: Player) -> number,
	clear: (player: Player) -> (),
	-- Hanya test / Studio admin.
	setForTest: (player: Player, key: string, owned: boolean) -> (),
}

local Passes = {}

local function passKeys(definitions: { [string]: Types.ProductDef }): { string }
	local keys: { string } = {}
	for key, def in definitions do
		if def.kind == "GamePass" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

function Passes.create(deps: Deps, definitions: { [string]: Types.ProductDef }?): Passes
	local defs = definitions or Products.definitions
	local keys = passKeys(defs)
	local cache: { [Player]: { [string]: boolean } } = {}
	local log = deps.log or warn

	local function has(player: Player, key: string): boolean
		local owned = cache[player]
		return owned ~= nil and owned[key] == true
	end

	local function extraPresets(player: Player): number
		return if has(player, "gp_presets") then Products.extraPresetsWithPass else 0
	end

	local function publish(player: Player): ()
		if not deps.isPresent(player) then
			return
		end
		for key, attribute in Products.passAttributes do
			if key == "gp_presets" then
				deps.setAttribute(player, attribute, extraPresets(player))
			else
				deps.setAttribute(player, attribute, has(player, key))
			end
		end
		if deps.onChanged then
			deps.onChanged(player)
		end
	end

	local function fetch(player: Player, passId: number): boolean?
		local ok, result = pcall(deps.ownsAsync, player.UserId, passId)
		if not ok or type(result) ~= "boolean" then
			log(`[Monetization] UserOwnsGamePassAsync gagal UserId={player.UserId} pass={passId}: {result}`)
			return nil
		end
		return result
	end

	local function load(player: Player): boolean
		local allOk = true
		local results: { [string]: boolean } = {}
		for _, key in keys do
			local id = defs[key].id
			if id > 0 then
				local owned = fetch(player, id)
				allOk = allOk and owned ~= nil
				results[key] = owned == true
			end
		end
		if not deps.isPresent(player) then
			return true
		end
		local current = cache[player] or {}
		for key, owned in results do
			-- Kepemilikan dalam sesi tidak dicabut oleh lookup yang gagal / cache Roblox yang usang.
			current[key] = owned or current[key] == true
		end
		cache[player] = current
		publish(player)
		return allOk
	end

	local function onPurchaseFinished(player: Player, passId: any, wasPurchased: any): ()
		if wasPurchased ~= true or type(passId) ~= "number" or passId <= 0 then
			return
		end
		local matched: string? = nil
		for _, key in keys do
			if defs[key].id == passId then
				matched = key
			end
		end
		if not matched or not deps.isPresent(player) then
			return
		end
		-- Event server dari engine (bukan dari client); verifikasi ulang tetap dicoba.
		local verified = fetch(player, passId)
		if verified == false then
			log(`[Monetization] pass {matched} belum terlihat dimiliki setelah pembelian UserId={player.UserId}`)
		end
		if not deps.isPresent(player) then
			return
		end
		local current = cache[player] or {}
		current[matched] = true
		cache[player] = current
		publish(player)
	end

	return {
		load = load,
		onPurchaseFinished = onPurchaseFinished,
		has = has,
		extraPresets = extraPresets,
		clear = function(player: Player)
			cache[player] = nil
		end,
		setForTest = function(player: Player, key: string, owned: boolean)
			local current = cache[player] or {}
			current[key] = owned
			cache[player] = current
			publish(player)
		end,
	}
end

return table.freeze(Passes)
