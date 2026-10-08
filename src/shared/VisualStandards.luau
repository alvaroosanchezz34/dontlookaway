--[[
	VisualStandards
	One place for the building's look, so every builder (map, architecture,
	props, lighting) uses the same surfaces, light profiles and quality tiers.

	Surfaces
	  A surface = built-in material + base colour + optional MaterialVariant.
	  Variants are the custom PBR textures (assets/textures, MaterialLibrary).
	  A part that names a variant the place does not have renders its base
	  material, so every surface works before and after the textures are
	  uploaded (Config/AssetIds).

	Fixture light profiles
	  Real fittings throw light in a shape: a fluorescent troffer and a pendant
	  shade light the floor under them, not the ceiling. Each profile has
	    main   the motivated light (SurfaceLight/SpotLight pointing down, or the
	           bare bulb's PointLight). It carries the fixture's shadows.
	    fill   the PointLight called "Light" (bounce on the ceiling and walls).
	  `ratio` is each light's share of the fixture brightness. On low quality
	  only the fill is kept and it takes `solo` of the brightness instead.

	Quality tiers (AccessibilityController:Quality(): 1 low, 2 medium, 3 high)
	  lightLod      fixture lights further than this are switched off locally
	  secondary     the main (shaped) light is used
	  detailLod     micro-detail (hardware, outlets, vents...) is hidden beyond
]]

local VisualStandards = {}

local M = Enum.Material

export type Surface = { material: EnumItem, color: Color3, variant: string?, reflectance: number? }

VisualStandards.Surfaces = {
	plaster = { material = M.Plaster, color = Color3.fromRGB(126, 120, 106) },
	oldPaint = { material = M.Plaster, color = Color3.fromRGB(118, 114, 100), variant = "DLA_PeelingPaint" },
	wallpaper = { material = M.Plaster, color = Color3.fromRGB(122, 112, 96), variant = "DLA_Wallpaper" },
	concrete = { material = M.Concrete, color = Color3.fromRGB(78, 80, 78) },
	wetConcrete = { material = M.Concrete, color = Color3.fromRGB(66, 68, 66), variant = "DLA_WetConcrete", reflectance = 0.02 },
	agedWood = { material = M.Wood, color = Color3.fromRGB(72, 54, 40) },
	varnishedWood = { material = M.Wood, color = Color3.fromRGB(86, 60, 40), reflectance = 0.03 },
	paintedMetal = { material = M.Metal, color = Color3.fromRGB(92, 96, 94) },
	rustedMetal = { material = M.CorrodedMetal, color = Color3.fromRGB(104, 76, 60) },
	hardware = { material = M.Metal, color = Color3.fromRGB(150, 148, 142), variant = "DLA_Hardware", reflectance = 0.08 },
	brass = { material = M.Metal, color = Color3.fromRGB(150, 122, 72), variant = "DLA_Hardware", reflectance = 0.1 },
	ceramic = { material = M.CeramicTiles, color = Color3.fromRGB(150, 160, 156) },
	porcelain = { material = M.SmoothPlastic, color = Color3.fromRGB(206, 206, 198), reflectance = 0.05 },
	glass = { material = M.Glass, color = Color3.fromRGB(150, 164, 166), reflectance = 0.12 },
	grime = { material = M.SmoothPlastic, color = Color3.fromRGB(28, 26, 22) },
	paper = { material = M.SmoothPlastic, color = Color3.fromRGB(196, 190, 172) },
	fabric = { material = M.Fabric, color = Color3.fromRGB(64, 62, 60) },
	plastic = { material = M.SmoothPlastic, color = Color3.fromRGB(214, 210, 196) },
	rubber = { material = M.Rubber, color = Color3.fromRGB(22, 22, 24) },
}

-- Gives a part a standard surface (colour may be overridden, e.g. per-room tint).
function VisualStandards.apply(part: BasePart, name: string, color: Color3?)
	local s = VisualStandards.Surfaces[name]
	if not s then
		return
	end
	part.Material = s.material
	part.Color = color or s.color
	if s.variant then
		part.MaterialVariant = s.variant
	end
	if s.reflectance then
		part.Reflectance = s.reflectance
	end
end

-- Material + colour pair for builders that take them as arguments.
function VisualStandards.get(name: string): (EnumItem, Color3, string?)
	local s = VisualStandards.Surfaces[name] or VisualStandards.Surfaces.plaster
	return s.material, s.color, s.variant
end

VisualStandards.Fixtures = {
	-- 2-tube troffer: a wide cone from the diffuser face onto the floor
	fluoro = {
		main = { class = "SurfaceLight", host = "Housing", face = Enum.NormalId.Bottom, angle = 115, range = 19, ratio = 1.15 },
		fill = { range = 14, ratio = 0.42, solo = 1 },
	},
	-- shaded pendant: a pool of warm light under the shade, a dim glow above
	pendant = {
		main = { class = "SpotLight", host = "Shade", face = Enum.NormalId.Bottom, angle = 100, range = 20, ratio = 1.5 },
		fill = { range = 11, ratio = 0.35, solo = 1 },
	},
	-- caged / bare bulbs light everything around them: the point light is the source
	cage = { fill = { range = 20, ratio = 1, solo = 1 } },
	bulb = { fill = { range = 18, ratio = 1, solo = 1 } },
}

VisualStandards.Quality = {
	[1] = { lightLod = 70, secondary = false, detailLod = 40 },
	[2] = { lightLod = 95, secondary = true, detailLod = 70 },
	[3] = { lightLod = 120, secondary = true, detailLod = 110 },
}

function VisualStandards.tier(level: number?)
	return VisualStandards.Quality[level or 2] or VisualStandards.Quality[2]
end

-- Distances a surface-mounted detail keeps off the surface it sits on: further
-- than the z-fighting tolerance (tools/zfight.luau), close enough to read as fixed.
VisualStandards.Proud = 0.03

return VisualStandards
