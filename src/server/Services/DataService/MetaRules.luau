--!strict
-- Aturan murni Boss Raid dan pajangan lobby yang memutasi DRAFT profil, plus rekonsiliasi field additive
-- prompt 10 (quests, raid, lobby). Dipanggil hanya lewat DataService/Meta dan Commit.run. Tidak boleh yield.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Constants = require(Shared.Config.Constants)
local Quests = require(Shared.Config.Quests)
local Skins = require(Shared.Config.Skins)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local ProfileRules = require(script.Parent.ProfileRules)
local QuestRules = require(script.Parent.QuestRules)
local StoryRules = require(script.Parent.StoryRules)

type Outcome = StoryRules.Outcome

export type RaidRequest = {
	day: number, -- hari UTC percobaan (dari jam server saat StartRaid mulai)
	damage: number, -- damage terkredit dari simulasi server
	maxDamage: number, -- HP boss (batas kredit)
	rewards: Types.RewardMap, -- dari Config/Raids lewat RaidMath, bukan dari client
}

local MAX_EXACT_INTEGER = 2 ^ 53 - 1
local MAX_SKIN_ID_LENGTH = 64
local RAID_SOURCE = "raid_reward"

local MetaRules = {}

-- Skin boleh dipajang untuk unit ini: ada di config dan universal (tanpa unitId) atau khusus unit itu.
function MetaRules.isSkinEligible(skinId: string, unitId: string): boolean
	local def = Skins[skinId]
	return def ~= nil and (def.unitId == nil or def.unitId == unitId)
end

-- Pajangan tersanitasi (uid & skin masih dimiliki dan valid). Tidak memutasi.
function MetaRules.showcase(profile: Types.Profile): (string?, string?)
	local lobby = (profile :: any).lobby
	if type(lobby) ~= "table" or type(lobby.showcaseUid) ~= "string" or lobby.showcaseUid == "" then
		return nil, nil
	end
	local unit = profile.units[lobby.showcaseUid]
	if not unit then
		return nil, nil
	end
	local skinId = lobby.showcaseSkinId
	if
		type(skinId) ~= "string"
		or skinId == ""
		or profile.skinsOwned[skinId] ~= true
		or not MetaRules.isSkinEligible(skinId, unit.unitId)
	then
		return lobby.showcaseUid, nil
	end
	return lobby.showcaseUid, skinId
end

function MetaRules.isUnlocked(profile: Types.Profile): boolean
	return profile.flags.tutorialDone == true
end

-- Record raid untuk hari `day` (record kosong bila hari tersimpan sudah lewat). Tidak memutasi.
function MetaRules.raidRecord(profile: Types.Profile, day: number): Types.RaidRecord
	local raid = (profile :: any).raid
	if type(raid) ~= "table" or raid.day ~= day then
		return { day = day, attempted = false, damage = 0 }
	end
	return {
		day = day,
		attempted = raid.attempted == true,
		damage = if Validate.isIntInRange(raid.damage, 0, MAX_EXACT_INTEGER) then raid.damage else 0,
	}
end

-- Melengkapi field additive prompt 10 pada profil lama (v1) tanpa mengubah arti field yang ada.
-- Pajangan yang unitnya sudah tidak dimiliki dikosongkan; skin yang tidak lagi sah kembali ke default.
function MetaRules.reconcile(profile: any): ()
	QuestRules.reconcile(profile)
	local raid = if type(profile.raid) == "table" then profile.raid else {}
	profile.raid = {
		day = if Validate.isIntInRange(raid.day, 0, MAX_EXACT_INTEGER) then raid.day else 0,
		attempted = raid.attempted == true,
		damage = if Validate.isIntInRange(raid.damage, 0, MAX_EXACT_INTEGER) then raid.damage else 0,
	}
	local lobby = if type(profile.lobby) == "table" then profile.lobby else {}
	local uid = lobby.showcaseUid
	local skinId = lobby.showcaseSkinId
	local units = if type(profile.units) == "table" then profile.units else {}
	local owned = if type(profile.skinsOwned) == "table" then profile.skinsOwned else {}
	if type(uid) ~= "string" or #uid > Constants.MAX_UID_LENGTH or units[uid] == nil then
		uid = ""
	end
	if
		uid == ""
		or type(skinId) ~= "string"
		or owned[skinId] ~= true
		or not MetaRules.isSkinEligible(skinId, units[uid].unitId)
	then
		skinId = ""
	end
	profile.lobby = { showcaseUid = uid, showcaseSkinId = skinId }
end

-- Satu percobaan raid per hari UTC: tanda percobaan, damage, dan reward dalam satu draft.
function MetaRules.attemptRaid(profile: Types.Profile, request: RaidRequest): (string?, Outcome?)
	if
		type(request) ~= "table"
		or not Validate.isIntInRange(request.day, 0, MAX_EXACT_INTEGER)
		or not Validate.isIntInRange(request.maxDamage, 1, MAX_EXACT_INTEGER)
		or not Validate.isIntInRange(request.damage, 0, request.maxDamage)
		or type(request.rewards) ~= "table"
	then
		return "INVALID_REQUEST", nil
	end
	if not MetaRules.isUnlocked(profile) then
		return "RAID_LOCKED", nil
	end
	if MetaRules.raidRecord(profile, request.day).attempted then
		return "ALREADY_ATTEMPTED", nil
	end
	profile.raid = { day = request.day, attempted = true, damage = request.damage }
	local outcome = StoryRules.newOutcome()
	for kind, amount in request.rewards do
		if not table.find(Quests.rewardCurrencies, kind) or not ProfileRules.isCurrencyKind(kind) then
			return "INTERNAL_ERROR", nil
		end
		local code = StoryRules.changeCurrency(profile, outcome, kind :: Types.CurrencyKind, amount, RAID_SOURCE, false)
		if code then
			return code, nil
		end
	end
	return nil, outcome
end

-- Memilih pajangan. uid "" = kosongkan. skinId nil/"" = skin default.
function MetaRules.setShowcase(profile: Types.Profile, uid: string, skinId: string?): (string?, Outcome?)
	if type(uid) ~= "string" or #uid > Constants.MAX_UID_LENGTH then
		return "INVALID_UID", nil
	end
	if skinId ~= nil and (type(skinId) ~= "string" or #skinId > MAX_SKIN_ID_LENGTH) then
		return "INVALID_SKIN", nil
	end
	if not MetaRules.isUnlocked(profile) then
		return "LOBBY_LOCKED", nil
	end
	local lobby = { showcaseUid = "", showcaseSkinId = "" }
	if uid ~= "" then
		local unit = profile.units[uid]
		if not unit then
			return "UNIT_NOT_OWNED", nil
		end
		local skin = skinId or ""
		if skin ~= "" then
			if not Skins[skin] then
				return "INVALID_SKIN", nil
			elseif profile.skinsOwned[skin] ~= true then
				return "SKIN_NOT_OWNED", nil
			elseif not MetaRules.isSkinEligible(skin, unit.unitId) then
				return "SKIN_NOT_ELIGIBLE", nil
			end
		end
		lobby = { showcaseUid = uid, showcaseSkinId = skin }
	end
	(profile :: any).lobby = lobby
	return nil, StoryRules.newOutcome()
end

return table.freeze(MetaRules)
