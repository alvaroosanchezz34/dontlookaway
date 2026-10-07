--[[
	Build
	Low-level part construction helpers shared by the map builder and prop library.
	All geometry is anchored and created through these helpers so physical and
	visual defaults (no studs, sensible shadows, no accidental physics) stay uniform.
]]

local Build = {}

local DEFAULT_COLOR = Color3.fromRGB(120, 120, 120)

-- Creates an anchored part. `cf` is a world CFrame.
function Build.part(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?, extra: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or DEFAULT_COLOR
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in extra do
			if k == "Attributes" then
				for an, av in v do
					p:SetAttribute(an, av)
				end
			elseif k == "Tags" then
				for _, tag in v do
					p:AddTag(tag)
				end
			else
				(p :: any)[k] = v
			end
		end
	end
	p.Parent = parent
	return p
end

function Build.wedge(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?, extra: { [string]: any }?): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or DEFAULT_COLOR
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in extra do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- Cylinder whose axis runs along the CFrame's X axis.
function Build.cylinder(parent: Instance?, name: string, length: number, diameter: number, cf: CFrame, color: Color3?, material: Enum.Material?, extra: { [string]: any }?): Part
	local p = Build.part(parent, name, Vector3.new(length, diameter, diameter), cf, color, material, extra)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function Build.ball(parent: Instance?, name: string, diameter: number, cf: CFrame, color: Color3?, material: Enum.Material?, extra: { [string]: any }?): Part
	local p = Build.part(parent, name, Vector3.new(diameter, diameter, diameter), cf, color, material, extra)
	p.Shape = Enum.PartType.Ball
	return p
end

function Build.model(parent: Instance?, name: string, pivot: CFrame?): Model
	local m = Instance.new("Model")
	m.Name = name
	if pivot then
		m.WorldPivot = pivot
	end
	m.Parent = parent
	return m
end

-- Local-space helper: place parts relative to a base CFrame.
-- `base` faces its LookVector (front = -Z local).
function Build.at(base: CFrame, x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	local cf = base * CFrame.new(x, y, z)
	if rx or ry or rz then
		cf *= CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	end
	return cf
end

-- Small detail parts: no collision, no shadow, still queryable for interaction.
function Build.detail(parent, name, size, cf, color, material, extra)
	local p = Build.part(parent, name, size, cf, color, material, extra)
	p.CanCollide = false
	p.CastShadow = false
	return p
end

function Build.light(parent: Instance, className: string, props: { [string]: any }): Light
	local l = Instance.new(className) :: any
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function Build.surfaceGui(parent: Instance, face: Enum.NormalId, pixelsPerStud: number?): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pixelsPerStud or 40
	g.LightInfluence = 1
	g.Brightness = 1.2
	g.MaxDistance = 90
	g.ResetOnSpawn = false
	g.ClipsDescendants = true
	g.Parent = parent
	return g
end

function Build.frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

function Build.text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = Color3.fromRGB(230, 226, 214)
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

function Build.corner(parent: Instance, scale: number?, offset: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0, offset or 0)
	c.Parent = parent
	return c
end

function Build.gradient(parent: Instance, a: Color3, b: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- Marks geometry that starts hidden and can be revealed by RealityOps "Show".
function Build.hideForReveal(target: Instance)
	local function apply(inst: Instance)
		if inst:IsA("BasePart") then
			inst:SetAttribute("ShowTransparency", inst.Transparency)
			inst:SetAttribute("ShowCollide", inst.CanCollide)
			inst.Transparency = 1
			inst.CanCollide = false
			inst.CanQuery = false
		elseif inst:IsA("Light") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("SurfaceGui") then
			inst:SetAttribute("ShowEnabled", (inst :: any).Enabled)
			;(inst :: any).Enabled = false
		elseif inst:IsA("Decal") then
			inst:SetAttribute("ShowTransparency", inst.Transparency)
			inst.Transparency = 1
		end
	end
	apply(target)
	for _, d in target:GetDescendants() do
		apply(d)
	end
end

-- Darken / vary a colour slightly for natural wear.
function Build.vary(color: Color3, rng, amount: number?): Color3
	local a = amount or 0.06
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.clamp(s + rng:Number(-a, a) * 0.5, 0, 1), math.clamp(v + rng:Number(-a, a), 0, 1))
end

return Build
