--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Units = require(Shared.Config.Units)
local Constants = require(Shared.Config.Constants)
local Types = require(Shared.Types)
local TIMEOUT = 4

local errors: { [string]: string } = {
	DATA_NOT_READY = "Your profile is still loading. Try again in a moment.",
	RATE_LIMITED = "Wait a moment before trying again.",
	ARENA_NOT_READY = "The practice arena is unavailable.",
	EMPTY_TEAM = "Place at least one unit to start a battle.",
	UNIT_NOT_OWNED = "A unit is no longer in your roster.",
}

local TeamBoardRemote = {}
local function request(name: string, ...: any): (Types.Result?, string?, string?)
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, TIMEOUT)
	local remote = folder and folder:WaitForChild(name, TIMEOUT)
	if not remote or not remote:IsA("RemoteFunction") then
		return nil, "Team service unavailable. Try again."
	end

	local invoked, response = pcall(remote.InvokeServer, remote, ...)
	if not invoked then
		warn("[TeamBoard] " .. name .. " failed: " .. tostring(response))
		return nil, "Connection failed. Try again."
	end
	if type(response) ~= "table" or response.ok ~= true then
		local code = if type(response) == "table" and type(response.code) == "string" then response.code else "UNKNOWN"
		return nil, errors[code] or "Request failed (" .. code .. "). Try again.", code
	end
	return response, nil
end

function TeamBoardRemote.load(teamIndex: number, slots: { string }?): (Types.TeamBoardData?, string?, string?)
	local response, failure, code
	if slots then
		response, failure, code = request("SaveTeam", teamIndex, slots)
	elseif teamIndex == 1 then
		response, failure, code = request("GetTeamBoard")
	else
		response, failure, code = request("GetTeamBoard", teamIndex)
	end
	if not response then
		return nil, failure, code
	end
	local data = response.data
	if
		type(data) ~= "table"
		or type(data.slots) ~= "table"
		or #data.slots ~= Constants.BOARD_SLOTS
		or type(data.units) ~= "table"
		or type(data.maxUnits) ~= "number"
	then
		return nil, "Unexpected server reply. Try again."
	end
	for index = 1, Constants.BOARD_SLOTS do
		if type(data.slots[index]) ~= "string" then
			return nil, "Unexpected server reply. Try again."
		end
	end
	for _, unit in data.units do
		local def = if type(unit) == "table" and type(unit.unitId) == "string" then Units[unit.unitId] else nil
		if
			not def
			or type(unit.uid) ~= "string"
			or type(unit.name) ~= "string"
			or unit.element ~= def.element
			or unit.rarity ~= def.rarity
			or unit.status ~= def.status
			or type(unit.level) ~= "number"
			or type(unit.stars) ~= "number"
		then
			return nil, "Unexpected unit data. Try again."
		end
	end
	return data, nil
end

function TeamBoardRemote.startPractice(teamIndex: number): (boolean, string?)
	local response, failure = request("StartPracticeBattle", teamIndex)
	return response ~= nil, failure
end

return table.freeze(TeamBoardRemote)
