--!strict
-- Bagian DataService: pemilik mutasi quest, Boss Raid, dan pajangan lobby lewat Commit.run (prompt 10).
-- QuestService/RaidService/LobbyService hanya memanggil fungsi bernama di sini; draft tidak keluar.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local MetaTypes = require(Shared.MetaTypes)
local Signal = require(Shared.Util.Signal)
local Commit = require(script.Parent.Commit)
local MetaRules = require(script.Parent.MetaRules)
local QuestRules = require(script.Parent.QuestRules)

export type QuestState = {
	daily: MetaTypes.QuestPeriodRecord,
	weekly: MetaTypes.QuestPeriodRecord,
}
export type ShowcaseState = {
	unlocked: boolean,
	uid: string?,
	skinId: string?,
	unitId: string?,
	stars: number?,
}
export type Ledger = {
	-- Salinan state quest untuk `now` (periode lewat = kosong); nil bila data belum siap.
	getQuests: (player: Player, now: number) -> QuestState?,
	addQuestProgress: (player: Player, kind: Types.ActivityKind, amount: number, now: number) -> string?,
	claimQuest: (player: Player, request: QuestRules.ClaimRequest) -> (string?, Types.RewardMap?),
	-- Salinan record raid untuk hari `day` dan status unlock; nil bila data belum siap.
	getRaid: (player: Player, day: number) -> (Types.RaidRecord?, boolean),
	attemptRaid: (player: Player, request: MetaRules.RaidRequest) -> string?,
	getShowcase: (player: Player) -> ShowcaseState?,
	setShowcase: (player: Player, uid: string, skinId: string?) -> string?,
}

local Meta = {}

function Meta.create(getSession: Commit.SessionGetter, changed: Signal.Signal<Player, string>): Ledger
	local function getQuests(player: Player, now: number): QuestState?
		local session = getSession(player)
		if not session then
			return nil
		end
		return {
			daily = QuestRules.view(session.Data, "Daily", now),
			weekly = QuestRules.view(session.Data, "Weekly", now),
		}
	end

	local function addQuestProgress(player: Player, kind: Types.ActivityKind, amount: number, now: number): string?
		local code = Commit.run(getSession, changed, player, function(draft: Types.Profile)
			local failure, outcome, count = QuestRules.addProgress(draft, kind, amount, now)
			if failure == nil and count == 0 then
				return "NO_CHANGE", nil -- tidak ada quest yang berubah: draft dibuang
			end
			return failure, outcome
		end)
		return if code == "NO_CHANGE" then nil else code
	end

	local function claimQuest(player: Player, request: QuestRules.ClaimRequest): (string?, Types.RewardMap?)
		local copy = table.clone(request)
		if copy.battlePass then
			copy.battlePass = table.clone(copy.battlePass)
		end
		local granted: Types.RewardMap? = nil
		local code = Commit.run(getSession, changed, player, function(draft: Types.Profile)
			local failure, outcome, rewards = QuestRules.claim(draft, copy)
			granted = rewards
			return failure, outcome
		end)
		if code ~= nil then
			return code, nil
		end
		return nil, granted
	end

	local function getRaid(player: Player, day: number): (Types.RaidRecord?, boolean)
		local session = getSession(player)
		if not session then
			return nil, false
		end
		return MetaRules.raidRecord(session.Data, day), MetaRules.isUnlocked(session.Data)
	end

	local function attemptRaid(player: Player, request: MetaRules.RaidRequest): string?
		local copy = table.clone(request)
		copy.rewards = table.clone(request.rewards)
		return (
			Commit.run(getSession, changed, player, function(draft: Types.Profile)
				return MetaRules.attemptRaid(draft, copy)
			end)
		)
	end

	local function getShowcase(player: Player): ShowcaseState?
		local session = getSession(player)
		if not session then
			return nil
		end
		local profile = session.Data
		local uid, skinId = MetaRules.showcase(profile)
		local unit = if uid then profile.units[uid] else nil
		return {
			unlocked = MetaRules.isUnlocked(profile),
			uid = uid,
			skinId = skinId,
			unitId = if unit then unit.unitId else nil,
			stars = if unit then unit.stars else nil,
		}
	end

	local function setShowcase(player: Player, uid: string, skinId: string?): string?
		return (
			Commit.run(getSession, changed, player, function(draft: Types.Profile)
				return MetaRules.setShowcase(draft, uid, skinId)
			end)
		)
	end

	return {
		getQuests = getQuests,
		addQuestProgress = addQuestProgress,
		claimQuest = claimQuest,
		getRaid = getRaid,
		attemptRaid = attemptRaid,
		getShowcase = getShowcase,
		setShowcase = setShowcase,
	}
end

return table.freeze(Meta)
