--[[
	MapService
	Owns the world: builds the lobby once, (re)builds the building every round from
	the round seed, and exposes the current Map object (rooms, doors, spots, exits).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)
local MapBuilder = require(script.Parent.Parent.Map.MapBuilder)
local Lobby = require(script.Parent.Parent.Map.Lobby)
local MaterialLibrary = require(ReplicatedStorage.Shared.MaterialLibrary)
local PropMeshes = require(ReplicatedStorage.Shared.PropMeshes)

local MapService = {}

MapService.MapBuilt = Signal.new() -- (map)

local currentMap = nil
local lobby = nil
local building = false

function MapService:GetMap()
	return currentMap
end

function MapService:GetLobby()
	return lobby
end

function MapService:IsBuilding(): boolean
	return building
end

function MapService:Rebuild(seed: number)
	building = true
	if currentMap and currentMap.Root then
		currentMap.Root:Destroy()
	end
	currentMap = nil
	workspace:SetAttribute("MapReady", false)
	local ok, result = pcall(MapBuilder.build, seed, workspace)
	if not ok then
		warn("[MapService] build failed:", result)
		building = false
		return nil
	end
	currentMap = result
	-- custom textures (assets/textures) on every surface of the building
	MaterialLibrary.dress(currentMap.Root)
	-- hero prop meshes (assets/props) where they are loaded
	PropMeshes.dress(currentMap.Root)
	-- walls the anti-exploit clip check tests against
	local walls = {}
	for _, d in currentMap.Root.Structure:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Wall" or d.Name == "Sill" or d.Name == "WindowHead") then
			table.insert(walls, d)
		end
	end
	Registry.AntiExploitService:SetWallFilter(walls)
	-- doors never collide with the Observer
	for _, door in CollectionService:GetTagged("Door") do
		if door:IsDescendantOf(currentMap.Root) then
			for _, p in door:GetDescendants() do
				if p:IsA("BasePart") then
					p.CollisionGroup = "Doors"
				end
			end
			local panel = door.PrimaryPart
			if panel then
				local modifier = Instance.new("PathfindingModifier")
				modifier.PassThrough = true
				modifier.Parent = panel
			end
		end
	end
	Registry.AudioService:DecorateMap(currentMap)
	workspace:SetAttribute("MapSeed", seed)
	workspace:SetAttribute("MapReady", true)
	building = false
	MapService.MapBuilt:Fire(currentMap)
	return currentMap
end

function MapService:Start()
	MaterialLibrary.apply()
	-- the Blender prop meshes load in the background; the map built meanwhile
	-- is dressed as soon as they arrive, later maps when they are built
	task.spawn(function()
		local wanted = #PropMeshes.configured()
		if wanted == 0 then
			return
		end
		local n = PropMeshes.load()
		print(string.format("[MapService] prop meshes: %d of %d loaded", n, wanted))
		if currentMap and currentMap.Root and currentMap.Root.Parent then
			PropMeshes.dress(currentMap.Root)
		end
	end)
	lobby = Lobby.build(workspace)
	MaterialLibrary.dress(lobby.Root)
	workspace:SetAttribute("LobbyCamera", lobby.Camera)
	self:Rebuild(os.time() % 1000000)
end

return MapService
