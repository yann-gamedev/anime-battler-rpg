--!strict
-- Signal sederhana tanpa dependency. Handler dijalankan dengan task.spawn.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Listener = { fn: (...any) -> (), connection: Connection }

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { Listener } = {}
	local self = {} :: any

	function self.Connect(_: any, fn: (...any) -> ()): Connection
		local listener: Listener
		local connection = {} :: any
		connection.Connected = true
		function connection.Disconnect(conn: any)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			local index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end
		listener = { fn = fn, connection = connection }
		table.insert(listeners, listener)
		return connection
	end

	function self.Fire(_: any, ...: any)
		-- Salin dulu agar Disconnect di dalam handler aman.
		for _, listener in table.clone(listeners) do
			if listener.connection.Connected then
				task.spawn(listener.fn, ...)
			end
		end
	end

	function self.DisconnectAll(_: any)
		for _, listener in listeners do
			listener.connection.Connected = false
		end
		table.clear(listeners)
	end

	return self :: Signal<T...>
end

return Signal
