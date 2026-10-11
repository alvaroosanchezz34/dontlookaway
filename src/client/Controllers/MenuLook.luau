--[[
	MenuLook
	The main menu's light. Between rounds the building has no power and the
	menu's camera drifts through it (MenuController's shots), so the menu was
	a near-black screen. While the player is in the menu (State.status ==
	"MENU"), and only on their screen:

	  * the look: VisualStandards.MenuLook (a dim grey ambient, a little more
	    exposure, the cold near-monochrome grade) over whatever the server's
	    preset is; the server's own values are restored on leaving;
	  * practical lights for each shot, so the light has a source you can see:
	    a bare bulb on its cord that sways a little and breathes, dim and warm,
	    with shadows. They exist only while the menu is open.

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
