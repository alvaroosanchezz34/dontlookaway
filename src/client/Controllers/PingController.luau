--[[
	PingController
	Tap ping = ANOMALY at the crosshair. Hold ping = wheel (ANOMALY, COME HERE,
	DANGER, DOOR, ITEM), release on a choice. Markers are visible through walls
	with distance, sender and colour. False pings (an anomaly) look almost the
	same: no distance readout, and the name never quite settles.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Pings = require(ReplicatedStorage.Shared.Catalog.Pings)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local PingController = {}

local player = Players.LocalPlayer
local wheel: Frame
local options: { [string]: TextButton } = {}
local pressAt = 0
local wheelOpen = false
local hovered: string? = nil
local markers: { [string]: { part: Part, gui: BillboardGui, dist: TextLabel, fake: boolean, name: TextLabel, from: string } } = {}
local random = Random.new()

local function aimPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local hit = Workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * GameConfig.Ping.MaxDistance, params)
	if hit then
		return hit.Position + hit.Normal * 0.5
	end
	return nil
end

local function send(kind: string)
	local point = aimPoint()
	if not point then
		Registry.HUDController:Hint("Nothing there to mark.", 1.5)
		return
	end
	Net.event("Ping"):FireServer(kind, point)
end

local function openWheel()
	wheelOpen = true
	hovered = nil
	wheel.Visible = true
	if State.inputType ~= "Touch" then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

local function closeWheel(sendHovered: boolean)
	if not wheelOpen then
		return
	end
	wheelOpen = false
	wheel.Visible = false
	if sendHovered and hovered then
		send(hovered)
	end
	hovered = nil
end

function PingController:OpenTouchWheel()
	if State.status ~= "ALIVE" then
		return
	end
	if wheelOpen then
		closeWheel(false)
	else
		openWheel()
	end
end

local function showMarker(payload)
	local id = payload.id
	if payload.remove then
		local m = markers[id]
		if m then
			m.part:Destroy()
			markers[id] = nil
		end
		return
	end
	local def = Pings.List[payload.kind]
	if not def or typeof(payload.position) ~= "Vector3" then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(payload.position)
	part.Parent = Workspace
	local gui = Kit.new("BillboardGui", { Size = UDim2.fromOffset(170, 74), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 400, Adornee = part, ResetOnSpawn = false, Parent = player:WaitForChild("PlayerGui") })
	local diamond = Kit.frame({ Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 12), Rotation = 45, BackgroundColor3 = def.color, Parent = gui })
	Kit.stroke(diamond, Color3.new(0, 0, 0), 1, 0.4)
	Kit.text({ Text = def.label, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 24), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 15, TextColor3 = def.color, TextStrokeTransparency = 0.5, Parent = gui })
	local name = Kit.text({ Text = payload.from or "", Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 42), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Light, TextSize = 12, TextColor3 = Kit.C.TextDim, TextStrokeTransparency = 0.6, Parent = gui })
	local dist = Kit.text({ Text = "", Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 56), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = Kit.C.TextDim, TextStrokeTransparency = 0.6, Parent = gui })
	markers[id] = { part = part, gui = gui, dist = dist, fake = payload.fake == true, name = name, from = payload.from or "" }
	Registry.AudioController:Play(def.sound, nil)
	local duration = payload.duration or GameConfig.Ping.Duration
	task.delay(duration, function()
		local m = markers[id]
		if m and m.part == part then
			Kit.tween(diamond, 0.6, { BackgroundTransparency = 1 })
			Debris:AddItem(part, 0.7)
			Debris:AddItem(gui, 0.7)
			markers[id] = nil
		end
	end)
	part.Destroying:Connect(function()
		gui:Destroy()
	end)
end

function PingController:Init()
	local gui = Kit.screen("PingWheel", 6)
	wheel = Kit.frame({ Size = UDim2.fromOffset(460, 460), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Visible = false, Parent = gui })
	for i, kind in Pings.Order do
		local def = Pings.List[kind]
		local angle = (i - 1) / #Pings.Order * math.pi * 2 - math.pi / 2
		local button = Kit.button({ Text = def.label, Size = UDim2.fromOffset(150, 50), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(angle) * 160, 0.5, math.sin(angle) * 160), TextColor3 = def.color, Parent = wheel }, function()
			hovered = kind
			closeWheel(true)
		end)
		button.MouseEnter:Connect(function()
			hovered = kind
		end)
		options[kind] = button
	end
	Kit.text({ Text = "PING", Size = UDim2.fromOffset(120, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextColor3 = Kit.C.TextDim, Parent = wheel })
end

function PingController:Start()
	Registry.InputController.Action:Connect(function(action, began)
		if action ~= "Ping" or State.status ~= "ALIVE" or State.inputType == "Touch" then
			return
		end
		if began then
			pressAt = os.clock()
			task.delay(0.28, function()
				if Registry.InputController:IsHeld("Ping") and os.clock() - pressAt >= 0.27 then
					openWheel()
				end
			end)
		else
			if wheelOpen then
				closeWheel(true)
			elseif os.clock() - pressAt < 0.28 then
				send("ANOMALY")
			end
		end
	end)
	-- gamepad: right stick chooses on the wheel
	UserInputService.InputChanged:Connect(function(input)
		if wheelOpen and input.KeyCode == Enum.KeyCode.Thumbstick2 and Vector2.new(input.Position.X, input.Position.Y).Magnitude > 0.5 then
			local a = math.atan2(-input.Position.Y, input.Position.X)
			local best, bestD = nil, math.huge
			for i, kind in Pings.Order do
				local angle = (i - 1) / #Pings.Order * math.pi * 2 - math.pi / 2
				local d = math.abs((a - angle + math.pi) % (2 * math.pi) - math.pi)
				if d < bestD then
					best, bestD = kind, d
				end
			end
			hovered = best
			for kind, b in options do
				b.BackgroundTransparency = if kind == best then 0 else 0.35
			end
		end
	end)
	Net.event("PingShow").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.id) == "string" then
			showMarker(payload)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local camPos = Workspace.CurrentCamera.CFrame.Position
		for _, m in markers do
			if m.fake then
				m.dist.Text = "--"
				if random:NextNumber() < 0.04 then
					m.name.Text = string.reverse(m.from)
				elseif random:NextNumber() < 0.2 then
					m.name.Text = m.from
				end
			else
				m.dist.Text = string.format("%dm", math.floor((m.part.Position - camPos).Magnitude / 3.57))
			end
		end
	end)
end

return PingController
