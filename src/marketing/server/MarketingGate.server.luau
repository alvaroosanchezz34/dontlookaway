--[[
	MarketingGate
	Grants Marketing Studio to authorised players by setting the player
	attribute "MarketingStudio". There is no RemoteEvent: Marketing Studio is
	entirely local to the recording player's screen, so the only thing the
	server decides is who sees the tool. On public servers this script does
	nothing at all.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Marketing")
local Config = require(folder:WaitForChild("MarketingConfig"))
local Access = require(folder:WaitForChild("MarketingAccess"))

local env = Access.currentEnv()
if not Access.environmentAllowed(Config, env) then
	return
end

local function grant(player: Player)
	if Access.isAuthorized(player.UserId, Config, env) then
		player:SetAttribute("MarketingStudio", true)
		print(string.format("[Marketing] Marketing Studio available to %s (%s to open)", player.Name, Config.ToggleKey.Name))
	end
end

Players.PlayerAdded:Connect(grant)
for _, player in Players:GetPlayers() do
	grant(player)
end
