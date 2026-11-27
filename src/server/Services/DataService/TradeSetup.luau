--!strict
-- Bagian DataService: merakit trade (ledger, jurnal, DataStore TradeLog) dan kait muat/keluar profil.
-- Dipisah dari init.luau agar file < 400 baris. TradeLog hanya dibuka di sini (RULES §3).
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local Trade = require(Shared.Config.Trade)
local Purchases = require(script.Parent.Purchases)
local TradeJournal = require(script.Parent.TradeJournal)
local TradeLog = require(script.Parent.TradeLog)
local TradeRules = require(script.Parent.TradeRules)
local Trades = require(script.Parent.Trades)

export type Api = {
	isEnabled: () -> boolean,
	checkPlayer: (player: Player, accountAgeDays: number) -> string?,
	checkOffer: (player: Player, offer: Trades.Offer) -> string?,
	checkPair: (a: Trades.Party, b: Trades.Party) -> string?,
	lock: (player: Player, lock: Trades.Lock) -> (),
	unlock: (player: Player) -> (),
	commit: (a: Trades.Party, b: Trades.Party, onResolved: ((code: string?) -> ())?) -> (string?, any?),
	describeUnits: (player: Player, uids: { string }) -> { Trades.UnitBrief },
	isUidLocked: (player: Player, uid: string) -> boolean,
	goldReserve: (player: Player) -> number,
	isLocked: (player: Player) -> boolean,
}
export type Hooks = {
	api: Api,
	guard: (player: Player, original: Types.Profile, draft: Types.Profile) -> string?,
	recover: (player: Player, session: any) -> (boolean, { any }),
	afterLoad: (player: Player, session: any, toFinish: { any }) -> (),
	remove: (player: Player) -> (),
}

local TradeSetup = {}

local function openLog(): TradeLog.Log?
	local isStudio = RunService:IsStudio()
	local enabled = if isStudio then Trade.studioEnabled else Trade.liveEnabled
	if not enabled then
		return nil
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(if isStudio then "TradeLog_Studio" else "TradeLog")
	end)
	if not ok then
		warn(`[DataService] TradeLog tidak tersedia, trade dimatikan: {store}`)
		return nil
	end
	local optionsOk, getOptions = pcall(function()
		local options = Instance.new("DataStoreGetOptions")
		options.UseCache = false -- baca indeks pemulihan langsung dari backend (bypass cache 4 detik)
		return options
	end)
	return TradeLog.create(store :: any, { getOptions = if optionsOk then getOptions else nil })
end

function TradeSetup.create(
	getSession: (Player) -> any,
	changed: Signal.Signal<Player, string>,
	isDurable: () -> boolean
): Hooks
	local log = openLog()
	local ledger = Trades.create(getSession, changed, os.time)
	local journal = TradeJournal.create({
		ledger = ledger,
		log = log,
		getSession = getSession,
		isDurable = isDurable,
		waitForSave = Purchases.defaultWaitForSave,
		sleep = function(seconds: number)
			task.wait(seconds)
		end,
		spawn = function(fn: () -> ())
			task.spawn(fn)
		end,
		newId = function(): string
			return HttpService:GenerateGUID(false)
		end,
	})

	local function afterLoad(player: Player, session: any, toFinish: { any }): ()
		for _, record in toFinish do
			task.spawn(journal.finish, player, record)
		end
		local profile = session.Data :: Types.Profile
		local flags = ledger.indexProfile(player, profile)
		if #flags == 0 then
			return
		end
		TradeRules.reconcile(profile)
		local stored = (profile :: any).trade.dupeFlags :: { [string]: number }
		for _, flag in flags do
			warn(`[DataService] UID ganda {flag.uid}: UserId={flag.userId} & UserId={flag.otherUserId} (tidak dihapus)`)
			local count = 0
			for _ in stored do
				count += 1
			end
			if stored[flag.uid] == nil and count < Trade.log.maxDupeFlagsPerProfile then
				stored[flag.uid] = flag.at
			end
			if log then
				task.spawn(log.flagDupe, TradeRules.utcDay(flag.at), flag :: any)
			end
		end
	end

	return {
		api = {
			isEnabled = journal.isEnabled,
			checkPlayer = ledger.checkPlayer,
			checkOffer = ledger.checkOffer,
			checkPair = ledger.checkPair,
			lock = ledger.lock,
			unlock = ledger.unlock,
			commit = journal.commit,
			describeUnits = ledger.describeUnits,
			isUidLocked = ledger.isUidLocked,
			goldReserve = ledger.goldReserve,
			isLocked = function(player: Player): boolean
				return ledger.goldReserve(player) > 0
			end,
		},
		guard = ledger.guard,
		recover = function(player: Player, session: any): (boolean, { any })
			return journal.recover(player.UserId, session)
		end,
		afterLoad = afterLoad,
		remove = ledger.unindex,
	}
end

return table.freeze(TradeSetup)
