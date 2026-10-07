--[[
	Shared Lune test environment: loads a built place, polyfills the engine
	features the game relies on (Position from CFrame, pivots, bounding boxes,
	world attachments, Random, wall-clock os.clock, ...) and executes the game's
	ModuleScripts with Roblox-style require().
]]

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local placePath = process.args[1] or "build/test.rbxlx"
local game = roblox.deserializePlace(fs.readFile(placePath))
local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

------------------------------------------------------------------------------------
-- Engine polyfills
------------------------------------------------------------------------------------

-- BasePart.Position derives from CFrame in the engine
for _, className in { "BasePart", "Part", "WedgePart", "MeshPart", "TrussPart", "CornerWedgePart" } do
	roblox.implementProperty(className, "Position", function(self)
		return self.CFrame.Position
	end, function(self, value)
		self.CFrame = CFrame.new(value) * (self.CFrame - self.CFrame.Position)
	end)
end

local function boundingParts(model)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

roblox.implementMethod("Model", "GetPivot", function(self)
	local primary = self.PrimaryPart
	if primary then
		return primary.CFrame
	end
	return self.WorldPivot
end)

roblox.implementMethod("Model", "PivotTo", function(self, target)
	local current = self:GetPivot()
	local delta = target * current:Inverse()
	for _, p in boundingParts(self) do
		p.CFrame = delta * p.CFrame
	end
	if not self.PrimaryPart then
		self.WorldPivot = target
	end
end)

roblox.implementMethod("Model", "GetBoundingBox", function(self)
	local parts = boundingParts(self)
	if #parts == 0 then
		return self.WorldPivot, Vector3.zero
	end
	local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in parts do
		local half = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = p.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					minV = minV:Min(w)
					maxV = maxV:Max(w)
				end
			end
		end
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end)

roblox.implementMethod("Instance", "FindFirstAncestorWhichIsA", function(self, className)
	local p = self.Parent
	while p do
		if p:IsA(className) then
			return p
		end
		p = p.Parent
	end
	return nil
end)

roblox.implementProperty("Attachment", "WorldCFrame", function(self)
	local parent = self.Parent
	if parent and parent:IsA("BasePart") then
		return parent.CFrame * self.CFrame
	end
	return self.CFrame
end, function(self, value)
	local parent = self.Parent
	if parent and parent:IsA("BasePart") then
		self.CFrame = parent.CFrame:Inverse() * value
	else
		self.CFrame = value
	end
end)

roblox.implementProperty("Attachment", "WorldPosition", function(self)
	return self.WorldCFrame.Position
end, function(self, value)
	self.WorldCFrame = CFrame.new(value)
end)

roblox.implementMethod("RunService", "IsServer", function()
	return true
end)
roblox.implementMethod("RunService", "IsClient", function()
	return false
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return true
end)

-- Lune does not derive Position from CFrame; store it explicitly before reads
local function syncPositions(root)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Position = d.CFrame.Position
		end
	end
end

roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("Players", "GetPlayers", function()
	return {}
end)
-- no physics in Lune: by default every ray reaches its end on a "floor"
local raycastStub = function(origin, direction)
	return { Position = origin + direction, Normal = Vector3.new(0, 1, 0), Instance = nil, Distance = direction.Magnitude }
end
roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction)
	return raycastStub(origin, direction)
end)
roblox.implementMethod("HttpService", "GenerateGUID", function()
	return tostring(math.random(1, 2 ^ 30)) .. "-" .. tostring(os.clock())
end)
roblox.implementMethod("RemoteEvent", "FireClient", function() end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function() end)
roblox.implementProperty("RemoteEvent", "OnServerEvent", function()
	return { Connect = function() end }
end)

-- engine-only Humanoid behaviour
roblox.implementMethod("Humanoid", "SetStateEnabled", function() end)
roblox.implementMethod("Humanoid", "MoveTo", function() end)
roblox.implementMethod("Humanoid", "Move", function() end)

-- Random (deterministic xorshift, same API surface the game uses)
local Random = {}
Random.__index = Random
function Random.new(seed)
	local s = math.floor((seed or os.clock() * 1e6) % 2147483647)
	if s == 0 then
		s = 1234567
	end
	return setmetatable({ s = s }, Random)
end
function Random:_next()
	local x = self.s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.s = x
	return x / 4294967296
end
function Random:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * self:_next()
end
function Random:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end

local TweenInfo = { new = function(...)
	return { ... }
end }

local function makeSignal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end, Connected = true }
		end,
		Once = function(_, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end }
		end,
		Wait = function() end,
		Fire = function(_, ...)
			for _, h in handlers do
				h(...)
			end
		end,
	}
end

local tagged = {}
local function scanTags(tag)
	local list = {}
	for _, d in game:GetDescendants() do
		if d:HasTag(tag) then
			table.insert(list, d)
		end
	end
	return list
end

local CollectionServiceStub = {
	GetTagged = function(_, tag)
		return scanTags(tag)
	end,
	GetInstanceAddedSignal = function()
		return makeSignal()
	end,
	GetInstanceRemovedSignal = function()
		return makeSignal()
	end,
}

local services = {}
local function getService(_, name)
	if name == "CollectionService" then
		return CollectionServiceStub
	end
	if services[name] then
		return services[name]
	end
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	if ok and s then
		return s
	end
	-- engine services that do not exist in Lune
	local stub = setmetatable({ Name = name }, {
		__index = function(t, k)
			if k == "Heartbeat" or k == "Stepped" or k == "RenderStepped" or k == "PlayerAdded" or k == "PlayerRemoving" then
				local sig = makeSignal()
				rawset(t, k, sig)
				return sig
			end
			return function()
				return nil
			end
		end,
	})
	services[name] = stub
	return stub
end

local workspace = game:GetService("Workspace")
local gameProxy = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then
			return getService
		end
		if k == "Workspace" then
			return workspace
		end
		return (game :: any)[k]
	end,
})

------------------------------------------------------------------------------------
-- Module loader
------------------------------------------------------------------------------------

local cache = {}
local requireModule

local function envFor(scriptInstance)
	local env = {
		script = scriptInstance,
		game = gameProxy,
		workspace = workspace,
		require = function(target)
			return requireModule(target)
		end,
		Instance = Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Font = roblox.Font,
		Random = Random,
		TweenInfo = TweenInfo,
		RaycastParams = { new = function()
			return {}
		end },
		task = require("@lune/task"),
		-- Roblox os.clock is wall-clock time; Lune's is CPU time
		os = setmetatable({ clock = function()
			return require("@lune/datetime").now().unixTimestampMillis / 1000
		end }, { __index = os }),
		typeof = typeof,
		warn = function(...)
			print("[warn]", ...)
		end,
	}
	return setmetatable(env, { __index = _G })
end

function requireModule(target)
	if cache[target] ~= nil then
		return cache[target]
	end
	assert(target:IsA("ModuleScript"), "require target is not a ModuleScript: " .. target:GetFullName())
	local source = target.Source
	local fn = luau.load(source, { debugName = target:GetFullName(), environment = envFor(target) })
	local result = fn()
	cache[target] = result
	return result
end


return {
	roblox = roblox,
	game = game,
	workspace = workspace,
	requireModule = requireModule,
	makeSignal = makeSignal,
	syncPositions = syncPositions,
	setRaycast = function(fn)
		raycastStub = fn
	end,
	setService = function(name, stub)
		services[name] = stub
	end,
	gameProxy = gameProxy,
}
