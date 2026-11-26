--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Skins = require(ReplicatedStorage.Shared.Config.Skins)
local Units = require(ReplicatedStorage.Shared.Config.Units)
local Types = require(ReplicatedStorage.Shared.Types)

local LobbyPage = require(script.Parent.LobbyPage)
local Page = require(script.Parent.ProgressPage)
local ProgressRemote = require(script.Parent.ProgressRemote)
local Remote = require(script.Parent.LobbyRemote)

local ShowcasePage = {}

function ShowcasePage.open(onBack: () -> ()): ()
	local page = LobbyPage.create("Unit Showcase", onBack)
	local profile: ProgressRemote.Snapshot?
	local info: Remote.Info?
	local busy = false
	local selected: Types.ClientOwnedUnit?
	local update: (string?, string?) -> ()
	local render: () -> ()

	render = function()
		Page.clear(page)
		local snapshot = profile
		local lobby = info
		if snapshot and lobby and lobby.unlocked then
			local current = lobby.showcaseUid and snapshot.units[lobby.showcaseUid]
			local skin = lobby.showcaseSkinId and Skins[lobby.showcaseSkinId]
			Page.label(
				page.body,
				if current
					then "Displayed: " .. Units[current.unitId].name .. (if skin then " · " .. skin.name else "")
					else "No unit displayed"
			)
			local unit = selected
			if unit then
				Page.label(page.body, "Choose a look for " .. Units[unit.unitId].name)
				Page.button(page.body, "Use default look", function()
					update(unit.uid, nil)
				end)
				local options = {}
				for id, owned in snapshot.skinsOwned or {} do
					local def = Skins[id]
					if owned and def and (def.unitId == nil or def.unitId == unit.unitId) then
						table.insert(options, id)
					end
				end
				table.sort(options)
				for _, id in options do
					Page.button(page.body, Skins[id].name, function()
						update(unit.uid, id)
					end)
				end
				Page.button(page.body, "Choose another unit", function()
					if not busy then
						selected = nil
						render()
					end
				end)
			else
				if current then
					Page.button(page.body, "Remove displayed unit", function()
						update("", nil)
					end)
				end
				local roster = {}
				for _, ownedUnit in snapshot.units do
					table.insert(roster, ownedUnit)
				end
				table.sort(roster, function(a, b)
					return if a.unitId == b.unitId then a.uid < b.uid else a.unitId < b.unitId
				end)
				if #roster == 0 then
					Page.label(page.body, "You have no units to display.")
				end
				for _, ownedUnit in roster do
					local def = Units[ownedUnit.unitId]
					local label = string.format("%s  ·  Lv. %d  ·  %d★", def.name, ownedUnit.level, ownedUnit.stars)
					if current == ownedUnit then
						label ..= "  ·  Displayed"
					end
					Page.button(page.body, label, function()
						if not busy then
							selected = ownedUnit
							render()
						end
					end)
				end
			end
		elseif lobby and not lobby.unlocked then
			Page.label(page.body, "Clear Story 1-3 to unlock your showcase.")
		end
		Page.button(page.body, "Refresh showcase", function()
			update(nil, nil)
		end)
		page.body.CanvasPosition = Vector2.zero
		LobbyPage.focus(page)
	end

	update = function(uid: string?, skinId: string?)
		if busy or not page.screen.Enabled then
			return
		end
		busy = true
		page.message.Text = if uid then "Saving display…" else "Loading showcase…"
		local reply, failure
		if uid then
			reply, failure = Remote.showcase(uid, skinId)
		end
		if not reply and page.screen.Enabled then
			local refreshFailure
			reply, refreshFailure = Remote.showcase(nil, nil)
			failure = failure or refreshFailure
		end
		if not page.screen.Enabled then
			return
		end
		if not uid or failure then
			local profileFailure
			profile, profileFailure = ProgressRemote.snapshot("GetMyData")
			failure = failure or profileFailure
		end
		if not page.screen.Enabled then
			return
		end
		info = reply
		selected = nil
		busy = false
		page.message.Text = failure or (if uid then "Display saved." else "")
		render()
	end

	task.spawn(update, nil, nil)
end

return table.freeze(ShowcasePage)
