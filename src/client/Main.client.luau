--[[
	DON'T LOOK AWAY - client bootstrap
	Client responsibilities: input, camera, UI and local effects. Everything that
	matters (anomalies, monster, inventory, rewards) is decided by the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local StarterGui = game:GetService("StarterGui")

local Registry = require(script.Parent.Registry)

-- the loading screen's record of what is really ready (ReplicatedFirst/Boot)
local BootState = nil
do
	local boot = ReplicatedFirst:WaitForChild("Boot", 10)
	local module = boot and boot:FindFirstChild("BootState")
	if module then
		BootState = require(module)
	end
end
-- the controllers start once, never twice
if BootState and not BootState.claim("client") then
	return
end
if BootState then
	BootState.set("systems", "active")
end

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
	"FilmController",
	"AccessibilityController",
	"LightController",
	"MenuLook",
	"DetailLOD",
	"DoorController",
	"RealityController",
	"WorldFXController",
	"ParanoiaController",
	"BlackoutFX",
	"ObserverFX",
	"FlashlightController",
	"ToolController",
	"NametagController",
	"EmoteController",
	"InteractController",
	"ReportController",
	"PingController",
	"HUDController",
	"TutorialController",
	"PuzzleUI",
	"MobileControls",
	"MenuController",
	"LobbyController",
	"ResultsController",
	"SpectatorController",
	"ScareController",
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

local startFailures = 0
for _, c in controllers do
	if c.Start then
		task.spawn(function()
			local ok, err = pcall(c.Start, c)
			if not ok then
				startFailures += 1
				warn(string.format("[Client] %s.Start failed: %s", c.Name, tostring(err)))
			end
		end)
	end
end

-- every controller ran Init and was started (a Start that yields keeps
-- running in its own thread; a failure is reported, never hidden)
if BootState then
	BootState.set("systems", "done", if startFailures > 0 then string.format("%d system(s) failed to start", startFailures) else nil)
end
