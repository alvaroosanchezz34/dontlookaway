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
	plaster_aged = { color = 107215450413033, normal = 84132935247783, roughness = 133763453720548 },
	wallpaper_damask = { color = 120863078953479, normal = 128306199589493, roughness = 108623304443042 },
	carpet_worn = { color = 81202392236431, normal = 124465885433566, roughness = 93225446930217 },
	tiles_worn = { color = 122065870248615, normal = 82385264798496, roughness = 111455651778102 },
	ceiling_tile = { color = 97904610194705, normal = 111698571339009, roughness = 121520549999929 },
	concrete_grimy = { color = 140127750101492, normal = 124397282736215, roughness = 92823511814189 },
	wood_planks_worn = { color = 106950480297885, normal = 101530558258022, roughness = 114210085469558 },
	brick_grimy = { color = 108837060381955, normal = 105803676660296, roughness = 95359754553547 },
	marble_stained = { color = 118681339278410, normal = 134150185593168, roughness = 105892051510999 },
	metal_worn = { color = 127374912032906, normal = 114374607971326, roughness = 71774178091112, metalness = 109152295762614 },
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
	skin = { color = 73026626049237, normal = 83633682521540, roughness = 128909048447810 },
}

-- Original synthesised audio (assets/audio/dla_<sheet>.ogg): three files, each
-- holding many sounds (see Config/AudioSheets). Upload them as audio.
AssetIds.Audio = {
	ambience = 110871317153737,
	horror = 0, -- regenerated (punchier jumpscare): upload the new dla_horror.ogg and set its id
	world = 124668448156045,
}

function AssetIds.url(id: number?): string?
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. string.format("%d", id)
	end
	return nil
end

return AssetIds
