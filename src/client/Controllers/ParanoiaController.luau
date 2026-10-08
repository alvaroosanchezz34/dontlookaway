--[[
	ParanoiaController
	The Observer's presence, felt by this player only.

	1. Proximity (player attribute "ObserverProx", decided by ObserverService):
	   FAR / AWARE / NEAR / VERY_NEAR / HUNT. EffectsController and
	   AudioController read State.prox for vignette, ducking, heartbeat and
	   breathing; this controller adds the moments when a state is entered:
	   AWARE    a far light stutters once
	   NEAR     the lights around you stutter, a low exhale somewhere close
	   VERY_NEAR the world goes quiet
	   HUNT     handled by the hunt cue / music

	2. Paranoia (Director cue "paranoia"): private, deniable moments that are
	   NOT anomalies. Nothing here changes the server's world, can be reported
	   or counted; everything is local and gone within a second or two.
	   micro    a light stutters / one step behind you / a creak overhead
	   glimpse  a figure in a mirror, a face on a monitor, a shape in a window
	   shadow   something crosses the corridor far ahead
	   silence  the building holds its breath, then something heavy falls far away
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local ParanoiaController = {}

local player = Players.LocalPlayer
local random = Random.new()

local function camera(): Camera
	return Workspace.CurrentCamera
end

-- Is `position` in front of the camera and not behind a wall?
local function inView(position: Vector3, ignore: Instance?, cone: number?): boolean
	local cf = camera().CFrame
	local offset = position - cf.Position
	if offset.Magnitude < 0.5 or offset.Unit:Dot(cf.LookVector) < (cone or 0.55) then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if player.Character then
		table.insert(exclude, player.Character)
	end
	if ignore then
		table.insert(exclude, ignore)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(cf.Position, offset * 0.97, params)
	return hit == nil or (hit.Instance.Transparency > 0.3)
end

local function behind(distance: number): Vector3
	local cf = camera().CFrame
	local back = Vector3.new(-cf.LookVector.X, 0, -cf.LookVector.Z)
	if back.Magnitude < 0.01 then
		back = Vector3.new(0, 0, 1)
	end
	return cf.Position + back.Unit * distance - Vector3.new(0, 4, 0)
end

------------------------------------------------------------------------------------
-- Paranoia moments
------------------------------------------------------------------------------------

local function micro(): boolean
	local audio = Registry.AudioController
	local roll = random:NextInteger(1, 3)
	if roll == 1 then
		local at = Registry.LightController:FlickerNear(camera().CFrame.Position, 30, random:NextNumber(0.3, 0.7), 1)
		if at then
			audio:Play("LightFlicker", at, { volume = 0.6 })
			return true
		end
	end
	if roll <= 2 then
		-- one step too many, just behind you
		task.delay(random:NextNumber(0.2, 0.5), function()
			audio:Play("StepConcrete", behind(random:NextNumber(5, 8)), { volume = 0.35 })
		end)
		return true
	end
	audio:Play("WoodCreak", camera().CFrame.Position + Vector3.new(random:NextNumber(-6, 6), 9, random:NextNumber(-6, 6)), { volume = 0.5 })
	return true
end

-- A tall shape, drawn on a SurfaceGui (no assets).
local function silhouette(parent: Instance, x: number, transparency: number)
	local figure = Instance.new("Frame")
	figure.Name = "Glimpse"
	figure.BackgroundTransparency = 1
	figure.Size = UDim2.fromScale(1, 1)
	figure.ZIndex = 5
	local body = Instance.new("Frame")
	body.BorderSizePixel = 0
	body.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
	body.BackgroundTransparency = transparency
	body.Position = UDim2.fromScale(x, 0.24)
	body.Size = UDim2.fromScale(0.11, 0.9)
	body.ZIndex = 5
	Instance.new("UICorner", body).CornerRadius = UDim.new(0.4, 0)
	body.Parent = figure
	local head = Instance.new("Frame")
	head.BorderSizePixel = 0
	head.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
	head.BackgroundTransparency = transparency
	head.Position = UDim2.fromScale(x + 0.012, 0.1)
	head.Size = UDim2.fromScale(0.085, 0.14)
	head.ZIndex = 5
	Instance.new("UICorner", head).CornerRadius = UDim.new(0.5, 0)
	head.Parent = figure
	figure.Parent = parent
	return figure
end

local function glimpseMirror(): boolean
	local camPos = camera().CFrame.Position
	for _, mirror in CollectionService:GetTagged("Mirror") do
		local glass = mirror:FindFirstChild("Glass")
		local gui = glass and glass:FindFirstChild("Overlay")
		if glass and gui and glass:IsA("BasePart") and (glass.Position - camPos).Magnitude < 30 and inView(glass.Position, mirror) then
			local figure = silhouette(gui, random:NextNumber(0.25, 0.65), 0.2)
			task.delay(random:NextNumber(0.25, 0.4), function()
				figure:Destroy()
			end)
			return true
		end
	end
	return false
end

local function glimpseScreen(): boolean
	local camPos = camera().CFrame.Position
	for _, screen in CollectionService:GetTagged("Screen") do
		if screen:IsA("BasePart") and screen:IsDescendantOf(Workspace) and (screen.Position - camPos).Magnitude < 24 and inView(screen.Position, screen.Parent) then
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Glimpse"
			gui.Face = Enum.NormalId.Front
			gui.LightInfluence = 0
			gui.Brightness = 1.4
			gui.PixelsPerStud = 40
			local bg = Instance.new("Frame")
			bg.Size = UDim2.fromScale(1, 1)
			bg.BorderSizePixel = 0
			bg.BackgroundColor3 = Color3.fromRGB(14, 18, 16)
			bg.Parent = gui
			local face = Instance.new("Frame")
			face.AnchorPoint = Vector2.new(0.5, 0.5)
			face.Position = UDim2.fromScale(0.5, 0.52)
			face.Size = UDim2.fromScale(0.32, 0.62)
			face.BorderSizePixel = 0
			face.BackgroundColor3 = Color3.fromRGB(196, 200, 190)
			face.BackgroundTransparency = 0.35
			Instance.new("UICorner", face).CornerRadius = UDim.new(0.5, 0)
			face.Parent = bg
			for _, x in { 0.3, 0.7 } do
				local eye = Instance.new("Frame")
				eye.AnchorPoint = Vector2.new(0.5, 0.5)
				eye.Position = UDim2.fromScale(x, 0.4)
				eye.Size = UDim2.fromScale(0.2, 0.12)
				eye.BorderSizePixel = 0
				eye.BackgroundColor3 = Color3.new(0, 0, 0)
				Instance.new("UICorner", eye).CornerRadius = UDim.new(0.5, 0)
				eye.Parent = face
			end
			gui.Parent = screen
			Registry.AudioController:Play("RadioStatic", screen.Position, { volume = 0.4 })
			task.delay(random:NextNumber(0.18, 0.3), function()
				gui:Destroy()
			end)
			return true
		end
	end
	return false
end

local function glimpseWindow(): boolean
	local camPos = camera().CFrame.Position
	for _, window in CollectionService:GetTagged("Window") do
		if window:IsA("Model") and window:IsDescendantOf(Workspace) then
			local pivot = window:GetPivot()
			if (pivot.Position - camPos).Magnitude < 34 and inView(pivot.Position, window) then
				-- outside the glass (the window's back side), standing still
				local shape = Instance.new("Part")
				shape.Name = "Glimpse"
				shape.Anchored = true
				shape.CanCollide = false
				shape.CanQuery = false
				shape.CanTouch = false
				shape.CastShadow = false
				shape.Material = Enum.Material.SmoothPlastic
				shape.Color = Color3.new(0, 0, 0)
				shape.Transparency = 0.1
				shape.Size = Vector3.new(1.3, 8.4, 0.6)
				shape.CFrame = pivot * CFrame.new(random:NextNumber(-1.2, 1.2), 0.4, 4.5)
				shape.Parent = Workspace
				task.delay(random:NextNumber(0.35, 0.55), function()
					shape:Destroy()
				end)
				return true
			end
		end
	end
	return false
end

local function glimpse(): boolean
	local order = { glimpseMirror, glimpseScreen, glimpseWindow }
	for i = #order, 2, -1 do
		local j = random:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for _, fn in order do
		if fn() then
			return true
		end
	end
	return false
end

local function shadow(): boolean
	local cf = camera().CFrame
	local dir = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if dir.Magnitude < 0.1 then
		return false
	end
	dir = dir.Unit
	local dist = random:NextNumber(28, 40)
	local ahead = cf.Position + dir * dist
	if not inView(ahead, nil, 0.5) then
		return false
	end
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local floor = ahead - Vector3.new(0, 4.5, 0)
	Registry.EffectsController:Handle("ShadowRun", { from = floor - side * 6, to = floor + side * 6 })
	return true
end

local function silence()
	Registry.AudioController:Silence(3.5)
	task.delay(random:NextNumber(4, 5), function()
		local cf = camera().CFrame
		local angle = random:NextNumber(0, math.pi * 2)
		Registry.AudioController:Play("Thud", cf.Position + Vector3.new(math.cos(angle) * 45, -6, math.sin(angle) * 45), { volume = 1 })
	end)
end

function ParanoiaController:Run(kind: string)
	if State.status ~= "ALIVE" then
		return
	end
	if kind == "glimpse" then
		if not glimpse() then
			micro()
		end
	elseif kind == "shadow" then
		if not shadow() then
			micro()
		end
	elseif kind == "silence" then
		silence()
	else
		micro()
	end
end

------------------------------------------------------------------------------------
-- Proximity transitions
------------------------------------------------------------------------------------

local LEVEL = { FAR = 1, AWARE = 2, NEAR = 3, VERY_NEAR = 4, HUNT = 5 }

local function onProx()
	local prox = player:GetAttribute("ObserverProx")
	prox = if type(prox) == "string" and LEVEL[prox] then prox else "FAR"
	local was = State.prox
	State.prox = prox
	if State.status ~= "ALIVE" or LEVEL[prox] <= LEVEL[was] then
		return
	end
	local camPos = camera().CFrame.Position
	if prox == "AWARE" then
		Registry.LightController:FlickerNear(camPos, 60, 0.4, 1)
	elseif prox == "NEAR" then
		Registry.LightController:FlickerNear(camPos, 26, random:NextNumber(0.6, 1.1), 3)
		Registry.AudioController:Play("ObserverInhale", behind(random:NextNumber(14, 20)), { volume = 0.45 })
	elseif prox == "VERY_NEAR" then
		Registry.AudioController:Silence(2.5)
	end
end

function ParanoiaController:Start()
	player:GetAttributeChangedSignal("ObserverProx"):Connect(onProx)
	onProx()
	Net.event("Director").OnClientEvent:Connect(function(p)
		if type(p) == "table" and p.cue == "paranoia" and type(p.kind) == "string" then
			ParanoiaController:Run(p.kind)
		end
	end)
end

return ParanoiaController
