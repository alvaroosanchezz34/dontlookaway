--[[
	Trove
	Tracks connections, instances, threads and cleanup callbacks so systems can be
	torn down without leaking. Every temporary object in the game goes through one.
]]

local Trove = {}
Trove.__index = Trove

function Trove.new()
	return setmetatable({ _items = {} }, Trove)
end

function Trove:Add(item)
	table.insert(self._items, item)
	return item
end

function Trove:Connect(signal, fn)
	return self:Add(signal:Connect(fn))
end

function Trove:Clone(instance)
	return self:Add(instance:Clone())
end

function Trove:Spawn(fn, ...)
	return self:Add(task.spawn(fn, ...))
end

function Trove:Delay(seconds, fn, ...)
	return self:Add(task.delay(seconds, fn, ...))
end

local function cleanItem(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		local ok, err = pcall(item)
		if not ok then
			warn("[Trove] cleanup error:", err)
		end
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" and item ~= coroutine.running() then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Clean) == "function" then
			item:Clean()
		end
	end
end

function Trove:Remove(item)
	local index = table.find(self._items, item)
	if index then
		table.remove(self._items, index)
		cleanItem(item)
	end
end

function Trove:Clean()
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		cleanItem(items[i])
	end
end

Trove.Destroy = Trove.Clean

return Trove
