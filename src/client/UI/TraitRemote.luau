--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Traits = require(Shared.Config.Traits)
local Remotes = require(Shared.Net.Remotes)
local ProgressRemote = require(script.Parent.ProgressRemote)

type TraitOdds = { id: string, name: string, percent: number }
type TierOdds = { tier: string, percent: number, traits: { TraitOdds } }
export type Info = {
	uid: string,
	traitId: string?,
	locked: boolean,
	restricted: boolean,
	shards: number,
	cost: number,
	pity: { sinceLegendary: number, rolls: number },
	odds: { tiers: { TierOdds } },
}

local TraitRemote = {}
local errors: { [string]: string } = {
	RESTRICTED_REGION = "Trait Shard rerolls are unavailable in your region.",
	UNIT_NOT_OWNED = "This unit is no longer in your inventory.",
	UNIT_LOCKED = "Unlock this unit before rerolling.",
	NOT_ENOUGH_TRAIT_SHARDS = "You need more Trait Shards.",
	ODDS_CHANGED = "The odds changed. Review the updated odds before rerolling.",
	DATA_NOT_READY = "Your profile is still loading. Try again in a moment.",
	RATE_LIMITED = "Wait a moment before trying again.",
}

function TraitRemote.message(code: string?): string
	return if code then errors[code] or "Trait data is unavailable. Try refreshing." else ""
end

local function request(name: string, uid: string): (any, string?)
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, 4)
	local remote = folder and folder:WaitForChild(name, 4)
	if not remote or not remote:IsA("RemoteFunction") then
		return nil, "UNAVAILABLE"
	end
	local invoked, reply = pcall(remote.InvokeServer, remote, uid)
	if not invoked then
		warn("[Trait] " .. name .. " failed: " .. tostring(reply))
		return nil, "UNAVAILABLE"
	end
	if type(reply) ~= "table" or reply.ok ~= true then
		return nil, if type(reply) == "table" and type(reply.code) == "string" then reply.code else "UNAVAILABLE"
	end
	return reply.data, nil
end

local function percent(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= 100
end

local function parseInfo(payload: any, uid: string): Info?
	if
		type(payload) ~= "table"
		or payload.uid ~= uid
		or (payload.traitId ~= nil and type(payload.traitId) ~= "string")
		or type(payload.locked) ~= "boolean"
		or type(payload.restricted) ~= "boolean"
		or type(payload.shards) ~= "number"
		or type(payload.cost) ~= "number"
		or type(payload.pity) ~= "table"
		or type(payload.pity.sinceLegendary) ~= "number"
		or type(payload.pity.rolls) ~= "number"
		or type(payload.odds) ~= "table"
		or type(payload.odds.tiers) ~= "table"
	then
		return nil
	end
	local tiers = Traits.tiers :: any
	local seenTiers: { [string]: boolean } = {}
	for _, row in payload.odds.tiers do
		if type(row) ~= "table" or type(row.tier) ~= "string" or not percent(row.percent) then
			return nil
		end
		local tier = tiers[row.tier]
		if not tier or seenTiers[row.tier] or type(row.traits) ~= "table" or #row.traits ~= #tier.traits then
			return nil
		end
		seenTiers[row.tier] = true
		local seenTraits: { [string]: boolean } = {}
		for _, outcome in row.traits do
			if
				type(outcome) ~= "table"
				or type(outcome.id) ~= "string"
				or type(outcome.name) ~= "string"
				or not percent(outcome.percent)
				or seenTraits[outcome.id]
			then
				return nil
			end
			seenTraits[outcome.id] = true
		end
		for _, trait in tier.traits do
			if not seenTraits[trait.id] then
				return nil
			end
		end
	end
	for tier in Traits.tiers do
		if not seenTiers[tier] then
			return nil
		end
	end
	return payload
end

function TraitRemote.getInfo(uid: string): (Info?, string?)
	local payload, code = request("GetTraitInfo", uid)
	local info = parseInfo(payload, uid)
	return info, if info then nil else code or "UNAVAILABLE"
end

function TraitRemote.reroll(uid: string): (ProgressRemote.Snapshot?, Info?, string?)
	local payload, code = request("RerollTrait", uid)
	if type(payload) ~= "table" then
		return nil, nil, code or "UNAVAILABLE"
	end
	local snapshot = ProgressRemote.parseSnapshot(payload.snapshot)
	local info = parseInfo(payload.info, uid)
	local unit = snapshot and snapshot.units[uid]
	if not unit or not info or unit.trait ~= info.traitId then
		return nil, nil, "UNAVAILABLE"
	end
	return snapshot, info, nil
end

return table.freeze(TraitRemote)
