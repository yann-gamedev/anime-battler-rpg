--!strict
-- Inti analytics yang bisa di-test: anggaran request, isolasi kegagalan backend, dan bentuk event.
-- Backend asli (Roblox AnalyticsService) dipasang di init.luau; test memakai backend mock.
-- Semua nilai string berasal dari config/label server, bukan teks pemain.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Analytics = require(Shared.Config.Analytics)

export type Fields = { string }? -- maks 3 nilai → CustomField01..03
export type Backend = {
	economy: (
		player: Player,
		isSource: boolean,
		currency: string,
		amount: number,
		endingBalance: number,
		transactionType: string,
		itemSku: string
	) -> (),
	onboarding: (player: Player, step: number, stepName: string) -> (),
	custom: (player: Player, eventName: string, value: number, fields: Fields) -> (),
}
export type Deps = {
	backend: Backend,
	clock: () -> number,
	playerCount: () -> number,
	warn: (message: string) -> (),
}
export type Core = {
	economy: (player: Player, currency: string, delta: number, endingBalance: number, source: string) -> boolean,
	onboarding: (player: Player, step: number) -> boolean,
	custom: (player: Player, eventName: string, value: number, fields: Fields) -> boolean,
	stats: () -> { sent: number, dropped: number, failed: number },
}

local Core = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Label server → itemSku aman (alfanumerik/_/-, panjang terbatas).
function Core.sku(source: string): string
	if type(source) ~= "string" or source == "" or #source > Analytics.maxSkuLength then
		return "other"
	end
	return if string.match(source, "^[%w_%-]+$") then source else "other"
end

function Core.transactionType(source: string): string
	return Analytics.transactionTypes[source] or Analytics.defaultTransactionType
end

local stepNames: { [number]: string } = {}
for _, entry in Analytics.onboardingSteps do
	stepNames[entry.step] = entry.name
end

function Core.create(deps: Deps): Core
	local windowStart = deps.clock()
	local used = 0
	local sent, dropped, failed = 0, 0, 0
	local lastWarn: { [string]: number } = {}

	local function allow(): boolean
		local now = deps.clock()
		if now - windowStart >= Analytics.budgetWindowSeconds then
			windowStart = now
			used = 0
		end
		local budget = Analytics.budgetBase + Analytics.budgetPerPlayer * math.max(0, deps.playerCount())
		if used >= budget then
			dropped += 1
			return false
		end
		used += 1
		return true
	end

	-- Panggilan backend bisa gagal (layanan Roblox); error di-log dengan jeda, tidak pernah dilempar ke pemanggil.
	local function send(kind: string, fn: (...any) -> (), ...: any): boolean
		if not allow() then
			return false
		end
		local ok, err = pcall(fn, ...)
		if ok then
			sent += 1
			return true
		end
		failed += 1
		local now = deps.clock()
		if lastWarn[kind] == nil or now - lastWarn[kind] >= Analytics.failureWarnSeconds then
			lastWarn[kind] = now
			deps.warn(`[Analytics] {kind} gagal: {err}`)
		end
		return false
	end

	local function economy(
		player: Player,
		currency: string,
		delta: number,
		endingBalance: number,
		source: string
	): boolean
		if not isFinite(delta) or delta == 0 or not isFinite(endingBalance) or type(currency) ~= "string" then
			return false
		end
		return send(
			"economy",
			deps.backend.economy,
			player,
			delta > 0,
			currency,
			math.abs(delta),
			math.max(0, endingBalance),
			Core.transactionType(source),
			Core.sku(source)
		)
	end

	local function onboarding(player: Player, step: number): boolean
		local name = stepNames[step]
		if not name then
			return false
		end
		return send("onboarding", deps.backend.onboarding, player, step, name)
	end

	local function custom(player: Player, eventName: string, value: number, fields: Fields): boolean
		if type(eventName) ~= "string" or not isFinite(value) then
			return false
		end
		local clean: { string }? = nil
		if fields then
			clean = {}
			for index = 1, math.min(#fields, 3) do
				table.insert(clean :: { string }, Core.sku(fields[index]))
			end
		end
		return send("custom", deps.backend.custom, player, eventName, value, clean)
	end

	local function stats()
		return { sent = sent, dropped = dropped, failed = failed }
	end

	return { economy = economy, onboarding = onboarding, custom = custom, stats = stats }
end

return table.freeze(Core)
