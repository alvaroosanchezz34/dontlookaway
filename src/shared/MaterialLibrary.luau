--[[
	MaterialLibrary
	The custom surface textures (assets/textures, ids in Config/AssetIds).

	Roblox does not let game scripts create MaterialVariants or set their texture
	maps (that needs Plugin capability), so the variants are written into the
	place by Rojo: tools/sync_assets.py generates src/materials/*.model.json and
	the MaterialService base-material overrides in default.project.json.

	  * Most textures REPLACE a built-in material everywhere (plaster, carpet,
	    ceramic tiles, concrete, wood planks, brick, marble, metal).
	  * Named variants the map applies to chosen surfaces:
	      DLA_Wallpaper     upper walls of reception, archive, gallery, quiet room
	      DLA_CeilingTile   suspended ceilings (offices, corridors, wet rooms)
	      DLA_PeelingPaint  failing paint: basement, closets, industrial rooms
	      DLA_WetConcrete   damp slabs: basement corridor, boiler, cold storage
	      DLA_Hardware      bare steel / brass: hinges, handles, plates, rails
	      DLA_MarbleTiles   checkerboard marble floor: reception, vestibule
	      DLA_WallpaperAged large-repeat aged wallpaper: reception, archive
	  * Visual Overhaul V2 adds three replacements: aged wood (doors, trims,
	    furniture), worn fabric (upholstery, boards) and rust (pipes, valves).
	    A texture whose id is 0 (Config/AssetIds) is simply not used and its
	    parts keep Roblox's own material.
	    A part whose MaterialVariant names a variant that does not exist just
	    renders its base material, so the map can always set them.
]]

local MaterialService = game:GetService("MaterialService")
local RunService = game:GetService("RunService")

local MaterialLibrary = {}

MaterialLibrary.Wallpaper = "DLA_Wallpaper"
MaterialLibrary.CeilingTile = "DLA_CeilingTile"
MaterialLibrary.PeelingPaint = "DLA_PeelingPaint"
MaterialLibrary.WetConcrete = "DLA_WetConcrete"
MaterialLibrary.Hardware = "DLA_Hardware"
MaterialLibrary.MarbleTiles = "DLA_MarbleTiles"
MaterialLibrary.WallpaperAged = "DLA_WallpaperAged"

-- Built-in material (by name) -> custom variant that replaces it.
local REPLACES = {
	Plaster = "DLA_Plaster",
	Carpet = "DLA_Carpet",
	CeramicTiles = "DLA_Tiles",
	Concrete = "DLA_Concrete",
	WoodPlanks = "DLA_WoodPlanks",
	Brick = "DLA_Brick",
	Marble = "DLA_Marble",
	Metal = "DLA_Metal",
	Wood = "DLA_Wood",
	Fabric = "DLA_Fabric",
	CorrodedMetal = "DLA_Rust",
}

--[[
	Gives every part under `root` the custom texture for its material (unless it
	already names a variant). The MaterialService base-material overrides cannot
	be set by scripts or reliably by sync, so the building and the lobby are
	dressed part by part when they are built. Returns how many parts changed.
]]
function MaterialLibrary.dress(root: Instance): number
	local available = {}
	for material, name in REPLACES do
		if MaterialService:FindFirstChild(name) then
			available[material] = name
		end
	end
	if next(available) == nil then
		return 0
	end
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.MaterialVariant == "" then
			local name = available[d.Material.Name]
			if name then
				d.MaterialVariant = name
				n += 1
			end
		end
	end
	return n
end

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
