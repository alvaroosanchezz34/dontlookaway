--[[
	CameraController
	A custom first-person camera (Scriptable), not Roblox's default.
	  * mouse, touch and gamepad look with configurable sensitivity / invert Y
	  * gentle head bob, landing dip and turn sway (toggleable, never nauseating)
	  * smooth FOV (setting + sprint + effect offsets)
	  * trauma-based camera shake (toggleable)
	  * overrides for cinematics (menu, death, escape, spectator) by priority
	  * reports the view ray to the server for perception (10 Hz)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)

local CameraController = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local yaw, pitch = 0, 0
local targetYawVel = 0
local bobPhase = 0
local bobAmount = 0
local landDip = 0
local roll = 0
local trauma = 0
local fovOffset = 0
local fovEffect = 0
local currentFov = GameConfig.Camera.DefaultFOV
local overrides: { [string]: { priority: number, fn: (number) -> (CFrame?, number?) } } = {}
local touchLook: InputObject? = nil
local touchDelta = Vector2.zero
local gamepadLook = Vector2.zero
local lastLookSend = 0
local wasFalling = false
local lastCF = CFrame.new()
local frozen = false
local overrideActive = false -- an override produced the camera last frame

function CameraController:SetOverride(name: string, priority: number, fn: (number) -> (CFrame?, number?))
	overrides[name] = { priority = priority, fn = fn }
end

function CameraController:ClearOverride(name: string)
	overrides[name] = nil
end

-- True only while an override is actually driving the camera. Overrides stay
-- registered (the menu one lives forever) and return nil when they don't apply.
function CameraController:HasOverride(): boolean
	return overrideActive
end

function CameraController:Shake(amount: number)
	if not State.settings.cameraShake then
		amount *= 0.15
	end
	trauma = math.clamp(trauma + amount, 0, 1)
end

function CameraController:SetFovEffect(offset: number)
	fovEffect = offset
end

function CameraController:GetYawPitch(): (number, number)
	return yaw, pitch
end

function CameraController:SetYawPitch(y: number, p: number)
	yaw, pitch = y, p
end

-- Points the view at a world position (used by cinematics and the death sequence).
function CameraController:LookAt(position: Vector3)
	local cf = camera.CFrame
	local dir = (position - cf.Position)
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	yaw = math.atan2(-dir.X, -dir.Z)
	pitch = math.asin(math.clamp(dir.Y, -1, 1))
end

function CameraController:SetFrozen(on: boolean)
	frozen = on
end

function CameraController:GetCFrame(): CFrame
	return lastCF
end

local function gameplayActive(): boolean
	return (State.status == "ALIVE" or State.status == "LOBBY") and not CameraController:HasOverride()
end

local function updateMouseLock()
	local lock = gameplayActive() and not State.uiOpen and State.inputType ~= "Touch"
	if lock and State.status == "LOBBY" and State.inputType == "Keyboard" then
		-- in the Field Office the cursor stays free for the lobby panel; hold RMB to look
		lock = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	end
	UserInputService.MouseBehavior = if lock then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not lock
end

local function hideCharacter(character: Model)
	local function hide(d: Instance)
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = 1
		end
	end
	for _, d in character:GetDescendants() do
		hide(d)
	end
	character.DescendantAdded:Connect(hide)
end

local function applyLookInput(dt: number)
	if frozen or State.uiOpen then
		touchDelta = Vector2.zero
		return
	end
	local sens = State.settings.sensitivity or GameConfig.Camera.DefaultSensitivity
	local invert = if State.settings.invertY then -1 else 1
	local dx, dy = 0, 0
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		local delta = UserInputService:GetMouseDelta()
		dx += delta.X * 0.0042 * sens
		dy += delta.Y * 0.0042 * sens
	end
	dx += touchDelta.X * 0.0075 * sens
	dy += touchDelta.Y * 0.0075 * sens
	touchDelta = Vector2.zero
	-- gamepad with a response curve for precise small corrections
	local g = gamepadLook
	if g.Magnitude > 0.12 then
		local m = (g.Magnitude - 0.12) / 0.88
		local curved = g.Unit * (m * m) * 3.4 * (sens / 0.55)
		dx += curved.X * dt
		dy += -curved.Y * dt
	end
	yaw -= dx
	pitch = math.clamp(pitch - dy * invert, -math.rad(GameConfig.Camera.MaxPitch), math.rad(GameConfig.Camera.MaxPitch))
	targetYawVel = dx / math.max(dt, 1 / 240)
end

local function fpsCFrame(dt: number): CFrame?
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not head or not root or not humanoid then
		return nil
	end
	humanoid.AutoRotate = false
	-- body follows the view yaw
	if not humanoid.PlatformStand then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	end
	local velocity = Util.flat(root.AssemblyLinearVelocity)
	local speed = velocity.Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	-- landing dip
	if not grounded then
		wasFalling = true
	elseif wasFalling then
		wasFalling = false
		landDip = math.min(0.35, landDip + 0.25)
	end
	landDip = math.max(0, landDip - dt * 1.4)
	-- head bob
	local motion = State.settings.headBob ~= false and not State.settings.reducedEffects and not State.settings.reduceMotion
	local targetBob = if grounded and speed > 1 and motion then math.clamp(speed / GameConfig.Movement.WalkSpeed, 0, 1.6) else 0
	bobAmount += (targetBob - bobAmount) * Util.damp(6, dt)
	bobPhase += dt * GameConfig.Camera.HeadBobFrequency * math.pi * 2 * math.clamp(speed / GameConfig.Movement.WalkSpeed, 0.6, 1.5)
	local amp = GameConfig.Camera.HeadBobAmplitude * bobAmount
	local bobY = math.abs(math.sin(bobPhase)) * amp - amp * 0.5
	local bobX = math.cos(bobPhase) * amp * 0.55
	-- sway on turns
	local targetRoll = if motion then math.clamp(-targetYawVel * 0.004, -0.035, 0.035) else 0
	roll += (targetRoll - roll) * Util.damp(5, dt)
	local base = CFrame.new(head.Position + Vector3.new(0, 0.35 - landDip, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	return base * CFrame.new(bobX, bobY, 0) * CFrame.Angles(0, 0, roll + bobX * 0.04)
end

local function shakeOffset(dt: number): CFrame
	if trauma <= 0 then
		return CFrame.new()
	end
	trauma = math.max(0, trauma - dt * 1.3)
	local t = os.clock() * 24
	local s = trauma * trauma * (if State.settings.reducedEffects or State.settings.reduceMotion then 0.3 else 1)
	return CFrame.Angles(math.noise(t, 1) * 0.05 * s, math.noise(t, 2) * 0.05 * s, math.noise(t, 3) * 0.04 * s)
end

local function step(dt: number)
	camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	updateMouseLock()
	applyLookInput(dt)
	-- highest priority override that applies wins
	local list = {}
	for _, o in overrides do
		table.insert(list, o)
	end
	table.sort(list, function(a, b)
		return a.priority > b.priority
	end)
	local cf: CFrame? = nil
	local overrideFov: number? = nil
	for _, o in list do
		cf, overrideFov = o.fn(dt)
		if cf then
			break
		end
	end
	overrideActive = cf ~= nil
	if not cf then
		cf = fpsCFrame(dt)
	end
	if not cf then
		cf = lastCF
	end
	local final = (cf :: CFrame) * shakeOffset(dt)
	camera.CFrame = final
	lastCF = final
	-- fov
	local sprintBoost = if State.sprinting then 4 else 0
	local target = overrideFov or ((State.settings.fov or GameConfig.Camera.DefaultFOV) + sprintBoost + fovEffect + fovOffset)
	currentFov += (target - currentFov) * Util.damp(5, dt)
	camera.FieldOfView = currentFov
	-- perception report
	local now = os.clock()
	if State.status == "ALIVE" and now - lastLookSend > 0.1 then
		lastLookSend = now
		Net.event("LookUpdate"):FireServer(final.Position, final.LookVector)
	end
end

function CameraController:Init()
	player.CharacterAdded:Connect(function(character)
		hideCharacter(character)
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if root then
			local look = root.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
			pitch = 0
		end
	end)
	if player.Character then
		hideCharacter(player.Character)
	end
	UserInputService.TouchStarted:Connect(function(touch, processed)
		if processed or touchLook then
			return
		end
		local viewport = camera.ViewportSize
		-- the left part of the screen belongs to the movement thumbstick
		if touch.Position.X > viewport.X * 0.35 then
			touchLook = touch
		end
	end)
	UserInputService.TouchMoved:Connect(function(touch)
		if touch == touchLook then
			touchDelta += Vector2.new(touch.Delta.X, touch.Delta.Y)
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch)
		if touch == touchLook then
			touchLook = nil
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.zero
		end
	end)
end

function CameraController:Start()
	RunService:BindToRenderStep("DLA_Camera", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
