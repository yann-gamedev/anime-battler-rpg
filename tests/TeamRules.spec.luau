--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestRunner = require(game:GetService("ServerScriptService").Server.Dev.TestRunner)

return function(t: TestRunner.TestContext): ()
	local module = ReplicatedStorage.Shared:FindFirstChild("TeamRules")
	assert(
		module and module:IsA("ModuleScript"),
		"TeamRules is missing. Integrate the backend branch to run this spec."
	)
	local TeamRules = require(module)
	local ownedByUid: { [string]: boolean } = { ["unit-a"] = true, ["unit-b"] = true, ["unowned"] = false }

	local function expectResult(slots: any, maxUnits: number, expectedCode: string?): ()
		local ok, code = TeamRules.validateSlots(slots, ownedByUid, maxUnits)
		t.expect(ok).toBe(expectedCode == nil)
		t.expect(code).toBe(expectedCode)
	end

	t.test("accepts an empty board at a zero-unit limit", function()
		expectResult(table.create(9, ""), 0, nil)
	end)

	t.test("accepts distinct owned units at the exact limit in slots 1 and 9", function()
		local slots = table.create(9, "")
		slots[1] = "unit-a"
		slots[9] = "unit-b"
		expectResult(slots, 2, nil)
	end)

	t.test("accepts a full board when all nine units are owned and allowed", function()
		local slots: { string } = {}
		local owned: { [string]: boolean } = {}
		for index = 1, 9 do
			local uid = "unit-" .. tostring(index)
			slots[index] = uid
			owned[uid] = true
		end
		local ok, code = TeamRules.validateSlots(slots, owned, 9)
		t.expect(ok).toBe(true)
		t.expect(code).toBe(nil)
	end)

	t.test("rejects absent and non-table slots", function()
		expectResult(nil, 3, "INVALID_SLOTS")
		expectResult("unit-a", 3, "INVALID_SLOTS")
	end)

	t.test("rejects arrays shorter or longer than nine slots", function()
		expectResult(table.create(8, ""), 3, "INVALID_SLOTS")
		expectResult(table.create(10, ""), 3, "INVALID_SLOTS")
	end)

	t.test("rejects sparse arrays and non-string values", function()
		local sparse: { [number]: string? } = table.create(9, "")
		sparse[5] = nil
		expectResult(sparse, 3, "INVALID_SLOTS")

		local wrongType: { any } = table.create(9, "")
		wrongType[5] = false
		expectResult(wrongType, 3, "INVALID_SLOTS")
	end)

	t.test("rejects extra keys outside the dense array", function()
		local slots: { [any]: string? } = table.create(9, "")
		slots.label = "board"
		expectResult(slots, 3, "INVALID_SLOTS")
		slots.label = nil
		slots[0] = ""
		expectResult(slots, 3, "INVALID_SLOTS")
	end)

	t.test("rejects UIDs absent from or denied by the ownership map", function()
		local slots = table.create(9, "")
		slots[5] = "missing"
		expectResult(slots, 3, "UNIT_NOT_OWNED")
		slots[5] = "unowned"
		expectResult(slots, 3, "UNIT_NOT_OWNED")
	end)

	t.test("rejects an owned UID repeated across slots", function()
		local slots = table.create(9, "")
		slots[1] = "unit-a"
		slots[9] = "unit-a"
		expectResult(slots, 3, "DUPLICATE_UNIT")
	end)

	t.test("rejects too many distinct owned units, including at limit zero", function()
		local slots = table.create(9, "")
		slots[1] = "unit-a"
		expectResult(slots, 0, "TOO_MANY_UNITS")
		slots[9] = "unit-b"
		expectResult(slots, 1, "TOO_MANY_UNITS")
	end)
end
