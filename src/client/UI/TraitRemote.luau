--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Traits = require(Shared.Config.Traits)
local Remotes = require(Shared.Net.Remotes)
local ProgressRemote = require(script.Parent.ProgressRemote)

type TraitOdds = { id: string, name: string, percent: number }
type TierOdds = { tier: string, percent: number, traits: { TraitOdds } }
export type DirectOption = { id: string, name: string, tier: "Common" | "Uncommon", cost: number }
type DirectInfo = { gold: number, options: { DirectOption } }
export type Info = {
	uid: string,
	traitId: string?,
	locked: boolean,
	restricted: boolean,
	shards: number,
	cost: number,
	pity: { sinceLegendary: number, rolls: number },
	odds: { tiers: { TierOdds } },
	direct: DirectInfo?,
}

local TraitRemote = {}
local errors: { [string]: string } = {
	RESTRICTED_REGION = "Trait Shard rerolls are unavailable in your region.",
	UNIT_NOT_OWNED = "This unit is no longer in your inventory.",
	UNIT_LOCKED = "Unlock this unit before changing its trait.",
	NOT_ENOUGH_TRAIT_SHARDS = "You need more Trait Shards.",
	ODDS_CHANGED = "The odds changed. Review the updated odds before rerolling.",
	TRAIT_CHANGED = "The current trait changed. Review it and confirm your choice again.",
	RESTRICTED_ONLY = "Direct trait selection is unavailable for this account.",
	INVALID_TRAIT = "This trait is no longer available.",
	TRAIT_ALREADY_SET = "This trait is already equipped.",
	NOT_ENOUGH_GOLD = "You need more Gold for this trait.",
	DATA_NOT_READY = "Your profile is still loading. Try again in a moment.",
	RATE_LIMITED = "Wait a moment before trying again.",
}

function TraitRemote.message(code: string?): string
	return if code then errors[code] or "Trait data is unavailable. Try refreshing." else ""
end

local function request(name: string, ...: any): (any, string?)
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, 4)
	local remote = folder and folder:WaitForChild(name, 4)
	if not remote or not remote:IsA("RemoteFunction") then
		return nil, "UNAVAILABLE"
	end
	local invoked, reply = pcall(remote.InvokeServer, remote, ...)
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

local function wholeNumber(value: any, minimum: number): boolean
	return type(value) == "number" and value >= minimum and value < math.huge and value % 1 == 0
end

local function parseDirect(payload: any): DirectInfo?
	if type(payload) ~= "table" or not wholeNumber(payload.gold, 0) or type(payload.options) ~= "table" then
		return nil
	end
	local options: { DirectOption } = {}
	local seen: { [string]: boolean } = {}
	for index, option in payload.options do
		if
			index ~= #options + 1
			or type(option) ~= "table"
			or (option.tier ~= "Common" and option.tier ~= "Uncommon")
			or type(option.id) ~= "string"
			or type(option.name) ~= "string"
			or option.name == ""
			or not wholeNumber(option.cost, 1)
			or seen[option.id]
		then
			return nil
		end
		local tier = if option.tier == "Common" then Traits.tiers.Common else Traits.tiers.Uncommon
		local known = false
		for _, trait in tier.traits do
			if trait.id == option.id then
				known = true
				break
			end
		end
		if not known then
			return nil
		end
		seen[option.id] = true
		table.insert(options, option)
	end
	return if #options > 0 then { gold = payload.gold, options = options } else nil
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
	local info: Info = table.clone(payload)
	info.direct = if info.restricted then parseDirect(payload.direct) else nil
	return info
end

function TraitRemote.getInfo(uid: string): (Info?, string?)
	local payload, code = request("GetTraitInfo", uid)
	local info = parseInfo(payload, uid)
	return info, if info then nil else code or "UNAVAILABLE"
end

function TraitRemote.canSelect(info: Info, traitId: string): boolean
	local direct = info.direct
	if not info.restricted or info.locked or not direct or info.traitId == traitId then
		return false
	end
	for _, option in direct.options do
		if option.id == traitId then
			return direct.gold >= option.cost
		end
	end
	return false
end

function TraitRemote.change(uid: string, traitId: string?): (ProgressRemote.Snapshot?, Info?, string?)
	local payload, code
	if traitId then
		payload, code = request("SelectRestrictedTrait", uid, traitId)
	else
		payload, code = request("RerollTrait", uid)
	end
	if type(payload) ~= "table" then
		return nil, nil, code or "UNAVAILABLE"
	end
	local snapshot = ProgressRemote.parseSnapshot(payload.snapshot)
	local info = parseInfo(payload.info, uid)
	local unit = snapshot and snapshot.units[uid]
	if not unit or not info or unit.trait ~= info.traitId or (traitId and unit.trait ~= traitId) then
		return nil, nil, "UNAVAILABLE"
	end
	return snapshot, info, nil
end

return table.freeze(TraitRemote)
