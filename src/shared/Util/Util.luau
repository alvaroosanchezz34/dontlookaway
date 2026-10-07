--[[
	Util
	Small general purpose helpers shared by server and client.
]]

local Util = {}

-- Creates an instance, assigns properties and parents children.
-- Parent is always assigned last for performance.
function Util.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif key == "Attributes" then
				for name, attr in value do
					instance:SetAttribute(name, attr)
				end
			elseif key == "Tags" then
				for _, tag in value do
					instance:AddTag(tag)
				end
			else
				instance[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Util.deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[Util.deepCopy(k)] = Util.deepCopy(v)
	end
	return copy
end

-- Fills missing keys of `target` using `template`, recursively. Returns target.
function Util.reconcile(target, template)
	for key, value in template do
		if target[key] == nil then
			target[key] = Util.deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			-- only recurse into "shape" tables (templates with keys)
			local isArray = #value > 0
			if not isArray then
				Util.reconcile(target[key], value)
			end
		end
	end
	return target
end

function Util.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Util.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function Util.getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Util.getHead(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("Head") :: BasePart?
end

function Util.getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Frame-rate independent exponential smoothing factor.
function Util.damp(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function Util.isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function Util.isFiniteVector(v: any): boolean
	return typeof(v) == "Vector3" and Util.isFinite(v.X) and Util.isFinite(v.Y) and Util.isFinite(v.Z)
end

function Util.sanitizeString(value: any, maxLength: number): string?
	if type(value) ~= "string" then
		return nil
	end
	if #value > maxLength then
		return nil
	end
	if not utf8.len(value) then
		return nil
	end
	return value
end

function Util.count(t): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Util.keys(t)
	local list = {}
	for k in t do
		table.insert(list, k)
	end
	return list
end

function Util.shallowEqual(a, b): boolean
	for k, v in a do
		if b[k] ~= v then
			return false
		end
	end
	for k, v in b do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

-- Returns the model's bounding sphere (center, radius).
function Util.boundingSphere(target: Instance): (Vector3, number)
	if target:IsA("Model") then
		local cf, size = target:GetBoundingBox()
		return cf.Position, size.Magnitude * 0.5
	elseif target:IsA("BasePart") then
		return target.Position, target.Size.Magnitude * 0.5
	elseif target:IsA("Attachment") then
		return target.WorldPosition, 1.5
	end
	return Vector3.zero, 0
end

return Util
