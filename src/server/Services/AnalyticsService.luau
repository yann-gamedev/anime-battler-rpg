--!strict
local AnalyticsService = {}

function AnalyticsService.init(): () end

function AnalyticsService.start(): () end

function AnalyticsService.logCurrencyChange(userId: number, kind: string, delta: number, source: string): ()
	print(`[Analytics] currency UserId={userId} kind={kind} delta={delta} source={source}`)
end

-- Pembelian Developer Product yang baru diberikan (bukan retry). robuxSpent = CurrencySpent aktual.
function AnalyticsService.logPurchase(userId: number, productKey: string, robuxSpent: number, firstBonus: boolean): ()
	print(`[Analytics] purchase UserId={userId} product={productKey} robux={robuxSpent} firstBonus={firstBonus}`)
end

return table.freeze(AnalyticsService)
