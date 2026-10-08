--[[
	MarketingStudio (entry point)
	Does nothing at all unless every gate passes:
	  1. MarketingConfig.Enabled
	  2. the environment allows it (Roblox Studio, or an allowed private server)
	  3. the server granted it to this player (player attribute "MarketingStudio",
	     set by ServerScriptService.Marketing.MarketingGate for authorised UserIds)
	Then it loads the controller and the panel (F7). Nothing it does replicates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Marketing", 10)
if not shared then
	return
end
local Config = require(shared:WaitForChild("MarketingConfig"))
local Access = require(shared:WaitForChild("MarketingAccess"))

-- the client can only check Studio itself; a private server is vouched for by
-- the server's grant below
local env = Access.currentEnv()
if Config.Enabled ~= true or (env.studio and not Access.environmentAllowed(Config, env)) or (not env.studio and Config.AllowInPrivateServers ~= true) then
	return
end

local player = Players.LocalPlayer
local function granted(): boolean
	return player:GetAttribute("MarketingStudio") == true
end
if not granted() then
	-- the server sets it as the player joins; give it a moment, then give up
	local deadline = os.clock() + 15
	while not granted() and os.clock() < deadline do
		task.wait(0.25)
	end
	if not granted() then
		return
	end
end

local MarketingController = require(script.Parent:WaitForChild("MarketingController"))
local Panel = require(script.Parent:WaitForChild("UI"):WaitForChild("Panel"))
Panel.mount(MarketingController, Config)
print(string.format("[Marketing] Marketing Studio ready: %d scenes · %s to open", #MarketingController.ListScenes(), Config.ToggleKey.Name))
