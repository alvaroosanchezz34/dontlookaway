--[[
	MovementController
	Natural, weighty movement on top of Roblox's input modules:
	  * acceleration / deceleration instead of instant starts and stops
	  * sprint with stamina (hold on keyboard, toggle on gamepad / touch)
	  * no jumping, no bunny hopping: this is a horror game
	The server independently enforces a speed ceiling (AntiExploitService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local MovementController = {}

local player = Players.LocalPlayer
local controls = nil
local current = Vector3.zero
local speed = GameConfig.Movement.WalkSpeed
local sprintToggle = false
local lastSprintAt = 0
local M = GameConfig.Movement

local function getControls()
	if controls then
		return controls
	end
	local ok, module = pcall(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		return require(playerModule :: ModuleScript)
	end)
	if ok and module then
		controls = (module :: any):GetControls()
	end
	return controls
end

function MovementController:IsSprinting(): boolean
	return State.sprinting
end

local function step(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local canMove = (State.status == "ALIVE" or State.status == "LOBBY") and not State.uiOpen and not Registry.CameraController:HasOverride()
	local raw = Vector3.zero
	local c = getControls()
	if c and canMove then
		local ok, mv = pcall(function()
			return c:GetMoveVector()
		end)
		if ok and mv then
			raw = mv
		end
	end
	if raw.Magnitude > 1 then
		raw = raw.Unit
	end
	local yaw = Registry.CameraController:GetYawPitch()
	local target = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.new(raw.X, 0, raw.Z))
	local rate = if target.Magnitude > current.Magnitude then M.Acceleration else M.Deceleration
	current += (target - current) * Util.damp(rate, dt)
	if current.Magnitude < 0.02 and target.Magnitude == 0 then
		current = Vector3.zero
	end
	humanoid:Move(current, false)

	-- sprint & stamina
	local wantsSprint = Registry.InputController:IsHeld("Sprint") or sprintToggle
	local movingForward = raw.Z < -0.3 and current.Magnitude > 0.3
	local sprinting = wantsSprint and movingForward and canMove and State.stamina > 0 and (State.sprinting or State.stamina > M.StaminaMinToSprint)
	if sprinting then
		State.stamina = math.max(0, State.stamina - M.StaminaDrain * dt)
		lastSprintAt = os.clock()
		if State.stamina <= 0 then
			sprintToggle = false
		end
	elseif os.clock() - lastSprintAt > M.StaminaRegenDelay then
		local regen = M.StaminaRegen * (if current.Magnitude < 0.1 then 1.5 else 1)
		State.stamina = math.min(M.StaminaMax, State.stamina + regen * dt)
	end
	State.sprinting = sprinting
	local targetSpeed = if sprinting then M.SprintSpeed else M.WalkSpeed
	if State.status == "LOBBY" then
		targetSpeed = M.WalkSpeed
	end
	speed += (targetSpeed - speed) * Util.damp(3, dt)
	humanoid.WalkSpeed = speed
end

function MovementController:Init()
	Registry.InputController.Action:Connect(function(action, began)
		if action == "Sprint" and began and State.inputType ~= "Keyboard" then
			sprintToggle = not sprintToggle
		end
	end)
	player.CharacterAdded:Connect(function()
		State.stamina = M.StaminaMax
		sprintToggle = false
		current = Vector3.zero
	end)
end

function MovementController:Start()
	RunService:BindToRenderStep("DLA_Movement", Enum.RenderPriority.Input.Value + 2, step)
end

return MovementController
