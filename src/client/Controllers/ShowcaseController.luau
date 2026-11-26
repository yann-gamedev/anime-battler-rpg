--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Products = require(ReplicatedStorage.Shared.Config.Products)
local Settings = require(script.Parent.SettingsController)
local auraConfig = Products.vipAura

type Showcase = {
	model: Model,
	offset: number,
	aura: Attachment?,
	connections: { RBXScriptConnection },
}

local ShowcaseController = {}

local function removeAura(showcase: Showcase): ()
	local aura = showcase.aura
	if aura then
		showcase.aura = nil
		aura:Destroy()
	end
end

local function updateAura(joint: Motor6D, showcase: Showcase): ()
	local body = joint.Part1
	if
		not body
		or body.Parent ~= showcase.model
		or not body:IsDescendantOf(Workspace)
		or showcase.model:GetAttribute("VipAura") ~= true
		or Settings.lowGraphics()
	then
		removeAura(showcase)
		return
	end

	if showcase.aura and showcase.aura.Parent == body then
		return
	end
	removeAura(showcase)

	local aura = Instance.new("Attachment")
	aura.Name = "ShowcaseVipAura"
	local particles = Instance.new("ParticleEmitter")
	particles.Rate = auraConfig.rate
	particles.Lifetime = NumberRange.new(auraConfig.lifetime)
	particles.Speed = NumberRange.new(auraConfig.speed)
	particles.Size = NumberSequence.new(auraConfig.size)
	particles.Color = ColorSequence.new(Color3.fromRGB(auraConfig.color.r, auraConfig.color.g, auraConfig.color.b))
	particles.LightEmission = 1
	particles.Parent = aura
	showcase.aura = aura
	aura.Parent = body
end

function ShowcaseController.start(): ()
	local joints: { [Motor6D]: Showcase } = {}
	local frame: RBXScriptConnection?
	local function remove(joint: Motor6D)
		local showcase = joints[joint]
		if not showcase then
			return
		end
		joints[joint] = nil
		for _, connection in showcase.connections do
			connection:Disconnect()
		end
		removeAura(showcase)
		joint.Transform = CFrame.identity
		if frame and next(joints) == nil then
			frame:Disconnect()
			frame = nil
		end
	end

	local function add(instance: Instance)
		if not instance:IsA("Motor6D") or instance.Name ~= "IdleJoint" or joints[instance] then
			return
		end
		local root = instance.Parent
		local model = root and root.Parent
		local character = model and model.Parent
		if not root or root.Name ~= "Root" or not model or not model:IsA("Model") or model.Name ~= "LobbyShowcase" then
			return
		end
		if not character or not character:IsA("Model") then
			return
		end
		local owner = Players:GetPlayerFromCharacter(character)
		if not owner then
			return
		end
		local showcase: Showcase = { model = model, offset = owner.UserId % 19, connections = {} }
		joints[instance] = showcase

		local function refresh()
			if joints[instance] == showcase then
				updateAura(instance, showcase)
			end
		end
		showcase.connections = {
			model:GetAttributeChangedSignal("VipAura"):Connect(refresh),
			instance:GetPropertyChangedSignal("Part1"):Connect(refresh),
			model.DescendantAdded:Connect(function(descendant)
				if descendant == instance.Part1 then
					refresh()
				end
			end),
			model.DescendantRemoving:Connect(function(descendant)
				if descendant == instance.Part1 then
					removeAura(showcase)
				end
			end),
		}
		refresh()

		if not frame then
			frame = RunService.PreSimulation:Connect(function()
				local phase = time() * 2
				for joint, display in joints do
					local offset = display.offset
					joint.Transform = CFrame.new(0, 0.2 * math.sin(phase + offset), 0)
						* CFrame.Angles(0, 0.12 * math.sin(phase * 0.65 + offset), 0)
				end
			end)
		end
	end

	local removing = Workspace.DescendantRemoving:Connect(function(instance)
		if instance:IsA("Motor6D") then
			remove(instance)
		end
	end)
	local added = Workspace.DescendantAdded:Connect(add)
	local graphics = Players.LocalPlayer:GetAttributeChangedSignal("LowGraphics"):Connect(function()
		for joint, showcase in joints do
			updateAura(joint, showcase)
		end
	end)
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
		graphics:Disconnect()
		for joint in joints do
			remove(joint)
		end
	end)
end

return table.freeze(ShowcaseController)
