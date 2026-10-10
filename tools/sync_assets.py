"""
Writes the asset instances that game scripts are not allowed to create at
runtime (MaterialVariant maps, SurfaceAppearance maps need Plugin capability),
so Rojo places them in the game instead:

    src/materials/<Variant>.model.json     -> MaterialService (one per texture)
    src/shared/ObserverSkin.model.json     -> ReplicatedStorage.Shared.ObserverSkin
    src/shared/PropSkins/<Prop>.model.json -> ReplicatedStorage.Shared.PropSkins (hero prop meshes)
    default.project.json                   -> MaterialService base-material overrides

Source of truth: src/shared/Config/AssetIds.luau. Run after changing any id:

    python3 tools/sync_assets.py
"""

import json
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
IDS = os.path.join(ROOT, "src", "shared", "Config", "AssetIds.luau")
MATERIALS = os.path.join(ROOT, "src", "materials")
SKIN = os.path.join(ROOT, "src", "shared", "ObserverSkin.model.json")
PROP_SKINS = os.path.join(ROOT, "src", "shared", "PropSkins")
PROJECT = os.path.join(ROOT, "default.project.json")

# texture key -> (variant name, base material, studs per tile, overrides the base material?)
DEFS = {
    "plaster_aged": ("DLA_Plaster", "Plaster", 10, True),
    "wallpaper_damask": ("DLA_Wallpaper", "Plaster", 4.5, False),
    "carpet_worn": ("DLA_Carpet", "Carpet", 8, True),
    "tiles_worn": ("DLA_Tiles", "CeramicTiles", 5, True),
    "ceiling_tile": ("DLA_CeilingTile", "Plaster", 4, False),
    "concrete_grimy": ("DLA_Concrete", "Concrete", 12, True),
    "wood_planks_worn": ("DLA_WoodPlanks", "WoodPlanks", 9, True),
    "brick_grimy": ("DLA_Brick", "Brick", 8, True),
    "marble_stained": ("DLA_Marble", "Marble", 20, True),
    "metal_worn": ("DLA_Metal", "Metal", 6, True),
    # Visual Overhaul V2
    "wood_aged": ("DLA_Wood", "Wood", 6, True),
    "fabric_worn": ("DLA_Fabric", "Fabric", 3, True),
    "metal_rusted": ("DLA_Rust", "CorrodedMetal", 5, True),
    "paint_peeling": ("DLA_PeelingPaint", "Plaster", 8, False),
    "concrete_wet": ("DLA_WetConcrete", "Concrete", 12, False),
    "metal_bare": ("DLA_Hardware", "Metal", 3, False),
    # Resident Evil quality pass
    "marble_tiles": ("DLA_MarbleTiles", "Marble", 6, False),  # 1.5-stud tiles (~55 cm at character scale)
    "wallpaper_aged": ("DLA_WallpaperAged", "Plaster", 8, False),
}

MAPS = {"color": "ColorMap", "normal": "NormalMap", "roughness": "RoughnessMap", "metalness": "MetalnessMap"}


def parse_entry(src, key):
    m = re.search(r"\b" + re.escape(key) + r"\s*=\s*\{([^}]*)\}", src)
    if not m:
        return {}
    return {k: int(v) for k, v in re.findall(r"(\w+)\s*=\s*(\d+)", m.group(1))}


def url(i):
    return "rbxassetid://%d" % i


def main():
    src = open(IDS, encoding="utf-8").read()
    os.makedirs(MATERIALS, exist_ok=True)
    for f in os.listdir(MATERIALS):
        if f.endswith(".model.json"):
            os.remove(os.path.join(MATERIALS, f))
    overrides = {}
    active = 0
    for key, (name, base, studs, override) in DEFS.items():
        ids = parse_entry(src, key)
        if ids.get("color", 0) <= 0:
            continue
        props = {"BaseMaterial": base, "StudsPerTile": studs}
        for field, prop in MAPS.items():
            if ids.get(field, 0) > 0:
                props[prop] = url(ids[field])
        with open(os.path.join(MATERIALS, name + ".model.json"), "w", encoding="utf-8") as fh:
            json.dump({"ClassName": "MaterialVariant", "Properties": props}, fh, indent=2)
            fh.write("\n")
        if override:
            overrides[base + "Name"] = name
        active += 1
    # keep the folder in git even when nothing is uploaded
    open(os.path.join(MATERIALS, ".gitkeep"), "w").close()

    skin_block = re.search(r"skin\s*=\s*\{([^}]*)\}", src)
    skin = {k: int(v) for k, v in re.findall(r"(\w+)\s*=\s*(\d+)", skin_block.group(1))} if skin_block else {}
    if skin.get("color", 0) > 0:
        props = {MAPS[k]: url(v) for k, v in skin.items() if k in MAPS and v > 0}
        with open(SKIN, "w", encoding="utf-8") as fh:
            json.dump({"ClassName": "SurfaceAppearance", "Properties": props}, fh, indent=2)
            fh.write("\n")
    elif os.path.exists(SKIN):
        os.remove(SKIN)

    # hero prop meshes: one SurfaceAppearance per mesh with its baked maps
    os.makedirs(PROP_SKINS, exist_ok=True)
    for f in os.listdir(PROP_SKINS):
        if f.endswith(".model.json"):
            os.remove(os.path.join(PROP_SKINS, f))
    open(os.path.join(PROP_SKINS, ".gitkeep"), "w").close()
    props_block = re.search(r"AssetIds\.PropMeshes\s*=\s*\{(.*?)\n\}", src, re.S)
    prop_skins = 0
    if props_block:
        for name, body in re.findall(r"\t(\w+)\s*=\s*\{([^}]*)\}", props_block.group(1)):
            ids = {k: int(v) for k, v in re.findall(r"(\w+)\s*=\s*(\d+)", body)}
            if ids.get("color", 0) > 0:
                props = {MAPS[k]: url(v) for k, v in ids.items() if k in MAPS and v > 0}
                with open(os.path.join(PROP_SKINS, name + ".model.json"), "w", encoding="utf-8") as fh:
                    json.dump({"ClassName": "SurfaceAppearance", "Properties": props}, fh, indent=2)
                    fh.write("\n")
                prop_skins += 1

    project = json.load(open(PROJECT, encoding="utf-8"))
    ms = project["tree"].setdefault("MaterialService", {"$className": "MaterialService"})
    ms["$path"] = "src/materials"
    props = {"Use2022Materials": True}
    props.update(overrides)
    ms["$properties"] = props
    with open(PROJECT, "w", encoding="utf-8") as fh:
        json.dump(project, fh, indent=2)
        fh.write("\n")
    print("materials: %d variants, %d overrides; observer skin: %s; prop skins: %d" % (active, len(overrides), "yes" if skin.get("color", 0) > 0 else "no", prop_skins))


if __name__ == "__main__":
    main()
