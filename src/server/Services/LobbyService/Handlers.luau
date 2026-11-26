--!strict
-- Logika LobbyService yang bisa di-test: GetLobbyInfo dan SetLobbyShowcase.
-- Kepemilikan unit, kepemilikan & kelayakan skin, serta unlock lobby dicek di draft profil saat commit.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)

export type ShowcaseState = { unlocked: boolean, uid: string?, skinId: string? }
export type Ledger = {
	getShowcase: (player: Player) -> ShowcaseState?,
	setShowcase: (player: Player, uid: string, skinId: string?) -> string?,
}
export type Deps = { ledger: Ledger, onChanged: ((player: Player) -> ())? }

local MAX_SKIN_ID_LENGTH = 64
local isUid = Validate.isStringMax(Constants.MAX_UID_LENGTH)
local isSkinId = Validate.isStringMax(MAX_SKIN_ID_LENGTH)

local Handlers = {}

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

function Handlers.create(deps: Deps)
	local ledger = deps.ledger

	local function buildInfo(player: Player): Types.LobbyInfo?
		local state = ledger.getShowcase(player)
		if not state then
			return nil
		end
		return { unlocked = state.unlocked, showcaseUid = state.uid, showcaseSkinId = state.skinId }
	end

	local function respond(player: Player): Types.Result
		local info = buildInfo(player)
		if not info then
			return failure("DATA_NOT_READY")
		end
		return { ok = true, data = info }
	end

	local function getLobbyInfo(player: Player, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		return respond(player)
	end

	local function setLobbyShowcase(player: Player, uid: any, skinId: any, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		if not isUid(uid) then
			return failure("INVALID_UID")
		end
		if skinId ~= nil and not isSkinId(skinId) then
			return failure("INVALID_SKIN")
		end
		-- "" = skin default; uid "" mengosongkan pajangan (skin diabaikan).
		local skin: string? = if skinId == "" or uid == "" then nil else skinId
		local code = ledger.setShowcase(player, uid, skin)
		if code then
			return failure(code)
		end
		if deps.onChanged then
			deps.onChanged(player)
		end
		return respond(player)
	end

	return { GetLobbyInfo = getLobbyInfo, SetLobbyShowcase = setLobbyShowcase, buildInfo = buildInfo }
end

return table.freeze(Handlers)
