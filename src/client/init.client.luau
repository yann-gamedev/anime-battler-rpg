--!strict

local controllers = {}

for _, child in script.Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		table.insert(controllers, require(child))
	end
end

for _, controller in controllers do
	if controller.init then
		controller.init()
	end
end

for _, controller in controllers do
	if controller.start then
		controller.start()
	end
end

print("[Client] booted")
