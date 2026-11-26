--!strict
local UI = script.Parent.Parent.UI
local Modal = require(UI.Components.Modal)
local Remote = require(UI.ProgressRemote)
local SummonController = require(script.Parent.SummonController)
local UIController = require(script.Parent.UIController)

local StoryFlow = {}
local NEXT_ROUND_SECONDS = 5

function StoryFlow.show(
	parent: PlayerGui,
	result: Remote.StageResult,
	lobbyUnlocked: boolean,
	onContinue: (boolean) -> (),
	nextRound: (() -> ())?
): ()
	local rows = { string.rep("★", result.stars) .. string.rep("☆", 3 - result.stars) }
	if result.firstThreeStar then
		table.insert(rows, "First three-star clear")
	end
	local amounts = result.rewards
	table.insert(
		rows,
		string.format(
			"Gold +%d   Gems +%d\nXP Scrolls +%d   Summon Tickets +%d",
			amounts.Gold,
			amounts.Gems,
			amounts.XPScrolls,
			amounts.SummonTickets
		)
	)
	local earnedTickets = result.stageId == "tutorial" and amounts.SummonTickets > 0
	if earnedTickets then
		table.insert(rows, "Use your free tickets on a summon banner.")
	elseif lobbyUnlocked then
		table.insert(rows, "The lobby is now open.")
	end
	if nextRound then
		table.insert(rows, string.format("Auto-replay starts the next round in %d seconds.", NEXT_ROUND_SECONDS))
	end

	local modal: Modal.View
	local restore: () -> ()
	local closed = false
	local visitedSummon = false
	local function close(): boolean
		if closed or not modal.screen.Enabled then
			return false
		end
		closed = true
		restore()
		modal.screen:Destroy()
		return true
	end
	local title = (if result.stageId == "tutorial" then "Tutorial" else "Stage " .. result.stageId)
		.. (if result.stars > 0 then " victory" elseif result.replay.winner == "draw" then " draw" else " defeat")
	local choices: { Modal.Choice } = if earnedTickets then { { label = "Open Summon", value = "summon" } } else {}
	modal = Modal.create(parent, title, choices, if earnedTickets then "summon" else nil, function()
		visitedSummon = true
		SummonController.open(function()
			UIController.show(modal.screen, modal.first)
		end)
	end, function()
		if close() then
			onContinue(visitedSummon)
		end
	end, {
		body = rows,
		closeText = if nextRound then "Stop auto-replay" else "Continue",
	})
	restore = UIController.overlay(modal.screen, modal.first)
	if nextRound then
		task.delay(NEXT_ROUND_SECONDS, function()
			if close() then
				nextRound()
			end
		end)
	end
end

function StoryFlow.chooseMode(parent: PlayerGui, stageId: string, teamIndex: number, start: (boolean) -> ()): ()
	local modal: Modal.View
	local restore: () -> ()
	local function close()
		restore()
		modal.screen:Destroy()
	end
	modal = Modal.create(
		parent,
		"Stage " .. stageId,
		{
			{ label = "Play once", value = "once" },
			{ label = "Start auto-replay", value = "auto" },
		},
		"once",
		function(choice)
			close()
			start(choice == "auto")
		end,
		close,
		{
			body = {
				"Using saved preset "
					.. teamIndex
					.. ". Stop auto-replay from the result screen or exit the battle view.",
			},
			closeText = "Cancel",
		}
	)
	restore = UIController.overlay(modal.screen, modal.first)
end

return table.freeze(StoryFlow)
