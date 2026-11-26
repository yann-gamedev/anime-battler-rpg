--!strict
-- Spec progres story & inventory (prompts/06): bintang, idempotensi reward, validasi bulk, save lama.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Config.Progression)
local Stages = require(Shared.Config.Stages)
local BattleSim = require(Shared.BattleSim)
local ProgressionRules = require(Shared.ProgressionRules)
local TableUtil = require(Shared.Util.TableUtil)
local Validate = require(Server.Util.Validate)
local DataServiceModules = Server.Services.DataService
local Template = require(DataServiceModules.Template)
local Migrations = require(DataServiceModules.Migrations)
local StoryRules = require(DataServiceModules.StoryRules)
local InventoryRules = require(DataServiceModules.InventoryRules)

local DAY = Progression.SECONDS_PER_DAY
local NOW = 400 * DAY + 10

local function spawn(id: number, side: string, owner: number?, t: number?): any
	return {
		t = t or 0,
		kind = "spawn",
		unit = id,
		unitId = "kael",
		side = side,
		cell = 1,
		hp = 1,
		maxHp = 1,
		owner = owner,
	}
end

local function survivor(id: number, side: string): any
	return { id = id, unitId = "kael", side = side, cell = 1, hp = 1, maxHp = 1 }
end

local function addUnit(profile: any, uid: string, unitId: string, stars: number?): any
	local unit = {
		uid = uid,
		unitId = unitId,
		stars = stars or 1,
		level = 1,
		xp = 0,
		locked = false,
		obtainedAt = 1,
		source = "story",
	}
	profile.units[uid] = unit
	return unit
end

local function newProfile(): any
	local profile = Template.create(1) :: any
	StoryRules.reconcile(profile)
	return profile
end

return function(t: TestRunner.TestContext): ()
	t.test("counts stars from initial team A units only, ignoring summons", function()
		local log = { spawn(1, "A"), spawn(2, "A"), spawn(3, "A"), spawn(4, "B"), spawn(5, "A", 1, 40) }
		local all = { survivor(1, "A"), survivor(2, "A"), survivor(3, "A") }
		t.expect(ProgressionRules.countStars({ winner = "A", ticks = 1, log = log, survivors = all })).toBe(3)
		t.expect(ProgressionRules.countStars({ winner = "B", ticks = 1, log = log, survivors = all })).toBe(0)
		t.expect(ProgressionRules.countStars({ winner = "draw", ticks = 1, log = log, survivors = {} })).toBe(0)
		local twoLost = { survivor(1, "A"), survivor(5, "A") }
		t.expect(ProgressionRules.countStars({ winner = "A", ticks = 1, log = log, survivors = twoLost })).toBe(2)
		local fourLog = table.clone(log)
		table.insert(fourLog, spawn(6, "A"))
		local oneLeft = { survivor(6, "A"), survivor(5, "A") }
		t.expect(ProgressionRules.countStars({ winner = "A", ticks = 1, log = fourLog, survivors = oneLeft })).toBe(1)
	end)

	t.test("starters clear the tutorial and early chapter 1 placeholders", function()
		local team = {}
		for _, unitId in { "kael", "pip", "mira" } do
			table.insert(
				team,
				{ unitId = unitId, stars = 1, level = 1, cell = Progression.TUTORIAL_STARTER_CELLS[unitId] }
			)
		end
		for _, stageId in { "tutorial", "1-1", "1-2", "1-3" } do
			local stage = assert(ProgressionRules.stageDef(stageId))
			local enemies = {}
			for _, enemy in stage.enemies do
				table.insert(
					enemies,
					{ unitId = enemy.unitId, stars = enemy.stars, level = enemy.level, cell = enemy.slot }
				)
			end
			local result = BattleSim.run({ teamA = team, teamB = enemies, seed = 12345 })
			t.expect(ProgressionRules.countStars(result) >= 1).toBe(true)
		end
	end)

	t.test("unlocks stages sequentially after the tutorial", function()
		local cleared: { [string]: number } = {}
		t.expect(ProgressionRules.isStageUnlocked(cleared, false, "tutorial")).toBe(true)
		t.expect(ProgressionRules.isStageUnlocked(cleared, false, "1-1")).toBe(false)
		t.expect(ProgressionRules.isStageUnlocked(cleared, true, "1-1")).toBe(true)
		t.expect(ProgressionRules.isStageUnlocked(cleared, true, "1-2")).toBe(false)
		cleared["1-10"] = 1
		t.expect(ProgressionRules.isStageUnlocked(cleared, true, "2-1")).toBe(true)
		t.expect(ProgressionRules.isStageUnlocked(cleared, true, "4-1")).toBe(false)
		t.expect(ProgressionRules.isStageUnlocked(cleared, true, "studio_test_battle")).toBe(false)
		t.expect(#Stages.order).toBe(30)
		t.expect(ProgressionRules.maxBoardUnits({})).toBe(3)
		t.expect(ProgressionRules.maxBoardUnits({ ["1-5"] = 1, ["3-5"] = 2 })).toBe(6)
	end)

	t.test("grants tutorial tickets and first-clear 3-star Gems exactly once", function()
		local profile = newProfile()
		t.expect(StoryRules.applyStageResult(profile, "1-1", 3, NOW)).toBe("STAGE_LOCKED")
		local code, outcome = StoryRules.applyStageResult(profile, "tutorial", 3, NOW)
		t.expect(code).toBe(nil)
		t.expect((outcome :: any).rewards.SummonTickets).toBe(10)
		_, outcome = StoryRules.applyStageResult(profile, "tutorial", 3, NOW)
		t.expect((outcome :: any).rewards.SummonTickets).toBe(0)
		t.expect(profile.currencies.SummonTickets).toBe(10)
		t.expect(profile.story.cleared.tutorial).toBe(nil)

		_, outcome = StoryRules.applyStageResult(profile, "1-1", 2, NOW)
		t.expect((outcome :: any).rewards.Gems).toBe(0)
		t.expect((outcome :: any).rewards.Gold).toBe(ProgressionRules.stageGold(1))
		_, outcome = StoryRules.applyStageResult(profile, "1-1", 3, NOW)
		t.expect((outcome :: any).firstThreeStar).toBe(true)
		t.expect((outcome :: any).rewards.Gems).toBe(Economy.firstThreeStarGems)
		for _ = 1, 3 do
			_, outcome = StoryRules.applyStageResult(profile, "1-1", 3, NOW)
			t.expect((outcome :: any).firstThreeStar).toBe(false)
			t.expect((outcome :: any).rewards.Gems).toBe(0)
		end
		t.expect(profile.currencies.Gems).toBe(30)
		t.expect(profile.story.cleared["1-1"]).toBe(3)
		_, outcome = StoryRules.applyStageResult(profile, "1-1", 1, NOW)
		t.expect(profile.story.cleared["1-1"]).toBe(3)
		t.expect(profile.accountLevel).toBe(2)
	end)

	t.test("ignores losses, finishes onboarding on 1-3 and levels the account per distinct stage", function()
		local profile = newProfile()
		StoryRules.applyStageResult(profile, "tutorial", 3, NOW)
		local _, outcome = StoryRules.applyStageResult(profile, "1-1", 0, NOW)
		t.expect((outcome :: any).rewards).toEqual({ Gold = 0, Gems = 0, XPScrolls = 0, SummonTickets = 0 })
		t.expect(profile.story.cleared["1-1"]).toBe(nil)
		t.expect(profile.stats.battles).toBe(2)
		for _, stageId in { "1-1", "1-2", "1-3" } do
			t.expect(StoryRules.applyStageResult(profile, stageId, 1, NOW)).toBe(nil)
		end
		t.expect(profile.flags.tutorialDone).toBe(true)
		t.expect(profile.accountLevel).toBe(4)
		t.expect(profile.materials.XPScrolls).toBe(3 * ProgressionRules.stageXpScrolls(1))
	end)

	t.test("halves replay Gold after 30 replays per UTC day and resets on a new day", function()
		local profile = newProfile()
		StoryRules.applyStageResult(profile, "tutorial", 3, NOW)
		StoryRules.applyStageResult(profile, "1-1", 3, NOW)
		local full = ProgressionRules.stageGold(1)
		local outcome
		for _ = 1, Economy.replayGoldSoftCap.replaysPerDay do
			_, outcome = StoryRules.applyStageResult(profile, "1-1", 3, NOW)
			t.expect((outcome :: any).rewards.Gold).toBe(full)
		end
		_, outcome = StoryRules.applyStageResult(profile, "1-1", 3, NOW)
		t.expect((outcome :: any).rewards.Gold).toBe(math.floor(full * Economy.replayGoldSoftCap.goldMultiplier))
		_, outcome = StoryRules.applyStageResult(profile, "1-1", 3, NOW + DAY)
		t.expect((outcome :: any).rewards.Gold).toBe(full)
		t.expect(profile.progress.replayCount).toBe(1)
	end)

	t.test("validates bulk UID arrays by shape, count and length", function()
		t.expect(Validate.isStringArray({ "a", "b" }, 1, 4, 64)).toBe(true)
		t.expect(Validate.isStringArray({}, 1, 4, 64)).toBe(false)
		t.expect(Validate.isStringArray({ "a", "b", "c", "d", "e" }, 1, 4, 64)).toBe(false)
		t.expect(Validate.isStringArray({ "a", "" }, 1, 4, 64)).toBe(false)
		t.expect(Validate.isStringArray({ string.rep("x", 65) }, 1, 4, 64)).toBe(false)
		t.expect(Validate.isStringArray({ "a", 1 } :: any, 1, 4, 64)).toBe(false)
		t.expect(Validate.isStringArray({ [1] = "a", [3] = "b" }, 1, 4, 64)).toBe(false)
		local withExtraKey: { [any]: string } = { "a" }
		withExtraKey.extra = "b"
		t.expect(Validate.isStringArray(withExtraKey, 1, 4, 64)).toBe(false)
		t.expect(Validate.isStringArray(setmetatable({ "a" }, {}), 1, 4, 64)).toBe(false)
		t.expect(Validate.isStringArray("a", 1, 4, 64)).toBe(false)
	end)

	t.test("rejects invalid dismantles without touching any unit or currency", function()
		local profile = newProfile()
		addUnit(profile, "free", "kael")
		addUnit(profile, "locked", "pip").locked = true
		addUnit(profile, "team", "mira")
		addUnit(profile, "mythic", "seraphine")
		profile.teams[1].slots[1] = "team"
		t.expect(InventoryRules.dismantle(profile, { "free" })).toBe("TUTORIAL_NOT_DONE")
		profile.progress.tutorialBattleCleared = true
		local before = TableUtil.deepCopy(profile)
		for uids, code in
			{
				[{ "free", "free" }] = "DUPLICATE_UNIT",
				[{ "free", "locked" }] = "UNIT_LOCKED",
				[{ "free", "team" }] = "UNIT_IN_TEAM",
				[{ "free", "mythic" }] = "UNIT_NOT_DISMANTLABLE",
				[{ "free", "missing" }] = "UNIT_NOT_OWNED",
				[{}] = "INVALID_UNITS",
			}
		do
			t.expect(InventoryRules.dismantle(profile, uids)).toBe(code)
			t.expect(profile).toEqual(before)
		end
		t.expect(InventoryRules.dismantle(profile, { "free" })).toBe(nil)
		t.expect(profile.units.free).toBe(nil)
		t.expect(profile.currencies.Gold).toBe(Economy.dismantleRewards.Rare.Gold)
	end)

	t.test("merges only free same-unit materials matching the star cost", function()
		local profile = newProfile()
		addUnit(profile, "target", "kael")
		addUnit(profile, "dup1", "kael")
		addUnit(profile, "dup2", "kael")
		addUnit(profile, "other", "pip")
		local before = TableUtil.deepCopy(profile)
		t.expect(InventoryRules.merge(profile, "target", { "dup1" })).toBe("NOT_ENOUGH_GOLD")
		profile.currencies.Gold = Progression.MERGE_GOLD[1] + Progression.MERGE_GOLD[2]
		before = TableUtil.deepCopy(profile)
		t.expect(InventoryRules.merge(profile, "target", { "dup1", "dup2" })).toBe("WRONG_MATERIAL_COUNT")
		t.expect(InventoryRules.merge(profile, "target", { "other" })).toBe("UNIT_MISMATCH")
		t.expect(InventoryRules.merge(profile, "target", { "target" })).toBe("DUPLICATE_UNIT")
		profile.units.dup1.locked = true
		t.expect(InventoryRules.merge(profile, "target", { "dup1" })).toBe("UNIT_LOCKED")
		profile.units.dup1.locked = false
		profile.teams[1].slots[4] = "target"
		t.expect(InventoryRules.merge(profile, "target", { "dup1" })).toBe("UNIT_IN_TEAM")
		profile.teams[1].slots[4] = ""
		t.expect(profile).toEqual(before)
		t.expect(InventoryRules.merge(profile, "target", { "dup1" })).toBe(nil)
		t.expect(profile.units.target.stars).toBe(2)
		t.expect(profile.units.dup1).toBe(nil)
		t.expect(profile.currencies.Gold).toBe(Progression.MERGE_GOLD[2])
		t.expect(InventoryRules.merge(profile, "target", { "dup2" })).toBe("WRONG_MATERIAL_COUNT")
	end)

	t.test("levels up with Economy.levelCost Gold plus XP Scroll materials", function()
		local profile = newProfile()
		addUnit(profile, "u", "kael")
		local gold, scrolls = ProgressionRules.levelUpCost(1, 3)
		t.expect(gold).toBe(Economy.levelCost(1) + Economy.levelCost(2) + Economy.levelCost(3))
		profile.currencies.Gold = gold
		t.expect(InventoryRules.levelUp(profile, "u", 3)).toBe("NOT_ENOUGH_XP_SCROLLS")
		profile.materials.XPScrolls = scrolls
		profile.units.u.level = 5
		t.expect(InventoryRules.levelUp(profile, "u", 56)).toBe("LEVEL_EXCEEDS_MAX")
		profile.units.u.level = 60
		t.expect(InventoryRules.levelUp(profile, "u", 1)).toBe("LEVEL_MAX")
		profile.units.u.level = 1
		t.expect(InventoryRules.levelUp(profile, "u", 60)).toBe("INVALID_LEVELS")
		t.expect(InventoryRules.levelUp(profile, "u", 0)).toBe("INVALID_LEVELS")
		t.expect(InventoryRules.levelUp(profile, "u", 3)).toBe(nil)
		t.expect(profile.units.u.level).toBe(4)
		t.expect(profile.currencies.Gold).toBe(0)
		t.expect(profile.materials.XPScrolls).toBe(0)
	end)

	t.test("reconciles old v1 saves additively without double first-clear Gems", function()
		local old = Template.create(1) :: any
		old.materials = nil
		old.progress = nil
		old.flags.tutorialDone = true
		old.story.cleared["1-1"] = 3
		old.currencies.Gems = 30
		Migrations.run(old)
		StoryRules.reconcile(old)
		t.expect(old.version).toBe(1)
		t.expect(old.materials.XPScrolls).toBe(0)
		t.expect(old.progress.tutorialBattleCleared).toBe(true)
		t.expect(old.progress.firstThreeStarClaimed["1-1"]).toBe(true)
		local _, outcome = StoryRules.applyStageResult(old, "1-1", 3, NOW)
		t.expect((outcome :: any).rewards.Gems).toBe(0)
		t.expect((outcome :: any).rewards.SummonTickets).toBe(0)
		t.expect(old.currencies.Gems).toBe(30)

		local fresh = Template.create(1) :: any
		fresh.progress.replayCount = -5
		fresh.materials.XPScrolls = 0 / 0
		StoryRules.reconcile(fresh)
		t.expect(fresh.progress.replayCount).toBe(0)
		t.expect(fresh.materials.XPScrolls).toBe(0)
		t.expect(fresh.progress.tutorialBattleCleared).toBe(false)
	end)
end
