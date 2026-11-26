--!strict
-- Membuat instance remote dari registry Shared/Net/Remotes dan memasang handler server.
-- Setiap RemoteFunction dibungkus: rate limit (Config/Constants.RATE_LIMITS) + tangkap error.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Constants = require(Shared.Config.Constants)
local Types = require(Shared.Types)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

export type FunctionHandler = (player: Player, ...any) -> Types.Result

local RemoteSetup = {}

local folder: Folder? = nil
local functions: { [string]: RemoteFunction } = {}
local events: { [string]: RemoteEvent } = {}
local bound: { [string]: boolean } = {}

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	elseif existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

-- Dipanggil sekali oleh bootstrap SEBELUM service init.
function RemoteSetup.init()
	assert(folder == nil, "RemoteSetup.init dipanggil dua kali")
	local root = getOrCreate(ReplicatedStorage, "Folder", Remotes.FOLDER_NAME) :: Folder
	for _, name in Remotes.Functions do
		assert(Constants.RATE_LIMITS[name], `RemoteFunction {name} belum punya RATE_LIMITS di Constants`)
		functions[name] = getOrCreate(root, "RemoteFunction", name) :: RemoteFunction
	end
	for _, name in Remotes.Events do
		events[name] = getOrCreate(root, "RemoteEvent", name) :: RemoteEvent
	end
	folder = root
end

local function failure(code: string): Types.Result
	return { ok = false, code = code }
end

-- Memasang handler C→S. Handler hanya dipanggil jika rate limit lolos.
function RemoteSetup.bindFunction(name: string, handler: FunctionHandler)
	local remote = functions[name]
	assert(remote, `RemoteFunction {name} tidak terdaftar di Shared/Net/Remotes`)
	assert(not bound[name], `RemoteFunction {name} sudah punya handler`)
	bound[name] = true
	local rule = Constants.RATE_LIMITS[name]

	remote.OnServerInvoke = function(player: Player, ...: any): Types.Result
		if not RateLimiter.allow(player, name, rule.max, rule.windowSec) then
			return failure("RATE_LIMITED")
		end
		-- xpcall: error handler tidak bocor ke client sebagai teks; error tetap di-log lengkap.
		local args = table.pack(...)
		local ok, result = xpcall(function()
			return handler(player, table.unpack(args, 1, args.n))
		end, debug.traceback)
		if not ok then
			warn(`[RemoteSetup] {name} error untuk {player.UserId}: {result}`)
			return failure("INTERNAL_ERROR")
		end
		if typeof(result) ~= "table" or typeof(result.ok) ~= "boolean" then
			warn(`[RemoteSetup] {name} mengembalikan Result tidak valid`)
			return failure("INTERNAL_ERROR")
		end
		return result
	end
end

function RemoteSetup.getEvent(name: string): RemoteEvent
	local remote = events[name]
	assert(remote, `RemoteEvent {name} tidak terdaftar di Shared/Net/Remotes`)
	return remote
end

return RemoteSetup
