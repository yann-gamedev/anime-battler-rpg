--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Arena = require(Shared.Config.BattleArena)
local BattleReplay = require(Shared.BattleReplay)
local Types = require(Shared.Types)
local TestRunner = require(game:GetService("ServerScriptService").Server.Dev.TestRunner)

local function result(): Types.BattleResult
	return {
		winner = "A",
		ticks = 5,
		survivors = {},
		log = {
			{ t = 0, kind = "spawn", unit = 1, unitId = "seraphine", side = "A", cell = 9, hp = 100, maxHp = 100 },
			{
				t = 2,
				kind = "ultimate",
				src = 1,
				skill = "seraphine_dawn",
				cell = 10,
				targets = { 2 },
				cinematic = true,
			},
			{ t = 2, kind = "death", unit = 2 },
			{ t = 3, kind = "move", unit = 1, cell = 10, leap = false },
		},
	}
end

return function(t: TestRunner.TestContext): ()
	t.test("dispatches zero-tick spawns and reaches death exactly on its tick at either speed", function()
		for _, speed in { 1, 2 } do
			local clock = BattleReplay.new()
			local seen: { string } = {}
			local function collect(event: Types.BattleEvent): boolean
				table.insert(seen, event.kind)
				return false
			end
			local replay = result()
			t.expect(BattleReplay.advance(clock, replay, 0, speed, collect)).toBe(false)
			t.expect(seen).toEqual({ "spawn" })
			BattleReplay.advance(clock, replay, 0.199 / speed, speed, collect)
			t.expect(seen).toEqual({ "spawn" })
			BattleReplay.advance(clock, replay, 0.001 / speed, speed, collect)
			t.expect(seen).toEqual({ "spawn", "ultimate", "death" })
		end
	end)

	t.test("pauses exactly at an ultimate and resumes same-tick events without dropping or duplicating them", function()
		local clock = BattleReplay.new()
		local replay = result()
		local seen: { string } = {}
		local function collect(event: Types.BattleEvent): boolean
			table.insert(seen, event.kind)
			return event.kind == "ultimate"
		end
		t.expect(BattleReplay.advance(clock, replay, 0.4, 2, collect)).toBe(false)
		t.expect(clock.seconds).toBe(0.2)
		t.expect(seen).toEqual({ "spawn", "ultimate" })
		t.expect(BattleReplay.advance(clock, replay, 0, 1, collect)).toBe(false)
		t.expect(seen).toEqual({ "spawn", "ultimate", "death" })
		t.expect(BattleReplay.advance(clock, replay, 0.3, 1, collect)).toBe(true)
		t.expect(seen).toEqual({ "spawn", "ultimate", "death", "move" })
	end)

	t.test("positions the mirrored boards with an open seam", function()
		local firstX, firstZ = Arena.cellOffset(1)
		local lastX, lastZ = Arena.cellOffset(18)
		local nearX, nearZ = Arena.cellOffset(9)
		local farX, farZ = Arena.cellOffset(10)
		t.expect(firstX).toBe(-lastX)
		t.expect(firstZ).toBe(-lastZ)
		t.expect(nearX).toBe(-farX)
		t.expect(farZ - nearZ > Arena.cellSize).toBe(true)
	end)
end
