--[[
	RealityOps
	The vocabulary of reality changes. An anomaly is expressed as a list of ops.
	The same op list is applied by the server (GLOBAL scope, replicated to everyone)
	or by a specific client (PLAYER / TEAM scope, local only). Every op returns a
	revert closure so reality can always be restored exactly.

	Op shapes:
		{ t = "Hide", target = Instance }
		{ t = "Show", target = Instance }                       -- reveals pre-built hidden geometry
		{ t = "Pivot", target = Instance, cframe = CFrame }
		{ t = "Prop", target = Instance, prop = string, value = any }
		{ t = "PropAll", target = Instance, class = string, prop = string, value = any }
		{ t = "Attr", target = Instance, name = string, value = any }
		{ t = "Clone", template = Instance, parent = Instance, cframe = CFrame?, name = string? }
]]

local RealityOps = {}

-- Properties an op is allowed to touch. Anything else is rejected, which keeps
-- client-side application safe even if an op table were malformed.
local ALLOWED_PROPS = {
	Color = true,
	Material = true,
	Transparency = true,
	Reflectance = true,
	CanCollide = true,
	CanQuery = true,
	Size = true,
	CFrame = true,
	Brightness = true,
	Range = true,
	Enabled = true,
	Angle = true,
	Text = true,
	TextColor3 = true,
	TextTransparency = true,
	Visible = true,
	BackgroundColor3 = true,
	BackgroundTransparency = true,
	Rate = true,
	Rotation = true,
	Position = true,
	Volume = true,
	PlaybackSpeed = true,
	Density = true,
	Offset = true,
	TintColor = true,
	Saturation = true,
	Contrast = true,
	Width0 = true,
	Width1 = true,
}

local function forEachVisual(target: Instance, fn: (Instance) -> ())
	fn(target)
	for _, d in target:GetDescendants() do
		fn(d)
	end
end

local function hide(target: Instance)
	local saved = {}
	forEachVisual(target, function(inst)
		if inst:IsA("BasePart") then
			saved[inst] = { Transparency = inst.Transparency, CanCollide = inst.CanCollide, CanQuery = inst.CanQuery }
			inst.Transparency = 1
			inst.CanCollide = false
			inst.CanQuery = false
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			saved[inst] = { Transparency = inst.Transparency }
			inst.Transparency = 1
		elseif inst:IsA("Light") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") or inst:IsA("Trail") then
			saved[inst] = { Enabled = (inst :: any).Enabled }
			;(inst :: any).Enabled = false
		end
	end)
	return function()
		for inst, props in saved do
			if inst.Parent ~= nil or inst == target then
				for k, v in props do
					(inst :: any)[k] = v
				end
			end
		end
	end
end

local function show(target: Instance)
	local saved = {}
	forEachVisual(target, function(inst)
		if inst:IsA("BasePart") then
			saved[inst] = { Transparency = inst.Transparency, CanCollide = inst.CanCollide, CanQuery = inst.CanQuery }
			local baseT = inst:GetAttribute("ShowTransparency")
			inst.Transparency = if type(baseT) == "number" then baseT else 0
			local baseC = inst:GetAttribute("ShowCollide")
			inst.CanCollide = if type(baseC) == "boolean" then baseC else true
			inst.CanQuery = true
		elseif inst:IsA("Light") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") then
			saved[inst] = { Enabled = (inst :: any).Enabled }
			local baseE = inst:GetAttribute("ShowEnabled")
			;(inst :: any).Enabled = if type(baseE) == "boolean" then baseE else true
		elseif inst:IsA("Decal") then
			saved[inst] = { Transparency = inst.Transparency }
			local baseT = inst:GetAttribute("ShowTransparency")
			inst.Transparency = if type(baseT) == "number" then baseT else 0
		end
	end)
	return function()
		for inst, props in saved do
			for k, v in props do
				(inst :: any)[k] = v
			end
		end
	end
end

local function pivot(target: Instance, cframe: CFrame)
	if target:IsA("Model") then
		local original = target:GetPivot()
		target:PivotTo(cframe)
		return function()
			if target.Parent then
				target:PivotTo(original)
			end
		end
	elseif target:IsA("BasePart") then
		local original = target.CFrame
		target.CFrame = cframe
		return function()
			target.CFrame = original
		end
	end
	return function() end
end

local function setProp(target: Instance, prop: string, value: any)
	if not ALLOWED_PROPS[prop] then
		warn("[RealityOps] property not allowed:", prop)
		return function() end
	end
	local ok, original = pcall(function()
		return (target :: any)[prop]
	end)
	if not ok then
		return function() end
	end
	local setOk = pcall(function()
		(target :: any)[prop] = value
	end)
	if not setOk then
		return function() end
	end
	return function()
		pcall(function()
			(target :: any)[prop] = original
		end)
	end
end

local function setPropAll(target: Instance, class: string, prop: string, value: any)
	local reverts = {}
	forEachVisual(target, function(inst)
		if inst:IsA(class) then
			table.insert(reverts, setProp(inst, prop, value))
		end
	end)
	return function()
		for i = #reverts, 1, -1 do
			reverts[i]()
		end
	end
end

local function setAttr(target: Instance, name: string, value: any)
	local original = target:GetAttribute(name)
	target:SetAttribute(name, value)
	return function()
		target:SetAttribute(name, original)
	end
end

local function cloneInto(template: Instance, parent: Instance, cframe: CFrame?, name: string?)
	local clone = template:Clone()
	if name then
		clone.Name = name
	end
	if cframe then
		if clone:IsA("Model") then
			clone:PivotTo(cframe)
		elseif clone:IsA("BasePart") then
			clone.CFrame = cframe
		end
	end
	clone.Parent = parent
	return function()
		clone:Destroy()
	end, clone
end

-- Applies a single op. Returns a revert function (never nil).
function RealityOps.apply(op): (() -> (), Instance?)
	if type(op) ~= "table" then
		return function() end
	end
	local t = op.t
	local target = op.target
	if t ~= "Clone" and (typeof(target) ~= "Instance") then
		return function() end
	end
	if t == "Hide" then
		return hide(target)
	elseif t == "Show" then
		return show(target)
	elseif t == "Pivot" and typeof(op.cframe) == "CFrame" then
		return pivot(target, op.cframe)
	elseif t == "Prop" and type(op.prop) == "string" then
		return setProp(target, op.prop, op.value)
	elseif t == "PropAll" and type(op.prop) == "string" and type(op.class) == "string" then
		return setPropAll(target, op.class, op.prop, op.value)
	elseif t == "Attr" and type(op.name) == "string" then
		return setAttr(target, op.name, op.value)
	elseif t == "Clone" and typeof(op.template) == "Instance" and typeof(op.parent) == "Instance" then
		local revert, clone = cloneInto(op.template, op.parent, op.cframe, op.name)
		return revert, clone
	end
	return function() end
end

-- Applies an op list, returning one revert closure for all of them (reverse order).
function RealityOps.applyAll(ops): (() -> (), { Instance })
	local reverts = {}
	local created = {}
	for _, op in ops do
		local ok, revert, clone = pcall(RealityOps.apply, op)
		if ok and revert then
			table.insert(reverts, revert)
			if clone then
				table.insert(created, clone)
			end
		elseif not ok then
			warn("[RealityOps] apply failed:", revert)
		end
	end
	return function()
		for i = #reverts, 1, -1 do
			local ok, err = pcall(reverts[i])
			if not ok then
				warn("[RealityOps] revert failed:", err)
			end
		end
	end, created
end

return RealityOps
