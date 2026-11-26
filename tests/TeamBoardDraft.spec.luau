--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Units = require(Shared.Config.Units)
local Draft = require(Shared.TeamBoardDraft)
local TestRunner = require(game:GetService("ServerScriptService").Server.Dev.TestRunner)

local function owned(uid: string, id: string): Types.TeamBoardUnit
	local def = Units[id]
	return {
		uid = uid,
		unitId = id,
		name = def.name,
		rarity = def.rarity,
		element = def.element,
		status = def.status,
		stars = 1,
		level = 1,
	}
end

return function(t: TestRunner.TestContext): ()
	t.test("combines rarity and element filters", function()
		local unit = owned("one", "kael")
		t.expect(Draft.matches(unit, nil, nil)).toBe(true)
		t.expect(Draft.matches(unit, "Api", "Rare")).toBe(true)
		t.expect(Draft.matches(unit, "Api", "Epic")).toBe(false)
		t.expect(Draft.matches(unit, "Es", "Rare")).toBe(false)
	end)

	t.test("moves, swaps, replaces and removes units without exceeding capacity", function()
		local slots = table.create(9, "")
		t.expect(Draft.place(slots, "first", 1, 2)).toBe(true)
		t.expect(Draft.place(slots, "second", 2, 2)).toBe(true)
		t.expect(Draft.place(slots, "third", 3, 2)).toBe(false)
		t.expect(Draft.place(slots, "first", 2, 2)).toBe(true)
		t.expect(slots[1]).toBe("second")
		t.expect(slots[2]).toBe("first")
		t.expect(Draft.place(slots, "third", 1, 2)).toBe(true)
		t.expect(Draft.place(slots, "third", 1, 2)).toBe(true)
		t.expect(Draft.count(slots)).toBe(1)
		t.expect(Draft.place(slots, "first", 9, 2)).toBe(true)
		t.expect(slots[2]).toBe("")
		t.expect(slots[9]).toBe("first")
	end)

	t.test("updates active synergy tiers for draft edits and counts duplicate unit definitions once", function()
		local units = { a = owned("a", "kael"), b = owned("b", "kael"), c = owned("c", "pip"), d = owned("d", "ignis") }
		local slots = table.create(9, "")
		Draft.place(slots, "a", 1, 3)
		Draft.place(slots, "b", 2, 3)
		t.expect(Draft.synergies(slots, units).elements.Api).toBe(nil)
		Draft.place(slots, "c", 2, 3)
		t.expect(assert(Draft.synergies(slots, units).elements.Api).count).toBe(2)
		Draft.place(slots, "d", 3, 3)
		t.expect(assert(Draft.synergies(slots, units).elements.Api).count).toBe(3)
		t.expect(assert(Draft.synergies(slots, units).statuses.Familiar).count).toBe(2)
		Draft.place(slots, "c", 2, 3)
		t.expect(assert(Draft.synergies(slots, units).elements.Api).count).toBe(2)
		t.expect(Draft.synergies(slots, units).statuses.Familiar).toBe(nil)
	end)
end
