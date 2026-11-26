--!strict
-- Bagian DataService: pemilik mutasi Battle Pass (XP musim, klaim tier) lewat Commit.run.
-- BattlePassService hanya memanggil fungsi bernama di sini dengan reward dari config musim.
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local Commit = require(script.Parent.Commit)
local BattlePassRules = require(script.Parent.BattlePassRules)
local ShopRules = require(script.Parent.ShopRules)

export type ClaimRequest = BattlePassRules.ClaimRequest
export type Options = { now: (() -> number)?, newUid: (() -> string)? }
export type Ledger = {
	-- Salinan record musim tersanitasi; nil bila data belum siap.
	getSeason: (player: Player, seasonId: string) -> Types.BattlePassSeasonRecord?,
	-- Bingkai profil terakhir yang dimiliki (lintas musim), atau nil.
	getProfileFrame: (player: Player) -> string?,
	addXp: (player: Player, seasonId: string, amount: number, maxXp: number) -> (string?, number?),
	claim: (player: Player, request: ClaimRequest) -> string?,
}

local BattlePass = {}

local function defaultUid(): string
	return HttpService:GenerateGUID(false)
end

function BattlePass.create(
	getSession: Commit.SessionGetter,
	changed: Signal.Signal<Player, string>,
	options: Options?
): Ledger
	local clock = if options and options.now then options.now else os.time
	local newUid = if options and options.newUid then options.newUid else defaultUid

	local function getSeason(player: Player, seasonId: string): Types.BattlePassSeasonRecord?
		local session = getSession(player)
		if not session or type(seasonId) ~= "string" then
			return nil
		end
		local battlePass = (session.Data :: any).battlePass
		local seasons = if type(battlePass) == "table" and type(battlePass.seasons) == "table"
			then battlePass.seasons
			else {}
		return ShopRules.readSeason(seasons[seasonId])
	end

	local function getProfileFrame(player: Player): string?
		local session = getSession(player)
		local battlePass = if session then (session.Data :: any).battlePass else nil
		if type(battlePass) ~= "table" or type(battlePass.profileFrames) ~= "table" then
			return nil
		end
		local frameId = battlePass.profileFrameId
		return if type(frameId) == "string" and battlePass.profileFrames[frameId] == true then frameId else nil
	end

	local function addXp(player: Player, seasonId: string, amount: number, maxXp: number): (string?, number?)
		local xp: number? = nil
		local code = Commit.run(getSession, changed, player, function(draft: Types.Profile)
			local failure, outcome, updated = BattlePassRules.addXp(draft, seasonId, amount, maxXp)
			xp = updated
			return failure, outcome
		end)
		if code ~= nil then
			return code, nil
		end
		return nil, xp
	end

	local function claim(player: Player, request: ClaimRequest): string?
		local now = clock()
		local copy = table.clone(request)
		return (
			Commit.run(getSession, changed, player, function(draft: Types.Profile)
				return BattlePassRules.claim(draft, copy, now, newUid)
			end)
		)
	end

	return { getSeason = getSeason, getProfileFrame = getProfileFrame, addXp = addXp, claim = claim }
end

return table.freeze(BattlePass)
