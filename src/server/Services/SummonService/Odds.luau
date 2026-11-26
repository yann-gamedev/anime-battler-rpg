--!strict
-- Tabel odds untuk UI, dihitung dari Roll.distribution (fungsi bobot yang sama dengan roll server).
-- odds.ten = peluang marginal tiap posisi 1..N sebelum pembelian, dihitung dengan iterasi eksak atas
-- state (pity, jaminan featured, rare-streak batch). Jumlah state terbatas: tiap posisi hanya menambah
-- cabang "reset" atau "lanjut" per counter, jadi paling banyak O(N²) × 4 state.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Banners = require(Shared.Config.Banners)
local Units = require(Shared.Config.Units)
local Roll = require(script.Parent.Roll)

type PityState = Roll.PityState
type Node = { state: PityState, allRare: boolean, probability: number }

-- Batas pengaman iterasi state; jauh di atas kebutuhan batch 10×.
local MAX_STATES = 4096

local Odds = {}

local function toPercent(value: number): number
	return math.clamp(value, 0, 100)
end

-- Bentuk tabel odds dari peluang per unit (0..100). Urutan unit mengikuti Roll.distribution.
function Odds.fromUnitPercents(order: Roll.Distribution, percents: { [string]: number }): Types.Odds
	local byRarity: { [Types.Rarity]: number } = { Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
	local units: { Types.UnitOdds } = {}
	for _, entry in order do
		local percent = toPercent(percents[entry.unitId] or 0)
		byRarity[entry.rarity] += percent
		table.insert(units, {
			unitId = entry.unitId,
			name = Units[entry.unitId].name,
			rarity = entry.rarity,
			percent = percent,
		})
	end
	local rarities: { Types.RarityOdds } = {}
	for _, rarity in Roll.RARITIES do
		table.insert(rarities, { rarity = rarity, percent = toPercent(byRarity[rarity]) })
	end
	return { rarities = rarities, units = units }
end

function Odds.fromDistribution(entries: Roll.Distribution): Types.Odds
	local percents: { [string]: number } = {}
	for _, entry in entries do
		percents[entry.unitId] = entry.percent
	end
	return Odds.fromUnitPercents(entries, percents)
end

function Odds.base(banner: Types.BannerDef): Types.Odds
	return Odds.fromDistribution(Roll.baseDistribution(banner))
end

-- Peluang individual aktual draw berikutnya untuk summon 1×.
function Odds.single(banner: Types.BannerDef, state: PityState): Types.Odds
	return Odds.fromDistribution(
		Roll.distribution(banner, state, { position = 1, batchCount = 1, allRareSoFar = true })
	)
end

local function nodeKey(state: PityState, allRare: boolean): string
	return `{state.sinceLegendary}:{state.sinceMythic}:{state.guaranteedFeatured}:{allRare}`
end

-- Marginal per posisi untuk batch `count` (default 10×) dari state pity saat ini.
function Odds.marginals(banner: Types.BannerDef, state: PityState, count: number?): { Types.Odds }
	local batchCount = count or Banners.multiSummonGuarantee.count
	local order = Roll.baseDistribution(banner)
	local nodes: { [string]: Node } = {
		[nodeKey(state, true)] = { state = state, allRare = true, probability = 1 },
	}
	local result: { Types.Odds } = {}
	for position = 1, batchCount do
		local percents: { [string]: number } = {}
		local nextNodes: { [string]: Node } = {}
		local stateCount = 0
		for _, node in nodes do
			local context = { position = position, batchCount = batchCount, allRareSoFar = node.allRare }
			for _, entry in Roll.distribution(banner, node.state, context) do
				if entry.percent > 0 then
					local probability = node.probability * entry.percent / 100
					percents[entry.unitId] = (percents[entry.unitId] or 0) + probability * 100
					local nextState = Roll.advance(banner, node.state, entry.rarity, entry.unitId)
					local allRare = node.allRare and entry.rarity == "Rare"
					local key = nodeKey(nextState, allRare)
					local existing = nextNodes[key]
					if existing then
						existing.probability += probability
					else
						stateCount += 1
						assert(stateCount <= MAX_STATES, "Odds.marginals: state space exceeded")
						nextNodes[key] = { state = nextState, allRare = allRare, probability = probability }
					end
				end
			end
		end
		table.insert(result, Odds.fromUnitPercents(order, percents))
		nodes = nextNodes
	end
	return result
end

return table.freeze(Odds)
