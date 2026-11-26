--!strict
-- Registry SEMUA remote (docs/RULES.md §2). Server membuat instance di ReplicatedStorage.Remotes
-- lewat src/server/Net/RemoteSetup.luau; client hanya WaitForChild.
-- Semua RemoteFunction hanya C→S dan mengembalikan { ok: boolean, code: string?, data: any? }.

local Remotes = {
	FOLDER_NAME = "Remotes",
	Events = { "InventoryChanged", "CurrencyChanged", "BattleResult" }, -- S→C
	Functions = { -- RemoteFunction, hanya C→S
		"GetMyData",
		"StartTestBattle",
		"StartPracticeBattle",
		"GetTeamBoard", -- (teamIndex: number?) → Result<TeamBoardData>; default 1
		"SaveTeam", -- (teamIndex: number, slots: { string }) → Result<TeamBoardData>
		"StartStage", -- (stageId: string, teamIndex: number) → Result<StageResultData>
		"StartAutoReplay", -- (stageId: string, teamIndex: number) → Result<StageResultData>; gp_autoreplay + 3★
		"LevelUpUnit", -- (uid: string, levels: number) → Result<MyData>
		"MergeUnit", -- (targetUid: string, materialUids: { string }) → Result<MyData>
		"DismantleUnit", -- (uids: { string }) → Result<MyData>
		"LockUnit", -- (uid: string, locked: boolean) → Result<MyData>
		"GetBannerInfo", -- () → Result<BannerInfo>
		"Summon", -- (bannerId: string, count: 1 | 10, payWith: "Gems" | "Tickets") → Result<SummonResultData>
		"GetTraitInfo", -- (uid: string) → Result<TraitInfo>
		"RerollTrait", -- (uid: string) → Result<TraitRerollData>
		"SelectRestrictedTrait", -- (uid: string, traitId: string) → Result<TraitRerollData>
		"GetShopInfo", -- () → Result<ShopInfo>
		"PrepareShopPurchase", -- (productKey: string) → Result<PreparedPurchase>; tidak pernah memberi reward
		"BuyAcademyItem", -- (itemId: string) → Result<ShopInfo>
		"GetBattlePass", -- () → Result<PassInfo>
		"ClaimBattlePassTier", -- (track: "Free" | "Premium", tier: number, unitId: string?) → Result<PassInfo>
	},
}

table.freeze(Remotes.Events)
table.freeze(Remotes.Functions)
return table.freeze(Remotes)
