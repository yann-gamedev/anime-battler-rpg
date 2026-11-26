--!strict
-- Logika RaidService yang bisa di-test: snapshot GetRaidInfo dan StartRaid.
-- Battle disimulasikan server dengan tim tersimpan; damage terkredit dihitung dari log server dan dibatasi
-- HP boss; percobaan + damage + reward di-commit sekali secara atomik untuk hari UTC saat request mulai.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Raids = require(Shared.Config.Raids)
local QuestPeriods = require(Shared.QuestPeriods)
local RaidMath = require(Shared.RaidMath)

export type Ledger = {
	getRaid: (player: Player, day: number) -> (Types.RaidRecord?, boolean),
	attemptRaid: (player: Player, request: any) -> string?,
}
export type Deps = {
	ledger: Ledger,
	now: () -> number,
	isTeamIndexAllowed: (player: Player, teamIndex: any) -> boolean,
	-- Menjalankan battle server untuk tim tersimpan teamIndex melawan boss (RaidMath.stageDef()).
	runBattle: (player: Player, teamIndex: number) -> (Types.BattleResult?, string?),
	onAttempt: ((player: Player, damage: number, tierIndex: number) -> ())?,
}

local Handlers = {}

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

function Handlers.create(deps: Deps)
	local ledger = deps.ledger
	local maxHp = RaidMath.bossMaxHp()

	local function buildInfo(player: Player, now: number): Types.RaidInfo?
		local record, unlocked = ledger.getRaid(player, QuestPeriods.utcDay(now))
		if not record then
			return nil
		end
		return {
			unlocked = unlocked,
			bossName = Raids.boss.name,
			bossId = Raids.boss.id,
			bossMaxHp = maxHp,
			bestDamage = record.damage,
			attempted = record.attempted,
			resetAt = QuestPeriods.dailyResetAt(now),
			serverTime = now,
			rewardTiers = RaidMath.tiers(maxHp),
		}
	end

	local function getRaidInfo(player: Player, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		local info = buildInfo(player, deps.now())
		if not info then
			return failure("DATA_NOT_READY")
		end
		return { ok = true, data = info }
	end

	local function startRaid(player: Player, teamIndex: any, ...: any): Types.Result
		if select("#", ...) ~= 0 then
			return failure("INVALID_ARGUMENTS")
		end
		if not deps.isTeamIndexAllowed(player, teamIndex) then
			return failure("INVALID_TEAM_INDEX")
		end
		local now = deps.now()
		local day = QuestPeriods.utcDay(now)
		local record, unlocked = ledger.getRaid(player, day)
		if not record then
			return failure("DATA_NOT_READY")
		elseif not unlocked then
			return failure("RAID_LOCKED")
		elseif record.attempted then
			return failure("ALREADY_ATTEMPTED")
		end
		local result, battleCode = deps.runBattle(player, teamIndex)
		if not result then
			return failure(battleCode or "BATTLE_FAILED")
		end
		local damage = RaidMath.creditedDamage(result, maxHp)
		local rewards, tierIndex = RaidMath.rewardsFor(damage, maxHp)
		-- Commit memeriksa ulang unlock & percobaan di draft (klaim ganda/rejoin ditolak di sini).
		local code = ledger.attemptRaid(player, { day = day, damage = damage, maxDamage = maxHp, rewards = rewards })
		if code then
			return failure(code)
		end
		if deps.onAttempt then
			deps.onAttempt(player, damage, tierIndex)
		end
		local info = buildInfo(player, now)
		if not info then
			return failure("DATA_NOT_READY")
		end
		local data: Types.RaidResultData = { raid = info, damage = damage, rewards = rewards, replay = result }
		return { ok = true, data = data }
	end

	return { GetRaidInfo = getRaidInfo, StartRaid = startRaid, buildInfo = buildInfo }
end

return table.freeze(Handlers)
