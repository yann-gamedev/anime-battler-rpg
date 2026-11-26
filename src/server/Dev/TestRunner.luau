--!strict
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: { [any]: any }) -> (),
	toBeTruthy: () -> (),
}

export type TestContext = {
	test: (name: string, fn: () -> ()) -> (),
	expect: (actual: any) -> Expectation,
}

local TestRunner = {}

local function deepEqual(actual: any, expected: any, seen: { [any]: { [any]: boolean } }): boolean
	if rawequal(actual, expected) then
		return true
	end
	if type(actual) ~= "table" or type(expected) ~= "table" then
		return false
	end

	local compared = seen[actual]
	if not compared then
		compared = {}
		seen[actual] = compared
	end
	if compared[expected] then
		return true
	end
	compared[expected] = true

	for key, value in next, actual do
		if not deepEqual(value, rawget(expected, key), seen) then
			return false
		end
	end
	for key in next, expected do
		if rawget(actual, key) == nil then
			return false
		end
	end
	return true
end

local function expect(actual: any): Expectation
	return {
		toBe = function(expected: any): ()
			if actual ~= expected then
				error(
					string.format(
						"Expected %s (%s), got %s (%s)",
						tostring(expected),
						typeof(expected),
						tostring(actual),
						typeof(actual)
					),
					2
				)
			end
		end,
		toEqual = function(expected: { [any]: any }): ()
			if not deepEqual(actual, expected, {}) then
				error("Expected structurally equal tables", 2)
			end
		end,
		toBeTruthy = function(): ()
			if not actual then
				error(string.format("Expected a truthy value, got %s", tostring(actual)), 2)
			end
		end,
	}
end

local function captureFailure(err: any): string
	return debug.traceback(tostring(err), 2)
end

function TestRunner.run(): ()
	if not RunService:IsStudio() or workspace:GetAttribute("RunTests") ~= true then
		return
	end

	local folder = ServerStorage:FindFirstChild("Tests")
	if not folder then
		warn("[Tests] ServerStorage.Tests is missing")
		return
	end

	local specs: { ModuleScript } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") and string.match(child.Name, "%.spec$") then
			table.insert(specs, child)
		end
	end
	table.sort(specs, function(a: ModuleScript, b: ModuleScript): boolean
		return a.Name < b.Name
	end)

	local passed = 0
	local failed = 0
	local specErrors = 0
	for _, module in specs do
		local context: TestContext = {
			expect = expect,
			test = function(name: string, fn: () -> ()): ()
				local ok, failure = xpcall(fn, captureFailure)
				if ok then
					passed += 1
				else
					failed += 1
					warn(string.format("[Tests] FAIL %s / %s\n%s", module.Name, name, tostring(failure)))
				end
			end,
		}
		local ok, failure = xpcall(function()
			local spec = require(module)
			assert(type(spec) == "function", "Spec must return a function")
			spec(context)
		end, captureFailure)
		if not ok then
			specErrors += 1
			warn(string.format("[Tests] ERROR %s\n%s", module.Name, tostring(failure)))
		end
	end

	local summary = string.format(
		"[Tests] %d passed, %d failed, %d spec errors across %d specs",
		passed,
		failed,
		specErrors,
		#specs
	)
	if failed > 0 or specErrors > 0 or passed == 0 then
		warn(summary)
	else
		print(summary)
	end
end

return TestRunner
