--[[
	DeathController
	No gore. Being caught is a short cinematic: control is lost, the view is pulled
	toward it, sound tears, the screen darkens and distorts, and you fall. Then
	you watch the others. Escaping gets its own quiet ending outside.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local DeathController = {}

local function afterDeath(delay: number)
	task.delay(delay, function()
		Registry.CameraController:ClearOverride("Death")
		Registry.EffectsController:ResetPost()
		if State.round.state ~= "RESULTS" and State.round.state ~= "RETURNING" and State.round.state ~= "LOBBY" then
			Registry.SpectatorController:Begin(false)
		end
	end)
end

local function deathSequence(payload)
	local cam = Registry.CameraController
	local fx = Registry.EffectsController
	-- caught by The Observer: one of the cinematic variants
	if payload.variant then
		Registry.MusicController:Force("DEATH", 7)
		Registry.ScareController:Death(payload, function()
			afterDeath(4.6)
		end)
		return
	end
	local start = os.clock()
	local from = cam:GetCFrame()
	local killer: CFrame? = payload.killer
	local focus = if killer then (killer * CFrame.new(0, 8.6, 0)).Position else from.Position + from.LookVector * 5
	Registry.MusicController:Force("DEATH", 6)
	Registry.AudioController:PlayUI("DeathHit")
	fx:Glitch(1, 0.4)
	if not State.settings.reducedEffects then
		fx:Flash(Color3.fromRGB(120, 20, 20), 0.35, 0.6)
	end
	cam:Shake(1)
	fx:Blur(10, 1.2)
	cam:SetOverride("Death", 50, function()
		local t = os.clock() - start
		local eye = from.Position
		if t < 0.35 then
			-- wrenched toward it
			local look = CFrame.lookAt(eye, focus)
			return from:Lerp(look, math.clamp(t / 0.3, 0, 1)), 50
		elseif t < 2.2 then
			-- falling: the view tips and drops toward the floor
			local a = math.clamp((t - 0.35) / 1.4, 0, 1)
			local eased = a * a
			local look = CFrame.lookAt(eye, focus)
			return look * CFrame.new(0, -4.2 * eased, 0) * CFrame.Angles(math.rad(25 * eased), 0, math.rad(75 * eased)), 50 + 20 * eased
		end
		local look = CFrame.lookAt(eye, focus)
		return look * CFrame.new(0, -4.2, 0) * CFrame.Angles(math.rad(25), 0, math.rad(75)), 70
	end)
	task.delay(1.6, function()
		fx:Fade(1, 1.2)
	end)
	task.delay(3.1, function()
		fx:Title("YOU WERE TAKEN", "It was right there when you looked away.", 3, Kit.F.Title)
	end)
	task.delay(6.2, function()
		cam:ClearOverride("Death")
		fx:ResetPost()
		if State.round.state ~= "RESULTS" and State.round.state ~= "RETURNING" and State.round.state ~= "LOBBY" then
			Registry.SpectatorController:Begin(false)
		end
	end)
end

local function escapeSequence(payload)
	local cam = Registry.CameraController
	local fx = Registry.EffectsController
	local shot: CFrame? = payload.camera
	local start = os.clock()
	Registry.MusicController:Force("RESULTS", 10)
	fx:Fade(1, 0.35)
	task.delay(0.5, function()
		if shot then
			cam:SetOverride("Escape", 45, function()
				local t = os.clock() - start
				return (shot :: CFrame) * CFrame.new(0, 0, -math.min(t, 8) * 0.6), 60
			end)
		end
		fx:Fade(0, 2)
		fx:Title("YOU GOT OUT", if payload.witness then "...and something came out with you." else "The rain has never sounded so loud.", 4)
	end)
	task.delay(7.5, function()
		fx:Fade(1, 1)
		task.wait(1.1)
		cam:ClearOverride("Escape")
		fx:Fade(0, 1)
		if State.round.state == "ESCAPE" then
			Registry.SpectatorController:Begin(false)
		end
	end)
end

function DeathController:Start()
	Net.event("Death").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			deathSequence(payload)
		end
	end)
	Registry.EffectsController:Register("Escaped", escapeSequence)
end

return DeathController
