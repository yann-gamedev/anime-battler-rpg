--!strict
local Controllers = script.Parent.Parent.Controllers
local Lobby = require(Controllers.LobbyController)
local Monetization = require(Controllers.MonetizationController)
local Quest = require(Controllers.QuestController)
local Raid = require(Controllers.RaidController)
local Settings = require(Controllers.SettingsController)
local Summon = require(Controllers.SummonController)
local TeamBoard = require(Controllers.TeamBoardController)
local LobbyPage = require(script.Parent.LobbyPage)
local Page = require(script.Parent.ProgressPage)
local ProgressRemote = require(script.Parent.ProgressRemote)
local Showcase = require(script.Parent.ShowcasePage)

local LobbyRoutes = {}

function LobbyRoutes.openWorld(story: () -> (), directory: () -> ()): ()
	local function enter(): ()
		LobbyRoutes.openWorld(story, directory)
	end
	Lobby.open({
		Story = story,
		Summon = function()
			Summon.open(enter)
		end,
		Shop = function()
			Monetization.openShop(enter)
		end,
		Quests = function()
			Quest.open(enter)
		end,
		Raid = function()
			LobbyRoutes.openRaid(enter)
		end,
		Announcements = function()
			local function announcements(): ()
				local page = LobbyPage.create("Academy Announcements", enter)
				Page.label(page.body, "Daily quests and Boss Raid reset at 00:00 UTC.")
				Page.label(page.body, "Visit the Quest Desk or Boss Raid station in the courtyard.")
				Page.button(page.body, "View quests", function()
					Quest.open(announcements)
					page.screen:Destroy()
				end)
				LobbyPage.focus(page)
			end
			announcements()
		end,
		Directory = directory,
	})
end

function LobbyRoutes.openRaid(onBack: () -> ()): ()
	Raid.open(onBack, function()
		TeamBoard.open(function()
			LobbyRoutes.openRaid(onBack)
		end)
	end)
end

type DirectoryActions = {
	story: () -> (),
	inventory: () -> (),
	summon: () -> (),
	team: () -> (),
	resume: () -> (),
	world: () -> (),
	menu: (() -> ())?,
}

function LobbyRoutes.directory(
	page: Page.Page,
	profile: ProgressRemote.Snapshot?,
	unlocked: boolean,
	actions: DirectoryActions
): TextButton
	Page.label(page.body, if unlocked then "Arcanum Lobby" else "Arcanum Academy")
	local first = Page.button(
		page.body,
		if profile and profile.progression and not unlocked then "Continue onboarding" else "Story",
		actions.story
	)
	Page.button(page.body, "Inventory", actions.inventory)
	Page.button(page.body, "Summon", actions.summon)
	Page.button(page.body, "Team Board", actions.team)
	Page.button(page.body, "Academy Shop", function()
		Monetization.openShop(actions.resume)
	end)
	Page.button(page.body, "Battle Pass", function()
		Monetization.openPass(actions.resume)
	end)
	if unlocked then
		if Lobby.available() then
			Page.button(page.body, "Back to courtyard", actions.world)
		end
		Page.button(page.body, "Quests", function()
			Quest.open(actions.resume)
		end)
		Page.button(page.body, "Boss Raid", function()
			LobbyRoutes.openRaid(actions.resume)
		end)
		Page.button(page.body, "Unit Showcase", function()
			Showcase.open(actions.resume)
		end)
	end
	Page.button(page.body, "Settings", function()
		Settings.open(actions.resume)
	end)
	if unlocked and Lobby.available() and actions.menu then
		Page.button(page.body, "Main Menu", actions.menu)
	end
	if profile then
		local currency = profile.currencies
		Page.label(
			page.body,
			string.format(
				"Gold %d · Gems %d · Summon Tickets %d",
				currency.Gold,
				currency.Gems,
				currency.SummonTickets
			)
		)
	end
	return first
end

return table.freeze(LobbyRoutes)
