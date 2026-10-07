--[[
	DON'T LOOK AWAY - client bootstrap
	Client responsibilities: input, camera, UI and local effects. Everything that
	matters (anomalies, monster, inventory, rewards) is decided by the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Registry = require(script.Parent.Registry)

-- The game draws its own HUD; hide default core UI that would break immersion.
local function disableCore()
	for _, coreType in { Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu } do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreType, false)
		end)
	end
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", false)
	end)
end

task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(disableCore)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

ReplicatedStorage:WaitForChild("Remotes")

local ORDER = {
	"InputController",
	"NetController",
	"AudioController",
	"MusicController",
	"CameraController",
	"MovementController",
	"EffectsController",
	"LightController",
	"DoorController",
	"RealityController",
	"WorldFXController",
	"ObserverFX",
	"FlashlightController",
	"NametagController",
	"EmoteController",
	"InteractController",
	"ReportController",
	"PingController",
	"HUDController",
	"PuzzleUI",
	"MobileControls",
	"MenuController",
	"LobbyController",
	"ResultsController",
	"SpectatorController",
	"DeathController",
	"AdminController",
}

local controllers = {}
for _, name in ORDER do
	local module = script.Parent.Controllers:FindFirstChild(name)
	assert(module, "missing controller " .. name)
	local controller = require(module)
	controller.Name = name
	Registry[name] = controller
	table.insert(controllers, controller)
end

for _, c in controllers do
	if c.Init then
		local ok, err = pcall(c.Init, c)
		if not ok then
			warn(string.format("[Client] %s.Init failed: %s", c.Name, tostring(err)))
		end
	end
end

for _, c in controllers do
	if c.Start then
		task.spawn(function()
			local ok, err = pcall(c.Start, c)
			if not ok then
				warn(string.format("[Client] %s.Start failed: %s", c.Name, tostring(err)))
			end
		end)
	end
end
