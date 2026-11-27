--!strict
-- Bagian DataService: indeks UID unit milik sesi aktif di server ini (deteksi dupe, SYSTEMS A4).
-- Saat profil dimuat, UID yang masih dimiliki pemain lain yang aktif = flag + log (TIDAK dihapus otomatis).
-- Setelah trade sah, UID dipindah ke pemilik baru. Flag palsu dari entri basi dicegah dengan memeriksa
-- profil pemilik lama saat ini.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)

export type DupeFlag = { uid: string, userId: number, otherUserId: number, at: number }
export type Index = {
	indexProfile: (player: Player, profile: Types.Profile) -> { DupeFlag },
	unindex: (player: Player) -> (),
	move: (uids: { string }, to: Player?) -> (),
}

local TradeIndex = {}

function TradeIndex.create(profileOf: (Player) -> Types.Profile?, clock: () -> number): Index
	local uidOwners: { [string]: Player } = {}
	local ownedUids: { [Player]: { [string]: boolean } } = {}

	local function move(uids: { string }, to: Player?): ()
		for _, uid in uids do
			local from = uidOwners[uid]
			if from and ownedUids[from] then
				ownedUids[from][uid] = nil
			end
			uidOwners[uid] = to
			if to and ownedUids[to] then
				ownedUids[to][uid] = true
			end
		end
	end

	local function indexProfile(player: Player, profile: Types.Profile): { DupeFlag }
		local flags: { DupeFlag } = {}
		local mine: { [string]: boolean } = {}
		ownedUids[player] = mine
		for uid in profile.units do
			local other = uidOwners[uid]
			local otherProfile = if other and other ~= player then profileOf(other) else nil
			if other and otherProfile and otherProfile.units[uid] ~= nil then
				table.insert(flags, { uid = uid, userId = player.UserId, otherUserId = other.UserId, at = clock() })
			else
				uidOwners[uid] = player
			end
			mine[uid] = true
		end
		return flags
	end

	local function unindex(player: Player): ()
		local mine = ownedUids[player]
		ownedUids[player] = nil
		if mine then
			for uid in mine do
				if uidOwners[uid] == player then
					uidOwners[uid] = nil
				end
			end
		end
	end

	return { indexProfile = indexProfile, unindex = unindex, move = move }
end

return table.freeze(TradeIndex)
