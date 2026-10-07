--[[
	WorldFXController
	Small local life that sells the building:
	  * every clock shows the same night-time hour (so a wrong one can be spotted)
	  * residents whose "Watching" attribute is set turn their heads to follow you
	  * rocking chairs rock, server LEDs blink, the lobby TV hisses with static
	  * distant lightning in the lobby windows
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local WorldFXController = {}

local clockState: { [Instance]: { mode: string, at: number, frozen: number } } = {}
local rockBase: { [Model]: CFrame } = {}
local random = Random.new()

local NIGHT_START = 3 * 3600 + 17 * 60

local function baseTime(): number
	return NIGHT_START + (Workspace:GetServerTimeNow() % 3600)
end

local function clockSeconds(clock: Instance): number
	local mode = clock:GetAttribute("ClockMode") or "normal"
	local offset = clock:GetAttribute("ClockOffset") or 0
	local st = clockState[clock]
	if not st or st.mode ~= mode then
		st = { mode = mode, at = Workspace:GetServerTimeNow(), frozen = baseTime() + offset }
		clockState[clock] = st
	end
	if mode == "stopped" then
		return st.frozen
	elseif mode == "backwards" then
		return st.frozen - (Workspace:GetServerTimeNow() - st.at) * 1.0
	end
	return baseTime() + offset
end

local function updateClock(clock: Instance)
	local face = clock:FindFirstChild("Face")
	local dial = face and face:FindFirstChild("Dial")
	local plate = dial and dial:FindFirstChild("Plate")
	if not plate then
		return
	end
	local t = clockSeconds(clock)
	local hour = plate:FindFirstChild("Hour") :: Frame?
	local minute = plate:FindFirstChild("Minute") :: Frame?
	local second = plate:FindFirstChild("Second") :: Frame?
	if hour then
		hour.Rotation = ((t / 3600) % 12) * 30
	end
	if minute then
		minute.Rotation = ((t / 60) % 60) * 6
	end
	if second then
		second.Rotation = math.floor(t % 60) * 6
	end
end

local function updateResident(npc: Model, camPos: Vector3)
	local head = npc:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local base = head:GetAttribute("BaseCFrame")
	if typeof(base) ~= "CFrame" then
		return
	end
	local origin = npc:GetAttribute("OriginPivot")
	local offset = if typeof(origin) == "CFrame" then npc:GetPivot() * origin:Inverse() else CFrame.new()
	local headPos = (offset * base).Position
	if npc:GetAttribute("Watching") then
		local dir = camPos - headPos
		if dir.Magnitude > 0.5 then
			head.CFrame = CFrame.lookAt(headPos, camPos) * CFrame.Angles(0, 0, math.rad(8))
		end
	else
		head.CFrame = offset * base
	end
end

function WorldFXController:Start()
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		local camPos = Workspace.CurrentCamera.CFrame.Position
		local now = os.clock()
		-- every frame: watchers & rocking chairs nearby
		for _, npc in CollectionService:GetTagged("Resident") do
			if npc:IsA("Model") and npc:IsDescendantOf(Workspace) and npc:GetAttribute("Watching") ~= nil then
				if (npc:GetPivot().Position - camPos).Magnitude < 90 then
					updateResident(npc, camPos)
				end
			end
		end
		for _, chair in CollectionService:GetTagged("Chair") do
			if chair:IsA("Model") and chair:GetAttribute("Rocking") and chair:IsDescendantOf(Workspace) then
				local base = rockBase[chair]
				if not base then
					base = chair:GetPivot()
					rockBase[chair] = base
				end
				if (base.Position - camPos).Magnitude < 50 then
					chair:PivotTo(base * CFrame.new(0, 0, 0) * CFrame.Angles(math.sin(now * 1.3) * 0.07, 0, 0))
				end
			end
		end
		if acc < 0.25 then
			return
		end
		acc = 0
		for _, clock in CollectionService:GetTagged("Clock") do
			if clock:IsDescendantOf(Workspace) then
				local face = clock:FindFirstChild("Face")
				if face and face:IsA("BasePart") and (face.Position - camPos).Magnitude < 70 then
					updateClock(clock)
				end
			end
		end
		for _, led in CollectionService:GetTagged("BlinkLED") do
			if led:IsA("BasePart") and random:NextNumber() < 0.2 then
				led.Transparency = if led.Transparency > 0.5 then 0 else 0.85
			end
		end
		for _, screen in CollectionService:GetTagged("StaticScreen") do
			if screen:IsA("BasePart") then
				local v = random:NextInteger(40, 110)
				screen.Color = Color3.fromRGB(v, v, v + 6)
			end
		end
	end)
	-- lobby lightning
	task.spawn(function()
		while true do
			task.wait(random:NextNumber(14, 34))
			if State.status == "LOBBY" or State.status == "MENU" then
				local strength = if State.settings.reducedEffects then 0.6 else 2.4
				for _, l in CollectionService:GetTagged("Lightning") do
					if l:IsA("PointLight") then
						l.Brightness = strength
						task.delay(0.08, function()
							l.Brightness = 0
							task.wait(0.1)
							l.Brightness = strength * 0.6
							task.wait(0.07)
							l.Brightness = 0
						end)
					end
				end
				task.delay(random:NextNumber(1.2, 3), function()
					Registry.AudioController:Play("DistantMetal", nil, { volume = 0.8 })
				end)
			end
		end
	end)
	-- rebuilt maps: forget stale rocking chair bases
	Workspace:GetAttributeChangedSignal("MapReady"):Connect(function()
		rockBase = {}
		clockState = {}
	end)
end

return WorldFXController
