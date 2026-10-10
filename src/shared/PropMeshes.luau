--[[
	PropMeshes
	The hero prop meshes made in Blender (tools/blender/build_assets.py):
	real geometry with baked PBR maps, replacing the part-built look of the
	props that matter most (reception desk, doors, door surrounds, lamps,
	radiators, chairs, tables, sofa, filing cabinets).

	Pipeline
	  assets/props/<Name>.obj            imported in Studio (Asset Manager, 3D
	                                      import) -> a Model asset that holds a
	                                      MeshPart; its id goes in
	                                      AssetIds.PropMeshes[Name].model
	  assets/props/<Name>/<Name>_*.png   uploaded as images; ids in the same
	                                      entry (color, normal, roughness,
	                                      metalness); tools/sync_assets.py
	                                      writes src/shared/PropSkins/<Name>
	                                      (a SurfaceAppearance, which scripts
	                                      may not author themselves)
	  Config/PropMeshMeta                 size and pivot offset of each mesh

	Builders never depend on a mesh. They tag their model:
	  MeshAsset   = "<Name>"             which mesh dresses it
	  MeshOrigin  = CFrame                the asset origin (Blender's origin)
	  MeshFollow  = "<part name>"         optional: the part the mesh moves with
	                                      (doors): it gets an Offset attribute
	and mark the parts the mesh replaces with MeshHide = true. Those parts stay
	(collision, queries, interaction, the geometry validator), only invisible.
	PropMeshes.dress(root) does the swap where a mesh is loaded; when it is not
	(not uploaded, Studio offline, tests) the part-built prop stays as it was.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(script.Parent.Config.AssetIds)
local Meta = require(script.Parent.Config.PropMeshMeta)

local PropMeshes = {}

local TEMPLATE_FOLDER = "PropMeshTemplates"

-- Names that have a model id.
function PropMeshes.configured(): { string }
	local list = {}
	for name, entry in AssetIds.PropMeshes or {} do
		if type(entry) == "table" and (entry.model or 0) > 0 and Meta[name] then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

local function folder(): Folder
	local f = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = TEMPLATE_FOLDER
		f.Parent = ReplicatedStorage
	end
	return f :: Folder
end

function PropMeshes.template(name: string): BasePart?
	local f = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	local t = f and f:FindFirstChild(name)
	return if t and t:IsA("BasePart") then t else nil
end

-- Registers a ready MeshPart as the template for `name` (load() and tests).
function PropMeshes.register(name: string, mesh: BasePart)
	local meta = Meta[name]
	mesh.Name = name
	if meta then
		mesh.Size = meta.size
	end
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CastShadow = true
	-- the baked PBR maps (Rojo writes the SurfaceAppearance; scripts can't)
	local skins = script.Parent:FindFirstChild("PropSkins")
	local skin = skins and skins:FindFirstChild(name)
	if skin and not mesh:FindFirstChildWhichIsA("SurfaceAppearance") then
		skin:Clone().Parent = mesh
	end
	local old = folder():FindFirstChild(name)
	if old then
		old:Destroy()
	end
	mesh.Parent = folder()
end

-- Server: loads every configured mesh (yields). Returns how many loaded.
function PropMeshes.load(): number
	if not RunService:IsServer() then
		return 0
	end
	local loaded = 0
	for _, name in PropMeshes.configured() do
		local id = AssetIds.PropMeshes[name].model
		local ok, mesh = pcall(function()
			local container = game:GetService("InsertService"):LoadAsset(id)
			local found = container:FindFirstChildWhichIsA("MeshPart", true)
			local copy = if found then found:Clone() else nil
			container:Destroy()
			if not copy then
				error("no MeshPart inside model " .. tostring(id))
			end
			for _, d in copy:GetChildren() do
				d:Destroy()
			end
			return copy
		end)
		if ok and mesh then
			PropMeshes.register(name, mesh)
			loaded += 1
		else
			warn("[PropMeshes] could not load " .. name .. ": " .. tostring(mesh))
		end
	end
	return loaded
end

-- Builder helper: tag `model` to be dressed by mesh `name` at `origin`; its
-- own parts named in `hide` become invisible when it is.
function PropMeshes.mark(model: Instance, name: string, origin: CFrame, hide: { [string]: boolean }, follow: string?)
	model:SetAttribute("MeshAsset", name)
	model:SetAttribute("MeshOrigin", origin)
	if follow then
		model:SetAttribute("MeshFollow", follow)
	end
	-- only the holder's own parts: nested props (a monitor on the desk) stay
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and hide[d.Name] then
			d:SetAttribute("MeshHide", true)
		end
	end
end

-- Builder helper for props made in several sizes from one mesh (picture
-- frames): the mesh is scaled to `size`.
function PropMeshes.markSized(model: Instance, name: string, origin: CFrame, hide: { [string]: boolean }, size: Vector3)
	PropMeshes.mark(model, name, origin, hide)
	model:SetAttribute("MeshSize", size)
end

-- Builder helper for straight runs (skirting, dado rail, cornice): the part is
-- its own holder, the mesh is stretched along X to `length` (its profile is
-- constant along X, so it never distorts).
function PropMeshes.markRun(part: BasePart, name: string, origin: CFrame, length: number)
	part:SetAttribute("MeshAsset", name)
	part:SetAttribute("MeshOrigin", origin)
	part:SetAttribute("MeshStretchX", length)
	part:SetAttribute("MeshHide", true)
end

local function dressOne(holder: Instance): boolean
	local name = holder:GetAttribute("MeshAsset")
	local origin = holder:GetAttribute("MeshOrigin")
	if type(name) ~= "string" or typeof(origin) ~= "CFrame" or holder:GetAttribute("MeshDressed") then
		return false
	end
	local tpl = PropMeshes.template(name)
	local meta = Meta[name]
	if not tpl or not meta then
		return false
	end
	local mesh = tpl:Clone()
	mesh.Name = "Mesh_" .. name
	local stretch = holder:GetAttribute("MeshStretchX")
	local sized = holder:GetAttribute("MeshSize")
	if typeof(sized) == "Vector3" then
		local k = sized / meta.size
		mesh.Size = sized
		mesh.CFrame = origin * CFrame.new(meta.offset * k)
	elseif type(stretch) == "number" and stretch > 0 then
		local k = stretch / meta.size.X
		mesh.Size = Vector3.new(stretch, meta.size.Y, meta.size.Z)
		mesh.CFrame = origin * CFrame.new(meta.offset.X * k, meta.offset.Y, meta.offset.Z)
	else
		mesh.CFrame = origin * CFrame.new(meta.offset)
	end
	local followName = holder:GetAttribute("MeshFollow")
	local follow = if type(followName) == "string" then holder:FindFirstChild(followName) else nil
	if follow and follow:IsA("BasePart") then
		-- moves with that part (DoorController / DoorService use Offset)
		mesh:SetAttribute("Offset", follow.CFrame:ToObjectSpace(mesh.CFrame))
	end
	local hideList = holder:GetDescendants()
	table.insert(hideList, holder)
	for _, d in hideList do
		if d:IsA("BasePart") and d:GetAttribute("MeshHide") then
			d:SetAttribute("MeshHiddenFrom", d.Transparency)
			d.Transparency = 1
			for _, g in d:GetChildren() do
				if g:IsA("Decal") or g:IsA("Texture") then
					g.Transparency = 1
				end
			end
		end
	end
	-- a run's holder is a part: the mesh goes next to it
	mesh.Parent = if holder:IsA("BasePart") then holder.Parent else holder
	holder:SetAttribute("MeshDressed", true)
	return true
end

-- Swaps in every loaded mesh under `root`. Safe to call again (already
-- dressed holders are skipped), e.g. when the meshes finish loading after the
-- map was built. Returns how many props were dressed.
function PropMeshes.dress(root: Instance): number
	local n = 0
	local holders = {}
	if root:GetAttribute("MeshAsset") then
		table.insert(holders, root)
	end
	for _, d in root:GetDescendants() do
		if d:GetAttribute("MeshAsset") then
			table.insert(holders, d)
		end
	end
	for _, h in holders do
		if dressOne(h) then
			n += 1
		end
	end
	return n
end

return PropMeshes
