--!strict
-- Bootstrap server (docs/ARCHITECTURE.md §3):
-- 1) buat remote dari registry, 2) require semua service, 3) init() semua, 4) start() semua,
-- 5) jalankan Dev/TestRunner hanya jika ModuleScript-nya ada (dimiliki branch test runner).
local Net = script:WaitForChild("Net")
local RemoteSetup = require(Net:WaitForChild("RemoteSetup")) :: any

type Service = { init: () -> (), start: () -> () }

RemoteSetup.init()

local services: { { name: string, module: Service } } = {}
for _, child in script:WaitForChild("Services"):GetChildren() do
	if child:IsA("ModuleScript") then
		local module = (require :: any)(child) :: Service
		assert(typeof(module.init) == "function", `{child.Name}.init tidak ada`)
		assert(typeof(module.start) == "function", `{child.Name}.start tidak ada`)
		table.insert(services, { name = child.Name, module = module })
	end
end
-- Urutan deterministik agar log & perilaku boot konsisten.
table.sort(services, function(a, b)
	return a.name < b.name
end)

for _, entry in services do
	entry.module.init()
end
for _, entry in services do
	task.spawn(entry.module.start)
end

print("[Server] booted")

local dev = script:FindFirstChild("Dev")
local testRunner = dev and dev:FindFirstChild("TestRunner")
if testRunner and testRunner:IsA("ModuleScript") then
	local runner = (require :: any)(testRunner)
	if typeof(runner) == "table" and typeof(runner.run) == "function" then
		task.spawn(runner.run)
	end
end
