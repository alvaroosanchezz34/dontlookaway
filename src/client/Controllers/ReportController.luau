--[[
	ReportController
	"Hold your gaze": hold the report input while looking at something that
	changed. The view narrows, a ring fills, and the ray is sent to the server,
	which alone decides whether it hit a real anomaly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local ReportController = {}

local focusing = false
local focusStart = 0
local lastSent = 0
local wasFocusing = false

local function canReport(): boolean
	return State.status == "ALIVE" and not State.uiOpen and not Registry.CameraController:HasOverride()
end

function ReportController:Begin()
	if not canReport() then
		return
	end
	if os.clock() - lastSent < GameConfig.Report.Cooldown then
		return
	end
	focusing = true
	focusStart = os.clock()
end

function ReportController:End()
	focusing = false
end

local function update()
	local hud = Registry.HUDController
	if not focusing then
		if wasFocusing then
			wasFocusing = false
			Registry.CameraController:SetFovEffect(0)
			if hud then
				hud:SetFocus(nil)
			end
		end
		return
	end
	wasFocusing = true
	if not canReport() then
		focusing = false
		return
	end
	local progress = math.clamp((os.clock() - focusStart) / GameConfig.Report.HoldTime, 0, 1)
	Registry.CameraController:SetFovEffect(-7 * progress)
	if hud then
		hud:SetFocus(progress)
	end
	if progress >= 1 then
		focusing = false
		lastSent = os.clock()
		local cf = Workspace.CurrentCamera.CFrame
		Net.event("Report"):FireServer(cf.Position, cf.LookVector)
	end
end

function ReportController:Start()
	Registry.InputController.Action:Connect(function(action, began)
		if action == "Report" then
			if began then
				self:Begin()
			else
				self:End()
			end
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return ReportController
