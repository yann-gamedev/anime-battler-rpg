--!strict
-- LobbyService (prompt 10, docs/GDD.md §2 "pamer"): satu unit pajangan per pemain mengikuti karakter di
-- lobby, terlihat semua pemain. Server memvalidasi & menyimpan pilihan lewat DataService.meta dan membuat
-- satu model ringan (Showcase.luau); client menganimasikan IdleJoint secara lokal.
-- Model dibangun ulang hanya saat isi berubah: pilihan baru, respawn, unit hilang/naik bintang, unlock, VIP.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local RemoteSetup = require(script.Parent.Parent.Net.RemoteSetup)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local Handlers = require(script.Handlers)
local Showcase = require(script.Showcase)

local LOAD_POLL_SECONDS = 1
local LOAD_POLL_LIMIT = 150
local VIP_ATTRIBUTE = Products.passAttributes.gp_vip_aura

local LobbyService = {}

type PlayerState = { connections: { RBXScriptConnection }, key: string?, generation: number }
local states: { [Player]: PlayerState } = {}

local function specFor(player: Player): Showcase.Spec?
	local state = DataService.meta.getShowcase(player)
	if not state or not state.unlocked or not state.uid or not state.unitId then
		return nil
	end
	return {
		unitId = state.unitId,
		skinId = state.skinId,
		stars = state.stars or 1,
		vipAura = MonetizationService.hasPass(player, "gp_vip_aura"),
		ownerUserId = player.UserId,
	}
end

-- Sinkronkan model dengan state server. force = karakter baru (model lama ikut hilang).
local function refresh(player: Player, force: boolean): ()
	local state = states[player]
	if not state or player.Parent ~= Players then
		return
	end
	local spec = specFor(player)
	local key = Showcase.key(spec)
	if not force and key == state.key then
		return
	end
	state.key = key
	state.generation += 1
	local generation = state.generation
	task.spawn(Showcase.apply, player.Character, spec, function(): boolean
		return states[player] == state and state.generation == generation
	end)
end

local handlers = Handlers.create({
	ledger = DataService.meta,
	onChanged = function(player: Player)
		refresh(player, false)
	end,
})

local function onPlayerAdded(player: Player): ()
	if states[player] then
		return
	end
	local state: PlayerState = { connections = {}, key = nil, generation = 0 }
	states[player] = state
	table.insert(
		state.connections,
		player.CharacterAdded:Connect(function()
			refresh(player, true)
		end)
	)
	table.insert(
		state.connections,
		player:GetAttributeChangedSignal(VIP_ATTRIBUTE):Connect(function()
			refresh(player, false)
		end)
	)
	-- Profil dimuat tanpa event Changed: tunggu (jarang, bukan per frame) sampai data siap lalu bangun.
	for _ = 1, LOAD_POLL_LIMIT do
		if states[player] ~= state then
			return
		end
		if DataService.meta.getShowcase(player) then
			refresh(player, true)
			return
		end
		task.wait(LOAD_POLL_SECONDS)
	end
end

local function onPlayerRemoving(player: Player): ()
	local state = states[player]
	states[player] = nil
	if state then
		for _, connection in state.connections do
			connection:Disconnect()
		end
	end
	Showcase.remove(player.Character)
end

function LobbyService.init(): ()
	RemoteSetup.bindFunction("GetLobbyInfo", handlers.GetLobbyInfo)
	RemoteSetup.bindFunction("SetLobbyShowcase", handlers.SetLobbyShowcase)
	-- Unit hilang (merge/dismantle/trade) atau berubah, serta unlock lobby: sinkronkan ulang bila perlu.
	DataService.Changed:Connect(function(player: Player, path: string)
		if path == "units" or path == "progress" then
			refresh(player, false)
		end
	end)
end

function LobbyService.start(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return LobbyService
