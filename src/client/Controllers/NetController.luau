--[[
	NetController
	Mirrors server state into the client State module and fires change signals.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local NetController = {}

local player = Players.LocalPlayer
local settingsLoaded = false

local function setStatus(status: string)
	if State.status ~= status then
		State.status = status
		State.StatusChanged:Fire(status)
	end
end

function NetController:Start()
	Net.event("RoundState").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		State.round.state = p.state or State.round.state
		State.round.difficulty = p.difficulty or State.round.difficulty
		State.round.seed = p.seed or State.round.seed
		State.round.elapsed = p.elapsed or 0
		if p.escapeRemaining then
			State.round.escapeEndsAt = os.clock() + p.escapeRemaining
		elseif p.state ~= "ESCAPE" then
			State.round.escapeEndsAt = nil
		end
		if p.state == "STARTING" or p.state == "LOBBY" then
			State.notes = {}
		end
		State.RoundChanged:Fire(State.round)
	end)
	Net.event("LobbyState").OnClientEvent:Connect(function(p)
		if type(p) == "table" then
			State.lobby = p
			State.LobbyChanged:Fire(p)
		end
	end)
	Net.event("InventoryState").OnClientEvent:Connect(function(p)
		if type(p) == "table" then
			local slots = {}
			for i, s in p.slots or {} do
				slots[i] = if s then s else nil
			end
			State.inventory = { slots = slots, selected = p.selected or 1, battery = p.battery or 100, light = p.light == true }
			State.InventoryChanged:Fire(State.inventory)
		end
	end)
	Net.event("Objective").OnClientEvent:Connect(function(p)
		if type(p) == "table" then
			local first = #(State.objectives.list or {}) > 0
			State.objectives = p
			State.ObjectivesChanged:Fire(p)
			if first and State.status == "ALIVE" then
				Registry.AudioController:PlayUI("ObjectiveUpdate")
			end
		end
	end)
	Net.event("Profile").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		State.profile = p
		-- settings come from the server only once; afterwards the client is the editor
		if not settingsLoaded and type(p.settings) == "table" then
			settingsLoaded = true
			for k, v in p.settings do
				State.settings[k] = v
			end
			State.SettingsChanged:Fire()
		end
		State.ProfileChanged:Fire(p)
	end)
	Net.event("Director").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		if p.cue == "phase" then
			State.phase = p.phase
		elseif p.cue == "silence" then
			Registry.AudioController:Silence(p.duration or 6)
		elseif p.cue == "hunt" then
			Registry.EffectsController:Glitch(0.3, 0.2)
		end
	end)
	player:GetAttributeChangedSignal("Status"):Connect(function()
		setStatus(player:GetAttribute("Status") or "MENU")
	end)
	setStatus(player:GetAttribute("Status") or "MENU")
	-- initial profile (in case the push arrived before we connected)
	task.spawn(function()
		task.wait(2)
		if not State.profile then
			local ok, p = pcall(function()
				return Net.func("GetProfile"):InvokeServer()
			end)
			if ok and type(p) == "table" then
				State.profile = p
				if not settingsLoaded and type(p.settings) == "table" then
					settingsLoaded = true
					for k, v in p.settings do
						State.settings[k] = v
					end
					State.SettingsChanged:Fire()
				end
				State.ProfileChanged:Fire(p)
			end
		end
	end)
end

return NetController
