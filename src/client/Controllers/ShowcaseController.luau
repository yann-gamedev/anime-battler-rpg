--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ShowcaseController = {}

function ShowcaseController.start(): ()
	local joints: { [Motor6D]: number } = {}
	local frame: RBXScriptConnection?
	local function stopIfEmpty()
		local connection = frame
		if connection and next(joints) == nil then
			connection:Disconnect()
			frame = nil
		end
	end

	local function add(instance: Instance)
		if not instance:IsA("Motor6D") or instance.Name ~= "IdleJoint" then
			return
		end
		local root = instance.Parent
		local model = root and root.Parent
		local character = model and model.Parent
		if not root or root.Name ~= "Root" or not model or model.Name ~= "LobbyShowcase" then
			return
		end
		if not character or not character:IsA("Model") then
			return
		end
		local owner = Players:GetPlayerFromCharacter(character)
		if not owner then
			return
		end
		joints[instance] = owner.UserId % 19
		if not frame then
			frame = RunService.PreSimulation:Connect(function()
				local phase = time() * 2
				for joint, offset in joints do
					joint.Transform = CFrame.new(0, 0.2 * math.sin(phase + offset), 0)
						* CFrame.Angles(0, 0.12 * math.sin(phase * 0.65 + offset), 0)
				end
			end)
		end
	end

	local removing = Workspace.DescendantRemoving:Connect(function(instance)
		if instance:IsA("Motor6D") and joints[instance] ~= nil then
			joints[instance] = nil
			instance.Transform = CFrame.identity
			stopIfEmpty()
		end
	end)
	local added = Workspace.DescendantAdded:Connect(add)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			for _, instance in character:GetDescendants() do
				add(instance)
			end
		end
	end
	script.Destroying:Once(function()
		added:Disconnect()
		removing:Disconnect()
		for joint in joints do
			joint.Transform = CFrame.identity
		end
		table.clear(joints)
		stopIfEmpty()
	end)
end

return table.freeze(ShowcaseController)
