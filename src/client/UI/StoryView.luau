--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Stages = require(Shared.Config.Stages)
local Units = require(Shared.Config.Units)
local Constants = require(Shared.Config.Constants)
local SynergyResolver = require(Shared.BattleSim.SynergyResolver)
local Types = require(Shared.Types)
local Controls = require(script.Parent.Components.Controls)
local Theme = require(script.Parent.Theme)
local Page = require(script.Parent.ProgressPage)
local Remote = require(script.Parent.ProgressRemote)

local StoryView = {}

function StoryView.guide(body: ScrollingFrame, data: Remote.Snapshot): ()
	local progression = data.progression
	if not progression or progression.tutorialDone then
		return
	end
	if not progression.tutorialBattleCleared then
		local starters: { string } = {}
		for _, id in Constants.STARTER_UNIT_IDS do
			table.insert(starters, Units[id].name)
		end
		Page.label(body, "Learn auto battle with your starters: " .. table.concat(starters, ", ") .. ".")
		return
	end

	local team = data.teams[1]
	local deployed: { Types.BattleUnitInput } = {}
	if team then
		for cell, uid in team.slots do
			local unit = data.units[uid]
			if unit then
				table.insert(
					deployed,
					{ unitId = unit.unitId, stars = unit.stars, level = unit.level, trait = unit.trait, cell = cell }
				)
			end
		end
	end
	local fire = SynergyResolver.resolve(deployed).elements.Api
	Page.label(
		body,
		if fire
			then string.format(
				"Api synergy active. Your Api units burn enemies for %g%% HP per second.",
				(fire.burnHpPerSecond or 0) * 100
			)
			else "Deploy two different Api units (such as Kael and Pip) and save your team to activate Burn."
	)
	Page.label(body, "Win stages 1-1 through 1-3 to unlock the lobby.")
end

function StoryView.render(
	page: Page.Page,
	data: Remote.Snapshot,
	play: (string) -> (),
	openTeam: () -> (),
	openSummon: () -> (),
	focusStage: string?
): TextButton
	local first: TextButton? = nil
	local progress = data.progression
	if not progress then
		Page.label(page.body, "Story progression is unavailable on this server.")
	elseif not progress.tutorialBattleCleared then
		first = Page.button(page.body, "Start tutorial", function()
			play("tutorial")
		end)
		StoryView.guide(page.body, data)
	else
		if not progress.tutorialDone then
			if data.currencies.SummonTickets > 0 then
				first = Page.button(page.body, "Summon with free tickets", openSummon)
			end
			StoryView.guide(page.body, data)
		end
		Page.label(
			page.body,
			string.format("Account Lv %d · %d board slots", progress.accountLevel, progress.maxBoardUnits)
		)
	end
	local team = Page.button(page.body, "Team Board", openTeam)
	local unlocked = progress ~= nil and progress.tutorialBattleCleared
	local latest: TextButton? = nil
	local preferred: TextButton? = nil
	for chapterIndex, chapter in Stages.chapters do
		local heading = Page.label(page.body, "Chapter " .. chapterIndex)
		heading.Font = Theme.bold
		local grid = Page.grid(page.body, 92, Theme.cardHeight)
		for index, stage in chapter do
			local stars = data.story.cleared[stage.id] or 0
			local button = Page.button(
				grid,
				string.format(
					"%s\n%s",
					stage.id,
					if unlocked then string.rep("★", stars) .. string.rep("☆", 3 - stars) else "Locked"
				),
				function()
					if not page.screen.Enabled then
						return
					end
					play(stage.id)
				end
			)
			button.LayoutOrder = index
			Controls.setEnabled(button, unlocked)
			if unlocked then
				latest = button
				if stage.id == focusStage then
					preferred = button
				end
			end
			unlocked = unlocked and stars > 0
		end
	end
	return first or preferred or latest or team
end

return table.freeze(StoryView)
