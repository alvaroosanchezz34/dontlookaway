--[[
	MaterialLibrary
	The custom surface textures (assets/textures, ids in Config/AssetIds).

	Roblox does not let game scripts create MaterialVariants or set their texture
	maps (that needs Plugin capability), so the variants are written into the
	place by Rojo: tools/sync_assets.py generates src/materials/*.model.json and
	the MaterialService base-material overrides in default.project.json.

	  * Most textures REPLACE a built-in material everywhere (plaster, carpet,
	    ceramic tiles, concrete, wood planks, brick, marble, metal).
	  * Two are named variants the map applies to chosen surfaces:
	      DLA_Wallpaper     upper walls of reception, archive, gallery, quiet room
	      DLA_CeilingTile   suspended ceilings (offices, corridors, wet rooms)
	    A part whose MaterialVariant names a variant that does not exist just
	    renders its base material, so the map can always set them.
]]

local MaterialService = game:GetService("MaterialService")
local RunService = game:GetService("RunService")

local MaterialLibrary = {}

MaterialLibrary.Wallpaper = "DLA_Wallpaper"
MaterialLibrary.CeilingTile = "DLA_CeilingTile"

-- How many custom textures are present in this place.
function MaterialLibrary.count(): number
	local n = 0
	for _, v in MaterialService:GetChildren() do
		if v:IsA("MaterialVariant") and string.sub(v.Name, 1, 4) == "DLA_" then
			n += 1
		end
	end
	return n
end

-- Reports what is active (the variants themselves come with the place).
function MaterialLibrary.apply()
	if RunService:IsServer() then
		local n = MaterialLibrary.count()
		if n > 0 then
			print(string.format("[MaterialLibrary] %d custom textures active", n))
		end
	end
end

return MaterialLibrary
