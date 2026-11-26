--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Traits = require(Shared.Config.Traits)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)

-- Lua numbers can represent every integer exactly only up to this limit.
local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local isUnitSource = Validate.isOneOf({ "summon", "story", "trade", "event", "admin", "shop", "battlepass" })
local isCurrencyKind = Validate.isOneOf({ "Gold", "Gems", "TraitShards", "SummonTickets", "AsramaTokens" })
local traitIds: { [string]: boolean } = {}
for _, tier in Traits.tiers do
	for _, trait in tier.traits do
		traitIds[trait.id] = true
	end
end
local ProfileRules = {}

function ProfileRules.isUnitSource(source: any): boolean
	return type(source) == "string" and isUnitSource(source)
end

function ProfileRules.isCurrencyKind(kind: any): boolean
	return type(kind) == "string" and isCurrencyKind(kind)
end

function ProfileRules.currencyBalance(balance: number, amount: number, spend: boolean): number?
	if not Validate.isIntInRange(balance, 0, MAX_EXACT_INTEGER) then
		return nil
	end
	if not Validate.isIntInRange(amount, 1, if spend then balance else MAX_EXACT_INTEGER - balance) then
		return nil
	end
	return if spend then balance - amount else balance + amount
end

function ProfileRules.isUnitUpdateValid(original: Types.OwnedUnit, candidate: Types.OwnedUnit): boolean
	return original.uid == candidate.uid
		and original.unitId == candidate.unitId
		and original.source == candidate.source
		and original.obtainedAt == candidate.obtainedAt
		and Validate.isIntInRange(candidate.stars, Constants.UNIT_STARS_MIN, Constants.UNIT_STARS_MAX)
		and Validate.isIntInRange(candidate.level, Constants.UNIT_LEVEL_MIN, Constants.UNIT_LEVEL_MAX)
		and Validate.isIntInRange(candidate.xp, 0, MAX_EXACT_INTEGER)
		and type(candidate.locked) == "boolean"
		and (candidate.trait == nil or (type(candidate.trait) == "string" and traitIds[candidate.trait] == true))
		and (
			candidate.tradeCooldownUntil == nil
			or Validate.isIntInRange(candidate.tradeCooldownUntil, 0, MAX_EXACT_INTEGER)
		)
end

return table.freeze(ProfileRules)
