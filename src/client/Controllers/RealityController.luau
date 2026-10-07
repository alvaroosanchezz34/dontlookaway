--[[
	RealityController
	Applies PLAYER / TEAM scoped reality changes locally. Only this client sees
	them; the server keeps the authoritative record and decides when they end.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local RealityOps = require(ReplicatedStorage.Shared.RealityOps)

local RealityController = {}

local live: { [string]: () -> () } = {}

local function autoplay(created: { Instance })
	for _, inst in created do
		for _, d in inst:GetDescendants() do
			if d:IsA("Sound") and d:GetAttribute("AutoPlay") then
				d:Play()
			end
		end
	end
end

function RealityController:Start()
	Net.event("Reality").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.action == "apply" and type(payload.token) == "string" and type(payload.ops) == "table" then
			if live[payload.token] then
				return
			end
			local revert, created = RealityOps.applyAll(payload.ops)
			live[payload.token] = revert
			autoplay(created)
		elseif payload.action == "revert" and type(payload.token) == "string" then
			local revert = live[payload.token]
			live[payload.token] = nil
			if revert then
				revert()
			end
		elseif payload.action == "clear" then
			for token, revert in live do
				live[token] = nil
				pcall(revert)
			end
		end
	end)
end

return RealityController
