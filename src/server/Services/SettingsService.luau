--[[
	SettingsService
	Accessibility & comfort settings are stored with the profile. The client may
	only send a settings table; every value is type checked and clamped here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)

local SettingsService = {}

local NUMBERS = {
	master = { 0, 1 },
	music = { 0, 1 },
	sfx = { 0, 1 },
	ambient = { 0, 1 },
	ui = { 0, 1 },
	sensitivity = { 0.05, 2 },
	fov = { GameConfig.Camera.MinFOV, GameConfig.Camera.MaxFOV },
}

local BOOLS = { headBob = true, cameraShake = true, reducedEffects = true, flashingAccepted = true, subtitles = true, invertY = true }

function SettingsService:Init()
	Net.on("Settings", function(player, incoming)
		if type(incoming) ~= "table" then
			return
		end
		Registry.DataService:Update(player, function(data)
			local count = 0
			for key, value in incoming do
				count += 1
				if count > 32 then
					break
				end
				if type(key) == "string" then
					local range = NUMBERS[key]
					if range and Util.isFinite(value) then
						data.settings[key] = math.clamp(value, range[1], range[2])
					elseif BOOLS[key] and type(value) == "boolean" then
						data.settings[key] = value
					end
				end
			end
		end)
	end)
end

return SettingsService
