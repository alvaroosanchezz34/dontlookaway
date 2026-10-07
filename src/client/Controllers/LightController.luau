--[[
	LightController
	Renders every light fixture from server attributes:
	  Mode      on | flicker | dead     (the fixture's personality)
	  Circuit   MAIN | EMERGENCY        (MAIN needs building power)
	  Override  "off"                   (anomalies / scares force darkness)
	  ForceOn   true                    (anomalies light a fixture without power)
	  Tint      Color3                  (anomalies change the colour)
	Lights far from the camera are disabled locally (light LOD) so the building
	stays fast on phones and consoles; their glowing tubes still read from afar.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local LightController = {}

local LOD_DISTANCE = 95
local EMERGENCY_COLOR = Color3.fromRGB(255, 150, 96)
local DARK = Color3.fromRGB(38, 38, 36)

type Info = { model: Model, light: PointLight?, lamps: { BasePart }, flickerUntil: number, seed: number, lit: boolean, visible: boolean }

local fixtures: { [Model]: Info } = {}
local roomFlicker: { [string]: number } = {}
local random = Random.new()

local function register(model: Instance)
	if not model:IsA("Model") or fixtures[model] then
		return
	end
	local lamps = {}
	local light = nil
	for _, d in model:GetDescendants() do
		if d:IsA("PointLight") then
			light = d
		elseif d:IsA("BasePart") and (d.Name == "Tube" or d.Name == "Tube2" or d.Name == "Bulb") then
			table.insert(lamps, d)
		end
	end
	fixtures[model] = { model = model, light = light, lamps = lamps, flickerUntil = 0, seed = model:GetAttribute("Seed") or random:NextInteger(1, 1000), lit = false, visible = false }
end

local function evaluate(info: Info, camPos: Vector3, now: number)
	local m = info.model
	local mode = m:GetAttribute("Mode")
	local power = Workspace:GetAttribute("Power") == true
	local circuit = m:GetAttribute("Circuit")
	local forceOn = m:GetAttribute("ForceOn") == true
	local override = m:GetAttribute("Override")
	local tint = m:GetAttribute("Tint")
	local base = m:GetAttribute("BaseColor")
	local baseBrightness = m:GetAttribute("BaseBrightness") or 1
	local escape = Workspace:GetAttribute("Escape") == true
	local lit = mode ~= "dead" and override ~= "off" and (forceOn or power or circuit == "EMERGENCY")
	local color = if typeof(tint) == "Color3" then tint elseif typeof(base) == "Color3" then base else Color3.new(1, 1, 1)
	local brightness = baseBrightness
	if lit and not power and not forceOn then
		-- emergency lighting: dim and warm
		color = if typeof(tint) == "Color3" then tint else EMERGENCY_COLOR
		brightness *= 0.42
	end
	if lit and escape then
		-- the building is failing: slow, uneasy pulse
		brightness *= 0.55 + 0.35 * math.sin(now * 2.2 + info.seed)
		if circuit == "EMERGENCY" and typeof(tint) ~= "Color3" then
			color = Color3.fromRGB(255, 110, 90)
		end
	end
	local flickering = lit and (mode == "flicker" or now < info.flickerUntil or (roomFlicker[m:GetAttribute("Room") or ""] or 0) > now)
	if flickering then
		local n = math.noise(now * 9, info.seed * 0.37)
		if n < -0.15 then
			lit = false
		elseif n < 0.05 then
			brightness *= 0.4
		end
	end
	local dist = (m:GetPivot().Position - camPos).Magnitude
	local light = info.light
	if light then
		light.Enabled = lit and dist < LOD_DISTANCE
		light.Color = color
		light.Brightness = brightness
	end
	for _, lamp in info.lamps do
		lamp.Color = if lit then color else DARK
		lamp.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
	end
	info.lit = lit
end

function LightController:FlickerRoom(roomId: string, duration: number)
	roomFlicker[roomId] = os.clock() + duration
end

local function applyPowered()
	local power = Workspace:GetAttribute("Power") == true
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Light") and d:GetAttribute("PoweredLight") then
			d.Enabled = power
		end
	end
	for _, d in CollectionService:GetTagged("Screen") do
		if d:IsA("BasePart") and d:IsDescendantOf(Workspace) then
			d.Material = if power then Enum.Material.Neon else Enum.Material.Glass
			d.Color = if power then Color3.fromRGB(46, 62, 56) else Color3.fromRGB(18, 22, 20)
		end
	end
end

function LightController:Start()
	for _, m in CollectionService:GetTagged("Fixture") do
		register(m)
	end
	CollectionService:GetInstanceAddedSignal("Fixture"):Connect(function(m)
		task.defer(register, m)
	end)
	CollectionService:GetInstanceRemovedSignal("Fixture"):Connect(function(m)
		fixtures[m :: Model] = nil
	end)
	Workspace:GetAttributeChangedSignal("Power"):Connect(applyPowered)
	Workspace:GetAttributeChangedSignal("MapReady"):Connect(function()
		task.wait(0.5)
		applyPowered()
	end)
	Net.event("Director").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.cue == "flicker" and type(payload.room) == "string" then
			self:FlickerRoom(payload.room, payload.duration or 2)
		elseif payload.cue == "sparks" and payload.at then
			Registry.EffectsController:Handle("Sparks", { at = payload.at })
		end
	end)
	-- near fixtures every frame (smooth flicker), far ones a few times a second
	local farAcc = 0
	RunService.RenderStepped:Connect(function(dt)
		local camPos = Workspace.CurrentCamera.CFrame.Position
		local now = os.clock()
		farAcc += dt
		local doFar = farAcc > 0.35
		if doFar then
			farAcc = 0
		end
		for model, info in fixtures do
			if not model.Parent then
				fixtures[model] = nil
			else
				local near = (model:GetPivot().Position - camPos).Magnitude < 60
				if near or doFar then
					evaluate(info, camPos, now)
				end
			end
		end
	end)
	-- ambient random flickers on nearby lights (not every light is stable)
	task.spawn(function()
		while true do
			task.wait(random:NextNumber(4, 10))
			if State.status == "ALIVE" then
				local camPos = Workspace.CurrentCamera.CFrame.Position
				for model, info in fixtures do
					if (model:GetPivot().Position - camPos).Magnitude < 40 and random:NextNumber() < 0.08 then
						info.flickerUntil = os.clock() + random:NextNumber(0.3, 1.2)
						Registry.AudioController:Play("LightFlicker", model:GetPivot().Position)
						break
					end
				end
			end
		end
	end)
end

return LightController
