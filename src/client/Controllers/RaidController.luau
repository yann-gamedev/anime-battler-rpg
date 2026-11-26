--!strict
local UI = script.Parent.Parent.UI
local LobbyPage = require(UI.LobbyPage)
local Page = require(UI.ProgressPage)
local ProgressRemote = require(UI.ProgressRemote)
local Remote = require(UI.LobbyRemote)
local TeamBoardController = require(script.Parent.TeamBoardController)
local BattleViewController = require(script.Parent.BattleViewController)

local RaidController = {}

function RaidController.open(onBack: () -> (), openTeam: (() -> ())?): ()
	local starting = false
	local page = LobbyPage.create("Boss Raid", onBack, function()
		return not starting
	end)
	local snapshot: Remote.Raid?
	local teams: ProgressRemote.Snapshot?
	local outcome: Remote.RaidResult?
	local serverOffset = 0
	local busy = false
	local load: () -> ()
	local attempt: (number) -> ()
	local watchReset = false
	local countdown: TextLabel?

	local function updateSnapshot(data: Remote.Raid?, requestAt: number): ()
		snapshot = data
		if data then
			serverOffset = data.serverTime - (requestAt + time()) / 2
		end
	end

	local function now(): number
		return time() + serverOffset
	end

	local function render(): ()
		Page.clear(page)
		local preferred: TextButton?
		if outcome then
			Page.label(page.body, string.format("%s · %d damage dealt", outcome.raid.bossName, outcome.damage))
			Page.label(page.body, "Rewards earned: " .. Remote.rewards(outcome.rewards))
		end
		local raid = snapshot
		if raid then
			local current = now() < raid.resetAt
			watchReset = current
			Page.label(page.body, string.format("%s  ·  %d HP", raid.bossName, raid.bossMaxHp))
			countdown = Page.label(page.body, "")
			Page.label(page.body, string.format("Best damage today: %d", raid.bestDamage))
			if not raid.unlocked then
				Page.label(page.body, "Clear Story 1-3 to unlock Boss Raid.")
			elseif not current then
				Page.label(page.body, "Raid ended. Refresh for today's boss.")
			elseif raid.attempted then
				Page.label(page.body, "Today's attempt has been used.")
			else
				Page.label(page.body, "One free attempt today. Choose a saved team to start.")
				local roster = teams
				if roster then
					for index, team in roster.teams do
						local deployed = 0
						for _, uid in team.slots do
							if uid ~= "" then
								deployed += 1
							end
						end
						if deployed > 0 then
							local button = Page.button(
								page.body,
								string.format("Start with %s (%d)", team.name, deployed),
								function()
									if now() < raid.resetAt then
										attempt(index)
									end
								end
							)
							if index == TeamBoardController.selectedIndex() then
								preferred = button
							end
						end
					end
				end
				if openTeam then
					Page.button(page.body, "Edit saved teams", function()
						if not busy then
							openTeam()
							page.screen:Destroy()
						end
					end)
				end
			end
			Page.label(page.body, "Damage reward tiers")
			for _, tier in raid.rewardTiers do
				Page.label(page.body, string.format("%d+ damage  ·  %s", tier.minDamage, Remote.rewards(tier.rewards)))
			end
		end
		Page.button(page.body, "Refresh raid", load)
		LobbyPage.focus(page, preferred)
	end

	load = function()
		if busy or not page.screen.Enabled then
			return
		end
		busy = true
		page.message.Text = "Loading today's raid…"
		local requestAt = time()
		local reply, failure = Remote.raid()
		if not page.screen.Enabled then
			return
		end
		updateSnapshot(reply, requestAt)
		if reply and reply.unlocked and not reply.attempted then
			teams = ProgressRemote.snapshot("GetMyData")
		end
		if not page.screen.Enabled then
			return
		end
		busy = false
		page.message.Text = failure or ""
		render()
	end

	attempt = function(teamIndex: number)
		if busy or not page.screen.Enabled then
			return
		end
		busy = true
		starting = true
		page.message.Text = "Starting raid…"
		task.delay(12, function()
			if starting and page.screen.Enabled then
				starting = false
				page.message.Text = "Still waiting. You can go Back and reopen Raid to check the attempt."
			end
		end)
		local requestAt = time()
		local reply, failure = Remote.startRaid(teamIndex)
		starting = false
		if not reply then
			if not page.screen.Enabled then
				return
			end
			requestAt = time()
			local recovered = Remote.raid()
			updateSnapshot(recovered, requestAt)
			if page.screen.Enabled then
				busy = false
				page.message.Text = failure or "Unable to start. Check your attempt status."
				render()
			end
			return
		end

		local result = reply
		local function showResult(): ()
			if not page.screen.Enabled then
				return
			end
			busy = false
			page.message.Text = ""
			outcome = result
			render()
			page.body.CanvasPosition = Vector2.zero
		end
		if page.screen.Enabled then
			updateSnapshot(result.raid, requestAt)
			BattleViewController.playReplay(result.replay, showResult, result.raid.bossName)
		end
	end

	task.spawn(load)
	task.spawn(function()
		while page.screen.Parent do
			local raid = snapshot
			if raid and countdown then
				countdown.Text = "Resets in " .. Remote.countdown(raid.resetAt, now())
				if watchReset and not busy and now() >= raid.resetAt then
					watchReset = false
					task.spawn(load)
				end
			end
			task.wait(1)
		end
	end)
end

return table.freeze(RaidController)
