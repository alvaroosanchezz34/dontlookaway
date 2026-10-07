--[[
	MaterialLibrary
	Turns the uploaded surface textures (Config/AssetIds) into MaterialVariants.

	  * Most textures REPLACE a built-in material everywhere (plaster, carpet,
	    ceramic tiles, concrete, wood planks, brick, marble, metal), so every room
	    style keeps working and only gains detail.
	  * Two are named variants the map applies to chosen surfaces:
	      DLA_Wallpaper     upper walls of reception, archive, gallery, quiet room
	      DLA_CeilingTile   suspended ceilings (offices, corridors, wet rooms)
	    A part whose MaterialVariant names a variant that does not exist just
	    renders its base material, so the map can always set them.

	The server creates the variants (they replicate inside MaterialService); both
	server and client apply the base-material overrides.
]]

local MaterialService = game:GetService("MaterialService")
local RunService = game:GetService("RunService")

local AssetIds = require(script.Parent.Config.AssetIds)

local MaterialLibrary = {}

MaterialLibrary.Wallpaper = "DLA_Wallpaper"
MaterialLibrary.CeilingTile = "DLA_CeilingTile"

-- key -> variant definition. `override` makes it replace the base material.
local DEFS = {
	{ key = "plaster_aged", name = "DLA_Plaster", base = Enum.Material.Plaster, studs = 10, override = true },
	{ key = "wallpaper_damask", name = MaterialLibrary.Wallpaper, base = Enum.Material.Plaster, studs = 8 },
	{ key = "carpet_worn", name = "DLA_Carpet", base = Enum.Material.Carpet, studs = 8, override = true },
	{ key = "tiles_worn", name = "DLA_Tiles", base = Enum.Material.CeramicTiles, studs = 5, override = true },
	{ key = "ceiling_tile", name = MaterialLibrary.CeilingTile, base = Enum.Material.Plaster, studs = 4 },
	{ key = "concrete_grimy", name = "DLA_Concrete", base = Enum.Material.Concrete, studs = 12, override = true },
	{ key = "wood_planks_worn", name = "DLA_WoodPlanks", base = Enum.Material.WoodPlanks, studs = 9, override = true },
	{ key = "brick_grimy", name = "DLA_Brick", base = Enum.Material.Brick, studs = 8, override = true },
	{ key = "marble_stained", name = "DLA_Marble", base = Enum.Material.Marble, studs = 12, override = true },
	{ key = "metal_worn", name = "DLA_Metal", base = Enum.Material.Metal, studs = 6, override = true },
}

local function ids(key: string)
	return AssetIds.Materials[key]
end

-- True when the colour map of `key` has been uploaded.
local function available(key: string): boolean
	local entry = ids(key)
	return entry ~= nil and AssetIds.url(entry.color) ~= nil
end

local function createVariants()
	for _, def in DEFS do
		if available(def.key) and not MaterialService:FindFirstChild(def.name) then
			local entry = ids(def.key)
			local variant = Instance.new("MaterialVariant")
			variant.Name = def.name
			variant.BaseMaterial = def.base
			variant.StudsPerTile = def.studs
			variant.ColorMap = AssetIds.url(entry.color) :: string
			variant.NormalMap = AssetIds.url(entry.normal) or ""
			variant.RoughnessMap = AssetIds.url(entry.roughness) or ""
			variant.MetalnessMap = AssetIds.url(entry.metalness) or ""
			variant.Parent = MaterialService
		end
	end
end

local function applyOverrides()
	for _, def in DEFS do
		if def.override and available(def.key) then
			pcall(function()
				MaterialService:SetBaseMaterialOverride(def.base, def.name)
			end)
		end
	end
end

-- How many textures are in use (for the admin panel / logs).
function MaterialLibrary.count(): number
	local n = 0
	for _, def in DEFS do
		if available(def.key) then
			n += 1
		end
	end
	return n
end

function MaterialLibrary.apply()
	local ok, err = pcall(function()
		if RunService:IsServer() then
			createVariants()
			if MaterialLibrary.count() > 0 then
				print(string.format("[MaterialLibrary] %d custom textures active", MaterialLibrary.count()))
			end
		end
		applyOverrides()
	end)
	if not ok then
		warn("[MaterialLibrary] " .. tostring(err))
	end
end

return MaterialLibrary
