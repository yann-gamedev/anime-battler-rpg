--!strict
-- Registry SEMUA remote (docs/RULES.md §2). Server membuat instance di ReplicatedStorage.Remotes
-- lewat src/server/Net/RemoteSetup.luau; client hanya WaitForChild.
-- Semua RemoteFunction hanya C→S dan mengembalikan { ok: boolean, code: string?, data: any? }.

local Remotes = {
	FOLDER_NAME = "Remotes",
	Events = {} :: { string }, -- RemoteEvent
	Functions = { -- RemoteFunction, hanya C→S
		"GetTeamBoard", -- () → Result<TeamBoardData>
		"SaveTeam", -- (teamIndex: number, slots: { string }) → Result<TeamBoardData>
	},
}

table.freeze(Remotes.Events)
table.freeze(Remotes.Functions)
return table.freeze(Remotes)
