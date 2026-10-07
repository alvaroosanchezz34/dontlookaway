--[[
	RealityService
	The building's reality state. Every change made by an anomaly (or by the
	escape sequence) goes through here as a list of RealityOps:
	  GLOBAL  ops are applied on the server and replicate to everyone
	  PLAYER / TEAM ops are sent only to the listed clients and applied locally
	Each application returns a token; reverting a token restores reality exactly.
	The service tracks every live token so a round can always be cleaned up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Net = require(ReplicatedStorage.Shared.Net)
local RealityOps = require(ReplicatedStorage.Shared.RealityOps)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local RealityService = {}

RealityService.Changed = Signal.new() -- (token, scope, applied:boolean)

type Entry = { token: string, scope: string, players: { Player }?, revert: (() -> ())?, created: { Instance }, ops: { any } }

local live: { [string]: Entry } = {}
local assetsFolder: Folder
local dynamicFolder: Folder

function RealityService:GetAssets(): Folder
	return assetsFolder
end

-- Stores a template that clients may need to clone locally.
function RealityService:AddTemplate(name: string, instance: Instance, dynamic: boolean?): Instance
	instance.Name = name
	instance.Parent = if dynamic then dynamicFolder else assetsFolder
	return instance
end

function RealityService:GetTemplate(name: string): Instance?
	return assetsFolder:FindFirstChild(name) or dynamicFolder:FindFirstChild(name)
end

-- Applies ops. Returns token and (for GLOBAL) the instances created by Clone ops.
function RealityService:Apply(ops: { any }, scope: string?, players: { Player }?): (string, { Instance })
	local token = HttpService:GenerateGUID(false)
	scope = scope or Enums.AnomalyScope.Global
	local entry: Entry = { token = token, scope = scope, players = players, revert = nil, created = {}, ops = ops }
	if scope == Enums.AnomalyScope.Global then
		local revert, created = RealityOps.applyAll(ops)
		entry.revert = revert
		entry.created = created
	else
		Net.fireList(players or {}, "Reality", { action = "apply", token = token, ops = ops })
	end
	live[token] = entry
	RealityService.Changed:Fire(token, scope, true)
	return token, entry.created
end

function RealityService:Revert(token: string?, silent: boolean?)
	if not token then
		return
	end
	local entry = live[token]
	if not entry then
		return
	end
	live[token] = nil
	if entry.scope == Enums.AnomalyScope.Global then
		if entry.revert then
			entry.revert()
		end
	else
		Net.fireList(entry.players or {}, "Reality", { action = "revert", token = token, silent = silent })
	end
	RealityService.Changed:Fire(token, entry.scope, false)
end

function RealityService:IsLive(token: string): boolean
	return live[token] ~= nil
end

function RealityService:RevertAll()
	for token in table.clone(live) do
		self:Revert(token, true)
	end
	Net.fireAll("Reality", { action = "clear" })
	dynamicFolder:ClearAllChildren()
end

function RealityService:Init()
	assetsFolder = ReplicatedStorage:FindFirstChild("RealityAssets") :: Folder
	if not assetsFolder then
		assetsFolder = Instance.new("Folder")
		assetsFolder.Name = "RealityAssets"
		assetsFolder.Parent = ReplicatedStorage
	end
	dynamicFolder = Instance.new("Folder")
	dynamicFolder.Name = "Dynamic"
	dynamicFolder.Parent = assetsFolder
end

return RealityService
