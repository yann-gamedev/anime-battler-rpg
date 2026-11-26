--!strict
-- Bentuk sesi ProfileStore yang dipakai DataService (dipisah dari init.luau agar file < 400 baris).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)

export type Session = {
	Data: Types.Profile,
	FirstSessionTime: number,
	OnSessionEnd: { Connect: (any, () -> ()) -> any },
	IsActive: (Session) -> boolean,
	AddUserId: (Session, number) -> (),
	Reconcile: (Session) -> (),
	EndSession: (Session) -> (),
	Save: (Session) -> (),
}

return table.freeze({})
