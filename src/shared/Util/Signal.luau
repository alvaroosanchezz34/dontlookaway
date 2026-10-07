--[[
	Signal
	Lightweight synchronous signal used for in-process events between modules.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local connection
	connection = {
		Connected = true,
		Disconnect = function(self)
			if not self.Connected then
				return
			end
			self.Connected = false
			local handlers = connection._signal._handlers
			local index = table.find(handlers, connection)
			if index then
				table.remove(handlers, index)
			end
		end,
		_fn = fn,
		_signal = self,
	}
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	-- Copy so handlers can disconnect while firing.
	local handlers = table.clone(self._handlers)
	for _, connection in handlers do
		if connection.Connected then
			local ok, err = pcall(connection._fn, ...)
			if not ok then
				warn("[Signal] handler error:", err)
			end
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._handlers) do
		connection:Disconnect()
	end
end

return Signal
