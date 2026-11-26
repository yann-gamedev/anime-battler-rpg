--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local ProgressRemote = require(script.Parent.ProgressRemote)

export type Rewards = { [string]: number }
export type Info = { unlocked: boolean, showcaseUid: string?, showcaseSkinId: string? }
export type Quest = {
	id: string,
	period: "Daily" | "Weekly",
	periodKey: string,
	title: string,
	description: string,
	progress: number,
	target: number,
	claimed: boolean,
	rewards: Rewards,
}
export type Quests = { serverTime: number, dailyResetAt: number, weeklyResetAt: number, quests: { Quest } }
export type Raid = {
	unlocked: boolean,
	bossName: string,
	bossId: string,
	bossMaxHp: number,
	bestDamage: number,
	attempted: boolean,
	resetAt: number,
	serverTime: number,
	rewardTiers: { { minDamage: number, rewards: Rewards } },
}
export type RaidResult = { raid: Raid, damage: number, rewards: Rewards, replay: Types.BattleResult }

local Remote = {}
local request = ProgressRemote.request

local INVALID = "Unexpected server reply. Refresh to check your latest status."

local function validTime(value: any): boolean
	return type(value) == "number" and value >= 0 and value < math.huge
end

local function validRewards(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	for key, amount in value do
		if type(key) ~= "string" or not validTime(amount) then
			return false
		end
	end
	return true
end

function Remote.showcase(uid: string?, skinId: string?): (Info?, string?)
	local data, failure
	if uid then
		data, failure = request("SetLobbyShowcase", uid, skinId)
	else
		data, failure = request("GetLobbyInfo")
	end
	if
		type(data) ~= "table"
		or type(data.unlocked) ~= "boolean"
		or (data.showcaseUid ~= nil and type(data.showcaseUid) ~= "string")
		or (data.showcaseSkinId ~= nil and type(data.showcaseSkinId) ~= "string")
	then
		return nil, failure or INVALID
	end
	return data, nil
end

function Remote.quests(quest: Quest?): (Quests?, string?)
	local data, failure
	if quest then
		data, failure = request("ClaimQuest", quest.id, quest.periodKey)
	else
		data, failure = request("GetQuests")
	end
	if
		type(data) ~= "table"
		or not validTime(data.serverTime)
		or not validTime(data.dailyResetAt)
		or not validTime(data.weeklyResetAt)
		or type(data.quests) ~= "table"
	then
		return nil, failure or INVALID
	end
	for _, row in data.quests do
		if
			type(row) ~= "table"
			or type(row.id) ~= "string"
			or type(row.periodKey) ~= "string"
			or (row.period ~= "Daily" and row.period ~= "Weekly")
			or type(row.title) ~= "string"
			or type(row.description) ~= "string"
			or not validTime(row.progress)
			or not validTime(row.target)
			or type(row.claimed) ~= "boolean"
			or not validRewards(row.rewards)
		then
			return nil, INVALID
		end
	end
	return data, nil
end

local function validRaid(data: any): boolean
	if
		type(data) ~= "table"
		or type(data.unlocked) ~= "boolean"
		or type(data.bossName) ~= "string"
		or type(data.bossId) ~= "string"
		or not validTime(data.bossMaxHp)
		or not validTime(data.bestDamage)
		or type(data.attempted) ~= "boolean"
		or not validTime(data.resetAt)
		or not validTime(data.serverTime)
		or type(data.rewardTiers) ~= "table"
	then
		return false
	end
	for _, tier in data.rewardTiers do
		if type(tier) ~= "table" or not validTime(tier.minDamage) or not validRewards(tier.rewards) then
			return false
		end
	end
	return true
end

function Remote.raid(): (Raid?, string?)
	local data, failure = request("GetRaidInfo")
	if not validRaid(data) then
		return nil, failure or INVALID
	end
	return data, nil
end

function Remote.startRaid(teamIndex: number): (RaidResult?, string?)
	local data, failure = request("StartRaid", teamIndex)
	if
		type(data) ~= "table"
		or not validRaid(data.raid)
		or not validTime(data.damage)
		or not validRewards(data.rewards)
		or type(data.replay) ~= "table"
		or type(data.replay.log) ~= "table"
		or not validTime(data.replay.ticks)
		or (data.replay.winner ~= "A" and data.replay.winner ~= "B" and data.replay.winner ~= "draw")
	then
		return nil, failure or INVALID
	end
	return data, nil
end

local rewardNames: { [string]: string } = {
	Gold = "Gold",
	Gems = "Gems",
	XPScrolls = "XP Scrolls",
	TraitShards = "Trait Shards",
	SummonTickets = "Summon Tickets",
	BattlePassXP = "Battle Pass XP",
	BattlePassXp = "Battle Pass XP",
}

function Remote.rewards(rewards: Rewards): string
	local parts = {}
	for key, amount in rewards do
		if amount > 0 then
			table.insert(parts, string.format("%d %s", amount, rewardNames[key] or key))
		end
	end
	table.sort(parts)
	return if #parts == 0 then "No rewards" else table.concat(parts, "  ·  ")
end

function Remote.countdown(resetAt: number, now: number): string
	local seconds = math.max(0, math.ceil(resetAt - now))
	local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
	return string.format("%dh %02dm %02ds", hours, minutes, seconds % 60)
end

return table.freeze(Remote)
