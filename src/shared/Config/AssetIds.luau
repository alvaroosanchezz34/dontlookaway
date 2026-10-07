--[[
	AssetIds
	Ids of the custom textures and meshes after they are uploaded to Roblox (see
	assets/README.md). Every id starts at 0: while an id is 0 that asset is simply
	not used and the game falls back to Roblox's built-in materials and the
	part-built Observer, so the game always works with or without them.

	Paste the numbers only (the part after rbxassetid://).
]]

local AssetIds = {}

-- Surface textures (assets/textures/<name>/<name>_<map>.png)
AssetIds.Materials = {
	plaster_aged = { color = 0, normal = 0, roughness = 0 },
	wallpaper_damask = { color = 0, normal = 0, roughness = 0 },
	carpet_worn = { color = 0, normal = 0, roughness = 0 },
	tiles_worn = { color = 0, normal = 0, roughness = 0 },
	ceiling_tile = { color = 0, normal = 0, roughness = 0 },
	concrete_grimy = { color = 0, normal = 0, roughness = 0 },
	wood_planks_worn = { color = 0, normal = 0, roughness = 0 },
	brick_grimy = { color = 0, normal = 0, roughness = 0 },
	marble_stained = { color = 0, normal = 0, roughness = 0 },
	metal_worn = { color = 0, normal = 0, roughness = 0, metalness = 0 },
}

-- THE OBSERVER (assets/observer/*.obj and observer_skin_*.png). Mesh ids are the
-- MeshId of each imported MeshPart.
AssetIds.Observer = {
	meshes = {
		UpperTorso = 0,
		LowerTorso = 0,
		Neck = 0,
		Head = 0,
		FaceL = 0,
		FaceR = 0,
		UpperArm = 0,
		LowerArm = 0,
		Hand = 0,
		UpperLeg = 0,
		LowerLeg = 0,
		Foot = 0,
	},
	skin = { color = 0, normal = 0, roughness = 0 },
}

function AssetIds.url(id: number?): string?
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. string.format("%d", id)
	end
	return nil
end

return AssetIds
