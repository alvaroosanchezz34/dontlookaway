--[[
	RbxCharacterSounds (replaces Roblox's default character sounds)
	Footsteps per floor material for every character, timed to walking speed,
	plus landings. Standing water silences nothing: it splashes. Mimics make no
	sound at all - one of the ways to tell them apart.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SoundFactory = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundFactory"))

local localPlayer = Players.LocalPlayer

local MATERIAL_SOUND = {
	[Enum.Material.Concrete] = "StepConcrete",
	[Enum.Material.Pavement] = "StepConcrete",
	[Enum.Material.Asphalt] = "StepConcrete",
	[Enum.Material.Brick] = "StepConcrete",
	[Enum.Material.Slate] = "StepConcrete",
	[Enum.Material.Ground] = "StepConcrete",
	[Enum.Material.CeramicTiles] = "StepTile",
	[Enum.Material.Marble] = "StepTile",
	[Enum.Material.Granite] = "StepTile",
	[Enum.Material.SmoothPlastic] = "StepTile",
	[Enum.Material.Plastic] = "StepTile",
	[Enum.Material.Wood] = "StepWood",
	[Enum.Material.WoodPlanks] = "StepWood",
	[Enum.Material.Metal] = "StepMetal",
	[Enum.Material.DiamondPlate] = "StepMetal",
	[Enum.Material.CorrodedMetal] = "StepMetal",
	[Enum.Material.Carpet] = "StepCarpet",
	[Enum.Material.Fabric] = "StepCarpet",
}

type Tracker = { humanoid: Humanoid, root: BasePart, nextStep: number, wasAir: boolean, model: Model }

local trackers: { [Model]: Tracker } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function play(key: string, parent: Instance, volume: number)
	local s = SoundFactory.create(key, parent, { volume = volume })
	if s then
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
end

local function track(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	trackers[character] = { humanoid = humanoid, root = root, nextStep = 0, wasAir = false, model = character }
end

local function stepKey(t: Tracker): string
	-- standing water (an anomaly) splashes
	params.FilterDescendantsInstances = { t.model }
	local hit = Workspace:Raycast(t.root.Position, Vector3.new(0, -5, 0), params)
	if hit and hit.Instance.Name == "Water" then
		return "StepWater"
	end
	return MATERIAL_SOUND[t.humanoid.FloorMaterial] or "StepConcrete"
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for model, t in trackers do
		if not model.Parent then
			trackers[model] = nil
		elseif not model:GetAttribute("Mimic") then
			local grounded = t.humanoid.FloorMaterial ~= Enum.Material.Air
			if grounded and t.wasAir then
				play("StepLand", t.root, 0.8)
			end
			t.wasAir = not grounded
			local v = t.root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			if grounded and speed > 1.5 and now >= t.nextStep then
				local interval = math.clamp(4.4 / speed, 0.26, 0.62)
				t.nextStep = now + interval
				local volume = if model == localPlayer.Character then 0.55 else 1
				volume *= math.clamp(speed / 12, 0.45, 1.25)
				play(stepKey(t), t.root, volume)
			end
		end
	end
end)

local function onPlayer(p: Player)
	if p.Character then
		task.spawn(track, p.Character)
	end
	p.CharacterAdded:Connect(function(c)
		track(c)
	end)
end

for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(p)
	if p.Character then
		trackers[p.Character] = nil
	end
end)
