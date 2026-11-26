--!strict
-- Test pajangan lobby: unlock, kepemilikan unit, kepemilikan & kelayakan skin, kosongkan, unit hilang,
-- rekonsiliasi data basi, validasi argumen, dan skinsOwned tersanitasi di GetMyData.
local Server = game:GetService("ServerScriptService").Server
local TestRunner = require(Server.Dev.TestRunner)
local Services = Server.Services
local Meta = require(Services.DataService.Meta)
local Progress = require(Services.DataService.Progress)
local Replication = require(Services.DataService.Replication)
local Template = require(Services.DataService.Template)
local Handlers = require(Services.LobbyService.Handlers)
local Showcase = require(Services.LobbyService.Showcase)
local Shared = game:GetService("ReplicatedStorage").Shared
local Signal = require(Shared.Util.Signal)

local function unit(uid: string, unitId: string): any
	return {
		uid = uid,
		unitId = unitId,
		stars = 2,
		level = 1,
		xp = 0,
		locked = false,
		obtainedAt = 1,
		source = "admin",
	}
end

local function world()
	local sessions: { [any]: any } = {}
	local changed = {}
	local ledger = Meta.create(function(player: Player): any
		return sessions[player]
	end, Signal.new())
	local h = Handlers.create({
		ledger = ledger,
		onChanged = function(player)
			table.insert(changed, player)
		end,
	})
	local function join(unlocked: boolean): any
		local player = { UserId = 21 }
		local profile = Template.create(0)
		profile.units.u1 = unit("u1", "selene")
		profile.units.u2 = unit("u2", "kael")
		profile.skinsOwned.skin_s1_starfall = true
		profile.skinsOwned.skin_academy_scholar = true
		profile.flags.tutorialDone = unlocked
		Progress.reconcile(profile)
		sessions[player] = { Data = profile }
		return player
	end
	return { sessions = sessions, ledger = ledger, h = h, join = join, changed = changed }
end

return function(ctx: TestRunner.TestContext)
	local test, expect = ctx.test, ctx.expect

	test("locked until onboarding is done", function()
		local w = world()
		local player = w.join(false)
		local info = w.h.GetLobbyInfo(player)
		expect(info.ok).toBe(true)
		expect(info.data.unlocked).toBe(false)
		expect(info.data.showcaseUid).toBe(nil)
		expect(w.h.SetLobbyShowcase(player, "u1").code).toBe("LOBBY_LOCKED")
		expect(#w.changed).toBe(0)
	end)

	test("set, default skin, eligible skin, and clear", function()
		local w = world()
		local player = w.join(true)
		local result = w.h.SetLobbyShowcase(player, "u1")
		expect(result.ok).toBe(true)
		expect(result.data.showcaseUid).toBe("u1")
		expect(result.data.showcaseSkinId).toBe(nil)
		expect(w.h.SetLobbyShowcase(player, "u1", "skin_s1_starfall").data.showcaseSkinId).toBe("skin_s1_starfall")
		-- Skin universal untuk unit lain; skin khusus Selene tidak boleh di Kael.
		expect(w.h.SetLobbyShowcase(player, "u2", "skin_academy_scholar").ok).toBe(true)
		expect(w.h.SetLobbyShowcase(player, "u2", "skin_s1_starfall").code).toBe("SKIN_NOT_ELIGIBLE")
		expect(w.h.SetLobbyShowcase(player, "u2", "").data.showcaseSkinId).toBe(nil)
		local cleared = w.h.SetLobbyShowcase(player, "", "skin_academy_scholar")
		expect(cleared.ok).toBe(true)
		expect(cleared.data.showcaseUid).toBe(nil)
		expect(w.sessions[player].Data.lobby.showcaseUid).toBe("")
		expect(#w.changed).toBe(5)
	end)

	test("ownership and argument validation", function()
		local w = world()
		local player = w.join(true)
		expect(w.h.SetLobbyShowcase(player, "missing").code).toBe("UNIT_NOT_OWNED")
		expect(w.h.SetLobbyShowcase(player, 5).code).toBe("INVALID_UID")
		expect(w.h.SetLobbyShowcase(player, string.rep("x", 200)).code).toBe("INVALID_UID")
		expect(w.h.SetLobbyShowcase(player, "u1", 3).code).toBe("INVALID_SKIN")
		expect(w.h.SetLobbyShowcase(player, "u1", "skin_nope").code).toBe("INVALID_SKIN")
		expect(w.h.SetLobbyShowcase(player, "u1", "skin_s1_starfall", 1).code).toBe("INVALID_ARGUMENTS")
		expect(w.h.GetLobbyInfo(player, 1).code).toBe("INVALID_ARGUMENTS")
		w.sessions[player].Data.skinsOwned.skin_s1_starfall = nil
		expect(w.h.SetLobbyShowcase(player, "u1", "skin_s1_starfall").code).toBe("SKIN_NOT_OWNED")
		expect(w.h.GetLobbyInfo({ UserId = 1 } :: any).code).toBe("DATA_NOT_READY")
	end)

	test("unit or skin loss hides the showcase and reconcile clears stale data", function()
		local w = world()
		local player = w.join(true)
		expect(w.h.SetLobbyShowcase(player, "u1", "skin_s1_starfall").ok).toBe(true)
		local data = w.sessions[player].Data
		data.skinsOwned.skin_s1_starfall = nil
		local state = w.ledger.getShowcase(player)
		expect(state.uid).toBe("u1")
		expect(state.skinId).toBe(nil)
		expect(state.unitId).toBe("selene")
		expect(state.stars).toBe(2)
		data.units.u1 = nil -- mis. merge/dismantle lewat jalur lain
		expect(w.ledger.getShowcase(player).uid).toBe(nil)
		expect(w.h.GetLobbyInfo(player).data.showcaseUid).toBe(nil)
		Progress.reconcile(data)
		expect(data.lobby.showcaseUid).toBe("")
		expect(data.lobby.showcaseSkinId).toBe("")
	end)

	test("showcase key changes only when visible content changes", function()
		local base = { unitId = "kael", skinId = nil, stars = 1, vipAura = false, ownerUserId = 1 }
		expect(Showcase.key(nil)).toBe("")
		expect(Showcase.key(base)).toBe(Showcase.key(table.clone(base)))
		local upgraded = table.clone(base)
		upgraded.stars = 2
		expect(Showcase.key(base) ~= Showcase.key(upgraded)).toBe(true)
		local vip = table.clone(base)
		vip.vipAura = true
		expect(Showcase.key(base) ~= Showcase.key(vip)).toBe(true)
	end)

	test("GetMyData exposes only owned configured skins", function()
		local profile: any = Template.create(0)
		profile.skinsOwned = { skin_academy_scholar = true, skin_fake = true, skin_s1_starfall = false }
		Progress.reconcile(profile)
		local data = Replication.buildMyData(profile)
		expect(data.skinsOwned).toEqual({ skin_academy_scholar = true })
	end)
end
