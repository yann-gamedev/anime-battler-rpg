--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

export type ProductKind = "DeveloperProduct" | "GamePass"
export type Product = {
	key: string,
	id: number,
	kind: ProductKind,
	name: string,
	available: boolean,
	owned: boolean,
	firstBonus: boolean?,
	grant: { currency: string, amount: number }?,
}
export type AcademyItem = {
	id: string,
	itemId: string,
	name: string,
	kind: "Unit" | "Skin",
	costGems: number,
	owned: boolean,
}
export type ShopInfo = {
	restricted: boolean,
	balances: { Gems: number, TraitShards: number },
	products: { Product },
	academy: { AcademyItem },
}
export type Track = "Free" | "Premium"
export type Reward = { kind: "Currency" | "UnitChoice" | "Skin", id: string?, amount: number?, options: { string }? }
export type Tier = {
	tier: number,
	free: { Reward },
	premium: { Reward },
	freeClaimed: boolean,
	premiumClaimed: boolean,
}
export type PassInfo = {
	seasonId: string,
	startsAt: number,
	endsAt: number,
	active: boolean,
	xp: number,
	xpPerTier: number,
	unlockedTier: number,
	premium: boolean,
	tiers: { Tier },
}

local Remote = {}

function Remote.request(name: string, ...: any): (any, string?)
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, 4)
	local remote = folder and folder:WaitForChild(name, 4)
	if not remote or not remote:IsA("RemoteFunction") then
		return nil, "Service unavailable. Try refreshing."
	end
	local ok, response = pcall(remote.InvokeServer, remote, ...)
	if not ok then
		warn("[Monetization] " .. name .. ": " .. tostring(response))
		return nil, "Connection interrupted. Refresh to check your account."
	end
	if type(response) == "table" and response.ok == true and type(response.data) == "table" then
		return response.data, nil
	end
	local code = if type(response) == "table" and type(response.code) == "string" then response.code else "UNKNOWN"
	return nil, "Request failed (" .. code .. ")."
end

return table.freeze(Remote)
