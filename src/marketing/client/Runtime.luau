--[[
	Runtime
	Everything a scene creates or changes goes through here, so that
	CleanupMarketingScene() can always put the game back exactly as it was:

	  * Runtime.folder()      Workspace.MarketingRuntime (local, never replicated)
	  * Runtime.gui()         PlayerGui.MarketingRuntimeGui (safe frame, text, fades)
	  * Runtime.track(inst)   anything parented elsewhere (post effects, sounds)
	  * Runtime.setProp(...)  changes a property of an existing instance and
	                          remembers the original. On cleanup it is restored
	                          only if nobody else changed it meanwhile (the game
	                          keeps running underneath a scene).
	  * Runtime.onCleanup(fn) custom restore steps (run last-in, first-out)
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Runtime = {}

type Saved = { inst: Instance, prop: string, original: any, set: any }

local saved: { [string]: Saved } = {}
local savedOrder: { string } = {}
local tracked: { Instance } = {}
local cleanups: { () -> () } = {}
local keys: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local nextKey = 0

local function keyOf(inst: Instance): string
	local k = keys[inst]
	if not k then
		nextKey += 1
		k = tostring(nextKey)
		keys[inst] = k
	end
	return k
end

function Runtime.folder(): Folder
	local f = Workspace:FindFirstChild("MarketingRuntime")
	if not f then
		f = Instance.new("Folder")
		f.Name = "MarketingRuntime"
		f.Parent = Workspace
	end
	return f :: Folder
end

function Runtime.gui(): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = playerGui:FindFirstChild("MarketingRuntimeGui")
	if not g then
		g = Instance.new("ScreenGui")
		g.Name = "MarketingRuntimeGui"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 950
		g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		g.Parent = playerGui
	end
	return g :: ScreenGui
end

function Runtime.track<T>(inst: T): T
	table.insert(tracked, inst :: any)
	return inst
end

-- Change `inst[prop]`; the first change remembers the original value.
function Runtime.setProp(inst: Instance, prop: string, value: any)
	local key = keyOf(inst) .. "." .. prop
	local entry = saved[key]
	if not entry then
		local ok, original = pcall(function()
			return (inst :: any)[prop]
		end)
		if not ok then
			return
		end
		entry = { inst = inst, prop = prop, original = original, set = nil }
		saved[key] = entry
		table.insert(savedOrder, key)
	end
	local ok = pcall(function()
		(inst :: any)[prop] = value
	end)
	if ok then
		entry.set = (inst :: any)[prop]
	end
end

function Runtime.original(inst: Instance, prop: string): any
	local entry = saved[keyOf(inst) .. "." .. prop]
	if entry then
		return entry.original
	end
	return (inst :: any)[prop]
end

function Runtime.onCleanup(fn: () -> ())
	table.insert(cleanups, fn)
end

function Runtime.isClean(): boolean
	local f = Workspace:FindFirstChild("MarketingRuntime")
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local g = playerGui and playerGui:FindFirstChild("MarketingRuntimeGui")
	return (f == nil or #f:GetChildren() == 0) and g == nil and #tracked == 0 and #savedOrder == 0 and #cleanups == 0
end

-- Undo everything. Safe to call any number of times.
function Runtime.cleanup()
	for i = #cleanups, 1, -1 do
		local fn = cleanups[i]
		cleanups[i] = nil
		local ok, err = pcall(fn)
		if not ok then
			warn("[Marketing] cleanup step failed:", err)
		end
	end
	for i = #savedOrder, 1, -1 do
		local entry = saved[savedOrder[i]]
		if entry and entry.inst.Parent ~= nil then
			pcall(function()
				-- only undo our own change; if the game changed it since, it wins
				if (entry.inst :: any)[entry.prop] == entry.set then
					(entry.inst :: any)[entry.prop] = entry.original
				end
			end)
		end
	end
	table.clear(saved)
	table.clear(savedOrder)
	for i = #tracked, 1, -1 do
		local inst = tracked[i]
		pcall(function()
			inst:Destroy()
		end)
	end
	table.clear(tracked)
	local f = Workspace:FindFirstChild("MarketingRuntime")
	if f then
		f:Destroy()
	end
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local g = playerGui and playerGui:FindFirstChild("MarketingRuntimeGui")
	if g then
		g:Destroy()
	end
end

return Runtime
