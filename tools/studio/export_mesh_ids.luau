--[[
	Prints the mesh ids of every imported model in one line (no screenshots).

	1. In Studio (the group's place): Asset Manager -> Import 3D, select ALL the
	   .obj files of assets/observer and/or assets/props at once, and keep
	   "Insert into Workspace" ticked.
	2. View -> Command Bar: paste this file, Enter.
	3. Copy the line that starts with DLA_MESH and send it (or run
	   python3 tools/apply_ids.py "DLA_MESH ..." yourself).
	4. Delete the inserted models from the Workspace (the ids stay valid).

	It reads MeshPart.MeshId (the uploaded mesh) of every model in the
	Workspace named after an .obj file. It changes nothing.
]]
local KNOWN = {
	-- The Observer
	Head = true, Neck = true, UpperTorso = true, LowerTorso = true, UpperArm = true,
	LowerArm = true, Hand = true, UpperLeg = true, LowerLeg = true, Foot = true,
	-- hero props
	ReceptionDesk = true, DoorLeaf = true, DoorCasing = true, PendantLamp = true, WallSconce = true,
	Radiator = true, WoodChair = true, Table = true, Sofa = true, FilingCabinet = true,
	Baseboard = true, DadoRail = true, Cornice = true, OfficeDesk = true, Locker = true,
	MetalShelf = true, PictureFrame = true,
}
local found, count = {}, 0
for _, inst in workspace:GetDescendants() do
	if inst:IsA("MeshPart") then
		local id = tonumber(string.match(tostring(inst.MeshId), "(%d+)%D*$"))
		-- the model is named after the file; the part may be "ObserverHead"
		local names = { inst.Name, (string.gsub(inst.Name, "^Observer", "")) }
		local model = inst:FindFirstAncestorWhichIsA("Model")
		if model then
			table.insert(names, 1, model.Name)
		end
		for _, name in names do
			if id and KNOWN[name] and not found[name] then
				found[name] = id
				count += 1
				break
			end
		end
	end
end
local parts = {}
for name, id in found do
	table.insert(parts, name .. "=" .. string.format("%d", id))
end
table.sort(parts)
local missing = {}
for name in KNOWN do
	if not found[name] then
		table.insert(missing, name)
	end
end
table.sort(missing)
print(string.format("[DLA] %d meshes found; not in the Workspace: %s", count, if #missing > 0 then table.concat(missing, ", ") else "none"))
print("DLA_MESH " .. table.concat(parts, ","))
