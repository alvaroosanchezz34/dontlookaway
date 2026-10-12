--[[
	DistortionController
	What a reality distortion looks and sounds like for the one player living
	it (Server/DistortionService decides everything; this only paints).

	Cues (Net "Distortion", each with the run's token):
	  break    the building stutters: the lamps near you flicker, the sound
	           drops out, the view tilts a hair, then a cut to black
	  arrive   you are facing down a corridor that cannot exist; the picture
	           fades back in. Its lamps are driven here: a fluorescent hum
	           that never quite holds still, a few dead, and the dark (the
	           corridor's DarkFrom) eating them from the far end
	  notice   the lamps far away, around what stands there, sag once
	  wake     a jolt; the dark arrives where it stands
	  chase    the run: lamps near you start to stutter late in it
	           (the corridor's Stutter), the view widens a touch
	  taken    a jolt and a glitch (no flashing with reduced effects)
	  exit     an instant cut to black, the sound gone (the server moves you)
	  return   you are back where you stood, facing where you faced; the
	           picture comes back. Nothing is said about what happened.
	The objectives and the team fade while it lasts (HUD quiet). A watchdog
	puts everything back if the return never arrives.

	It also tells the server when a menu, a puzzle or a note is open
	(ClientFlag "busy"): a distortion never takes someone mid-read.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local DistortionController = {}

local player = Players.LocalPlayer
local token: number? = nil
local hall: Model? = nil
local savedYaw, savedPitch = 0, 0
local lampList: { { model: Model, tube: BasePart, light: PointLight, z: number, dead: boolean, spot: boolean, seed: number, flickerUntil: number } } = {}
local drive: RBXScriptConnection? = nil
-- a total blackout (level 4): only the red emergency tubes, pulsing slowly
local TUBE_ON = Color3.fromRGB(255, 72, 58)
local LIGHT_RED = Color3.fromRGB(255, 84, 66)
local TUBE_OFF = Color3.fromRGB(40, 42, 40)
-- the one white tube left, over where it waits
local SPOT = Color3.fromRGB(228, 234, 255)
local EYES = Color3.fromRGB(255, 238, 228)
local LIGHT_RANGE = 90 -- lamps further than this stay off (cheap at any quality)

local function reduced(): boolean
	return State.settings.reducedEffects == true
end

local function collectLamps(h: Model)
	table.clear(lampList)
	local folder = h:FindFirstChild("Lamps")
	if not folder then
		return
	end
	for _, lamp in folder:GetChildren() do
		local tube = lamp:FindFirstChild("Tube") :: BasePart?
		local light = tube and tube:FindFirstChild("Light") :: PointLight?
		if lamp:IsA("Model") and tube and light then
			table.insert(lampList, {
				model = lamp,
				tube = tube,
				light = light,
				z = lamp:GetAttribute("Z") or 0,
				dead = lamp:GetAttribute("Dead") == true,
				spot = lamp:GetAttribute("Spot") == true,
				seed = (lamp:GetAttribute("Index") or 1) * 17.3,
				flickerUntil = 0,
			})
		end
	end
end

local function observerPosition(): Vector3?
	for _, o in game:GetService("CollectionService"):GetTagged("Observer") do
		if o:IsA("Model") and o:IsDescendantOf(Workspace) then
			return o:GetPivot().Position
		end
	end
	return nil
end

-- The corridor's lamps, every frame (near ones only).
local function paint()
	local h = hall
	if not h or not h.Parent then
		return
	end
	local camPos = Workspace.CurrentCamera.CFrame.Position
	local darkFrom = h:GetAttribute("DarkFrom") or -1e6
	local stutter = h:GetAttribute("Stutter") == true
	local now = os.clock()
	local calm = reduced()
	local obs = observerPosition()
	for _, lamp in lampList do
		local pos = lamp.tube.Position
		local dist = (pos - camPos).Magnitude
		local lit = not lamp.dead and lamp.z > darkFrom
		local b = 0.9
		if lit then
			-- the emergency pulse of a total blackout (under 1 Hz with reduced
			-- effects, never a flash)
			b *= 0.68 + 0.32 * math.sin(now * (if calm then 0.8 else 2.2) + lamp.seed)
			-- and never perfectly still
			if not calm then
				b *= 0.95 + 0.05 * math.noise(now * 3, lamp.seed)
				if math.noise(now * 0.7, lamp.seed + 9) > 0.62 then
					b *= 0.55
				end
			end
			-- late in the run the lamps near you stutter
			if stutter and not calm and dist < 26 and math.noise(now * 8, lamp.seed * 0.3) < -0.4 then
				lit = false
			end
			if now < lamp.flickerUntil then
				if calm then
					b *= 0.5
				elseif math.noise(now * 12, lamp.seed) < -0.1 then
					lit = false
				end
			end
			-- the light is its: lamps near it sag
			if obs then
				local r = (pos - obs).Magnitude
				if r < 22 then
					b *= 0.35 + 0.65 * (r / 22) ^ 2
				end
			end
		end
		if lamp.spot and lit then
			-- the last white tube: bright enough to show what stands under it,
			-- and failing (a buzzing flicker, never a strobe)
			local f = if calm then 1 else (if math.noise(now * 6, 3.7) < -0.3 then 0.35 else 1)
			lamp.light.Enabled = dist < LIGHT_RANGE * 1.5
			lamp.light.Brightness = 2.2 * f
			lamp.light.Range = 24
			lamp.light.Color = SPOT
			lamp.tube.Material = Enum.Material.Neon
			lamp.tube.Color = SPOT
		else
			lamp.light.Enabled = lit and dist < LIGHT_RANGE
			lamp.light.Brightness = b
			lamp.light.Color = LIGHT_RED
			lamp.tube.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
			lamp.tube.Color = if lit then TUBE_ON else TUBE_OFF
		end
	end
end

-- the picture of a total blackout: darker and tinted by the red light
local grade: ColorCorrectionEffect? = nil
local function setGrade(on: boolean)
	if on then
		if not grade or not grade.Parent then
			local g = Instance.new("ColorCorrectionEffect")
			g.Name = "DistortionGrade"
			g.Brightness = -0.03
			g.Contrast = 0.06
			g.Saturation = -0.25
			g.TintColor = Color3.fromRGB(255, 212, 206)
			g.Parent = game:GetService("Lighting")
			grade = g
		end
	elseif grade then
		grade:Destroy()
		grade = nil
	end
end

------------------------------------------------------------------------------------
-- It: seen (its eyes), heard (steps, breath), and felt (the frenzy)
------------------------------------------------------------------------------------

local function observerModel(): Model?
	for _, o in game:GetService("CollectionService"):GetTagged("Observer") do
		if o:IsA("Model") and o:IsDescendantOf(Workspace) then
			return o
		end
	end
	return nil
end

-- its eyes burn pale in the dark (on this screen only; put back after)
local eyeSaved: { [BasePart]: { color: Color3, material: any } } = {}
local function lightEyes(on: boolean)
	if on then
		local m = observerModel()
		if not m then
			return
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and (string.find(d.Name, "Eyeball") or d.Name == "Iris") and not eyeSaved[d] then
				eyeSaved[d] = { color = d.Color, material = d.Material }
				d.Color = EYES
				d.Material = Enum.Material.Neon
			end
		end
	else
		for part, saved in eyeSaved do
			if part.Parent then
				part.Color = saved.color
				part.Material = saved.material
			end
		end
		table.clear(eyeSaved)
	end
end

-- the red at the edges of your sight, closing in with it
local fxGui: ScreenGui? = nil
local edges: { Frame } = {}
local function setEdges(on: boolean)
	if on and not fxGui then
		local g = Instance.new("ScreenGui")
		g.Name = "DistortionFX"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 2
		g.Parent = player:WaitForChild("PlayerGui")
		fxGui = g
		table.clear(edges)
		local specs = {
			{ 0, UDim2.fromScale(0.22, 1), UDim2.fromScale(0, 0), Vector2.zero },
			{ 180, UDim2.fromScale(0.22, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0) },
			{ 90, UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), Vector2.zero },
			{ -90, UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 1), Vector2.new(0, 1) },
		}
		for _, spec in specs do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = Color3.fromRGB(110, 0, 0)
			f.BackgroundTransparency = 1
			f.Size = spec[2]
			f.Position = spec[3]
			f.AnchorPoint = spec[4]
			local grad = Instance.new("UIGradient")
			grad.Rotation = spec[1]
			grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			grad.Parent = f
			f.Parent = g
			table.insert(edges, f)
		end
	elseif not on and fxGui then
		fxGui:Destroy()
		fxGui = nil
		table.clear(edges)
	end
end

local frenzy = { lastPos = nil :: Vector3?, stepAcc = 0, nextBreath = 0, nextWhisper = 0, nextGlitch = 0 }

-- Every frame of the run: its steps as it moves, its breath when near, the
-- view widening, the red closing in, the sight of it fraying up close.
local function frenzyStep()
	local phase = State.distortionPhase
	local m = observerModel()
	if not m or (phase ~= "wake" and phase ~= "chase") then
		for _, f in edges do
			f.BackgroundTransparency = 1
		end
		frenzy.lastPos = nil
		return
	end
	local now = os.clock()
	local calm = reduced()
	local cam = Workspace.CurrentCamera.CFrame
	local at = m:GetPivot().Position
	local d = (at - cam.Position).Magnitude
	local k = math.clamp(1 - d / 50, 0, 1)
	-- its steps: one every few studs it moves, heavier the nearer
	if frenzy.lastPos then
		local moved = Vector3.new(at.X - frenzy.lastPos.X, 0, at.Z - frenzy.lastPos.Z).Magnitude
		frenzy.stepAcc += moved
		if frenzy.stepAcc >= 3.4 then
			frenzy.stepAcc = 0
			Registry.AudioController:Play("ObserverStep", at, { volume = 1.3 + 0.9 * k })
			if d < 32 then
				Registry.CameraController:Shake((if calm then 0.01 else 0.035) + (if calm then 0.02 else 0.08) * k)
			end
		end
	end
	frenzy.lastPos = at
	-- its breath when it is close
	if d < 32 and now >= frenzy.nextBreath then
		frenzy.nextBreath = now + 2.2 + 1.2 * (d / 32)
		Registry.AudioController:Play("ObserverBreath", at + Vector3.new(0, 7, 0), { volume = 1.2 })
	end
	-- something whispering right behind you
	if d < 22 and now >= frenzy.nextWhisper then
		frenzy.nextWhisper = now + 6 + math.random() * 4
		Registry.AudioController:Play("Whisper", cam.Position - cam.LookVector * 4 + Vector3.new(0, 1, 0), { volume = 1 })
	end
	-- the sight of it frays up close
	if d < 11 and not calm and now >= frenzy.nextGlitch then
		frenzy.nextGlitch = now + 1.3
		Registry.EffectsController:Glitch(0.25, 0.1)
	end
	-- the view widens as you run from it; the red closes in with it (the
	-- pulse stays under ~1 Hz, and is steady with reduced effects)
	Registry.CameraController:SetFovEffect(2 + 7 * k)
	local pulse = if calm then 1 else 0.78 + 0.22 * math.sin(now * (2 + 4 * k))
	local alpha = (0.1 + 0.5 * k) * pulse
	for _, f in edges do
		f.BackgroundTransparency = 1 - alpha
	end
end

local function stopDriving()
	if drive then
		drive:Disconnect()
		drive = nil
	end
	table.clear(lampList)
	hall = nil
end

-- Everything back as it was before the break.
local function restore(fadeIn: boolean)
	stopDriving()
	setGrade(false)
	setEdges(false)
	lightEyes(false)
	frenzy.lastPos = nil
	State.distortion = nil
	State.distortionPhase = nil
	Registry.CameraController:SetYawPitch(savedYaw, savedPitch)
	Registry.CameraController:SetFovEffect(0)
	if Registry.HUDController.SetQuiet then
		Registry.HUDController:SetQuiet(false)
	end
	if fadeIn then
		Registry.EffectsController:Fade(0, 0.9)
	end
	token = nil
end

local handlers = {}

handlers["break"] = function(p)
	token = p.token
	savedYaw, savedPitch = Registry.CameraController:GetYawPitch()
	Registry.HUDController:SetQuiet(true)
	local camPos = Workspace.CurrentCamera.CFrame.Position
	Registry.LightController:FlickerNear(camPos, 24, 0.55, 4)
	Registry.AudioController:Silence(1.2)
	Registry.AudioController:Play("RealityShift", nil, { volume = 0.25 })
	Registry.CameraController:Shake(0.05)
	task.delay(0.5, function()
		if token == p.token then
			Registry.EffectsController:Fade(1, 0.12)
		end
	end)
end

handlers.arrive = function(p)
	State.distortion = p.id
	State.distortionPhase = "arrive"
	setGrade(true)
	local h = p.hall
	if typeof(h) ~= "Instance" then
		h = Workspace:WaitForChild("ImpossibleHallway", 3)
	end
	if h and h:IsA("Model") then
		hall = h
		collectLamps(h)
		if drive then
			drive:Disconnect()
		end
		drive = RunService.RenderStepped:Connect(function()
			pcall(paint)
			pcall(frenzyStep)
		end)
	end
	setEdges(true)
	-- its eyes, once it is there (it is placed just before this cue)
	task.delay(0.2, function()
		if State.distortion then
			lightEyes(true)
		end
	end)
	-- face down the corridor (computed from the direction: the camera has
	-- not moved yet this frame)
	if typeof(p.look) == "Vector3" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local from = if root then root.Position else Workspace.CurrentCamera.CFrame.Position
		local dir = Vector3.new(p.look.X - from.X, 0, p.look.Z - from.Z)
		if dir.Magnitude > 0.1 then
			dir = dir.Unit
			Registry.CameraController:SetYawPitch(math.atan2(-dir.X, -dir.Z), 0)
		end
	end
	Registry.EffectsController:Fade(0, 1.4)
end

handlers.notice = function()
	State.distortionPhase = "notice"
	lightEyes(true)
	local obs = observerPosition()
	if not obs then
		return
	end
	-- a long, slow breath from the far end
	Registry.AudioController:Play("ObserverBreath", obs + Vector3.new(0, 7, 0), { volume = 1.4 })
	for _, lamp in lampList do
		if (lamp.tube.Position - obs).Magnitude < 26 then
			lamp.flickerUntil = os.clock() + 0.6
		end
	end
end

handlers.wake = function()
	State.distortionPhase = "wake"
	Registry.CameraController:Shake(if reduced() then 0.08 else 0.3)
	local obs = observerPosition()
	if obs then
		-- it screams; the last white tube bursts over it
		Registry.AudioController:Play("ObserverScreech", obs + Vector3.new(0, 7, 0), { volume = 1.6 })
		for _, lamp in lampList do
			if lamp.spot then
				Registry.AudioController:Play("BulbPop", lamp.tube.Position, { volume = 1.3 })
				Registry.EffectsController:Handle("Sparks", { at = lamp.tube.Position })
			end
		end
	end
end

handlers.chase = function()
	State.distortionPhase = "chase"
	Registry.CameraController:SetFovEffect(2)
end

handlers.taken = function()
	State.distortionPhase = "taken"
	Registry.CameraController:Shake(if reduced() then 0.1 else 0.5)
	if not reduced() then
		Registry.EffectsController:Glitch(0.8, 0.4)
	end
	Registry.AudioController:Play("ObserverScreech", nil, { volume = 0.7 })
end

handlers.exit = function()
	-- an instant cut: the move back happens behind it
	Registry.EffectsController:Fade(1, 0.08)
	Registry.AudioController:Silence(0.8)
end

handlers["return"] = function()
	restore(true)
end

function DistortionController:IsActive(): boolean
	return State.distortion ~= nil
end

-- Tests: the lamps being driven.
function DistortionController:Lamps()
	return lampList
end

function DistortionController:Start()
	Net.event("Distortion").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" or type(p.cue) ~= "string" then
			return
		end
		-- a cue from an earlier run (or for nobody) is ignored, except the
		-- return, which always puts things back
		if p.cue ~= "break" and p.cue ~= "return" and p.token ~= token then
			return
		end
		local fn = handlers[p.cue]
		if fn then
			local ok, err = pcall(fn, p)
			if not ok then
				warn("[DistortionController] " .. p.cue .. ": " .. tostring(err))
			end
		end
	end)
	-- the watchdog: the server cleared the player's distortion but the
	-- return never arrived: put everything back anyway
	player:GetAttributeChangedSignal("Distortion"):Connect(function()
		if player:GetAttribute("Distortion") == nil and (State.distortion ~= nil or token ~= nil) then
			task.delay(1.5, function()
				if player:GetAttribute("Distortion") == nil and (State.distortion ~= nil or token ~= nil) then
					restore(true)
				end
			end)
		end
	end)
	-- leaving the round (death, results) never leaves the picture black
	State.StatusChanged:Connect(function()
		if State.status ~= "ALIVE" and (State.distortion ~= nil or token ~= nil) then
			restore(true)
		end
	end)
	-- a menu, a puzzle or a note open: never taken mid-read
	State.UIOpenChanged:Connect(function(open)
		Net.event("ClientFlag"):FireServer("busy", open == true)
	end)
end

return DistortionController
