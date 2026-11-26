--!strict
local Types = require(script.Parent.Types)
local Constants = require(script.Parent.Config.Constants)

export type Clock = { seconds: number, nextEvent: number }
local BattleReplay = {}

function BattleReplay.new(): Clock
	return { seconds = 0, nextEvent = 1 }
end

-- The callback returns true when a cinematic interrupts playback at this event's tick.
function BattleReplay.advance(
	clock: Clock,
	result: Types.BattleResult,
	delta: number,
	speed: number,
	dispatch: (Types.BattleEvent) -> boolean
): boolean
	local ticksPerSecond = Constants.BATTLE_TICKS_PER_SECOND
	clock.seconds += delta * speed
	local currentTick = math.floor(clock.seconds * ticksPerSecond + 1e-7)
	local event = result.log[clock.nextEvent]
	while event and event.t <= currentTick do
		clock.nextEvent += 1
		if dispatch(event) then
			clock.seconds = event.t / ticksPerSecond
			return false
		end
		event = result.log[clock.nextEvent]
	end
	return currentTick >= result.ticks and event == nil
end

return table.freeze(BattleReplay)
