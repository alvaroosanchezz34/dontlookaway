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

-- THE OBSERVER (assets/observer/*.obj and observer_skin_*.png).
-- `models`: the Model asset Studio creates when a .obj is imported (Asset Manager,
-- type "Modelo", named after the file). `meshes`: a raw mesh id, if preferred.
-- Either works; a mesh id wins when both are set.
AssetIds.Observer = {
	models = {
		UpperTorso = 133171989693937,
		LowerTorso = 129218204675278,
		Neck = 121327873576376,
		Head = 81693864937120,
		FaceL = 137474714940635,
		FaceR = 84783262679053,
		UpperArm = 114524026637038,
		LowerArm = 118352438172157,
		Hand = 105017445485151,
		UpperLeg = 107974134887547,
		LowerLeg = 84078826201154,
		Foot = 133906447313908,
	},
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
