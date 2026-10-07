--[[
	TutorialController
	The tutorial is the first night itself. New players (no tutorial finished on
	their profile) get one short coaching line at the moment each thing becomes
	relevant, never a wall of text:

	  outside           how to move and sprint
	  inside            interact with doors, notes and items
	  first note        notes are kept in the notebook
	  the outage        the flashlight, batteries run down
	  out of breath     walk to recover
	  first sighting    it only moves when nobody looks
	  with friends      ping things for the team
	  first anomaly     (server) look at it and hold the report input

	Veterans only get the flashlight line at the outage. Every line is shown once
	per session, and the whole thing stops when the server marks the tutorial
	as done.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local TutorialController = {}

local player = Players.LocalPlayer
local shown: { [string]: boolean } = {}
local insideSince = 0

local function isNewcomer(): boolean
	local p = State.profile
	return p ~= nil and p.flags ~= nil and p.flags.tutorialDone ~= true
end

local function key(action: string): string
	return "[" .. Registry.InputController:Label(action) .. "]"
end

function TutorialController:Show(id: string, text: string, duration: number?, everyone: boolean?)
	if shown[id] or State.status ~= "ALIVE" then
		return
	end
	if not everyone and not isNewcomer() then
		return
	end
	shown[id] = true
	Registry.HUDController:Coach(text, duration or 6)
end

local function moveText(): string
	if State.inputType == "Touch" then
		return "Left thumb to move, drag to look.  RUN to sprint."
	elseif State.inputType == "Gamepad" then
		return "Left stick to move, right stick to look.  " .. key("Sprint") .. " to sprint."
	end
	return "WASD to move.  " .. key("Sprint") .. " to sprint.  Walk inside."
end

function TutorialController:Start()
	-- outside, on arrival
	State.StatusChanged:Connect(function()
		if State.status == "ALIVE" and State.round.state == "STARTING" then
			task.delay(2.5, function()
				self:Show("move", moveText(), 6)
			end)
		end
	end)
	-- inside: interaction
	State.RoundChanged:Connect(function()
		if State.round.state == "EXPLORING" then
			insideSince = os.clock()
			task.delay(9, function()
				self:Show("interact", key("Interact") .. " opens doors, reads notes and picks things up.", 6)
			end)
		end
	end)
	-- first note read
	Net.event("Document").OnClientEvent:Connect(function()
		task.delay(1.5, function()
			self:Show("notes", "Notes you read are kept in your notebook " .. key("Notes") .. ".", 6)
		end)
	end)
	-- the outage: everybody hears about the flashlight once
	Net.event("Director").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		if p.cue == "blackout" and p.outage then
			task.delay(2.5, function()
				self:Show("flashlight", key("Flashlight") .. " flashlight.  Batteries run down: pick up spares.", 7, true)
			end)
		end
	end)
	-- first time the Observer is seen
	Net.event("Effect").OnClientEvent:Connect(function(p)
		if type(p) == "table" and p.name == "ObserverSeen" then
			task.delay(1.2, function()
				self:Show("observer", "It only moves when nobody is looking at it. Keep your eyes on it and back away.", 7, true)
			end)
		end
	end)
	-- breath and teamwork
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		if State.status ~= "ALIVE" then
			return
		end
		if State.stamina < 25 and not shown.breath then
			self:Show("breath", "Out of breath. Walk to recover.", 4)
		end
		if insideSince > 0 and os.clock() - insideSince > 70 and not shown.ping then
			local others = 0
			for _, p in State.players do
				if p.status == "ALIVE" and p.userId ~= player.UserId then
					others += 1
				end
			end
			if others > 0 then
				self:Show("ping", "Hold " .. key("Ping") .. " to point things out to your team.", 6)
			end
		end
	end)
end

return TutorialController
