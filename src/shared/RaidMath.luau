--!strict
-- Aturan murni Boss Raid (tanpa Instance): input boss untuk BattleSim, HP boss, tier reward, dan damage
-- yang dikreditkan dari BattleResult hasil simulasi server. Nilai hanya dari Config/Raids.
local Types = require(script.Parent.Types)
local Raids = require(script.Parent.Config.Raids)
local Stats = require(script.Parent.BattleSim.Stats)
local SynergyResolver = require(script.Parent.BattleSim.SynergyResolver)

local RaidMath = {}

local boss = Raids.boss

function RaidMath.bossInput(): Types.BattleUnitInput
	return {
		unitId = boss.unitId,
		stars = boss.stars,
		level = boss.level,
		cell = boss.cell,
		hpMultiplier = boss.hpMultiplier,
	}
end

-- StageDef sintetis untuk BattleService.runPve (tidak masuk story.cleared, tanpa reward story).
function RaidMath.stageDef(): Types.StageDef
	return {
		id = `raid_{boss.id}`,
		chapter = 0,
		index = 0,
		enemies = {
			{
				unitId = boss.unitId,
				slot = boss.cell,
				level = boss.level,
				stars = boss.stars,
				hpMultiplier = boss.hpMultiplier,
			},
		},
		firstThreeStarGems = 0,
	}
end

-- HP maksimum boss (dibulatkan ke bawah), sama dengan HP spawn di BattleSim.
function RaidMath.bossMaxHp(): number
	local input = RaidMath.bossInput()
	local stats = Stats.compute(input, SynergyResolver.resolve({ input }))
	return math.floor(stats.hp * boss.hpMultiplier)
end

local function copyRewards(rewards: Types.RewardMap): Types.RewardMap
	return table.clone(rewards)
end

function RaidMath.tiers(maxHp: number): { { minDamage: number, rewards: Types.RewardMap } }
	local list: { { minDamage: number, rewards: Types.RewardMap } } = {}
	for _, tier in Raids.tiers do
		table.insert(list, {
			minDamage = math.max(1, math.ceil(tier.minHpFraction * maxHp)),
			rewards = copyRewards(tier.rewards),
		})
	end
	return list
end

-- Reward untuk damage terkredit: tier tertinggi dengan minDamage <= damage. Damage 0 = tanpa reward.
function RaidMath.rewardsFor(damage: number, maxHp: number): (Types.RewardMap, number)
	local best: Types.RewardMap = {}
	local bestIndex = 0
	for index, tier in RaidMath.tiers(maxHp) do
		if damage >= tier.minDamage then
			best = tier.rewards
			bestIndex = index
		end
	end
	return best, bestIndex
end

-- Damage yang diterima boss (unit tim B bukan panggilan dengan unitId boss) dari event log server,
-- dibulatkan ke bawah dan dibatasi HP maksimum boss.
function RaidMath.creditedDamage(result: Types.BattleResult, maxHp: number): number
	local bossIds: { [number]: boolean } = {}
	local total = 0
	for _, event in result.log do
		if event.kind == "spawn" then
			local spawn = event :: any
			if spawn.side == "B" and spawn.owner == nil and spawn.unitId == boss.unitId then
				bossIds[spawn.unit] = true
			end
		elseif event.kind == "attack" or event.kind == "damage" then
			local hit = event :: any
			if bossIds[hit.dst] and type(hit.dmg) == "number" and hit.dmg == hit.dmg and hit.dmg > 0 then
				total += hit.dmg
			end
		end
	end
	if total == math.huge then
		return maxHp
	end
	return math.clamp(math.floor(total), 0, maxHp)
end

return table.freeze(RaidMath)
