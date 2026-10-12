--[[
	MenuLook
	The main menu's light. Between rounds the building has no power and the
	menu's camera drifts through it (MenuController's shots), so the menu was
	a near-black screen. While the player is in the menu (State.status ==
	"MENU"), and only on their screen:

	  * the look: VisualStandards.MenuLook (a dim grey ambient, a little more
	    exposure, the cold near-monochrome grade) over whatever the server's
	    preset is; the server's own values are restored on leaving;
	  * practical lights for the shots, so the light has a source you can see:
	    bare bulbs on their cords that sway a little and breathe, dim and warm,
	    with shadows; a cold shaft of moonlight slanting into the reception;
	    a battery emergency lamp glowing amber on the basement wall. They exist
	    only while the menu is open.

	  * a presence, barely: now and then (never on a schedule you could
	    learn) a dark figure stands far down the shot for a few seconds, so
	    faint you are not sure it was there. Never with reduced effects.

	Nothing is replicated and nothing the server owns is changed for good.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VisualStandards = require(ReplicatedStorage.Shared.VisualStandards)
local State = require(script.Parent.Parent.State)

local MenuLook = {}

-- where the bulbs hang for the menu's shots (MenuController.SHOTS): the
-- reception, the main corridor, the basement corridor, the portrait gallery
local BULBS = {
	{ at = Vector3.new(70, 9.6, 68), brightness = 0.7 },
	{ at = Vector3.new(68, 9.8, 44), brightness = 0.65 },
	{ at = Vector3.new(112, 9.8, 44), brightness = 0.35 },
	{ at = Vector3.new(96, -8.2, 44), brightness = 0.6 },
	{ at = Vector3.new(66, -8.2, 44), brightness = 0.3 },
	{ at = Vector3.new(134, 27.6, 16), brightness = 0.6 },
}
local BULB_COLOR = Color3.fromRGB(236, 224, 204)
-- moonlight through the reception's front windows, slanting down onto the floor
local MOON = { from = Vector3.new(80, 12, 102), to = Vector3.new(74, 0, 84), color = Color3.fromRGB(150, 172, 210), brightness = 0.9 }
-- a battery emergency lamp on the basement corridor's wall
local EMERGENCY = { at = Vector3.new(84, -8.6, 40.6), face = Vector3.new(0, 0, 1), color = Color3.fromRGB(255, 176, 120), brightness = 0.45 }
local CORD = 2.4

local PROPS = { "Ambient", "OutdoorAmbient", "ExposureCompensation" }

local active = false
local folder: Folder? = nil
local grade: ColorCorrectionEffect? = nil
local bulbs: { { part: BasePart, light: PointLight, anchor: Vector3, phase: number, base: number } } = {}
local serverValues: { [string]: any } = {}
local writing = false

local function look()
	return VisualStandards.MenuLook
end

local function writeLook()
	local L = look()
	writing = true
	Lighting.Ambient = L.ambient
	Lighting.OutdoorAmbient = L.outdoorAmbient
	Lighting.ExposureCompensation = L.exposure
	writing = false
end

local function restore()
	writing = true
	for _, prop in PROPS do
		if serverValues[prop] ~= nil then
			(Lighting :: any)[prop] = serverValues[prop]
		end
	end
	writing = false
end

local function buildBulbs()
	local f = Instance.new("Folder")
	f.Name = "MenuLights"
	for i, b in BULBS do
		local part = Instance.new("Part")
		part.Name = "MenuBulb"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(0.45, 0.45, 0.45)
		part.Material = Enum.Material.Neon
		part.Color = BULB_COLOR
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = CFrame.new(b.at)
		part.Parent = f
		local cord = Instance.new("Part")
		cord.Name = "Cord"
		cord.Size = Vector3.new(0.05, CORD, 0.05)
		cord.Material = Enum.Material.Rubber
		cord.Color = Color3.fromRGB(16, 16, 16)
		cord.Anchored = true
		cord.CanCollide = false
		cord.CanQuery = false
		cord.CanTouch = false
		cord.CastShadow = false
		cord.Parent = part
		local light = Instance.new("PointLight")
		light.Color = BULB_COLOR
		light.Range = 16
		light.Brightness = b.brightness
		light.Shadows = true
		light.Parent = part
		table.insert(bulbs, { part = part, light = light, anchor = b.at + Vector3.new(0, CORD, 0), phase = i * 1.7, base = b.brightness })
	end
	-- the moon's shaft (it casts shadows, so it stays inside the room)
	local moonHolder = Instance.new("Part")
	moonHolder.Name = "MenuMoon"
	moonHolder.Size = Vector3.new(0.2, 0.2, 0.2)
	moonHolder.Transparency = 1
	moonHolder.Anchored = true
	moonHolder.CanCollide = false
	moonHolder.CanQuery = false
	moonHolder.CanTouch = false
	moonHolder.CFrame = CFrame.lookAt(MOON.from, MOON.to)
	moonHolder.Parent = f
	local moon = Instance.new("SpotLight")
	moon.Face = Enum.NormalId.Front
	moon.Angle = 28
	moon.Range = 26
	moon.Brightness = MOON.brightness
	moon.Color = MOON.color
	moon.Shadows = true
	moon.Parent = moonHolder
	-- the emergency lamp: a small glowing box on the wall, a warm, weak light
	local box = Instance.new("Part")
	box.Name = "MenuEmergencyLamp"
	box.Size = Vector3.new(1.6, 0.5, 0.3)
	box.Material = Enum.Material.Neon
	box.Color = EMERGENCY.color
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.CFrame = CFrame.lookAt(EMERGENCY.at, EMERGENCY.at + EMERGENCY.face)
	box.Parent = f
	local glow = Instance.new("SpotLight")
	glow.Face = Enum.NormalId.Front
	glow.Angle = 120
	glow.Range = 14
	glow.Brightness = EMERGENCY.brightness
	glow.Color = EMERGENCY.color
	glow.Shadows = true
	glow.Parent = box
	f.Parent = Workspace
	folder = f
end

local function enter()
	if active then
		return
	end
	active = true
	for _, prop in PROPS do
		serverValues[prop] = (Lighting :: any)[prop]
	end
	writeLook()
	local L = look()
	local g = Instance.new("ColorCorrectionEffect")
	g.Name = "MenuGrade"
	g.Brightness = L.cc.Brightness
	g.Contrast = L.cc.Contrast
	g.Saturation = L.cc.Saturation
	g.TintColor = L.cc.TintColor
	g.Parent = Lighting
	grade = g
	buildBulbs()
end

-- the presence: far down the view, on the floor, fading in and out
local random = Random.new()
local nextPresenceAt = os.clock() + random:NextNumber(25, 50)

local function presence()
	local camera = Workspace.CurrentCamera
	if not camera or not folder then
		return
	end
	local cf = camera.CFrame
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if flat.Magnitude < 0.3 then
		return
	end
	flat = flat.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder :: Instance }
	local want = random:NextNumber(26, 40)
	local hit = Workspace:Raycast(cf.Position, flat * want, params)
	local dist = if hit then hit.Distance - 3 else want
	if dist < 20 then
		return
	end
	local spot = cf.Position + flat * dist + Vector3.new(-flat.Z, 0, flat.X) * random:NextNumber(-3, 3)
	local ground = Workspace:Raycast(spot + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	if not ground then
		return
	end
	local base = ground.Position
	local face = CFrame.lookAt(base, Vector3.new(cf.Position.X, base.Y, cf.Position.Z))
	local parts = {}
	for _, spec in { { Vector3.new(1.3, 5.4, 0.6), 2.7 }, { Vector3.new(0.8, 1.1, 0.7), 5.95 } } do
		local p = Instance.new("Part")
		p.Name = "MenuPresence"
		p.Size = spec[1]
		p.CFrame = face * CFrame.new(0, spec[2], 0)
		p.Color = Color3.fromRGB(8, 8, 9)
		p.Material = Enum.Material.Fabric
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Parent = folder
		table.insert(parts, p)
	end
	local TweenService = game:GetService("TweenService")
	for _, p in parts do
		TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { Transparency = 0.2 }):Play()
	end
	task.delay(1.6 + random:NextNumber(1.8, 3), function()
		for _, p in parts do
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(1.8, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
			end
		end
		task.delay(2, function()
			for _, p in parts do
				p:Destroy()
			end
		end)
	end)
end

local function leave()
	if not active then
		return
	end
	active = false
	restore()
	if grade then
		grade:Destroy()
		grade = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(bulbs)
end

function MenuLook:IsActive(): boolean
	return active
end

function MenuLook:Refresh()
	if State.status == "MENU" then
		enter()
	else
		leave()
	end
end

function MenuLook:Start()
	-- what the server sets while the menu is open is remembered (and restored
	-- on leaving); the menu's own look is put back over it
	for _, prop in PROPS do
		Lighting:GetPropertyChangedSignal(prop):Connect(function()
			if writing then
				return
			end
			serverValues[prop] = (Lighting :: any)[prop]
			if active then
				writeLook()
			end
		end)
	end
	State.StatusChanged:Connect(function()
		self:Refresh()
	end)
	self:Refresh()
	RunService.RenderStepped:Connect(function()
		if not active then
			return
		end
		local t = os.clock()
		if t >= nextPresenceAt then
			nextPresenceAt = t + random:NextNumber(45, 110)
			if not State.settings.reducedEffects then
				pcall(presence)
			end
		end
		for _, b in bulbs do
			-- a bare bulb on its cord: a slow sway, a light that breathes
			local swing = CFrame.Angles(math.sin(t * 0.7 + b.phase) * 0.06, 0, math.cos(t * 0.53 + b.phase) * 0.05)
			local cf = CFrame.new(b.anchor) * swing * CFrame.new(0, -CORD, 0)
			b.part.CFrame = cf
			local cord = b.part:FindFirstChild("Cord") :: BasePart?
			if cord then
				cord.CFrame = CFrame.new(b.anchor) * swing * CFrame.new(0, -CORD / 2, 0)
			end
			b.light.Brightness = b.base * (0.9 + 0.1 * math.noise(t * 0.8, b.phase))
		end
	end)
end

return MenuLook
