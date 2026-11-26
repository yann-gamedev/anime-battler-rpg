--!strict
local TestRunner = require(game:GetService("ServerScriptService").Server.Dev.TestRunner)

return function(t: TestRunner.TestContext): ()
	t.test("supports equality, nested tables, and truthiness", function()
		t.expect(1 + 1).toBe(2)
		t.expect({ slots = { "", "unit-a" } }).toEqual({ slots = { "", "unit-a" } })
		t.expect(0).toBeTruthy()
	end)
end
