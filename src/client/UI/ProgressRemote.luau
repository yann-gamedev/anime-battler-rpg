--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Remotes = require(Shared.Net.Remotes)
local Units = require(Shared.Config.Units)

export type Progression = {
	accountLevel: number,
	maxBoardUnits: number,
	xpScrolls: number,
	tutorialBattleCleared: boolean,
	tutorialDone: boolean,
}

export type Snapshot = {
	progression: Progression?,
	currencies: Types.Currencies,
	units: { [string]: Types.ClientOwnedUnit },
	teams: { { name: string, slots: { string } } },
	story: { cleared: { [string]: number } },
}

export type StageResult = {
	stageId: string,
	replay: Types.BattleResult,
	stars: number,
	rewards: { Gold: number, Gems: number, XPScrolls: number, SummonTickets: number },
	firstThreeStar: boolean,
	progression: Progression,
}

local ProgressRemote = {}
local errors: { [string]: string } = {
	DATA_NOT_READY = "Your profile is still loading. Try again in a moment.",
	RATE_LIMITED = "Wait a moment before trying again.",
	STAGE_LOCKED = "Complete the previous stage to unlock this one.",
	EMPTY_TEAM = "Deploy units and save your team first.",
	UNIT_NOT_OWNED = "A selected unit is no longer in your inventory.",
	UNIT_LOCKED = "Unlock the selected unit before using it as material.",
	UNIT_IN_TEAM = "Remove the selected unit from every saved team first.",
	NOT_ENOUGH_GOLD = "You need more Gold.",
	NOT_ENOUGH_XP_SCROLLS = "You need more XP Scrolls.",
	LEVEL_MAX = "This unit is already at maximum level.",
	LEVEL_EXCEEDS_MAX = "This upgrade would exceed the maximum level.",
	STARS_MAX = "This unit already has maximum stars.",
	WRONG_MATERIAL_COUNT = "Choose the required number of duplicates.",
	UNIT_MISMATCH = "Merge materials must match the target unit.",
	UNIT_NOT_DISMANTLABLE = "This unit cannot be dismantled.",
	TUTORIAL_NOT_DONE = "Finish onboarding before dismantling units.",
}

local function request(name: string, ...: any): (any, string?)
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, 4)
	local remote = folder and folder:WaitForChild(name, 4)
	if not remote or not remote:IsA("RemoteFunction") then
		return nil, "This service is unavailable. Try again."
	end
	local invoked, reply = pcall(remote.InvokeServer, remote, ...)
	if not invoked then
		warn("[Progress] " .. name .. " failed: " .. tostring(reply))
		return nil, "Connection interrupted. Reload your profile before trying again."
	end
	if type(reply) ~= "table" then
		return nil, "Unexpected server reply. Reload your profile."
	end
	if reply.ok ~= true then
		local code = if type(reply.code) == "string" then reply.code else "UNKNOWN"
		return nil, errors[code] or string.format("Request failed (%s).", code)
	end
	return reply.data, nil
end

local function validProgression(data: any): boolean
	return type(data) == "table"
		and type(data.accountLevel) == "number"
		and type(data.maxBoardUnits) == "number"
		and type(data.xpScrolls) == "number"
		and type(data.tutorialBattleCleared) == "boolean"
		and type(data.tutorialDone) == "boolean"
end

function ProgressRemote.parseSnapshot(data: any): (Snapshot?, string?)
	local invalid = "Unexpected profile data. Reload your profile."
	if
		type(data) ~= "table"
		or type(data.units) ~= "table"
		or type(data.teams) ~= "table"
		or type(data.story) ~= "table"
		or type(data.story.cleared) ~= "table"
		or type(data.currencies) ~= "table"
		or (data.progression ~= nil and not validProgression(data.progression))
	then
		return nil, invalid
	end
	for _, key in { "Gold", "SummonTickets", "Gems", "TraitShards" } do
		if type(data.currencies[key]) ~= "number" then
			return nil, invalid
		end
	end
	for uid, unit in data.units do
		if
			type(uid) ~= "string"
			or type(unit) ~= "table"
			or unit.uid ~= uid
			or type(unit.unitId) ~= "string"
			or not Units[unit.unitId]
			or type(unit.level) ~= "number"
			or type(unit.stars) ~= "number"
			or type(unit.locked) ~= "boolean"
			or (unit.trait ~= nil and type(unit.trait) ~= "string")
		then
			return nil, invalid
		end
	end
	for _, team in data.teams do
		if type(team) ~= "table" or type(team.slots) ~= "table" then
			return nil, invalid
		end
		for cell, uid in team.slots do
			if type(cell) ~= "number" or type(uid) ~= "string" then
				return nil, invalid
			end
		end
	end
	for _, stars in data.story.cleared do
		if type(stars) ~= "number" or stars < 0 or stars > 3 or stars % 1 ~= 0 then
			return nil, invalid
		end
	end
	return data, nil
end

function ProgressRemote.snapshot(name: string, ...: any): (Snapshot?, string?)
	local data, errorMessage = request(name, ...)
	if errorMessage then
		return nil, errorMessage
	end
	return ProgressRemote.parseSnapshot(data)
end

function ProgressRemote.startStage(stageId: string, teamIndex: number): (StageResult?, string?)
	local data, errorMessage = request("StartStage", stageId, teamIndex)
	if errorMessage then
		return nil, errorMessage
	end
	if
		type(data) ~= "table"
		or data.stageId ~= stageId
		or type(data.replay) ~= "table"
		or type(data.replay.log) ~= "table"
		or type(data.replay.ticks) ~= "number"
		or (data.replay.winner ~= "A" and data.replay.winner ~= "B" and data.replay.winner ~= "draw")
		or type(data.rewards) ~= "table"
		or not validProgression(data.progression)
		or type(data.firstThreeStar) ~= "boolean"
		or type(data.stars) ~= "number"
		or data.stars < 0
		or data.stars > 3
		or data.stars % 1 ~= 0
	then
		return nil, "Unexpected battle result. Reload your profile to check your progress."
	end
	for _, key in { "Gold", "Gems", "XPScrolls", "SummonTickets" } do
		if type(data.rewards[key]) ~= "number" then
			return nil, "Unexpected rewards. Reload your profile to check your progress."
		end
	end
	return data, nil
end

return table.freeze(ProgressRemote)
