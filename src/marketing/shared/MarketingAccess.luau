--[[
	MarketingAccess
	Who may use Marketing Studio, and where. Pure functions so the rules can be
	tested; the server decides (MarketingGate) and the client re-checks.

	`env` lets tests describe the environment:
	  { studio: boolean, privateServerId: string, privateServerOwnerId: number,
	    creatorType: Enum.CreatorType, creatorId: number }
]]

local MarketingAccess = {}

function MarketingAccess.currentEnv()
	local RunService = game:GetService("RunService")
	local env = {
		studio = RunService:IsStudio(),
		privateServerId = "",
		privateServerOwnerId = 0,
		creatorType = game.CreatorType,
		creatorId = game.CreatorId,
	}
	-- private-server fields can only be read on the server; on the client the
	-- server's grant (player attribute) is what matters
	if RunService:IsServer() then
		env.privateServerId = game.PrivateServerId
		env.privateServerOwnerId = game.PrivateServerOwnerId
	end
	return env
end

-- Is this server one where Marketing Studio may exist at all?
function MarketingAccess.environmentAllowed(config, env): boolean
	if config.Enabled ~= true then
		return false
	end
	if env.studio then
		return config.AllowInStudio == true
	end
	-- a VIP server someone owns (reserved servers have no owner)
	return config.AllowInPrivateServers == true and type(env.privateServerId) == "string" and env.privateServerId ~= "" and (env.privateServerOwnerId or 0) > 0
end

local function listed(config, userId: number): boolean
	for _, id in config.AdminUserIds or {} do
		if id == userId then
			return true
		end
	end
	return false
end

-- May this player use it here?
function MarketingAccess.isAuthorized(userId: number, config, env): boolean
	if type(userId) ~= "number" or not MarketingAccess.environmentAllowed(config, env) then
		return false
	end
	if listed(config, userId) then
		return true
	end
	if config.AllowPlaceOwner and env.creatorType == Enum.CreatorType.User and userId == env.creatorId and userId > 0 then
		return true
	end
	if env.studio and config.AllowStudioTestPlayers and userId <= 0 then
		return true
	end
	-- in Studio an unpublished place has no owner: the person running it is the developer
	if env.studio and config.AllowPlaceOwner and (env.creatorId or 0) == 0 then
		return true
	end
	-- on a private server, only its owner (if listed above) or the place owner
	return false
end

return MarketingAccess
