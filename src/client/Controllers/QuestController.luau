--!strict
local UI = script.Parent.Parent.UI
local LobbyPage = require(UI.LobbyPage)
local Page = require(UI.ProgressPage)
local Remote = require(UI.LobbyRemote)

local QuestController = {}

function QuestController.open(onBack: () -> ()): ()
	local page = LobbyPage.create("Quests", onBack)
	local snapshot: Remote.Quests?
	local serverOffset = 0
	local busy = false
	local load: (Remote.Quest?) -> ()
	local rolloverAt: number?
	local daily: TextLabel?
	local weekly: TextLabel?

	local function now(): number
		return time() + serverOffset
	end

	local function render(): ()
		local scroll = page.body.CanvasPosition
		Page.clear(page)
		local data = snapshot
		if data then
			local currentTime = now()
			rolloverAt = nil
			for _, period in { "Daily", "Weekly" } do
				local isDaily = period == "Daily"
				local reset = if isDaily then data.dailyResetAt else data.weeklyResetAt
				local heading = Page.label(page.body, period .. " quests")
				heading.Font = Enum.Font.GothamBold
				local countdown = Page.label(page.body, "")
				if isDaily then
					daily = countdown
				else
					weekly = countdown
				end
				if currentTime < reset then
					rolloverAt = math.min(rolloverAt or reset, reset)
				end
				for _, quest in data.quests do
					if quest.period ~= period then
						continue
					end
					Page.label(page.body, quest.title .. "  ·  " .. quest.description)
					Page.label(
						page.body,
						string.format("%d / %d  ·  %s", quest.progress, quest.target, Remote.rewards(quest.rewards))
					)
					if currentTime >= reset then
						Page.label(page.body, "Period ended. Refresh for new quests.")
					elseif quest.claimed then
						Page.label(page.body, "Claimed")
					elseif quest.progress >= quest.target then
						Page.button(page.body, "Claim " .. quest.title, function()
							if not busy and now() < reset then
								load(quest)
							end
						end)
					else
						Page.label(page.body, "In progress")
					end
				end
			end
		end
		Page.button(page.body, "Refresh quests", function()
			load(nil)
		end)
		LobbyPage.focus(page)
		page.body.CanvasPosition = scroll
	end

	load = function(quest: Remote.Quest?)
		if busy or not page.screen.Enabled then
			return
		end
		busy = true
		page.message.Text = if quest then "Claiming reward…" else "Loading quests…"
		local requestAt = time()
		local reply, failure
		if quest then
			reply, failure = Remote.quests(quest)
		else
			reply, failure = Remote.quests(nil)
		end
		if quest and not reply and page.screen.Enabled then
			requestAt = time()
			reply = Remote.quests(nil)
		end
		if not page.screen.Enabled then
			return
		end
		busy = false
		snapshot = reply
		if snapshot then
			serverOffset = snapshot.serverTime - (requestAt + time()) / 2
		end
		page.message.Text = failure or (if quest then "Reward claimed." else "")
		render()
	end

	task.spawn(load, nil)
	task.spawn(function()
		while page.screen.Parent do
			local data = snapshot
			local stamp = now()
			if data then
				if daily then
					daily.Text = "Daily reset in " .. Remote.countdown(data.dailyResetAt, stamp)
				end
				if weekly then
					weekly.Text = "Weekly reset in " .. Remote.countdown(data.weeklyResetAt, stamp)
				end
				if rolloverAt and stamp >= rolloverAt and not busy then
					rolloverAt = nil
					task.spawn(load, nil)
				end
			end
			task.wait(1)
		end
	end)
end

return table.freeze(QuestController)
