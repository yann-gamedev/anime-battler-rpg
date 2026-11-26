--!strict
-- PENYIMPANAN SESI DEMO — TIDAK PERSISTEN.
-- Profil hanya hidup di memori server selama pemain di server ini; rejoin = profil baru.
-- Dipakai sampai ProfileStore diverifikasi & di-vendor (prompts/02-data-service.md).
-- Antarmuka sengaja kecil (load/release) agar bisa diganti adapter ProfileStore tanpa
-- mengubah API DataService. Modul ini HANYA boleh di-require oleh DataService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)
local Template = require(script.Parent.Template)

export type LoadResult = { profile: Types.Profile, isNew: boolean }

local SessionStore = {}

SessionStore.PERSISTENT = false

local sessions: { [number]: Types.Profile } = {}

function SessionStore.load(userId: number): LoadResult?
	local existing = sessions[userId]
	if existing then
		return { profile = existing, isNew = false }
	end
	local profile = Template.create(os.time())
	sessions[userId] = profile
	return { profile = profile, isNew = true }
end

function SessionStore.release(userId: number)
	sessions[userId] = nil
end

return SessionStore
