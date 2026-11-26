--!strict
local AnalyticsService = {}

function AnalyticsService.init(): () end

function AnalyticsService.start(): () end

function AnalyticsService.logCurrencyChange(userId: number, kind: string, delta: number, source: string): ()
	print(`[Analytics] currency UserId={userId} kind={kind} delta={delta} source={source}`)
end

return table.freeze(AnalyticsService)
