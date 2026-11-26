--!strict

local TradeState = {}

export type Offer = {
	units: { { uid: string?, unitId: string, name: string, rarity: string, stars: number } },
	skins: { { skinId: string, name: string } },
}

export type View = {
	sessionId: string,
	revision: number,
	status: "Requested" | "Open" | "Ready" | "Countdown" | "Confirmed" | "Done" | "Cancelled",
	initiatorUserId: number,
	selfUserId: number,
	otherUserId: number,
	otherDisplayName: string,
	mine: Offer,
	theirs: Offer,
	myReady: boolean,
	theirReady: boolean,
	myConfirmed: boolean,
	theirConfirmed: boolean,
	countdownEndsAt: number?,
	expiresAt: number,
	reason: string?,
}

export type State = { view: View?, seen: { [string]: boolean } }

function TradeState.new(): State
	return { view = nil, seen = {} }
end

function TradeState.terminal(view: View): boolean
	return view.status == "Done" or view.status == "Cancelled"
end

function TradeState.apply(state: State, incoming: View, userId: number, now: number): boolean
	if incoming.selfUserId ~= userId then
		return false
	end
	local current = state.view
	if current and current.sessionId == incoming.sessionId then
		if TradeState.terminal(current) or incoming.revision <= current.revision then
			return false
		end
	elseif
		state.seen[incoming.sessionId]
		or (not TradeState.terminal(incoming) and incoming.status ~= "Confirmed" and incoming.expiresAt <= now)
		or (current and not TradeState.terminal(current) and (current.status == "Confirmed" or current.expiresAt > now))
	then
		return false
	end
	state.seen[incoming.sessionId] = true
	state.view = incoming
	return true
end

function TradeState.canEdit(view: View, now: number): boolean
	return now < view.expiresAt and (view.status == "Open" or view.status == "Ready")
end

function TradeState.canConfirm(view: View, now: number): boolean
	local ends = view.countdownEndsAt
	return view.status == "Countdown"
		and view.myReady
		and view.theirReady
		and not view.myConfirmed
		and ends ~= nil
		and now >= ends
		and now < view.expiresAt
end

function TradeState.canRespond(view: View, now: number): boolean
	return view.status == "Requested" and view.initiatorUserId ~= view.selfUserId and now < view.expiresAt
end

return table.freeze(TradeState)
