--[[
	DetailLOD
	Distance culling for the building's micro-detail (Architecture: hinges,
	switches, outlets, grilles, sprinklers, conduit...). Each room's detail is a
	"DetailGroup" folder with its Center / Radius; rooms further than the
	quality tier's detailLod (VisualStandards.Quality) are hidden locally with
	LocalTransparencyModifier, so they cost nothing to draw. Nothing is
	destroyed or reparented: the server's map is untouched.

	No popping: a group hides beyond detailLod + 10 % and shows again inside
	detailLod - 10 % (walking along the line no longer flips it every check),
	and at most MAX_CHANGES groups change per check, nearest first, so a
	teleport or a turn of the quality setting spreads over a few frames.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VisualStandards = require(ReplicatedStorage.Shared.VisualStandards)
local Registry = require(script.Parent.Parent.Registry)

local DetailLOD = {}

-- parts and decals (a decal does not follow its carrier part's modifier)
type Group = { folder: Instance, parts: { Instance }, hidden: boolean }

local groups: { [Instance]: Group } = {}

local HYSTERESIS = 0.1
local MAX_CHANGES = 4
local INTERVAL = 0.2

local function setHidden(g: Group, hidden: boolean)
	g.hidden = hidden
	local value = if hidden then 1 else 0
	for _, p in g.parts do
		pcall(function()
			(p :: any).LocalTransparencyModifier = value
		end)
	end
end

local function register(folder: Instance)
	if groups[folder] then
		return
	end
	local g: Group = { folder = folder, parts = {}, hidden = false }
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(g.parts, d)
		end
	end
	-- streamed in later
	folder.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(g.parts, d)
			if g.hidden then
				pcall(function()
					(d :: any).LocalTransparencyModifier = 1
				end)
			end
		end
	end)
	groups[folder] = g
end

-- How many groups are hidden right now (debug / tests).
function DetailLOD:HiddenCount(): number
	local n = 0
	for _, g in groups do
		if g.hidden then
			n += 1
		end
	end
	return n
end

function DetailLOD:Update(camPos: Vector3)
	local access = Registry.AccessibilityController
	local tier = VisualStandards.tier(if access then access:Quality() else 2)
	local hideBeyond, showWithin = tier.detailLod * (1 + HYSTERESIS), tier.detailLod * (1 - HYSTERESIS)
	local pending: { { g: Group, d: number, hide: boolean } } = {}
	for folder, g in groups do
		if not folder.Parent then
			groups[folder] = nil
		else
			local center = folder:GetAttribute("Center")
			local radius = folder:GetAttribute("Radius")
			if typeof(center) == "Vector3" then
				local d = (center - camPos).Magnitude - (if type(radius) == "number" then radius else 0)
				if not g.hidden and d > hideBeyond then
					table.insert(pending, { g = g, d = d, hide = true })
				elseif g.hidden and d < showWithin then
					table.insert(pending, { g = g, d = d, hide = false })
				end
			end
		end
	end
	-- nearest first: what is about to be in front of you comes in first
	table.sort(pending, function(a, b)
		return a.d < b.d
	end)
	for i = 1, math.min(#pending, MAX_CHANGES) do
		setHidden(pending[i].g, pending[i].hide)
	end
end

function DetailLOD:Start()
	for _, f in CollectionService:GetTagged("DetailGroup") do
		register(f)
	end
	CollectionService:GetInstanceAddedSignal("DetailGroup"):Connect(function(f)
		task.defer(register, f)
	end)
	CollectionService:GetInstanceRemovedSignal("DetailGroup"):Connect(function(f)
		groups[f] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(INTERVAL)
			local camera = Workspace.CurrentCamera
			if camera then
				DetailLOD:Update(camera.CFrame.Position)
			end
		end
	end)
end

return DetailLOD
