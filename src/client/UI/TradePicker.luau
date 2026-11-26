--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.Trade)
local Units = require(Shared.Config.Units)
local Skins = require(Shared.Config.Skins)
local Page = require(script.Parent.ProgressPage)
local ProgressRemote = require(script.Parent.ProgressRemote)
local TradeState = require(script.Parent.TradeState)
local TradeView = require(script.Parent.TradeView)

local TradePicker = {}

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function TradePicker.peers(page: Page.Page, enabled: boolean, request: (number) -> ()): ()
	local player = Players.LocalPlayer
	local ownRoot = rootOf(player)
	local lobby = workspace:FindFirstChild(Config.plaza.lobbyName)
	local plaza = lobby and lobby:FindFirstChild(Config.plaza.partName)
	Page.label(page.body, "Meet another player at the Trading Plaza to send a request.")
	local count = 0
	if plaza and plaza:IsA("BasePart") and ownRoot then
		for _, peer in Players:GetPlayers() do
			local root = rootOf(peer)
			if
				peer ~= player
				and root
				and (root.Position - plaza.Position).Magnitude <= plaza.Size.Magnitude
				and (root.Position - ownRoot.Position).Magnitude <= Config.plaza.maxPairDistance
			then
				count += 1
				TradeView.button(
					page,
					"Peer" .. tostring(peer.UserId),
					"Request · " .. peer.DisplayName .. " (@" .. peer.Name .. ")",
					enabled,
					function()
						request(peer.UserId)
					end
				)
			end
		end
	end
	if count == 0 then
		Page.label(page.body, "No nearby players found.")
	end
end

function TradePicker.items(
	page: Page.Page,
	view: TradeState.View,
	profile: ProgressRemote.Snapshot,
	maxItems: number,
	enabled: boolean,
	submit: ({ string }, { string }) -> ()
): ()
	local units: { string } = {}
	local skins: { string } = {}
	local names = {}
	for _, unit in view.mine.units do
		local uid = unit.uid
		if uid then
			table.insert(units, uid)
			names[uid] = string.format("%s · %s · %d★", unit.name, unit.rarity, unit.stars)
		end
	end
	for _, skin in view.mine.skins do
		table.insert(skins, skin.skinId)
		names[skin.skinId] = "Skin · " .. skin.name
	end
	Page.label(page.body, string.format("Edit offer · %d / %d items", #units + #skins, maxItems))

	local function option(id: string, isSkin: boolean)
		local target = if isSkin then skins else units
		local index = table.find(target, id)
		local label = (if index then "Remove · " else "Add · ") .. names[id]
		TradeView.button(page, (if isSkin then "Skin:" else "Unit:") .. id, label, enabled, function()
			local nextUnits, nextSkins = table.clone(units), table.clone(skins)
			local changed = if isSkin then nextSkins else nextUnits
			if index then
				table.remove(changed, index)
			else
				table.insert(changed, id)
			end
			submit(nextUnits, nextSkins)
		end)
	end

	for _, uid in units do
		option(uid, false)
	end
	for _, id in skins do
		option(id, true)
	end
	if #units + #skins >= maxItems then
		Page.label(page.body, "Remove an offered item to add another.")
		return
	end
	local availableUnits = {}
	local availableSkins = {}
	for uid, unit in profile.units do
		local definition = Units[unit.unitId]
		if definition and unit.stars == Config.tradableStars and not unit.locked and not table.find(units, uid) then
			names[uid] =
				string.format("%s · %s · %d★ · Lv %d", definition.name, definition.rarity, unit.stars, unit.level)
			table.insert(availableUnits, uid)
		end
	end
	for id, owned in profile.skinsOwned or {} do
		local definition = Skins[id]
		if owned and definition and not table.find(skins, id) then
			names[id] = "Skin · " .. definition.name
			table.insert(availableSkins, id)
		end
	end
	local function byName(a: string, b: string): boolean
		return if names[a] == names[b] then a < b else names[a] < names[b]
	end
	table.sort(availableUnits, byName)
	table.sort(availableSkins, byName)
	for _, uid in availableUnits do
		option(uid, false)
	end
	for _, id in availableSkins do
		option(id, true)
	end
	if #availableUnits + #availableSkins == 0 then
		Page.label(page.body, "No more items to offer.")
	end
end

return table.freeze(TradePicker)
