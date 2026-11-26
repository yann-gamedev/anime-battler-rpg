--!strict
-- Logika Battle Pass yang bisa di-test: PassInfo, klaim tier, dan XP (story & quest).
-- Reward, XP per tier, dan periode musim hanya dari Config/BattlePass; client hanya mengirim niat.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local BattlePass = require(Shared.Config.BattlePass)
local BattlePassSeason = require(Shared.BattlePassSeason)
local ProfileFrames = require(Shared.Config.ProfileFrames)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)

export type Ledger = {
	getSeason: (player: Player, seasonId: string) -> Types.BattlePassSeasonRecord?,
	getProfileFrame: (player: Player) -> string?,
	addXp: (player: Player, seasonId: string, amount: number, maxXp: number) -> (string?, number?),
	claim: (player: Player, request: any) -> string?,
}
export type Deps = { ledger: Ledger, now: () -> number }

local isTrack = Validate.isOneOf({ "Free", "Premium" })
local isUnitId = Validate.isStringMax(BattlePass.maxSeasonIdLength)
local isQuestId = Validate.isStringMax(64)

local Handlers = {}

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

local function cloneRewards(rewards: { Types.Reward }): { Types.Reward }
	local list: { Types.Reward } = {}
	for _, reward in rewards do
		table.insert(list, {
			kind = reward.kind,
			id = reward.id,
			amount = reward.amount,
			options = if reward.options then table.clone(reward.options) else nil,
		})
	end
	return list
end

function Handlers.create(deps: Deps)
	local ledger = deps.ledger

	local function buildInfo(player: Player): Types.PassInfo?
		local now = deps.now()
		local season = BattlePassSeason.display(now)
		local record = ledger.getSeason(player, season.id)
		if not record then
			return nil
		end
		local tiers: { Types.PassTierView } = {}
		for tier, def in season.tiers do
			local key = tostring(tier)
			table.insert(tiers, {
				tier = tier,
				free = cloneRewards(def.free),
				premium = cloneRewards(def.premium),
				freeClaimed = record.freeClaimed[key] == true,
				premiumClaimed = record.premiumClaimed[key] == true,
			})
		end
		-- Bingkai hanya dikirim bila sudah diperoleh (lintas musim) dan masih ada di config.
		local frameId = ledger.getProfileFrame(player)
		return {
			seasonId = season.id,
			startsAt = season.startsAt,
			endsAt = season.endsAt,
			active = BattlePassSeason.isActive(season, now),
			xp = record.xp,
			xpPerTier = season.xpPerTier,
			unlockedTier = BattlePassSeason.unlockedTier(season, record.xp),
			premium = record.premium,
			tiers = tiers,
			profileFrameId = if frameId and ProfileFrames[frameId] then frameId else nil,
		}
	end

	local function respond(player: Player): Types.Result
		local info = buildInfo(player)
		if not info then
			return failure("DATA_NOT_READY")
		end
		return { ok = true, data = info }
	end

	local function getBattlePass(player: Player, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		return respond(player)
	end

	local function claimTier(player: Player, track: any, tier: any, unitId: any, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		if type(track) ~= "string" or not isTrack(track) then
			return failure("INVALID_TRACK")
		end
		if unitId ~= nil and (not isUnitId(unitId) or unitId == "") then
			return failure("INVALID_UNIT_CHOICE")
		end
		local season = BattlePassSeason.active(deps.now())
		if not season then
			return failure("SEASON_INACTIVE")
		end
		if not Validate.isIntInRange(tier, 1, #season.tiers) then
			return failure("INVALID_TIER")
		end
		local def = season.tiers[tier]
		local code = ledger.claim(player, {
			seasonId = season.id,
			track = track,
			tier = tier,
			xpRequired = tier * season.xpPerTier,
			rewards = if track == "Premium" then def.premium else def.free,
			unitId = unitId,
		})
		if code then
			return failure(code)
		end
		return respond(player)
	end

	-- XP ke musim aktif. Mengembalikan (kode, xp baru).
	local function addXp(player: Player, amount: number): (string?, number?)
		local season = BattlePassSeason.active(deps.now())
		if not season then
			return "SEASON_INACTIVE", nil
		end
		return ledger.addXp(player, season.id, amount, BattlePassSeason.maxXp(season))
	end

	local function awardStoryWin(player: Player): (string?, number?)
		return addXp(player, BattlePass.storyWinXp)
	end

	-- API server untuk quest (prompt 10). questId hanya label log; jumlah dibatasi config.
	local function grantQuestXp(player: Player, questId: string, amount: number): (string?, number?)
		if not isQuestId(questId) or questId == "" then
			return "INVALID_QUEST", nil
		end
		if not Validate.isIntInRange(amount, 1, BattlePass.maxQuestXpPerGrant) then
			return "INVALID_AMOUNT", nil
		end
		return addXp(player, amount)
	end

	return {
		GetBattlePass = getBattlePass,
		ClaimBattlePassTier = claimTier,
		buildInfo = buildInfo,
		awardStoryWin = awardStoryWin,
		grantQuestXp = grantQuestXp,
	}
end

return table.freeze(Handlers)
