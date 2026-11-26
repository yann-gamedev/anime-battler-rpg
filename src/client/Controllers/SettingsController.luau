--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local UI = script.Parent.Parent.UI
local LobbyPage = require(UI.LobbyPage)
local Page = require(UI.ProgressPage)
local Assets = require(ReplicatedStorage.Shared.Config.Assets)

local player = Players.LocalPlayer
local SettingsController = {}
local MUSIC = "MusicEnabled"
local SFX = "SoundEffectsEnabled"
local CINEMATICS = "BattleCinematicsEnabled"
local LOW_GRAPHICS = "LowGraphics"
local sfxGroup: SoundGroup?
local effects: { [string]: Sound } = {}

local settings = {
	{ key = MUSIC, title = "Music", default = true },
	{ key = SFX, title = "Sound effects", default = true },
	{ key = CINEMATICS, title = "Battle cinematics", default = true },
	{ key = LOW_GRAPHICS, title = "Low graphics", default = false },
}

function SettingsController.open(onBack: () -> ()): ()
	local page = LobbyPage.create("Settings", onBack)
	for _, setting in settings do
		local button: TextButton
		local function label(): string
			return setting.title .. (if player:GetAttribute(setting.key) == true then ": On" else ": Off")
		end
		button = Page.button(page.body, label(), function()
			player:SetAttribute(setting.key, player:GetAttribute(setting.key) ~= true)
			button.Text = label()
		end)
	end
	LobbyPage.focus(page)
end

local function group(name: string, setting: string): SoundGroup
	local item = Instance.new("SoundGroup")
	item.Name = name
	item.Parent = SoundService
	local function apply()
		item.Volume = if player:GetAttribute(setting) == true then 1 else 0
	end
	apply()
	player:GetAttributeChangedSignal(setting):Connect(apply)
	return item
end

local function sound(id: number, target: SoundGroup, looped: boolean): Sound
	local item = Instance.new("Sound")
	item.SoundId = "rbxassetid://" .. tostring(id)
	item.Looped = looped
	item.SoundGroup = target
	item.Parent = SoundService
	return item
end

function SettingsController.playEffect(key: string): ()
	local id = Assets.sounds[key]
	local target = sfxGroup
	if not id or id <= 0 or not target or player:GetAttribute(SFX) == false then
		return
	end
	local item = effects[key]
	if not item then
		item = sound(id, target, false)
		effects[key] = item
	end
	if item.IsPlaying then
		return
	end
	item:Play()
end

function SettingsController.lowGraphics(): boolean
	return player:GetAttribute(LOW_GRAPHICS) == true
end

function SettingsController.init(): ()
	for _, setting in settings do
		if player:GetAttribute(setting.key) == nil then
			player:SetAttribute(setting.key, setting.default)
		end
	end
	local music = group("ArcanumMusic", MUSIC)
	sfxGroup = group("ArcanumSfx", SFX)

	local track = Assets.sounds.academyMusic
	if track and track > 0 then
		sound(track, music, true):Play()
	end

	local suppressed: { [ParticleEmitter]: boolean } = {}
	local function apply(instance: Instance)
		if instance:IsA("ParticleEmitter") and suppressed[instance] == nil then
			suppressed[instance] = instance.Enabled
			instance.Enabled = false
			instance:Clear()
		end
	end
	local function audio(instance: Instance)
		if instance:IsA("Sound") and instance.SoundGroup == nil then
			local category = instance:GetAttribute("AudioCategory")
			if category == "Music" then
				instance.SoundGroup = music
			elseif category == "SFX" or (instance.Parent and instance.Parent.Name == "HumanoidRootPart") then
				instance.SoundGroup = sfxGroup
			end
		end
	end
	local function graphics()
		if SettingsController.lowGraphics() then
			for _, instance in Workspace:GetDescendants() do
				if instance:IsA("ParticleEmitter") then
					apply(instance)
				end
			end
		else
			for emitter, enabled in suppressed do
				emitter.Enabled = enabled
			end
			table.clear(suppressed)
		end
	end
	for _, root in { Workspace, SoundService } do
		for _, instance in root:GetDescendants() do
			audio(instance)
		end
		root.DescendantAdded:Connect(function(instance)
			audio(instance)
			if SettingsController.lowGraphics() and instance:IsA("ParticleEmitter") then
				apply(instance)
			end
		end)
	end
	Workspace.DescendantRemoving:Connect(function(instance)
		if instance:IsA("ParticleEmitter") then
			local enabled = suppressed[instance]
			if enabled ~= nil then
				instance.Enabled = enabled
				suppressed[instance] = nil
			end
		end
	end)
	player:GetAttributeChangedSignal(LOW_GRAPHICS):Connect(graphics)
	graphics()
end

return table.freeze(SettingsController)
