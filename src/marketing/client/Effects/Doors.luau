--[[
	Doors
	Moves a door on this screen only. The building's doors carry ClosedCFrame /
	OpenCFrame attributes and every part an "Offset" from the door's primary
	part (see the game's DoorController); Marketing sets the same CFrames
	locally and, on cleanup, puts the door back where the game's own state says
	it is (open or closed), so a scene can never leave a door half open.

	In the virtual set (no building) `Doors.prop(cf)` builds a plain local door
	with the same attributes.
]]

local Runtime = require(script.Parent.Parent.Runtime)

local Doors = {}

local touched: { [Model]: boolean } = {}

local function apply(model: Model, cf: CFrame)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	primary.CFrame = cf
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= primary then
			local offset = d:GetAttribute("Offset")
			if typeof(offset) == "CFrame" then
				d.CFrame = cf * offset
			end
		end
	end
end

local function restore(model: Model)
	if not model.Parent then
		return
	end
	local open = model:GetAttribute("Open") == true
	local target = model:GetAttribute(if open then "OpenCFrame" else "ClosedCFrame")
	if typeof(target) == "CFrame" then
		apply(model, target)
	end
end

function Doors.reset()
	table.clear(touched)
end

-- Is this a door Marketing can move?
function Doors.valid(model: Instance?): boolean
	return model ~= nil and model:IsA("Model") and typeof(model:GetAttribute("ClosedCFrame")) == "CFrame" and typeof(model:GetAttribute("OpenCFrame")) == "CFrame" and model.PrimaryPart ~= nil
end

-- Pose the door: 0 = closed, 1 = fully open (any value in between, or beyond).
function Doors.set(model: Model, amount: number)
	if not Doors.valid(model) then
		return
	end
	if not touched[model] then
		touched[model] = true
		Runtime.onCleanup(function()
			touched[model] = nil
			restore(model)
		end)
	end
	local closed = model:GetAttribute("ClosedCFrame") :: CFrame
	local open = model:GetAttribute("OpenCFrame") :: CFrame
	apply(model, closed:Lerp(open, amount))
end

-- How open the door is right now (0..1), estimated from its primary part.
function Doors.amount(model: Model): number
	if not Doors.valid(model) then
		return 0
	end
	local closed = model:GetAttribute("ClosedCFrame") :: CFrame
	local open = model:GetAttribute("OpenCFrame") :: CFrame
	local current = (model.PrimaryPart :: BasePart).CFrame
	local total = (open.LookVector - closed.LookVector).Magnitude
	if total < 1e-3 then
		return 0
	end
	return math.clamp((current.LookVector - closed.LookVector).Magnitude / total, 0, 1)
end

-- A plain door (frame + leaf) for the virtual set. `floorCf` faces the camera.
function Doors.prop(floorCf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "MarketingDoor"
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: any): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Parent = m
		return p
	end
	local wood = Color3.fromRGB(92, 74, 58)
	local wall = Color3.fromRGB(150, 146, 136)
	-- wall around the opening so the gap reads as darkness behind
	part("WallL", Vector3.new(6, 12, 0.6), floorCf * CFrame.new(-5.2, 6, 0), wall, Enum.Material.Plaster)
	part("WallR", Vector3.new(6, 12, 0.6), floorCf * CFrame.new(5.2, 6, 0), wall, Enum.Material.Plaster)
	part("WallTop", Vector3.new(4.4, 2, 0.6), floorCf * CFrame.new(0, 11, 0), wall, Enum.Material.Plaster)
	part("Void", Vector3.new(4.4, 10, 0.2), floorCf * CFrame.new(0, 5, 4), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	-- the leaf hinges on its left edge
	local hinge = floorCf * CFrame.new(-2.1, 5, 0)
	local leaf = part("Leaf", Vector3.new(4.2, 10, 0.25), hinge * CFrame.new(2.1, 0, 0), wood, Enum.Material.Wood)
	local knob = part("Knob", Vector3.new(0.3, 0.3, 0.4), hinge * CFrame.new(3.7, -0.2, -0.2), Color3.fromRGB(160, 140, 90), Enum.Material.Metal)
	m.PrimaryPart = leaf
	knob:SetAttribute("Offset", leaf.CFrame:ToObjectSpace(knob.CFrame))
	local closed = leaf.CFrame
	-- swings away from the camera, 100 degrees around the hinge
	local open = hinge * CFrame.Angles(0, math.rad(-100), 0) * CFrame.new(2.1, 0, 0)
	m:SetAttribute("ClosedCFrame", closed)
	m:SetAttribute("OpenCFrame", open)
	m.Parent = Runtime.folder()
	return m
end

return Doors
