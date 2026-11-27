--!strict
-- Handler RequestTrade & RespondTrade (gerbang pasangan sebelum sesi dibuka). Bagian dari Coordinator.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local Contract = require(script.Parent.Contract)
local TradeSession = require(script.Parent.TradeSession)

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local fail = Contract.fail

local Requests = {}

function Requests.attach(handlers: { [string]: Contract.Handler }, ctx: Contract.Context): ()
	local deps = ctx.deps
	local trades = deps.trades
	local sessions, byUser = ctx.sessions, ctx.byUser
	local playerOf, ownSession, publish, success, cancel =
		ctx.playerOf, ctx.ownSession, ctx.publish, ctx.success, ctx.cancel

	-- Gerbang pasangan (lokasi + syarat pemain + kebijakan). Kebijakan boleh yield.
	local function checkPeople(player: Player, other: Player): string?
		local code = deps.proximity(player, other)
		if code then
			return code
		end
		code = trades.checkPlayer(player, deps.accountAgeDays(player))
		if code then
			return code
		end
		code = trades.checkPlayer(other, deps.accountAgeDays(other))
		if code then
			return `TARGET_{code}`
		end
		if not deps.isTradingAllowed(player) then
			return "TRADE_POLICY_RESTRICTED"
		end
		if not deps.isTradingAllowed(other) then
			return "TARGET_TRADE_POLICY_RESTRICTED"
		end
		return nil
	end

	function handlers.RequestTrade(player: Player, targetUserId: any, ...: any): Types.Result
		if select("#", ...) > 0 or not Validate.isIntInRange(targetUserId, -MAX_EXACT_INTEGER, MAX_EXACT_INTEGER) then
			return fail("INVALID_ARGUMENTS")
		end
		if not trades.isEnabled() then
			return fail("TRADE_DISABLED")
		end
		local target = deps.findPlayer(targetUserId)
		if targetUserId == player.UserId or targetUserId == 0 then
			return fail("INVALID_TARGET")
		elseif not target or not deps.isPresent(target) then
			return fail("TARGET_NOT_IN_SERVER")
		elseif byUser[player.UserId] or trades.isLocked(player) then
			return fail("TRADE_BUSY")
		elseif byUser[targetUserId] or trades.isLocked(target) then
			return fail("TARGET_BUSY")
		end
		local code = checkPeople(player, target)
		if code then
			return fail(code)
		end
		-- Setelah yield kebijakan: ulangi cek yang bisa berubah.
		if not deps.isPresent(player) or not deps.isPresent(target) then
			return fail("TARGET_NOT_IN_SERVER")
		elseif byUser[player.UserId] or byUser[targetUserId] then
			return fail("TRADE_BUSY")
		end
		local session = TradeSession.new(deps.newId(), player.UserId, targetUserId, deps.now())
		sessions[session.id] = session
		byUser[player.UserId] = session
		byUser[targetUserId] = session
		publish(session)
		return success(session, player)
	end

	function handlers.RespondTrade(player: Player, sessionId: any, accept: any, ...: any): Types.Result
		if select("#", ...) > 0 or typeof(accept) ~= "boolean" then
			return fail("INVALID_ARGUMENTS")
		end
		local session = ownSession(player, sessionId)
		if not session then
			return fail("TRADE_NOT_FOUND")
		end
		if accept and session.status == "Requested" and session.target.userId == player.UserId then
			local initiator = playerOf(session.initiator)
			if not initiator then
				cancel(session, "PLAYER_LEFT")
				return fail("PLAYER_LEFT")
			end
			local code = checkPeople(player, initiator)
			if code then
				return fail(code)
			end
		end
		local code = TradeSession.respond(session, player.UserId, accept, deps.now())
		if code then
			return fail(code)
		end
		publish(session)
		return success(session, player)
	end
end

return table.freeze(Requests)
