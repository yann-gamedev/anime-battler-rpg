--!strict
-- Visual aura VIP (gp_vip_aura) dibuat SERVER pada karakter pemain sehingga tereplikasi ke semua client.
-- Kosmetik murni: tidak memengaruhi gameplay. Parameter dari Config/Products.vipAura.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Products = require(Shared.Config.Products)

local CONFIG = Products.vipAura
local ROOT_WAIT_SECONDS = 10

local Aura = {}

local function remove(character: Model): ()
	local root = character:FindFirstChild("HumanoidRootPart")
	local existing = root and root:FindFirstChild(CONFIG.name)
	if existing then
		existing:Destroy()
	end
end

local function add(root: BasePart): ()
	if root:FindFirstChild(CONFIG.name) then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = CONFIG.name
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = CONFIG.rate
	emitter.Lifetime = NumberRange.new(CONFIG.lifetime)
	emitter.Speed = NumberRange.new(CONFIG.speed)
	emitter.Size = NumberSequence.new(CONFIG.size)
	emitter.Color = ColorSequence.new(Color3.fromRGB(CONFIG.color.r, CONFIG.color.g, CONFIG.color.b))
	emitter.LightEmission = 1
	emitter.Parent = attachment
	attachment.Parent = root
end

-- Memasang / melepas aura pada karakter saat ini. Boleh yield (menunggu HumanoidRootPart).
function Aura.apply(character: Model?, enabled: boolean): ()
	if not character then
		return
	end
	if not enabled then
		remove(character)
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", ROOT_WAIT_SECONDS)
	if root and root:IsA("BasePart") and character.Parent ~= nil then
		add(root)
	end
end

return table.freeze(Aura)
