--[[
	EquipmentModels
	Small procedural models of every piece of equipment, built from parts. Used
	for the 3D previews in the shop and for the tool you hold in first person.
	Each model is centred on its pivot, roughly 1-2 studs long, front = -Z.
]]

local Equipment = require(script.Parent.Catalog.Equipment)

local EquipmentModels = {}

local M = Enum.Material

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function cylinder(model, name, length, diameter, cf, color, material)
	-- cylinders lie along X; rotate so the length runs along -Z
	return part(model, name, Vector3.new(length, diameter, diameter), cf * CFrame.Angles(0, math.rad(90), 0), color, material, Enum.PartType.Cylinder)
end

local BUILDERS = {}

BUILDERS.FLASHLIGHT = function(model, item)
	local body = ({
		FL_STARTER = Color3.fromRGB(40, 40, 42),
		FL_INDUSTRIAL = Color3.fromRGB(176, 140, 50),
		FL_TACTICAL = Color3.fromRGB(28, 30, 28),
		FL_ADVANCED = Color3.fromRGB(150, 156, 162),
		FL_PROTOTYPE = Color3.fromRGB(196, 170, 120),
	})[item.id] or Color3.fromRGB(40, 40, 42)
	local length = 1.2 + (item.range - 46) / 40
	cylinder(model, "Body", length, 0.28, CFrame.new(0, 0, 0), body, M.Metal)
	cylinder(model, "Head", 0.35, 0.42, CFrame.new(0, 0, -length / 2 - 0.15), body:Lerp(Color3.new(0, 0, 0), 0.2), M.Metal)
	local lens = cylinder(model, "Lens", 0.04, 0.36, CFrame.new(0, 0, -length / 2 - 0.34), Color3.fromRGB(255, 240, 210), M.Neon)
	lens.Transparency = 0.15
	part(model, "Switch", Vector3.new(0.12, 0.08, 0.2), CFrame.new(0, 0.15, 0.1), Color3.fromRGB(20, 20, 20))
	if item.rarity == "RARE" or item.rarity == "EPIC" or item.rarity == "LEGENDARY" then
		for i = -1, 1 do
			part(model, "Grip", Vector3.new(0.31, 0.04, 0.05), CFrame.new(0, 0, 0.2 + i * 0.12), Color3.fromRGB(20, 20, 20), M.Rubber)
		end
	end
end

BUILDERS.BATTERY = function(model, item)
	local scale = (item.capacity or 100) / 100
	local color = ({ BAT_STANDARD = Color3.fromRGB(150, 160, 150), BAT_EXTENDED = Color3.fromRGB(110, 150, 120), BAT_HIGH = Color3.fromRGB(110, 130, 170) })[item.id] or Color3.fromRGB(150, 160, 150)
	cylinder(model, "Cell", 0.9 * scale, 0.42, CFrame.new(), color, M.Metal)
	cylinder(model, "Cap", 0.08, 0.2, CFrame.new(0, 0, -0.45 * scale - 0.04), Color3.fromRGB(200, 200, 196), M.Metal)
	part(model, "Label", Vector3.new(0.43, 0.2, 0.5 * scale), CFrame.new(0, 0.02, 0), Color3.fromRGB(230, 226, 214))
end

BUILDERS.GLOWSTICKS = function(model)
	for i = -1, 1 do
		local stick = part(model, "Stick", Vector3.new(0.16, 0.16, 1.1), CFrame.new(i * 0.2, 0, 0) * CFrame.Angles(0, math.rad(i * 8), 0), Color3.fromRGB(150, 255, 170), M.Neon)
		stick.Transparency = 0.1
	end
end

BUILDERS.SPARE_CELL = function(model)
	BUILDERS.BATTERY(model, Equipment.get("BAT_STANDARD"))
end

BUILDERS.FIELD_RADIO = function(model)
	part(model, "Body", Vector3.new(0.6, 1.1, 0.3), CFrame.new(), Color3.fromRGB(46, 50, 44), M.Plastic)
	part(model, "Antenna", Vector3.new(0.06, 0.7, 0.06), CFrame.new(0.2, 0.85, 0), Color3.fromRGB(20, 20, 20), M.Rubber)
	part(model, "Speaker", Vector3.new(0.45, 0.4, 0.04), CFrame.new(0, 0.2, -0.16), Color3.fromRGB(30, 32, 30), M.DiamondPlate)
	local led = part(model, "LED", Vector3.new(0.08, 0.08, 0.04), CFrame.new(-0.18, 0.45, -0.16), Color3.fromRGB(120, 230, 140), M.Neon)
	led.Transparency = 0.1
end

BUILDERS.MOTION_SENSOR = function(model)
	part(model, "Base", Vector3.new(0.9, 0.3, 0.9), CFrame.new(), Color3.fromRGB(40, 44, 46), M.Metal)
	part(model, "Eye", Vector3.new(0.3, 0.12, 0.3), CFrame.new(0, 0.2, 0), Color3.fromRGB(90, 220, 120), M.Neon)
	for _, s in { -1, 1 } do
		part(model, "Leg", Vector3.new(0.08, 0.2, 0.7), CFrame.new(s * 0.5, -0.12, 0), Color3.fromRGB(20, 20, 20), M.Metal)
	end
end

BUILDERS.INSTANT_CAMERA = function(model)
	part(model, "Body", Vector3.new(1.1, 0.8, 0.6), CFrame.new(), Color3.fromRGB(226, 222, 210), M.SmoothPlastic)
	cylinder(model, "Lens", 0.25, 0.42, CFrame.new(0, -0.05, -0.38), Color3.fromRGB(30, 30, 32), M.Glass)
	part(model, "Flash", Vector3.new(0.35, 0.18, 0.04), CFrame.new(0.3, 0.25, -0.31), Color3.fromRGB(240, 240, 240), M.Glass)
	part(model, "Slot", Vector3.new(0.8, 0.05, 0.3), CFrame.new(0, -0.42, 0), Color3.fromRGB(30, 30, 32))
end

BUILDERS.RESONANCE_METER = function(model)
	part(model, "Body", Vector3.new(0.7, 1.2, 0.3), CFrame.new(), Color3.fromRGB(70, 60, 50), M.Plastic)
	part(model, "Display", Vector3.new(0.5, 0.35, 0.04), CFrame.new(0, 0.3, -0.16), Color3.fromRGB(30, 40, 30), M.Glass)
	for i = 1, 5 do
		local bar = part(model, "Bar" .. i, Vector3.new(0.07, 0.05 + i * 0.04, 0.03), CFrame.new(-0.2 + (i - 1) * 0.1, 0.22 + i * 0.02, -0.18), Color3.fromRGB(60, 70, 60), M.Neon)
		bar:SetAttribute("Bar", i)
	end
	part(model, "Probe", Vector3.new(0.12, 0.12, 0.6), CFrame.new(0, 0.55, -0.2), Color3.fromRGB(30, 30, 30), M.Metal)
end

BUILDERS.SIGNAL_TRACKER = function(model)
	part(model, "Body", Vector3.new(0.8, 0.25, 1.1), CFrame.new(), Color3.fromRGB(56, 60, 64), M.Metal)
	local dial = cylinder(model, "Dial", 0.04, 0.6, CFrame.new(0, 0.14, -0.1) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(30, 34, 30), M.Glass)
	dial.Name = "Dial"
	local needle = part(model, "Needle", Vector3.new(0.04, 0.03, 0.26), CFrame.new(0, 0.17, -0.18), Color3.fromRGB(220, 90, 70), M.Neon)
	needle:SetAttribute("Needle", true)
end

BUILDERS.THERMAL_VIEWER = function(model)
	part(model, "Body", Vector3.new(0.9, 0.7, 0.8), CFrame.new(), Color3.fromRGB(38, 40, 44), M.Plastic)
	cylinder(model, "Lens", 0.35, 0.5, CFrame.new(0, 0.05, -0.55), Color3.fromRGB(20, 20, 24), M.Glass)
	part(model, "Screen", Vector3.new(0.6, 0.45, 0.04), CFrame.new(0, 0.05, 0.42), Color3.fromRGB(120, 60, 160), M.Neon)
	part(model, "Grip", Vector3.new(0.3, 0.6, 0.3), CFrame.new(0, -0.6, 0.1), Color3.fromRGB(20, 20, 20), M.Rubber)
end

BUILDERS.ANOMALY_LENS = function(model)
	cylinder(model, "Ring", 0.12, 1.1, CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, 0), Color3.fromRGB(150, 120, 70), M.Metal)
	local glass = cylinder(model, "Glass", 0.04, 0.95, CFrame.new(0, 0.2, 0), Color3.fromRGB(190, 210, 255), M.Glass)
	glass.Transparency = 0.5
	part(model, "Handle", Vector3.new(0.16, 0.9, 0.16), CFrame.new(0, -0.55, 0.05), Color3.fromRGB(60, 40, 30), M.Wood)
end

-- Builds the model for an equipment id (nil for unknown ids).
function EquipmentModels.build(id: string): Model?
	local item = Equipment.get(id)
	if not item then
		return nil
	end
	local builder = BUILDERS[id] or BUILDERS[item.kind]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = id
	builder(model, item)
	local first = model:FindFirstChildWhichIsA("BasePart")
	model.PrimaryPart = first
	return model
end

-- A 3D preview inside a ViewportFrame (shop cards), slowly turning if `spin`.
function EquipmentModels.preview(id: string, viewport: ViewportFrame): Model?
	local model = EquipmentModels.build(id)
	if not model then
		return nil
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(15)) * 1.15
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(distance * 0.55, distance * 0.35, -distance * 0.75), cf.Position)
	viewport.Ambient = Color3.fromRGB(150, 150, 150)
	viewport.LightColor = Color3.fromRGB(255, 244, 230)
	viewport.LightDirection = Vector3.new(-0.4, -1, 0.6)
	return model
end

return EquipmentModels
