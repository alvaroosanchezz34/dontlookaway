--[[
	DoorController
	Server sets door CFrames instantly; clients animate the swing locally from the
	"Open" attribute so doors move smoothly at any network quality.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local DoorController = {}

type Anim = { model: Model, from: CFrame, to: CFrame, start: number, duration: number, style: string }

local visual: { [Model]: CFrame } = {}
local anims: { [Model]: Anim } = {}

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

local function ease(t: number, style: string): number
	if style == "slam" then
		return t * t
	elseif style == "slow" then
		return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
	end
	-- doors swing out quickly, settle slowly
	return 1 - (1 - t) ^ 3
end

local function onChanged(model: Model)
	local open = model:GetAttribute("Open") == true
	local target = model:GetAttribute(if open then "OpenCFrame" else "ClosedCFrame")
	if typeof(target) ~= "CFrame" then
		return
	end
	local from = visual[model]
	if not from then
		local other = model:GetAttribute(if open then "ClosedCFrame" else "OpenCFrame")
		from = if typeof(other) == "CFrame" then other else target
	end
	local style = if model:GetAttribute("Slam") then "slam" elseif model:GetAttribute("Slow") then "slow" else "normal"
	local duration = if style == "slam" then 0.18 elseif style == "slow" then 2.4 else 0.6
	anims[model] = { model = model, from = from :: CFrame, to = target, start = os.clock(), duration = duration, style = style }
end

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local m = model :: Model
	local closed = m:GetAttribute("ClosedCFrame")
	local open = m:GetAttribute("Open") == true
	local target = m:GetAttribute(if open then "OpenCFrame" else "ClosedCFrame")
	visual[m] = if typeof(target) == "CFrame" then target elseif typeof(closed) == "CFrame" then closed else nil
	m:GetAttributeChangedSignal("Open"):Connect(function()
		onChanged(m)
	end)
end

-- A closed door eases a hand's width open on its own and settles back (only
-- on this screen: BlackoutFX's level 2). The server's door stays shut, so
-- nothing changes for anyone else; an Open change on the server wins.
function DoorController:Creak(model: Model, amount: number?): boolean
	if model:GetAttribute("Open") == true or anims[model] then
		return false
	end
	local closed = model:GetAttribute("ClosedCFrame")
	local open = model:GetAttribute("OpenCFrame")
	if typeof(closed) ~= "CFrame" or typeof(open) ~= "CFrame" then
		return false
	end
	local ajar = closed:Lerp(open, amount or 0.14)
	anims[model] = { model = model, from = closed, to = ajar, start = os.clock(), duration = 1.6, style = "slow" }
	task.delay(2.6, function()
		if model.Parent and model:GetAttribute("Open") ~= true and not anims[model] then
			anims[model] = { model = model, from = visual[model] or ajar, to = closed, start = os.clock(), duration = 1.2, style = "slow" }
		end
	end)
	return true
end

-- The closed door nearest `at` within `radius` studs, if any.
function DoorController:NearestClosed(at: Vector3, radius: number): Model?
	local best, bestD = nil, radius
	for model in visual do
		-- (a locked door never gives: it would tell the players it is not)
		if model.Parent and model:GetAttribute("Open") ~= true and not model:GetAttribute("Locked") and not anims[model] then
			local d = (model:GetPivot().Position - at).Magnitude
			if d < bestD then
				best, bestD = model, d
			end
		end
	end
	return best
end

function DoorController:Start()
	for _, tag in { "Door", "SetPieceDoor" } do
		for _, m in CollectionService:GetTagged(tag) do
			track(m)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(m)
			task.defer(track, m)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(m)
			visual[m :: Model] = nil
			anims[m :: Model] = nil
		end)
	end
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for model, a in anims do
			if not model.Parent then
				anims[model] = nil
			else
				local t = math.clamp((now - a.start) / a.duration, 0, 1)
				local cf = a.from:Lerp(a.to, ease(t, a.style))
				apply(model, cf)
				visual[model] = cf
				if t >= 1 then
					anims[model] = nil
				end
			end
		end
	end)
end

return DoorController
