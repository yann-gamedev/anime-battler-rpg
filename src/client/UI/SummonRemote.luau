--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

-- Luau singleton types support strings, so the view supplies the numeric 1 and 10 options.
export type Count = number
export type Payment = "Gems" | "Tickets"
export type Odds = {
	rarities: { { rarity: string, percent: number } },
	units: { { unitId: string, name: string, rarity: string, percent: number } },
}
export type Banner = {
	id: string,
	kind: "Standard" | "Limited",
	active: boolean,
	startsAt: number?,
	endsAt: number?,
	featuredUnitId: string?,
	prices: { gems1: number, gems10: number, tickets1: number, tickets10: number },
	pity: {
		sinceLegendary: number,
		sinceMythic: number,
		legendaryPlusRolls: number,
		mythicRolls: number,
		guaranteedFeatured: boolean,
	},
	odds: { base: Odds, single: Odds, ten: { Odds } },
}
export type Info = {
	restricted: boolean,
	balances: { Gems: number, SummonTickets: number },
	capacity: { used: number, max: number },
	banners: { Banner },
}
export type Roll = { uid: string, unitId: string, name: string, rarity: string }
export type Result = { bannerId: string, rolls: { Roll }, info: Info }

local Remote = {}

local messages: { [string]: string } = {
	ODDS_CHANGED = "Your summon odds changed. Review the refreshed odds and choose again.",
	RESTRICTED_REGION = "Gem summons are unavailable for your account.",
	BANNER_INACTIVE = "This banner is no longer active.",
	BANNER_NOT_ACTIVE = "This banner is no longer active.",
	NOT_ENOUGH_GEMS = "You need more Gems.",
	NOT_ENOUGH_TICKETS = "You need more Summon Tickets.",
	INVENTORY_FULL = "There is not enough room for these units.",
	RATE_LIMITED = "Wait a moment before trying again.",
	DATA_NOT_READY = "Your profile is still loading. Try refreshing in a moment.",
	UNAVAILABLE = "The summon service is unavailable. Try refreshing.",
	CONNECTION = "Connection interrupted. Check your inventory and refreshed balances before trying again.",
	INVALID_REPLY = "The server reply was incomplete. Check your inventory and refreshed balances.",
}

function Remote.message(code: string): string
	return messages[code] or "The server could not complete the request. Try refreshing."
end

local function request(name: string, ...: any): (any, string?)
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, 4)
	local remote = folder and folder:WaitForChild(name, 4)
	if not remote or not remote:IsA("RemoteFunction") then
		return nil, "UNAVAILABLE"
	end
	local invoked, reply = pcall(remote.InvokeServer, remote, ...)
	if not invoked then
		warn("[Summon] " .. name .. " failed: " .. tostring(reply))
		return nil, "CONNECTION"
	end
	if type(reply) ~= "table" then
		return nil, "INVALID_REPLY"
	end
	if reply.ok ~= true then
		return nil, if type(reply.code) == "string" then reply.code else "UNKNOWN"
	end
	return reply.data, nil
end

local function unsigned(value: any): boolean
	return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

local function fields(value: any, keys: { string }): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, key in keys do
		if not unsigned(value[key]) then
			return false
		end
	end
	return true
end

local function validOutcome(row: any): boolean
	return type(row) == "table"
		and type(row.rarity) == "string"
		and type(row.percent) == "number"
		and row.percent >= 0
		and row.percent <= 100
end

local function validOdds(value: any): boolean
	if
		type(value) ~= "table"
		or type(value.rarities) ~= "table"
		or #value.rarities == 0
		or type(value.units) ~= "table"
		or #value.units == 0
	then
		return false
	end
	for _, row in value.rarities do
		if not validOutcome(row) then
			return false
		end
	end
	for _, row in value.units do
		if not validOutcome(row) or type(row.unitId) ~= "string" or type(row.name) ~= "string" then
			return false
		end
	end
	return true
end

local function validBanner(value: any): boolean
	if
		type(value) ~= "table"
		or type(value.id) ~= "string"
		or (value.kind ~= "Standard" and value.kind ~= "Limited")
		or type(value.active) ~= "boolean"
		or (value.startsAt ~= nil and not unsigned(value.startsAt))
		or (value.endsAt ~= nil and not unsigned(value.endsAt))
		or (value.featuredUnitId ~= nil and type(value.featuredUnitId) ~= "string")
		or not fields(value.prices, { "gems1", "gems10", "tickets1", "tickets10" })
		or not fields(value.pity, { "sinceLegendary", "sinceMythic", "legendaryPlusRolls", "mythicRolls" })
		or type(value.pity.guaranteedFeatured) ~= "boolean"
		or type(value.odds) ~= "table"
		or not validOdds(value.odds.base)
		or not validOdds(value.odds.single)
		or type(value.odds.ten) ~= "table"
		or #value.odds.ten ~= 10
	then
		return false
	end
	for position = 1, 10 do
		if not validOdds(value.odds.ten[position]) then
			return false
		end
	end
	return true
end

local function validInfo(value: any): boolean
	if
		type(value) ~= "table"
		or type(value.restricted) ~= "boolean"
		or not fields(value.balances, { "Gems", "SummonTickets" })
		or not fields(value.capacity, { "used", "max" })
		or type(value.banners) ~= "table"
	then
		return false
	end
	for _, banner in value.banners do
		if not validBanner(banner) then
			return false
		end
	end
	return true
end

function Remote.getInfo(): (Info?, string?)
	local value, code = request("GetBannerInfo")
	if not validInfo(value) then
		return nil, code or "INVALID_REPLY"
	end
	return value, nil
end

function Remote.summon(bannerId: string, count: Count, payment: Payment): (Result?, string?)
	local value, code = request("Summon", bannerId, count, payment)
	if
		type(value) ~= "table"
		or value.bannerId ~= bannerId
		or not validInfo(value.info)
		or type(value.rolls) ~= "table"
		or #value.rolls ~= count
	then
		return nil, code or "INVALID_REPLY"
	end
	for index = 1, count do
		local roll = value.rolls[index]
		if
			type(roll) ~= "table"
			or type(roll.uid) ~= "string"
			or type(roll.unitId) ~= "string"
			or type(roll.rarity) ~= "string"
			or type(roll.name) ~= "string"
		then
			return nil, "INVALID_REPLY"
		end
	end
	return value, nil
end

return table.freeze(Remote)
