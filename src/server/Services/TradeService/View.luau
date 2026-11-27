--!strict
-- TradeView untuk satu peserta (kontrak shared/TradeTypes). UID hanya dikirim untuk sisi milik penerima.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TradeTypes = require(Shared.TradeTypes)
local Skins = require(Shared.Config.Skins)
local Units = require(Shared.Config.Units)
local TradeSession = require(script.Parent.TradeSession)

local View = {}

local function offer(side: TradeSession.Side, includeUid: boolean): TradeTypes.TradeOffer
	local units: { TradeTypes.TradeUnitView } = {}
	for _, unit in side.units do
		local def = Units[unit.unitId]
		table.insert(units, {
			uid = if includeUid then unit.uid else nil,
			unitId = unit.unitId,
			name = if def then def.name else unit.unitId,
			rarity = if def then def.rarity else "Rare",
			stars = unit.stars,
		})
	end
	local skins: { TradeTypes.TradeSkinView } = {}
	for _, skinId in side.skins do
		local def = Skins[skinId]
		table.insert(skins, { skinId = skinId, name = if def then def.name else skinId })
	end
	return { units = units, skins = skins }
end

function View.build(
	session: TradeSession.Session,
	viewerUserId: number,
	otherDisplayName: string
): TradeTypes.TradeView?
	local mine, other = TradeSession.sides(session, viewerUserId)
	if not mine or not other then
		return nil
	end
	return {
		sessionId = session.id,
		revision = session.revision,
		updateId = session.updateId,
		status = session.status,
		initiatorUserId = session.initiator.userId,
		selfUserId = mine.userId,
		otherUserId = other.userId,
		otherDisplayName = otherDisplayName,
		mine = offer(mine, true),
		theirs = offer(other, false),
		myReady = mine.ready,
		theirReady = other.ready,
		myConfirmed = mine.confirmed,
		theirConfirmed = other.confirmed,
		countdownEndsAt = session.countdownEndsAt,
		expiresAt = session.expiresAt,
		reason = session.reason,
	}
end

return table.freeze(View)
