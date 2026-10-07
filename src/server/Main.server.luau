--[[
	DON'T LOOK AWAY - server bootstrap
	Loads every service, runs Init (wire-up, no yielding on other services) then
	Start (behaviour) in a fixed order.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Registry = require(script.Parent.Registry)

Net.init()

local ORDER = {
	"AnalyticsService",
	"DataService",
	"SettingsService",
	"AntiExploitService",
	"PlayerService",
	"AudioService",
	"LightingService",
	"MapService",
	"DoorService",
	"RealityService",
	"InventoryService",
	"InteractionService",
	"ProgressionService",
	"EconomyService",
	"EquipmentService",
	"ChallengeService",
	"ObjectiveService",
	"PuzzleService",
	"AnomalyService",
	"ObserverService",
	"HorrorDirector",
	"GuidanceService",
	"PingService",
	"RoundService",
	"LobbyService",
	"AdminService",
}

local services = {}
for _, name in ORDER do
	local module = script.Parent.Services:FindFirstChild(name)
	assert(module, "missing service " .. name)
	local service = require(module)
	service.Name = name
	Registry[name] = service
	table.insert(services, service)
end

for _, service in services do
	if service.Init then
		local ok, err = pcall(service.Init, service)
		if not ok then
			warn(string.format("[Main] %s.Init failed: %s", service.Name, tostring(err)))
		end
	end
end

for _, service in services do
	if service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn(string.format("[Main] %s.Start failed: %s", service.Name, tostring(err)))
			end
		end)
	end
end

print(string.format("[DON'T LOOK AWAY] server ready (%d services)", #services))
