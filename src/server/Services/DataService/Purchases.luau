--!strict
-- Bagian DataService: pemilik mutasi pembelian (receipt Developer Product, Toko Akademi) dan bukti simpan
-- receipt. Grant, bonus pertama, stats.robuxSpent, dan marker receipt masuk SATU commit (Commit.run).
-- `confirmSaved` boleh yield: memicu Save ProfileStore lalu menunggu LastSavedData memuat marker receipt
-- (docs ProfileStore "Developer Products"). Fallback mock / DataStore tanpa akses tidak dianggap tahan lama.
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Products = require(Shared.Config.Products)
local Signal = require(Shared.Util.Signal)
local Validate = require(script.Parent.Parent.Parent.Util.Validate)
local Commit = require(script.Parent.Commit)
local Replication = require(script.Parent.Replication)
local ShopRules = require(script.Parent.ShopRules)

export type ReceiptRequest = ShopRules.ReceiptRequest
export type ReceiptResult = ShopRules.ReceiptResult
type Connection = { Disconnect: (any) -> () }
type SignalLike = { Connect: (any, (...any) -> ()) -> Connection }
-- Bagian sesi ProfileStore yang dipakai di sini (lihat ProfileStore.luau: Save, LastSavedData, OnAfterSave).
export type SaveSession = {
	Data: Types.Profile,
	LastSavedData: any,
	OnAfterSave: SignalLike,
	OnSessionEnd: SignalLike,
	IsActive: (any) -> boolean,
	Save: (any) -> (),
}
export type ShopState = {
	gems: number,
	shards: number,
	firstBonusUsed: { [string]: boolean },
	academyOwned: { [string]: boolean },
	premiumSeasons: { [string]: boolean },
}
export type Options = {
	isDurable: () -> boolean, -- true hanya bila ProfileStore memakai DataStore asli (bukan mock)
	waitForSave: ((session: SaveSession, timeout: number) -> ())?,
	sleep: ((seconds: number) -> ())?,
	now: (() -> number)?,
	newUid: (() -> string)?,
}
export type Ledger = {
	isReceiptId: (purchaseId: any) -> boolean,
	isReceiptProcessed: (player: Player, purchaseId: string) -> boolean,
	markReceiptProcessed: (player: Player, purchaseId: string) -> boolean,
	grantReceipt: (player: Player, request: ReceiptRequest) -> (string?, ReceiptResult?),
	confirmSaved: (player: Player, purchaseId: string) -> boolean,
	buyAcademy: (player: Player, item: Types.AcademyItemDef) -> string?,
	getShopState: (player: Player) -> ShopState?,
	getMyData: (player: Player) -> Types.MyData?,
}

local isLabel = Validate.isStringMax(128)
local RECEIPT = Products.receipt

local Purchases = {}

-- Menunggu satu OnAfterSave atau akhir sesi, paling lama `timeout` detik.
local function defaultWaitForSave(session: SaveSession, timeout: number): ()
	local thread = coroutine.running()
	local done = false
	local connections: { Connection } = {}
	local function finish()
		if done then
			return
		end
		done = true
		for _, connection in connections do
			connection:Disconnect()
		end
		task.spawn(thread)
	end
	table.insert(connections, session.OnAfterSave:Connect(finish))
	table.insert(connections, session.OnSessionEnd:Connect(finish))
	task.delay(timeout, finish)
	coroutine.yield()
end

local function defaultUid(): string
	return HttpService:GenerateGUID(false)
end

local function isSavedIn(saved: any, purchaseId: string): boolean
	return type(saved) == "table"
		and type(saved.processedReceipts) == "table"
		and saved.processedReceipts[purchaseId] == true
end

function Purchases.create(
	getSession: (Player) -> SaveSession?,
	changed: Signal.Signal<Player, string>,
	options: Options
): Ledger
	local waitForSave = options.waitForSave or defaultWaitForSave
	local sleep = options.sleep or task.wait
	local clock = options.now or os.time
	local newUid = options.newUid or defaultUid
	local commitSession = getSession :: Commit.SessionGetter

	local function isReceiptId(purchaseId: any): boolean
		return isLabel(purchaseId) and purchaseId ~= "" and utf8.len(purchaseId) ~= nil
	end

	local function isReceiptProcessed(player: Player, purchaseId: string): boolean
		local session = getSession(player)
		return session ~= nil and isReceiptId(purchaseId) and session.Data.processedReceipts[purchaseId] == true
	end

	-- Kompatibilitas API lama: hanya menandai. Jalur receipt memakai grantReceipt (grant + marker atomik).
	local function markReceiptProcessed(player: Player, purchaseId: string): boolean
		local session = getSession(player)
		if not session or not isReceiptId(purchaseId) then
			return false
		end
		session.Data.processedReceipts[purchaseId] = true
		return true
	end

	local function grantReceipt(player: Player, request: ReceiptRequest): (string?, ReceiptResult?)
		if type(request) ~= "table" or not isReceiptId(request.purchaseId) then
			return "INVALID_RECEIPT", nil
		end
		-- Marker sudah ada di memori (retry saat save tertunda): jangan buka commit, jangan grant ulang.
		if isReceiptProcessed(player, request.purchaseId) then
			return nil, { duplicate = true, firstBonus = false, granted = 0, premiumAlreadyOwned = false }
		end
		local result: ReceiptResult? = nil
		local code = Commit.run(commitSession, changed, player, function(draft: Types.Profile)
			local failure, outcome, applied = ShopRules.applyReceipt(draft, request)
			result = applied
			return failure, outcome
		end)
		if code ~= nil then
			return code, nil
		end
		return nil, result
	end

	-- true hanya bila LastSavedData (data yang terbukti tersimpan) memuat marker receipt ini.
	local function confirmSaved(player: Player, purchaseId: string): boolean
		local session = getSession(player)
		if not session or not isReceiptId(purchaseId) or not options.isDurable() then
			return false
		end
		if isSavedIn(session.LastSavedData, purchaseId) then
			return true
		end
		if session.Data.processedReceipts[purchaseId] ~= true then
			return false
		end
		for attempt = 1, RECEIPT.saveAttempts do
			if getSession(player) ~= session or not session:IsActive() or not options.isDurable() then
				return false
			end
			local before = session.LastSavedData
			session:Save()
			if session.LastSavedData == before then
				waitForSave(session, RECEIPT.saveWaitSeconds)
			end
			if isSavedIn(session.LastSavedData, purchaseId) then
				return options.isDurable()
			end
			if attempt < RECEIPT.saveAttempts then
				sleep(RECEIPT.saveRetrySeconds)
			end
		end
		return false
	end

	local function buyAcademy(player: Player, item: Types.AcademyItemDef): string?
		local now = clock()
		return (
			Commit.run(commitSession, changed, player, function(draft: Types.Profile)
				return ShopRules.buyAcademy(draft, item, now, newUid)
			end)
		)
	end

	local function getShopState(player: Player): ShopState?
		local session = getSession(player)
		if not session then
			return nil
		end
		local profile = session.Data
		local purchases = profile.purchases
		local academyOwned: { [string]: boolean } = {}
		for _, item in Products.academy do
			if purchases and purchases.academy and ShopRules.isAcademyOwned(profile, item) then
				academyOwned[item.id] = true
			end
		end
		local premiumSeasons: { [string]: boolean } = {}
		local seasons = if profile.battlePass then profile.battlePass.seasons else {}
		for seasonId, record in seasons do
			if ShopRules.readSeason(record).premium then
				premiumSeasons[seasonId] = true
			end
		end
		return {
			gems = profile.currencies.Gems,
			shards = profile.currencies.TraitShards,
			firstBonusUsed = if purchases then table.clone(purchases.firstBonus) else {},
			academyOwned = academyOwned,
			premiumSeasons = premiumSeasons,
		}
	end

	local function getMyData(player: Player): Types.MyData?
		local session = getSession(player)
		return if session then Replication.buildMyData(session.Data) else nil
	end

	return {
		isReceiptId = isReceiptId,
		isReceiptProcessed = isReceiptProcessed,
		markReceiptProcessed = markReceiptProcessed,
		grantReceipt = grantReceipt,
		confirmSaved = confirmSaved,
		buyAcademy = buyAcademy,
		getShopState = getShopState,
		getMyData = getMyData,
	}
end

return table.freeze(Purchases)
