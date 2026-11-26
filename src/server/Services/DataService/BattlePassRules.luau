--!strict
-- Aturan murni Battle Pass yang memutasi DRAFT profil: XP musim dan klaim tier. Dipanggil hanya lewat
-- DataService/BattlePass (Commit.run). Semua cek (musim, unlock, premium, klaim ganda, pilihan unit)
-- dilakukan di draft saat commit, tanpa yield; gagal di tengah = draft dibuang.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Units = require(Shared.Config.Units)
local ProfileFrames = require(Shared.Config.ProfileFrames)
local Skins = require(Shared.Config.Skins)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local ProfileRules = require(script.Parent.ProfileRules)
local ShopRules = require(script.Parent.ShopRules)
local StoryRules = require(script.Parent.StoryRules)

type Outcome = StoryRules.Outcome

export type ClaimRequest = {
	seasonId: string,
	track: Types.BattlePassTrack,
	tier: number,
	xpRequired: number, -- tier × xpPerTier dari config musim
	rewards: { Types.Reward }, -- dari config musim, bukan dari client
	unitId: string?, -- pilihan untuk reward UnitChoice
}

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local REWARD_SOURCE = "battle_pass"
local MAX_TIER = 1000

local BattlePassRules = {}

-- Menambah XP musim, dibatasi maxXp (XP tier terakhir). Mengembalikan XP baru.
function BattlePassRules.addXp(
	profile: Types.Profile,
	seasonId: string,
	amount: number,
	maxXp: number
): (string?, Outcome?, number?)
	if
		type(seasonId) ~= "string"
		or seasonId == ""
		or not Validate.isIntInRange(amount, 1, MAX_EXACT_INTEGER)
		or not Validate.isIntInRange(maxXp, 0, MAX_EXACT_INTEGER)
	then
		return "INVALID_REQUEST", nil, nil
	end
	local record = ShopRules.season(profile, seasonId)
	record.xp = math.min(maxXp, record.xp + amount)
	return nil, StoryRules.newOutcome(), record.xp
end

local function hasUnitChoice(rewards: { Types.Reward }): boolean
	for _, reward in rewards do
		if reward.kind == "UnitChoice" then
			return true
		end
	end
	return false
end

local function applyReward(
	profile: Types.Profile,
	outcome: Outcome,
	reward: Types.Reward,
	unitId: string?,
	now: number,
	newUid: () -> string
): string?
	if reward.kind == "Currency" then
		local kind = reward.id
		if not ProfileRules.isCurrencyKind(kind) then
			return "INTERNAL_ERROR"
		end
		return StoryRules.changeCurrency(
			profile,
			outcome,
			kind :: Types.CurrencyKind,
			reward.amount :: number,
			REWARD_SOURCE,
			false
		)
	elseif reward.kind == "UnitChoice" then
		local options = reward.options or {}
		if unitId == nil then
			return "UNIT_CHOICE_REQUIRED"
		end
		if not table.find(options, unitId) or not Units[unitId] then
			return "INVALID_UNIT_CHOICE"
		end
		local code = ShopRules.addUnit(profile, unitId, "battlepass", now, newUid)
		if code == nil then
			outcome.units = true
		end
		return code
	elseif reward.kind == "Skin" then
		local skinId = reward.id
		if type(skinId) ~= "string" or not Skins[skinId] then
			return "INTERNAL_ERROR"
		end
		profile.skinsOwned[skinId] = true
		return nil
	elseif reward.kind == "ProfileFrame" then
		local frameId = reward.id
		if type(frameId) ~= "string" or not ProfileFrames[frameId] then
			return "INTERNAL_ERROR"
		end
		-- Draft sudah direkonsiliasi Commit.run, jadi profileFrames selalu ada.
		local battlePass = profile.battlePass :: any
		battlePass.profileFrames[frameId] = true
		battlePass.profileFrameId = frameId
		return nil
	end
	return "INTERNAL_ERROR"
end

-- Klaim satu tier pada satu track. Reward diberikan sekali; klaim ulang = ALREADY_CLAIMED.
function BattlePassRules.claim(
	profile: Types.Profile,
	request: ClaimRequest,
	now: number,
	newUid: () -> string
): (string?, Outcome?)
	if
		type(request) ~= "table"
		or type(request.seasonId) ~= "string"
		or (request.track ~= "Free" and request.track ~= "Premium")
		or not Validate.isIntInRange(request.tier, 1, MAX_TIER)
		or not Validate.isIntInRange(request.xpRequired, 0, MAX_EXACT_INTEGER)
		or type(request.rewards) ~= "table"
	then
		return "INVALID_REQUEST", nil
	end
	local record = ShopRules.season(profile, request.seasonId)
	if record.xp < request.xpRequired then
		return "TIER_LOCKED", nil
	end
	if request.track == "Premium" and not record.premium then
		return "PREMIUM_REQUIRED", nil
	end
	local claimed = if request.track == "Premium" then record.premiumClaimed else record.freeClaimed
	local key = tostring(request.tier)
	if claimed[key] == true then
		return "ALREADY_CLAIMED", nil
	end
	if #request.rewards == 0 then
		return "NOTHING_TO_CLAIM", nil
	end
	-- unitId hanya berarti untuk tier dengan UnitChoice; selain itu ditolak agar tidak ambigu.
	if request.unitId ~= nil and not hasUnitChoice(request.rewards) then
		return "INVALID_UNIT_CHOICE", nil
	end
	local outcome = StoryRules.newOutcome()
	for _, reward in request.rewards do
		local code = applyReward(profile, outcome, reward, request.unitId, now, newUid)
		if code then
			return code, nil
		end
	end
	claimed[key] = true
	return nil, outcome
end

return table.freeze(BattlePassRules)
