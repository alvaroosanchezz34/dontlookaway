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
	  No visible surface is SmoothPlastic: MaterialService does not replace it
	  (default.project.json) and under the night sky's specular it reads as
	  glossy plastic. It is kept only for invisible parts (hit boxes, holders)
	  and where a SurfaceAppearance covers the whole part.

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
	  shadowLights  how many of the nearest lit lamps cast shadows (the rest
	                are cut to their room so they never light through a wall)
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
	porcelain = { material = M.Marble, color = Color3.fromRGB(206, 206, 198), reflectance = 0.05 },
	glass = { material = M.Glass, color = Color3.fromRGB(150, 164, 166), reflectance = 0.12 },
	grime = { material = M.Concrete, color = Color3.fromRGB(28, 26, 22) },
	paper = { material = M.Fabric, color = Color3.fromRGB(196, 190, 172) },
	fabric = { material = M.Fabric, color = Color3.fromRGB(64, 62, 60) },
	plastic = { material = M.Plastic, color = Color3.fromRGB(214, 210, 196) },
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

-- Each fixture lights a pool that fades out: a bright centre, a wide penumbra
-- and a gradual falloff to dark, with no visible cone edge. A cone edge is a
-- hard line wherever it lands, so the pool is shaped by the lights' range (a
-- smooth falloff) and never by the cone:
--   * the cone edge of a main light lands where its range has already faded
--     it to nothing (pendant), or up against the ceiling (troffer);
--   * the fill is a long, weak point light: it has no edge at all and carries
--     the penumbra onto the floor around the pool and the walls next to it.
-- The ceiling is ~13 studs up and fixtures are 16 apart: halfway between two
-- of them the floor gets 15-30% of the light under one, so the stretch between
-- pools stays dark without a cut.
VisualStandards.Fixtures = {
	-- 2-tube troffer: an open wash from the diffuser. At 150 degrees the cone
	-- edge sits against the ceiling, so floor and walls fade with the range
	fluoro = {
		main = { class = "SurfaceLight", host = "Housing", face = Enum.NormalId.Bottom, angle = 150, range = 16, ratio = 1 },
		fill = { range = 18, ratio = 0.25, solo = 1 },
	},
	-- enamel pendant: a warm core under the bell (the bell's local -X face
	-- points down). The bell hangs 9.5 studs up: a 62 degree cone stays off the
	-- walls and its edge reaches the floor at the end of the 12 stud range. The
	-- fill is the glow under the shade: floor penumbra, walls and ceiling
	pendant = {
		main = { class = "SpotLight", host = "Shade", face = Enum.NormalId.Left, angle = 62, range = 12, ratio = 1.8 },
		fill = { range = 15, ratio = 0.28, solo = 1 },
	},
	-- caged / bare bulbs light everything around them: the point light is the source
	cage = { fill = { range = 12, ratio = 1, solo = 1 } },
	bulb = { fill = { range = 11, ratio = 1, solo = 1 } },
	-- wall sconce: a soft warm glow on the wall around it (no shadows: cheap)
	sconce = { fill = { range = 8, ratio = 1, solo = 1 } },
}

-- Moonlight through the boarded windows. It has no shadows on most windows, so
-- it passes through walls: kept faint so rooms without a fixture stay dark.
VisualStandards.Moonlight = {
	shaft = { brightness = 0.7, range = 30, angle = 30 },
	wash = { brightness = 0.2, range = 18, angle = 50 },
}

-- The main menu (MenuLook, client only): a dim grey light with a source you
-- can see (bare bulbs in the shots), the cold, nearly colourless grade, and
-- a little more exposure than the building in play. Tenuous, never bright.
VisualStandards.MenuLook = {
	ambient = Color3.fromRGB(34, 34, 36),
	outdoorAmbient = Color3.fromRGB(36, 38, 42),
	exposure = 1.0,
	cc = { Brightness = 0.04, Contrast = 0.06, Saturation = -0.8, TintColor = Color3.fromRGB(236, 238, 244) },
}

VisualStandards.Quality = {
	[1] = { lightLod = 70, secondary = false, detailLod = 40, shadowLights = 2 },
	[2] = { lightLod = 95, secondary = true, detailLod = 70, shadowLights = 10 },
	[3] = { lightLod = 120, secondary = true, detailLod = 110, shadowLights = 14 },
}

function VisualStandards.tier(level: number?)
	return VisualStandards.Quality[level or 2] or VisualStandards.Quality[2]
end

-- Distances a surface-mounted detail keeps off the surface it sits on: further
-- than the z-fighting tolerance (tools/zfight.luau), close enough to read as fixed.
VisualStandards.Proud = 0.03

return VisualStandards
